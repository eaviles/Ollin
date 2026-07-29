#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Vision](./README.md) → `Vision`</sup>

---

## Vision

See with the Mac's camera. Vision lives in a separate library so the drawing core stays free of `AVFoundation` and Apple's Vision framework. Add `import OllinVision` alongside `import Ollin` to reach it.

There are two pieces. A [`Camera`](#camera) captures frames from the built-in camera, a Continuity Camera iPhone, or an external webcam, and hands them over as drawable `Image`s. A **tracker** attached to a [frame source](#frame-sources), meaning that camera or a playing [`VideoPlayer`](../Video/Video.md), runs Apple's on-device perception on each frame and publishes typed results you read in `draw()`. Every tracker follows the same shape: [`FaceTracker`](#facetracker) for faces, then hands, bodies, segmentation, contours, text, and on through [`ModelTracker`](#modeltracker), which runs **your own Core ML model** the same way.

The usual flow is to make a camera in `setup()` and `start()` it, attach the trackers you want, then in `draw()` draw the feed with `drawFrame(camera)` and read each tracker's results. `drawFrame` letterboxes the latest frame, shows a standard waiting notice until the first one arrives, and returns the rectangle to map results into.

```swift
import Ollin
import OllinVision

final class Faces: Sketch {
    let camera = Camera()
    lazy var faces = FaceTracker(camera)

    override func setup() { try? camera.start() }

    override func draw() {
        background(.black)
        guard let rect = drawFrame(camera) else { return }

        noFill(); stroke(.green); strokeWeight(2)
        for face in faces.faces {
            drawRect(face.bounds(in: rect))
        }
    }
}
```

### Contents

- [Camera](#camera) - capture the webcam (built-in, Continuity, or external)
- [Frame sources](#frame-sources) - trackers over any source of frames (a video, your own)
- [FaceTracker](#facetracker) - find faces, landmarks, and head pose
- [Face](#face) - one detected face, and reading its parts
- [ContourDetector](#contourdetector) - trace edges into vector contours
- [DetectedContours](#detectedcontours) - contours as `Contour`s and `Shape`s
- [HandTracker](#handtracker) - find hands and their 21-joint skeletons
- [Hand](#hand) - one detected hand, its joints and fingers
- [BodyTracker](#bodytracker) - find people and their pose skeletons
- [BodyTracker3D](#bodytracker3d) - one person's pose in space, in meters
- [Body3D](#body3d) - the 3D skeleton in canvas, model, and camera space
- [PersonSegmenter](#personsegmenter) - lift the people out of the frame
- [SubjectSegmenter](#subjectsegmenter) - lift whatever stands out as foreground
- [Segmentation](#segmentation) - a soft matte and the cutout it makes
- [RectangleDetector](#rectangledetector) - find rectangular shapes and their corners
- [BarcodeScanner](#barcodescanner) - read barcodes and QR codes
- [TextRecognizer](#textrecognizer) - read text (OCR) from the feed
- [ObjectTracker](#objecttracker) - follow a patch you point at across frames
- [TrackedObject](#trackedobject) - the tracked box and its confidence
- [TrajectoryTracker](#trajectorytracker) - find things flying along parabolic arcs
- [DetectedTrajectory](#detectedtrajectory) - one arc: its points, fit, and identity
- [FlowTracker](#flowtracker) - measure optical flow, the whole picture's motion
- [MotionField](#motionfield) - the motion field, sampled anywhere on the canvas
- [ImageClassifier](#imageclassifier) - name what's in the picture
- [Classification](#classification) - one label and how strongly it applies
- [SaliencyTracker](#saliencytracker) - map what draws the eye
- [Saliency](#saliency) - the heat map, regions, and point query
- [ModelTracker](#modeltracker) - run your own Core ML model over the frames
- [ModelOutput](#modeloutput) - its decoded surfaces: labels, objects, map
- [ClassMask](#classmask) - a semantic segmenter's output: every pixel named
- [Coordinate mapping](#coordinate-mapping) - placing normalized results on the canvas
- [Still images](#still-images) - running a tracker on a loaded image
- [Availability](#availability) - when a model can't run on a Mac
- [Permission](#permission) - the camera prompt

<a name="camera"></a>

### Camera

```swift
Camera(_ device: Camera.Device = .default)
func start() throws
func stop()
var frame: Image? { get }
var frameSize: Vector2? { get }
func fittedRect(in container: Rectangle) -> Rectangle?

// on Sketch, for any VideoFeed (a Camera, a VideoPlayer, your own):
@discardableResult
func drawFrame(_ feed: some VideoFeed, in container: Rectangle? = nil,
               waiting: String? = nil) -> Rectangle?
```

A frame source. Create it in `setup()`, `start()` it, and draw it with `drawFrame(camera)` in `draw()`. That draws the latest frame letterboxed into the canvas (or `container`) and returns the rectangle it landed in, so map every tracker result into that same rectangle and the overlays line up. Before the first frame arrives it draws a standard waiting notice instead ("Waiting for camera…", which `waiting:` changes) and returns `nil`, so a camera sketch opens with one line:

```swift
guard let rect = drawFrame(camera) else { return }
```

`drawFrame` works on any `VideoFeed`, the core protocol `Camera` and [`VideoPlayer`](../Video/Video.md) conform to (`frame`, `frameSize`, and the letterboxing `fittedRect(in:)` come with it). Reaching for the typed pieces, `frame` is the latest captured frame (or `nil` before the first one), and `fittedRect(in:)` is the letterboxed rectangle alone, which a sketch uses when it draws a frame's *derivatives* (a segmentation matte, a cutout) rather than the frame itself.

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

Every tracker takes `any FrameSource`, not just a camera, which is the seam that lets the same perception run over any source of moving pictures. `Camera` conforms, and so does [`VideoPlayer`](../Video/Video.md), so a tracker runs over recorded footage exactly the way it runs over the live feed:

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

A type of your own can join the seam too. Conform to `FrameSource` (hold the closure, call it with each new `CGImage` from whatever thread produces them) and every tracker accepts it. `Examples/Vision/TrajectoryTracking` does exactly that, since its "camera" is a little ball-launching simulation the example renders itself.

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

Analysis runs on a background thread, and if recognition is slower than the camera's frame rate, frames are dropped so the sketch stays responsive (the displayed `frame` is never dropped, only the analysis is throttled). `faces` always holds the most recent result.

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

One detected face. The `in:` helpers map it onto the canvas, so pass the same rectangle you drew the frame into. `landmarks(_:in:)` returns the points of one region (`.faceContour`, `.leftEye`, `.rightEye`, `.leftEyebrow`, `.rightEyebrow`, `.nose`, `.noseCrest`, `.medianLine`, `.outerLips`, `.innerLips`, `.leftPupil`, `.rightPupil`, or `.allPoints`) ready to `drawPolyline`. Loop regions like the eyes and lips read closed, so append the first point to close them.

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

Where the other trackers find *things*, this one finds *edges*, the boundaries between light and dark, and hands them back as Ollin geometry. That makes a live camera frame **vector**, so the traced `Shape`s ride the same path as any other geometry and `drawShape`, [SVG export](../Output/Export.md), and the hatching transform all work on them, the kind of thing a pen plotter wants.

```swift
let camera = Camera()
let contours = ContourDetector(camera)
override func draw() {
    background(.white)
    noFill(); stroke(.black)
    for shape in contours.shapes(in: bounds) { drawShape(shape) }
}
```

`detectsDarkOnLight` (the default) traces dark shapes on a light background, which suits line art and documents. `contrastAdjustment` (`0…3`) boosts faint edges at the cost of more noise. Point the camera at high-contrast subjects for the cleanest result. Like every tracker it also runs one-shot on a still image (`ContourDetector.detect(in:)`).

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

The result of a contour trace is a tree of closed outlines, where a contour can contain nested contours (a shape with a hole, a ring inside a disk). `contours(in:)` flattens the tree to closed `Contour`s mapped onto the canvas, for line work. `shapes(in:)` collects each top-level contour and its descendants into one even-odd `Shape`, so the nesting reads correctly when filled, hatched, or exported.

<a name="handtracker"></a>

### HandTracker

```swift
HandTracker(_ source: any FrameSource, maximumHandCount: Int = 2)
var hands: [Hand] { get }
var count: Int { get }
static func detect(in: Image, maximumHandCount: Int = 2) async throws -> [Hand]
```

Finds hands and their 21-joint skeletons, the most expressive tracker for gesture work. Read `hands` in `draw()`. Joints Vision isn't confident about (occluded, off-frame) are dropped, so what you get back is what it actually saw.

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

One detected hand. `point(_:in:)` maps a single joint, or `nil` if it wasn't seen, and `points(in:)` maps them all. `finger(_:in:)` returns one finger's chain as a polyline from wrist to tip, and `bones(in:)` returns the whole skeleton as line segments, breaking a chain at any missing joint rather than drawing across the gap.

The joints are `HandJoint`, meaning `.wrist` plus four per finger (`.indexMCP`, `.indexPIP`, `.indexDIP`, `.indexTip`, and so on), with `HandJoint.tips` for the five fingertips. A `Finger` (`.thumb`, `.index`, `.middle`, `.ring`, `.little`) has a `.chain` of its joints.

<a name="bodytracker"></a>

### BodyTracker

```swift
BodyTracker(_ source: any FrameSource)
var bodies: [Body] { get }
var count: Int { get }
static func detect(in: Image) async throws -> [Body]
```

Finds people and their 2D pose skeletons, 19 joints from head to ankles. Where `HandTracker` is the close-up tool, this is the whole-body one, so reach, lean, jump, and silhouette all read from the joints. Joints out of view (often the legs at a desk) are dropped, so the figure is whatever Vision can see.

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

`Body` mirrors `Hand`, so `point(_:in:)` maps a single `BodyJoint` (or `nil`), `points(in:)` maps them all, and `bones(in:)` returns the skeleton as line segments (`Body.skeleton` is the joint-pair list covering head, spine, arms, and legs). Body pose is a heavier model, so see [Availability](#availability).

<a name="bodytracker3d"></a>

### BodyTracker3D

```swift
BodyTracker3D(_ source: any FrameSource)
var body: Body3D? { get }
static func detect(in: Image) async throws -> Body3D?
```

Finds one person's pose **in space** from an ordinary 2D camera, putting every joint at a 3D position in meters where `BodyTracker` gives flat picture coordinates. The same single webcam, but now the sketch knows how far the person is, how tall they are, and what their figure looks like from the side.

Two ways it differs from the 2D tracker, both worth knowing before reaching for it:

- **One person.** The model follows the most prominent person, so the read surface is a singular `body` (`nil` while no one is in view), not a list. For counting people or multi-person scenes, use `BodyTracker`.
- **The full skeleton, always.** All 17 joints are placed every time, so joints the camera can't see are the model's best guess, and their canvas projections simply land outside the frame's rectangle rather than disappearing. There is no per-joint confidence. (The 2D tracker is the opposite, dropping what it can't see.)

It's a heavier neural model, so see [Availability](#availability).

<a name="body3d"></a>

### Body3D

```swift
var confidence: Double                      // 0…1
var height: Double                          // meters
var heightEstimation: HeightEstimation      // .reference or .measured
var distance: Double?                       // meters from the camera to the root
func has(_ joint: BodyJoint3D) -> Bool

// canvas: the overlay surface, like the other trackers
func point(_ joint: BodyJoint3D, in rect: Rectangle, mirrored: Bool = false) -> Vector2?
func points(in rect: Rectangle, mirrored: Bool = false) -> [BodyJoint3D: Vector2]
func bones(in rect: Rectangle, mirrored: Bool = false) -> [(Vector2, Vector2)]

// model space: meters, the pelvis root at the origin
func position(_ joint: BodyJoint3D) -> Vector3?
var positions: [BodyJoint3D: Vector3] { get }
func bones() -> [(Vector3, Vector3)]

// camera space: meters from the camera itself
func cameraRelativePosition(_ joint: BodyJoint3D) -> Vector3?

static let skeleton: [(BodyJoint3D, BodyJoint3D)]
```

One person's pose, readable in three spaces:

- **Canvas.** `point(_:in:)`, `points(in:)`, and `bones(in:)` work exactly like `Body`'s, giving the joints projected onto the frame and mapped into the rectangle you drew it in, for skeleton overlays.
- **Model space.** `position(_:)`, `positions`, and the no-argument `bones()` give meters, with the pelvis `root` at the origin, x to the picture's right, y up, and z pointing away from the camera. Because it's a real 3D figure, you can project it from *any* angle: `(x, y)` is the front view, `(z, y)` the side, and `(x, z)` the top, views no camera was at.
- **Camera space.** `cameraRelativePosition(_:)` gives meters from the camera itself (x right, y up, z out in front of the lens), so a joint's z is how far away it is. `distance` is the sugar for the distance to the person's root.

The 17 `BodyJoint3D` joints are the head (`topHead`, `centerHead`), shoulders (`centerShoulder`, left/right), arms (elbows, wrists), `spine` and `root`, and legs (hips, knees, ankles). That's a different set from the 2D `BodyJoint`, with no eyes or ears, because the 3D skeleton is built for the body in space rather than the face. `height` is the person's estimated height, and without real depth data `heightEstimation` is `.reference` (the skeleton scaled to a standard assumed height, which is what a webcam gives), turning `.measured` when the image carried depth (a LiDAR photo).

```swift
if let body = tracker.body {
    for (a, b) in body.bones(in: rect) { drawLine(a, b) }     // over the feed
    for (a, b) in body.bones() {                              // from the side, in meters
        drawLine(center + Vector2(a.z, -a.y) * 200, center + Vector2(b.z, -b.y) * 200)
    }
}
```

<a name="personsegmenter"></a>

### PersonSegmenter

```swift
PersonSegmenter(_ source: any FrameSource, quality: Quality = .balanced)
var matte: Image? { get }
var cutout: Image? { get }
static func detect(in: Image, quality: Quality = .accurate) async throws -> Segmentation?
```

Segments the people out of the frame. Where the pose trackers reduce a person to joints, this gives you their **pixels**. `matte` is a soft white silhouette of everyone in view, its alpha the per-pixel confidence, so `tint(_:)` recolors it into a shadow, a glow, or a flat silhouette. `cutout` is the frame's own pixels with the background gone, you lifted out and ready to composite over anything the sketch draws. Both are plain `Image`s, so draw them into the same rectangle as the frame and they sit exactly on the picture.

```swift
let camera = Camera()
lazy var people = PersonSegmenter(camera)
override func draw() {
    drawMyBackground()                        // anything, the replacement backdrop
    guard let rect = camera.fittedRect(in: bounds) else { return }
    if let cutout = people.cutout { drawImage(cutout, in: rect) }
}
```

`quality` trades matte resolution for speed: `.fast` for the lowest latency, `.balanced` (the live default), and `.accurate` for the finest edges (the still-image default). It's a neural model, so see [Availability](#availability).

Each of the two images is converted only for the surfaces your sketch actually reads, so the first read of `matte` or `cutout` turns its conversion on and a sketch reading only the matte never pays for the cutout. (That first read can come back `nil` once, and the next analyzed frame publishes.) The same applies to `SubjectSegmenter` below.

<a name="subjectsegmenter"></a>

### SubjectSegmenter

```swift
SubjectSegmenter(_ source: any FrameSource)
var matte: Image? { get }
var cutout: Image? { get }
var count: Int { get }
static func detect(in: Image) async throws -> Segmentation?
```

Lifts the **salient subject**, meaning the thing held up to the camera or the object on the table, people included, rather than specifically people. It gives the same `matte` and `cutout` pair as `PersonSegmenter` (all subjects combined), plus `count`, how many distinct subjects the model found. While nothing stands out as foreground, `matte` and `cutout` are `nil` and `count` is `0`, and the still-image `detect(in:)` likewise returns `nil` when nothing lifts.

```swift
let camera = Camera()
lazy var subjects = SubjectSegmenter(camera)
override func draw() {
    tint(Color(white: 0.3))                                             // the room, dimmed
    guard let rect = drawFrame(camera) else { return noTint() }
    noTint()
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

What the still-image `detect(in:)` calls return, the same two images the live trackers publish as properties. The matte is at the model's resolution, so drawing it into the source's rectangle rescales it onto the picture, while the cutout is at the source's own resolution.

<a name="rectangledetector"></a>

### RectangleDetector

```swift
RectangleDetector(_ source: any FrameSource, minimumAspectRatio: Float = 0.2,
                  maximumAspectRatio: Float = 1.0, minimumSize: Float = 0.1,
                  minimumConfidence: Float = 0.6, maximumCount: Int = 8)
var rectangles: [DetectedRectangle] { get }
static func detect(in: Image, …) async throws -> [DetectedRectangle]
```

Finds rectangular shapes (a sheet of paper, a screen, a card, a sign) even seen at an angle, and reports their four corners. Unlike the pose and segmentation models, this is a *classical* detector with no ML, so it runs on any Mac. The aspect, size, and confidence knobs tune what counts as a rectangle.

```swift
let camera = Camera()
let rects = RectangleDetector(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    noFill(); stroke(.green)
    for r in rects.rectangles { drawPolygon(r.corners(in: bounds)) }
}
```

A `DetectedRectangle` is `corners(in:)` (the four corners in perimeter order, ready to `drawPolygon` as a closed quad), `center(in:)`, `bounds(in:)` (the axis-aligned box containing the corners, ready to `drawRect`), and a `confidence`. The corners come back in perspective, which is exactly what a document scanner uses to warp a page flat. The same type carries [`SaliencyTracker`](#saliencytracker)'s salient regions, which arrive upright, so `bounds(in:)` is the natural read there.

<a name="barcodescanner"></a>

### BarcodeScanner

```swift
BarcodeScanner(_ source: any FrameSource)
var barcodes: [DetectedBarcode] { get }
static func detect(in: Image) async throws -> [DetectedBarcode]
```

Reads barcodes and QR codes and decodes their payload. Also classical, so it runs on any Mac. Point it at a QR code to pull a URL or a bit of text out of the world and into a sketch, a simple way to hand a running piece some input.

```swift
let camera = Camera()
let codes = BarcodeScanner(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    for code in codes.barcodes {
        drawPolygon(code.corners(in: bounds))
        if let payload = code.payload { drawText(payload, at: code.center(in: bounds)) }
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

Reads text out of the feed using Apple's OCR, the same engine behind Live Text, with its language coverage. Each line comes back with its text and position. `level` trades speed for thoroughness, so `.fast` keeps up with a live feed while `.accurate` reads more (the default for still images).

```swift
let camera = Camera()
let reader = TextRecognizer(camera)
override func draw() {
    if let frame = camera.frame { drawImage(frame, in: bounds) }
    for line in reader.lines {
        drawRect(line.bounds(in: bounds))
        drawText(line.text, at: line.bounds(in: bounds).corner)
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

The other trackers *detect*, finding faces or rectangles on their own. This one *tracks*, so you hand it a box (where something is right now) and it follows that same patch frame to frame as it moves, which keeps tabs on an object the recognizers have no model for. It's a classical tracker with no neural model, so it runs on any Mac.

Seed it from a click with `track(centeredAt:size:in:)`, from a box you drew with `track(_:in:)`, or from another detector's result by passing its `bounds(in:)`, then read `trackedObject` each frame. Call a `track(…)` method again to re-target, or `stop()` to let go.

```swift
let camera = Camera()
lazy var tracker = ObjectTracker(camera)
var view = Rectangle(x: 0, y: 0, width: 1, height: 1)

override func draw() {
    guard let rect = drawFrame(camera) else { return }
    view = rect
    if let object = tracker.trackedObject {
        noFill(); stroke(.green)
        drawRect(object.bounds(in: view))
    }
}

override func mousePressed() {
    tracker.track(centeredAt: Vector2(mouseX, mouseY), size: 160, in: view)
}
```

The static `track(_:across:)` follows a patch through an ordered array of frames with no camera, which is handy for a recorded clip.

<a name="trackedobject"></a>

### TrackedObject

```swift
var confidence: Double { get }
func bounds(in: Rectangle, mirrored: Bool = false) -> Rectangle
func center(in: Rectangle, mirrored: Bool = false) -> Vector2
```

Where the tracked patch is now and how sure the tracker is. `confidence` stays high while the patch is clearly in view and falls as it's occluded, leaves the frame, or moves too fast, which makes it a good value to fade an overlay by, or to threshold on to decide the object's been lost (then `track(…)` again to re-lock).

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

Where `ObjectTracker` follows a patch you point at, this one watches for **ballistic motion** on its own, so anything small that flies along a parabola, a thrown ball or a bounce, comes back as a `DetectedTrajectory`, an arc of points with the fitted curve. It's classical, with no neural model, so it runs on any Mac. It needs two things: the camera held still (a moving camera turns the whole scene into motion), and a beat of patience, since an arc is reported only once the object has been seen `trajectoryLength` times.

```swift
let camera = Camera()
lazy var tracker = TrajectoryTracker(camera)

override func draw() {
    guard let view = drawFrame(camera) else { return }
    for arc in tracker.trajectories {
        stroke(Color(red: 0.35, green: 1, blue: 0.6, alpha: arc.confidence))
        drawPolyline(arc.projectedPoints(in: view))
    }
}
```

The optional radius bounds (fractions of the frame, `0…1`) filter what counts as a moving object, so set `maximumObjectRadius` to ignore large movers like a person crossing the scene. Call `reset()` after the scene jumps (a video loop, a seek) so the discontinuity isn't read as motion. The static `detect(across:frameRate:)` finds the arcs in an ordered array of frames with no camera, a recorded clip's frames paced at `frameRate`.

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

One arc. `detectedPoints(in:)` is the path as observed, the raw sightings in travel order, and `projectedPoints(in:)` is the same span projected onto the fitted parabola, the smoothed path and the better one to draw. The fit itself is `equationCoefficients`, so in normalized space (lower-left origin) `y = c.x·x² + c.y·x + c.z`, which you can sample *past* the last point to predict where the arc is headed.

An arc keeps its `id` as more of it comes into view, so accumulate results by `id` to build trails that outlive any single frame's detection, and fade them by `confidence`, which is how sure the detector is that the points form one real trajectory.

<a name="flowtracker"></a>

### FlowTracker

```swift
FlowTracker(_ source: any FrameSource, accuracy: Accuracy = .medium)
var field: MotionField? { get }
func reset()
static func flow(from previous: Image, to current: Image,
                 accuracy: Accuracy = .high) async throws -> MotionField?
static func flow(across: [Image], accuracy: Accuracy = .medium) async throws -> [MotionField?]
```

Where `ObjectTracker` follows one patch and `TrajectoryTracker` finds arcs, this one measures **all** the motion. Optical flow is a dense field of vectors describing how every part of the picture moved since the previous analyzed frame. Wave a hand and the pixels under it get vectors, or pan the camera and the whole field drifts together. It's classical, with no neural model, so it runs on any Mac.

Read `field` each frame (it's `nil` until the second analyzed frame, since flow needs a pair) and sample it wherever you like (see [`MotionField`](#motionfield)). `accuracy` trades speed for a finer field (`.low` / `.medium` / `.high` / `.veryHigh`), and `.medium` keeps up with a live camera. Call `reset()` after the scene jumps (a video loop, a seek) so the discontinuity isn't read as one huge motion.

Two camera-free forms: `flow(from:to:)` measures a single pair of stills, and `flow(across:)` runs an ordered array of frames through the same frame-over-frame path the live tracker uses (its first entry is `nil`, since flow needs a frame before it).

<a name="motionfield"></a>

### MotionField

```swift
func vector(at point: Vector2, in rect: Rectangle, mirrored: Bool = false) -> Vector2
func samples(in rect: Rectangle, every step: Double = 24, mirrored: Bool = false) -> [Sample]
func averageFlow(in rect: Rectangle, mirrored: Bool = false) -> Vector2
func flowNormalized(at point: Vector2) -> Vector2
var averageFlowNormalized: Vector2 { get }
var confidence: Double { get }
var size: Vector2 { get }
```

The motion between the previous analyzed frame and this one, queryable anywhere. `vector(at:in:)` answers in canvas terms, "which way is the picture moving under this point, and how far", taking a canvas point and the rectangle you drew the frame into and returning a canvas-space vector, so it scales with how large you drew the frame. `samples(in:every:)` lays a regular grid of those over the rect, each a `Sample` with a `position` and the `flow` there, ready to draw as arrows. `averageFlow(in:)` is the global drift, so a camera pan reads as one shared direction while localized motion mostly averages out.

```swift
let camera = Camera()
lazy var flow = FlowTracker(camera)

override func draw() {
    guard let view = drawFrame(camera) else { return }

    if let field = flow.field {
        stroke(.white)
        for s in field.samples(in: view, every: 36) {
            drawLine(s.position, s.position + s.flow * 3)
        }
    }
}
```

Because every query is a read out of the underlying flow map, the field works as the input to anything: push particles by the vector under each one, drive a [physics](../Simulation/Physics.md) world's forces from the motion in front of the camera, or steer a brush by `averageFlow`. Two practical notes. Magnitudes are conservative estimates, so treat them as a signal you scale by a gain of your own rather than a calibrated speed (the analysis interval also breathes with load). And motion is only *measurable* where the picture has texture, so a flat, featureless area (a blank wall, a solid backdrop) doesn't read as zero motion, it reads as **noise**, since there's nothing to match frame to frame. Don't take stillness from a featureless region at face value, and if the scene is mostly flat, give it texture (even a faint static speckle behind the action) before trusting the field there.

`flowNormalized(at:)` and `averageFlowNormalized` are the raw surface for working in normalized coordinates yourself (`0…1`, lower-left origin, +y up, see [coordinate mapping](#coordinate-mapping)). `size` is the flow map's resolution, and `confidence` is the tracker's confidence in the field as a whole.

<a name="imageclassifier"></a>

### ImageClassifier

```swift
ImageClassifier(_ source: any FrameSource, minimumConfidence: Double = 0.1)
var labels: [Classification] { get }
var top: Classification? { get }
func confidence(of label: String) -> Double
static func detect(in: Image, minimumConfidence: Double = 0.1) async throws -> [Classification]
static func supportedLabels() -> [String]
```

Names what the picture shows (`"sky"`, `"people"`, `"dog"`, `"food"`) from a fixed vocabulary of about 1,300 everyday labels. Unlike the other trackers it reports no positions, so the result is *what's in the frame* and how confidently, which is exactly the right shape for a sketch that reacts to its surroundings rather than overlaying them.

```swift
let camera = Camera()
lazy var classifier = ImageClassifier(camera)

override func draw() {
    drawFrame(camera)

    for (i, found) in classifier.labels.prefix(5).enumerated() {
        drawText("\(found.name) \(Int(found.confidence * 100))%", 40, 60 + Double(i) * 32)
    }
}
```

`labels` is everything at or above `minimumConfidence`, strongest first, and `top` is the single strongest. The other read surface goes by name, so `confidence(of: "dog")` answers `0…1` for any label in the vocabulary, unfiltered, which means a concept below the floor still reads its true (small) value. That's the knob-shaped form, letting "how much does this look like a plant" drive a color, a speed, or a sound. Spaces work in place of underscores (`"blue sky"` finds `blue_sky`).

Two things worth knowing about the vocabulary. It's hierarchical, so one clear subject lights up its whole lineage, and a blue sky scores `blue_sky`, `sky`, and `outdoor` together. The classifier also scores *all* of it every frame, mostly near zero, so `minimumConfidence` (default `0.1`) is what keeps `labels` down to the meaningful few. `supportedLabels()` lists the full vocabulary when you want to browse for a concept to key on.

The model is neural, so the [availability](#availability) surface applies (`isAvailable` / `unavailableReason`).

<a name="classification"></a>

### Classification

```swift
var label: String { get }       // "blue_sky", the identifier
var confidence: Double { get }  // 0…1
var name: String { get }        // "blue sky", ready to draw
```

One label the classifier saw. `label` is the underscored identifier the vocabulary uses, the one `confidence(of:)` and `supportedLabels()` speak, and `name` opens the underscores up for display.

<a name="saliencytracker"></a>

### SaliencyTracker

```swift
SaliencyTracker(_ source: any FrameSource, mode: Mode = .attention)
var heatMap: Image? { get }
var regions: [DetectedRectangle] { get }
func salience(at: Vector2, in: Rectangle, mirrored: Bool = false) -> Double
static func detect(in: Image, mode: Mode = .attention) async throws -> Saliency?
```

Maps **what draws the eye**, giving a heat map of visual salience over the frame plus the bounding regions it peaks in. Where the segmenters answer "which pixels are the subject," this answers "which parts of the picture matter", for any content. There are two flavors via `mode`. `.attention` (the default) predicts where a person would look, trained on human gaze and drawn to faces and contrast, while `.objectness` highlights regions likely to contain discrete objects, whether or not they draw the eye. The mode is fixed at init, so make one tracker per mode to read both.

```swift
let camera = Camera()
lazy var saliency = SaliencyTracker(camera)

override func draw() {
    guard let rect = drawFrame(camera) else { return }
    if let heat = saliency.heatMap {
        tint(Color(red: 1, green: 0.6, blue: 0.1, alpha: 0.7))
        drawImage(heat, in: rect)                     // attention as a warm glow
        noTint()
    }
    for region in saliency.regions {
        noFill(); stroke(.white)
        drawRect(region.bounds(in: rect))             // the salient spots, boxed
    }
}
```

`heatMap` is a white-alpha image like the segmentation matte, where alpha is the salience, so `tint(_:)` recolors it into a glow, a fog, or an inverted spotlight. It comes back at the model's own coarse resolution (68×68, whatever the source's size or aspect), and drawing it into the frame's rectangle stretches it smoothly onto the picture. Like the segmenters' images, it's converted only once a read has armed it (the first read can come back `nil`, and the next analyzed frame publishes). `regions` are the salient bounding boxes (usually a handful at most) as [`DetectedRectangle`](#rectangledetector)s, upright here, so `bounds(in:)` is the natural read.

The third surface is a query. `salience(at:in:)` answers "how salient is the picture under this canvas point" (`0…1`) straight from the latest result, with no image in between. That's the field-shaped form: a density for stippling or hatching, an attractor for particles, a weight for where to spend detail. Pass the same rectangle you drew the frame into (and `mirrored:` if you drew it flipped), and out-of-range points clamp to the edge. `salienceNormalized(at:)` is the raw normalized-space form.

The model is neural, so the [availability](#availability) surface applies (`isAvailable` / `unavailableReason`).

<a name="saliency"></a>

### Saliency

```swift
struct Saliency {
    var heatMap: Image                 // white, alpha = salience
    var regions: [DetectedRectangle]   // the salient bounding boxes
    func salience(at: Vector2, in: Rectangle, mirrored: Bool = false) -> Double
    func salienceNormalized(at: Vector2) -> Double
}
```

What the still-image `detect(in:mode:)` returns, the same three surfaces the live tracker publishes as one value. `nil` only if the heat map couldn't be converted.

<a name="modeltracker"></a>

### ModelTracker

```swift
ModelTracker(_ source: any FrameSource, modelAt: URL)
ModelTracker(_ source: any FrameSource, model: MLModel)   // a model you configured yourself
ModelTracker(modelAt: URL)                                // bound to no source; still images only
var labels: [Classification] { get }                      // classifier outputs, strongest first
var top: Classification? { get }
func confidence(of: String) -> Double
var objects: [DetectedObject] { get }                     // object-detector outputs
var map: Image? { get }                                   // image-typed output, white-alpha
var outputImage: Image? { get }                           // image-typed output, full color
var classMask: ClassMask? { get }                         // semantic-segmenter output
func value(at: Vector2, in: Rectangle, mirrored: Bool = false) -> Double
var isLoaded: Bool { get }
func detect(in: Image) async throws -> ModelOutput
```

Runs **your own Core ML model** over the frames, the open end of the tracker catalog. Anything converted to Core ML drops in: an `.mlpackage` or `.mlmodel` you converted yourself (most published models convert with `coremltools`), one from [Apple's model gallery](https://developer.apple.com/machine-learning/models/), or an already-compiled `.mlmodelc`. Core ML schedules the work across the CPU, GPU, and Neural Engine on its own, and on Apple silicon a typical vision model runs mostly on the Neural Engine.

A model fills the surfaces matching what it outputs, decoded the same way the built-in trackers decode theirs:

- **Classifier** (label + confidence outputs) → `labels` / `top` / `confidence(of:)`, like [`ImageClassifier`](#imageclassifier) but over your model's own vocabulary.
- **Image-to-image** (a depth estimator, a custom matte, a style-transfer model) → two readings of the same output. `map` is the output as a *value field*, a white-alpha `Image` like the segmentation matte (`tint(_:)` recolors it, and drawing it into the frame's rectangle stretches it onto the picture), plus `value(at:in:)` for the value under any canvas point, the same field-shaped query [`SaliencyTracker`](#saliencytracker) offers (`0…1`, and out-of-range points clamp to the edge). `outputImage` is the output as a *picture*, full color, for a model that paints rather than measures, like a style-transfer model's stylized frame drawn as any image (the `StyleMirror` example). Each surface converts only once something reads it, so a sketch pays for the reading it uses.
- **Object detector** (a detector exported with its non-maximum-suppression head, the form Apple's gallery ships) → `objects`, labeled boxes mapped by `bounds(in:)`.
- **Semantic segmenter** (a model whose output is a plane of class indices, one per pixel, the DeepLabV3 form) → `classMask`, a [`ClassMask`](#classmask): what classes are in frame and how much of it they fill, the class under any canvas point, and each class as a drawable, tintable mask. The model's own vocabulary comes along when it declares one (Apple's gallery models do).

```swift
let camera = Camera()
lazy var depth = ModelTracker(camera, modelAt: URL(fileURLWithPath:
    "Models/DepthAnythingV2SmallF16.mlpackage"))

override func draw() {
    guard let rect = drawFrame(camera) else { return }
    let near = depth.value(at: Vector2(mouseX, mouseY), in: rect)   // 0 far … 1 near
    if let map = depth.map { drawImage(map, in: rect) }             // the depth map, tintable
}
```

Loading happens in the background, off the frame loop, started by the first analyzed frame (or the first `detect(in:)`). `isLoaded` flips when the model is ready, and frames simply pass by until then, so the source's other trackers aren't stalled behind it. The compiled model is cached at a stable path, which is load-bearing, because Core ML *specializes* a model for this Mac's compute device and keys that work to the compiled files and the executable that loads them, so the **first launch of a (re)built sketch takes several seconds** while every later launch of the same build starts in milliseconds. A model file that's missing or won't load surfaces through the [availability](#availability) pair instead of failing silently, so check it and tell the user what to do (the `DepthRelief` example points at its download script).

Model weights are yours to bring, since Ollin bundles none. The examples fetch theirs with `Scripts/fetch-models.sh` (the repo ignores `Models/`), which downloads Apple's official conversion of **Depth Anything V2 (small)** (Apache-2.0, ~50 MB, for the `DepthRelief` example), **YOLOv3-tiny** (YOLO License v2, ~18 MB, for `ObjectDetection`), the **MNIST drawing classifier** (MIT, ~400 KB, for `DigitReader`, which points the model at the sketch's *own* pixels, no camera anywhere), and **DeepLabV3** (Apache-2.0, ~4 MB, for `PaintByClass`, the class-mask surface). The `StyleMirror` example's model isn't fetched at all. You train it yourself from any style image in a couple of minutes with `swift Scripts/train-style-model.swift <image>` (the CreateML framework underneath, since the Create ML app no longer offers its Style Transfer template), so the weights are your own work with no license to check.

<a name="modeloutput"></a>

### ModelOutput

```swift
struct ModelOutput {
    var labels: [Classification]     // classifier outputs, strongest first
    var objects: [DetectedObject]    // detector outputs
    var map: Image?                  // image-typed output, white-alpha
    var outputImage: Image?          // image-typed output, full color
    var classMask: ClassMask?        // semantic-segmenter output
    func value(at: Vector2, in: Rectangle, mirrored: Bool = false) -> Double
    func valueNormalized(at: Vector2) -> Double
}

struct DetectedObject {
    var label: String                // what the model says it is
    var confidence: Double           // 0…1
    func bounds(in: Rectangle, mirrored: Bool = false) -> Rectangle
    func center(in: Rectangle, mirrored: Bool = false) -> Vector2
}
```

What the still-image `detect(in:)` returns, the same surfaces the live tracker publishes as one value. `DetectedObject` is one thing an object-detection model found: its label, confidence, and box, mapped onto the canvas by the usual `in:` helpers.

<a name="classmask"></a>

### ClassMask

```swift
var labels: [String] { get }                 // the model's class vocabulary, by index
var presentClasses: [Int] { get }            // classes in frame, largest first
var presentLabels: [String] { get }          // the same, by name
func coverage(of label: String) -> Double            // fraction of the picture, 0…1
func coverage(ofClass index: Int) -> Double
func classIndex(at: Vector2, in: Rectangle, mirrored: Bool = false) -> Int
func label(at: Vector2, in: Rectangle, mirrored: Bool = false) -> String?
func classIndexNormalized(at: Vector2) -> Int
func mask(of label: String) -> Image?        // one class as a white-alpha mask
func mask(ofClass index: Int) -> Image?
```

What a semantic-segmentation model labeled, pixel by pixel, in three readings of one plane. **What's in frame:** `presentClasses` / `presentLabels` (largest first) and `coverage(of:)`, the share of the picture a class fills. **What's under a point:** `classIndex(at:in:)` / `label(at:in:)`, the class under any canvas point (out-of-range points clamp, and you pass the rectangle you drew the frame into, like every `in:` helper). **One class as pixels:** `mask(of: "person")`, white where the picture is that class and transparent elsewhere, like the segmentation matte, so draw it into the frame's rectangle and it lands on the picture, with `tint(_:)` recoloring it. A mask returns `nil` for a class that isn't in frame, and masks are memoized per result, so drawing the same class every frame costs one conversion per analyzed frame.

`labels` is the vocabulary the model declares about itself (DeepLabV3's 21 PASCAL VOC classes, `"background"` first), and with an undeclared vocabulary the index-based reads still work. The plane is at the model's own resolution (DeepLabV3 answers 513×513 whatever it watched) and covers the full frame. Class indices above 255 aren't representable on this surface.

```swift
lazy var segmenter = ModelTracker(camera, modelAt: URL(fileURLWithPath:
    "Models/DeepLabV3FP16.mlmodel"))

override func draw() {
    guard let rect = drawFrame(camera) else { return }
    if let classes = segmenter.classMask,
       let person = classes.mask(of: "person") {
        tint(.red)                        // the person's pixels, as paint
        drawImage(person, in: rect)
        noTint()
    }
}
```

<a name="coordinate-mapping"></a>

### Coordinate mapping

The recognizers report geometry in **normalized** coordinates, `0…1` across the frame with the origin at the **lower-left** and y pointing up, the convention Apple's Vision framework uses. Ollin's canvas is the opposite: **pixels**, origin at the **top-left**, y pointing down. So a result has to be flipped in y and scaled to wherever the frame was drawn.

```
  normalized (what a tracker returns)      canvas (what you draw in)
  (0,1) ───────────── (1,1)                (0,0) ───────────── (w,0)
    │                   │                     │                   │
    │        · (x,y)    │        ──▶          │                   │
    │                   │                     │        · maps to  │
  (0,0) ───────────── (1,0)                (0,h) ───────────── (w,h)
      y up, lower-left                         y down, top-left
```

The `Face` helpers (`bounds(in:)`, `landmarks(_:in:)`) do this for you. Pass the rectangle you drew the frame into, usually `camera.fittedRect(in: bounds)`, so the overlay sits on the picture. Set `mirrored: true` when you draw the frame flipped left-to-right (the natural "selfie" orientation for a front camera) so the overlay flips with it.

For mapping points from a source the built-in trackers don't cover (say, a custom Core ML model), `VisionSpace` exposes the same math directly:

```swift
VisionSpace.point(_ x: Double, _ y: Double, in: Rectangle, mirrored: Bool = false) -> Vector2
VisionSpace.rectangle(_ normalized: Rectangle, in: Rectangle, mirrored: Bool = false) -> Rectangle
VisionSpace.fittedRect(imageSize: Vector2, in container: Rectangle) -> Rectangle
```

The inverse goes the other way, taking a point or box you drew in canvas space back to normalized coordinates, which is how `ObjectTracker` is seeded from where something sits on the canvas:

```swift
VisionSpace.normalizedPoint(_ canvasPoint: Vector2, in: Rectangle, mirrored: Bool = false) -> Vector2
VisionSpace.normalizedRectangle(_ canvasRect: Rectangle, in: Rectangle, mirrored: Bool = false) -> Rectangle
```

<a name="still-images"></a>

### Still images

Every tracker also runs once on an image you loaded, with no camera needed. It's useful for analyzing photos, and it's how the framework tests detection:

```swift
let image = loadImage("crowd.jpg")!
let found = try await FaceTracker.detect(in: image)
print("\(found.count) faces")
```

The trackers that work *across* frames are the exception (one frame isn't enough), so their camera-free forms take more than one: `ObjectTracker.track(seed, across: frames)` and `TrajectoryTracker.detect(across: frames)` take an ordered sequence, and `FlowTracker.flow(from:to:)` takes the pair of stills to measure between (with `flow(across:)` for a sequence).

Every one of these calls is `async`, which is fine in a `Task`, but `setup()` isn't one, and a deterministic render (a figure, an export) can't wait a few frames for a result to land. `waitFor` runs the call inline and blocks until it's done:

```swift
let shapes = try waitFor(image) { try await ContourDetector.detect(in: $0) }
let field  = try waitFor(before, after) { try await FlowTracker.flow(from: $0, to: $1) }
let arcs   = try waitFor(frames) { try await TrajectoryTracker.detect(across: $0) }
```

Pass the image (or pair, or sequence) as the argument rather than capturing it, because the argument is what carries it into the analysis task safely. Since `waitFor` parks the calling thread, never call it from an async context (just `await` there). A live sketch usually wants neither, so start a `Task`, stash its result in a property, and keep drawing until detection lands.

<a name="availability"></a>

### Availability

Some Vision models, body pose especially, need a compute device (a Neural Engine or a capable GPU) that not every Mac has. On a Mac without one the model can't run, and rather than silently reporting nothing, a tracker tells you, and [`drawStatus`](../Drawing/Text.md#notices) turns the reason into the standard on-canvas notice:

```swift
if let reason = bodies.unavailableReason {
    return drawStatus(reason, style: .warning)
}
```

`isAvailable` is `false` only when the model genuinely can't run here (a transient error doesn't flip it), and `unavailableReason` is a short human-readable explanation. The tracker also logs the reason once to the console. Every tracker exposes the pair through the `VisionAvailability` protocol, so a helper of your own can take `any VisionAvailability` and report for whichever tracker it's handed. Face, hands, and contours run on nearly any Mac, while body pose, segmentation, and the heavier models want Apple silicon.

<a name="permission"></a>

### Permission

Using the camera needs the user's permission, and `start()` requests it the first time it runs. Until the user grants it, `frame` stays `nil` and trackers report nothing. From `swift run` the system prompts on first use, and a packaged app should include a camera-usage description (`NSCameraUsageDescription`).
