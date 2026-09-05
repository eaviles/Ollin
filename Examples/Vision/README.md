#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Vision</sup>

---

## Vision

Computer vision on the Mac. Vision lives in a separate library, so add `import OllinVision`. It covers the Mac's camera (built-in, a Continuity Camera iPhone, or an external webcam) plus Apple's on-device perception. Build a `Camera` in `setup()` and `start()` it. Draw `camera.frame` in `draw()`. Then attach a tracker (like `FaceTracker`) to the same camera to read recognition results. See the [Vision reference](../../Docs/Vision/Vision.md).

| Example | What it shows |
|---|---|
| [WebcamFeed](WebcamFeed/Sketch.swift) | the live camera drawn to the canvas with one `drawFrame(camera)` call, letterboxed, with the standard waiting notice until the first frame arrives; this is the foundation every tracker builds on, and `Camera.start()` requests camera permission (`Camera`, `drawFrame`) |
| [FaceTracking](FaceTracking/Sketch.swift) | detected faces overlaid on the feed: a bounding box plus landmark outlines (jaw, brows, eyes, nose, lips) and pupil dots; the `in:` mapping helpers place the normalized points on the canvas (`FaceTracker`, `Face`, landmarks) |
| [FaceAlign](FaceAlign/Sketch.swift) | the overlay idea reversed: the *picture* is translated, rotated, and scaled each frame so your eyes stay level and centered at a constant size, which means that when you tilt your head the room counter-rotates around your face (`FaceTracker`, `@Smoothed`, `withState`) |
| [ContourTrace](ContourTrace/Sketch.swift) | the camera's edges traced into vector contours and drawn as black line art over a faint feed; each contour is an Ollin `Shape`, so it can be filled, hatched, or sent to a plotter; pass a clip path on launch and the same detector traces the footage instead, because the `FrameSource` seam makes the source a one-line swap (`ContourDetector`, `shapes(in:)`, `VideoPlayer`) |
| [HandTracking](HandTracking/Sketch.swift) | up to two hands drawn as 21-joint skeletons over the feed: finger bones, joint dots, and highlighted fingertips, tinted by which hand it is (`HandTracker`, `Hand`, `bones(in:)`) |
| [BodyPose](BodyPose/Sketch.swift) | a person's 2D pose drawn as a stick figure over the feed; when the body-pose model can't run on the Mac, the sketch shows an on-canvas message instead of failing silently (`BodyTracker`, `Body`, `isAvailable`) |
| [BodyPose3D](BodyPose3D/Sketch.swift) | the pose in meters from one ordinary webcam: the skeleton is overlaid on the feed *and* re-drawn from the side in an inset, a view no camera is at, and the caption shows the live distance to the person (`BodyTracker3D`, `Body3D`, `bones()`, `distance`) |
| [Lift](Lift/Sketch.swift) | something lifted off the background, two ways, with a `segmenter` parameter switching between them: people composited over a drawn, drifting gradient (background replacement in a few lines, with the tinted matte serving as the drop shadow), or the salient subject in a spotlight, where the frame is dimmed and the cutout stays at full color with a halo from the tinted matte (`PersonSegmenter`, `SubjectSegmenter`, `matte`, `cutout`, `count`) |
| [TuringMirror](TuringMirror/Sketch.swift) | the person matte steering a reaction-diffusion simulation: the matte drives the field's modulation layer, so one continuous simulation grows maze walls on your silhouette and spots everywhere else, and it reorganizes live as you move (`PersonSegmenter`, `SimField.modulation`, `.reactionDiffusion(feed:kill:toFeed:toKill:)`) |
| [PointLift](PointLift/Sketch.swift) | click a thing and it lifts out of the feed: point-prompted segmentation of whatever sits under the click; shift-click trims the mask and C releases it; needs the fetched model (`PointSegmenter`, `pick`, `bounds(in:)`) |
| [RectangleScan](RectangleScan/Sketch.swift) | rectangular shapes (paper, screens, cards) highlighted as four-corner quads over the feed, perspective included; this is a classical detector, so it runs on any Mac (`RectangleDetector`, `corners(in:)`) |
| [BarcodeReader](BarcodeReader/Sketch.swift) | barcodes and QR codes outlined with their decoded payload printed above them; point a phone showing a QR code at the camera; also a classical detector, so it runs on any Mac (`BarcodeScanner`, `payload`) |
| [TextScan](TextScan/Sketch.swift) | text read out of the feed (OCR): each line is boxed with the recognized text printed above it; point the camera at a sign, label, or page (`TextRecognizer`, `DetectedText`) |
| [ObjectTracking](ObjectTracking/Sketch.swift) | follow whatever you point at: click to lock onto the patch under the cursor, and an `ObjectTracker` tracks it frame to frame, with the box fading as confidence drops; classical, so it runs on any Mac (`ObjectTracker`, `trackedObject`) |
| [OpticalFlow](OpticalFlow/Sketch.swift) | the camera's motion as a field of vectors: a grid of arrows colored by speed, and dust particles that follow the field, scattering when you wave and settling when you hold still; classical, so it runs on any Mac (`FlowTracker`, `MotionField`, `samples(in:)`, `vector(at:in:)`) |
| [SceneLabels](SceneLabels/Sketch.swift) | what the camera sees, named: the strongest of ~1,300 everyday labels race as animated bars while you re-stage the picture; this is a neural model, so an on-canvas message appears where it can't run (`ImageClassifier`, `labels`, `confidence(of:)`) |
| [EyeCatcher](EyeCatcher/Sketch.swift) | where the eye goes, made visible: the salience heat map glows warm over the dimmed feed, the salient regions are boxed, and a marker glides to the hottest sampled spot; click to switch between attention and objectness (`SaliencyTracker`, `heatMap`, `salience(at:in:)`) |
| [DepthRelief](DepthRelief/Sketch.swift) | depth from one plain webcam: your own Core ML model (a monocular depth estimator) runs over the live feed, and its map is sampled into a relief of disks, where nearer is bigger and warmer; run `Scripts/fetch-models.sh` once to download the model (`ModelTracker`, `value(at:in:)`, `map`) |
| [DepthContours](DepthContours/Sketch.swift) | depth that holds still: contour lines of depth over the feed from a *video* depth model, which reads each frame against the ones before it, so the lines move only with the scene; a `perFrame` parameter draws them from the single-image model instead, and then they crawl, which shows why a video model matters; R re-anchors the depth scale; run `Scripts/fetch-models.sh` once to build the model (`DepthTracker`, `value(at:in:)`, `reset()`, `isolines`) |
| [FootageDepth](FootageDepth/Sketch.swift) | the whole clip's depth, read ahead of time: a bundled recording goes through the video depth model's published 32-frame window inference once (a progress bar counts the pass up, and the result is cached); then contour lines of its depth follow the flyers by clip time, and `--export-video` puts them on the same frames every run, which a live tracker over a playing clip can't promise; pass a path on launch to read your own clip (`DepthClip`) |
| [ObjectDetection](ObjectDetection/Sketch.swift) | objects found, boxed, and named in the live feed; SceneLabels names the whole picture, but a detector answers *where* and *how many*, with one labeled, color-coded box per thing the model can name; run `Scripts/fetch-models.sh` once to download the model (`ModelTracker`, `objects`, `bounds(in:)`) |
| [PaintByClass](PaintByClass/Sketch.swift) | every pixel named and painted: a semantic-segmentation model (DeepLabV3) colors each class's pixels its own steady color, a legend counts what's in frame, and the cursor reads the class under it; run `Scripts/fetch-models.sh` once to download the model (`ModelTracker`, `classMask`, `mask(of:)`, `coverage(of:)`) |
| [DigitReader](DigitReader/Sketch.swift) | a model reading the sketch's *own* pixels: draw a digit with the mouse onto a pixel-authored `Image`, and MNIST classifies it on every mouse lift; there is no camera anywhere, which is the point, because a sketch can point a model at its own output (`ModelTracker`, still `detect(in:)`, `mouseIsPressed`, `Image[x, y]`) |
| [StyleMirror](StyleMirror/Sketch.swift) | the camera through a style-transfer model *you train yourself* with one command (any style image, no download, no license to check; see [Training the StyleMirror model](#training-the-stylemirror-model) below); slide the mouse to crossfade between the camera and the painted frame (`ModelTracker`, `image`, `tint`) |
| [TugOfWords](TugOfWords/Sketch.swift) | typed phrases as live parameters: two phrases pull on one rope by how well each matches the frame, and rewriting a phrase in the inspector (⌘/) re-anchors the rope; run `Scripts/fetch-models.sh` once to download the model (`ConceptTracker`, `confidence(of:)`, `similarity(of:)`) |
| [TrajectoryTracking](TrajectoryTracking/Sketch.swift) | ballistic arcs found and *predicted* in a synthetic ball-launcher feed; the example conforms its own `FrameSource`, so a simulation is the tracker's camera (`TrajectoryTracker`, `DetectedTrajectory`) |

These examples need a camera, and they ask for camera permission on first run (the system prompts from `swift run`). The exceptions are TrajectoryTracking and DigitReader, which are self-contained and run with no camera at all. ContourTrace is a partial exception: handed a clip path on launch, it traces the file instead of the camera. DepthRelief, DepthContours, ObjectDetection, PaintByClass, DigitReader, and TugOfWords also need their models downloaded once with `Scripts/fetch-models.sh`. The weights are fetched, never committed. StyleMirror wants a model you train yourself (below). Run one with `swift run Example-Vision-<Name>`, for example `swift run Example-Vision-WebcamFeed`.

### Training the StyleMirror model

StyleMirror runs a model that is *your own work*, so there is nothing to download and no license to check. The Create ML app no longer offers its Style Transfer template, but the CreateML framework still trains them. The repo wraps that training in one command, which you run from the repo root:

```sh
swift Scripts/train-style-model.swift path/to/any-image.jpg
```

Any image works as the style: a painting, a texture, or an export of one of your own sketches. A couple of minutes later `Models/StyleTransfer.mlmodel` exists and StyleMirror starts painting. The sketch watches for the file, so you can train while it runs and see the style arrive.

The flags, all optional:

| Flag | What it does |
|---|---|
| `--content <folder>` | your own photos as training *content*, the images that teach the model to preserve structure; defaults to frames pulled from the repo's sample clip |
| `--iterations <n>` | more iterations give a finer style (default 200, about two minutes) |
| `--strength <1-10>` | how strongly the style is applied (default 5) |
| `--quality` | the heavier image-quality network instead of the lighter real-time one that the live mirror wants |
| `--out <path>` | write the model somewhere else (default `Models/StyleTransfer.mlmodel`) |
