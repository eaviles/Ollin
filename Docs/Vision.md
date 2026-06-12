#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Vision`</sup>

---

## Vision

See with the Mac's camera. Vision lives in a separate library so the drawing core stays free of `AVFoundation` and Apple's Vision framework — add `import OllinVision` alongside `import Ollin` to reach it.

There are two pieces. A [`Camera`](#camera) captures frames from the built-in camera, a Continuity Camera iPhone, or an external webcam, and hands them over as drawable `Image`s. A **tracker** attached to a [frame source](#frame-sources) — that camera, or a playing [`VideoPlayer`](./Video.md) — runs Apple's on-device perception on each frame and publishes typed results you read in `draw()`. The first tracker is [`FaceTracker`](#facetracker); more (hands, bodies, segmentation, contours, text, …) follow the same shape.

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
- [Frame sources](#frame-sources) — trackers over any source of frames (a video, your own)
- [FaceTracker](#facetracker) — find faces, landmarks, and head pose
- [Face](#face) — one detected face, and reading its parts
- [ContourDetector](#contourdetector) — trace edges into vector contours
- [DetectedContours](#detectedcontours) — contours as `Contour`s and `Shape`s
- [HandTracker](#handtracker) — find hands and their 21-joint skeletons
- [Hand](#hand) — one detected hand, its joints and fingers
- [BodyTracker](#bodytracker) — find people and their pose skeletons
- [PersonSegmenter](#personsegmenter) — lift the people out of the frame
- [SubjectSegmenter](#subjectsegmenter) — lift whatever stands out as foreground
- [Segmentation](#segmentation) — a soft matte and the cutout it makes
- [RectangleDetector](#rectangledetector) — find rectangular shapes and their corners
- [BarcodeScanner](#barcodescanner) — read barcodes and QR codes
- [TextRecognizer](#textrecognizer) — read text (OCR) from the feed
- [ObjectTracker](#objecttracker) — follow a patch you point at across frames
- [TrackedObject](#trackedobject) — the tracked box and its confidence
- [TrajectoryTracker](#trajectorytracker) — find things flying along parabolic arcs
- [DetectedTrajectory](#detectedtrajectory) — one arc: its points, fit, and identity
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

<a name="frame-sources"></a>

### Frame sources

```swift
protocol FrameSource: AnyObject {       // lives in the Ollin core
    var frameTap: FrameTap? { get set }
}
typealias FrameTap = @Sendable (CGImage) -> Void
```

Every tracker takes `any FrameSource`, not just a camera — the seam that lets the same perception run over any source of moving pictures. `Camera` conforms, and so does [`VideoPlayer`](./Video.md), so a tracker runs over recorded footage exactly the way it runs over the live feed:

```swift
import Ollin
import OllinVideo
import OllinVision

final class Traced: Sketch {
    let player = try! VideoPlayer(path: "/path/to/clip.mp4")
    lazy var contours = ContourDetector(player)   // analyzed as it plays

    override func setup() {
        player.loops = true
        player.play()
    }
}
```

Trackers attached to the same source share one analysis engine, so the source is tapped once and its frames fan out. Analysis is throttled to what the machine keeps up with (frames are skipped, never queued), and a paused video stops producing frames, so its trackers simply hold their last results.

A type of your own can join the seam too: conform to `FrameSource` (hold the closure, call it with each new `CGImage` from whatever thread produces them) and every tracker accepts it. `Examples/Vision/TrajectoryTracking` does exactly that — its "camera" is a little ball-launching simulation the example renders itself.

<a name="facetracker"></a>

### FaceTracker

```swift
FaceTracker(_ source: any FrameSource)
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
ContourDetector(_ source: any FrameSource, detectsDarkOnLight: Bool = true, contrastAdjustment: Float = 1)
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
HandTracker(_ source: any FrameSource, maximumHandCount: Int = 2)
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
BodyTracker(_ source: any FrameSource)
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

<a name="personsegmenter"></a>

### PersonSegmenter

```swift
PersonSegmenter(_ source: any FrameSource, quality: Quality = .balanced)
var matte: Image? { get }
var cutout: Image? { get }
static func detect(in: Image, quality: Quality = .accurate) async throws -> Segmentation?
```

Segments the people out of the frame. Where the pose trackers reduce a person to joints, this gives you their **pixels**: `matte` is a soft white silhouette of everyone in view (alpha = per-pixel confidence; `tint(_:)` recolors it into a shadow, a glow, a flat silhouette), and `cutout` is the frame's own pixels with the background gone — you, lifted, ready to composite over anything the sketch draws. Both are plain `Image`s: draw them into the same rectangle as the frame and they sit exactly on the picture.

```swift
let camera = Camera()
lazy var people = PersonSegmenter(camera)
override func draw() {
    drawMyBackground()                        // anything — the replacement backdrop
    let rect = camera.fittedRect(in: bounds) ?? bounds
    if let cutout = people.cutout { drawImage(cutout, in: rect) }
}
```

`quality` trades matte resolution for speed: `.fast` for the lowest latency, `.balanced` (the live default), `.accurate` for the finest edges (the still-image default). It's a neural model — see [Availability](#availability).

Each of the two images is converted only for the surfaces your sketch actually reads — the first read of `matte` or `cutout` turns its conversion on, so a sketch reading only the matte never pays for the cutout. (That first read can come back `nil` once; the next analyzed frame publishes.) The same applies to `SubjectSegmenter` below.

<a name="subjectsegmenter"></a>

### SubjectSegmenter

```swift
SubjectSegmenter(_ source: any FrameSource)
var matte: Image? { get }
var cutout: Image? { get }
var count: Int { get }
static func detect(in: Image) async throws -> Segmentation?
```

Lifts the **salient subject** — the thing held up to the camera, the object on the table, people included — rather than specifically people. The same `matte`/`cutout` pair as `PersonSegmenter` (all subjects combined), plus `count`, how many distinct subjects the model found. While nothing stands out as foreground, `matte` and `cutout` are `nil` and `count` is `0`; the still-image `detect(in:)` likewise returns `nil` when nothing lifts.

```swift
let camera = Camera()
lazy var subjects = SubjectSegmenter(camera)
override func draw() {
    let rect = camera.fittedRect(in: bounds) ?? bounds
    if let frame = camera.frame {
        tint(Color(white: 0.3)); drawImage(frame, in: rect); noTint()   // the room, dimmed
    }
    if let cutout = subjects.cutout { drawImage(cutout, in: rect) }     // the subject, lit
}
```

<a name="segmentation"></a>

### Segmentation

```swift
struct Segmentation {
    var matte: Image     // white silhouette, alpha = per-pixel confidence
    var cutout: Image    // the source's pixels where the matte is on
}
```

What the still-image `detect(in:)` calls return — the same two images the live trackers publish as properties. The matte is at the model's resolution (drawing it into the source's rectangle rescales it onto the picture); the cutout is at the source's own resolution.

<a name="rectangledetector"></a>

### RectangleDetector

```swift
RectangleDetector(_ source: any FrameSource, minimumAspectRatio: Float = 0.2,
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
BarcodeScanner(_ source: any FrameSource)
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
TextRecognizer(_ source: any FrameSource, level: Level = .fast)
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

<a name="objecttracker"></a>

### ObjectTracker

```swift
ObjectTracker(_ source: any FrameSource)
func track(_ region: Rectangle, in frameRect: Rectangle, mirrored: Bool = false)
func track(centeredAt: Vector2, size: Double, in frameRect: Rectangle, mirrored: Bool = false)
func track(normalized: Rectangle)
func stop()
var trackedObject: TrackedObject? { get }
var isTracking: Bool { get }
static func track(_ seed: Rectangle, across: [Image]) async throws -> [TrackedObject]
```

The other trackers *detect* — they find faces or rectangles on their own. This one *tracks*: you hand it a box (where something is right now) and it follows that same patch frame to frame as it moves, so you can keep tabs on an object the recognizers have no model for. It's a classical tracker (no neural model), so it runs on any Mac.

Seed it from a click with `track(centeredAt:size:in:)`, from a box you drew with `track(_:in:)`, or from another detector's result by passing its `bounds(in:)` — then read `trackedObject` each frame. Call a `track(…)` method again to re-target, or `stop()` to let go.

```swift
let camera = Camera()
lazy var tracker = ObjectTracker(camera)
var view = Rectangle(x: 0, y: 0, width: 1, height: 1)

override func draw() {
    guard let frame = camera.frame else { return }
    view = camera.fittedRect(in: bounds) ?? bounds
    drawImage(frame, in: view)
    if let object = tracker.trackedObject {
        noFill(); stroke(.green)
        drawRect(object.bounds(in: view))
    }
}

override func mousePressed() {
    tracker.track(centeredAt: Vector2(mouseX, mouseY), size: 160, in: view)
}
```

The static `track(_:across:)` follows a patch through an ordered array of frames with no camera — handy for a recorded clip.

<a name="trackedobject"></a>

### TrackedObject

```swift
var confidence: Double { get }
func bounds(in: Rectangle, mirrored: Bool = false) -> Rectangle
func center(in: Rectangle, mirrored: Bool = false) -> Vector2
```

Where the tracked patch is now and how sure the tracker is. `confidence` stays high while the patch is clearly in view and falls as it's occluded, leaves the frame, or moves too fast — a good value to fade an overlay by, or to threshold on to decide the object's been lost (then `track(…)` again to re-lock).

<a name="trajectorytracker"></a>

### TrajectoryTracker

```swift
TrajectoryTracker(_ source: any FrameSource, trajectoryLength: Int = 10,
                  minimumObjectRadius: Double? = nil, maximumObjectRadius: Double? = nil)
var trajectories: [DetectedTrajectory] { get }
func reset()
static func detect(across: [Image], frameRate: Double = 30,
                   trajectoryLength: Int = 10) async throws -> [[DetectedTrajectory]]
```

Where `ObjectTracker` follows a patch you point at, this one watches for **ballistic motion** on its own: anything small that flies along a parabola — a thrown ball, a bounce — comes back as a `DetectedTrajectory`, an arc of points with the fitted curve. It's classical (no neural model), so it runs on any Mac. Two things it needs: the camera held still (a moving camera turns the whole scene into motion), and a beat of patience — an arc is reported only once the object has been seen `trajectoryLength` times.

```swift
let camera = Camera()
lazy var tracker = TrajectoryTracker(camera)

override func draw() {
    guard let frame = camera.frame else { return }
    let view = camera.fittedRect(in: bounds) ?? bounds
    drawImage(frame, in: view)
    for arc in tracker.trajectories {
        stroke(Color(red: 0.35, green: 1, blue: 0.6, alpha: arc.confidence))
        drawPolyline(arc.projectedPoints(in: view))
    }
}
```

The optional radius bounds (fractions of the frame, `0…1`) filter what counts as a moving object — set `maximumObjectRadius` to ignore large movers like a person crossing the scene. Call `reset()` after the scene jumps (a video loop, a seek) so the discontinuity isn't read as motion. The static `detect(across:frameRate:)` finds the arcs in an ordered array of frames with no camera — a recorded clip's frames, paced at `frameRate`.

<a name="detectedtrajectory"></a>

### DetectedTrajectory

```swift
var id: UUID { get }
var confidence: Double { get }
func detectedPoints(in: Rectangle, mirrored: Bool = false) -> [Vector2]
func projectedPoints(in: Rectangle, mirrored: Bool = false) -> [Vector2]
var equationCoefficients: SIMD3<Double> { get }
var normalizedRadius: Double { get }
var timeRange: ClosedRange<Double>? { get }
```

One arc. `detectedPoints(in:)` is the path as observed (the raw sightings, in travel order); `projectedPoints(in:)` is the same span projected onto the fitted parabola — the smoothed path, and the better one to draw. The fit itself is `equationCoefficients`: in normalized space (lower-left origin), `y = c.x·x² + c.y·x + c.z`, which you can sample *past* the last point to predict where the arc is headed.

An arc keeps its `id` as more of it comes into view, so accumulate results by `id` to build trails that outlive any single frame's detection — and fade them by `confidence`, which is how sure the detector is that the points form one real trajectory.

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

The inverse goes the other way — a point or box you drew (canvas space) back to normalized coordinates, which is how `ObjectTracker` is seeded from where something sits on the canvas:

```swift
VisionSpace.normalizedPoint(_ canvasPoint: Vector2, in: Rectangle, mirrored: Bool = false) -> Vector2
VisionSpace.normalizedRectangle(_ canvasRect: Rectangle, in: Rectangle, mirrored: Bool = false) -> Rectangle
```

<a name="still-images"></a>

### Still images

Every tracker also runs once on an image you loaded, no camera needed — useful for analyzing photos, and how the framework tests detection:

```swift
let image = loadImage("crowd.jpg")!
let found = try await FaceTracker.detect(in: image)
print("\(found.count) faces")
```

The two trackers that work *across* frames are the exception — one frame isn't enough — so their camera-free forms take an ordered sequence instead: `ObjectTracker.track(seed, across: frames)` and `TrajectoryTracker.detect(across: frames)`.

<a name="availability"></a>

### Availability

Some Vision models — body pose especially — need a compute device (a Neural Engine or a capable GPU) that not every Mac has. On a Mac without one, the model can't run, and rather than silently reporting nothing, a tracker tells you:

```swift
if !bodies.isAvailable {
    drawText(bodies.unavailableReason ?? "Unavailable", width / 2, height / 2)
}
```

`isAvailable` is `false` only when the model genuinely can't run here (a transient error doesn't flip it); `unavailableReason` is a short human-readable explanation. The tracker also logs the reason once to the console. Face, hands, and contours run on nearly any Mac; body pose, segmentation, and the heavier models want Apple silicon.

<a name="permission"></a>

### Permission

Using the camera needs the user's permission; `start()` requests it the first time it runs. Until the user grants it, `frame` stays `nil` and trackers report nothing. From `swift run` the system prompts on first use; a packaged app should include a camera-usage description (`NSCameraUsageDescription`).
