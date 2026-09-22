unit NES.RomMetadata;

interface

uses
  NES.Types;

function ResolveLegacyMapper(Declared: Integer; const Prg, Chr: NES.Types.TByteArray): Integer;

function PrepareLegacyRom(Declared: Integer; var Prg: NES.Types.TByteArray;
  const Chr: NES.Types.TByteArray): string;

implementation

uses
  System.Hash, System.SysUtils;

function PayloadHash(const Prg, Chr: NES.Types.TByteArray): string;
begin
  var Hash := THashSHA1.Create;
  if Length(Prg) > 0 then Hash.Update(Prg[0], Length(Prg));
  if Length(Chr) > 0 then Hash.Update(Chr[0], Length(Chr));
  Result := Hash.HashAsString;
end;

function PrepareLegacyRom(Declared: Integer; var Prg: NES.Types.TByteArray;
  const Chr: NES.Types.TByteArray): string;
const
  DW4_OVERSIZED_SHA1 = 'da46fbf0d3bd89d3b3d3c9ff782b3357e2f6b638';
  DW4_VERIFIED_SHA1 = '1b3dc265ba0d7e4b2cef9b3f8b0be0847df67c3c';
begin
  Result := '';
  if not (Declared in [1, 3, 4]) then Exit;
  var Digest := PayloadHash(Prg, Chr);
  if (Declared = 1) and (Length(Prg) = $100000) and (Length(Chr) = 0) and
    SameText(Digest, DW4_OVERSIZED_SHA1) then
  begin
    var Restored: NES.Types.TByteArray;
    SetLength(Restored, $80000);
    // The old dump duplicates A18 differently depending on A12. Select the
    // original 4-KB pages; no program bytes are synthesized or patched.
    for var page := 0 to 127 do
    begin
      var SourcePage := page;
      if (page and 1) <> 0 then SourcePage := (page and $3F) or ((page and $40) shl 1);
      for var offset := 0 to $FFF do Restored[page * $1000 + offset] := Prg[SourcePage * $1000 + offset];
    end;
    if not SameText(PayloadHash(Restored, nil), DW4_VERIFIED_SHA1) then
      raise ENesException.Create('Dragon Warrior IV recovery failed SHA-1 verification');
    Prg := Restored;
    Exit('Recovered the legacy 1-MB Dragon Warrior IV dump as verified 512-KB SUROM (SHA-1 '
      + DW4_VERIFIED_SHA1 + '). Source file unchanged.');
  end;
  if (Declared = 4) and SameText(Digest, '91aac682c5f05c4bbab037c6371ac84eb4067d76') then
    raise ENesException.Create('Damaged ROM dump: Bugs Bunny Birthday Bash prototype (Bugs Bunny 2). '
      + 'This known bad image contains corrupted program bytes and halts at PC=$60C3. '
      + 'Use a verified clean dump of the prototype.');
  if (Declared = 3) and SameText(Digest, '077a47e48770dfd03adc2db7bf1938e35d163b75') then
    raise ENesException.Create('Damaged ROM dump: Family Fun Fitness Stadium Events. '
      + 'Corrupted PRG instruction stream reaches KIL/JAM at PC=$8023. Use a verified clean dump.');
  if (Declared = 3) and SameText(Digest, 'a60752d90c50e3ddd74e9414ab97500286be9c86') then
    raise ENesException.Create('Damaged ROM dump: TwinBee. '
      + 'The startup return points to KIL/JAM at PC=$8062 in fixed PRG ROM. Use a verified clean dump.');
end;

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

