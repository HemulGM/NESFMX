unit NES.Audio.Android.AudioTrack;

interface

uses
  NES.Audio.Backend;

type
  // All calls, including release, belong to the emulation thread. Open returns
  // the actual buffer size in mono frames; Write returns copied PCM16 samples.
  INesAudioTrackDevice = interface
    ['{CB633CA8-AD26-4B56-A4EB-794E4667C0A0}']
    function Open(SampleRate, MaxBufferSamples: Integer): Integer;
    function Write(const Samples: array of SmallInt; Count: Integer): Integer;
    function PlaybackHead: Cardinal;
    procedure Play;
    procedure Pause;
    procedure Flush;
    procedure Close;
  end;

const
  AUDIOTRACK_ERROR_DEAD_OBJECT = -6;

type
  TNesAndroidAudioBackend = class(TInterfacedObject, INesAudioBackend)
  private
    FTrack: INesAudioTrackDevice;
    FDeviceOpen, FPlaying: Boolean;
    FCapacity: Integer;
    FWrittenPosition, FClears: Cardinal;
    FSubmitted, FDropped: UInt64;
    FError: string;
    function OpenDevice: Boolean;
    procedure CloseDevice;
    procedure Fail(const MessageText: string);
    function ReadQueue(out Pending: Integer; out Played: Cardinal): Boolean;
  public
    constructor Create; overload;
    // Injectable device boundary keeps queue/recovery tests independent of JNI.
    constructor Create(const Track: INesAudioTrackDevice); overload;
    destructor Destroy; override;
  public { INesAudioBackend }
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
  end;

implementation

uses
  System.SysUtils, System.Math, Androidapi.JNI.Media, Androidapi.JNI.Os,
  Androidapi.JNIBridge;

type
  TAndroidAudioTrackDevice = class(TInterfacedObject, INesAudioTrackDevice)
  private
    FTrack: JAudioTrack;
    FSamples: TJavaArray<SmallInt>;
  public
    destructor Destroy; override;
    function Open(SampleRate, MaxBufferSamples: Integer): Integer;
    function Write(const Samples: array of SmallInt; Count: Integer): Integer;
    function PlaybackHead: Cardinal;
    procedure Play;
    procedure Pause;
    procedure Flush;
    procedure Close;
  end;

function TAndroidAudioTrackDevice.Open(SampleRate, MaxBufferSamples: Integer): Integer;
begin
  Close;
  if TJBuild_VERSION.JavaClass.SDK_INT < 23 then
    raise Exception.Create('AudioTrack requires Android 6.0 / API 23 or newer');
  var MinimumBytes := TJAudioTrack.JavaClass.getMinBufferSize(SampleRate,
    TJAudioFormat.JavaClass.CHANNEL_OUT_MONO, TJAudioFormat.JavaClass.ENCODING_PCM_16BIT);
  if MinimumBytes <= 0 then
    raise Exception.CreateFmt('AudioTrack cannot configure mono PCM16 at %d Hz (%d)', [SampleRate, MinimumBytes]);
  if MinimumBytes > MaxBufferSamples * SizeOf(SmallInt) then
    raise Exception.CreateFmt('AudioTrack requires %d buffer bytes; queue limit is %d', [MinimumBytes, MaxBufferSamples * SizeOf(SmallInt)]);

  var Attributes := TJAudioAttributes_Builder.JavaClass.init
    .setUsage(TJAudioAttributes.JavaClass.USAGE_GAME)
    .setContentType(TJAudioAttributes.JavaClass.CONTENT_TYPE_MUSIC).build;
  var Format := TJAudioFormat_Builder.JavaClass.init
    .setEncoding(TJAudioFormat.JavaClass.ENCODING_PCM_16BIT)
    .setSampleRate(SampleRate).setChannelMask(TJAudioFormat.JavaClass.CHANNEL_OUT_MONO).build;
  FTrack := TJAudioTrack_Builder.JavaClass.init.setAudioAttributes(Attributes)
    .setAudioFormat(Format).setTransferMode(TJAudioTrack.JavaClass.MODE_STREAM)
    .setBufferSizeInBytes(MaxBufferSamples * SizeOf(SmallInt)).build;
  if (FTrack = nil) or (FTrack.getState <> TJAudioTrack.JavaClass.STATE_INITIALIZED) then
    raise Exception.Create('AudioTrack initialization failed');
  FSamples := TJavaArray<SmallInt>.Create(AUDIO_BLOCK_SAMPLES);
  Result := FTrack.getBufferSizeInFrames;
