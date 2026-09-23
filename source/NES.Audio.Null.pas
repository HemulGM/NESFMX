unit NES.Audio.Null;

interface

uses
  NES.Audio.Backend;

type
  // No native dependencies: used for unsupported platforms and headless runs.
  TNesNullAudioBackend = class(TInterfacedObject, INesAudioBackend)
  private
    FState: TAudioQueueState;
    FError: string;
  public
    constructor Create(const Reason: string = '');
    procedure Clear;
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
  end;

implementation

constructor TNesNullAudioBackend.Create(const Reason: string);
begin
  inherited Create;
  FError := Reason;
end;

procedure TNesNullAudioBackend.Clear;
begin
  FState.Clears := (UInt64(FState.Clears) + 1) and $FFFFFFFF;
end;

procedure TNesNullAudioBackend.Submit(const Samples: array of SmallInt; Count: Integer);
begin
  Inc(FState.DroppedSamples, Count);
end;

function TNesNullAudioBackend.QueueState: TAudioQueueState;
begin
  Result := FState;
end;

function TNesNullAudioBackend.GetError: string;
begin
  Result := FError;
end;

end.
