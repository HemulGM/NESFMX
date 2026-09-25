unit NES.Main;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IniFiles,
  System.Math, FMX.Forms, FMX.Types, FMX.Controls, FMX.Objects, FMX.Graphics,
  FMX.Dialogs, NES.Input, NES.Consts, NES.Types, NES.Emulation,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Layouts, NES.Gamepad, NES.SuborKeyboard
  {$IFDEF ANDROID}
    , Androidapi.Helpers, Androidapi.JNI.GraphicsContentViewText,
    Androidapi.JNI.App, Androidapi.JNI.Widget, Androidapi.JNI.Os,
    Androidapi.JNI.Media, FMX.Platform, FMX.ApplicationEvents,
    NES.RomPicker.Android
  {$ENDIF};

type
  TAppConfig = record
    Scale: Integer;
    Filter: string;
    Keys: TKeyMap;
    Keys2: TKeyMap;
    Keys3: TKeyMap;
    Keys4: TKeyMap;
    FourScore: Boolean;
    Region: TRegionOverride;
  end;

  TFormMain = class(TForm)
    ImageCanvas: TImage;
    TimerUpdate: TTimer;
    LayoutHead: TLayout;
    ButtonOpen: TButton;
    LabelStatus: TLabel;
    procedure FormActivate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
    procedure FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure TimerUpdateTimer(Sender: TObject);
    procedure ButtonOpenClick(Sender: TObject);
    procedure FormSafeAreaChanged(Sender: TObject; const AInsets: TRectF);
  private
    FEmulation: TNesEmulationThread;
    FGamepad: TNesGamepad;
    FSuborKeyboard: TNesSuborKeyboard;
    FDisplayFrame: TFrameBuffer;
    FSoundErrorShown: Boolean;
    FConfig: TAppConfig;
    FRomDisplayName: string;
    FOpeningRom: Boolean;
    FEmulationFaulted: Boolean;
    FKeysDown: array[0..255] of Boolean;
    {$IFDEF ANDROID}
    FPicker: TNesAndroidRomPicker;
    FAppEvents: TApplicationEvents;
    FInBackground, FActivityPaused: Boolean;
    FSuborKeyboardTouchAttached: Boolean;
    function ApplicationStateChanged(Sender: TObject; const AAppEvent: TApplicationEvent; const AContext: TObject): Boolean;
    procedure PollRomPicker;
    {$ENDIF}
    procedure SetKeyState(Code: UInt32; Pressed: Boolean);
    procedure GamepadChanged(Sender: TObject);
    procedure SuborKeyboardChanged(Sender: TObject);
    procedure SetStatus(const Text: string);
    procedure SyncActivity;
    procedure OpenRom;
    procedure StopOnError;
    procedure UpdateFrame;
  public
    procedure SaveSnapshot(const Name: string);
    procedure LoadSnapshot(const Name: string);
    procedure LoadRom(const FileName: string; const DisplayName: string = '');
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
  Result.Region := TRegionOverride.Auto;
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
    case Config.Region of
      TRegionOverride.NTSC:
        Ini.WriteString('Video', 'Region', 'NTSC');
      TRegionOverride.PAL:
        Ini.WriteString('Video', 'Region', 'PAL');
    else
      Ini.WriteString('Video', 'Region', 'Auto');
    end;
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
    var Region := Trim(Ini.ReadString('Video', 'Region', 'Auto'));
    if SameText(Region, 'PAL') then
      Result.Region := TRegionOverride.PAL
    else if SameText(Region, 'NTSC') then
      Result.Region := TRegionOverride.NTSC;

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

procedure TFormMain.ButtonOpenClick(Sender: TObject);
begin
  try
    OpenRom;
  except
    on E: Exception do
      ShowMessage(E.Message);
  end;
end;