end;

function TAndroidAudioTrackDevice.Write(const Samples: array of SmallInt; Count: Integer): Integer;
begin
  // Reuse one Java short[]. Sync releases/copies its JNI elements before Java
  // reads them; do not keep pinned array elements across the write call.
  Move(Samples[0], FSamples.Data^, Count * SizeOf(SmallInt));
  FSamples.Sync;
  Result := FTrack.write(FSamples, 0, Count, TJAudioTrack.JavaClass.WRITE_NON_BLOCKING);
end;

function TAndroidAudioTrackDevice.PlaybackHead: Cardinal;
begin
  // Java returns a signed int containing an unsigned wrapping frame counter.
  Result := UInt64(Int64(FTrack.getPlaybackHeadPosition) and $FFFFFFFF);
end;

procedure TAndroidAudioTrackDevice.Play;
begin
  FTrack.play;
end;

procedure TAndroidAudioTrackDevice.Pause;
begin
  FTrack.pause;
end;

procedure TAndroidAudioTrackDevice.Flush;
begin
  FTrack.flush;
end;

procedure TAndroidAudioTrackDevice.Close;
begin
  var Track := FTrack;
  FTrack := nil;
  FreeAndNil(FSamples);
  if Track <> nil then
  try
    if Track.getState = TJAudioTrack.JavaClass.STATE_INITIALIZED then
    try
      Track.pause;
    finally
      Track.flush;
    end;
  finally
    // Never stop/drain and wait for queued audio; always release, even if a
    // disconnected device throws during pause/flush.
    Track.release;
  end;
end;

destructor TAndroidAudioTrackDevice.Destroy;
begin
  try
    Close;
  except
    // The backend reports explicit Close failures; destruction cannot raise.
  end;
  inherited;
end;

constructor TNesAndroidAudioBackend.Create;
begin
  Create(TAndroidAudioTrackDevice.Create);
end;

constructor TNesAndroidAudioBackend.Create(const Track: INesAudioTrackDevice);
begin
  inherited Create;
  FTrack := Track;
  if FTrack = nil then
    FError := 'AudioTrack is available only on Android'
  else
    OpenDevice;
end;

function TNesAndroidAudioBackend.OpenDevice: Boolean;
begin
  Result := False;
  try
    FCapacity := FTrack.Open(NES_SAMPLE_RATE, AUDIO_BLOCK_COUNT * AUDIO_BLOCK_SAMPLES);
    // Android may increase the requested buffer to the route's minimum. Do not
    // silently deadlock priming a buffer larger than our allowed queue.
    if (FCapacity <= 0) or (FCapacity > AUDIO_BLOCK_COUNT * AUDIO_BLOCK_SAMPLES) then
      raise Exception.CreateFmt('AudioTrack buffer size %d exceeds the supported queue', [FCapacity]);
    FWrittenPosition := FTrack.PlaybackHead;
    FPlaying := False;
    FDeviceOpen := True;
    FError := '';
    Result := True;
  except
    on E: Exception do
      Fail(E.Message);
  end;
end;

procedure TNesAndroidAudioBackend.CloseDevice;
begin
  FDeviceOpen := False;
  FPlaying := False;
  if FTrack <> nil then
  try
    FTrack.Close;
  except
    on E: Exception do
      if FError = '' then
        FError := 'AudioTrack release: ' + E.Message;
  end;
end;

