unit NES.Cartridge;

interface

uses
  System.Classes, System.SysUtils, NES.Types, NES.Mapper;

type
  TCartridge = class
  private
    FMapper: TMapper;
    FMapperId: Integer;
    FHeaderMapperId: Integer;
    FValid: Boolean;
  public
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure Reset;
    property Mapper: TMapper read FMapper;
    property MapperId: Integer read FMapperId;
    property HeaderMapperId: Integer read FHeaderMapperId;
    property Valid: Boolean read FValid;
  end;

implementation

uses
  NES.RomMetadata, NES.Mapper.Factory, NES.Mapper.Nrom, NES.Mapper.Mmc1,
  NES.Mapper.Uxrom, NES.Mapper.Cnrom, NES.Mapper.Mmc3, NES.Mapper.Axrom,
  NES.Mapper.Gxrom, NES.Mapper.ColorDreams;

type
  TInesHeader = packed record
    Magic: array[0..3] of AnsiChar;
    PrgRomChunks: UInt8;
    ChrRomChunks: UInt8;
    Flags6: UInt8;
    Flags7: UInt8;
    PrgRamSize: UInt8;
    Flags9: UInt8;
    Flags10: UInt8;
    Zero: array[0..4] of UInt8;
  end;

procedure ReadExact(Stream: TFileStream; var Buffer; Count: Integer);
begin
  if Stream.Read(Buffer, Count) <> Count then
    raise ENesException.Create('Unexpected end of file');
end;

destructor TCartridge.Destroy;
begin
  FMapper.Free;
  inherited Destroy;
end;

procedure TCartridge.LoadFromFile(const FileName: string);
begin
  var Header: TInesHeader;
  var PrgRom: TByteArray;
  var ChrRom: TByteArray;
  var Trainer: TByteArray;
  var Mirror: TMirrorMode;
  var HasTrainer: Boolean;
  var ChrRam: Boolean;
  FreeAndNil(FMapper);
  FValid := False;
  FMapperId := -1;
  FHeaderMapperId := -1;

  var Stream: TFileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    ReadExact(Stream, Header, SizeOf(Header));
    if (Header.Magic[0] <> 'N') or (Header.Magic[1] <> 'E') or (Header.Magic[2] <> 'S') or (Ord(Header.Magic[3]) <> $1A) then
      raise ENesException.Create('Invalid iNES file');

    if (Header.Flags6 and $08) <> 0 then
      Mirror := mmFourScreen
    else if (Header.Flags6 and $01) <> 0 then
      Mirror := mmVertical
    else
      Mirror := mmHorizontal;

    HasTrainer := (Header.Flags6 and $04) <> 0;
    if HasTrainer then
    begin
      SetLength(Trainer, 512);
      ReadExact(Stream, Trainer[0], 512);
    end;

    SetLength(PrgRom, Header.PrgRomChunks * $4000);
    if Length(PrgRom) = 0 then
      raise ENesException.Create('ROM has no PRG data');
    ReadExact(Stream, PrgRom[0], Length(PrgRom));

    SetLength(ChrRom, Header.ChrRomChunks * $2000);
    ChrRam := Length(ChrRom) = 0;
    if Length(ChrRom) > 0 then
      ReadExact(Stream, ChrRom[0], Length(ChrRom));

    FMapperId := ((Header.Flags7 and $F0) or (Header.Flags6 shr 4));
    // Old dumping tools wrote signatures such as "DiskDude!" over bytes
    // 7..15, turning mapper 2 into 66. Preserve genuine NES 2.0 headers.
    if ((Header.Flags7 and $0C) <> $08) and
      ((Header.Zero[1] or Header.Zero[2] or Header.Zero[3] or Header.Zero[4]) <> 0) then
      FMapperId := Header.Flags6 shr 4;
    FHeaderMapperId := FMapperId;
    // Preserve explicit NES 2.0 metadata; legacy corrections require exact payload identity.
    if (Header.Flags7 and $0C) <> $08 then
      FMapperId := ResolveLegacyMapper(FMapperId, PrgRom, ChrRom);
    case FMapperId of
      MAPPER_NROM:
        FMapper := TMapperNrom.Create(PrgRom, ChrRom, ChrRam, Mirror);
      MAPPER_MMC1:
        FMapper := TMapperMmc1.Create(PrgRom, ChrRom, ChrRam, Mirror);
      MAPPER_UXROM:
        FMapper := TMapperUxrom.Create(PrgRom, ChrRom, ChrRam, Mirror);
      MAPPER_CNROM:
        FMapper := TMapperCnrom.Create(PrgRom, ChrRom, ChrRam, Mirror);
      MAPPER_MMC3:
        FMapper := TMapperMmc3.Create(PrgRom, ChrRom, ChrRam, Mirror);
      MAPPER_AXROM:
        FMapper := TMapperAxrom.Create(PrgRom, ChrRom, ChrRam);
      MAPPER_COLOR_DREAMS:
        FMapper := TMapperColorDreams.Create(PrgRom, ChrRom, ChrRam, Mirror);
      MAPPER_GXROM:
        FMapper := TMapperGxrom.Create(PrgRom, ChrRom, ChrRam, Mirror);
    else
      FMapper := CreateExtendedMapper(FMapperId, PrgRom, ChrRom, ChrRam, Mirror,
        (Header.Flags7 and $0C) <> $08);
      if FMapper = nil then
        raise ENesException.CreateFmt('Unsupported mapper: %d', [FMapperId]);
    end;

    FValid := True;
  finally
    Stream.Free;
  end;
end;

procedure TCartridge.Reset;
begin
  if FMapper <> nil then
    FMapper.Reset;
end;

end.

