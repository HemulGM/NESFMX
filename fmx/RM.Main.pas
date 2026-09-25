unit RM.Main;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, FMX.Forms,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Graphics, FMX.Dialogs, NES.Consts,
  NES.Controller, Core.Emulation, Core.EmulatorFactory, Core.NesAdapter,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Layouts, NES.Gamepad,
  NES.SuborKeyboard
  {$IFDEF ANDROID}
    , Androidapi.Helpers, Androidapi.JNI.GraphicsContentViewText,
    Androidapi.JNI.App, Androidapi.JNI.Widget, Androidapi.JNI.Os,
    Androidapi.JNI.Media, FMX.Platform, FMX.ApplicationEvents,
    NES.RomPicker.Android
  {$ENDIF};

type
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
    FEmulation: IEmulationCore;
    FGamepad: TNesGamepad;
    FSuborKeyboard: TNesSuborKeyboard;
    FGamepadInput: TEmulatorInput;
    FSoundErrorShown: Boolean;
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
    procedure GamepadChanged(Sender: TObject);
    procedure SuborKeyboardChanged(Sender: TObject);
    function InputControlHeight(const CanvasHeight: Single): Single;
    procedure ResizeClientArea;
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

const
  AppName = 'Retromul';

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
  SetStatus(' - Open ROM');
  {$IFDEF ANDROID}
  // Hardware volume keys control game audio, including before a ROM is loaded.
  TAndroidHelper.Activity.setVolumeControlStream(TJAudioManager.JavaClass.STREAM_MUSIC);
  FPicker := TNesAndroidRomPicker.Create;
  FAppEvents := TApplicationEvents.Create(Self);
  FAppEvents.OnStateChanged := ApplicationStateChanged;
  {$ELSE}
  Position := TFormPosition.ScreenCenter;
  ResizeClientArea;
  {$ENDIF}
  Fill.Color := TAlphaColors.Black;
  ImageCanvas.WrapMode := TImageWrapMode.Fit;
  ImageCanvas.DisableInterpolation := True;
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
    FEmulation.Stop;
  except
    Application.HandleException(Self);
  end;
  FEmulation := nil;
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

function TFormMain.InputControlHeight(const CanvasHeight: Single): Single;
var
  AvailableWidth: Single;
begin
  AvailableWidth := ClientWidth - Padding.Left - Padding.Right;
  if (FEmulation <> nil) and FEmulation.UsesSuborKeyboard then
    Result := TNesSuborKeyboard.PreferredHeight(AvailableWidth, CanvasHeight)
  else
    Result := TNesGamepad.PreferredHeight(AvailableWidth, CanvasHeight);
end;

procedure TFormMain.ResizeClientArea;
{$IFNDEF ANDROID}
var
  CanvasHeight: Single;
  Scale: Integer;
begin
  Scale := 2;
  if FEmulation <> nil then
    Scale := FEmulation.Config.Scale;
  ClientWidth := NES_WIDTH * Scale;
  CanvasHeight := NES_HEIGHT * Scale;
  ClientHeight := Trunc(Padding.Top + LayoutHead.Height + CanvasHeight +
    InputControlHeight(CanvasHeight) + Padding.Bottom);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure TFormMain.GamepadChanged(Sender: TObject);
begin
  FGamepadInput.Buttons := [];
  if TNesButton.A in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.A);
  if TNesButton.B in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.B);
  if TNesButton.Select in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.Select);
  if TNesButton.Start in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.Start);
  if TNesButton.Up in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.Up);
  if TNesButton.Down in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.Down);
  if TNesButton.Left in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.Left);
  if TNesButton.Right in FGamepad.Buttons then
    Include(FGamepadInput.Buttons, TEmulatorButton.Right);
  if FEmulation <> nil then
    FEmulation.SetGamepadInput(FGamepadInput);
end;

procedure TFormMain.SuborKeyboardChanged(Sender: TObject);
var
  Peripheral: INesPeripheralCore;
begin
  if Supports(FEmulation, INesPeripheralCore, Peripheral) then
    Peripheral.SetSuborKeys(FSuborKeyboard.Keys);
end;

