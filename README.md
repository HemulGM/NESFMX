# NESFMX — Delphi / FireMonkey

A Delphi NES emulator with an FMX interface. 47 mapper numbers are supported:
NROM, MMC1–MMC5, UxROM, CNROM, AxROM, Color Dreams, GxROM, Bandai, VRC,
Sunsoft, RAMBO-1, Namco 108, JY and other boards from the proven ROM collection.
A list of implementations, test results, and limitations are provided in
[description of mappers](EXTENDED_MAPPERS.md).
Audio output is implemented for Windows (Win32/Win64) and Linux64.

SDL is no longer required: the window, zoom, keyboard, timer, and PNG images
are implemented using FMX tools. 44 100 Hz streaming audio, mono PCM16 output via
Windows WaveOut (`Winapi.MMSystem`) or ALSA (`libasound.so.2`) on Linux:
FMX Media does not provide a queue of arbitrary PCM samples.
On Windows, third-party DLLs and runtime packages are not needed; on Linux, ALSA is needed.

CPU/PPU/APU emulation and audio sending are performed in a separate thread
`NES.Emulation'. The FMX timer displays the last finished frame:
interface delays do not stop the game and do not accumulate a queue of frames.
Input and reset commands are passed to the thread under lock, and when the ROM is changed
or the application is closed, the audio device is released in the workflow,
and the console is released after the thread ends.

MMC3 supports PRG/CHR banks, mirroring switching, PRG RAM
and IRQ protection over A12 PPU. Adventure Island 2 has been tested with the transition to the first level.
The frame is drawn line by line, so switching banks between lines is saved
in the image. MMC3B/C and several derivative boards are implemented;
MMC6 is not supported yet. A12 filtering is approximate, the accuracy to each clock cycle of the PPU
is not stated. CNROM and GxROM account for bus conflicts; AxROM uses
the conflict-free option. Old iNES headers with the caption `DiskDude!` recognized
without changing the ROM on the disk. There is no full support for NES 2.0 extensions yet.

## Assembly

Open `fmx/NESFMX.dproj` in RAD Studio with Delphi FMX support, select
Win32 or Win64 and run Build. The form `fmx/NES.Main.fmx` is available for
visual editing. The common core is located in `source/'.
Overflow and range checks are included in Debug and Release.
Tested with Delphi 13 / compiler 37.0.

The audio subsystem is separate from the platform API: `NES.Audio` provides a common
facade, `NES.Audio.Windows` implements output via WaveOut, and `NES.Audio.Linux` —
via ALSA. The rest of the OS is still
using the NES.Audio.Null`: emulation continues without sound, the reason is available
through `Audio.Error` and diagnostics. Native audio has not yet been implemented for these operating systems.

To add sound for the platform:

1. Create the NES module.Audio.<Platform>` with the implementation of `INesAudioBackend`
   from `source/NES.Audio.Backend.pas'.
2. Connect it conditionally to `source/NES.Audio.Factory.pas` and add a branch
   creations in the 'CreatePlatformAudioBackend'. The OS API dependencies remain
inside the platform module.
3. Implement non-blocking PCM16 mono 44100 Hz reception, queue clearing,
   queue status and error message. `Submit` copies the input data
   until return; the queue is limited to four blocks of 1024 samples each.
   Counters of accepted/discarded samples are saved after `Clear`;
   the device position only makes sense if `PositionKnown = True'.

The 'NES.Emulation` thread creates, uses, and releases a device in its
`Execute'; the implementation itself synchronizes native callbacks and stops
them before releasing buffers. For tests, you can pass your own backend
to `TNesAudio.Create(Backend)`. The conditional character `NES_AUDIO_NULL` selects
the device-free mode on any OS, including Windows; in it, samples are counted as
discarded, `DeviceOpen` and `PositionKnown` remain `False'.

### Sound in Linux

When building Linux64` the factory automatically selects `TNesLinuxAudioBackend'.
It dynamically loads the system `libasound.so.2'; the C API declarations are
in the 'NES.Audio.Alsa`. Static linking with ALSA and its headers
are not needed for Delphi assembly. The FMX application itself requires FMX support for Linux and the SDK.

Data path: APU → PCM16 mono 44100 Hz → `TNesAudio` → ALSA `default` →
audio output configured in the system. `default` allows you to use the settings
ALSA, including routing via PulseAudio/PipeWire, if
the corresponding ALSA plugin is installed and configured. This is not a direct connection to the API of these
servers. In WSL, the sound goes through the configured ALSA plug-in to WSLg/PulseAudio.

'snd_pcm_open` uses `SND_PCM_NONBLOCK`, and `snd_pcm_writei' copies the PCM
to the ALSA queue. Emulation does not wait for playback: when there is a full queue or partial
recording, the remaining samples are counted as discarded. The amount
of queued data is limited to 4096 samples (about 93 ms); the initial filling
before the explicit start is about 46 ms. These are the parameters of the client buffer, and not
a guarantee of a full delay to the speakers: the server/device can add its own.

