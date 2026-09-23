unit NES.Audio.Factory;

interface

uses
  NES.Audio.Backend;

function CreatePlatformAudioBackend: INesAudioBackend;

implementation

// Add platform units and their constructors here as implementations become
// available. NES_AUDIO_NULL also allows testing the portable path on Windows.
uses
  {$IF Defined(MSWINDOWS) and not Defined(NES_AUDIO_NULL)}
  NES.Audio.Windows.MMSystem;
  {$ELSEIF Defined(ANDROID) and not Defined(NES_AUDIO_NULL)}
  NES.Audio.Android.AudioTrack;
  {$ELSEIF Defined(LINUX) and not Defined(ANDROID) and not Defined(NES_AUDIO_NULL)}
  NES.Audio.Linux.Alsa;
  {$ELSE}
  NES.Audio.Null;
  {$ENDIF}

function CreatePlatformAudioBackend: INesAudioBackend;
begin
  {$IF Defined(NES_AUDIO_NULL)}
  Result := TNesNullAudioBackend.Create;
  {$ELSEIF Defined(MSWINDOWS)}
  Result := TNesWindowsAudioBackend.Create;
  {$ELSEIF Defined(ANDROID)}
  Result := TNesAndroidAudioBackend.Create;
  {$ELSEIF Defined(LINUX) and not Defined(ANDROID)}
  Result := TNesLinuxAudioBackend.Create;
  {$ELSE}
  Result := TNesNullAudioBackend.Create('Audio output is not implemented for this platform');
  {$ENDIF}
end;

end.
