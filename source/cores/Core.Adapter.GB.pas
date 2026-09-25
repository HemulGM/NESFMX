unit Core.Adapter.GB;

interface

uses
  System.IniFiles, Core.Emulation, GB.EmulationThread, GB.Joypad;

type
  TGBKeyMap = record
    A, B, Select, Start, Up, Down, Left, Right: UInt32;
  end;

  IGBEmulatorConfig = interface(IEmulatorConfig)
    ['{F92F710A-091C-4D32-9C97-369476030FB1}']
    function GetKeys: TGBKeyMap;
    procedure SetKeys(const Value: TGBKeyMap);
    property Keys: TGBKeyMap read GetKeys write SetKeys;
  end;

  TGBEmulatorConfig = class(TEmulatorConfigBase, IGBEmulatorConfig)
  private
    FKeys: TGBKeyMap;
  protected
    procedure LoadCoreSettings(Ini: TIniFile); override;
    procedure SaveCoreSettings(Ini: TIniFile); override;
  public
    constructor Create(const AFileName: string);
    function GetKeys: TGBKeyMap;
    procedure SetKeys(const Value: TGBKeyMap);
  end;

  TGBCoreAdapter = class(TInterfacedObject, IEmulationCore)
  private
    FThread: TGBEmulationThread;
    FFileName: string;
    FGamepadInput: TEmulatorInput;
    FConfig: IGBEmulatorConfig;
    FFrameNumber: UInt64;
    procedure CreateThread;
    procedure ApplyInput;
    function GetName: string;
    function GetSupportsSnapshots: Boolean;
    function GetUsesSuborKeyboard: Boolean;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure Pause;
    procedure Resume;
    procedure Reset;
    procedure ClearInput;
    procedure SetKeyState(Code: UInt32; Pressed: Boolean);
    procedure SetGamepadInput(const Input: TEmulatorInput);
    procedure SaveSnapshot(const Name: string);
    procedure LoadSnapshot(const Name: string);
    function TryGetFrame(out Frame: TEmulatorFrame): Boolean;
    function TakeError: string;
    function GetConfig: IEmulatorConfig;
  end;

implementation

uses
  System.SysUtils, System.UITypes, GB.GPU, GB.Palettes;

constructor TGBCoreAdapter.Create(const FileName: string);
begin
  inherited Create;
  FConfig := TGBEmulatorConfig.Create(EmulatorConfigFileName('gb'));
  FConfig.Load;
  FFileName := FileName;
  CreateThread;
end;

procedure TGBCoreAdapter.CreateThread;
begin
  FThread := TGBEmulationThread.Create(FFileName, FConfig.AudioEnabled);
  FThread.SoundVolume := FConfig.AudioVolume;
end;

destructor TGBCoreAdapter.Destroy;
begin
  Stop;
  FThread.Free;
  inherited;
end;

procedure TGBCoreAdapter.ApplyInput;
const
  ButtonKeys: array[TEmulatorButton] of TGBKey =
    (TGBKey.Up, TGBKey.Down, TGBKey.Left, TGBKey.Right,
    TGBKey.A, TGBKey.B, TGBKey.Select, TGBKey.Start);
begin
  for var Button := Low(TEmulatorButton) to High(TEmulatorButton) do
    FThread.SetKeyState(ButtonKeys[Button], Button in FGamepadInput.Buttons);
end;

procedure TGBCoreAdapter.ClearInput;
begin
  FGamepadInput := Default(TEmulatorInput);
  FThread.ReleaseKeys;
end;

function TGBCoreAdapter.GetName: string;
begin
  Result := 'Game Boy';
end;

function TGBCoreAdapter.GetSupportsSnapshots: Boolean;
begin
  Result := False;
end;

function TGBCoreAdapter.GetUsesSuborKeyboard: Boolean;
begin
  Result := False;
end;

procedure TGBCoreAdapter.LoadSnapshot(const Name: string);
begin
  raise ENotSupportedException.Create('Game Boy snapshots are not implemented');
end;

procedure TGBCoreAdapter.Pause;
begin
  FThread.RequestPause;
end;

procedure TGBCoreAdapter.Reset;
begin
  // The Game Boy core has no in-place reset path. Recreate its worker so all
  // singleton CPU, GPU and memory state is returned to the power-on state.
  FThread.Free;
  CreateThread;
  FFrameNumber := 0;
  FThread.Start;
  ApplyInput;
end;

procedure TGBCoreAdapter.Resume;
begin
  FThread.RequestResume;
end;

procedure TGBCoreAdapter.SaveSnapshot(const Name: string);
begin
  raise ENotSupportedException.Create('Game Boy snapshots are not implemented');
end;

