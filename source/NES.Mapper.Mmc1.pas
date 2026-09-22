unit NES.Mapper.Mmc1;

interface

uses
  NES.Types, NES.Mapper;

type
  TMapperMmc1 = class(TMapper)
  private
    FPrgRom: TByteArray;
    FChrMemory: TByteArray;
    FPrgRam: array[0..$1FFF] of UInt8;
    FHasChrRam: Boolean;
    FBoardMirrorMode: TMirrorMode;
    FShiftRegister: UInt8;
    FWriteCount: Integer;
    FControl: UInt8;
    FChrBank0: UInt8;
    FChrBank1: UInt8;
    FPrgBank: UInt8;
    FLastWriteCycle: UInt64;
    FHasLastWrite: Boolean;
    function GetPrgBankCount: Integer;
    function GetChrBankCount4K: Integer;
    function MapPrgBank(Bank: Integer): Integer;
    function MapChrBank4K(Bank: Integer): Integer;
  public
    constructor Create(const APrgRom, AChrData: TByteArray; AHasChrRam: Boolean; AMirrorMode: TMirrorMode);
    function CpuRead(Address: UInt16; out Value: UInt8): Boolean; override;
    function CpuWrite(Address: UInt16; Value: UInt8): Boolean; override;
    function CpuWriteTimed(Address: UInt16; Value: UInt8; CpuCycle: UInt64): Boolean; override;
    function PpuRead(Address: UInt16; out Value: UInt8): Boolean; override;
    function PpuWrite(Address: UInt16; Value: UInt8): Boolean; override;
    function GetMirrorMode: TMirrorMode; override;
    procedure Reset; override;
  end;

implementation

constructor TMapperMmc1.Create(const APrgRom, AChrData: TByteArray; AHasChrRam: Boolean; AMirrorMode: TMirrorMode);
begin
  inherited Create;
  ValidateMemory(APrgRom, AChrData);
  FPrgRom := Copy(APrgRom);
  FChrMemory := Copy(AChrData);
  FHasChrRam := AHasChrRam;
  FBoardMirrorMode := AMirrorMode;
  if Length(FChrMemory) = 0 then
    SetLength(FChrMemory, $2000);
  Reset;
end;

function TMapperMmc1.GetPrgBankCount: Integer;
begin
  Result := Length(FPrgRom) div $4000;
  if Result <= 0 then
    Result := 1;
end;

function TMapperMmc1.GetChrBankCount4K: Integer;
begin
  Result := Length(FChrMemory) div $1000;
  if Result <= 0 then
    Result := 1;
end;

function TMapperMmc1.MapPrgBank(Bank: Integer): Integer;
begin
  Result := Bank mod GetPrgBankCount;
  if Result < 0 then
    Inc(Result, GetPrgBankCount);
end;

function TMapperMmc1.MapChrBank4K(Bank: Integer): Integer;
begin
  Result := Bank mod GetChrBankCount4K;
  if Result < 0 then
    Inc(Result, GetChrBankCount4K);
end;

function TMapperMmc1.CpuRead(Address: UInt16; out Value: UInt8): Boolean;
begin
  var Bank16K: Integer;
  var Offset: Integer;
  if (Address >= $6000) and (Address < $8000) then
  begin
    Value := FPrgRam[Address and $1FFF];
    Exit(True);
  end;

  Result := Address >= $8000;
  if not Result then
    Exit;

  var PrgMode: Integer := (FControl shr 2) and 3;
  case PrgMode of
    0, 1:
      begin
        Bank16K := MapPrgBank((FPrgBank and $0E) + ((Address - $8000) div $4000));
        Offset := Bank16K * $4000 + ((Address - $8000) and $3FFF);
      end;
    2:
      begin
        if Address < $C000 then
          Bank16K := 0
        else
          Bank16K := MapPrgBank(FPrgBank and $0F);
        Offset := Bank16K * $4000 + (Address and $3FFF);
      end;
  else
    begin
      if Address < $C000 then
        Bank16K := MapPrgBank(FPrgBank and $0F)
      else
        Bank16K := GetPrgBankCount - 1;
      Offset := Bank16K * $4000 + (Address and $3FFF);
    end;
  end;

  Value := FPrgRom[Offset mod Length(FPrgRom)];
