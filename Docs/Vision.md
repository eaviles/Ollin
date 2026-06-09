#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Vision`</sup>

---

## Vision

See with the Mac's camera. Vision lives in a separate library so the drawing core stays free of `AVFoundation` and Apple's Vision framework — add `import OllinVision` alongside `import Ollin` to reach it.

There are two pieces. A [`Camera`](#camera) captures frames from the built-in camera, a Continuity Camera iPhone, or an external webcam, and hands them over as drawable `Image`s. A **tracker** attached to that camera runs Apple's on-device perception on each frame and publishes typed results you read in `draw()`. The first tracker is [`FaceTracker`](#facetracker); more (hands, bodies, segmentation, contours, text, …) follow the same shape.

The usual flow: make a camera in `setup()` and `start()` it, attach the trackers you want, then in `draw()` draw `camera.frame` and read each tracker's results.

```swift
import Ollin
import OllinVision

final class Faces: Sketch {
    let camera = Camera()
    lazy var faces = FaceTracker(camera)

    override func setup() { try? camera.start() }

    override func draw() {
        background(.black)
        guard let frame = camera.frame else { return }
        let rect = camera.fittedRect(in: bounds) ?? bounds
        drawImage(frame, in: rect)

        noFill(); stroke(.green); strokeWeight(2)
        for face in faces.faces {
            drawRect(face.bounds(in: rect))
        }
    }
}
```

### Contents

- [Camera](#camera) — capture the webcam (built-in, Continuity, or external)
- [FaceTracker](#facetracker) — find faces, landmarks, and head pose
- [Face](#face) — one detected face, and reading its parts
- [ContourDetector](#contourdetector) — trace edges into vector contours
- [DetectedContours](#detectedcontours) — contours as `Contour`s and `Shape`s
- [HandTracker](#handtracker) — find hands and their 21-joint skeletons
- [Hand](#hand) — one detected hand, its joints and fingers
- [BodyTracker](#bodytracker) — find people and their pose skeletons
- [RectangleDetector](#rectangledetector) — find rectangular shapes and their corners
- [BarcodeScanner](#barcodescanner) — read barcodes and QR codes
- [TextRecognizer](#textrecognizer) — read text (OCR) from the feed
- [Coordinate mapping](#coordinate-mapping) — placing normalized results on the canvas
- [Still images](#still-images) — running a tracker on a loaded image
- [Availability](#availability) — when a model can't run on a Mac
- [Permission](#permission) — the camera prompt

<a name="camera"></a>

### Camera

```swift
Camera(_ device: Camera.Device = .default)
func start() throws
func stop()
var frame: Image? { get }
var frameSize: Vector2? { get }
func fittedRect(in container: Rectangle) -> Rectangle?
```

A frame source. Create it in `setup()`, `start()` it, and draw `frame` (the latest captured frame, or `nil` before the first one arrives) in `draw()`. `fittedRect(in:)` is the letterboxed rectangle that fits the frame inside a container without stretching — draw the frame into it and map results into the same rectangle so overlays line up.

`Camera.Device` picks which camera: `.default` (the system default), `.builtIn`, `.continuity` (a nearby iPhone), `.external` (a USB/Thunderbolt webcam), or `.deskView`.

```swift
let camera = Camera(.continuity)   // use a Continuity Camera iPhone
```

A fresh `Image` is produced each new frame, so draw `camera.frame` directly in `draw()` rather than holding onto it across frames.

<a name="facetracker"></a>

### FaceTracker

```swift
FaceTracker(_ camera: Camera)
var faces: [Face] { get }
var count: Int { get }
static func detect(in image: Image) async throws -> [Face]
```

Finds faces in a camera's frames: their bounding box, head pose (`roll`/`yaw`/`pitch`), a capture-quality score, and 76-point landmarks (jaw, brows, eyes, nose, lips, pupils). Attach it to a camera, then read `faces` in `draw()`.

```swift
let camera = Camera()
lazy var faces = FaceTracker(camera)
```

Analysis runs on a background thread; if recognition is slower than the camera's frame rate, frames are dropped so the sketch stays responsive (the displayed `frame` is never dropped — only the analysis is throttled). `faces` always holds the most recent result.

<a name="face"></a>

### Face

```swift
struct Face {
    var confidence: Double
    var roll, yaw, pitch: Double          // radians
    var quality: Double?                  // 0…1 capture quality, if scored
    var hasLandmarks: Bool

    func bounds(in: Rectangle, mirrored: Bool = false) -> Rectangle
    func center(in: Rectangle, mirrored: Bool = false) -> Vector2
    func landmarks(_: FaceLandmark, in: Rectangle, mirrored: Bool = false) -> [Vector2]
}
```

One detected face. The `in:` helpers map it onto the canvas — pass the same rectangle you drew the frame into. `landmarks(_:in:)` returns the points of one region (`.faceContour`, `.leftEye`, `.rightEye`, `.leftEyebrow`, `.rightEyebrow`, `.nose`, `.noseCrest`, `.medianLine`, `.outerLips`, `.innerLips`, `.leftPupil`, `.rightPupil`, or `.allPoints`) ready to `drawPolyline`. Loop regions like the eyes and lips read closed; append the first point to close them.

```swift
for face in faces.faces {
    drawRect(face.bounds(in: rect))
    drawPolyline(face.landmarks(.faceContour, in: rect))
    for p in face.landmarks(.leftPupil, in: rect) { drawCircle(p.x, p.y, 3) }
}
```

<a name="contourdetector"></a>

### ContourDetector

```swift
ContourDetector(_ camera: Camera, detectsDarkOnLight: Bool = true, contrastAdjustment: Float = 1)
var latest: DetectedContours { get }
var count: Int { get }
func contours(in: Rectangle, mirrored: Bool = false) -> [Contour]
func shapes(in: Rectangle, mirrored: Bool = false) -> [Shape]
static func detect(in: Image, …) async throws -> DetectedContours
```

Where the other trackers find *things*, this one finds *edges* — the boundaries between light and dark — and hands them back as Ollin geometry. That makes a live camera frame **vector**: the traced `Shape`s ride the same path as any other geometry, so `drawShape`, [SVG export](./Export.md), and the hatching transform all work on them, the kind of thing a pen plotter wants.

```swift
let camera = Camera()
let contours = ContourDetector(camera)
override func draw() {
    background(.white)
    noFill(); stroke(.black)
    for shape in contours.shapes(in: bounds) { drawShape(shape) }
}
```

`detectsDarkOnLight` (the default) traces dark shapes on a light background — good for line art and documents. `contrastAdjustment` (`0…3`) boosts faint edges at the cost of more noise. Point the camera at high-contrast subjects for the cleanest result. Like every tracker it also runs one-shot on a still image (`ContourDetector.detect(in:)`).

<a name="detectedcontours"></a>

### DetectedContours

```swift
struct DetectedContours {
    var topLevel: [Node]      // each Node has points + nested children
    var count: Int
    func contours(in: Rectangle, mirrored: Bool = false) -> [Contour]
    func shapes(in: Rectangle, mirrored: Bool = false) -> [Shape]
}
```

The result of a contour trace: a tree of closed outlines, where a contour can contain nested contours (a shape with a hole, a ring inside a disk). `contours(in:)` flattens the tree to closed `Contour`s mapped onto the canvas (for line work); `shapes(in:)` collects each top-level contour and its descendants into one even-odd `Shape`, so the nesting reads correctly when filled, hatched, or exported.

<a name="handtracker"></a>

### HandTracker

```swift
HandTracker(_ camera: Camera, maximumHandCount: Int = 2)
var hands: [Hand] { get }
var count: Int { get }
static func detect(in: Image, maximumHandCount: Int = 2) async throws -> [Hand]
```

Finds hands and their 21-joint skeletons — the most expressive tracker for gesture work. Read `hands` in `draw()`. Joints Vision isn't confident about (occluded, off-frame) are dropped, so what you get back is what it actually saw.

```swift
let camera = Camera()
let hands = HandTracker(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    for hand in hands.hands {
        for (a, b) in hand.bones(in: bounds) { drawLine(a, b) }
    }
}
```

Gestures fall out of a few joints: the distance between `.thumbTip` and `.indexTip` is a pinch, `.indexTip` alone is a cursor, the spread of the fingertips is an open or closed hand.

<a name="hand"></a>

### Hand

```swift
struct Hand {
    var chirality: Chirality        // .left, .right, or .unknown
    var confidence: Double
    func has(_: HandJoint) -> Bool
    func point(_: HandJoint, in: Rectangle, mirrored: Bool = false) -> Vector2?
    func points(in: Rectangle, mirrored: Bool = false) -> [HandJoint: Vector2]
    func finger(_: Finger, in: Rectangle, mirrored: Bool = false) -> [Vector2]
    func bones(in: Rectangle, mirrored: Bool = false) -> [(Vector2, Vector2)]
}
```

One detected hand. `point(_:in:)` maps a single joint (or `nil` if it wasn't seen); `points(in:)` maps them all; `finger(_:in:)` returns one finger's chain as a polyline (wrist to tip); `bones(in:)` returns the whole skeleton as line segments, breaking a chain at any missing joint rather than drawing across the gap.

The joints are `HandJoint` — `.wrist` plus four per finger (`.indexMCP`, `.indexPIP`, `.indexDIP`, `.indexTip`, and so on), with `HandJoint.tips` for the five fingertips. A `Finger` (`.thumb`, `.index`, `.middle`, `.ring`, `.little`) has a `.chain` of its joints.

<a name="bodytracker"></a>

### BodyTracker

```swift
BodyTracker(_ camera: Camera)
var bodies: [Body] { get }
var count: Int { get }
static func detect(in: Image) async throws -> [Body]
```

Finds people and their 2D pose skeletons — 19 joints from head to ankles. Where `HandTracker` is the close-up tool, this is the whole-body one: reach, lean, jump, and silhouette all read from the joints. Joints out of view (often the legs at a desk) are dropped, so the figure is whatever Vision can see.

```swift
let camera = Camera()
let bodies = BodyTracker(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    for body in bodies.bodies {
        for (a, b) in body.bones(in: bounds) { drawLine(a, b) }
    }
}
```

`Body` mirrors `Hand`: `point(_:in:)` maps a single `BodyJoint` (or `nil`), `points(in:)` maps them all, and `bones(in:)` returns the skeleton as line segments (`Body.skeleton` is the joint-pair list — head, spine, arms, legs). Note that body pose is a heavier model — see [Availability](#availability).

<a name="rectangledetector"></a>

### RectangleDetector

```swift
RectangleDetector(_ camera: Camera, minimumAspectRatio: Float = 0.2,
                  maximumAspectRatio: Float = 1.0, minimumSize: Float = 0.1,
                  minimumConfidence: Float = 0.6, maximumCount: Int = 8)
var rectangles: [DetectedRectangle] { get }
static func detect(in: Image, …) async throws -> [DetectedRectangle]
```

Finds rectangular shapes — a sheet of paper, a screen, a card, a sign — even seen at an angle, and reports their four corners. Unlike the pose and segmentation models, this is a *classical* detector (no ML), so it runs on any Mac. The aspect/size/confidence knobs tune what counts as a rectangle.

```swift
let camera = Camera()
let rects = RectangleDetector(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    noFill(); stroke(.green)
    for r in rects.rectangles { drawPolygon(r.corners(in: bounds)) }
}
```

A `DetectedRectangle` is `corners(in:)` (the four corners in perimeter order, ready to `drawPolygon` as a closed quad), `center(in:)`, and a `confidence`. The corners come back in perspective, which is exactly what a document scanner uses to warp a page flat.

<a name="barcodescanner"></a>

### BarcodeScanner

```swift
BarcodeScanner(_ camera: Camera)
var barcodes: [DetectedBarcode] { get }
static func detect(in: Image) async throws -> [DetectedBarcode]
```

Reads barcodes and QR codes and decodes their payload. Also classical, so it runs on any Mac. Point it at a QR code to pull a URL or a bit of text out of the world and into a sketch — a simple way to hand a running piece some input.

```swift
let camera = Camera()
let codes = BarcodeScanner(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    for code in codes.barcodes {
        drawPolygon(code.corners(in: bounds))
        if let payload = code.payload { drawText(payload, code.center(in: bounds)) }
    }
}
```

A `DetectedBarcode` is its `payload` (the decoded text or URL, or `nil`), its `symbology` (`"QR"`, `"EAN13"`, …), a `confidence`, and `corners(in:)` / `center(in:)` for where it is.

<a name="textrecognizer"></a>

### TextRecognizer

```swift
TextRecognizer(_ camera: Camera, level: Level = .fast)
var lines: [DetectedText] { get }
var text: String { get }            // all lines joined
static func detect(in: Image, level: Level = .accurate) async throws -> [DetectedText]
```

Reads text out of the feed — Apple's OCR, the same engine behind Live Text, with its language coverage. Each line comes back with its text and position. `level` trades speed for thoroughness: `.fast` keeps up with a live feed, `.accurate` reads more (the default for still images).

```swift
let camera = Camera()
let reader = TextRecognizer(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    for line in reader.lines {
        drawRect(line.bounds(in: bounds))
        drawText(line.text, line.bounds(in: bounds).corner)
    }
}
```

A `DetectedText` is its `text`, a `confidence`, and `corners(in:)` / `bounds(in:)` for where the line sits. `reader.text` joins every line into one block.

<a name="coordinate-mapping"></a>

### Coordinate mapping

The recognizers report geometry in **normalized** coordinates — `0…1` across the frame, origin at the **lower-left**, y pointing up — the convention Apple's Vision framework uses. Ollin's canvas is the opposite: **pixels**, origin at the **top-left**, y pointing down. So a result has to be flipped in y and scaled to wherever the frame was drawn.

```
  normalized (what a tracker returns)      canvas (what you draw in)
  (0,1) ───────────── (1,1)                (0,0) ───────────── (w,0)
    │                   │                     │                   │
    │        · (x,y)    │        ──▶          │                   │
    │                   │                     │        · maps to  │
  (0,0) ───────────── (1,0)                (0,h) ───────────── (w,h)
      y up, lower-left                         y down, top-left
```

The `Face` helpers (`bounds(in:)`, `landmarks(_:in:)`) do this for you. Pass the rectangle you drew the frame into — usually `camera.fittedRect(in: bounds)` — so the overlay sits on the picture. Set `mirrored: true` when you draw the frame flipped left-to-right (the natural "selfie" orientation for a front camera) so the overlay flips with it.

For mapping points from a source the built-in trackers don't cover (say, a custom Core ML model), `VisionSpace` exposes the same math directly:

```swift
VisionSpace.point(_ x: Double, _ y: Double, in: Rectangle, mirrored: Bool = false) -> Vector2
VisionSpace.rectangle(_ normalized: Rectangle, in: Rectangle, mirrored: Bool = false) -> Rectangle
VisionSpace.fittedRect(imageSize: Vector2, in container: Rectangle) -> Rectangle
```

<a name="still-images"></a>

### Still images

Every tracker also runs once on an image you loaded, no camera needed — useful for analyzing photos, and how the framework tests detection:

```swift
let image = loadImage("crowd.jpg")!
let found = try await FaceTracker.detect(in: image)
print("\(found.count) faces")
```

<a name="availability"></a>

### Availability

Some Vision models — body pose especially — need a compute device (a Neural Engine or a capable GPU) that not every Mac has. On a Mac without one, the model can't run, and rather than silently reporting nothing, a tracker tells you:

```swift
if !bodies.isAvailable {
    drawText(bodies.unavailableReason ?? "Unavailable", width / 2, height / 2)
}
```

`isAvailable` is `false` only when the model genuinely can't run here (a transient error doesn't flip it); `unavailableReason` is a short human-readable explanation. The tracker also logs the reason once to the console. Face, hands, and contours run on nearly any Mac; body pose and the heavier models want Apple silicon.

<a name="permission"></a>

### Permission

Using the camera needs the user's permission; `start()` requests it the first time it runs. Until the user grants it, `frame` stays `nil` and trackers report nothing. From `swift run` the system prompts on first use; a packaged app should include a camera-usage description (`NSCameraUsageDescription`).
