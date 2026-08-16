#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Vision</sup>

---

## Vision

Computer vision on the Mac. Vision lives in a separate library — add `import OllinVision` — for the Mac's camera (built-in, a Continuity Camera iPhone, or an external webcam) plus Apple's on-device perception. Build a `Camera` in `setup()` and `start()` it, draw `camera.frame` in `draw()`, and attach a tracker (like `FaceTracker`) to the same camera to read recognition results. See the [Vision reference](../../Docs/Vision/Vision.md).

| Example | What it shows |
|---|---|
| [WebcamFeed](WebcamFeed/Sketch.swift) | the live camera drawn to the canvas with one `drawFrame(camera)` call — letterboxed, with the standard waiting notice until the first frame arrives — the foundation every tracker builds on; `Camera.start()` requests camera permission (`Camera`, `drawFrame`) |
| [FaceTracking](FaceTracking/Sketch.swift) | detected faces overlaid on the feed — a bounding box plus landmark outlines (jaw, brows, eyes, nose, lips) and pupil dots, with the normalized points placed on the canvas by the `in:` mapping helpers (`FaceTracker`, `Face`, landmarks) |
| [FaceAlign](FaceAlign/Sketch.swift) | the overlay idea inside out — the *picture* is translated, rotated, and scaled each frame so your eyes stay level and centered at a constant size: tilt your head and the room counter-rotates around your face (`FaceTracker`, `@Smoothed`, `withState`) |
| [ContourTrace](ContourTrace/Sketch.swift) | the camera's edges traced into vector contours and drawn as black line art over a faint feed — each is an Ollin `Shape`, so it could be filled, hatched, or sent to a plotter (`ContourDetector`, `shapes(in:)`) |
| [HandTracking](HandTracking/Sketch.swift) | up to two hands drawn as 21-joint skeletons over the feed — finger bones, joint dots, and highlighted fingertips, tinted by which hand it is (`HandTracker`, `Hand`, `bones(in:)`) |
| [BodyPose](BodyPose/Sketch.swift) | a person's 2D pose drawn as a stick figure over the feed; shows an on-canvas message when the body-pose model can't run on the Mac instead of failing silently (`BodyTracker`, `Body`, `isAvailable`) |
| [BodyPose3D](BodyPose3D/Sketch.swift) | the pose in meters from one ordinary webcam — the skeleton overlaid on the feed *and* re-drawn from the side in an inset, a view no camera is at, with the live distance to the person in the caption (`BodyTracker3D`, `Body3D`, `bones()`, `distance`) |
| [PersonSegmentation](PersonSegmentation/Sketch.swift) | people lifted off the background and composited over a drawn, drifting gradient — background replacement in a few lines, with the tinted matte doubling as the drop shadow (`PersonSegmenter`, `matte`, `cutout`) |
| [SubjectLift](SubjectLift/Sketch.swift) | the salient foreground — whatever you hold up to the camera — lifted into a spotlight: the frame dimmed, the cutout at full color, a halo from the tinted matte (`SubjectSegmenter`, `count`) |
| [RectangleScan](RectangleScan/Sketch.swift) | rectangular shapes (paper, screens, cards) highlighted as four-corner quads over the feed, perspective and all — a classical detector, so it runs on any Mac (`RectangleDetector`, `corners(in:)`) |
| [BarcodeReader](BarcodeReader/Sketch.swift) | barcodes and QR codes outlined with their decoded payload printed above them — point a phone showing a QR code at the camera; also classical, runs on any Mac (`BarcodeScanner`, `payload`) |
| [TextScan](TextScan/Sketch.swift) | text read out of the feed (OCR) — each line boxed with the recognized text printed above it; point the camera at a sign, label, or page (`TextRecognizer`, `DetectedText`) |
| [ObjectTracking](ObjectTracking/Sketch.swift) | follow whatever you point at — click to lock onto the patch under the cursor and an `ObjectTracker` tracks it frame to frame, the box fading as confidence drops; classical, so it runs on any Mac (`ObjectTracker`, `trackedObject`) |
| [OpticalFlow](OpticalFlow/Sketch.swift) | the camera's motion as a field of vectors: a grid of arrows colored by speed, and dust particles that ride the field, scattering when you wave and settling when you hold still; classical, runs on any Mac (`FlowTracker`, `MotionField`, `samples(in:)`, `vector(at:in:)`) |
| [SceneLabels](SceneLabels/Sketch.swift) | what the camera sees, named — the strongest of ~1,300 everyday labels race as animated bars while you re-stage the picture; a neural model, with an on-canvas message where it can't run (`ImageClassifier`, `labels`, `confidence(of:)`) |
| [EyeCatcher](EyeCatcher/Sketch.swift) | where the eye goes, made visible — the salience heat map glowing warm over the dimmed feed, the salient regions boxed, and a marker gliding to the hottest sampled spot; click to switch between attention and objectness (`SaliencyTracker`, `heatMap`, `salience(at:in:)`) |
| [DepthRelief](DepthRelief/Sketch.swift) | depth from one plain webcam — your own Core ML model (a monocular depth estimator) over the live feed, its map sampled into a relief of disks: nearer is bigger and warmer; run `Scripts/fetch-models.sh` once to download the model (`ModelTracker`, `value(at:in:)`, `map`) |
| [ObjectDetection](ObjectDetection/Sketch.swift) | objects found, boxed, and named in the live feed — where SceneLabels names the whole picture, a detector answers *where* and *how many*: one labeled, color-coded box per thing the model can name; run `Scripts/fetch-models.sh` once to download the model (`ModelTracker`, `objects`, `bounds(in:)`) |
| [PaintByClass](PaintByClass/Sketch.swift) | every pixel named and painted — a semantic-segmentation model (DeepLabV3) colors each class's pixels its own steady color, with a legend counting what's in frame and the cursor reading the class under it; run `Scripts/fetch-models.sh` once to download the model (`ModelTracker`, `classMask`, `mask(of:)`, `coverage(of:)`) |
| [DigitReader](DigitReader/Sketch.swift) | a model reading the sketch's *own* pixels — draw a digit with the mouse onto a pixel-authored `Image` and MNIST classifies it on every mouse lift; no camera anywhere, which is the point: a sketch can point a model at its own output (`ModelTracker`, still `detect(in:)`, `mouseIsPressed`, `Image[x, y]`) |
| [StyleMirror](StyleMirror/Sketch.swift) | the camera through a style-transfer model *you train yourself* with one command (any style image, no download, no license to check — see [Training the StyleMirror model](#training-the-stylemirror-model) below) — slide the mouse to crossfade between the camera and the painted frame (`ModelTracker`, `outputImage`, `tint`) |
| [TugOfWords](TugOfWords/Sketch.swift) | typed phrases as live knobs: two phrases pull on one rope by how well each matches the frame, and a phrase rewritten in the inspector (⌘/) re-anchors the rope; run `Scripts/fetch-models.sh` once to download the model (`ConceptTracker`, `confidence(of:)`, `similarity(of:)`) |
| [VideoTrace](VideoTrace/Sketch.swift) | vision over recorded footage — the bundled clip traced into line art as it plays, with the clip itself in a corner inset; a tracker attaches to a `VideoPlayer` exactly the way it attaches to a camera (`ContourDetector` over `VideoPlayer`, the frame-source seam) |
| [TrajectoryTracking](TrajectoryTracking/Sketch.swift) | ballistic arcs found and *predicted* in a synthetic ball-launcher feed — the example conforms its own `FrameSource`, so a simulation is the tracker's camera (`TrajectoryTracker`, `DetectedTrajectory`) |

These examples need a camera and ask for camera permission on first run (the system prompts from `swift run`), except VideoTrace, TrajectoryTracking, and DigitReader, which are self-contained and run with no camera at all. DepthRelief, ObjectDetection, PaintByClass, DigitReader, and TugOfWords additionally need their models downloaded once (`Scripts/fetch-models.sh`; the weights are fetched, never committed), and StyleMirror wants a model you train yourself (below). Run one with `swift run Example-Vision-<Name>`, e.g. `swift run Example-Vision-WebcamFeed`.

### Training the StyleMirror model

StyleMirror runs a model that's *your own work* — nothing to download, no license to check. The Create ML app no longer offers its Style Transfer template, but the CreateML framework still trains them, and the repo wraps that in one command (run it from the repo root):

```sh
swift Scripts/train-style-model.swift path/to/any-image.jpg
```

Any image works as the style — a painting, a texture, an export of one of your own sketches. A couple of minutes later `Models/StyleTransfer.mlmodel` exists and StyleMirror starts painting; the sketch watches for the file, so you can train while it runs and watch the style arrive.

Options, all optional:

| Flag | What it does |
|---|---|
| `--content <folder>` | your own photos as training *content* (what teaches the model to preserve structure); defaults to frames pulled from the repo's sample clip |
| `--iterations <n>` | more iterations, finer style (default 200 — about two minutes) |
| `--strength <1-10>` | how hard the style pushes (default 5) |
| `--quality` | the heavier image-quality network instead of the lighter real-time one the live mirror wants |
| `--out <path>` | write somewhere else (default `Models/StyleTransfer.mlmodel`) |
