unit NES.Audio.Apple.AudioQueue;

interface

uses
  System.SysUtils, NES.Audio.Backend;

const
  // AudioQueueStart can return this while a new output device is priming.
  AUDIO_QUEUE_ERR_CANNOT_START_YET = -66665;

type
  // C ABI declarations shared by macOS and iOS AudioToolbox. Keep natural
  // alignment: pointer fields in AudioQueueBuffer are aligned on 64-bit Apple.
  TAppleStreamFormat = record
    SampleRate: Double;
    FormatID: UInt32;
    FormatFlags: UInt32;
    BytesPerPacket: UInt32;
    FramesPerPacket: UInt32;
    BytesPerFrame: UInt32;
    ChannelsPerFrame: UInt32;
    BitsPerChannel: UInt32;
    Reserved: UInt32;
  end;

  PAppleStreamFormat = ^TAppleStreamFormat;

  TAppleQueueBuffer = record
    Capacity: Cardinal;
    Data: Pointer;
    ByteSize: Cardinal;
    UserData: Pointer;
    PacketCapacity: Cardinal;
    PacketDescriptions: Pointer;
    PacketCount: Cardinal;
  end;

  PAppleQueueBuffer = ^TAppleQueueBuffer;

  TAppleOutputCallback = procedure(UserData, Queue: Pointer; Buffer: PAppleQueueBuffer); cdecl;

  TAppleAudioApi = record
    NewOutput: function(Format: PAppleStreamFormat; Callback: TAppleOutputCallback; UserData, RunLoop, RunLoopMode: Pointer; Flags: Cardinal; out Queue: Pointer): Integer; cdecl;
    AllocateBuffer: function(Queue: Pointer; Size: Cardinal; out Buffer: PAppleQueueBuffer): Integer; cdecl;
    EnqueueBuffer: function(Queue: Pointer; Buffer: PAppleQueueBuffer; PacketCount: Cardinal; Packets: Pointer): Integer; cdecl;
    Start: function(Queue, StartTime: Pointer): Integer; cdecl;
    Stop: function(Queue: Pointer; Immediate: Boolean): Integer; cdecl;
    Dispose: function(Queue: Pointer; Immediate: Boolean): Integer; cdecl;
    ActivateSession: function: Boolean;
    function Complete: Boolean;
  end;

  TNesAppleAudioBackend = class(TInterfacedObject, INesAudioBackend)
  private
    FApi: TAppleAudioApi;
    FQueue: Pointer;
    FBuffers: array[0..AUDIO_BLOCK_COUNT - 1] of PAppleQueueBuffer;
    FBusy: array[0..AUDIO_BLOCK_COUNT - 1] of Integer;
    // AudioQueueStart is asynchronous. This prevents a second Start call
    // before kAudioQueueProperty_IsRunning has caught up on macOS.
    FStartRequested: Integer;
    FSubmitted, FDropped: UInt64;
    FClears: Cardinal;
    FError: string;
    procedure OpenDevice;
    procedure CloseDevice;
    procedure Fail(const Operation: string; Code: Integer);
    function EnsureStarted: Boolean;
    class procedure BufferReturned(UserData, Queue: Pointer; Buffer: PAppleQueueBuffer); static; cdecl;
  public
    constructor Create; overload;
    // Host-side tests inject the native boundary without Apple frameworks.
    constructor Create(const Api: TAppleAudioApi); overload;
    destructor Destroy; override;
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
  end;

implementation

uses
  {$IFDEF IOS}
  iOSapi.AVFAudio,
  {$ENDIF}
  System.SyncObjs;

const
  AudioToolbox = '/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox';
  // Two emulation blocks provide about 33–46 ms of PCM before AudioQueueStart.
  // This avoids an immediate startup underrun on macOS audio devices.
  START_QUEUE_BLOCKS = 2;
  {$IFDEF UNDERSCOREIMPORTNAME}
  _PU = '_';
  {$ELSE}
  _PU = '';
  {$ENDIF}

function AudioQueueNewOutput(Format: PAppleStreamFormat; Callback: TAppleOutputCallback; UserData, RunLoop, RunLoopMode: Pointer; Flags: Cardinal; out Queue: Pointer): Integer; cdecl; external AudioToolbox name _PU + 'AudioQueueNewOutput';

function AudioQueueAllocateBuffer(Queue: Pointer; Size: Cardinal; out Buffer: PAppleQueueBuffer): Integer; cdecl; external AudioToolbox name _PU + 'AudioQueueAllocateBuffer';

