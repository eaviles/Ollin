# Writing an extension

An Ollin extension is an ordinary Swift package that depends on Ollin. There is no plug-in format, no registry, and nothing to register at run time. Someone adds your package, writes `import OllinxYourThing`, and what you added is simply there beside the framework's own calls.

That means the mechanics are free, and they have been all along. What this page adds is the part that is not. One is a shared name, so extensions are recognisable. The other is an honest list of what you can build on, so you do not start on something that turns out to be closed.

<img src="../../Guide/Images/31-SharingAndPerforming/ExtensionShape.jpg" alt="Two cards side by side: on the left a package called ollinx-halftone holding one file that adds drawSpiral to Sketch, on the right a sketch that imports it and calls drawSpiral, with the spiral it draws underneath. An arrow between them is labeled import" width="680">

## Starting one

```sh
ollin new Halftone --kind extension
```

You get a package laid out the shared way, with a worked starter, tests that check something, and a release checklist:

```
ollinx-halftone/
  Package.swift
  README.md
  Sources/OllinxHalftone/Halftone.swift
  Tests/OllinxHalftoneTests/HalftoneTests.swift
```

Build it and run its tests the usual way:

```sh
cd ollinx-halftone
swift test
```

Pick what the starter is built on with `--seam`. The four seams are the four sections below, and `ollin new --list` prints them.

```sh
ollin new Vignette --kind extension --seam filter
```

## The name

The package and its repository take `ollinx-` in lower case with dashes. The module inside takes `Ollinx` in camel case. `Halftone` becomes the package `ollinx-halftone` and the module `OllinxHalftone`.

The prefix follows openFrameworks' `ofx` addons and OPENRNDR's `orx-` set. Both chose one for the same reason: with no registry to search, a shared prefix is what makes a set of packages findable. `ollin new` writes both spellings for you.

## What you can build on

Each of these is a real, public seam. Each says what it promises and where it stops.

### A new call a sketch makes

The commonest kind, and the plainest. Ollin's own drawing calls are methods on `Sketch`, so an extension adds one the same way.

```swift
import Ollin

extension Sketch {
    public func drawSpiral(center: Vector2, radius: Double, turns: Double = 3) {
        // ...
        drawPolyline(points)
    }
}
```

A drawing call reads the current state rather than taking it in arguments. Write it that way and you get a great deal for nothing. `stroke`, `strokeWeight`, the transform stack, clipping, symmetry, and vector export all apply already, because you emit through the ordinary calls.

Emit the geometry separately from the drawing where you can. A public function that returns `[Vector2]` or a `Shape` can be measured, cut, hatched, and sent to a plotter. It can also be tested without a GPU, which the generated starter relies on.

The value types are open in the same way. `Vector2`, `Vector3`, `Rectangle`, `Circle`, `Shape`, `Contour`, `Color`, `Ramp`, `Palette`, `Grid`, `Mesh`, and `Heightfield` are all public, and an extension can add to any of them.

### A GPU effect

`Filter`, `Generator`, `Sim`, and `Combine` are structs with no public initialiser. You cannot add a case to any of them. The way in is a shader:

```swift
extension Filter {
    public static func vignette(amount: Double = 0.6) -> Filter {
        .shader(Shader(vignetteSource, params: [Float(amount)]))
    }
}
```

`Filter.shader(_:)` takes one input layer, `Generator.shader(_:)` takes none, and `Combine.shader(_:)` takes two. Wrapping it once, as above, is what makes the call site read like a built-in: `layer.filtered(.vignette())`.

The shader contract is one function. See [user-supplied shaders](../Shaders/Shaders.md) for it, and the [shader library](../Shaders/ShaderLibrary.md) for the helpers spliced in for you. A shader compiles once per source, so a filter value rebuilt every frame costs nothing after the first.

What you cannot do is read a filter back. `Filter.Kind` and a `Shader`'s parameters are internal, so from outside the framework a filter is a value you build and hand over. That is what your tests can and cannot check.

### A new source of frames

Anything that reads moving pictures in Ollin reads it through a protocol, so a source you write works with everything already written against one.

| Protocol | What it is for | What it asks for |
|---|---|---|
| `FrameSource` | Frames anything can analyze. The vision trackers attach to one. | `var frameTap: FrameTap?` |
| `VideoFeed` | Frames a sketch draws with `drawFrame`. | `frame`, `frameSize`, `waitingMessage` |
| `AudioTapSource` | Blocks of samples. The audio analyzer and the listeners attach to one. | `var audioTap: AudioTap?` |

`FrameSource` is the whole contract in one property. Hold the tap and call it with each new frame:

```swift
@MainActor
public final class WallSource: FrameSource {
    public var frameTap: FrameTap?

    public func publish(_ frame: CGImage) {
        frameTap?(frame)
    }
}
```

Conform to more than one where it makes sense. The video player conforms to all three, so one object can be drawn, analyzed, and listened to at once. The camera conforms to the first two, having no sound to offer.

