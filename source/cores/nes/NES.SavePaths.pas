unit NES.SavePaths;

interface

// An empty extension selects a snapshot directory; '.sav' selects a battery file.
// Existing paths are reused by hash alone, including legacy hash-only names.

function ResolveGameSavePath(const Root, RomFileName, Hash, Extension: string): string;

function ResolveDefaultSaveDirectory(const DocumentsDirectory, HomeDirectory: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils;

function ResolveDefaultSaveDirectory(const DocumentsDirectory, HomeDirectory: string): string;
begin
  // Linux may have no XDG Documents entry. Never turn that into a path
  // relative to the executable: NESFMX can then collide with the binary.
  var Root := DocumentsDirectory;
  if (Root = '') or not TPath.IsPathRooted(Root) then
    Root := HomeDirectory;
  if (Root = '') or not TPath.IsPathRooted(Root) then
    raise EInOutError.Create('Cannot determine an absolute save directory');
  Result := TPath.Combine(TPath.Combine(Root, 'NESFMX'), 'Saves');
end;

function ResolveGameSavePath(const Root, RomFileName, Hash, Extension: string): string;
begin
  Result := '';
  if TDirectory.Exists(Root) then
  begin
    var Candidates: TArray<string>;
    if Extension = '' then
      Candidates := TDirectory.GetDirectories(Root)
    else
      Candidates := TDirectory.GetFiles(Root);
    for var Path in Candidates do
    begin
      var Name := ExtractFileName(Path);
      if SameText(Name, Hash + Extension) or EndsText('_' + Hash + Extension, Name) then
      begin
        if Result <> '' then
          raise EInOutError.CreateFmt('Multiple saves for ROM %s in %s', [Hash, Root]);
        Result := Path;
      end;
    end;
  end;
  if Result <> '' then
    Exit;
  var Title := ChangeFileExt(ExtractFileName(RomFileName), '').Trim;
  // Use portable names even when moving saves between Android/Linux and Windows.
  for var I := 1 to Length(Title) do
    if (Ord(Title[I]) < 32) or CharInSet(Title[I], ['<', '>', ':', '"', '/', '\', '|', '?', '*']) then
      Title[I] := '_';
  Title := Copy(Title, 1, 80).Trim;
  if Title = '' then
    Title := 'Game';
  Result := TPath.Combine(Root, Title + '_' + Hash + Extension);
end;

end.