procedure TFormMain.SetStatus(const Text: string);
begin
  Caption := AppName + Text;
  LabelStatus.Text := Caption;
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
        FEmulation.Pause;
      end
      else if not FEmulationFaulted then
        FEmulation.Resume;
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
  FGamepadInput := Default(TEmulatorInput);
end;

procedure TFormMain.SaveSnapshot(const Name: string);
begin
  if FEmulation = nil then
    raise Exception.Create('No game loaded');
  if not FEmulation.SupportsSnapshots then
    raise ENotSupportedException.Create('Snapshots are not implemented by this core');
  FEmulation.SaveSnapshot(Name);
end;

procedure TFormMain.LoadSnapshot(const Name: string);
begin
  if FEmulation = nil then
    raise Exception.Create('No game loaded');
  if not FEmulation.SupportsSnapshots then
    raise ENotSupportedException.Create('Snapshots are not implemented by this core');
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
        FEmulation.Reset;
        FEmulationFaulted := False;
        {$IFDEF ANDROID}
        if FActivityPaused then
          FEmulation.Pause;
        {$ENDIF}
        SyncActivity;
        SetStatus(' - ' + FRomDisplayName);
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
    if FEmulation <> nil then
      FEmulation.SetKeyState(Code, True);
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
    if FEmulation <> nil then
      FEmulation.SetKeyState(Code, False);
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
    FEmulation.Pause;
  FormDeactivate(Self);
  SetStatus(' - Stopped after error - ' + FRomDisplayName);
  SyncActivity;
end;

procedure TFormMain.LoadRom(const FileName: string; const DisplayName: string);
begin
  // Construct first: an invalid ROM leaves the current worker running.
  var NewEmulation: IEmulationCore;
  NewEmulation := CreateEmulationCore(FileName);
  try
    if FEmulation <> nil then
      FEmulation.Stop;
  except
    NewEmulation := nil;
    raise;
  end;
  if FGamepad <> nil then
    FGamepad.ReleaseAll;
  if FSuborKeyboard <> nil then
    FSuborKeyboard.ReleaseAll;
  TimerUpdate.Enabled := False;
  FEmulation := nil; // Join before replacing the session.
  FEmulation := NewEmulation;
  ImageCanvas.DisableInterpolation := SameText(FEmulation.Config.Filter, 'nearest');
  {$IFNDEF ANDROID}
  ResizeClientArea;
  {$ENDIF}
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
      FEmulation.Pause;
    {$ENDIF}
    FEmulation.Start;
    SyncActivity;
    SetStatus(' - ' + FEmulation.Name + ' - ' + FRomDisplayName);
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
    Dialog.Filter := 'Console ROM (*.nes;*.gb;*.gbc)|*.nes;*.gb;*.gbc|NES ROM (*.nes)|*.nes|Game Boy ROM (*.gb;*.gbc)|*.gb;*.gbc';
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
  var ErrorText := FEmulation.TakeError;
  if (ErrorText <> '') and not FEmulationFaulted then
  begin
    StopOnError;
    raise Exception.Create(ErrorText);
  end;
  var Frame: TEmulatorFrame;
  var NewFrame := FEmulation.TryGetFrame(Frame);
  if not FEmulationFaulted and NewFrame then
  begin
    var NewCaption := Format('- %s - %.1f FPS', [FEmulation.Name, Frame.FramesPerSecond]);
    if Caption <> NewCaption then
      SetStatus(NewCaption);
  end;
  if not NewFrame then
    Exit;
  if (ImageCanvas.Bitmap.Width <> Frame.Width) or
    (ImageCanvas.Bitmap.Height <> Frame.Height) then
    ImageCanvas.Bitmap.SetSize(Frame.Width, Frame.Height);
  var Data: TBitmapData;
  if ImageCanvas.Bitmap.Map(TMapAccess.Write, Data) then
  try
    for var Y := 0 to Frame.Height - 1 do
      for var X := 0 to Frame.Width - 1 do
        Data.SetPixel(X, Y, Frame.Pixels[Y * Frame.Width + X]);
  finally
    ImageCanvas.Bitmap.Unmap(Data);
  end;
  ImageCanvas.Repaint;
end;

end.