Two rules matter here. Frames arrive on whatever thread produced them, which is why the tap is `@Sendable`; hand the frame across rather than touching main-thread state inside it. And there is one tap per source, so setting it replaces the previous consumer rather than adding to it.

### Something that runs every frame

`SketchExtension` is the lifecycle seam. Register one in `setup()` and the runner calls its hooks around every frame.

```swift
@MainActor
public final class GuidesOverlay: SketchExtension {
    public func afterDraw(_ sketch: Sketch) {
        sketch.withState { /* draw over the sketch */ }
    }
}
```

```swift
override func setup() {
    extend(GuidesOverlay())
}
```

Every hook is optional, so write only the moments you want:

| Hook | When | What it is for |
|---|---|---|
| `setup` | Once, after the sketch's own | Preparing state |
| `beforeDraw` | Inside the frame, before `draw()` | Setting something up per frame |
| `afterDraw` | Inside the frame, before the render | Drawing over the sketch: guides, a border, a watermark |
| `afterFrame` | After the render, with `FrameInfo` | Reading rather than drawing: a readout, a log |
| `frameRendered` | After the render, with the pixels | A recorder, a snapshot, sharing the frame |

The pixel hooks cost a GPU readback, so they only fire when the extension asks. Return `true` from `wantsRenderedFrame` for a `CGImage`, or from `wantsRenderedTexture` for a Metal texture with no round trip through the CPU. Both are read every frame, so a recorder can arm and disarm itself.

Extensions are per instance. Every live reload starts a fresh sketch with none, which is why one registers itself in `setup()` rather than anywhere else.

### A type the inspector can drive

`@Param` turns a property into a knob in the live inspector. Conform your own type to `ParamValue` and it gets one too, mapped onto a control that already exists.

For an enum, `ParamOption` is the short way: conform to it and `CaseIterable`, give each case a label, and the inspector shows a menu.

```swift
public enum Weave: String, CaseIterable, ParamOption {
    case plain, twill, satin
    public var optionLabel: String { rawValue.capitalized }
}
```

`ParamChoices` is the sibling for a named catalog rather than a fixed set of cases. Both need `Equatable`, because the inspector finds the current selection by comparing.

### A type that animates

Two small protocols open the motion helpers to your own types.

`Tweenable` asks for one static `lerp`, and gives you `Timeline` keyframe sequencing. `Smoothable` asks for `+`, `-`, `*` by a `Double`, and a `smoothingSpeed`, and gives you `@Smoothed`, `@Sprung`, and the one-euro filter.

### A library of your own

The largest shape is a package that adds whole types rather than extending existing ones. That is what the framework's own satellites are: `OllinAudio`, `OllinVision`, `OllinPhysics`, and the rest are packages that depend on the core and add to it.

Nothing about them is privileged, so an extension can do the same. One rule of theirs is worth knowing: satellites cannot depend on each other, so anything two of them share lives in the core. That is about the framework's own layout, not a limit on yours.

## What is not a seam

Said plainly, so you do not start on one of these:

- **`Drawer` is internal.** The renderer's recorder is not public API. Extend `Sketch`, and reach the GPU through a `Shader`.
- **The effect catalogs are closed.** `Filter`, `Generator`, `Sim`, and `Combine` take no new cases. The shader seam is the way in, and it reaches the same render graph.
- **The Metal shader library is fixed.** An extension cannot add a segment to Ollin's own shader source. A `Shader` of your own compiles on its own and gets the whole helper library spliced in.
- **There is no run-time discovery.** Nothing scans for extensions. A sketch that does not import your package does not have your calls, which is the point.

## What the promise is

Ollin is before 1.0 and its API still moves. A rename ships with no compatibility shim today, so an extension can break on a framework update. Say in your README which version you built against.

From 1.0 that changes. Every public rename or removal ships an `@available(*, deprecated, renamed:)` shim that forwards to the new API, so Xcode offers a one-click fix. The seams on this page are the surface that promise covers.

## Publishing

The generated README carries this as a checklist. The first item is the one that actually stops people:

- **Point `Package.swift` at the framework's repository**, not at a path on your machine. `ollin new` writes a local path, because that is what builds straight away while you work. Nobody else has that folder.
- **Add a `LICENSE`.** Your extension is your own work under your own license. Ollin bundles none of it, so nothing about the framework's license reaches you.
- **Name the repository `ollinx-yourthing`**, so it is recognisable and turns up in a search.
- **Say which Ollin version it was built against**, and tag a version of your own so a dependant can ask for one.

## See also

- [Project generator](./ProjectGenerator.md) - the rest of what `ollin new` makes
- [User-supplied shaders](../Shaders/Shaders.md) - the shader contract the filter seam uses
- [Sketch](../Core/Sketch.md) - the lifecycle an extension hangs off
- [Parameters](../Helpers/Parameters.md) - what `@Param` already drives
- [Animation](../Helpers/Animation.md) - `Timeline`, `@Smoothed`, and `@Sprung`
