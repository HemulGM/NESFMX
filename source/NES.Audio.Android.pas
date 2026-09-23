unit NES.Audio.Android;

interface

uses
  NES.Audio.Backend, NES.Audio.AudioTrack;

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
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
  end;

implementation

uses
  System.SysUtils, System.Math;

constructor TNesAndroidAudioBackend.Create;
begin
  Create(CreateAudioTrackDevice);
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
    on E: Exception do Fail(E.Message);
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
      if FError = '' then FError := 'AudioTrack release: ' + E.Message;
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
  if not FDeviceOpen then Exit;
  try
    Played := FTrack.PlaybackHead;
    // Difference modulo 2^32 handles both Java's sign bit and the ~27-hour wrap.
    var Difference := (UInt64(FWrittenPosition) + UInt64($100000000) - Played) and $FFFFFFFF;
    if Difference > UInt64(FCapacity) then
      raise Exception.Create('Invalid playback head position');
    Pending := Integer(Difference);
    Result := True;
  except
    on E: Exception do Fail(E.Message);
  end;
end;

procedure TNesAndroidAudioBackend.Clear;
begin
  if not FDeviceOpen then Exit;
  try
    // flush only discards queued PCM while paused/stopped; it resets the head.
    FTrack.Pause;
    FTrack.Flush;
    FWrittenPosition := FTrack.PlaybackHead;
    FPlaying := False;
    FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
  except
    on E: Exception do Fail(E.Message);
  end;
end;

procedure TNesAndroidAudioBackend.Submit(const Samples: array of SmallInt; Count: Integer);
var
  Pending, ToWrite, Written: Integer;
  Played: Cardinal;
begin
  if (Count < 0) or (Count > Length(Samples)) or (Count > AUDIO_BLOCK_SAMPLES) then
    raise EArgumentOutOfRangeException.Create('Invalid audio sample count');
  if Count = 0 then Exit;
  if not ReadQueue(Pending, Played) then
  begin
    Inc(FDropped, Count);
    Exit;
  end;
  ToWrite := Min(Count, FCapacity - Pending);
  Written := 0;
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
        if FError = '' then Fail(Format('write failed (%d)', [Written]));
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
    on E: Exception do Fail(E.Message);
  end;
end;

function TNesAndroidAudioBackend.QueueState: TAudioQueueState;
var
  Pending: Integer;
  Played: Cardinal;
begin
  Result := Default(TAudioQueueState);
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
