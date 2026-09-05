# Writing an extension

An Ollin extension is an ordinary Swift package that depends on Ollin. There is no plug-in format, no registry, and nothing to register at run time. Someone adds your package and writes `import OllinxYourThing`. After that, your calls sit beside the framework's own calls.

So the mechanics need no work from you, and they never have. This page covers the two things that do need your attention. The first is a shared naming convention, so that extensions are easy to recognize. The second is a list of what you can build on. That way you do not start on something that turns out to be closed.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/ExtensionShape-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/ExtensionShape.jpg" alt="Two cards side by side: on the left a package called ollinx-halftone holding one file that adds drawSpiral to Sketch, on the right a sketch that imports it and calls drawSpiral, with the spiral it draws underneath. An arrow between them is labeled import" width="680">
</picture>

## Starting one

```sh
ollin new Halftone --kind extension
```

This writes a package laid out in the shared way. It holds a worked starter, tests that check something, and a release checklist:

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

The `--seam` flag picks what the starter is built on. The four seams are the four sections below, and `ollin new --list` prints them.

```sh
ollin new Vignette --kind extension --seam filter
```

The generator window offers the same thing. Pick **Extension package** from its kind menu, or open the window with `ollin generate --kind extension`. In the window, the seams take the place of the templates on the left. The stage shows the starter's source instead of a running sketch, and that source is type-checked against the framework. So if a seam stopped compiling, the type check reports the failure before anything is written. See [the window](ProjectGenerator.md#an-extension-package-in-the-window).

## The name

The package and its repository take the prefix `ollinx-`, in lower case with dashes. The module inside takes the prefix `Ollinx`, in camel case. So `Halftone` becomes the package `ollinx-halftone` and the module `OllinxHalftone`.

The prefix follows the `ofx` addons of openFrameworks and the `orx-` set of OPENRNDR. Both chose a prefix for the same reason. There is no registry to search, so a shared prefix is what makes a set of packages findable. `ollin new` writes both spellings for you.

## What you can build on

Each seam in this section is public. Each entry says what the seam promises and where it stops.

### A new call a sketch makes

This is the most common kind of extension, and the plainest. Ollin's own drawing calls are methods on `Sketch`, so an extension adds a new call the same way.

```swift
import Ollin

extension Sketch {
    public func drawSpiral(center: Vector2, radius: Double, turns: Double = 3) {
        // ...
        drawPolyline(points)
    }
}
```

A drawing call reads the current drawing state rather than taking it as arguments. Write yours that way, because then the existing state applies to it with no extra work. `stroke`, `strokeWeight`, the transform stack, clipping, symmetry, and vector export all apply already, because your call emits its geometry through the ordinary calls.

Where you can, build the geometry in one function and draw it in another. A public function that returns `[Vector2]` or a `Shape` can be measured, cut, hatched, and sent to a plotter. It can also be tested without a GPU, and the generated starter's tests rely on that.

The value types are open in the same way. `Vector2`, `Vector3`, `Rectangle`, `Circle`, `Shape`, `Contour`, `Color`, `Ramp`, `Palette`, `Grid`, `Mesh`, and `Heightfield` are all public, so an extension can add to any of them.

### A GPU effect

`Filter`, `Generator`, `Sim`, and `Combine` are structs with no public initializer, so you cannot add a case to any of them. The way in is a shader:

```swift
extension Filter {
    public static func vignette(amount: Double = 0.6) -> Filter {
        .shader(Shader(vignetteSource, params: [Float(amount)]))
    }
}
```

`Filter.shader(_:)` takes one input layer, `Generator.shader(_:)` takes none, and `Combine.shader(_:)` takes two. Wrap the shader in a static function once, as above, and the call site then reads like a built-in: `layer.filtered(.vignette())`.

The shader contract is one function. See [user-supplied shaders](../Shaders/Shaders.md) for that contract, and the [shader library](../Shaders/ShaderLibrary.md) for the helpers that are spliced in for you. A shader compiles once per source text, so a filter value that you rebuild every frame costs nothing after the first frame.

You cannot read a filter back. `Filter.Kind` and a `Shader`'s parameters are internal, so from outside the framework a filter is a value you build and hand over. That limit decides what your tests can check and what they cannot.

### A new source of frames

Everything in Ollin that reads moving pictures reads them through a protocol. So a source you write works with everything already written against that protocol.

| Protocol | What it is for | What it asks for |
|---|---|---|
| `FrameSource` | Frames that anything can analyze. The vision trackers attach to one. | `var frameTap: FrameTap?` |
| `VideoFeed` | Frames that a sketch draws with `drawFrame`. | `frame`, `frameSize`, `waitingMessage` |
| `AudioTapSource` | Blocks of audio samples. The audio analyzer and the listeners attach to one. | `var audioTap: AudioTap?` |

`FrameSource` is one property, and that property is the whole contract. Hold the tap and call it with each new frame:

```swift
@MainActor
public final class WallSource: FrameSource {
    public var frameTap: FrameTap?

    public func publish(_ frame: CGImage) {
        frameTap?(frame)
    }
}
```

Conform to more than one protocol where that makes sense. The video player conforms to all three, so one object can be drawn, analyzed, and listened to at once. The camera has no sound to offer, so it conforms to the first two.

