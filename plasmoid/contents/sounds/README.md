# Turbo audio

Keep all original and derived audio assets in this folder.

| File | Purpose |
| --- | --- |
| `power_on.mp3` | Turbo activation |
| `poweroff.mp3` | Turbo deactivation and five-second expiry |
| `zap.mp3` | Lightning strikes |
| `electricity-loop.wav` | Seamless, buffered electrical buzz during Turbo |
| `electricity.mp3` | Original recording used to create the seamless loop |

The loop uses a 250 ms crossfade between the original recording's tail and head.
`../ui/TurboAudio.qml` references these files through `../sounds/`.
Both packaging scripts include this directory as part of the Plasma package;
there should be no duplicate audio files in the project root.

The short `zap.wav`, `power_on.wav`, and `poweroff.wav` effects are 48 kHz stereo 16-bit PCM versions of the corresponding MP3 originals. Turbo mixes these and the buzz into one native QAudioSink output, avoiding MP3 decoder initialization and separate per-effect streams. The output exists only while Turbo or its power-off tail is active. Sounds overlap in the mixer, and disabling sound immediately discards buffered audio and closes the output.