constructor TFormMain.Create(AOwner: TComponent);
begin
  inherited;
  SetStatus('NESFMX - Open ROM');
  {$IFDEF ANDROID}
  // Hardware volume keys control game audio, including before a ROM is loaded.
  TAndroidHelper.Activity.setVolumeControlStream(TJAudioManager.JavaClass.STREAM_MUSIC);
  FConfig := LoadOrCreateConfig(TPath.Combine(TPath.GetDocumentsPath, 'config.ini'));
  FPicker := TNesAndroidRomPicker.Create;
  FAppEvents := TApplicationEvents.Create(Self);
  FAppEvents.OnStateChanged := ApplicationStateChanged;
  {$ELSE}
  Position := TFormPosition.ScreenCenter;
  FConfig := LoadOrCreateConfig(TPath.Combine(ExtractFilePath(ParamStr(0)), 'config.ini'));
  ClientWidth := NES_WIDTH * FConfig.Scale;
  ClientHeight := NES_HEIGHT * FConfig.Scale + Trunc(LayoutHead.Height);
  {$ENDIF}
  Fill.Color := TAlphaColors.Black;
  ImageCanvas.WrapMode := TImageWrapMode.Fit;
  ImageCanvas.DisableInterpolation := SameText(FConfig.Filter, 'nearest');
  ImageCanvas.Bitmap.SetSize(NES_WIDTH, NES_HEIGHT);
  ImageCanvas.Bitmap.Clear(TAlphaColors.Black);
  FGamepad := TNesGamepad.Create(Self);
  FGamepad.Name := 'ScreenGamepad';
  FGamepad.Parent := Self;
  FGamepad.Align := TAlignLayout.Bottom;
  FGamepad.OnChange := GamepadChanged;
  FGamepad.Enabled := False;
  FGamepad.Visible := False;
  FSuborKeyboard := TNesSuborKeyboard.Create(Self);
  FSuborKeyboard.Name := 'ScreenSuborKeyboard';
  FSuborKeyboard.Parent := Self;
  FSuborKeyboard.Align := TAlignLayout.Bottom;
  FSuborKeyboard.OnChange := SuborKeyboardChanged;
  FSuborKeyboard.Enabled := False;
  FSuborKeyboard.Visible := False;
  FormResize(Self);
  TimerUpdate.Interval := 8;
end;

destructor TFormMain.Destroy;
begin
  if TimerUpdate <> nil then
    TimerUpdate.Enabled := False;
  FreeAndNil(FSuborKeyboard);
  FreeAndNil(FGamepad); // Detach the native listener before destroying the form.
  {$IFDEF ANDROID}
  FreeAndNil(FAppEvents);
  FreeAndNil(FPicker);
  {$ENDIF}
  if FEmulation <> nil then
  try
    FEmulation.StopAndSave;
  except
    Application.HandleException(Self);
  end;
  FreeAndNil(FEmulation);
  inherited;
end;

procedure TFormMain.FormActivate(Sender: TObject);
begin
  if FGamepad <> nil then
    FGamepad.AttachToForm(Self);
  SyncActivity;
end;

procedure TFormMain.FormResize(Sender: TObject);
begin
  if FGamepad <> nil then
    FGamepad.Height := TNesGamepad.PreferredHeight(
      ClientWidth - Padding.Left - Padding.Right,
      ClientHeight - Padding.Top - Padding.Bottom - LayoutHead.Height);
  if FSuborKeyboard <> nil then
    FSuborKeyboard.Height := TNesSuborKeyboard.PreferredHeight(
      ClientWidth - Padding.Left - Padding.Right,
      ClientHeight - Padding.Top - Padding.Bottom - LayoutHead.Height);
end;

procedure TFormMain.GamepadChanged(Sender: TObject);
begin
  if FEmulation <> nil then
    FEmulation.SetButtons(INPUT_SCREEN_GAMEPAD, 1, FGamepad.Buttons);
end;

procedure TFormMain.SuborKeyboardChanged(Sender: TObject);
begin
  if FEmulation <> nil then
    FEmulation.SetSuborKeys(FSuborKeyboard.Keys);
end;

procedure TFormMain.SetStatus(const Text: string);
begin
  Caption := Text;
  LabelStatus.Text := Text;
end;

procedure TFormMain.SyncActivity;
begin
  var SuborKeyboardActive := (FEmulation <> nil) and FEmulation.UsesSuborKeyboard;
  if FGamepad <> nil then
  begin
    FGamepad.Visible := not SuborKeyboardActive;
    FGamepad.Enabled := (FEmulation <> nil) and not FEmulationFaulted and not FOpeningRom and not SuborKeyboardActive;
  end;
  if FSuborKeyboard <> nil then
  begin
    FSuborKeyboard.Visible := SuborKeyboardActive;
    FSuborKeyboard.Enabled := SuborKeyboardActive and not FEmulationFaulted and not FOpeningRom;
  end;
  {$IFDEF ANDROID}
  // The Android view accepts one native touch listener.  The controls are
  // mutually exclusive, so hand it to the currently visible control.
  if FSuborKeyboardTouchAttached <> SuborKeyboardActive then
  begin
    if FSuborKeyboardTouchAttached then
      FSuborKeyboard.AttachToForm(nil)
    else
      FGamepad.AttachToForm(nil);
    if SuborKeyboardActive then
      FSuborKeyboard.AttachToForm(Self)
    else
      FGamepad.AttachToForm(Self);
    FSuborKeyboardTouchAttached := SuborKeyboardActive;
  end;
  var Paused := FInBackground or FOpeningRom;
  if FGamepad <> nil then
    FGamepad.Enabled := FGamepad.Enabled and not FInBackground;
  if FSuborKeyboard <> nil then
    FSuborKeyboard.Enabled := FSuborKeyboard.Enabled and not FInBackground;
  if Paused <> FActivityPaused then
  begin
    FActivityPaused := Paused;
    if FEmulation <> nil then
      if Paused then
      begin
        FormDeactivate(Self);
        FEmulation.RequestPause;
      end
      else if not FEmulationFaulted then
        FEmulation.RequestResume;
  end;
  TimerUpdate.Enabled := not FInBackground and
    (FOpeningRom or ((FEmulation <> nil) and not FEmulationFaulted));
  {$ELSE}
  TimerUpdate.Enabled := (FEmulation <> nil) and not FEmulationFaulted;
  {$ENDIF}
