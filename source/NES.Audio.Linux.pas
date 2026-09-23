unit NES.Audio.Linux;

interface

uses
  System.SysUtils, NES.Audio.Backend, NES.Audio.Alsa;

type
  TNesLinuxAudioBackend = class(TInterfacedObject, INesAudioBackend)
  private
    FApi: TAlsaApi;
    FModule: HMODULE;
    FDevice: Pointer;
    FBufferSize: NativeUInt;
    FSubmitted, FDropped, FEpochSubmitted: UInt64;
    FClears: Cardinal;
    FError: string;
    procedure OpenDevice(const DeviceName: UTF8String);
    procedure CloseDevice;
    procedure Fail(const Operation: string; Code: Integer);
    function Recover(Code: Integer): Boolean;
    function ReadQueue(out Queued, Delay: NativeInt): Boolean;
  public
    constructor Create(const DeviceName: UTF8String = 'default'); overload;
    // Native boundary injection for deterministic tests; caller owns Api's library.
    constructor Create(const Api: TAlsaApi; const DeviceName: UTF8String = 'default'); overload;
    destructor Destroy; override;
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
  end;

implementation

uses
  System.Math;

const
  MAX_QUEUED_SAMPLES = AUDIO_BLOCK_COUNT * AUDIO_BLOCK_SAMPLES;
  // snd_pcm_set_params takes microseconds, not frames.
  TARGET_LATENCY_US = ( Int64(MAX_QUEUED_SAMPLES) * 1000000 + NES_SAMPLE_RATE - 1) div NES_SAMPLE_RATE;

constructor TNesLinuxAudioBackend.Create(const DeviceName: UTF8String);
begin
  inherited Create;
  if LoadAlsa(FApi, FModule, FError) then
    OpenDevice(DeviceName);
end;

constructor TNesLinuxAudioBackend.Create(const Api: TAlsaApi; const DeviceName: UTF8String);
begin
  inherited Create;
  FApi := Api;
  if not FApi.Complete then
    FError := 'Incomplete ALSA function table'
  else
    OpenDevice(DeviceName);
end;

procedure TNesLinuxAudioBackend.OpenDevice(const DeviceName: UTF8String);
var
  Code: Integer;
  PeriodSize: NativeUInt;
begin
  Code := FApi.Open(FDevice, PAnsiChar(DeviceName), SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK);
  if Code < 0 then
  begin
    FDevice := nil;
    Fail('open ' + string(DeviceName), Code);
    Exit;
  end;
  Code := FApi.SetParams(FDevice, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
    1, NES_SAMPLE_RATE, 1, TARGET_LATENCY_US);
  if Code < 0 then
  begin
    Fail('configure PCM', Code);
    Exit;
  end;
  Code := FApi.GetParams(FDevice, FBufferSize, PeriodSize);
  if Code < 0 then
    Fail('read buffer size', Code)
  else if (FBufferSize = 0) or (FBufferSize > NativeUInt(High(NativeInt))) then
  begin
    FError := 'ALSA returned an invalid PCM buffer size';
    CloseDevice;
  end;
end;

destructor TNesLinuxAudioBackend.Destroy;
begin
  CloseDevice;
{$IF Defined(LINUX) and not Defined(ANDROID)}
  if FModule <> 0 then
    FreeLibrary(FModule);
{$ENDIF}
  inherited;
end;

procedure TNesLinuxAudioBackend.CloseDevice;
begin
  if FDevice = nil then
    Exit;
  // Never drain: shutdown/reset must not wait for queued sound to play.
  FApi.Drop(FDevice);
  FApi.Close(FDevice);
  FDevice := nil;
end;

procedure TNesLinuxAudioBackend.Fail(const Operation: string; Code: Integer);
begin
  FError := 'ALSA ' + Operation + ': ' + string(UTF8String(FApi.StrError(Code)));
  CloseDevice;
end;

function TNesLinuxAudioBackend.Recover(Code: Integer): Boolean;
begin
  Result := False;
  if (Code = -ALSA_EAGAIN) or (Code = -ALSA_EINTR) then
    Exit;
  if (Code = -ALSA_EPIPE) or (Code = -ALSA_ESTRPIPE) then
  begin
    // Prepare discards an underrun/suspended queue. Unlike snd_pcm_recover's
    // resume loop, this does not sleep waiting for a suspended device.
    Code := FApi.Prepare(FDevice);
    if Code >= 0 then
    begin
      FEpochSubmitted := 0;
      FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
      Exit(True);
    end;
  end;
  Fail('stream', Code);
end;

procedure TNesLinuxAudioBackend.Clear;
var
  Code: Integer;
