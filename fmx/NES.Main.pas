unit NES.Main;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IniFiles,
  System.Math, System.Diagnostics, System.IOUtils, FMX.Forms, FMX.Types,
  FMX.Controls, FMX.Objects, FMX.Graphics, FMX.Dialogs, NES.Console,
  NES.Controller, NES.Consts, NES.Types, NES.Audio, NES.AudioDiagnostics;

type
  TKeyMap = record
    A: UInt32;
    B: UInt32;
    Select: UInt32;
    Start: UInt32;
    Up: UInt32;
    Down: UInt32;
    Left: UInt32;
    Right: UInt32;
  end;

  TAppConfig = record
    Scale: Integer;
    Filter: string;
    Keys: TKeyMap;
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
    FConsole: TNesConsole;
    FAudio: TNesAudio;
    FAudioDiagnostics: TAudioDiagnostics;
    FConfig: TAppConfig;
    FRomPath: string;
    FNextFrame, FFpsStart: Int64;
    FFrames: Integer;
    FStarted: Boolean;
    FKeysDown: array[0..255] of Boolean;
    procedure LoadRom(const FileName: string);
    procedure OpenRom;
    procedure ResetClock;
    procedure UpdateFrame;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

  end;

var
  FormMain: TFormMain;

implementation

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
  Result.Filter := 'linear';
  Result.Keys.A := Ord('Z');
  Result.Keys.B := Ord('X');
  Result.Keys.Select := vkSpace;
  Result.Keys.Start := vkReturn;
  Result.Keys.Up := vkUp;
  Result.Keys.Down := vkDown;
  Result.Keys.Left := vkLeft;
  Result.Keys.Right := vkRight;
end;

procedure WriteConfig(const FileName: string; const Config: TAppConfig);
begin
  var Ini: TIniFile := TIniFile.Create(FileName);
  try
    Ini.WriteInteger('Video', 'Scale', Config.Scale);
    Ini.WriteString('Video', 'Filter', Config.Filter);
    Ini.WriteString('Controls', 'A', KeyCodeToName(Config.Keys.A));
    Ini.WriteString('Controls', 'B', KeyCodeToName(Config.Keys.B));
    Ini.WriteString('Controls', 'Select', KeyCodeToName(Config.Keys.Select));
    Ini.WriteString('Controls', 'Start', KeyCodeToName(Config.Keys.Start));
    Ini.WriteString('Controls', 'Up', KeyCodeToName(Config.Keys.Up));
    Ini.WriteString('Controls', 'Down', KeyCodeToName(Config.Keys.Down));
    Ini.WriteString('Controls', 'Left', KeyCodeToName(Config.Keys.Left));
    Ini.WriteString('Controls', 'Right', KeyCodeToName(Config.Keys.Right));
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

    Result.Keys.A := ReadMappedKey(Ini, 'Controls', 'A', Defaults.Keys.A);
    Result.Keys.B := ReadMappedKey(Ini, 'Controls', 'B', Defaults.Keys.B);
    Result.Keys.Select := ReadMappedKey(Ini, 'Controls', 'Select', Defaults.Keys.Select);
    Result.Keys.Start := ReadMappedKey(Ini, 'Controls', 'Start', Defaults.Keys.Start);
    Result.Keys.Up := ReadMappedKey(Ini, 'Controls', 'Up', Defaults.Keys.Up);
    Result.Keys.Down := ReadMappedKey(Ini, 'Controls', 'Down', Defaults.Keys.Down);
    Result.Keys.Left := ReadMappedKey(Ini, 'Controls', 'Left', Defaults.Keys.Left);
    Result.Keys.Right := ReadMappedKey(Ini, 'Controls', 'Right', Defaults.Keys.Right);
  finally
    Ini.Free;
  end;
end;

procedure SetButtonState(Console: TNesConsole; KeySym: UInt32; Pressed: Boolean; const Keys: TKeyMap);
begin
  if KeySym = Keys.A then
    Console.Controller1.SetButton(nbA, Pressed);
  if KeySym = Keys.B then
    Console.Controller1.SetButton(nbB, Pressed);
  if KeySym = Keys.Select then
    Console.Controller1.SetButton(nbSelect, Pressed);
  if KeySym = Keys.Start then
    Console.Controller1.SetButton(nbStart, Pressed);
  if KeySym = Keys.Up then
    Console.Controller1.SetButton(nbUp, Pressed);
  if KeySym = Keys.Down then
    Console.Controller1.SetButton(nbDown, Pressed);
  if KeySym = Keys.Left then
    Console.Controller1.SetButton(nbLeft, Pressed);
  if KeySym = Keys.Right then
    Console.Controller1.SetButton(nbRight, Pressed);
end;

{ TFormMain }

constructor TFormMain.Create(AOwner: TComponent);
begin
  inherited;
  Caption := 'NESFMX - Open ROM: Ctrl+O';
  Position := TFormPosition.ScreenCenter;
  Fill.Color := TAlphaColors.Black;
  FConfig := LoadOrCreateConfig(System.IOUtils.TPath.Combine(ExtractFilePath(ParamStr(0)), 'config.ini'));
  ClientWidth := NES_WIDTH * FConfig.Scale;
  ClientHeight := NES_HEIGHT * FConfig.Scale;
  FConsole := TNesConsole.Create;
  FAudio := TNesAudio.Create;
  FAudioDiagnostics := TAudioDiagnostics.Create;
  ImageCanvas.DisableInterpolation := SameText(FConfig.Filter, 'nearest');
  ImageCanvas.Bitmap.SetSize(NES_WIDTH, NES_HEIGHT);
  ImageCanvas.Bitmap.Clear(TAlphaColors.Black);
