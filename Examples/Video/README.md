#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Video</sup>

---

## Video

Recorded footage as drawing material. Video playback lives in a separate library — add `import OllinVideo` — with a `VideoPlayer` that surfaces each decoded frame as a GPU-textured `Image` a sketch draws with `drawImage`. See the [Video reference](../../Docs/Video.md).

| Example | What it shows |
|---|---|
| [VideoPlayback](VideoPlayback/Sketch.swift) | loops a video file as a live image, letterboxed with `fittedRect`, with a playback-progress line along the bottom; plays a bundled clip (*Voladores de Papantla México* by José Millán, CC BY-SA — the Totonac pole-flying ritual dance) by default, or pass a path on launch to play your own video (`VideoPlayer`, `frame`, `fittedRect`, `duration`/`currentTime`) |

Run it with `swift run Example-VideoPlayback`.