Two rules matter here. First, frames arrive on whatever thread produced them, which is why the tap is `@Sendable`. Hand the frame across, and do not touch main-thread state inside the tap. Second, there is one tap per source, so setting it replaces the previous consumer rather than adding to it.

### Something that runs every frame

`SketchExtension` is the lifecycle seam. Register one in `setup()`, and the runner then calls its hooks around every frame.

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

Every hook is optional, so implement only the ones you want:

| Hook | When | What it is for |
|---|---|---|
| `setup` | Once, after the sketch's own `setup()` | Preparing state |
| `beforeDraw` | Inside the frame, before `draw()` | Setting something up for each frame |
| `afterDraw` | Inside the frame, before the render | Drawing over the sketch: guides, a border, a watermark |
| `afterFrame` | After the render, with `FrameInfo` | Reading rather than drawing: a readout, a log |
| `frameRendered` | After the render, with the pixels | A recorder, a snapshot, sharing the frame |

The pixel hooks cost a tone-map pass and a copy, so they fire only when the extension asks for them. Return `true` from `wantsRenderedFrame` to receive a `CGImage`, or from `wantsRenderedTexture` to receive a Metal texture with no round trip through the CPU. Both are read once every frame, so a recorder can arm and disarm itself. The frame arrives once the GPU has finished it, which is about one refresh after `afterFrame`. It is the frame the window shows, at the canvas size, and frames arrive in frame order. An extension that wants a single frame keeps the first one that arrives. If it asks for a second frame before the first one arrives, it discards that second frame.

Extensions belong to one sketch instance. Every live reload starts a fresh sketch with no extensions, which is why an extension registers itself in `setup()` and nowhere else.

### A type the inspector can drive

`@Param` turns a property into a parameter in the live inspector. Conform your own type to `ParamValue`, and a property of that type gets a parameter too. Your type maps onto a control that already exists.

For an enum, `ParamOption` is the short way. Conform to it and to `CaseIterable`, give each case a label, and the inspector shows a menu.

```swift
public enum Weave: String, CaseIterable, ParamOption {
    case plain, twill, satin
    public var optionLabel: String { rawValue.capitalized }
}
```

`ParamChoices` is the sibling protocol for a named catalog rather than a fixed set of cases. Both protocols need `Equatable`, because the inspector finds the current selection by comparing values.

### A type that animates

Two small protocols open the motion helpers to your own types.

`Tweenable` asks for one static `lerp`, and in return gives you `Timeline` keyframe sequencing. `Smoothable` asks for `+`, `-`, `*` by a `Double`, and a `smoothingSpeed`. In return it gives you `@Smoothed`, `@Sprung`, and the one-euro filter.

### A library of your own

The largest kind of extension is a package that adds whole types rather than extending existing ones. The framework's own satellites are this kind: `OllinAudio`, `OllinVision`, `OllinPhysics`, and the rest are packages that depend on the core and add to it.

The satellites have no special access, so an extension can do the same. They do follow one rule worth knowing, because satellites cannot depend on each other, so anything two of them share lives in the core. That rule is about the framework's own layout, and it is not a limit on yours.

## What is not a seam

These are not seams, so do not start on one of them:

- **`Drawer` is internal.** The renderer's recorder is not public API. Extend `Sketch`, and reach the GPU through a `Shader`.
- **The effect catalogs are closed.** `Filter`, `Generator`, `Sim`, and `Combine` take no new cases. The shader seam is the way in, and it reaches the same render graph.
- **The Metal shader library is fixed.** An extension cannot add a segment to Ollin's own shader source. A `Shader` of your own compiles separately, and the whole helper library is spliced into it.
- **There is no run-time discovery.** Nothing scans for extensions. A sketch that does not import your package does not have your calls. That is by design.

## What the promise is

Ollin is before 1.0, and its API still changes. Today a rename ships with no compatibility shim, so an extension can break on a framework update. State in your README which version you built against.

From 1.0 on, that changes. Every public rename or removal will ship an `@available(*, deprecated, renamed:)` shim that forwards to the new API, so Xcode offers a one-click fix. The seams on this page are the surface that promise covers.

## Publishing

The generated README carries this list as a checklist. The first item is the one that stops people in practice:

- **Point `Package.swift` at the framework's repository**, not at a path on your machine. `ollin new` writes a local path, because a local path builds straight away while you work. Nobody else has that folder.
- **Add a `LICENSE`.** Your extension is your own work under your own license. Ollin bundles none of your code, so the framework's license does not reach you.
- **Name the repository `ollinx-yourthing`**, so it is recognizable and turns up in a search.
- **Say which Ollin version it was built against**, and tag a version of your own, so that a dependent package can ask for one.

## See also

- [Project generator](./ProjectGenerator.md) - the rest of what `ollin new` makes
- [User-supplied shaders](../Shaders/Shaders.md) - the shader contract the filter seam uses
- [Sketch](../Core/Sketch.md) - the lifecycle an extension hooks into
- [Parameters](../Helpers/Parameters.md) - what `@Param` already drives
- [Animation](../Helpers/Animation.md) - `Timeline`, `@Smoothed`, and `@Sprung`