end;

{$IFDEF ANDROID}
function TFormMain.ApplicationStateChanged(Sender: TObject; const AAppEvent: TApplicationEvent; const AContext: TObject): Boolean;
begin
  case AAppEvent of
    TApplicationEvent.WillBecomeInactive, TApplicationEvent.EnteredBackground:
      FInBackground := True;
    TApplicationEvent.BecameActive:
      FInBackground := False;
  else
    Exit(False);
  end;
  SyncActivity;
  Result := False;
end;

procedure TFormMain.PollRomPicker;
begin
  if not FOpeningRom then
    Exit;
  var FileName, DisplayName, Error: string;
  if not FPicker.Poll(FileName, DisplayName, Error) then
    Exit;
  try
    try
      if Error <> '' then
        raise Exception.Create(Error);
      if FileName <> '' then
        LoadRom(FileName, DisplayName);
    except
      on E: Exception do
        ShowMessage(E.Message);
    end;
  finally
    FPicker.Finish;
    FOpeningRom := False;
    ButtonOpen.Enabled := True;
    SyncActivity;
  end;
end;
{$ENDIF}

procedure TFormMain.FormDeactivate(Sender: TObject);
begin
  // Release keys whose key-up may be lost. Android lifecycle controls pausing.
  FillChar(FKeysDown, SizeOf(FKeysDown), 0);
  if FGamepad <> nil then
    FGamepad.ReleaseAll;
  if FSuborKeyboard <> nil then
    FSuborKeyboard.ReleaseAll;
  if FEmulation <> nil then
    FEmulation.ClearInput;
end;

procedure TFormMain.SaveSnapshot(const Name: string);
begin
  if FEmulation = nil then
    raise ENesException.Create('No game loaded');
  FEmulation.SaveSnapshot(Name);
end;

procedure TFormMain.LoadSnapshot(const Name: string);
begin
  if FEmulation = nil then
    raise ENesException.Create('No game loaded');
  FEmulation.LoadSnapshot(Name);
  FEmulationFaulted := False;
  SyncActivity;
  UpdateFrame;
end;

procedure TFormMain.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  {$IFDEF ANDROID}
  // Keep the key intact so FMX delegates volume adjustment/repeat to Android.
  if Key in [vkVolumeUp, vkVolumeDown, vkVolumeMute] then
    Exit;
  {$ENDIF}
  var Code: Word := EventKey(Key, KeyChar);
  var SuborKeyboardActive := (FEmulation <> nil) and FEmulation.UsesSuborKeyboard;
  var WasDown: Boolean := False;
  if Code <= High(FKeysDown) then
  begin
    WasDown := FKeysDown[Code];
    FKeysDown[Code] := True;
  end;
  if not WasDown then
  begin
    if (Code = vkEscape) and not SuborKeyboardActive then
      Close
    else if (Code = Ord('O')) and (ssCtrl in Shift) then
      OpenRom
    else if (Code = Ord('R')) and (FEmulation <> nil) and not SuborKeyboardActive then
    begin
      TimerUpdate.Enabled := False;
      try
        FEmulation.RequestReset;
        FEmulationFaulted := False;
        {$IFDEF ANDROID}
        if FActivityPaused then
          FEmulation.RequestPause;
        {$ENDIF}
        SyncActivity;
        SetStatus('NESFMX - ' + FRomDisplayName);
      except
        StopOnError;
        raise;
      end;
    end
    else if (Code in [vkF5, vkF6]) and (FEmulation <> nil) and not SuborKeyboardActive then
    begin
      try
        if Code = vkF5 then
          SaveSnapshot('quick')
        else
          LoadSnapshot('quick');
      except
        on E: Exception do
          ShowMessage('Snapshot: ' + E.Message);
      end;
    end;
  end;
  if SuborKeyboardActive or not (ssCtrl in Shift) then
    SetKeyState(Code, True);
  Key := 0;
  KeyChar := #0;
