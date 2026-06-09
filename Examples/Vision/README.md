#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Vision</sup>

---

## Vision

Computer vision on the Mac. Vision lives in a separate library — add `import OllinVision` — for the Mac's camera (built-in, a Continuity Camera iPhone, or an external webcam) plus Apple's on-device perception. Build a `Camera` in `setup()` and `start()` it, draw `camera.frame` in `draw()`, and attach a tracker (like `FaceTracker`) to the same camera to read recognition results. See the [Vision reference](../../Docs/Vision.md).

| Example | What it shows |
|---|---|
| [WebcamFeed](WebcamFeed/Sketch.swift) | the live camera drawn to the canvas, letterboxed with `fittedRect(in:)` — the foundation every tracker builds on; `Camera.start()` requests camera permission and the canvas waits until a frame arrives (`Camera`, `frame`) |
| [FaceTracking](FaceTracking/Sketch.swift) | detected faces overlaid on the feed — a bounding box plus landmark outlines (jaw, brows, eyes, nose, lips) and pupil dots, with the normalized points placed on the canvas by the `in:` mapping helpers (`FaceTracker`, `Face`, landmarks) |
| [ContourTrace](ContourTrace/Sketch.swift) | the camera's edges traced into vector contours and drawn as black line art over a faint feed — each is an Ollin `Shape`, so it could be filled, hatched, or sent to a plotter (`ContourDetector`, `shapes(in:)`) |
| [HandTracking](HandTracking/Sketch.swift) | up to two hands drawn as 21-joint skeletons over the feed — finger bones, joint dots, and highlighted fingertips, tinted by which hand it is (`HandTracker`, `Hand`, `bones(in:)`) |

These examples need a camera and grant camera permission on first run (the system prompts from `swift run`). Run one with `swift run Example-<Name>`, e.g. `swift run Example-WebcamFeed`.
