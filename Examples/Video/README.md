#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Video</sup>

---

## Video

Recorded footage as drawing material. Video playback lives in a separate library — add `import OllinVideo` — with a `VideoPlayer` that surfaces each decoded frame as a GPU-textured `Image` a sketch draws with `drawImage`. See the [Video reference](../../Docs/Video/Video.md).

| Example | What it shows |
|---|---|
| [VideoPlayback](VideoPlayback/Sketch.swift) | loops a video file as a live image, drawn letterboxed with `drawFrame`, with a playback-progress line along the bottom; plays a bundled clip (*Voladores de Papantla México* by José Millán, CC BY-SA — the Totonac pole-flying ritual dance) by default, or pass a path on launch to play your own video (`VideoPlayer`, `drawFrame`, `duration`/`currentTime`) |

| [SoundReactive](SoundReactive/Sketch.swift) | analyzes the playing clip's own soundtrack live: spectrum bars and a beat-kick ring drawn over the footage they react to (`Soundtrack(of: player)`, `bands`, `beat`; needs `import OllinAudio` too); its clip pairs the voladores footage with the *El Fandanguito* violin recording as the soundtrack, both CC BY-SA |

Run one with `swift run Example-Video-VideoPlayback` (or `Example-Video-SoundReactive`).
