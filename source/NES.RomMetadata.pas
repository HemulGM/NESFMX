unit NES.RomMetadata;

interface

uses
  NES.Types;

function ResolveLegacyMapper(Declared: Integer; const Prg, Chr: NES.Types.TByteArray): Integer;

implementation

uses
  System.Hash, System.SysUtils;

type
  TMapperIdentity = record
    Declared, Actual: Integer;
    Sha1: string;
  end;

const
  MAPPER_IDENTITIES: array[0..10] of TMapperIdentity = (
    (Declared: 2; Actual: 1; Sha1: '5b05c8859f356013d37f0545f5de5fa1693da5da'),
    (Declared: 2; Actual: 206; Sha1: '881b6413fbcbfb9a0308583f0510c09283a72d2a'),
    (Declared: 70; Actual: 152; Sha1: '627d4f20667eded6f26a379c8477669348f3ecab'),
    (Declared: 88; Actual: 154; Sha1: 'ce34b12a46ae8d4432d06f461342f729e8be35e6'),
    (Declared: 16; Actual: 159; Sha1: '4037db53d45db20e3a131d722dcd317adc966deb'),
    (Declared: 8; Actual: 79; Sha1: '04e42ef95de5c857c560b67743310f8777980745'),
    (Declared: 15; Actual: 0; Sha1: 'efe9dd039206c59420ecd58436ef0cd8e640e30c'),
    (Declared: 71; Actual: 232; Sha1: '6f288136923adfa0b1dc7c5ca5782bf0892dfce1'),
    (Declared: 90; Actual: 209; Sha1: '2e0889131da5ba9505a15b94887113f4360d98cd'),
    (Declared: 12; Actual: 13; Sha1: '3e24edd8c06713b775eaa66f3468f71693a542a9'),
    (Declared: 11; Actual: 144; Sha1: '80cd18bb63a5b52b1f3ad36c9191845eb29dd807'));

function ResolveLegacyMapper(Declared: Integer; const Prg, Chr: NES.Types.TByteArray): Integer;
begin
  Result := Declared;
  var Relevant := False;
  for var entry in MAPPER_IDENTITIES do
    Relevant := Relevant or (entry.Declared = Declared);
  if not Relevant or (Length(Prg) = 0) then
    Exit;
  var Hash := THashSHA1.Create;
  Hash.Update(Prg[0], Length(Prg));
  if Length(Chr) > 0 then
    Hash.Update(Chr[0], Length(Chr));
  var Digest := Hash.HashAsString;
  for var entry in MAPPER_IDENTITIES do
    if (entry.Declared = Declared) and SameText(entry.Sha1, Digest) then
      Exit(entry.Actual);
end;

end.

