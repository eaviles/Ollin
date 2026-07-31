#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 21</sup>

---

# 21. Seeing

<img src="Images/21-Seeing/MotionBrush.jpg" alt="A dark canvas holding a wreath of thousands of small green and magenta strokes, dense and bright where motion was recent, fading where it was long ago" width="560">

A camera pointed at the world is the richest input a sketch can have, because whoever stands in front of it brings their face, their hands, their whole moving body to the piece. This chapter is about reading that. The Mac already knows how to find faces, hands, bodies, edges, text, and motion in a picture, on the machine, with no cloud in the loop, and Ollin wraps that perception as values you read in `draw()`, the same way you read the mouse. The painting above was made by motion alone, and by the end you'll have built it.

## The webcam is an image

Everything starts with `OllinVision`'s `Camera`, a frame source you start once and then draw like any image.

```swift
import Ollin
import OllinVision

final class Mirror: Sketch {
    let camera = Camera()

    override func setup() { try? camera.start() }

    override func draw() {
        background(.black)
        drawFrame(camera)
    }
}
```

Run it and you're on the canvas. `drawFrame(camera)` draws the latest frame letterboxed into the canvas (fitted without stretching, like a photo in a mat), shows a standard "Waiting for camera…" notice until the first frame arrives, and returns the rectangle the picture landed in. Keep that rectangle, because it matters more than it looks. Using the camera needs permission, like the microphone did, and macOS asks once, the first time `start()` runs. `Camera(.continuity)` uses a nearby iPhone as the camera, and `.external` a USB webcam.

## Trackers: attach, then read

Seeing more than pixels is the job of the **trackers**. Each one attaches to a frame source and runs one kind of perception over its frames, publishing typed results your sketch reads every frame:

<img src="Images/21-Seeing/TrackerFlow.jpg" alt="A diagram of three boxes: Camera producing frames, FaceTracker analyzing in the background, and typed results read in draw. Below, two panels show a normalized lower-left-origin point mapping into the drawn frame's rectangle" width="680">

```swift
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
            drawPolyline(face.landmarks(.faceContour, in: rect))
        }
    }
}
```

That's the whole model, and every tracker follows it. The analysis runs on a background thread, throttled to what the machine keeps up with (analysis frames are skipped under load, never queued, and the *displayed* frame is never dropped), so your `draw()` stays smooth and simply reads the most recent result.

The second half of the diagram is the part that bites everyone once. Trackers report geometry in **normalized** coordinates: `0...1` across the frame, origin at the *lower left*, y pointing *up*. The canvas is pixels from the *top left*, y pointing *down*, and the frame usually landed letterboxed somewhere inside it. So every result must be flipped and scaled into the rectangle you drew the frame in. You never do that math yourself, because every result type carries `in:` helpers (`bounds(in: rect)`, `point(_:in:)`, `landmarks(_:in:)`) that take the rectangle `drawFrame` returned and answer in canvas terms. Pass `mirrored: true` to them when you draw the feed flipped like a bathroom mirror, which is usually what feels right for a piece you stand in front of.

> **Swift note.** `lazy var faces = FaceTracker(camera)` builds the tracker the first time it's touched, which is what lets its declaration mention `camera`, another property of the same class. Plain `let` properties initialize too early for that.

## Hands, faces, bodies

Three trackers carry most interactive pieces, and they all speak in named parts:

<img src="Images/21-Seeing/Landmarks.jpg" alt="Three panels: a hand skeleton of 21 dots wired finger by finger, a face of 76 dots grouped into contour, brows, eyes, nose and lips regions, and a body skeleton of 19 dots" width="680">

**`HandTracker`** finds up to two hands (ask for more with `maximumHandCount:`), each a `Hand` of 21 joints, the wrist plus four joints per finger, base to tip. `hand.point(.indexTip, in: rect)` is a fingertip as a canvas point, `finger(.index, in: rect)` one finger as a polyline, `bones(in: rect)` the whole skeleton as line segments. Gestures fall out of arithmetic on a few joints: thumb tip near index tip is a pinch, five spread tips are an open hand, the index tip alone is a cursor that needs no mouse.

**`FaceTracker`** finds every face with its head pose (`roll`/`yaw`/`pitch`) and 76 landmark points grouped into named regions: `.faceContour`, the brows, the eyes, `.nose`, the lips, the pupils. Each region comes back ready to `drawPolyline`, which is why the five-minute face overlay is a creative-coding classic.

