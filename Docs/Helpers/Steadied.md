#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Steadied`</sup>

## Found things held steady

A detector answers each frame on its own. On a live feed its boxes shake by a few pixels, and a thing it is unsure of blinks in and out. `@Steadied` holds what a detector finds steady: you assign the findings every frame and read the same things back without the shake.

```swift
import Ollin
import OllinSamplePhotos
import OllinVision

final class Table: Sketch {
    let feed = Camera.orStill(SamplePhoto.breakfast.load())
    lazy var detector = ModelTracker(feed, modelAt: URL(fileURLWithPath: "Models/YOLOv3TinyFP16.mlmodel"))

    @Steadied var objects: [Detection] = []

    override func draw() {
        background(.black)
        guard let view = drawFrame(feed) else { return }
        objects = detector.objects          // what was found, as found
        noFill()
        stroke(.green)
        for object in objects {             // the same things, steady
            drawRect(object.bounds(in: view))
        }
    }
}
```

It lives in the core beside [`@Smoothed`](./Animation.md#smoothed), so it needs no vision import of its own. It works on the [vision detectors'](../Vision/Vision.md) results, on a `Rectangle`, and on a type of yours.

### Contents

- [What it does](#what): matched, smoothed, shown after a moment, kept through a gap
- [Each thing's number and how long it has gone unfound](#things): `$objects.things`
- [The settings](#steadiness): `Steadiness`
- [A type's own settings](#own)
- [A type of your own](#steadiable): `Steadiable`
- [The value under it](#steadier): `Steadier`
- [What it does not do](#limits)

<a name="what"></a>

### What it does

Four things happen to the findings, every frame:

- **Each finding is matched to a thing already there**, by how much their boxes overlap. All the findings are paired at once, so the pairing with the most overlap in total wins. A thing's box is first carried a little way on at the speed it was going, which keeps two things that cross from trading places.
- **Each point of a thing is smoothed**, by the same adaptive filter `@Smoothed` uses: stiff while the thing is still, loose while it moves.
- **A new thing shows only once it has been found for a moment**, a tenth of a second without a break. A finding that is there for a frame and never again is dropped unseen.
- **A thing that goes unfound stays for a moment**, three tenths of a second, held where it was. If it is found again in that time it carries on as the same thing.

It takes more to be admitted than to stay, in two ways. A finding needs `minConfidence` to start a new thing, and a fainter one, down to `minKeptConfidence`, can still continue a thing already there. So a thing whose confidence dips for a frame stays, and a faint guess never appears. The overlap that makes a finding the same thing has the same two levels, `minOverlap` and `minKeptOverlap`.

What comes back is the type you put in. A steadied `Detection` has the newest finding's `label` and `confidence`, and its `bounds(in:)` is the steadied box. `detector.objects` is unchanged: it is still what the detector found.

**Measured on the object detector.** A table of five things was filmed with heavy sensor noise and read thirty times a second for ten seconds. As found, a box appeared 110 times and left as often, and an edge stepped more than 4 pixels on one frame in twenty (on a canvas 1080 across). Steadied, the three things the detector finds on every frame never left, and their edges moved under a pixel on nineteen frames in twenty.

**One frame late.** The sketch steps the wrapper before `draw()`, the way it steps `@Smoothed`. So what you read during a frame is what you assigned the frame before, steadied. Keep the property on the sketch, because that is where the sketch finds it.

**Assign every frame, even when the detector has nothing newer.** A detector usually answers slower than the sketch draws, so the same findings are read two or three frames in a row. That is expected. The delays are measured in seconds, and the smoothing rounds off the steps between two answers.

<a name="things"></a>

### Each thing's number and how long it has gone unfound

`$objects` is the wrapper itself. Its `things` carry what a plain list cannot:

```swift
$objects.things: [Steady<Detection>]

Steady<Thing>
    let id: Int             // 1, 2, 3…, kept for as long as the thing lasts
    let value: Thing        // the thing at its steadied place
    let found: Thing        // the thing as it was last found
    let age: Double         // seconds since it was first found
    let unseenFor: Double   // seconds since it was last found, 0 while it is found

$objects.rawValue: [Detection]      // what was last assigned
$objects.reset()                    // forget everything, numbers start again at 1
```

The number picks a color or a name that stays with the thing. `unseenFor` fades a thing out over the time it is held, rather than cutting it off:

```swift
for thing in $objects.things {
    let fade = 1 - thing.unseenFor / $objects.steadiness.holdTime
    stroke(palette[thing.id % palette.count].withAlpha(fade))
    drawRect(thing.value.bounds(in: view))
}
```

Things come oldest first, so the drawing order holds from frame to frame. Numbers count the things that have appeared. A thing let go and found again later is a new thing with a new number.

<a name="steadiness"></a>

### The settings

Eight numbers, gathered in a `Steadiness`:

```swift
Steadiness(appearDelay: Double = 0.1, holdTime: Double = 0.3,
           minConfidence: Double = 0.5, minKeptConfidence: Double = 0.1,
           minOverlap: Double = 0.2, minKeptOverlap: Double = 0.2,
           minCutoff: Double = 1, beta: Double = 3)
```

| Setting | What it is | Raise it when |
| --- | --- | --- |
| `appearDelay` | Seconds a thing must be found, without a break, before it shows. `0` shows it at once. | Things flash up for a moment that are not there. |
| `holdTime` | Seconds a thing stays after it was last found. | A thing that is still there blinks. Lower it when a thing that left hangs on too long. |
| `minConfidence` | The confidence a finding needs to start a thing. | Wrong things appear. |
| `minKeptConfidence` | The confidence a finding needs to continue a thing. | A thing lingers on findings that are noise. |
| `minOverlap` | The least overlap that makes a finding the same thing, before the thing shows: shared area over covered area, 0 to 1. | Things appear that are only findings piled up in one place. |
| `minKeptOverlap` | The same, once the thing is showing. Never counted higher than `minOverlap`. | A showing thing hops onto a neighbor. Lower it when a fast thing, or one whose box changes shape, is lost. |
| `minCutoff` | The smoothing's cutoff at rest, in Hz. | A slow thing trails. Lower it when a still thing shakes. |
| `beta` | How fast the cutoff opens as a thing moves. | A moving thing trails. Lower it when a moving thing shakes. |

Set them where the property is declared, or while the sketch runs:

```swift
@Steadied(holdTime: 0.5, minConfidence: 0.45) var objects: [Detection] = []

$objects.steadiness.holdTime = 0.2
```

To tune the smoothing, follow the filter's own order. Set `beta` to 0 and hold the thing still, then lower `minCutoff` until the shake is gone. Then move the thing and raise `beta` until it stops trailing.

**The settings mean the same in any units.** A thing's speed is counted in its own sizes a second, so `beta` suits points in pixels as it suits points given as a share of the picture, and a small thing is smoothed as a large one is.

<a name="own"></a>

### A type's own settings

A setting you do not give is the type's own, `Thing.steadiness`. Most types leave the defaults. `DetectedRectangle` does not:

```swift
DetectedRectangle.steadiness    // Steadiness(appearDelay: 0.25, minOverlap: 0.8, minKeptOverlap: 0.5)
```

The rectangle detector reports rectangles in anything with an edge. Around a cup or a plant it gives a different one on every frame, each at full confidence, and those overlap one another enough to pass for one rectangle that hops. A real rectangle overlaps itself almost wholly from frame to frame and is found for seconds on end. A high overlap and a longer wait tell the two apart. Once a rectangle is showing it is followed more loosely, because the detector gives even a real one slightly different corners from frame to frame.

Measured on a desk with a notebook, a trackpad, and a cup, the detector gave about seven rectangles a frame, most of them around the cup. Steadied with these settings, the notebook's rectangles stayed for the whole ten seconds, none that showed was let go, and the ones around the cup never showed. The cost is at the start. A rectangle has to hold nearly still for a quarter of a second to appear, and under heavy noise the fainter ones took a few seconds.

<a name="steadiable"></a>

### A type of your own

Anything `Steadiable` can be steadied. The type says where it is as points, and makes itself again at others:

```swift
protocol Steadiable: Sendable {
    var steadyPoints: [Vector2] { get }             // two opposite corners, or an outline's corners in turn
    var steadyConfidence: Double { get }            // 0 to 1; the default is 1
    func steadied(at points: [Vector2]) -> Self     // the same thing at other points
    static var steadiness: Steadiness { get }       // the default is Steadiness()
}
```

```swift
struct Blob: Steadiable {
    var center: Vector2
    var radius: Double

    var steadyPoints: [Vector2] {
        [center - Vector2(radius, radius), center + Vector2(radius, radius)]
    }

    func steadied(at points: [Vector2]) -> Blob {
        Blob(center: (points[0] + points[1]) * 0.5, radius: (points[1].x - points[0].x) / 2)
    }
}
```

Every finding of a type gives the same number of points, in the same units. Two points are a box. Three or more are an outline, and its first corner may be whichever the finder calls first: the corners are lined up with the thing's own before they are smoothed, and handed back in the newest finding's order.

`Rectangle` conforms, so boxes that arrive from anywhere (a message, a file, a detector of your own) can be steadied as they are. `Detection` and `DetectedRectangle` conform in `OllinVision`.

<a name="steadier"></a>

### The value under it

`@Steadied` is a property wrapper over `Steadier`, a plain value. Use it when the state is not a property of the sketch, or runs on a clock of its own:

```swift
Steadier<Thing>(_ steadiness: Steadiness = Thing.steadiness)
    var steadiness: Steadiness
    mutating func steady(_ found: [Thing], deltaTime: Double) -> [Steady<Thing>]
    var things: [Steady<Thing>]         // what the last call returned
    mutating func reset()
```

```swift
var steadier = Steadier<Rectangle>()

override func draw() {
    let things = steadier.steady(boxes, deltaTime: deltaTime)
    for thing in things { drawRect(thing.value) }
}
```

Called this way there is no frame of delay: the findings handed in are the ones steadied.

<a name="limits"></a>

### What it does not do

- **It does not find anything.** It only holds what a detector found. A thing the detector misses for longer than `holdTime` is gone.
- **It does not know what a thing looks like.** Things are told apart by where they are. One that passes behind another for longer than `holdTime` comes back with a new number.
- **A label is the newest finding's.** When a detector calls a thing a cup on one frame and a bowl on the next, the label changes with it.
- **A held thing stays where it was.** It is not carried on along its path while it is unfound.
- **Two boxes for one thing stay two.** Some detectors give a thing two boxes of different sizes on alternate frames. Each is a finding, and the steadied box moves between them.
- **Only boxes and outlines.** Skeletons, landmarks, and masks are not `Steadiable`. Smooth a joint with [`@Smoothed`](./Animation.md#smoothed).

The matching follows the published trackers that pair detections with tracks by overlap; the credits are in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

### See also

- [Vision](../Vision/Vision.md) has the detectors whose results it steadies.
- [Animation](./Animation.md#smoothed) has `@Smoothed`, the same filter on one value.
- [Matching](../Drawing/Matching.md) is the pairing it uses.
- Guide [Chapter 36](../../Guide/36-Seeing.md) teaches it.
- `Examples/Vision/ObjectDetection` and `Examples/Vision/RectangleScan` draw through it.