begin
  if FDevice = nil then
    Exit;
  Code := FApi.Drop(FDevice);
  if Code >= 0 then
    Code := FApi.Prepare(FDevice);
  if Code < 0 then
    Fail('clear', Code)
  else
  begin
    FEpochSubmitted := 0;
    FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
  end;
end;

function TNesLinuxAudioBackend.ReadQueue(out Queued, Delay: NativeInt): Boolean;
var
  Available: NativeInt;
  Code: Integer;

  function Query: Integer;
  begin
    if FApi.State(FDevice) = SND_PCM_STATE_PREPARED then
    begin
      // PulseAudio's ALSA plugin cannot report playback delay before Start.
      // In PREPARED nothing has played; query writable frames independently.
      Available := FApi.AvailUpdate(FDevice);
      Delay := NativeInt(FEpochSubmitted);
      if Available < 0 then
        Exit(Integer(Available));
      Result := 0;
    end
    else
      Result := FApi.AvailDelay(FDevice, Available, Delay);
  end;

begin
  Result := False;
  Queued := 0;
  Delay := 0;
  if FDevice = nil then
    Exit;
  Code := Query;
  if (Code < 0) and Recover(Code) then
    Code := Query;
  if Code < 0 then
  begin
    // The retry is bounded; another transient/underrun is handled next frame.
    if (FDevice <> nil) and (Code <> -ALSA_EAGAIN) and (Code <> -ALSA_EINTR) and
      (Code <> -ALSA_EPIPE) and (Code <> -ALSA_ESTRPIPE) then
      Fail('query queue', Code);
    Exit;
  end;
  Available := EnsureRange(Available, NativeInt(0), NativeInt(FBufferSize));
  Queued := NativeInt(FBufferSize) - Available;
  Result := True;
end;

procedure TNesLinuxAudioBackend.Submit(const Samples: array of SmallInt; Count: Integer);
var
  Queued, Delay, Written: NativeInt;
  ToWrite, Code: Integer;
begin
  if (Count < 0) or (Count > Length(Samples)) or (Count > AUDIO_BLOCK_SAMPLES) then
    raise EArgumentOutOfRangeException.Create('Invalid audio sample count');
  if Count = 0 then
    Exit;
  if not ReadQueue(Queued, Delay) then
  begin
    Inc(FDropped, Count);
    Exit;
  end;
  // Some plugins negotiate larger native buffers. Still bound our queued PCM
  // to 4096 samples. No software backlog, waits or spin on EAGAIN/short writes.
  ToWrite := Min(Count, Integer(Max(NativeInt(0),
        Min(NativeInt(FBufferSize), NativeInt(MAX_QUEUED_SAMPLES)) - Queued)));
  Written := 0;
  if ToWrite > 0 then
  begin
    Written := FApi.WriteInterleaved(FDevice, @Samples[0], ToWrite);
    if (Written < 0) and Recover(Integer(Written)) then
      Written := FApi.WriteInterleaved(FDevice, @Samples[0], ToWrite);
    if Written < 0 then
    begin
      if (FDevice <> nil) and (Written <> -ALSA_EAGAIN) and (Written <> -ALSA_EINTR) then
        Recover(Integer(Written));
      Written := 0;
    end;
  end;
  Inc(FSubmitted, Written);
  Inc(FEpochSubmitted, Written);
  Inc(FDropped, Count - Written);
  // Do not depend on a plugin's start threshold exceeding our queue limit.
  // Prime about 46 ms before explicitly starting a still-prepared stream.
  if (FDevice <> nil) and
    (FEpochSubmitted >= Min(FBufferSize, NativeUInt(2 * AUDIO_BLOCK_SAMPLES))) and
    (FApi.State(FDevice) = SND_PCM_STATE_PREPARED) then
  begin
    Code := FApi.Start(FDevice);
    if Code < 0 then
      Recover(Code);
  end;
end;

function TNesLinuxAudioBackend.QueueState: TAudioQueueState;
var
  Queued, Delay: NativeInt;
begin
  Result := Default(TAudioQueueState);
  if ReadQueue(Queued, Delay) then
  begin
    // ALSA exposes frames, not submitted block boundaries; report block equivalents.
    Result.QueuedBlocks := Integer((Queued + AUDIO_BLOCK_SAMPLES - 1) div AUDIO_BLOCK_SAMPLES);
    if (Delay >= 0) and (UInt64(Delay) <= FEpochSubmitted) then
    begin
      Result.PlayedSamples := (FEpochSubmitted - UInt64(Delay)) and $FFFFFFFF;
      Result.PositionKnown := True;
    end;
  end;
  Result.SubmittedSamples := FSubmitted;
  Result.DroppedSamples := FDropped;
  Result.Clears := FClears;
  Result.DeviceOpen := FDevice <> nil;
end;

function TNesLinuxAudioBackend.GetError: string;
begin
  Result := FError;
end;

end.