end;

procedure TFormMain.FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  {$IFDEF ANDROID}
  // Android must also receive the release of its volume keys.
  if Key in [vkVolumeUp, vkVolumeDown, vkVolumeMute] then
    Exit;
  {$ENDIF}
  var Code: Word := EventKey(Key, KeyChar);
  if Code <= High(FKeysDown) then
    FKeysDown[Code] := False;
  if ((FEmulation <> nil) and FEmulation.UsesSuborKeyboard) or not (ssCtrl in Shift) then
    SetKeyState(Code, False);
  Key := 0;
  KeyChar := #0;
end;

procedure TFormMain.FormSafeAreaChanged(Sender: TObject; const AInsets: TRectF);
begin
  Padding.Left := AInsets.Left;
  Padding.Top := AInsets.Top;
  Padding.Right := AInsets.Right;
  Padding.Bottom := AInsets.Bottom;
  FormResize(Self);
end;

procedure TFormMain.TimerUpdateTimer(Sender: TObject);
begin
  {$IFDEF ANDROID}
  PollRomPicker;
  if FOpeningRom then
    Exit;
  {$ENDIF}
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
  SetStatus('NESFMX - Stopped after error - ' + FRomDisplayName);
  SyncActivity;
end;

procedure TFormMain.LoadRom(const FileName: string; const DisplayName: string);
begin
  // Validate first: an invalid ROM leaves the current worker running.
  var NewEmulation := TNesEmulationThread.Create(FileName, FConfig.FourScore, FConfig.Region);
  try
    if FEmulation <> nil then
      FEmulation.StopAndSave;
  except
    NewEmulation.Free;
    raise;
  end;
  if FGamepad <> nil then
    FGamepad.ReleaseAll;
  if FSuborKeyboard <> nil then
    FSuborKeyboard.ReleaseAll;
  TimerUpdate.Enabled := False;
  FreeAndNil(FEmulation); // Join before replacing the session.
  FEmulation := NewEmulation;
  FillChar(FKeysDown, SizeOf(FKeysDown), 0);
  FRomDisplayName := DisplayName;
  if FRomDisplayName = '' then
    FRomDisplayName := ExtractFileName(FileName);
  FSoundErrorShown := False;
  try
    ImageCanvas.Bitmap.Clear(TAlphaColors.Black);
    FEmulationFaulted := False;
    {$IFDEF ANDROID}
    if FActivityPaused then
      FEmulation.RequestPause;
    {$ENDIF}
    FEmulation.Start;
    SyncActivity;
    SetStatus('NESFMX - ' + FRomDisplayName);
  except
    StopOnError;
    raise;
  end;
end;

procedure TFormMain.OpenRom;
begin
  if FOpeningRom then
    Exit;
  FOpeningRom := True;
  ButtonOpen.Enabled := False;
  FormDeactivate(Self);
  {$IFDEF ANDROID}
  try
    SyncActivity;
    FPicker.Open;
  except
    FPicker.Finish;
    FOpeningRom := False;
    ButtonOpen.Enabled := True;
    SyncActivity;
    raise;
  end;
  {$ELSE}
  var Dialog: TOpenDialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'NES ROM (*.nes)|*.nes';
    Dialog.Options := [TOpenOption.ofFileMustExist, TOpenOption.ofPathMustExist];
    if Dialog.Execute then
      LoadRom(Dialog.FileName);
  finally
    Dialog.Free;
    FOpeningRom := False;
    ButtonOpen.Enabled := True;
    FormActivate(Self);
  end;
  {$ENDIF}
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
    var RegionName := 'NTSC';
    if Status.Region = TNesRegion.PAL then
      RegionName := 'PAL';
    if Status.Region = TNesRegion.Dendy then
      RegionName := 'Dendy';
    //var NewCaption := Format('NESFMX - %s - %.1f FPS - %s', [RegionName, Status.FramesPerSecond, FRomDisplayName]);
    var NewCaption := Format('%.1f - %.1f FPS', [FEmulation.RunFrameMs, Status.FramesPerSecond]);
    if Status.AudioError <> '' then
      NewCaption := NewCaption + ' - sound unavailable';
    //NewCaption := NewCaption;
    if Caption <> NewCaption then
      SetStatus(NewCaption);
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
    for var Y := 0 to NES_HEIGHT - 1 do
      for var X := 0 to NES_WIDTH - 1 do
        Data.SetPixel(X, Y, FDisplayFrame[X, Y] or $FF000000);
  finally
    ImageCanvas.Bitmap.Unmap(Data);
  end;
  ImageCanvas.Repaint;
end;

end.