After underrun (`EPIPE`) or suspension (`ESTRPIPE`), the backend calls
`snd_pcm_prepare` and starts filling the queue again, without a waiting cycle.
`Clear` performs `snd_pcm_drop` + `snd_pcm_prepare'; closing resets the queue
without waiting for it to be played. `QueuedBlocks' for ALSA is the equivalent of the number
of 1024 sample blocks, since ALSA stores the stream, not the boundaries of our blocks.
The playback position is calculated based on the number of samples received and the ALSA delay;
if the position is unknown, `PositionKnown = False'. Reset/Restore starts
a new position count, keeping the total counters of sending and loss.

If the library, device, or desired format are not available, the error gets into
`Audio.Error` and diagnostics, but the emulation continues without sound. To check
the `default` setting, you can use `aplay -L'. An alternative device name
can be passed to the `TNesLinuxAudioBackend' constructor.Create('name')`.

API Contracts: [ALSA PCM](https://www.alsa-project.org/alsa-doc/alsa-lib/pcm.html ),
[function reference](https://www.alsa-project.org/alsa-doc/alsa-lib/group___p_c_m.html ).

## Launch and management

Run the EXE and select `.nes` in the dialog or pass the path in the command line:

```bat
fmx\Win64\Release\NESFMX.exe "C:\ROMs\game.nes"
```

| Key | Action |
| --- | --- |
| Z / X | A / B |
| Space / Enter | Select / Start |
| Arrows | Directions |
| G / H | A / B of the second player |
| T / Y | Select / Start of the second player |
| W / S / A / D | Up / down / left / right of the second player |
| N / M | A / B of the third player |
| U / O | Select / Start of the third player |
| I / K / J / L | Up / Down / Left / Right of the third player |
| Num 1 / Num 3 | A / B of the fourth player |
| Num 7 / Num 9 | Select / Start the fourth player |
| Num 8 / Num 5 / Num 4 / Num 6 | Directions of the fourth player (Num Lock enabled) |
| Ctrl+O | "Open" another ROM |
|R | Reset console |
| F5 | Save PNG 256×240 to "Documents" folder |
| F6 | Save the last ~30 seconds of audio and diagnostics to "Documents" |
| Esc | Close the application |

When you lose focus, the emulation and sound continue, and the pressed buttons are reset.
The window can be scaled;
the proportions of the image are preserved. An invalid ROM does not replace the current game.
If the sound device is unavailable, the app informs you about it and runs without sound.

## Settings

The `config.ini` is read next to the EXE and is created at the first startup.
Copy the existing INI to the compiled EXE to transfer your settings.
The application folder must be writable when creating the INI.

```ini
[Video]
Scale=2
Filter=nearest
[Input]
FourScore=1
[Controls]
A=Z
B=X
Select=SPACE
Start=RETURN
Up=UP
Down=DOWN
Left=LEFT
Right=RIGHT
[Controls2]
A=G
B=H
Select=T
Start=Y
Up=W
Down=S
Left=A
Right=D
[Controls3]
A=N
B=M
Select=U
Start=O
Up=I
Down=K
Left=J
Right=L
[Controls4]
A=NUMPAD1
B=NUMPAD3
Select=NUMPAD7
Start=NUMPAD9
Up=NUMPAD8
Down=NUMPAD5
Left=NUMPAD4
Right=NUMPAD6
```

Four virtual NES gamepads are independently controlled from the keyboard.
By default, the NES Four Score adapter is enabled: port `$4016` transmits buttons
for players 1 and 3, port `$4017` for players 2 and 4, then each port transmits
the adapter signature. The game must support Four Score; the number of players
is selected in the game itself. The Famicom protocol for four players has not yet been implemented.
Protocol description: [NESdev](https://www.nesdev.org/wiki/Controller_detection#Four_Score ).

The sections `[Controls]`, `[Controls2]`, `[Controls3]` and `[Controls4] define
the keys of the respective players. The old INI works with default settings
for missing partitions; existing assignments are retained.
To reassign, add the required section to the INI and restart the application.
'NUMPAD0`–`NUMPAD9` denote a separate numeric block; turn on Num Lock.

For the usual two controllers and the previous control of the Power Pad with the keys
of the first player, set `FourScore=0` in the `[Input]` section and restart
the application. The Power Pad is disabled in Four Score mode.
Input from physical USB/Bluetooth gamepads has not yet been implemented.

The input is separated from the form in `source/NES.Input.pas`: `TNesInput` stores the states
of the four players by source IDs (0 is the keyboard). The future handler
of the external device passes the buttons through the `SetButton', and when disconnected, it calls
`ReleaseSource`. Source clicks are combined: releasing a button on one
device does not cancel pressing on the other. `Apply` transmits the final state
to the NES port; `Clear' resets all sources when focus is lost or ROM is changed.

`Scale` is limited to the range 1-8. `Filter=nearest` disables interpolation,
`linear` includes it. Valid assignments are: A–Z, 0-9, SPACE, RETURN/ENTER,
UP, DOWN, LEFT, RIGHT, NUMPAD0–NUMPAD9. Incorrect assignments are replaced with default values.
R, F5, F6, Esc, and Ctrl+O are used as service combinations.