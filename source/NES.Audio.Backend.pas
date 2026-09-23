unit NES.Audio.Backend;

interface

const
  NES_SAMPLE_RATE = 44100;
  AUDIO_BLOCK_SAMPLES = 1024;
  AUDIO_BLOCK_COUNT = 4;

type
  TAudioQueueState = record
    // Lifetime counters; Clear does not discard submitted/dropped totals.
    SubmittedSamples, DroppedSamples: UInt64;
    // Clears and the device playback position wrap at 32 bits.
    // PlayedSamples is valid only when PositionKnown, and may reset on Clear.
    Clears, PlayedSamples: Cardinal;
    QueuedBlocks: Integer;
    DeviceOpen, PositionKnown: Boolean;
  end;

  // PCM16 signed mono, NES_SAMPLE_RATE Hz. Create, use and release on the
  // owning thread. Implementations synchronize their own native callbacks.
  // Submit must copy samples before returning and must not wait for playback.
  // Keep at most AUDIO_BLOCK_COUNT blocks; count overflow as dropped samples.
  // Clear discards pending playback. Destruction stops callbacks before freeing
  // their buffers. Device failures are exposed through Error and QueueState.
  INesAudioBackend = interface
    ['{7AF07CE4-5773-485D-8427-A2065839694C}']
    procedure Clear;
    // The facade validates 0 < Count <= Min(Length(Samples), AUDIO_BLOCK_SAMPLES).
    procedure Submit(const Samples: array of SmallInt; Count: Integer);
    function QueueState: TAudioQueueState;
    function GetError: string;
    property Error: string read GetError;
  end;

implementation

end.
