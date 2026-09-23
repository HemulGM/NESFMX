unit NES.Emulation;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, NES.Types, NES.Console,
  NES.Input, NES.Audio, NES.AudioDiagnostics, NES.Controller;

type
  TEmulationStatus = record
    Region: TNesRegion;
    FrameNumber: UInt64;
    FramesPerSecond: Double;
    AudioQueue: TAudioQueueState;
    AudioError, Error: string;
  end;

  // The core and audio backend belong to Execute after Start. The UI only exchanges
  // input, commands and completed frame copies through FLock; it never runs NES code.
  TNesEmulationThread = class(TThread)
  private
    FConsole: TNesConsole;
    FAudio: TNesAudio;
    FDiagnostics: TAudioDiagnostics;
    FInput: TNesInput;
    FLock: TCriticalSection;
    FWake: TEvent;
    FRomPath: string;
    FSaveDirectory: string;
    FSnapshotDirectory: string;
    FSnapshotLock: TCriticalSection;
    FSnapshotDone: TEvent;
    FSnapshotPending, FSnapshotLoading: Boolean;
    FSnapshotName, FSnapshotError: string;
    FPowerPad: array[1..4] of Boolean;
    FResetRequested, FPauseRequested, FResumeRequested: Boolean;
    FFrame: TFrameBuffer;
    FFramePending: Boolean;
    FStatus: TEmulationStatus;
    procedure RunEmulation;
    procedure SnapshotCommand(const Name: string; Loading: Boolean);
    function ProcessSnapshot: Boolean;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    // Validates the ROM before replacing the current session. Call Start once.
    constructor Create(const FileName: string; FourScoreEnabled: Boolean = False; RegionOverride: TRegionOverride = TRegionOverride.Auto; const SaveDirectory: string = '');
    destructor Destroy; override;
    procedure StopAndSave;
    procedure SetKey(Code: UInt32; Pressed: Boolean; const Keys, Keys2: TKeyMap); overload;
    procedure SetKey(Code: UInt32; Pressed: Boolean; const Keys, Keys2, Keys3, Keys4: TKeyMap); overload;
    procedure ClearInput;
    procedure SetButtons(Source: UInt32; Player: Integer; const Buttons: TNesButtons);
    procedure RequestReset;
    procedure RequestPause;
    procedure RequestResume;
    function TakeSnapshot(var Frame: TFrameBuffer; out Status: TEmulationStatus): Boolean;
    procedure SaveDiagnostics(const Prefix: string);
    // Synchronous commands executed by the worker at a frame boundary.
    procedure SaveSnapshot(const Name: string);
    procedure LoadSnapshot(const Name: string);
    property SnapshotDirectory: string read FSnapshotDirectory;
  end;

implementation

uses
  System.Diagnostics, System.Math, System.IOUtils, NES.Consts, NES.SavePaths;

