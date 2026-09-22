program NESFMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  NES.Main in 'NES.Main.pas' {FormMain},
  NES.Mapper.ColorDreams in '..\source\NES.Mapper.ColorDreams.pas',
  NES.Mapper.Banked in '..\source\NES.Mapper.Banked.pas',
  NES.Mapper.Discrete in '..\source\NES.Mapper.Discrete.pas',
  NES.Mapper.MmcLatch in '..\source\NES.Mapper.MmcLatch.pas',
  NES.Mapper.Mmc3Variants in '..\source\NES.Mapper.Mmc3Variants.pas',
  NES.Mapper.Vrc in '..\source\NES.Mapper.Vrc.pas',
  NES.Mapper.Sunsoft in '..\source\NES.Mapper.Sunsoft.pas',
  NES.Mapper.Rambo in '..\source\NES.Mapper.Rambo.pas',
  NES.Mapper.Cony in '..\source\NES.Mapper.Cony.pas',
  NES.Mapper.Bandai in '..\source\NES.Mapper.Bandai.pas',
  NES.Mapper.Jy in '..\source\NES.Mapper.Jy.pas',
  NES.Mapper.Mmc5 in '..\source\NES.Mapper.Mmc5.pas',
  NES.Mapper.Factory in '..\source\NES.Mapper.Factory.pas',
  NES.RomMetadata in '..\source\NES.RomMetadata.pas',
  NES.Mapper.Mmc1 in '..\source\NES.Mapper.Mmc1.pas',
  NES.Mapper.Mmc3 in '..\source\NES.Mapper.Mmc3.pas',
  NES.Mapper.Nrom in '..\source\NES.Mapper.Nrom.pas',
  NES.Mapper in '..\source\NES.Mapper.pas',
  NES.Mapper.Uxrom in '..\source\NES.Mapper.Uxrom.pas',
  NES.PPU in '..\source\NES.PPU.pas',
  NES.Types in '..\source\NES.Types.pas',
  NES.APU in '..\source\NES.APU.pas',
  NES.Audio in '..\source\NES.Audio.pas',
  NES.AudioDiagnostics in '..\source\NES.AudioDiagnostics.pas',
  NES.Bus in '..\source\NES.Bus.pas',
  NES.Cartridge in '..\source\NES.Cartridge.pas',
  NES.Console in '..\source\NES.Console.pas',
  NES.Consts in '..\source\NES.Consts.pas',
  NES.Controller in '..\source\NES.Controller.pas',
  NES.CPU in '..\source\NES.CPU.pas',
  NES.Mapper.Axrom in '..\source\NES.Mapper.Axrom.pas',
  NES.Mapper.Cnrom in '..\source\NES.Mapper.Cnrom.pas',
  NES.Mapper.Gxrom in '..\source\NES.Mapper.Gxrom.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
