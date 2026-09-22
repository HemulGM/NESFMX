unit NES.Mapper;

interface

uses
  NES.Types;

const
  MAPPER_NROM = 0;
  MAPPER_MMC1 = 1;
  MAPPER_UXROM = 2;
  MAPPER_CNROM = 3;
  MAPPER_MMC3 = 4;
  MAPPER_AXROM = 7;
  MAPPER_COLOR_DREAMS = 11;
  MAPPER_GXROM = 66;

type
  TMirrorMode = (mmHorizontal, mmVertical, mmSingle0, mmSingle1, mmFourScreen);

  TMapper = class
  protected
    class procedure ValidateMemory(const PrgRom, ChrData: TByteArray); static;
  public
    function CpuRead(Address: UInt16; out Value: UInt8): Boolean; virtual; abstract;
    function CpuWrite(Address: UInt16; Value: UInt8): Boolean; virtual; abstract;
    function CpuWriteTimed(Address: UInt16; Value: UInt8; CpuCycle: UInt64): Boolean; virtual;
    function PpuRead(Address: UInt16; out Value: UInt8): Boolean; virtual; abstract;
    function PpuWrite(Address: UInt16; Value: UInt8): Boolean; virtual; abstract;
    function GetMirrorMode: TMirrorMode; virtual; abstract;
    procedure ClockPpuAddress(Address: UInt16; PpuCycle: UInt64); virtual;
    procedure ClockCpu; virtual;
    procedure ClockCpuWrite; virtual;
    procedure ClockPpuRead; virtual;
    procedure ClockScanline(Line: Integer; Rendering: Boolean); virtual;
    procedure SetPpuFetchKind(Sprite: Boolean; X, Y: Integer); virtual;
    procedure SetPpuControl(Value: UInt8); virtual;
    function IrqPending: Boolean; virtual;
    procedure Reset; virtual; abstract;
  end;

implementation

procedure TMapper.ClockCpu;
begin
end;

procedure TMapper.ClockCpuWrite;
begin
end;

procedure TMapper.ClockPpuRead;
begin
end;

procedure TMapper.ClockScanline(Line: Integer; Rendering: Boolean);
begin
end;

procedure TMapper.SetPpuFetchKind(Sprite: Boolean; X, Y: Integer);
begin
end;

procedure TMapper.SetPpuControl(Value: UInt8);
begin
end;

class procedure TMapper.ValidateMemory(const PrgRom, ChrData: TByteArray);
begin
  if (Length(PrgRom) = 0) or ((Length(PrgRom) mod $4000) <> 0) then
    raise ENesException.Create('PRG ROM must contain complete 16 KB banks');
  if (Length(ChrData) mod $2000) <> 0 then
    raise ENesException.Create('CHR data must contain complete 8 KB banks');
end;

procedure TMapper.ClockPpuAddress(Address: UInt16; PpuCycle: UInt64);
begin
end;

function TMapper.IrqPending: Boolean;
begin
  Result := False;
end;

function TMapper.CpuWriteTimed(Address: UInt16; Value: UInt8; CpuCycle: UInt64): Boolean;
begin
  Result := CpuWrite(Address, Value);
end;

end.