**`BodyTracker`** finds every person as a 19-joint pose skeleton, head to ankles. Joints it can't see are simply absent (often the legs, at a desk), so what you get is what the camera saw. Its sibling `BodyTracker3D` places one person's 17 joints in *meters*, real 3D positions you can view from angles no camera was at, and it drops straight into Chapter 17's world.

Two practical notes are worth keeping. These are neural models, and the heavier ones (body pose, segmentation) want Apple silicon. Every tracker exposes `isAvailable` and `unavailableReason`, and `drawStatus(reason, style: .warning)` turns the reason into the standard on-canvas notice instead of a silent nothing. And every tracker also runs one-shot on a still picture with no camera at all. `try await FaceTracker.detect(in: image)` analyzes a loaded `Image`, which is how you analyze photos, and how this chapter's figures were made honest.

## Edges and motion

Two more trackers see *qualities* of the picture rather than things in it, and both connect straight back to ideas you already have.

**`ContourDetector`** traces the boundaries between dark and light into closed vector contours, and hands them back as Chapter 13's `Shape`s, holes and all:

<img src="Images/21-Seeing/Contours.jpg" alt="Two panels: a black ink study of merged blobs beside a ring, and the same forms traced as orange vector outlines with the ring's hole preserved" width="680">

The picture on the left was built pixel by pixel by the committed figure, standing in for a camera frame, and the shapes on the right are what `ContourDetector.detect(in:)` traced out of it. Once a camera frame is `Shape`s, everything from Chapter 13 applies: boolean it, offset it, hatch it, warp it, export it as SVG for a plotter. A webcam pointed at high-contrast subjects becomes a live vectorizer.

**`FlowTracker`** measures **optical flow**, meaning how every part of the picture moved since the previous frame. Chapter 12 taught fields as "an answer at every point", and this is that exact idea, except the answers are measured from the world instead of computed from noise:

<img src="Images/21-Seeing/FlowArrows.jpg" alt="Two panels: a dark frame holding two pale speckled hands, and the same frame with orange arrows on one hand showing its measured motion. The other hand, mid-turnaround, gets no arrows" width="680">

```swift
lazy var flow = FlowTracker(camera)
// in draw():
if let field = flow.field {
    let push = field.vector(at: particle.position, in: rect)   // canvas-space motion
}
```

`field` is `nil` until the second analyzed frame (flow needs a pair), then you can ask it anywhere: `vector(at:in:)` for the motion under a point, `samples(in:every:)` for a grid of arrows, `averageFlow(in:)` for the whole picture's drift. Look closely at the figure and you'll see that only one hand grew arrows. The other was turning around at that instant, nearly still, and flow reports *motion*, not presence, so a hand at rest is invisible to it.

Motion is also only measurable where the picture has texture, and a featureless area (a blank wall, a solid backdrop) doesn't politely read as zero. It reads as noise, because there is nothing to match from one frame to the next. If your scene is mostly flat, give it some texture before trusting the field there. Treat the magnitudes as a signal to scale by a gain of your own rather than a calibrated speed. The measured field has its own name, `MotionField`, so you won't confuse it with Chapter 12's generative `FlowField`: one is a rule you invent, the other is motion the camera actually saw.

## The wider catalog

The rest of the trackers follow the exact same attach-and-read shape, so knowing they exist is most of knowing how to use them. `RectangleDetector` finds rectangular things (paper, screens, cards) with their four corners in perspective. `BarcodeScanner` reads QR codes, a nice way to hand a running installation some input. `TextRecognizer` is on-device OCR over the feed. `ObjectTracker` follows a patch you point at, and `TrajectoryTracker` waits for things that fly and reports their parabolic arcs, predicted ahead. `PersonSegmenter` and `SubjectSegmenter` lift people (or whatever stands out) from the frame as a soft matte and a cutout `Image`, ready to composite over anything your sketch draws. `ImageClassifier` names what's in view from about 1,300 everyday labels, and `SaliencyTracker` maps where an eye would look. And when the built-ins run out, `ModelTracker` runs *your own* Core ML model over the frames with the same read surfaces, which opens the whole published-model world (depth estimators, object detectors, style transfer, semantic segmentation). The [vision reference](../Docs/Vision/Vision.md) covers each in detail, and there's a worked example for every one of them in [`Examples/Vision/`](../Examples/Vision).

## Footage as material

