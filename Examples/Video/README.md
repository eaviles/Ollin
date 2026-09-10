#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Video</sup>

---

## Video

These examples use recorded footage as drawing material. Video playback lives in a separate library, so add `import OllinVideo`. The library provides a `VideoPlayer`, which presents each decoded frame as a GPU-textured `Image`. A sketch then draws that image with `drawImage`. See the [Video reference](../../Docs/Video/Video.md).

| [![SoundReactive](https://media.ollin.art/examples/Video/SoundReactive/still-640.jpg?v=876903b9)](SoundReactive/) | [![VideoPlayback](https://media.ollin.art/examples/Video/VideoPlayback/still-640.jpg?v=617a629f)](VideoPlayback/) |  |  |
|---|---|---|---|
| [SoundReactive](SoundReactive/) | [VideoPlayback](VideoPlayback/) |  |  |

| Example | What it shows |
|---|---|
| [VideoPlayback](VideoPlayback/Sketch.swift) | loops a video file as a live image, draws it letterboxed with `drawFrame`, and draws a playback-progress line along the bottom; by default it plays a bundled clip (*Voladores de Papantla México* by José Millán, CC BY-SA, the Totonac pole-flying ritual dance), or you pass a path on launch to play your own video (`VideoPlayer`, `drawFrame`, `duration`/`currentTime`) |
| [SoundReactive](SoundReactive/Sketch.swift) | analyzes the playing clip's own soundtrack live, and draws spectrum bars and a beat-kick ring over the footage they react to (`Soundtrack(of: player)`, `bands`, `beat`; it also needs `import OllinAudio`); its clip pairs the voladores footage with the *El Fandanguito* violin recording as the soundtrack, and both are CC BY-SA |

To run one, use `swift run Example-Video-VideoPlayback` (or `Example-Video-SoundReactive`).