function AudioQueueEnqueueBuffer(Queue: Pointer; Buffer: PAppleQueueBuffer; PacketCount: Cardinal; Packets: Pointer): Integer; cdecl; external AudioToolbox name _PU + 'AudioQueueEnqueueBuffer';

function AudioQueueStart(Queue, StartTime: Pointer): Integer; cdecl; external AudioToolbox name _PU + 'AudioQueueStart';

function AudioQueueStop(Queue: Pointer; Immediate: Boolean): Integer; cdecl; external AudioToolbox name _PU + 'AudioQueueStop';

function AudioQueueDispose(Queue: Pointer; Immediate: Boolean): Integer; cdecl; external AudioToolbox name _PU + 'AudioQueueDispose';

function ActivateAppleSession: Boolean;
begin
  {$IFDEF IOS}
  // Use the application's session/category (and respect the silent switch).
  // Activation is also retried when an interrupted queue is started again.
  Result := TAVAudioSession.OCClass.sharedInstance.setActive(True, nil);
  {$ELSE}
  Result := True;
  {$ENDIF}
end;

function TAppleAudioApi.Complete: Boolean;
begin
  Result :=
    Assigned(NewOutput) and
    Assigned(AllocateBuffer) and
    Assigned(EnqueueBuffer) and
    Assigned(Start) and
    Assigned(Stop) and
    Assigned(Dispose) and
    Assigned(ActivateSession);
end;

constructor TNesAppleAudioBackend.Create;
begin
  inherited Create;
  FApi.NewOutput := AudioQueueNewOutput;
  FApi.AllocateBuffer := AudioQueueAllocateBuffer;
  FApi.EnqueueBuffer := AudioQueueEnqueueBuffer;
  FApi.Start := AudioQueueStart;
  FApi.Stop := AudioQueueStop;
  FApi.Dispose := AudioQueueDispose;
  FApi.ActivateSession := ActivateAppleSession;
  OpenDevice;
end;

constructor TNesAppleAudioBackend.Create(const Api: TAppleAudioApi);
begin
  inherited Create;
  FApi := Api;
  if not FApi.Complete then
    FError := 'Incomplete Audio Queue function table'
  else
    OpenDevice;
end;

procedure TNesAppleAudioBackend.OpenDevice;
begin
  var Format := Default(TAppleStreamFormat);
  Format.SampleRate := NES_SAMPLE_RATE;
  Format.FormatID := $6C70636D; // 'lpcm'
  Format.FormatFlags := 4 or 8; // signed integer, packed, little endian
  Format.BytesPerPacket := SizeOf(SmallInt);
  Format.FramesPerPacket := 1;
  Format.BytesPerFrame := SizeOf(SmallInt);
  Format.ChannelsPerFrame := 1;
  Format.BitsPerChannel := 16;
  // A nil run loop delivers callbacks on Audio Queue's internal thread.
  var Code := FApi.NewOutput(@Format, BufferReturned, Self, nil, nil, 0, FQueue);
  if Code <> 0 then
  begin
    FQueue := nil;
    Fail('create', Code);
    Exit;
  end;
  for var i := 0 to High(FBuffers) do
  begin
    Code := FApi.AllocateBuffer(FQueue, AUDIO_BLOCK_SAMPLES * SizeOf(SmallInt), FBuffers[i]);
    if Code <> 0 then
    begin
      Fail('allocate buffer', Code);
      Exit;
    end;
  end;
end;

class procedure TNesAppleAudioBackend.BufferReturned(UserData, Queue: Pointer; Buffer: PAppleQueueBuffer);
begin
  var Backend := TNesAppleAudioBackend(UserData);
  // No locks, allocations or native calls on the callback thread. Buffer
  // return means reusable, not audibly played; do not invent a playback clock.
  for var i := 0 to High(Backend.FBuffers) do
    if Backend.FBuffers[i] = Buffer then
    begin
      TInterlocked.Exchange(Backend.FBusy[i], 0);
      // A completely drained queue needs a new start after a later Submit.
      // This is only a recovery path; continuous emulation retains the start.
      for var j := 0 to High(Backend.FBusy) do
        if TInterlocked.CompareExchange(Backend.FBusy[j], 0, 0) <> 0 then
          Exit;
      TInterlocked.Exchange(Backend.FStartRequested, 0);
      Exit;
    end;
end;