Everything above also works on recorded video, because `VideoPlayer` is a frame source exactly like the camera:

```swift
import OllinVideo

let player = try VideoPlayer(path: "/path/to/clip.mp4")
lazy var contours = ContourDetector(player)     // traces the clip as it plays

override func setup() { player.loops = true; player.play() }
override func draw() { drawFrame(player) }
```

Frames arrive as GPU textures (drawing them costs almost nothing), `drawFrame` letterboxes them the same way, trackers analyze the footage as it plays, and `snapshot()` hands you a CPU still for the one-shot `detect(in:)` calls. Chapter 20's `Soundtrack(of: player)` completes the loop: one clip can drive a piece with its pixels *and* its music. The `Video/VideoPlayback` example ships with a short clip of the *Voladores de Papantla* to play with, and `Vision/VideoTrace` runs a contour tracker over it live. One export note is worth carrying forward. Headless exports drive the player deterministically (frame `k` of the export always shows the clip at `k/fps`), but a *tracker* attached to it analyzes nothing during an export, since analysis rides the live clock.

## The past as material

Everything so far reads the frame in front of you. Keeping the *previous* frames around opens a different technique, and it's one of the oldest tricks in camera art.

A `SlitScan` is a rolling history of frames. You push the newest one every time you draw, it keeps the last few dozen, and then you ask it for a picture in which each pixel comes from a different moment.

```swift
let history = Ollin.SlitScan(frames: 48)

override func draw() {
    history.push(camera.snapshot())
    if let warped = history.image(delay: { uv in uv.x }) {
        drawImage(warped, in: canvasRectangle)
    }
}
```

The closure is the whole idea. It receives a pixel's position as fractions across the picture and returns how far back to read there, where 0 is the newest frame and 1 is the oldest one still held. Returning `uv.x` means the left edge shows a moment ago and the right edge shows now, so time runs left to right across the image.

<img src="Images/21-Seeing/SlitScanDelay.jpg" alt="Two panels: a synthetic clip's newest frame showing horizontal stripes with one bright horizontal band, and the slit-scanned version where that band has become a clean diagonal and the stripes have sheared" width="680">

The figure uses a made-up clip rather than a webcam so it can be reproduced, and it shows what the delay actually does. A bright band that was sweeping down the frame becomes a diagonal line, because each column caught it at a different height. Any delay map works, so `1 - uv.y` puts now at the bottom, and `dist(uv.x, uv.y, 0.5, 0.5) / 0.71` makes time ripple outward from the center. There's also a form that takes an `Image` as the delay map, which means you can paint where time runs slow.

Two practical notes. The history costs width times height times four bytes per frame, so push modest sizes rather than full-resolution stills. And the first push fixes the size, after which differently sized frames are skipped with a one-time note in the console.

> **Swift note.** The type is written `Ollin.SlitScan` in the listing above because the example sketch that ships with this technique is itself named `SlitScan`, and a class shadows a type of the same name. Qualifying with the module name is how you say "I mean the framework's one", the same move SwiftUI code makes for `Image`.

## Putting it together: motion paints

