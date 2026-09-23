unit NES.Audio;

interface

uses
  NES.Audio.Backend;

const
  // Preserve the public names used by emulation and diagnostic clients.
  NES_SAMPLE_RATE = NES.Audio.Backend.NES_SAMPLE_RATE;
  AUDIO_BLOCK_SAMPLES = NES.Audio.Backend.AUDIO_BLOCK_SAMPLES;
  AUDIO_BLOCK_COUNT = NES.Audio.Backend.AUDIO_BLOCK_COUNT;

type
  TAudioQueueState = NES.Audio.Backend.TAudioQueueState;

  TNesAudio = class
  private
    FBackend: INesAudioBackend;
    function GetError: string;
  public
    constructor Create; overload;
    // Keeps a reference to Backend; release all references on its owning thread.
    constructor Create(const Backend: INesAudioBackend); overload;
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    property Error: string read GetError;
  end;

implementation

uses
  System.SysUtils, NES.Audio.Factory;

constructor TNesAudio.Create;
begin
  Create(CreatePlatformAudioBackend);
end;

constructor TNesAudio.Create(const Backend: INesAudioBackend);
begin
  inherited Create;
  if Backend = nil then
    raise EArgumentNilException.Create('Audio backend must not be nil');
  FBackend := Backend;
end;

procedure TNesAudio.Clear;
begin
  FBackend.Clear;
end;

procedure TNesAudio.Submit(const Samples: array of SmallInt; Count: Integer);
begin
  if (Count < 0) or (Count > AUDIO_BLOCK_SAMPLES) or (Count > Length(Samples)) then
    raise EArgumentOutOfRangeException.Create('Invalid audio sample count');
  if Count > 0 then
    FBackend.Submit(Samples, Count);
end;

function TNesAudio.QueueState: TAudioQueueState;
begin
  Result := FBackend.QueueState;
end;

function TNesAudio.GetError: string;
begin
  Result := FBackend.Error;
end;

end.
