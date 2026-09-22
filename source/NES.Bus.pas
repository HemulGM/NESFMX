unit NES.Bus;

interface

uses
  NES.Types, NES.PPU, NES.Cartridge, NES.Controller, NES.APU;

type
  TNesBus = class
  private
    FRam: array[0..$07FF] of UInt8;
    FCartridge: TCartridge;
    FPpu: TPpu;
    FApu: TApu;
    FController1: TController;
    FController2: TController;
    FDmaActive: Boolean;
    FDmaDummy: Boolean;
    FDmaAlign: Boolean;
    FDmaPage: UInt8;
    FDmaAddress: UInt8;
    FDmaData: UInt8;
    FDmaHaveData: Boolean;
    FCpuCycle: UInt64;
  public
    constructor Create;
    procedure Reset;
    procedure Connect(Cartridge: TCartridge; Ppu: TPpu; Apu: TApu; Controller1, Controller2: TController);
    function CpuRead(Address: UInt16): UInt8;
    procedure CpuWrite(Address: UInt16; Value: UInt8);
    function IsDmaActive: Boolean;
    procedure ClockDma(CpuCycleOdd: Boolean);
    function DebugCpuRead(Address: UInt16): UInt8;
    property CpuCycle: UInt64 read FCpuCycle write FCpuCycle;
    property DmaWritePending: Boolean read FDmaHaveData;
  end;

implementation

constructor TNesBus.Create;
begin
  inherited Create;
  for var i := Low(FRam) to High(FRam) do
    FRam[i] := 0;
  FDmaActive := False;
  FDmaDummy := True;
  FDmaAlign := False;
  FDmaPage := 0;
  FDmaAddress := 0;
  FDmaData := 0;
end;

procedure TNesBus.Connect(Cartridge: TCartridge; Ppu: TPpu; Apu: TApu; Controller1, Controller2: TController);
begin
  FCartridge := Cartridge;
  FPpu := Ppu;
  FApu := Apu;
  FController1 := Controller1;
  FController2 := Controller2;
end;

function TNesBus.CpuRead(Address: UInt16): UInt8;
begin
  var Value: UInt8;
  if Address < $2000 then
    Exit(FRam[Address and $07FF]);
  if Address < $4000 then
    Exit(FPpu.CpuRead($2000 or (Address and 7)));

  case Address of
    $4015:
      Exit(FApu.CpuReadStatus);
    $4016:
      Exit(FController1.Read);
    $4017:
      Exit(FController2.Read);
  end;

  if (FCartridge <> nil) and (FCartridge.Mapper <> nil) and FCartridge.Mapper.CpuRead(Address, Value) then
    Exit(Value);
  Result := 0;
end;

procedure TNesBus.CpuWrite(Address: UInt16; Value: UInt8);
begin
  if (FCartridge <> nil) and (FCartridge.Mapper <> nil) then
    FCartridge.Mapper.ClockCpuWrite;
  if Address < $2000 then
  begin
    FRam[Address and $07FF] := Value;
    Exit;
  end;
  if Address < $4000 then
  begin
    FPpu.CpuWrite($2000 or (Address and 7), Value);
    Exit;
  end;

  case Address of
    $4000..$4013, $4015, $4017:
      begin
        FApu.CpuWrite(Address, Value);
        if Address = $4016 then
        begin
          FController1.Write(Value);
          FController2.Write(Value);
        end;
        Exit;
      end;
    $4014:
      begin
        FDmaPage := Value;
        FDmaAddress := 0;
        FDmaDummy := True;
        FDmaAlign := False;
        FDmaActive := True;
        FDmaHaveData := False;
        Exit;
      end;
    $4016:
      begin
        FController1.Write(Value);
        FController2.Write(Value);
        if (FCartridge <> nil) and (FCartridge.Mapper <> nil) then
          FCartridge.Mapper.CpuWriteTimed(Address, Value, FCpuCycle);
        Exit;
      end;
  end;

  if (FCartridge <> nil) and (FCartridge.Mapper <> nil) and FCartridge.Mapper.CpuWriteTimed(Address, Value, FCpuCycle) then
    Exit;
end;

function TNesBus.IsDmaActive: Boolean;
begin
  Result := FDmaActive;
end;

procedure TNesBus.ClockDma(CpuCycleOdd: Boolean);
begin
  if not FDmaActive then
    Exit;

  if FDmaDummy then
  begin
    FDmaDummy := False;
    FDmaAlign := CpuCycleOdd;
    Exit;
  end;

  if FDmaAlign then
  begin
    FDmaAlign := False;
    Exit;
  end;

  if CpuCycleOdd then
  begin
    FDmaData := CpuRead((UInt16(FDmaPage) shl 8) or FDmaAddress);
    FDmaHaveData := True;
  end
  else if FDmaHaveData then
  begin
    FDmaHaveData := False;
    FPpu.WriteOamDma(FDmaAddress, FDmaData);
    FDmaAddress := (FDmaAddress + 1) and $FF;
    if FDmaAddress = 0 then
    begin
      FDmaActive := False;
      FDmaDummy := True;
      FDmaAlign := False;
    end;
  end;
end;

procedure TNesBus.Reset;
begin
  FDmaActive := False;
  FDmaDummy := True;
  FDmaAlign := False;
  FDmaHaveData := False;
  FCpuCycle := 0;
end;

function TNesBus.DebugCpuRead(Address: UInt16): UInt8;
begin
  Result := CpuRead(Address);
end;

end.