The finished piece is the interactive mirror promised at the top, where you stand in front of the camera and your motion is the brush. Where the picture moved, strokes appear, colored by the direction of the movement and sized by its speed. Stillness paints nothing, and old gestures sink slowly into the dark. Make `MySketches/MotionBrush.swift` (the committed figure [`MotionBrush.swift`](Figures/21-Seeing/MotionBrush.swift) carries `StagePerformer`, the pretend dancer that stands in for a webcam so the figure renders without you, while the listing below is the sketch as you'd run it live):

```swift
import Ollin
import OllinVision

final class MotionBrush: Sketch {
    let camera = Camera()
    lazy var flow = FlowTracker(camera)

    override func setup() {
        try? camera.start()
        seed(21)                    // the brush dabs land the same way every run
        noClear()
        background(Color(hex: 0x0A0A14))
    }

    override func draw() {
        // A faint veil each frame, so old strokes sink slowly into the dark.
        noStroke()
        fill(Color(hex: 0x0A0A14, alpha: 0.007))
        drawRect(0, 0, width, height)

        guard let field = flow.field else { return }

        // Fling brushes at random spots; paint only where the picture moved.
        for _ in 0 ..< 900 {
            let p = Vector2(random(0, width), random(0, height))
            let v = field.vector(at: p, in: bounds, mirrored: true)
            let strength = v.length
            guard strength > 4 else { continue }
            let hue = v.angle / .tau + 0.5              // direction picks the color
            stroke(Color(hue: hue, saturation: 0.75, brightness: 1)
                .withAlpha(min(0.5, strength * 0.02)))
            strokeWeight((1.2 + min(5, strength * 0.07)) * scale)
            drawLine(p, p + v.limited(to: 110 * scale) * 3)
        }
    }
}
```

<img src="Images/21-Seeing/MotionBrush.jpg" alt="The finished motion painting: a swirling wreath of green and magenta strokes tracing where the pretend dancer's hands moved, dense where recent, faded where old" width="560">

The committed figure swaps the camera block for the pretend dancer (`StagePerformer.step()` stands where `flow.field` stands, feeding the same kind of field from a synthesized dance, with nobody to mirror), and the painting code is identical. Chapter 14's accumulation (`noClear` plus the faint veil) is what turns instants of motion into a painting with a memory.

Then make it yours:

- Change what motion means by using `field.averageFlow(in: bounds)` to steer one big brush instead of thousands of small ones, and the piece becomes a single line that follows the room.
- Paint with yourself instead of your motion. Swap the flow for `PersonSegmenter` and stamp the `matte`, tinted, wherever you stand, so motion leaves silhouettes.
- Give the brush a hand by driving it with `HandTracker`'s `.indexTip` instead of flow, and you're drawing in the air.
- Trace the room instead, with a `ContourDetector` over the same camera drawn as strokes that jitter with Chapter 5's noise, which makes the mirror a live etching.

## Where this comes from

Camera-as-instrument art is older than the personal computer: Myron Krueger's *Videoplace* (mid-1970s) let people play with their own silhouettes, David Rokeby's *Very Nervous System* (1986) turned body motion into sound, and Camille Utterback and Romy Achituv's *Text Rain* (1999) let falling letters rest on your outline. That lineage runs straight through today's interactive mirrors, and Golan Levin's writing on computer vision for artists is a fine map of it. Optical flow goes back to Berthold Horn and Brian Schunck, and Bruce Lucas and Takeo Kanade, in the same year (1981). Slit scanning started as a photographic technique with a physical slit and moving film, gave *2001: A Space Odyssey* its stargate sequence, and became a per-pixel delay map once video was digital; Golan Levin's informal catalogue of slit-scan works is the map of that history. The perception itself here is Apple's Vision framework and Core ML, running on the machine, and Ollin's contribution is the typed, canvas-mapped reading surface. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Vision](../Docs/Vision/Vision.md): every tracker in detail, coordinate mapping, still images, availability.
- [Video](../Docs/Video/Video.md): loading and playing footage, analysis, the soundtrack, deterministic export.
- [Slit scan](../Docs/Video/SlitScan.md): the frame history, both delay forms, memory cost, and the delay maps worth trying.
- Worked examples: [`Examples/Vision/FaceTracking`](../Examples/Vision/FaceTracking/Sketch.swift), [`Examples/Vision/HandTracking`](../Examples/Vision/HandTracking/Sketch.swift), [`Examples/Vision/BodyPose`](../Examples/Vision/BodyPose/Sketch.swift), [`Examples/Vision/ContourTrace`](../Examples/Vision/ContourTrace/Sketch.swift), [`Examples/Vision/OpticalFlow`](../Examples/Vision/OpticalFlow/Sketch.swift), [`Examples/Vision/PersonSegmentation`](../Examples/Vision/PersonSegmentation/Sketch.swift), [`Examples/Vision/EyeCatcher`](../Examples/Vision/EyeCatcher/Sketch.swift), [`Examples/Vision/DigitReader`](../Examples/Vision/DigitReader/Sketch.swift) (a model over the sketch's own pixels, no camera anywhere), and the rest of [`Examples/Vision/`](../Examples/Vision); [`Examples/Video/VideoPlayback`](../Examples/Video/VideoPlayback/Sketch.swift) and [`Examples/Vision/VideoTrace`](../Examples/Vision/VideoTrace/Sketch.swift) for footage; [`Examples/Images/SlitScan`](../Examples/Images/SlitScan/Sketch.swift) for the frame history.

---

[Contents](README.md#contents) · Previous: [Chapter 20, Sound and control](20-SoundAndControl.md) · Next: [Chapter 22, Sharing and performing](22-SharingAndPerforming.md)