end;

function TMapperMmc1.CpuWrite(Address: UInt16; Value: UInt8): Boolean;
begin
  if (Address >= $6000) and (Address < $8000) then
  begin
    FPrgRam[Address and $1FFF] := Value;
    Exit(True);
  end;

  Result := Address >= $8000;
  if not Result then
    Exit;

  if (Value and $80) <> 0 then
  begin
    FShiftRegister := $10;
    FWriteCount := 0;
    FControl := FControl or $0C;
    Exit;
  end;

  FShiftRegister := (FShiftRegister shr 1) or ((Value and 1) shl 4);
  Inc(FWriteCount);
  if FWriteCount < 5 then
    Exit;

  var RegisterValue: UInt8 := FShiftRegister and $1F;
  case (Address shr 13) and 3 of
    0:
      FControl := RegisterValue;
    1:
      FChrBank0 := RegisterValue;
    2:
      FChrBank1 := RegisterValue;
    3:
      FPrgBank := RegisterValue;
  end;

  FShiftRegister := $10;
  FWriteCount := 0;
end;

function TMapperMmc1.CpuWriteTimed(Address: UInt16; Value: UInt8; CpuCycle: UInt64): Boolean;
begin
  if Address >= $8000 then
  begin
    // MMC1 ignores the second consecutive write of a CPU RMW instruction.
    if FHasLastWrite and (CpuCycle > FLastWriteCycle) and (CpuCycle - FLastWriteCycle = 1) then
      Exit(True);
    FHasLastWrite := True;
    FLastWriteCycle := CpuCycle;
  end;
  Result := CpuWrite(Address, Value);
end;

function TMapperMmc1.PpuRead(Address: UInt16; out Value: UInt8): Boolean;
begin
  var Bank4K: Integer;
  var Offset: Integer;
  Result := Address < $2000;
  if not Result then
    Exit;

  var ChrMode: Integer := (FControl shr 4) and 1;
  if ChrMode = 0 then
  begin
    Bank4K := MapChrBank4K((FChrBank0 and $1E) + (Address div $1000));
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end
  else
  begin
    if Address < $1000 then
      Bank4K := MapChrBank4K(FChrBank0)
    else
      Bank4K := MapChrBank4K(FChrBank1);
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end;

  Value := FChrMemory[Offset mod Length(FChrMemory)];
end;

function TMapperMmc1.PpuWrite(Address: UInt16; Value: UInt8): Boolean;
begin
  var Bank4K: Integer;
  var Offset: Integer;
  Result := (Address < $2000) and FHasChrRam;
  if not Result then
    Exit;

  var ChrMode: Integer := (FControl shr 4) and 1;
  if ChrMode = 0 then
  begin
    Bank4K := MapChrBank4K((FChrBank0 and $1E) + (Address div $1000));
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end
  else
  begin
    if Address < $1000 then
      Bank4K := MapChrBank4K(FChrBank0)
    else
      Bank4K := MapChrBank4K(FChrBank1);
    Offset := Bank4K * $1000 + (Address and $0FFF);
  end;

  FChrMemory[Offset mod Length(FChrMemory)] := Value;
end;

function TMapperMmc1.GetMirrorMode: TMirrorMode;
begin
  if FBoardMirrorMode = mmFourScreen then
    Exit(mmFourScreen);

  case FControl and 3 of
    0:
      Result := mmSingle0;
    1:
      Result := mmSingle1;
    2:
      Result := mmVertical;
  else
    Result := mmHorizontal;
  end;
end;

procedure TMapperMmc1.Reset;
begin
  for var i := Low(FPrgRam) to High(FPrgRam) do
    FPrgRam[i] := 0;
  FShiftRegister := $10;
  FWriteCount := 0;
  FControl := $0C;
  FChrBank0 := 0;
  FChrBank1 := 0;
  FPrgBank := 0;
  FHasLastWrite := False;
  FLastWriteCycle := 0;
end;

end.