constructor TNesEmulationThread.Create(const FileName: string; FourScoreEnabled: Boolean; RegionOverride: TRegionOverride; const SaveDirectory: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FSnapshotLock := TCriticalSection.Create;
  FSnapshotDone := TEvent.Create(nil, True, False, '');
  FWake := TEvent.Create(nil, False, False, '');
  FInput := TNesInput.Create;
  FDiagnostics := TAudioDiagnostics.Create;
  FRomPath := FileName;
  FSaveDirectory := SaveDirectory;
  if FSaveDirectory = '' then
    FSaveDirectory := TPath.Combine(TPath.Combine(TPath.GetDocumentsPath, 'NESFMX'), 'Saves');
  FConsole := TNesConsole.Create(FourScoreEnabled);
  FConsole.LoadRom(FileName, RegionOverride);
  FSnapshotDirectory := ResolveGameSavePath(TPath.Combine(
      ExtractFileDir(ExcludeTrailingPathDelimiter(FSaveDirectory)), 'snapshots'),
    FileName, FConsole.RomIdentity, '');
  FStatus.Region := FConsole.Region;
  FConsole.Apu.SetSampleRate(NES_SAMPLE_RATE);
end;

procedure TNesEmulationThread.StopAndSave;
begin
  Terminate;
  if Suspended then
    Start;
  WaitFor;
  // Retry on the caller after joining, propagating any disk error to the UI.
  // Execute's final save also covers owners that just destroy the thread.
  FConsole.SaveBattery;
end;

destructor TNesEmulationThread.Destroy;
begin
  // TThread.Destroy also handles a suspended thread / failed constructor.
  // Wake first, and join before freeing anything Execute can still access.
  Terminate;
  inherited;
  FConsole.Free;
  FDiagnostics.Free;
  FInput.Free;
  FWake.Free;
  FLock.Free;
  FSnapshotDone.Free;
  FSnapshotLock.Free;
end;

procedure TNesEmulationThread.SaveSnapshot(const Name: string);
begin
  SnapshotCommand(Name, False);
end;

procedure TNesEmulationThread.LoadSnapshot(const Name: string);
begin
  SnapshotCommand(Name, True);
end;

procedure TNesEmulationThread.SnapshotCommand(const Name: string; Loading: Boolean);
begin
  // Restrict names to portable slot names; callers cannot escape the game folder.
  if (Name = '') or (Length(Name) > 80) then
    raise EArgumentException.Create('Invalid snapshot name');
  for var C in Name do
    if not CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) then
      raise EArgumentException.Create('Snapshot names use letters, digits, - and _');
  FSnapshotLock.Enter;
  try
    if Suspended or Terminated or Finished then
      raise ENesException.Create('Emulation worker is not running');
    FLock.Enter;
    try
      FSnapshotDone.ResetEvent;
      FSnapshotName := Name;
      FSnapshotLoading := Loading;
      FSnapshotError := '';
      FSnapshotPending := True;
    finally
      FLock.Leave;
    end;
    FWake.SetEvent;
    while FSnapshotDone.WaitFor(50) <> wrSignaled do
      if Finished then
        raise ENesException.Create('Emulation stopped before completing the snapshot');
    FLock.Enter;
    try
      if FSnapshotError <> '' then
        raise ENesException.Create(FSnapshotError);
    finally
      FLock.Leave;
    end;
  finally
    FSnapshotLock.Leave;
  end;
end;

function TNesEmulationThread.ProcessSnapshot: Boolean;
begin
  Result := False;
  var Name: string;
  var Loading: Boolean;
  FLock.Enter;
  try
    if not FSnapshotPending then
      Exit;
    Name := FSnapshotName;
    Loading := FSnapshotLoading;
    FSnapshotPending := False;
  finally
    FLock.Leave;
  end;
  var ErrorText := '';
  try
    var Path := TPath.Combine(FSnapshotDirectory, Name + '.snapshot');
    if Loading then
    begin
      FConsole.LoadSnapshot(Path);
      FAudio.Clear;
      FLock.Enter;
      try
        FDiagnostics.Clear;
        FFrame := FConsole.Ppu.Frame;
        FFramePending := True;
        FStatus.Error := '';
      finally
        FLock.Leave;
      end;
      Result := True;
    end
    else
      FConsole.SaveSnapshot(Path);
  except
    on E: Exception do
      ErrorText := E.Message;
  end;
  FLock.Enter;
  try
    FSnapshotError := ErrorText;
  finally
    FLock.Leave;
  end;
  FSnapshotDone.SetEvent;
end;

procedure TNesEmulationThread.TerminatedSet;
begin
  inherited;
  if FWake <> nil then
    FWake.SetEvent;
end;

procedure TNesEmulationThread.SetKey(Code: UInt32; Pressed: Boolean; const Keys, Keys2: TKeyMap);
begin
  SetKey(Code, Pressed, Keys, Keys2, Default(TKeyMap), Default(TKeyMap));
end;

