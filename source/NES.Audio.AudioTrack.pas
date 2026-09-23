unit NES.Audio.AudioTrack;

interface

type
  // All calls, including release, belong to the emulation thread. Open returns
  // the actual buffer size in mono frames; Write returns copied PCM16 samples.
  INesAudioTrackDevice = interface
    ['{CB633CA8-AD26-4B56-A4EB-794E4667C0A0}']
    function Open(SampleRate, MaxBufferSamples: Integer): Integer;
    function Write(const Samples: array of SmallInt; Count: Integer): Integer;
    function PlaybackHead: Cardinal;
    procedure Play;
    procedure Pause;
    procedure Flush;
    procedure Close;
  end;

const
  AUDIOTRACK_ERROR_DEAD_OBJECT = -6;

function CreateAudioTrackDevice: INesAudioTrackDevice;

implementation

{$IFDEF ANDROID}
uses
  System.SysUtils, Androidapi.JNI.Media, Androidapi.JNI.Os,
  Androidapi.JNIBridge, NES.Audio.Backend;

type
  TAndroidAudioTrackDevice = class(TInterfacedObject, INesAudioTrackDevice)
  private
    FTrack: JAudioTrack;
    FSamples: TJavaArray<SmallInt>;
  public
    destructor Destroy; override;
    function Open(SampleRate, MaxBufferSamples: Integer): Integer;
    function Write(const Samples: array of SmallInt; Count: Integer): Integer;
    function PlaybackHead: Cardinal;
    procedure Play;
    procedure Pause;
    procedure Flush;
    procedure Close;
  end;

function TAndroidAudioTrackDevice.Open(SampleRate, MaxBufferSamples: Integer): Integer;
begin
  Close;
  if TJBuild_VERSION.JavaClass.SDK_INT < 23 then
    raise Exception.Create('AudioTrack requires Android 6.0 / API 23 or newer');
  var MinimumBytes := TJAudioTrack.JavaClass.getMinBufferSize(SampleRate,
    TJAudioFormat.JavaClass.CHANNEL_OUT_MONO, TJAudioFormat.JavaClass.ENCODING_PCM_16BIT);
  if MinimumBytes <= 0 then
    raise Exception.CreateFmt('AudioTrack cannot configure mono PCM16 at %d Hz (%d)',
      [SampleRate, MinimumBytes]);
  if MinimumBytes > MaxBufferSamples * SizeOf(SmallInt) then
    raise Exception.CreateFmt('AudioTrack requires %d buffer bytes; queue limit is %d',
      [MinimumBytes, MaxBufferSamples * SizeOf(SmallInt)]);

  var Attributes := TJAudioAttributes_Builder.JavaClass.init
    .setUsage(TJAudioAttributes.JavaClass.USAGE_GAME)
    .setContentType(TJAudioAttributes.JavaClass.CONTENT_TYPE_MUSIC).build;
  var Format := TJAudioFormat_Builder.JavaClass.init
    .setEncoding(TJAudioFormat.JavaClass.ENCODING_PCM_16BIT)
    .setSampleRate(SampleRate).setChannelMask(TJAudioFormat.JavaClass.CHANNEL_OUT_MONO).build;
  FTrack := TJAudioTrack_Builder.JavaClass.init.setAudioAttributes(Attributes)
    .setAudioFormat(Format).setTransferMode(TJAudioTrack.JavaClass.MODE_STREAM)
    .setBufferSizeInBytes(MaxBufferSamples * SizeOf(SmallInt)).build;
  if (FTrack = nil) or (FTrack.getState <> TJAudioTrack.JavaClass.STATE_INITIALIZED) then
    raise Exception.Create('AudioTrack initialization failed');
  FSamples := TJavaArray<SmallInt>.Create(AUDIO_BLOCK_SAMPLES);
  Result := FTrack.getBufferSizeInFrames;
end;

function TAndroidAudioTrackDevice.Write(const Samples: array of SmallInt; Count: Integer): Integer;
begin
  // Reuse one Java short[]. Sync releases/copies its JNI elements before Java
  // reads them; do not keep pinned array elements across the write call.
  Move(Samples[0], FSamples.Data^, Count * SizeOf(SmallInt));
  FSamples.Sync;
  Result := FTrack.write(FSamples, 0, Count, TJAudioTrack.JavaClass.WRITE_NON_BLOCKING);
end;

function TAndroidAudioTrackDevice.PlaybackHead: Cardinal;
begin
  // Java returns a signed int containing an unsigned wrapping frame counter.
  Result := UInt64(Int64(FTrack.getPlaybackHeadPosition) and $FFFFFFFF);
end;

procedure TAndroidAudioTrackDevice.Play;
begin
  FTrack.play;
end;

procedure TAndroidAudioTrackDevice.Pause;
begin
  FTrack.pause;
end;

procedure TAndroidAudioTrackDevice.Flush;
begin
  FTrack.flush;
end;

procedure TAndroidAudioTrackDevice.Close;
begin
  var Track := FTrack;
  FTrack := nil;
  FreeAndNil(FSamples);
  if Track <> nil then
  try
    if Track.getState = TJAudioTrack.JavaClass.STATE_INITIALIZED then
    try
      Track.pause;
    finally
      Track.flush;
    end;
  finally
    // Never stop/drain and wait for queued audio; always release, even if a
    // disconnected device throws during pause/flush.
    Track.release;
  end;
end;

destructor TAndroidAudioTrackDevice.Destroy;
begin
  try
    Close;
  except
    // The backend reports explicit Close failures; destruction cannot raise.
  end;
  inherited;
end;
{$ENDIF}

function CreateAudioTrackDevice: INesAudioTrackDevice;
begin
{$IFDEF ANDROID}
  Result := TAndroidAudioTrackDevice.Create;
{$ELSE}
  Result := nil;
{$ENDIF}
end;

end.
