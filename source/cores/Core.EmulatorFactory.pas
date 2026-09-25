unit Core.EmulatorFactory;

interface

uses
  System.SysUtils, System.IOUtils, Core.Emulation;

function CreateEmulationCore(const FileName: string): IEmulationCore;

implementation

uses
  Core.Adapter.NES, Core.Adapter.GB, Core.Adapter.GBC;

function CreateEmulationCore(const FileName: string): IEmulationCore;
var
  Extension: string;
begin
  Extension := TPath.GetExtension(FileName).ToLower;
  if Extension = '.nes' then
    Result := TNesCoreAdapter.Create(FileName)
  else if Extension = '.gb' then
    Result := TGBCoreAdapter.Create(FileName)
  else if Extension = '.gbc' then
    Result := TGBCCoreAdapter.Create(FileName)
  else
    raise Exception.Create('Unsupported ROM type. Choose .nes, .gb or .gbc');
end;

end.