procedure TNesEmulationThread.SetKey(Code: UInt32; Pressed: Boolean; const Keys, Keys2, Keys3, Keys4: TKeyMap);
begin
  if Code = 0 then
    Exit;
  FLock.Enter;
  try
    FInput.SetKey(1, Code, Pressed, Keys);
    FInput.SetKey(2, Code, Pressed, Keys2);
    FInput.SetKey(3, Code, Pressed, Keys3);
    FInput.SetKey(4, Code, Pressed, Keys4);
    if Code = Keys.A then
      FPowerPad[1] := Pressed;
    if Code = Keys.B then
      FPowerPad[2] := Pressed;
    if Code = Keys.Left then
      FPowerPad[3] := Pressed;
    if Code = Keys.Right then
      FPowerPad[4] := Pressed;
  finally
    FLock.Leave;
  end;
end;

procedure TNesEmulationThread.ClearInput;
begin
  FLock.Enter;
  try
    FInput.Clear;
    FillChar(FPowerPad, SizeOf(FPowerPad), 0);
  finally
    FLock.Leave;
  end;
end;

procedure TNesEmulationThread.SetButtons(Source: UInt32; Player: Integer; const Buttons: TNesButtons);
begin
  FLock.Enter;
  try
    for var Button := Low(TNesButton) to High(TNesButton) do
      FInput.SetButton(Source, Player, Button, Button in Buttons);
  finally
    FLock.Leave;
  end;
end;

procedure TNesEmulationThread.RequestReset;
begin
  FLock.Enter;
  try
    FResetRequested := True;
    FPauseRequested := False;
    FResumeRequested := False;
    FStatus.Error := '';
    FFramePending := False;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

procedure TNesEmulationThread.RequestPause;
begin
  FLock.Enter;
  try
    FPauseRequested := True;
    FResumeRequested := False;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

procedure TNesEmulationThread.RequestResume;
begin
  FLock.Enter;
  try
    FResumeRequested := True;
    FPauseRequested := False;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

function TNesEmulationThread.TakeSnapshot(var Frame: TFrameBuffer; out Status: TEmulationStatus): Boolean;
begin
  FLock.Enter;
  try
    Status := FStatus;
    Result := FFramePending;
    if Result then
    begin
      Frame := FFrame;
      FFramePending := False;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNesEmulationThread.SaveDiagnostics(const Prefix: string);
begin
  var Snapshot: TAudioDiagnostics;
  var AudioError: string;
  FLock.Enter;
  try
    Snapshot := FDiagnostics.Clone;
    AudioError := FStatus.AudioError;
  finally
    FLock.Leave;
  end;
  try
    // File I/O never blocks the emulation thread.
    Snapshot.Save(Prefix, FRomPath, AudioError);
  finally
    Snapshot.Free;
  end;
end;

procedure TNesEmulationThread.Execute;
begin
  if Terminated then
    Exit;
  try
    FConsole.LoadBattery(FSaveDirectory);
    try
      // Native backends may require initialization and teardown on the same thread.
      FAudio := TNesAudio.Create;
      try
        FLock.Enter;
        try
          FStatus.AudioError := FAudio.Error;
          FStatus.AudioQueue := FAudio.QueueState;
        finally
          FLock.Leave;
        end;
        RunEmulation;
      finally
        FreeAndNil(FAudio);
      end;
    finally
      FConsole.SaveBattery;
    end;
  except
    on E: Exception do
    begin
      FLock.Enter;
      try
        FStatus.Error := E.Message;
      finally
        FLock.Leave;
      end;
    end;
  end;
end;