procedure TNesAppleAudioBackend.CloseDevice;
begin
  if FQueue = nil then
    Exit;
  // Synchronous disposal stops callbacks and frees all native buffers. Never
  // hold a callback lock here, and retain Self/buffer pointers until it returns.
  FApi.Dispose(FQueue, True);
  FQueue := nil;
  for var i := 0 to High(FBuffers) do
  begin
    FBuffers[i] := nil;
    FBusy[i] := 0;
  end;
end;

destructor TNesAppleAudioBackend.Destroy;
begin
  CloseDevice;
  inherited;
end;

procedure TNesAppleAudioBackend.Fail(const Operation: string; Code: Integer);
begin
  FError := Format('Audio Queue %s: OSStatus %d', [Operation, Code]);
  CloseDevice;
end;

function TNesAppleAudioBackend.EnsureStarted: Boolean;
begin
  Result := False;
  if TInterlocked.CompareExchange(FStartRequested, 0, 0) <> 0 then
    Exit(True);
  var QueuedBlocks := 0;
  for var i := 0 to High(FBusy) do
    Inc(QueuedBlocks, TInterlocked.CompareExchange(FBusy[i], 0, 0));
  if QueuedBlocks < START_QUEUE_BLOCKS then
    Exit;
  if TInterlocked.CompareExchange(FStartRequested, 1, 0) <> 0 then
    Exit(True);
  if not FApi.ActivateSession() then
  begin
    TInterlocked.Exchange(FStartRequested, 0);
    // An iOS interruption can temporarily deny activation. Clear queued
    // stale sound and try again on a subsequent Submit, without spinning.
    Clear;
    if FQueue <> nil then
      FError := 'Audio session activation unavailable';
    Exit;
  end;
  var Code := FApi.Start(FQueue, nil);
  if Code = AUDIO_QUEUE_ERR_CANNOT_START_YET then
  begin
    // Keep the PCM already queued. The next Submit retries once more data
    // is available instead of closing a healthy but not-yet-primed device.
    TInterlocked.Exchange(FStartRequested, 0);
    Exit;
  end;
  if Code <> 0 then
  begin
    TInterlocked.Exchange(FStartRequested, 0);
    Fail('start', Code);
    Exit;
  end;
  FError := '';
  Result := True;
end;

procedure TNesAppleAudioBackend.Clear;
begin
  if FQueue = nil then
    Exit;
  var Code := FApi.Stop(FQueue, True); // synchronous stop also resets the queue
  if Code <> 0 then
  begin
    Fail('stop', Code);
    Exit;
  end;
  for var i := 0 to High(FBusy) do
    TInterlocked.Exchange(FBusy[i], 0);
  TInterlocked.Exchange(FStartRequested, 0);
  FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
end;

procedure TNesAppleAudioBackend.Submit(const Samples: array of SmallInt; Count: Integer);
begin
  if (Count < 0) or (Count > Length(Samples)) or (Count > AUDIO_BLOCK_SAMPLES) then
    raise EArgumentOutOfRangeException.Create('Invalid audio sample count');
  if Count = 0 then
    Exit;
  if FQueue <> nil then
    for var i := 0 to High(FBuffers) do
      if TInterlocked.CompareExchange(FBusy[i], 1, 0) = 0 then
      begin
        Move(Samples[0], FBuffers[i].Data^, Count * SizeOf(SmallInt));
        FBuffers[i].ByteSize := Count * SizeOf(SmallInt);
        var Code := FApi.EnqueueBuffer(FQueue, FBuffers[i], 0, nil);
        if Code <> 0 then
        begin
          Inc(FDropped, Count);
          Fail('enqueue', Code);
          Exit;
        end;
        Inc(FSubmitted, Count);
        EnsureStarted;
        Exit;
      end;
  Inc(FDropped, Count);
  // A stopped/interrupted full queue must still get a chance to restart.
  if FQueue <> nil then
    EnsureStarted;
end;

function TNesAppleAudioBackend.QueueState: TAudioQueueState;
begin
  Result := Default(TAudioQueueState);
  Result.SubmittedSamples := FSubmitted;
  Result.DroppedSamples := FDropped;
  Result.Clears := FClears;
  Result.DeviceOpen := FQueue <> nil;
  for var i := 0 to High(FBusy) do
    Inc(Result.QueuedBlocks, TInterlocked.CompareExchange(FBusy[i], 0, 0));
end;

function TNesAppleAudioBackend.GetError: string;
begin
  Result := FError;
end;

end.

