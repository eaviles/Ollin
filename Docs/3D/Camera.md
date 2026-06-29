#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Camera control`</sup>

---

## Camera control

A [3D](./3D.md) sketch sets a [`camera`](./3D.md#the-camera) each frame. Often what you want is one of two things that are tedious to hand-write: let the viewer *move the camera by hand*, or play a *ready-made cinematic move* instead of keyframing a path. Both are here, both opt-in, and both reuse the orbit pose ([`Camera3D.orbiting`](./3D.md#the-camera)) so they suit the kind of scene Ollin draws: an object on a turntable (a transforming solid, a particle system, a point cloud), looked at from around it, rather than a camera flown through a space. The one most sketches reach for is [`cameraShowcase(_:)`](#showcase), which **fuses the two**: a camera that orbits on its own *and* that the viewer can grab and explore, easing back to the opening shot when left alone.

Each is a single call you make in `draw()`, like `camera(...)`. A sketch that calls neither keeps its own camera untouched. Both write the same pose, so framing a shot by hand and then handing off to a move (or back) continues smoothly from wherever you left it.

### Contents

- [Showcase camera](#showcase) - `cameraShowcase(_:)`, the usual default
- [Interactive control](#control) - `cameraControl()`
- [The input surface it reads](#input) - `scrollDeltaY`, `modifiers`, `mouseWheel()`, `rightMouseIsPressed`
- [Cinematic moves](#moves) - `cameraMove(_:)`
- [The move catalog](#catalog) - `CameraMove`
- [Composing: frame, then drift](#compose)
- [Notes](#notes)

<a id="showcase"></a>
### Showcase camera (the usual default)

`cameraShowcase(_:)` is the one most 3D sketches want: the camera **orbits on its own**, but the viewer can **take it over** at any time (drag to orbit, scroll to dolly, right-drag or shift / option-drag to pan), and after a stretch of no input it **eases back to the opening shot** and resumes orbiting. So a sketch is alive on its own on a wall or in a gallery, yet always explorable.

```swift
override func draw() {
    background(Color(white: 0.05))
    cameraShowcase(radius: 8, elevation: 0.4)   // a gentle auto-orbit you can grab
    drawTorusKnot(p: 2, q: 3, radius: 1.4, tube: 0.4)
}
```

It is the interactive ([`cameraControl()`](#control)) and cinematic ([`cameraMove(_:)`](#moves)) halves fused: the move plays until you touch the camera, your input drives while you do, and the idle return glides back over `returnDuration` seconds to the *opening* framing (its `target` / `radius` / `elevation`), not wherever you left it, then carries on. The gestures are the same as [interactive control](#control) below.

The motion defaults to `.autoOrbit()`, a slow product-shot turntable; pass any [`CameraMove`](#catalog) to keep a specific motion:

```swift
cameraShowcase(.sway(amplitude: 0.4, period: 30), radius: 8, elevation: 0.3)
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `move` | `.autoOrbit()` | the automatic motion (any `CameraMove`) |
| `idleReturn` | `10` | seconds of no input before the return begins |
| `returnDuration` | `4` | seconds the eased glide back to the opening shot takes |

The `target` / `radius` / `elevation` / `fieldOfView` arguments frame the opening shot on the first call, and are where the idle return glides back to.

<a id="control"></a>
### Interactive control

`cameraControl()` hands the camera to the viewer: drag to orbit the object, scroll to dolly in and out, and right-drag (or shift / option-drag) to pan the target. The motion is damped, so it settles smoothly and a flick keeps a little spin before coming to rest. It is opt-in like [`lights()`](./3D.md#lights): call it each `draw()` and it sets the camera for the frame.

```swift
override func draw() {
    background(Color(white: 0.05))
    cameraControl(target: .zero, radius: 9, elevation: 0.35)
    drawBox(size: 2)
}
```

The `target` / `radius` / `azimuth` / `elevation` / `fieldOfView` arguments frame the *opening* shot, applied on the first call only. After that the viewer owns the pose, so passing the same framing every frame does not fight the interaction or snap the camera back.

| Gesture | Action |
| --- | --- |
| Drag (left) | Orbit (azimuth and elevation around the target) |
| Scroll | Dolly (change the radius) |
| Right-drag, or shift / option-drag | Pan (move the target across the view) |

<a id="input"></a>
### The input surface it reads

`cameraControl()` is built on a small input surface you can also read directly, the same way you read `mouseX` / `mouseIsPressed`:

- `scrollDeltaY` - how far the scroll wheel (or a trackpad two-finger scroll) moved this frame, summed since the last frame, `0` when nothing scrolled. A per-frame value: read it in `draw()`. Positive is a scroll up.
- `modifiers` - the modifier keys held, a `ModifierKeys` option set (`.shift`, `.option`, `.command`, `.control`): `if modifiers.contains(.shift) { … }`.
- `rightMouseIsPressed` - whether the secondary mouse button is held, the companion to `mouseIsPressed`.
- `mouseWheel()` - an override hook called once per scroll event, for one-shot response (a discrete step). For continuous response poll `scrollDeltaY` instead.

So a sketch can drive its own zoom or modified gesture without the camera rig at all.

<a id="moves"></a>
### Cinematic moves

`cameraMove(_:)` plays a named motion over the camera instead of keyframing it. Each move is a way to look at an object on a turntable: it modulates the orbit pose (azimuth, elevation, radius) around the target.

```swift
override func draw() {
    cameraMove(.turntable(period: 12), radius: 6)   // a slow product-shot spin
    drawTorusKnot(p: 2, q: 3, radius: 1.4, tube: 0.4)
}
```

Like `cameraControl()`, the `target` / `radius` / `elevation` / `fieldOfView` arguments frame the shot on the first call; after that the move owns the pose. Angles are in radians, matching the rest of the camera API.

<a id="catalog"></a>
### The move catalog

`CameraMove` is a value type; build one with a static factory. The finite moves ease over a duration and then hold; the cyclic ones run continuously.

| Move | Kind | The shot |
| --- | --- | --- |
| `.turntable(period:)` | cyclic | a continuous spin, one turn every `period` seconds |
| `.sway(amplitude:period:)` | cyclic | a gentle azimuth rock, so the object is seen from a range of angles without a full spin |
| `.pushIn(by:in:ease:)` | finite | dolly closer (scale the radius by `by`, below 1) |
| `.pullOut(by:in:ease:)` | finite | dolly away (scale the radius by `by`, above 1) |
| `.tilt(to:in:ease:)` | finite | sweep the elevation (rise to look down, drop to look up) |
| `.orbitAndRise(period:rise:in:)` | hybrid | the spiral beauty pass: turn continuously while the elevation rises |
| `.reveal(in:ease:)` | finite | an opener: start close and low, pull back and rise to the framed shot |
| `.handheld(amount:speed:)` | cyclic | subtle operator breathing on all three, from a smooth noise field, so a held shot reads as alive |

```swift
cameraMove(.orbitAndRise(period: 12, rise: 0.5, in: 6), radius: 7)
```

<a id="compose"></a>
### Composing: frame, then drift

Because both halves write the same pose, a move *composes over the pose it starts from*. Switching from one move to another departs from where the last one left the camera, and a move started after `cameraControl()` departs from the pose the viewer framed by hand. So "frame it, then let it drift" is one call after another:

```swift
override func draw() {
    if locked {
        cameraMove(.handheld(amount: 0.05))   // gentle life, from the framed pose
    } else {
        cameraControl()                        // frame it by hand
    }
    drawScene()
}
```

<a id="notes"></a>
### Notes

- **Call it in `draw()`, every frame.** `cameraShowcase(_:)`, `cameraControl()`, and `cameraMove(_:)` all set the camera for the current frame (the camera is per-frame state, reset each frame), the same lifetime as `camera(.orbiting(...))`. Calling once in `setup()` does nothing.
- **The 3D examples use `cameraShowcase` by default.** Almost every sketch under `Examples/3D/` orbits through it, so each one is both a self-running shot and something you can grab and explore: the recommended default for a new orbiting sketch.
- **Reading where the camera ended up.** When an interactive rig owns the pose, `activeCamera` returns the `Camera3D` set this frame (its `eye`, `target`, …), or `nil` in a 2D frame. Handy when a sketch places geometry relative to the camera.
- **Object-centric by design.** The pose is always an orbit around a centered `target`, so there is no "walk the camera through a scene"; a move or drag changes the angle, height, and distance you view the object from. To recenter on a different object, pan (interactively) or set a new `target` on the first framing call.
- **The shared timeline.** The finite moves are built on `Timeline`, the small sequencing primitive documented under [Animation](../Helpers/Animation.md#timeline). It is public, so a sketch can sequence any value the same way.
