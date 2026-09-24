program NESFMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  NES.Gamepad in 'NES.Gamepad.pas',
  NES.Main in 'NES.Main.pas' {FormMain},
  {$IFDEF ANDROID}
  NES.RomPicker.Android in 'NES.RomPicker.Android.pas',
  {$ENDIF }
  {$IF Defined(ANDROID) and not Defined(NES_AUDIO_NULL)}
  PCM.Audio.Android.AudioTrack in '..\source\PCM\PCM.Audio.Android.AudioTrack.pas',
  {$ENDIF }
  {$IF Defined(MSWINDOWS) and not Defined(NES_AUDIO_NULL)}
  PCM.Audio.Windows.MMSystem in '..\source\PCM\PCM.Audio.Windows.MMSystem.pas',
  {$ENDIF }
  {$IF Defined(LINUX) and not Defined(ANDROID) and not Defined(NES_AUDIO_NULL)}
  PCM.Audio.Linux.Alsa in '..\source\PCM\PCM.Audio.Linux.Alsa.pas',
  {$ENDIF }
  {$IF (Defined(MACOS) or Defined(IOS)) and not Defined(NES_AUDIO_NULL)}
  PCM.Audio.Apple.AudioQueue in '..\source\PCM\PCM.Audio.Apple.AudioQueue.pas',
  {$ENDIF }
  PCM.Audio.Null in '..\source\PCM\PCM.Audio.Null.pas',
  PCM.Audio.Factory in '..\source\PCM\PCM.Audio.Factory.pas',
  PCM.Audio in '..\source\PCM\PCM.Audio.pas',
  PCM.Audio.Backend in '..\source\PCM\PCM.Audio.Backend.pas',
  NES.Mapper in '..\source\NES.Mapper.pas',
  NES.Mapper.Factory in '..\source\NES.Mapper.Factory.pas',
  NES.Mapper.ColorDreams in '..\source\mappers\NES.Mapper.ColorDreams.pas',
  NES.Mapper.Banked in '..\source\mappers\NES.Mapper.Banked.pas',
  NES.Mapper.Discrete in '..\source\mappers\NES.Mapper.Discrete.pas',
  NES.Mapper.MmcLatch in '..\source\mappers\NES.Mapper.MmcLatch.pas',
  NES.Mapper.Mmc3Variants in '..\source\mappers\NES.Mapper.Mmc3Variants.pas',
  NES.Mapper.Vrc in '..\source\mappers\NES.Mapper.Vrc.pas',
  NES.Mapper.Sunsoft in '..\source\mappers\NES.Mapper.Sunsoft.pas',
  NES.Mapper.Rambo in '..\source\mappers\NES.Mapper.Rambo.pas',
  NES.Mapper.Cony in '..\source\mappers\NES.Mapper.Cony.pas',
  NES.Mapper.Bandai in '..\source\mappers\NES.Mapper.Bandai.pas',
  NES.Mapper.Jy in '..\source\mappers\NES.Mapper.Jy.pas',
  NES.Mapper.Mmc5 in '..\source\mappers\NES.Mapper.Mmc5.pas',
  NES.Mapper.Subor in '..\source\mappers\NES.Mapper.Subor.pas',
  NES.Mapper.Mmc1 in '..\source\mappers\NES.Mapper.Mmc1.pas',
  NES.Mapper.Mmc3 in '..\source\mappers\NES.Mapper.Mmc3.pas',
  NES.Mapper.Nrom in '..\source\mappers\NES.Mapper.Nrom.pas',
  NES.Mapper.Uxrom in '..\source\mappers\NES.Mapper.Uxrom.pas',
  NES.Mapper.Axrom in '..\source\mappers\NES.Mapper.Axrom.pas',
  NES.Mapper.Cnrom in '..\source\mappers\NES.Mapper.Cnrom.pas',
  NES.Mapper.Gxrom in '..\source\mappers\NES.Mapper.Gxrom.pas',
  NES.PPU in '..\source\NES.PPU.pas',
  NES.State in '..\source\NES.State.pas',
  NES.SavePaths in '..\source\NES.SavePaths.pas',
  NES.Types in '..\source\NES.Types.pas',
  NES.APU in '..\source\NES.APU.pas',
  NES.AudioDiagnostics in '..\source\NES.AudioDiagnostics.pas',
  NES.Emulation in '..\source\NES.Emulation.pas',
  NES.Bus in '..\source\NES.Bus.pas',
  NES.Cartridge in '..\source\NES.Cartridge.pas',
  NES.RomMetadata in '..\source\NES.RomMetadata.pas',
  NES.Console in '..\source\NES.Console.pas',
  NES.Consts in '..\source\NES.Consts.pas',
  NES.Controller in '..\source\NES.Controller.pas',
  NES.Input in '..\source\NES.Input.pas',
  NES.CPU in '..\source\NES.CPU.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.

