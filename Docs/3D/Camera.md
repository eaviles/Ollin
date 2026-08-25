#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Camera control`</sup>

---

## Camera control

A [3D](./3D.md) sketch sets a [`camera`](./3D.md#the-camera) each frame. Often what you want is one of two things that are tedious to hand-write. One is to let the viewer *move the camera by hand*. The other is to play a *ready-made cinematic move* instead of keyframing a path.

Both are here, both opt-in, and both reuse the orbit pose ([`Camera3D.orbiting`](./3D.md#the-camera)). That suits the kind of scene Ollin draws: an object on a turntable, looked at from around it. It is not a camera flown through a space. The object might be a transforming solid, a particle system, or a point cloud.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/21-3DGently/Orbit-dark.jpg">
  <img src="../../Guide/Images/21-3DGently/Orbit.jpg" alt="A diagram of the orbiting camera: a small camera body on a gray ring around a dark knot, with a dashed sight line labeled radius, a ground arc labeled azimuth, and a climbing arc labeled elevation" width="680">
</picture>

The one most sketches reach for is [`cameraShowcase(_:)`](#showcase), which **fuses the two**. It orbits on its own *and* lets the viewer grab and explore, easing back to the opening shot when left alone.

Each is a single call you make in `draw()`, like `camera(...)`. A sketch that calls neither keeps its own camera untouched. Both write the same pose, so handing off between hand-framing and a move continues smoothly from wherever you left it.

### Contents

- [Showcase camera](#showcase) - `cameraShowcase(_:)`, the usual default
- [Interactive control](#control) - `cameraControl()`
- [The input surface it reads](#input) - `scrollDeltaY`, `modifiers`, `mouseWheel()`, `rightMouseIsPressed`
- [Cinematic moves](#moves) - `cameraMove(_:)`
- [The move catalog](#catalog) - `CameraMove`
- [Opening on an authored camera](#from-authored) - the `from:` forms, seeding the rig from any `Camera3D`
- [Composing: frame, then drift](#compose)
- [Scene inspection views](#views) - `cameraView(_:)` / `resetCamera()`, the Camera menu
- [Orientation axis & ground grid](#chrome) - `cameraAxis()` / `groundGrid()`, the live-only viewport aids
- [Notes](#notes)

<a id="showcase"></a>
### Showcase camera (the usual default)

`cameraShowcase(_:)` is the one most 3D sketches want. The camera **orbits on its own**, but the viewer can **take it over** at any time. Drag to orbit, scroll to dolly, right-drag or shift / option-drag to pan. After a stretch of no input it **eases back to the opening shot** and resumes orbiting. So a sketch is alive on its own on a wall or in a gallery, yet always explorable.

```swift
override func draw() {
    background(Color(white: 0.05))
    cameraShowcase(radius: 8, elevation: 0.4)   // a gentle auto-orbit you can grab
    drawTorusKnot(p: 2, q: 3, radius: 1.4, tube: 0.4)
}
```

It is the interactive ([`cameraControl()`](#control)) and cinematic ([`cameraMove(_:)`](#moves)) halves fused. The move plays until you touch the camera, and your input drives while you do. Then the idle return glides back over `returnDuration` seconds and the move carries on. It returns to the *opening* framing, its `target` / `radius` / `elevation`, not wherever you left it. The gestures are the same as [interactive control](#control) below.

The motion defaults to `.autoOrbit()`, a slow product-shot turntable. Pass any [`CameraMove`](#catalog) to keep a specific motion:

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

`cameraControl()` hands the camera to the viewer. Drag to orbit the object, scroll to dolly in and out, and right-drag or shift / option-drag to pan the target. The motion is damped, so it settles smoothly and a flick keeps a little spin before coming to rest. It is opt-in like [`lights()`](./3D.md#lights): call it each `draw()` and it sets the camera for the frame.

```swift
override func draw() {
    background(Color(white: 0.05))
    cameraControl(target: .zero, radius: 9, elevation: 0.35)
    drawBox(size: 2)
}
```

The `target` / `radius` / `azimuth` / `elevation` / `fieldOfView` arguments frame the *opening* shot, applied on the first call only. After that the viewer owns the pose. Passing the same framing every frame does not fight the interaction or snap the camera back.

| Gesture | Action |
| --- | --- |
| Drag (left) | Orbit (azimuth and elevation around the target) |
| Scroll | Dolly (change the radius) |
| Right-drag, or shift / option-drag | Pan (move the target across the view) |

<a id="input"></a>
### The input surface it reads

`cameraControl()` is built on a small input surface you can also read directly, the same way you read `mouseX` / `mouseIsPressed`:

- `scrollDeltaY` - how far the scroll wheel or a trackpad two-finger scroll moved this frame, summed since the last frame, `0` when nothing scrolled. It is a per-frame value, so read it in `draw()`. Positive is a scroll up.
- `modifiers` - the modifier keys held, a `ModifierKeys` option set (`.shift`, `.option`, `.command`, `.control`): `if modifiers.contains(.shift) { … }`.
- `rightMouseIsPressed` - whether the secondary mouse button is held, the companion to `mouseIsPressed`.
- `mouseWheel()` - an override hook called once per scroll event, for a one-shot discrete step. For continuous response poll `scrollDeltaY` instead.

So a sketch can drive its own zoom or modified gesture without the camera rig at all.

<a id="moves"></a>
### Cinematic moves

`cameraMove(_:)` plays a named motion over the camera instead of keyframing it. Each move is a way to look at an object on a turntable. It modulates the orbit pose, meaning azimuth, elevation, and radius, around the target.

```swift
override func draw() {
    cameraMove(.turntable(period: 12), radius: 6)   // a slow product-shot spin
    drawTorusKnot(p: 2, q: 3, radius: 1.4, tube: 0.4)
}
```

Like `cameraControl()`, the `target` / `radius` / `elevation` / `fieldOfView` arguments frame the shot on the first call. After that the move owns the pose. Angles are in radians, matching the rest of the camera API.

<a id="catalog"></a>
### The move catalog

`CameraMove` is a value type; build one with a static factory. The finite moves ease over a duration and then hold. The cyclic ones run continuously.

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

<a id="from-authored"></a>
### Opening on an authored camera

All three calls take a `from:` form that seeds the opening shot from any `Camera3D` instead of the framing arguments. It is the natural fit for a [loaded scene's](./Scenes.md#cameras) authored camera. Open on the exact shot composed in the design tool, then hand the viewer the orbit, or let a move drift from it.

```swift
cameraControl(from: stage.camera ?? .orbiting(radius: 6))     // the authored view, explorable
cameraShowcase(from: stage.camera ?? .orbiting(radius: 6))    // ...or auto-orbiting from it
cameraMove(.handheld(amount: 0.05), from: stage.camera!)      // ...or breathing on it
```

The camera decomposes into the rig's orbit pose. Its `target` becomes the pivot, the eye's offset becomes the radius and angles, and its field of view carries over. An orthographic camera opens the rig flat, and the axis widget's Ortho toggle switches back. Its frame height maps to the matching field of view at the target distance, so the shot shows the authored extent. `near`/`far` default to the camera's own clip range. Like the framing arguments, it seeds on the *first* call only, and the idle return / `.reset` glide back to it. Two things don't carry. The rig orbits y-up, so an authored camera roll is dropped, and a camera looking straight up or down clamps just off the pole.

<a id="compose"></a>
### Composing: frame, then drift

Because both halves write the same pose, a move *composes over the pose it starts from*. Switching from one move to another departs from where the last one left the camera. A move started after `cameraControl()` departs from the pose the viewer framed by hand. So "frame it, then let it drift" is one call after another:

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

<a id="views"></a>
### Scene inspection views

While building a 3D scene it helps to look at it from a known angle, the way a modeling tool's numpad snaps the viewport. `cameraView(_:)` does that. It glides the camera to a canonical orientation, then hands the pose back to whatever motion was running.

```swift
cameraView(.front)                  // look straight down +Z
cameraView(.isometric)              // the three-quarter, all three axes at once
resetCamera()                       // back to the opening framing
cameraView(.top, animated: false)   // cut instantly instead of gliding
```

The views:

- `.reset` returns to the sketch's opening framing: its center, distance, and angle, the shot the first `cameraShowcase` / `cameraControl` / `cameraMove` call set. `resetCamera()` is sugar for it.
- `.front` / `.back` / `.left` / `.right` / `.top` / `.bottom` look straight down each axis, so each flattens the scene to two axes. They keep the current center and distance and only swing the orbit angle.
- `.isometric` is the three-quarter, 45° around and tilted so the three axes foreshorten equally. It is the one angle that shows all three axes at once. Pair it with the axis widget's Ortho toggle for a textbook isometric look.

By default the camera glides over `duration` seconds, reusing the rig's eased return; pass `animated: false` to cut. A snap works with the rig, so after gliding it resumes that motion from the snapped pose. That covers `cameraShowcase`, `cameraControl`, and `cameraMove`. A sketch that drives the camera by hand with `camera(...)` overrides the pose every frame, so a snap has no effect there. A 2D sketch ignores it.

**From the menu.** The host apps carry a **Camera** menu with the same snaps and keyboard shortcuts. So you can orbit by hand and snap back without the sketch wiring anything. Reset View is ⌘0, Front ⌘1, Back ⌘2, Right ⌘3, Left ⌘4, Top ⌘5, Bottom ⌘6, and Isometric ⌘7. The menu drives whatever 3D sketch is running, in a standalone example run, the examples gallery, or OllinLive.

<a id="chrome"></a>
### Orientation axis & ground grid

Two aids for keeping your bearings while you build a 3D scene. Both are *live-only host chrome*: they draw in the preview window but never in an export. Both are no-ops in a 2D sketch, which has no camera to orient to.

```swift
cameraAxis()    // the interactive orientation widget, bottom-center
groundGrid()    // a faint reference floor at y = 0
```

`cameraAxis()` shows a small XYZ indicator that turns with the camera, so you can read which way the scene faces as it orbits. It is interactive. Click an axis to snap the view down it, the same snaps as `cameraView`. Its buttons reset the view, frame the isometric angle, and toggle between perspective and orthographic projection, the Ortho look that pairs with `.isometric`.

`groundGrid()` lays a faint grid on the y = 0 plane the scene sits on, for reading scale and placement. It subdivides with the camera and fades toward the horizon, with the X and Z world axes picked out in red and blue. Finer lines fade in as you dolly closer, coarser ones as you pull back.

Both read live each frame, so set them once in `setup()` for a fixed choice, or flip them in `draw()`, say on a key. The host apps also expose them as **Camera** menu toggles, **Show Axis** and **Show Ground Grid**. So you can turn them on for any running sketch without editing it.

<a id="notes"></a>
### Notes

- **Call it in `draw()`, every frame.** `cameraShowcase(_:)`, `cameraControl()`, and `cameraMove(_:)` all set the camera for the current frame, the same lifetime as `camera(.orbiting(...))`. The camera is per-frame state, reset each frame, so calling once in `setup()` does nothing.
- **The 3D examples use `cameraShowcase` by default.** Almost every sketch under `Examples/3D/` orbits through it, so each one is both a self-running shot and something you can grab and explore. It is the recommended default for a new orbiting sketch.
- **Reading where the camera ended up.** When an interactive rig owns the pose, `activeCamera` returns the `Camera3D` set this frame, its `eye`, `target`, and the rest, or `nil` in a 2D frame. Reach for it when a sketch places geometry relative to the camera.
- **Object-centric by design.** The pose is always an orbit around a centered `target`, so there is no "walk the camera through a scene". A move or drag changes the angle, height, and distance you view the object from. To recenter on a different object, pan interactively or set a new `target` on the first framing call.
- **The shared timeline.** The finite moves are built on `Timeline`, the small sequencing primitive documented under [Animation](../Helpers/Animation.md#timeline). It is public, so a sketch can sequence any value the same way.
