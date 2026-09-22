unit NES.Mapper.Factory;

interface

uses
  NES.Types, NES.Mapper;

function CreateExtendedMapper(MapperId: Integer; const Prg, Chr: TByteArray; HasChrRam: Boolean; MirrorMode: TMirrorMode; LegacyHeader: Boolean = False): TMapper;

implementation

uses
  NES.Mapper.Discrete, NES.Mapper.MmcLatch, NES.Mapper.Mmc3Variants,
  NES.Mapper.Vrc, NES.Mapper.Sunsoft, NES.Mapper.Rambo, NES.Mapper.Cony,
  NES.Mapper.Bandai, NES.Mapper.Jy, NES.Mapper.Mmc5;

function CreateExtendedMapper(MapperId: Integer; const Prg, Chr: TByteArray; HasChrRam: Boolean; MirrorMode: TMirrorMode; LegacyHeader: Boolean): TMapper;
begin
  case MapperId of
    5:
      Result := TMapperMmc5.Create(Prg, Chr, HasChrRam, MirrorMode);
    16, 159:
      Result := TMapperBandai.Create(MapperId = 159, Prg, Chr, HasChrRam, MirrorMode);
    90, 209:
      Result := TMapperJy.Create(MapperId, Prg, Chr, HasChrRam, MirrorMode);
    8, 13, 15, 32, 34, 70, 71, 79, 87, 88, 99, 112, 113, 144, 152, 154, 206, 228, 232, 240, 242:
      Result := TMapperDiscrete.Create(MapperId, Prg, Chr, HasChrRam, MirrorMode, LegacyHeader);
    9, 10:
      Result := TMapperMmcLatch.Create(MapperId = 10, Prg, Chr, HasChrRam, MirrorMode);
    12, 91, 119, 245, 250:
      Result := TMapperMmc3Variant.Create(MapperId, Prg, Chr, HasChrRam, MirrorMode);
    22, 23, 25:
      Result := TMapperVrc.Create(MapperId, Prg, Chr, HasChrRam, MirrorMode);
    68, 69:
      Result := TMapperSunsoft.Create(MapperId, Prg, Chr, HasChrRam, MirrorMode);
    64:
      Result := TMapperRambo.Create(Prg, Chr, HasChrRam, MirrorMode);
    83:
      Result := TMapperCony.Create(Prg, Chr, HasChrRam, MirrorMode);
  else
    Result := nil;
  end;
end;

end.

