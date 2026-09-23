unit NES.Main;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IniFiles,
  System.Math, FMX.Forms, FMX.Types, FMX.Controls, FMX.Objects, FMX.Graphics,
  FMX.Dialogs, NES.Input, NES.Consts, NES.Types, NES.Emulation;

type
  TAppConfig = record
    Scale: Integer;
    Filter: string;
    Keys: TKeyMap;
    Keys2: TKeyMap;
    Keys3: TKeyMap;
    Keys4: TKeyMap;
    FourScore: Boolean;
  end;

  TFormMain = class(TForm)
    ImageCanvas: TImage;
    TimerUpdate: TTimer;
    procedure FormActivate(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
    procedure FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
    procedure TimerUpdateTimer(Sender: TObject);
  private
    FEmulation: TNesEmulationThread;
    FDisplayFrame: TFrameBuffer;
    FSoundErrorShown: Boolean;
    FConfig: TAppConfig;
    FRomPath: string;
    FStarted: Boolean;
    FEmulationFaulted: Boolean;
    FKeysDown: array[0..255] of Boolean;
    procedure SetKeyState(Code: UInt32; Pressed: Boolean);
    procedure LoadRom(const FileName: string);
    procedure OpenRom;
    procedure StopOnError;
    procedure UpdateFrame;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

  end;

var
  FormMain: TFormMain;

implementation

uses
  System.IOUtils;

{$R *.fmx}

function EventKey(Key: Word; KeyChar: WideChar): Word;
begin
  Result := Key;
  if (Result = 0) and (KeyChar <> #0) then
    Result := Ord(UpCase(KeyChar));
end;

function KeyNameToCode(const Name: string): UInt32;
begin
  var NormalizedName: string := UpperCase(Trim(Name));
  if (Length(NormalizedName) = 7) and (Copy(NormalizedName, 1, 6) = 'NUMPAD') and
    CharInSet(NormalizedName[7], ['0'..'9']) then
    Exit(vkNumpad0 + Ord(NormalizedName[7]) - Ord('0'));
  if NormalizedName = 'Z' then
    Exit(Ord('Z'));
  if NormalizedName = 'X' then
    Exit(Ord('X'));
  if NormalizedName = 'A' then
    Exit(Ord('A'));
  if NormalizedName = 'S' then
    Exit(Ord('S'));
  if NormalizedName = 'SPACE' then
    Exit(vkSpace);
  if (NormalizedName = 'RETURN') or (NormalizedName = 'ENTER') then
    Exit(vkReturn);
  if NormalizedName = 'UP' then
    Exit(vkUp);
  if NormalizedName = 'DOWN' then
    Exit(vkDown);
  if NormalizedName = 'LEFT' then
    Exit(vkLeft);
  if NormalizedName = 'RIGHT' then
    Exit(vkRight);
  if (Length(NormalizedName) = 1) and (NormalizedName[1] >= 'A') and (NormalizedName[1] <= 'Z') then
    Exit(Ord(NormalizedName[1]));
  if (Length(NormalizedName) = 1) and (NormalizedName[1] >= '0') and (NormalizedName[1] <= '9') then
    Exit(Ord(NormalizedName[1]));
  Result := 0;
end;

function KeyCodeToName(KeyCode: UInt32): string;
begin
  if (KeyCode >= vkNumpad0) and (KeyCode <= vkNumpad9) then
    Exit('NUMPAD' + IntToStr(KeyCode - vkNumpad0));
  case KeyCode of
    Ord('Z'):
      Result := 'Z';
    Ord('X'):
      Result := 'X';
    Ord('A'):
      Result := 'A';
    Ord('S'):
      Result := 'S';
    vkSpace:
      Result := 'SPACE';
    vkReturn:
      Result := 'RETURN';
    vkUp:
      Result := 'UP';
    vkDown:
      Result := 'DOWN';
    vkLeft:
      Result := 'LEFT';
    vkRight:
      Result := 'RIGHT';
  else
    if (KeyCode >= Ord('A')) and (KeyCode <= Ord('Z')) then
      Result := UpperCase(Chr(KeyCode))
    else if (KeyCode >= Ord('0')) and (KeyCode <= Ord('9')) then
      Result := Chr(KeyCode)
    else
      Result := 'UNKNOWN';
  end;
end;

function DefaultConfig: TAppConfig;
begin
  Result.Scale := 2;
  Result.Filter := 'nearest';
  Result.Keys.A := Ord('Z');
  Result.Keys.B := Ord('X');
  Result.Keys.Select := vkSpace;
  Result.Keys.Start := vkReturn;
  Result.Keys.Up := vkUp;
  Result.Keys.Down := vkDown;
  Result.Keys.Left := vkLeft;
  Result.Keys.Right := vkRight;
  Result.Keys2.A := Ord('G');
  Result.Keys2.B := Ord('H');
  Result.Keys2.Select := Ord('T');
  Result.Keys2.Start := Ord('Y');
  Result.Keys2.Up := Ord('W');
  Result.Keys2.Down := Ord('S');
  Result.Keys2.Left := Ord('A');
  Result.Keys2.Right := Ord('D');
  Result.Keys3.A := Ord('N');
  Result.Keys3.B := Ord('M');
  Result.Keys3.Select := Ord('U');
  Result.Keys3.Start := Ord('O');
  Result.Keys3.Up := Ord('I');
  Result.Keys3.Down := Ord('K');
  Result.Keys3.Left := Ord('J');
  Result.Keys3.Right := Ord('L');
  Result.Keys4.A := vkNumpad1;
  Result.Keys4.B := vkNumpad3;
  Result.Keys4.Select := vkNumpad7;
  Result.Keys4.Start := vkNumpad9;
  Result.Keys4.Up := vkNumpad8;
  Result.Keys4.Down := vkNumpad5;
  Result.Keys4.Left := vkNumpad4;
  Result.Keys4.Right := vkNumpad6;
  Result.FourScore := True;
end;

procedure WriteKeyMap(Ini: TIniFile; const Section: string; const Keys: TKeyMap);
begin
  Ini.WriteString(Section, 'A', KeyCodeToName(Keys.A));
  Ini.WriteString(Section, 'B', KeyCodeToName(Keys.B));
  Ini.WriteString(Section, 'Select', KeyCodeToName(Keys.Select));
  Ini.WriteString(Section, 'Start', KeyCodeToName(Keys.Start));
  Ini.WriteString(Section, 'Up', KeyCodeToName(Keys.Up));
  Ini.WriteString(Section, 'Down', KeyCodeToName(Keys.Down));
  Ini.WriteString(Section, 'Left', KeyCodeToName(Keys.Left));
  Ini.WriteString(Section, 'Right', KeyCodeToName(Keys.Right));
end;

procedure WriteConfig(const FileName: string; const Config: TAppConfig);
begin
  var Ini: TIniFile := TIniFile.Create(FileName);
  try
    Ini.WriteInteger('Video', 'Scale', Config.Scale);
    Ini.WriteString('Video', 'Filter', Config.Filter);
    Ini.WriteBool('Input', 'FourScore', Config.FourScore);
    WriteKeyMap(Ini, 'Controls', Config.Keys);
    WriteKeyMap(Ini, 'Controls2', Config.Keys2);
    WriteKeyMap(Ini, 'Controls3', Config.Keys3);
    WriteKeyMap(Ini, 'Controls4', Config.Keys4);
  finally
    Ini.Free;
  end;
end;

function ReadMappedKey(Ini: TIniFile; const Section, Ident: string; DefaultKey: UInt32): UInt32;
begin
  var Value: UInt32 := KeyNameToCode(Ini.ReadString(Section, Ident, KeyCodeToName(DefaultKey)));
  if Value = 0 then
    Result := DefaultKey
  else
    Result := Value;
end;

function ReadKeyMap(Ini: TIniFile; const Section: string; const Defaults: TKeyMap): TKeyMap;
begin
  Result.A := ReadMappedKey(Ini, Section, 'A', Defaults.A);
  Result.B := ReadMappedKey(Ini, Section, 'B', Defaults.B);
  Result.Select := ReadMappedKey(Ini, Section, 'Select', Defaults.Select);
  Result.Start := ReadMappedKey(Ini, Section, 'Start', Defaults.Start);
  Result.Up := ReadMappedKey(Ini, Section, 'Up', Defaults.Up);
  Result.Down := ReadMappedKey(Ini, Section, 'Down', Defaults.Down);
  Result.Left := ReadMappedKey(Ini, Section, 'Left', Defaults.Left);
  Result.Right := ReadMappedKey(Ini, Section, 'Right', Defaults.Right);
end;

function LoadOrCreateConfig(const FileName: string): TAppConfig;
begin
  var Defaults: TAppConfig := DefaultConfig;
  if not FileExists(FileName) then
    WriteConfig(FileName, Defaults);

  var Ini: TIniFile := TIniFile.Create(FileName);
  try
    Result := Defaults;
    Result.Scale := Ini.ReadInteger('Video', 'Scale', Defaults.Scale);
    Result.Scale := EnsureRange(Result.Scale, 1, 8);
    Result.Filter := Trim(Ini.ReadString('Video', 'Filter', Defaults.Filter));
    if Result.Filter = '' then
      Result.Filter := Defaults.Filter;

    Result.FourScore := Ini.ReadBool('Input', 'FourScore', Defaults.FourScore);
    Result.Keys := ReadKeyMap(Ini, 'Controls', Defaults.Keys);
    Result.Keys2 := ReadKeyMap(Ini, 'Controls2', Defaults.Keys2);
    Result.Keys3 := ReadKeyMap(Ini, 'Controls3', Defaults.Keys3);
    Result.Keys4 := ReadKeyMap(Ini, 'Controls4', Defaults.Keys4);
  finally
    Ini.Free;
  end;
end;

procedure TFormMain.SetKeyState(Code: UInt32; Pressed: Boolean);
begin
  if FEmulation <> nil then
    FEmulation.SetKey(Code, Pressed, FConfig.Keys, FConfig.Keys2, FConfig.Keys3, FConfig.Keys4);
end;

{ TFormMain }

constructor TFormMain.Create(AOwner: TComponent);
begin
  inherited;
  Caption := 'NESFMX - Open ROM: Ctrl+O';
  Position := TFormPosition.ScreenCenter;
  Fill.Color := TAlphaColors.Black;
  FConfig := LoadOrCreateConfig(TPath.Combine(ExtractFilePath(ParamStr(0)), 'config.ini'));
  ClientWidth := NES_WIDTH * FConfig.Scale;
  ClientHeight := NES_HEIGHT * FConfig.Scale;
  ImageCanvas.DisableInterpolation := SameText(FConfig.Filter, 'nearest');
  ImageCanvas.Bitmap.SetSize(NES_WIDTH, NES_HEIGHT);
  ImageCanvas.Bitmap.Clear(TAlphaColors.Black);
  TimerUpdate.Interval := 8;
end;

destructor TFormMain.Destroy;
begin
  if TimerUpdate <> nil then
    TimerUpdate.Enabled := False;
  FreeAndNil(FEmulation);
  inherited;
end;

procedure TFormMain.FormActivate(Sender: TObject);
begin
  TimerUpdate.Enabled := (FEmulation <> nil) and not FEmulationFaulted;
end;

procedure TFormMain.FormDeactivate(Sender: TObject);
begin
  // Keep emulation and audio running, but release keys whose key-up may be lost.
  FillChar(FKeysDown, SizeOf(FKeysDown), 0);
  if FEmulation <> nil then
    FEmulation.ClearInput;
end;

procedure TFormMain.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  var Code: Word := EventKey(Key, KeyChar);
  var WasDown: Boolean := False;
  if Code <= High(FKeysDown) then
  begin
    WasDown := FKeysDown[Code];
    FKeysDown[Code] := True;
  end;
  if not WasDown then
  begin
    if Code = vkEscape then
      Close
    else if (Code = Ord('O')) and (ssCtrl in Shift) then
      OpenRom
    else if (Code = Ord('R')) and (FEmulation <> nil) then
    begin
      TimerUpdate.Enabled := False;
      try
        FEmulation.RequestReset;
        FEmulationFaulted := False;
        TimerUpdate.Enabled := True;
        Caption := 'NESFMX - ' + ExtractFileName(FRomPath);
      except
        StopOnError;
        raise;
      end;
    end
    else if (Code = vkF5) and (FEmulation <> nil) then
    begin
      UpdateFrame;
      ImageCanvas.Bitmap.SaveToFile(TPath.Combine(TPath.GetDocumentsPath,
          'screenshot_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + '.png'));
    end
    else if (Code = vkF6) and (FEmulation <> nil) then
    begin
      var DiagnosticPath := TPath.Combine(TPath.GetDocumentsPath,
        'NES-audio-' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
      FormDeactivate(Self);
      try
        FEmulation.SaveDiagnostics(DiagnosticPath);
        UpdateFrame;
        ImageCanvas.Bitmap.SaveToFile(DiagnosticPath + '.png');
        ShowMessage('Audio diagnostics saved: ' + DiagnosticPath + '.csv');
      finally
        FormActivate(Self);
      end;
    end;
  end;
  if not (ssCtrl in Shift) then
    SetKeyState(Code, True);
  Key := 0;
  KeyChar := #0;
end;

procedure TFormMain.FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  var Code: Word := EventKey(Key, KeyChar);
  if Code <= High(FKeysDown) then
    FKeysDown[Code] := False;
  SetKeyState(Code, False);
  Key := 0;
  KeyChar := #0;
end;

procedure TFormMain.FormShow(Sender: TObject);
begin
  if FStarted then
    Exit;
  FStarted := True;
  try
    if ParamCount > 0 then
      LoadRom(ParamStr(1))
    else
      OpenRom;
  except
    on E: Exception do
      ShowMessage(E.Message);
  end;
end;

procedure TFormMain.TimerUpdateTimer(Sender: TObject);
begin
  if FEmulationFaulted or not TimerUpdate.Enabled or (FEmulation = nil) then
    Exit;
  try
    UpdateFrame;
  except
    StopOnError;
    raise;
  end;
end;

procedure TFormMain.StopOnError;
begin
  FEmulationFaulted := True;
  TimerUpdate.Enabled := False;
  if FEmulation <> nil then
    FEmulation.RequestPause;
  FormDeactivate(Self);
  Caption := 'NESFMX - Stopped after error - ' + ExtractFileName(FRomPath);
end;

procedure TFormMain.LoadRom(const FileName: string);
begin
  // Validate first: an invalid ROM leaves the current worker running.
  var NewEmulation := TNesEmulationThread.Create(FileName, FConfig.FourScore);
  TimerUpdate.Enabled := False;
  FreeAndNil(FEmulation); // Join before replacing the session.
  FEmulation := NewEmulation;
  FillChar(FKeysDown, SizeOf(FKeysDown), 0);
  FRomPath := FileName;
  FSoundErrorShown := False;
  try
    ImageCanvas.Bitmap.Clear(TAlphaColors.Black);
    FEmulationFaulted := False;
    FEmulation.Start;
    TimerUpdate.Enabled := True;
    Caption := 'NESFMX - ' + ExtractFileName(FRomPath);
  except
    StopOnError;
    raise;
  end;
end;

procedure TFormMain.OpenRom;
begin
  FormDeactivate(Self);
  var Dialog: TOpenDialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'NES ROM (*.nes)|*.nes';
    Dialog.Options := [TOpenOption.ofFileMustExist, TOpenOption.ofPathMustExist];
    if Dialog.Execute then
      LoadRom(Dialog.FileName);
  finally
    Dialog.Free;
    FormActivate(Self);
  end;
end;

procedure TFormMain.UpdateFrame;
begin
  if FEmulation = nil then
    Exit;
  var Status: TEmulationStatus;
  var NewFrame := FEmulation.TakeSnapshot(FDisplayFrame, Status);
  if (Status.Error <> '') and not FEmulationFaulted then
  begin
    StopOnError;
    raise ENesException.Create(Status.Error);
  end;
  if not FEmulationFaulted and (Status.FramesPerSecond > 0) then
  begin
    var NewCaption := Format('NESFMX - %.1f FPS - %s',
      [Status.FramesPerSecond, ExtractFileName(FRomPath)]);
    if Status.AudioError <> '' then
      NewCaption := NewCaption + ' - sound unavailable';
    if Caption <> NewCaption then
      Caption := NewCaption;
  end;
  if (Status.AudioError <> '') and not FSoundErrorShown then
  begin
    FSoundErrorShown := True;
    ShowMessage('Sound unavailable: ' + Status.AudioError);
  end;
  if not NewFrame then
    Exit;
  var Data: TBitmapData;
  if ImageCanvas.Bitmap.Map(TMapAccess.Write, Data) then
  try
    for var y := 0 to NES_HEIGHT - 1 do
      for var x := 0 to NES_WIDTH - 1 do
        Data.SetPixel(x, y, FDisplayFrame[x, y] or $FF000000);
  finally
    ImageCanvas.Bitmap.Unmap(Data);
  end;
  ImageCanvas.Repaint;
end;

end.

