unit NES.Audio.Alsa;

interface

uses
  System.SysUtils;

const
  ALSA_LIBRARY = 'libasound.so.2';
  SND_PCM_STREAM_PLAYBACK = 0;
  SND_PCM_NONBLOCK = 1;
  SND_PCM_FORMAT_S16_LE = 2;
  SND_PCM_ACCESS_RW_INTERLEAVED = 3;
  SND_PCM_STATE_PREPARED = 2;
  ALSA_EINTR = 4;
  ALSA_EAGAIN = 11;
  ALSA_EPIPE = 32;
  ALSA_ESTRPIPE = 86;

type
  // ALSA uses C long / unsigned long for frames (64 bits on Linux64),
  // C int for status/enums, and opaque snd_pcm_t pointers.
  TAlsaApi = record
    Open: function(out PCM: Pointer; Name: PAnsiChar; Stream, Mode: Integer): Integer; cdecl;
    Close: function(PCM: Pointer): Integer; cdecl;
    SetParams: function(PCM: Pointer; Format, Access: Integer; Channels, Rate: Cardinal; SoftResample: Integer; Latency: Cardinal): Integer; cdecl;
    GetParams: function(PCM: Pointer; out BufferSize, PeriodSize: NativeUInt): Integer; cdecl;
    AvailDelay: function(PCM: Pointer; out Avail, Delay: NativeInt): Integer; cdecl;
    AvailUpdate: function(PCM: Pointer): NativeInt; cdecl;
    WriteInterleaved: function(PCM, Buffer: Pointer; Frames: NativeUInt): NativeInt; cdecl;
    Prepare: function(PCM: Pointer): Integer; cdecl;
    Drop: function(PCM: Pointer): Integer; cdecl;
    State: function(PCM: Pointer): Integer; cdecl;
    Start: function(PCM: Pointer): Integer; cdecl;
    StrError: function(Code: Integer): PAnsiChar; cdecl;
    function Complete: Boolean;
  end;

function LoadAlsa(out Api: TAlsaApi; out Module: HMODULE; out Error: string): Boolean;

implementation

function TAlsaApi.Complete: Boolean;
begin
  Result := Assigned(Open) and Assigned(Close) and Assigned(SetParams) and
    Assigned(GetParams) and Assigned(AvailDelay) and Assigned(AvailUpdate) and Assigned(WriteInterleaved) and
    Assigned(Prepare) and Assigned(Drop) and Assigned(State) and Assigned(Start) and
    Assigned(StrError);
end;

function LoadAlsa(out Api: TAlsaApi; out Module: HMODULE; out Error: string): Boolean;
begin
  Api := Default(TAlsaApi);
  Module := 0;
  Error := '';
  {$IF Defined(LINUX) and not Defined(ANDROID)}
  Module := LoadLibrary(ALSA_LIBRARY);
  if Module = 0 then
    Error := 'Cannot load ' + ALSA_LIBRARY + '; install the ALSA runtime library'
  else
  begin
    @Api.Open := GetProcAddress(Module, 'snd_pcm_open');
    @Api.Close := GetProcAddress(Module, 'snd_pcm_close');
    @Api.SetParams := GetProcAddress(Module, 'snd_pcm_set_params');
    @Api.GetParams := GetProcAddress(Module, 'snd_pcm_get_params');
    @Api.AvailDelay := GetProcAddress(Module, 'snd_pcm_avail_delay');
    @Api.AvailUpdate := GetProcAddress(Module, 'snd_pcm_avail_update');
    @Api.WriteInterleaved := GetProcAddress(Module, 'snd_pcm_writei');
    @Api.Prepare := GetProcAddress(Module, 'snd_pcm_prepare');
    @Api.Drop := GetProcAddress(Module, 'snd_pcm_drop');
    @Api.State := GetProcAddress(Module, 'snd_pcm_state');
    @Api.Start := GetProcAddress(Module, 'snd_pcm_start');
    @Api.StrError := GetProcAddress(Module, 'snd_strerror');
    if not Api.Complete then
    begin
      Error := 'Missing PCM functions in ' + ALSA_LIBRARY;
      FreeLibrary(Module);
      Module := 0;
      Api := Default(TAlsaApi);
    end;
  end;
  {$ELSE}
  Error := 'ALSA is available only on desktop Linux';
  {$ENDIF}
  Result := Module <> 0;
end;

end.

