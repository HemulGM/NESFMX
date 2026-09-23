unit NES.Audio.Windows;

interface

uses
  System.SysUtils, Winapi.Windows, Winapi.MMSystem, NES.Audio.Backend;

type
  TNesWindowsAudioBackend = class(TInterfacedObject, INesAudioBackend)
  private
    FDevice: HWAVEOUT;
    FHeaders: array[0..AUDIO_BLOCK_COUNT - 1] of TWaveHdr;
    FBuffers: array[0..AUDIO_BLOCK_COUNT - 1, 0..AUDIO_BLOCK_SAMPLES - 1] of SmallInt;
    FPrepared: Integer;
    FError: string;
    FSubmittedSamples, FDroppedSamples: UInt64;
    FClears: Cardinal;
    procedure Close;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
  end;

implementation

function TNesWindowsAudioBackend.GetError: string;
begin
  Result := FError;
end;

constructor TNesWindowsAudioBackend.Create;
begin
  var Format: TWaveFormatEx;
  var ErrorText: array[0..255] of Char;
  inherited Create;
  FillChar(Format, SizeOf(Format), 0);
  Format.wFormatTag := WAVE_FORMAT_PCM;
  Format.nChannels := 1;
  Format.nSamplesPerSec := NES_SAMPLE_RATE;
  Format.wBitsPerSample := 16;
  Format.nBlockAlign := 2;
  Format.nAvgBytesPerSec := NES_SAMPLE_RATE * 2;
  var Code: MMRESULT := waveOutOpen(@FDevice, WAVE_MAPPER, @Format, 0, 0, CALLBACK_NULL);
  if Code = MMSYSERR_NOERROR then
    for var i := 0 to AUDIO_BLOCK_COUNT - 1 do
    begin
      FHeaders[i].lpData := PAnsiChar(@FBuffers[i, 0]);
      FHeaders[i].dwBufferLength := SizeOf(FBuffers[i]);
      Code := waveOutPrepareHeader(FDevice, @FHeaders[i], SizeOf(TWaveHdr));
      if Code <> MMSYSERR_NOERROR then
        Break;
      Inc(FPrepared);
    end;
  if Code <> MMSYSERR_NOERROR then
  begin
    waveOutGetErrorText(Code, ErrorText, Length(ErrorText));
    FError := string(ErrorText);
    Close;
  end;
end;

destructor TNesWindowsAudioBackend.Destroy;
begin
  Close;
  inherited;
end;

procedure TNesWindowsAudioBackend.Clear;
begin
  if FDevice <> 0 then
  begin
    waveOutReset(FDevice);
    FClears := (UInt64(FClears) + 1) and $FFFFFFFF;
  end;
end;

function TNesWindowsAudioBackend.QueueState: TAudioQueueState;
begin
  var Position: TMMTime;
  Result := Default(TAudioQueueState);
  Result.SubmittedSamples := FSubmittedSamples;
  Result.DroppedSamples := FDroppedSamples;
  Result.Clears := FClears;
  Result.DeviceOpen := FDevice <> 0;
  for var i := 0 to FPrepared - 1 do
    if (FHeaders[i].dwFlags and WHDR_INQUEUE) <> 0 then
      Inc(Result.QueuedBlocks);
  if FDevice = 0 then
    Exit;
  FillChar(Position, SizeOf(Position), 0);
  Position.wType := TIME_SAMPLES;
  if waveOutGetPosition(FDevice, @Position, SizeOf(Position)) = MMSYSERR_NOERROR then
    case Position.wType of
      TIME_SAMPLES:
        begin
          Result.PlayedSamples := Position.sample;
          Result.PositionKnown := True;
        end;
      TIME_BYTES:
        begin
          Result.PlayedSamples := Position.cb div 2;
          Result.PositionKnown := True;
        end;
    end;
end;

procedure TNesWindowsAudioBackend.Close;
begin
  if FDevice = 0 then
    Exit;
  Clear;
  for var i := 0 to FPrepared - 1 do
    waveOutUnprepareHeader(FDevice, @FHeaders[i], SizeOf(TWaveHdr));
  FPrepared := 0;
  waveOutClose(FDevice);
  FDevice := 0;
end;

procedure TNesWindowsAudioBackend.Submit(const Samples: array of SmallInt; Count: Integer);
begin
  if Count <= 0 then
    Exit;
  if (Count > AUDIO_BLOCK_SAMPLES) or (Count > Length(Samples)) then
    raise EArgumentOutOfRangeException.Create('Audio block is too large');
  if FDevice = 0 then
  begin
    Inc(FDroppedSamples, Count);
    Exit;
  end;
  for var i := 0 to FPrepared - 1 do
    if (FHeaders[i].dwFlags and WHDR_INQUEUE) = 0 then
    begin
      Move(Samples[0], FBuffers[i, 0], Count * SizeOf(SmallInt));
      FHeaders[i].dwBufferLength := Count * SizeOf(SmallInt);
      if waveOutWrite(FDevice, @FHeaders[i], SizeOf(TWaveHdr)) <> MMSYSERR_NOERROR then
      begin
        Inc(FDroppedSamples, Count);
        FError := 'Audio device stopped accepting samples';
        Close;
      end
      else
        Inc(FSubmittedSamples, Count);
      Exit;
    end;
  // Bound latency: discard new samples if all device buffers are still queued.
  Inc(FDroppedSamples, Count);
end;

end.

