#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Camera control`</sup>

---

## Camera control

A [3D](./3D.md) sketch sets a [`camera`](./3D.md#the-camera) each frame. Two things a sketch often wants from that camera are tedious to write yourself. One is to let the viewer *move the camera by hand*. The other is to play a *ready-made cinematic move* instead of keyframing a path.

This page covers both. Each is opt-in, and each reuses the orbit pose ([`Camera3D.orbiting`](./3D.md#the-camera)). An orbit suits the kind of scene Ollin draws, which is an object on a turntable that you look at from around it. It is not a camera flown through a space. The object might be a transforming solid, a particle system, or a point cloud.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/21-3DGently/Orbit-dark.jpg">
  <img src="../../Guide/Images/21-3DGently/Orbit.jpg" alt="A diagram of the orbiting camera: a small camera body on a gray ring around a dark knot, with a dashed sight line labeled radius, a ground arc labeled azimuth, and a climbing arc labeled elevation" width="680">
</picture>

Most sketches use [`cameraShowcase(_:)`](#showcase), which **combines the two**. It orbits on its own, and it also lets the viewer grab the camera and explore. When the viewer stops, it eases back to the opening shot.

Each is a single call you make in `draw()`, like `camera(...)`. A sketch that calls neither keeps its own camera untouched. Both write the same pose, so handing off between hand-framing and a move continues smoothly from wherever you left it.

### Contents

- [Showcase camera](#showcase) - `cameraShowcase(_:)`, the usual default
- [Interactive control](#control) - `cameraControl()`
- [The input surface it reads](#input) - `scrollDeltaY`, `modifiers`, `mouseScrolled()`, `rightMouseIsPressed`
- [Cinematic moves](#moves) - `cameraMove(_:)`
- [The move catalog](#catalog) - `CameraMove`
- [Opening on an authored camera](#from-authored) - the `from:` forms, which seed the rig from any `Camera3D`
- [Composing: frame, then drift](#compose)
- [Scene inspection views](#views) - `cameraView(_:)` / `resetCamera()`, the Camera menu
- [Orientation axis & ground grid](#chrome) - `cameraAxis()` / `groundGrid()`, the live-only viewport aids
- [Notes](#notes)

<a id="showcase"></a>
### Showcase camera (the usual default)

`cameraShowcase(_:)` is the call most 3D sketches want. The camera **orbits on its own**, and the viewer can **take it over** at any time. Drag to orbit, scroll to dolly, and right-drag or shift / option-drag to pan. After a period of no input, the camera **eases back to the opening shot** and resumes orbiting. So a sketch keeps moving unattended on a wall or in a gallery, and a viewer can still explore it.

```swift
override func draw() {
    background(Color(white: 0.05))
    cameraShowcase(radius: 8, elevation: 0.4)   // a gentle auto-orbit you can grab
    drawTorusKnot(p: 2, q: 3, radius: 1.4, tube: 0.4)
}
```

It combines the interactive half ([`cameraControl()`](#control)) and the cinematic half ([`cameraMove(_:)`](#moves)). The move plays until you touch the camera. Your input then drives the camera for as long as you keep moving it. After that, the idle return glides back over `returnDuration` seconds, and the move carries on. The return goes to the *opening* framing (its `target` / `radius` / `elevation`), not to wherever you left the camera. The gestures are the same as in [interactive control](#control) below.

The motion defaults to `.autoOrbit()`, which is a slow product-shot turntable. To use a specific motion, pass any [`CameraMove`](#catalog):

```swift
cameraShowcase(.sway(amplitude: 0.4, period: 30), radius: 8, elevation: 0.3)
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `move` | `.autoOrbit()` | the automatic motion (any `CameraMove`) |
| `idleReturn` | `10` | seconds of no input before the return begins |
| `returnDuration` | `4` | how many seconds the eased glide back to the opening shot takes |

The `target` / `radius` / `elevation` / `fieldOfView` arguments frame the opening shot on the first call. The idle return glides back to that shot.

<a id="control"></a>
### Interactive control

`cameraControl()` hands the camera to the viewer. Drag to orbit the object, scroll to dolly in and out, and right-drag or shift / option-drag to pan the target. The motion is damped, so it settles smoothly, and a flick keeps a little spin before it comes to rest. It is opt-in, like [`lights()`](./3D.md#lights). Call it in each `draw()`, and it sets the camera for that frame.

```swift
override func draw() {
    background(Color(white: 0.05))
    cameraControl(target: .zero, radius: 9, elevation: 0.35)
    drawBox(size: 2)
}
```

The `target` / `radius` / `azimuth` / `elevation` / `fieldOfView` arguments frame the *opening* shot. They apply on the first call only, and after that the viewer owns the pose. So passing the same framing every frame does not interfere with the interaction or snap the camera back.

| Gesture | Action |
| --- | --- |
| Drag (left) | Orbit (azimuth and elevation around the target) |
| Scroll | Dolly (change the radius) |
| Right-drag, or shift / option-drag | Pan (move the target across the view) |

<a id="input"></a>
### The input surface it reads

`cameraControl()` is built on a small set of input values. You can also read them directly, the same way you read `mouseX` / `mouseIsPressed`:

- `scrollDeltaY` - how far the scroll wheel or a two-finger trackpad scroll moved this frame. The value is summed since the last frame, and it is `0` when nothing scrolled. It is a per-frame value, so read it in `draw()`. A positive value is a scroll up.
- `modifiers` - the modifier keys currently held, as a `ModifierKeys` option set (`.shift`, `.option`, `.command`, `.control`). Test one with `if modifiers.contains(.shift) { … }`.
- `rightMouseIsPressed` - whether the secondary mouse button is held. It is the companion to `mouseIsPressed`.
- `mouseScrolled()` - an override hook that is called once per scroll event. Use it for a one-shot discrete step. For a continuous response, poll `scrollDeltaY` instead.

So a sketch can drive its own zoom or its own modified gesture without using the camera rig at all.

<a id="moves"></a>
### Cinematic moves

`cameraMove(_:)` plays a named motion on the camera, so you do not keyframe it. Each move is a way to look at an object on a turntable. A move changes the orbit pose around the target, which means the azimuth, the elevation, and the radius.

```swift
override func draw() {
    cameraMove(.turntable(period: 12), radius: 6)   // a slow product-shot spin
    drawTorusKnot(p: 2, q: 3, radius: 1.4, tube: 0.4)
}
```

As with `cameraControl()`, the `target` / `radius` / `elevation` / `fieldOfView` arguments frame the shot on the first call. After that the move owns the pose. Angles are in radians, which matches the rest of the camera API.

<a id="catalog"></a>
### The move catalog

`CameraMove` is a value type, and you build one with a static factory. The finite moves ease over a duration and then hold. The cyclic moves run continuously. One move is a hybrid, running continuously along one axis while easing along another.

| Move | Kind | The shot |
| --- | --- | --- |
| `.turntable(period:)` | cyclic | a continuous spin, one turn every `period` seconds |
| `.sway(amplitude:period:)` | cyclic | a gentle azimuth rock, so the object is seen from a range of angles without a full spin |
| `.pushIn(by:in:ease:)` | finite | dolly closer (scale the radius by `by`, below 1) |
| `.pullOut(by:in:ease:)` | finite | dolly away (scale the radius by `by`, above 1) |
| `.tilt(to:in:ease:)` | finite | sweep the elevation (rise to look down, drop to look up) |
| `.orbitAndRise(period:rise:in:)` | hybrid | the spiral beauty pass: the camera turns continuously while the elevation rises |
| `.reveal(in:ease:)` | finite | an opener: start close and low, then pull back and rise to the framed shot |
| `.handheld(amount:speed:)` | cyclic | a subtle operator breathing on all three, driven by a smooth noise field, so a held shot looks alive |

```swift
cameraMove(.orbitAndRise(period: 12, rise: 0.5, in: 6), radius: 7)
```

<a id="from-authored"></a>
### Opening on an authored camera

All three calls take a `from:` form. It seeds the opening shot from any `Camera3D` instead of from the framing arguments. It fits a [loaded scene's](./Scenes.md#cameras) authored camera well, so you open on the exact shot composed in the design tool. From there you hand the viewer the orbit, or you let a move drift from it.

```swift
cameraControl(from: stage.camera ?? .orbiting(radius: 6))     // the authored view, explorable
cameraShowcase(from: stage.camera ?? .orbiting(radius: 6))    // ...or auto-orbiting from it
cameraMove(.handheld(amount: 0.05), from: stage.camera!)      // ...or breathing on it
```

The rig decomposes the camera into its orbit pose. The camera's `target` becomes the pivot, the eye's offset becomes the radius and the angles, and its field of view carries over. An orthographic camera opens the rig flat, and the axis widget's Ortho toggle switches it back to perspective. The orthographic frame height maps to the matching field of view at the target distance, so the shot shows the authored extent. `near`/`far` default to the camera's own clip range. Like the framing arguments, `from:` seeds the rig on the *first* call only, and the idle return and `.reset` glide back to it. Two things do not carry over. The rig orbits y-up, so an authored camera roll is dropped. A camera that looks straight up or down clamps to just off the pole.

<a id="compose"></a>
### Composing: frame, then drift

Because both halves write the same pose, a move *composes over the pose it starts from*. Switch from one move to another and the new move picks up where the last one left the camera. A move you begin after `cameraControl()` picks up the pose the viewer framed by hand. So to frame the shot and then let it drift, you make one call after the other:

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

While you build a 3D scene, it helps to look at it from a known angle, the way a modeling tool's numpad snaps the viewport. `cameraView(_:)` does the same thing in a sketch. It glides the camera to a canonical orientation, and then it hands the pose back to whatever motion was running.

```swift
cameraView(.front)                  // look straight down +Z
cameraView(.isometric)              // the three-quarter, all three axes at once
resetCamera()                       // back to the opening framing
cameraView(.top, animated: false)   // cut instantly instead of gliding
```

The views:

- `.reset` returns to the sketch's opening framing (its center, distance, and angle). That is the shot the first `cameraShowcase` / `cameraControl` / `cameraMove` call set. `resetCamera()` is a shorthand for it.
- `.front` / `.back` / `.left` / `.right` / `.top` / `.bottom` look straight down each axis. Each one flattens the scene to two axes. They keep the current center and distance, and they only swing the orbit angle.
- `.isometric` is the three-quarter view: 45° around, and tilted so that the three axes foreshorten equally. It is the one angle that shows all three axes at once. Pair it with the axis widget's Ortho toggle for a textbook isometric look.

By default the camera glides over `duration` seconds, reusing the rig's eased return. Pass `animated: false` to cut instead. A snap works together with the rig, so after the glide the rig resumes its motion from the snapped pose. That covers `cameraShowcase`, `cameraControl`, and `cameraMove`. A sketch that drives the camera by hand with `camera(...)` overrides the pose every frame, so a snap has no effect there. A 2D sketch ignores a snap.

**From the menu.** The host apps have a **Camera** menu with the same snaps and keyboard shortcuts. So you can orbit by hand and snap back without the sketch wiring anything. Reset View is ⌘0, Front ⌘1, Back ⌘2, Right ⌘3, Left ⌘4, Top ⌘5, Bottom ⌘6, and Isometric ⌘7. The menu drives whatever 3D sketch is running, whether in a standalone example run, in the examples gallery, or in OllinLive.

<a id="chrome"></a>
### Orientation axis & ground grid

Two aids help you stay oriented while you build a 3D scene. Both are *live-only host chrome*, which means they draw in the preview window but never in an export. Both do nothing in a 2D sketch, because a 2D sketch has no camera to orient to.

```swift
cameraAxis()    // the interactive orientation widget, bottom-center
groundGrid()    // a faint reference floor at y = 0
```

`cameraAxis()` shows a small XYZ indicator that turns with the camera, so you can read which way the scene faces as it orbits. The widget is interactive. Click an axis to snap the view down it, which gives the same snaps as `cameraView`. Its buttons reset the view, frame the isometric angle, and toggle between perspective and orthographic projection. That last button is the Ortho toggle, and its orthographic look pairs with `.isometric`.

`groundGrid()` draws a faint grid on the y = 0 plane the scene sits on, so you can read scale and placement. The grid subdivides with the camera and fades toward the horizon, and the X and Z world axes are marked in red and blue. Finer lines fade in as you dolly closer, and coarser lines fade in as you pull back.

Both are read live each frame. So you can set them once in `setup()` for a fixed choice, or you can flip them in `draw()`, for example on a key press. The host apps also expose them as **Camera** menu toggles, **Show Axis** and **Show Ground Grid**. So you can turn them on for any running sketch without editing it.

<a id="notes"></a>
### Notes

- **Call it in `draw()`, every frame.** `cameraShowcase(_:)`, `cameraControl()`, and `cameraMove(_:)` all set the camera for the current frame only. That is the same lifetime as `camera(.orbiting(...))`. The camera is per-frame state that is reset each frame, so a single call in `setup()` does nothing.
- **The 3D examples use `cameraShowcase` by default.** Almost every sketch under `Examples/3D/` orbits through it. So each one is a self-running shot, and you can also grab it and explore. It is the recommended default for a new orbiting sketch.
- **Reading where the camera ended up.** When an interactive rig owns the pose, `activeCamera` returns the `Camera3D` that was set this frame. That gives you its `eye`, `target`, and the rest. In a 2D frame it returns `nil`. Use it when a sketch places geometry relative to the camera.
- **Object-centric by design.** The pose is always an orbit around a centered `target`. So there is no way to walk the camera through a scene. A move or a drag changes the angle, the height, and the distance you view the object from. To recenter on a different object, pan interactively, or set a new `target` on the first framing call.
- **The shared timeline.** The finite moves are built on `Timeline`, the small sequencing type documented under [Animation](../Helpers/Animation.md#timeline). `Timeline` is public, so a sketch can sequence any value the same way.