destructor TNesAndroidAudioBackend.Destroy;
begin
  CloseDevice;
  inherited;
end;

procedure TNesAndroidAudioBackend.Fail(const MessageText: string);
begin
  FError := 'AudioTrack: ' + MessageText;
  CloseDevice;
end;

function TNesAndroidAudioBackend.ReadQueue(out Pending: Integer; out Played: Cardinal): Boolean;
begin
  Result := False;
  Pending := 0;
  Played := 0;
  if not FDeviceOpen then
    Exit;
  try
    Played := FTrack.PlaybackHead;
    // Difference modulo 2^32 handles both Java's sign bit and the ~27-hour wrap.
    var Difference := (UInt64(FWrittenPosition) + UInt64($100000000) - Played) and $FFFFFFFF;
    if Difference > UInt64(FCapacity) then
      raise Exception.Create('Invalid playback head position');
    Pending := Integer(Difference);
    Result := True;
  except
    on E: Exception do
      Fail(E.Message);
  end;
end;

procedure TNesAndroidAudioBackend.Clear;
begin
  if not FDeviceOpen then
    Exit;
  try
    // flush only discards queued PCM while paused/stopped; it resets the head.
    FTrack.Pause;
    FTrack.Flush;
    FWrittenPosition := FTrack.PlaybackHead;
    FPlaying := False;
    FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
  except
    on E: Exception do
      Fail(E.Message);
  end;
end;

procedure TNesAndroidAudioBackend.Submit(const Samples: array of SmallInt; Count: Integer);
begin
  if (Count < 0) or (Count > Length(Samples)) or (Count > AUDIO_BLOCK_SAMPLES) then
    raise EArgumentOutOfRangeException.Create('Invalid audio sample count');
  if Count = 0 then
    Exit;
  var Pending: Integer;
  var Played: Cardinal;
  if not ReadQueue(Pending, Played) then
  begin
    Inc(FDropped, Count);
    Exit;
  end;
  var ToWrite := Min(Count, FCapacity - Pending);
  var Written: Integer := 0;
  try
    if ToWrite > 0 then
    begin
      Written := FTrack.Write(Samples, ToWrite);
      if Written = AUDIOTRACK_ERROR_DEAD_OBJECT then
      begin
        // Audio service/device loss: recreate and retry once, never spin.
        CloseDevice;
        if OpenDevice then
        begin
          FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
          ToWrite := Min(Count, FCapacity);
          Written := FTrack.Write(Samples, ToWrite);
        end;
      end;
      if (Written < 0) or (Written > ToWrite) then
      begin
        if FError = '' then
          Fail(Format('write failed (%d)', [Written]));
        Written := 0;
      end;
    end;
  except
    on E: Exception do
    begin
      Fail(E.Message);
      Written := 0;
    end;
  end;
  Inc(FSubmitted, Written);
  Inc(FDropped, Count - Written);
  FWrittenPosition := (UInt64(FWrittenPosition) + Cardinal(Written)) and $FFFFFFFF;
  if FDeviceOpen and not FPlaying and (Written > 0) then
  try
    FTrack.Play;
    FPlaying := True;
  except
    on E: Exception do
      Fail(E.Message);
  end;
end;

function TNesAndroidAudioBackend.QueueState: TAudioQueueState;
begin
  Result := Default(TAudioQueueState);
  var Pending: Integer;
  var Played: Cardinal;
  if ReadQueue(Pending, Played) then
  begin
    Result.QueuedBlocks := (Pending + AUDIO_BLOCK_SAMPLES - 1) div AUDIO_BLOCK_SAMPLES;
    Result.PlayedSamples := Played;
    Result.PositionKnown := True;
  end;
  Result.DeviceOpen := FDeviceOpen;
  Result.SubmittedSamples := FSubmitted;
  Result.DroppedSamples := FDropped;
  Result.Clears := FClears;
end;

function TNesAndroidAudioBackend.GetError: string;
begin
  Result := FError;
end;

end.

