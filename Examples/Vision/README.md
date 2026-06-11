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
| [BodyPose](BodyPose/Sketch.swift) | a person's 2D pose drawn as a stick figure over the feed; shows an on-canvas message when the body-pose model can't run on the Mac instead of failing silently (`BodyTracker`, `Body`, `isAvailable`) |
| [PersonSegmentation](PersonSegmentation/Sketch.swift) | people lifted off the background and composited over a drawn, drifting gradient — background replacement in a few lines, with the tinted matte doubling as the drop shadow (`PersonSegmenter`, `matte`, `cutout`) |
| [SubjectLift](SubjectLift/Sketch.swift) | the salient foreground — whatever you hold up to the camera — lifted into a spotlight: the frame dimmed, the cutout at full color, a halo from the tinted matte (`SubjectSegmenter`, `count`) |
| [RectangleScan](RectangleScan/Sketch.swift) | rectangular shapes (paper, screens, cards) highlighted as four-corner quads over the feed, perspective and all — a classical detector, so it runs on any Mac (`RectangleDetector`, `corners(in:)`) |
| [BarcodeReader](BarcodeReader/Sketch.swift) | barcodes and QR codes outlined with their decoded payload printed above them — point a phone showing a QR code at the camera; also classical, runs on any Mac (`BarcodeScanner`, `payload`) |
| [TextScan](TextScan/Sketch.swift) | text read out of the feed (OCR) — each line boxed with the recognized text printed above it; point the camera at a sign, label, or page (`TextRecognizer`, `DetectedText`) |
| [ObjectTracking](ObjectTracking/Sketch.swift) | follow whatever you point at — click to lock onto the patch under the cursor and an `ObjectTracker` tracks it frame to frame, the box fading as confidence drops; classical, so it runs on any Mac (`ObjectTracker`, `trackedObject`) |
| [VideoTrace](VideoTrace/Sketch.swift) | vision over recorded footage — the bundled clip traced into line art as it plays, with the clip itself in a corner inset; a tracker attaches to a `VideoPlayer` exactly the way it attaches to a camera (`ContourDetector` over `VideoPlayer`, the frame-source seam) |
| [TrajectoryTracking](TrajectoryTracking/Sketch.swift) | ballistic arcs found and *predicted* in a synthetic ball-launcher feed — the example conforms its own `FrameSource`, so a simulation is the tracker's camera (`TrajectoryTracker`, `DetectedTrajectory`) |

These examples need a camera and ask for camera permission on first run (the system prompts from `swift run`) — except VideoTrace and TrajectoryTracking, which are self-contained and run with no camera at all. Run one with `swift run Example-<Name>`, e.g. `swift run Example-WebcamFeed`.
