unit NES.Console;

interface

uses
  System.SysUtils, NES.Types, NES.CPU, NES.PPU, NES.APU, NES.Bus, NES.Cartridge,
  NES.Controller;

type
  TNesConsole = class
  private
    FCpu: TCpu6502;
    FPpu: TPpu;
    FApu: TApu;
    FBus: TNesBus;
    FCartridge: TCartridge;
    FController1: TController;
    FController2: TController;
    FController3: TController;
    FController4: TController;
    FMasterClock: UInt64;
    FDmcDmaCycles: Integer;
  public
    constructor Create(FourScoreEnabled: Boolean = False);
    destructor Destroy; override;
    procedure LoadRom(const FileName: string);
    procedure Reset;
    procedure Clock;
    procedure RunFrame;
    procedure CheckCpuState;
    function HasCartridge: Boolean;
    function DebugCpuRead(Address: UInt16): UInt8;
    procedure DebugWriteRam(Address: UInt16; Value: UInt8);
    property Cpu: TCpu6502 read FCpu;
    property Ppu: TPpu read FPpu;
    property Apu: TApu read FApu;
    property Controller1: TController read FController1;
    property Controller2: TController read FController2;
    property Controller3: TController read FController3;
    property Controller4: TController read FController4;
  end;

implementation

constructor TNesConsole.Create(FourScoreEnabled: Boolean);
begin
  inherited Create;
  FCpu := TCpu6502.Create;
  FPpu := TPpu.Create;
  FApu := TApu.Create;
  FBus := TNesBus.Create;
  FCartridge := TCartridge.Create;
  FController1 := TController.Create;
  FController2 := TController.Create;
  FController3 := TController.Create;
  FController4 := TController.Create;
  FController2.PowerPadEnabled := not FourScoreEnabled;
  FBus.FourScoreEnabled := FourScoreEnabled;
  FBus.Connect(FCartridge, FPpu, FApu, FController1, FController2,
    FController3, FController4);
  FCpu.Connect(FBus.CpuRead, FBus.CpuWrite);
end;

destructor TNesConsole.Destroy;
begin
  FController4.Free;
  FController3.Free;
  FController2.Free;
  FController1.Free;
  FCartridge.Free;
  FBus.Free;
  FApu.Free;
  FPpu.Free;
  FCpu.Free;
  inherited Destroy;
end;

procedure TNesConsole.LoadRom(const FileName: string);
begin
  FCartridge.LoadFromFile(FileName);
  FPpu.ConnectMapper(FCartridge.Mapper);
  Reset;
end;

procedure TNesConsole.Reset;
begin
  if FCartridge.Valid then
    FCartridge.Reset;
  FPpu.Reset;
  FPpu.ConnectMapper(FCartridge.Mapper);
  FApu.Reset;
  FBus.Reset;
  FDmcDmaCycles := 0;
  FCpu.Reset;
  FMasterClock := 0;
end;

procedure TNesConsole.Clock;
begin
  var CanHalt: Boolean;
  FBus.CpuCycle := FMasterClock div 3;
  var CpuOdd: Boolean := (FBus.CpuCycle and 1) <> 0;
  FPpu.Clock;
  FPpu.Clock;
  FPpu.Clock;

  if FPpu.ConsumeNmi then
    FCpu.TriggerNmi;

  FApu.Clock;
  if FCartridge.Mapper <> nil then
    FCartridge.Mapper.ClockCpu;
  FCpu.SetIrqLine(FApu.IrqPending or
    ((FCartridge.Mapper <> nil) and FCartridge.Mapper.IrqPending));

  if FBus.IsDmaActive then
    CanHalt := not FBus.DmaWritePending
  else
    CanHalt := not FCpu.NextCycleIsWrite;
  if (FDmcDmaCycles = 0) and FApu.DmcDmaRequested and CanHalt then
  begin
    // Halt + dummy + optional alignment + get. Get shares OAM's read phase.
    if CpuOdd then
      FDmcDmaCycles := 3
    else
      FDmcDmaCycles := 4;
  end;
  if FDmcDmaCycles > 0 then
  begin
    Dec(FDmcDmaCycles);
    if FDmcDmaCycles = 0 then
      FApu.CompleteDmcDma(FBus.CpuRead(FApu.DmcDmaAddress));
  end
  else if FBus.IsDmaActive and not FCpu.NextCycleIsWrite then
    FBus.ClockDma(CpuOdd)
  else
    FCpu.Clock;

  Inc(FMasterClock, 3);
end;

procedure TNesConsole.RunFrame;
begin
  FPpu.FrameReady := False;
  while not FPpu.FrameReady do
    Clock;
  FPpu.RebuildFrame;
  CheckCpuState;
end;

procedure TNesConsole.CheckCpuState;
begin
  if FCpu.Jammed then
    raise ENesException.CreateFmt('CPU halted: KIL/JAM %s at PC=%s; check ROM data and mapper', [IntToHex(FCpu.JamOpcode, 2), IntToHex(FCpu.JamPc, 4)]);
  if FCpu.UnknownOpcodeCount <> 0 then
    raise ENesException.CreateFmt('Unknown opcode %s at PC=%s', [IntToHex(FCpu.LastUnknownOpcode, 2), IntToHex(FCpu.LastUnknownPc, 4)]);
end;

function TNesConsole.HasCartridge: Boolean;
begin
  Result := FCartridge.Valid;
end;

function TNesConsole.DebugCpuRead(Address: UInt16): UInt8;
begin
  Result := FBus.DebugCpuRead(Address);
end;

procedure TNesConsole.DebugWriteRam(Address: UInt16; Value: UInt8);
begin
  if Address >= $0800 then
    raise EArgumentOutOfRangeException.Create('Diagnostic writes are limited to CPU RAM');
  FBus.CpuWrite(Address, Value);
end;

end.