procedure TNesEmulationThread.RunEmulation;
begin
  var Samples: array[0..AUDIO_BLOCK_SAMPLES - 1] of SmallInt;
  var FramePeriod := Round(TStopwatch.Frequency / FrameRate(FConsole.Region));
  var NextFrame := TStopwatch.GetTimeStamp;
  var FpsStart := NextFrame;
  var Frames := 0;
  var Paused := False;
  var Failed := False;
  var NextSave := TStopwatch.GetTimeStamp + TStopwatch.Frequency * 5;
  while not Terminated do
  begin
    try
      if ProcessSnapshot then
      begin
        NextFrame := TStopwatch.GetTimeStamp;
        FpsStart := NextFrame;
        Frames := 0;
        if Failed then
          Paused := False;
        Failed := False;
      end;
      var ResetRequested: Boolean;
      var PauseRequested: Boolean;
      var ResumeRequested: Boolean;
      FLock.Enter;
      try
        ResetRequested := FResetRequested;
        FResetRequested := False;
        PauseRequested := FPauseRequested;
        FPauseRequested := False;
        ResumeRequested := FResumeRequested;
        FResumeRequested := False;
        FInput.Apply(1, FConsole.Controller1);
        FInput.Apply(2, FConsole.Controller2);
        FInput.Apply(3, FConsole.Controller3);
        FInput.Apply(4, FConsole.Controller4);
        for var Button := Low(FPowerPad) to High(FPowerPad) do
          FConsole.Controller2.SetPowerPadButton(Button, FPowerPad[Button]);
      finally
        FLock.Leave;
      end;
      if ResetRequested then
      begin
        FAudio.Clear;
        FConsole.Reset;
        FLock.Enter;
        try
          FDiagnostics.Clear;
          FStatus := Default(TEmulationStatus);
          FStatus.Region := FConsole.Region;
          FStatus.AudioError := FAudio.Error;
          FFramePending := False;
        finally
          FLock.Leave;
        end;
        NextFrame := TStopwatch.GetTimeStamp;
        FpsStart := NextFrame;
        Frames := 0;
        Paused := False;
        Failed := False;
      end;
      if ResumeRequested and Paused and not Failed then
      begin
        Paused := False;
        NextFrame := TStopwatch.GetTimeStamp;
        FpsStart := NextFrame;
        Frames := 0;
      end;
      if PauseRequested then
      begin
        FAudio.Clear;
        Paused := True;
        FConsole.SaveBattery;
      end;
      if Paused then
      begin
        FWake.WaitFor(INFINITE);
        Continue;
      end;
      var ClockNow := TStopwatch.GetTimeStamp;
      if ClockNow < NextFrame then
      begin
        FWake.WaitFor(Cardinal(Max(Int64(1), (NextFrame - ClockNow) * 1000 div TStopwatch.Frequency)));
        Continue;
      end;
      if Terminated then
        Break;
      FConsole.RunFrame;
      var Count: Integer;
      repeat
        Count := FConsole.Apu.PopSamples(Samples);
        if Count > 0 then
        begin
          FAudio.Submit(Samples, Count);
          FLock.Enter;
          try
            FDiagnostics.Capture(FConsole, FAudio, Samples, Count);
          finally
            FLock.Leave;
          end;
        end;
      until Count = 0;
      Inc(Frames);
      ClockNow := TStopwatch.GetTimeStamp;
      if ClockNow >= NextSave then
      begin
        FConsole.SaveBattery;
        NextSave := ClockNow + TStopwatch.Frequency * 5;
      end;
      FLock.Enter;
      try
        // One bounded mailbox: a slow UI skips old frames instead of queuing them.
        FFrame := FConsole.Ppu.Frame;
        FFramePending := True;
        Inc(FStatus.FrameNumber);
        FStatus.AudioError := FAudio.Error;
        FStatus.AudioQueue := FAudio.QueueState;
        if ClockNow - FpsStart >= TStopwatch.Frequency then
        begin
          FStatus.FramesPerSecond := Frames * TStopwatch.Frequency / (ClockNow - FpsStart);
          Frames := 0;
          FpsStart := ClockNow;
        end;
      finally
        FLock.Leave;
      end;
      Inc(NextFrame, FramePeriod);
      // Bound catch-up after debugging or an unusually slow frame.
      if ClockNow - NextFrame > FramePeriod * 3 then
        NextFrame := ClockNow + FramePeriod;
    except
      on E: Exception do
      begin
        FAudio.Clear;
        Paused := True;
        FLock.Enter;
        Failed := True;
        try
          // A reset submitted during the failed frame supersedes its error.
          if not FResetRequested then
            FStatus.Error := E.Message;
        finally
          FLock.Leave;
        end;
      end;
    end;
  end;
end;

end.