end;

destructor TFormMain.Destroy;
begin
  if TimerUpdate <> nil then
    TimerUpdate.Enabled := False;
  FAudioDiagnostics.Free;
  FAudio.Free;
  FConsole.Free;
  inherited;
end;

procedure TFormMain.FormActivate(Sender: TObject);
begin
  ResetClock;
  TimerUpdate.Enabled := FConsole.HasCartridge;
end;

procedure TFormMain.FormDeactivate(Sender: TObject);
begin
  TimerUpdate.Enabled := False;
  FAudio.Clear;
  FillChar(FKeysDown, SizeOf(FKeysDown), 0);
  for var button := Low(TNesButton) to High(TNesButton) do
    FConsole.Controller1.SetButton(button, False);
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
    else if (Code = Ord('R')) and FConsole.HasCartridge then
    begin
      FAudio.Clear;
      FConsole.Reset;
      FAudioDiagnostics.Clear;
      ResetClock;
    end
    else if (Code = vkF5) and FConsole.HasCartridge then
    begin
      UpdateFrame;
      ImageCanvas.Bitmap.SaveToFile(System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetDocumentsPath,
          'screenshot_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + '.png'));
    end
    else if (Code = vkF6) and FConsole.HasCartridge then
    begin
      var DiagnosticPath := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetDocumentsPath,
        'NES-audio-' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
      FormDeactivate(Self);
      try
        FAudioDiagnostics.Save(DiagnosticPath, FRomPath, FAudio.Error);
        UpdateFrame;
        ImageCanvas.Bitmap.SaveToFile(DiagnosticPath + '.png');
        ShowMessage('Audio diagnostics saved: ' + DiagnosticPath + '.csv');
      finally
        FormActivate(Self);
      end;
    end;
  end;
  if not (ssCtrl in Shift) then
    SetButtonState(FConsole, Code, True, FConfig.Keys);
  Key := 0;
  KeyChar := #0;
end;

procedure TFormMain.FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  var Code: Word := EventKey(Key, KeyChar);
  if Code <= High(FKeysDown) then
    FKeysDown[Code] := False;
  SetButtonState(FConsole, Code, False, FConfig.Keys);
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
  if FAudio.Error <> '' then
    ShowMessage('Sound unavailable: ' + FAudio.Error);
end;

procedure TFormMain.TimerUpdateTimer(Sender: TObject);
begin
  var Count: Integer;
  var Samples: array[0..AUDIO_BLOCK_SAMPLES - 1] of SmallInt;
  var ClockNow: Int64 := TStopwatch.GetTimeStamp;
  if ClockNow < FNextFrame then
    Exit;
  var FramePeriod: Int64 := Round(TStopwatch.Frequency * (NES_FRAME_CYCLES - 0.5) / (3.0 * NES_CPU_HZ));
  var CatchUp: Integer := 0;
  try
    repeat
      FConsole.RunFrame;
      repeat
        Count := FConsole.Apu.PopSamples(Samples);
        if Count > 0 then
        begin
          FAudio.Submit(Samples, Count);
          FAudioDiagnostics.Capture(FConsole, FAudio, Samples, Count);
        end;
      until Count = 0;
      Inc(FFrames);
      Inc(CatchUp);
      Inc(FNextFrame, FramePeriod);
    until (FNextFrame > ClockNow) or (CatchUp = 3);
    // Avoid a long blocking catch-up after resizing, debugging or a slow frame.
    if ClockNow - FNextFrame > FramePeriod * 3 then
      FNextFrame := ClockNow + FramePeriod;
    UpdateFrame;
    if ClockNow - FFpsStart >= TStopwatch.Frequency then
    begin
      Caption := Format('NESFMX - %.1f FPS - %s',
        [FFrames * TStopwatch.Frequency / (ClockNow - FFpsStart), ExtractFileName(FRomPath)]);
      if FAudio.Error <> '' then
        Caption := Caption + ' - sound unavailable';
      FFrames := 0;
      FFpsStart := ClockNow;
    end;
  except
    TimerUpdate.Enabled := False;
    FAudio.Clear;
    raise;
  end;
end;

procedure TFormMain.ResetClock;
begin
  FNextFrame := TStopwatch.GetTimeStamp;
  FFpsStart := FNextFrame;
  FFrames := 0;
end;

procedure TFormMain.LoadRom(const FileName: string);
begin
  // Load into a fresh console so an invalid ROM cannot invalidate the running game.
  var NewConsole: TNesConsole := TNesConsole.Create;
  try
    NewConsole.LoadRom(FileName);
    NewConsole.Apu.SetSampleRate(NES_SAMPLE_RATE);
  except
    NewConsole.Free;
    raise;
  end;
  TimerUpdate.Enabled := False;
  FAudio.Clear;
  FAudioDiagnostics.Clear;
  FConsole.Free;
  FConsole := NewConsole;
  FillChar(FKeysDown, SizeOf(FKeysDown), 0);
  FRomPath := FileName;
  Caption := 'NESFMX - ' + ExtractFileName(FRomPath);
  UpdateFrame;
  ResetClock;
  TimerUpdate.Enabled := True;
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
  var Data: TBitmapData;
  if ImageCanvas.Bitmap.Map(TMapAccess.Write, Data) then
  try
    for var y := 0 to NES_HEIGHT - 1 do
      for var x := 0 to NES_WIDTH - 1 do
        Data.SetPixel(x, y, FConsole.Ppu.Frame[x, y] or $FF000000);
  finally
    ImageCanvas.Bitmap.Unmap(Data);
  end;
  ImageCanvas.Repaint;
end;

end.