procedure TGBCoreAdapter.SetGamepadInput(const Input: TEmulatorInput);
begin
  FGamepadInput := Input;
  ApplyInput;
end;

procedure TGBCoreAdapter.SetKeyState(Code: UInt32; Pressed: Boolean);
begin
  var Keys := FConfig.Keys;
  if Code = Keys.A then
    FThread.SetKeyState(TGBKey.A, Pressed);
  if Code = Keys.B then
    FThread.SetKeyState(TGBKey.B, Pressed);
  if Code = Keys.Select then
    FThread.SetKeyState(TGBKey.Select, Pressed);
  if Code = Keys.Start then
    FThread.SetKeyState(TGBKey.Start, Pressed);
  if Code = Keys.Up then
    FThread.SetKeyState(TGBKey.Up, Pressed);
  if Code = Keys.Down then
    FThread.SetKeyState(TGBKey.Down, Pressed);
  if Code = Keys.Left then
    FThread.SetKeyState(TGBKey.Left, Pressed);
  if Code = Keys.Right then
    FThread.SetKeyState(TGBKey.Right, Pressed);
end;

procedure TGBCoreAdapter.Start;
begin
  FThread.Start;
end;

procedure TGBCoreAdapter.Stop;
begin
  if (FThread <> nil) and not FThread.Finished then
    FThread.RequestStop;
end;

function TGBCoreAdapter.TakeError: string;
begin
  Result := FThread.TakeError;
end;

function TGBCoreAdapter.GetConfig: IEmulatorConfig;
begin
  Result := FConfig;
end;

function TGBCoreAdapter.TryGetFrame(out Frame: TEmulatorFrame): Boolean;
var
  Screen: TScreenArray;
  X, Y, Index: Integer;
  FramesPerSecond: Double;
begin
  Result := FThread.TryGetFrame(Screen, FramesPerSecond);
  if not Result then
    Exit;
  Frame.Width := 160;
  Frame.Height := 144;
  SetLength(Frame.Pixels, Frame.Width * Frame.Height);
  for Y := 0 to Frame.Height - 1 do
    for X := 0 to Frame.Width - 1 do
    begin
      Index := Screen[Y * Frame.Width + X];
      if (Index < 0) or (Index > 3) then
        Index := 0;
      Frame.Pixels[Y * Frame.Width + X] := ScreenPalettes[0].Colors[Index];
    end;
  Inc(FFrameNumber);
  Frame.FrameNumber := FFrameNumber;
  Frame.FramesPerSecond := FramesPerSecond;
end;

{ TGameBoyEmulatorConfig }

constructor TGBEmulatorConfig.Create(const AFileName: string);
begin
  inherited Create(AFileName);
  FKeys.A := Ord('Z');
  FKeys.B := Ord('X');
  FKeys.Select := vkSpace;
  FKeys.Start := vkReturn;
  FKeys.Up := vkUp;
  FKeys.Down := vkDown;
  FKeys.Left := vkLeft;
  FKeys.Right := vkRight;
end;

procedure TGBEmulatorConfig.LoadCoreSettings(Ini: TIniFile);
begin
  FKeys.A := Ini.ReadInteger('Controls', 'A', FKeys.A);
  FKeys.B := Ini.ReadInteger('Controls', 'B', FKeys.B);
  FKeys.Select := Ini.ReadInteger('Controls', 'Select', FKeys.Select);
  FKeys.Start := Ini.ReadInteger('Controls', 'Start', FKeys.Start);
  FKeys.Up := Ini.ReadInteger('Controls', 'Up', FKeys.Up);
  FKeys.Down := Ini.ReadInteger('Controls', 'Down', FKeys.Down);
  FKeys.Left := Ini.ReadInteger('Controls', 'Left', FKeys.Left);
  FKeys.Right := Ini.ReadInteger('Controls', 'Right', FKeys.Right);
end;

procedure TGBEmulatorConfig.SaveCoreSettings(Ini: TIniFile);
begin
  Ini.WriteInteger('Controls', 'A', FKeys.A);
  Ini.WriteInteger('Controls', 'B', FKeys.B);
  Ini.WriteInteger('Controls', 'Select', FKeys.Select);
  Ini.WriteInteger('Controls', 'Start', FKeys.Start);
  Ini.WriteInteger('Controls', 'Up', FKeys.Up);
  Ini.WriteInteger('Controls', 'Down', FKeys.Down);
  Ini.WriteInteger('Controls', 'Left', FKeys.Left);
  Ini.WriteInteger('Controls', 'Right', FKeys.Right);
end;

function TGBEmulatorConfig.GetKeys: TGBKeyMap;
begin
  Result := FKeys;
end;

procedure TGBEmulatorConfig.SetKeys(const Value: TGBKeyMap);
begin
  FKeys := Value;
end;

end.

