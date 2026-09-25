unit Core.Adapter.GBC;

interface

uses
  System.IniFiles, Core.Emulation, GBC.EmulationThread, GBC.Joypad;

type
  TGBCKeyMap = record
    A, B, Select, Start, Up, Down, Left, Right: UInt32;
  end;

  IGBCEmulatorConfig = interface(IEmulatorConfig)
    ['{A222ECCD-315C-49EF-8B71-E25A2369E045}']
    function GetKeys: TGBCKeyMap;
    procedure SetKeys(const Value: TGBCKeyMap);
    property Keys: TGBCKeyMap read GetKeys write SetKeys;
  end;

  TGBCEmulatorConfig = class(TEmulatorConfigBase, IGBCEmulatorConfig)
  private
    FKeys: TGBCKeyMap;
  protected
    procedure LoadCoreSettings(Ini: TIniFile); override;
    procedure SaveCoreSettings(Ini: TIniFile); override;
  public
    constructor Create(const AFileName: string);
    function GetKeys: TGBCKeyMap;
    procedure SetKeys(const Value: TGBCKeyMap);
  end;

  TGBCCoreAdapter = class(TInterfacedObject, IEmulationCore)
  private
    FThread: TGBCEmulationThread;
    FFileName: string;
    FGamepadInput: TEmulatorInput;
    FConfig: IGBCEmulatorConfig;
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
  System.SysUtils, System.UITypes, GBC.GPU;

constructor TGBCCoreAdapter.Create(const FileName: string);
begin
  inherited Create;
  FConfig := TGBCEmulatorConfig.Create(EmulatorConfigFileName('gbc'));
  FConfig.Load;
  FFileName := FileName;
  CreateThread;
end;

procedure TGBCCoreAdapter.CreateThread;
begin
  FThread := TGBCEmulationThread.Create(FFileName, FConfig.AudioEnabled);
  FThread.SoundVolume := FConfig.AudioVolume;
end;

destructor TGBCCoreAdapter.Destroy;
begin
  Stop;
  FThread.Free;
  inherited;
end;

procedure TGBCCoreAdapter.ApplyInput;
const
  ButtonKeys: array[TEmulatorButton] of TGBCKey =
    (TGBCKey.Up, TGBCKey.Down, TGBCKey.Left, TGBCKey.Right,
    TGBCKey.A, TGBCKey.B, TGBCKey.Select, TGBCKey.Start);
begin
  for var Button := Low(TEmulatorButton) to High(TEmulatorButton) do
    FThread.SetKeyState(ButtonKeys[Button], Button in FGamepadInput.Buttons);
end;

procedure TGBCCoreAdapter.ClearInput;
begin
  FGamepadInput := Default(TEmulatorInput);
  FThread.ReleaseKeys;
end;

function TGBCCoreAdapter.GetName: string;
begin
  Result := 'Game Boy Color';
end;

function TGBCCoreAdapter.GetSupportsSnapshots: Boolean;
begin
  Result := False;
end;

function TGBCCoreAdapter.GetUsesSuborKeyboard: Boolean;
begin
  Result := False;
end;

procedure TGBCCoreAdapter.LoadSnapshot(const Name: string);
begin
  raise ENotSupportedException.Create('Game Boy Color snapshots are not implemented');
end;

procedure TGBCCoreAdapter.Pause;
begin
  FThread.RequestPause;
end;

procedure TGBCCoreAdapter.Reset;
begin
  // The Game Boy Color core has no in-place reset path. Recreate its worker so all
  // singleton CPU, GPU and memory state is returned to the power-on state.
  FThread.Free;
  CreateThread;
  FFrameNumber := 0;
  FThread.Start;
  ApplyInput;
end;

procedure TGBCCoreAdapter.Resume;
begin
  FThread.RequestResume;
end;

procedure TGBCCoreAdapter.SaveSnapshot(const Name: string);
begin
  raise ENotSupportedException.Create('Game Boy Color snapshots are not implemented');
end;

procedure TGBCCoreAdapter.SetGamepadInput(const Input: TEmulatorInput);
begin
  FGamepadInput := Input;
  ApplyInput;
end;

procedure TGBCCoreAdapter.SetKeyState(Code: UInt32; Pressed: Boolean);
begin
  var Keys := FConfig.Keys;
  if Code = Keys.A then
    FThread.SetKeyState(TGBCKey.A, Pressed);
  if Code = Keys.B then
    FThread.SetKeyState(TGBCKey.B, Pressed);
  if Code = Keys.Select then
    FThread.SetKeyState(TGBCKey.Select, Pressed);
  if Code = Keys.Start then
    FThread.SetKeyState(TGBCKey.Start, Pressed);
  if Code = Keys.Up then
    FThread.SetKeyState(TGBCKey.Up, Pressed);
  if Code = Keys.Down then
    FThread.SetKeyState(TGBCKey.Down, Pressed);
  if Code = Keys.Left then
    FThread.SetKeyState(TGBCKey.Left, Pressed);
  if Code = Keys.Right then
    FThread.SetKeyState(TGBCKey.Right, Pressed);
end;

procedure TGBCCoreAdapter.Start;
begin
  FThread.Start;
end;

procedure TGBCCoreAdapter.Stop;
begin
  if (FThread <> nil) and not FThread.Finished then
    FThread.RequestStop;
end;

function TGBCCoreAdapter.TakeError: string;
begin
  Result := FThread.TakeError;
end;

function TGBCCoreAdapter.GetConfig: IEmulatorConfig;
begin
  Result := FConfig;
end;

function TGBCCoreAdapter.TryGetFrame(out Frame: TEmulatorFrame): Boolean;
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
      // GBC pixels are stored as ARGB bit patterns.  With range checks enabled
      // a direct Integer -> TAlphaColor conversion rejects every opaque color
      // (the high alpha bit makes its signed Integer value negative).
      Move(Index, Frame.Pixels[Y * Frame.Width + X], SizeOf(Index));
    end;
  Inc(FFrameNumber);
  Frame.FrameNumber := FFrameNumber;
  Frame.FramesPerSecond := FramesPerSecond;
end;

{ TGBCEmulatorConfig }

constructor TGBCEmulatorConfig.Create(const AFileName: string);
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

procedure TGBCEmulatorConfig.LoadCoreSettings(Ini: TIniFile);
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

procedure TGBCEmulatorConfig.SaveCoreSettings(Ini: TIniFile);
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

function TGBCEmulatorConfig.GetKeys: TGBCKeyMap;
begin
  Result := FKeys;
end;

procedure TGBCEmulatorConfig.SetKeys(const Value: TGBCKeyMap);
begin
  FKeys := Value;
end;

end.

