#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `QuickReference`</sup>

---

## Ollin quick reference

This page is the whole shape of Ollin in one read. It covers how a sketch runs, what the calls are called, their units, the command line, and the mistakes that fail with no error. Each part links to the page with the rest. It is written for anybody writing a sketch, and for an assistant helping somebody write one. Read it once, then look details up with the commands under [Looking something up](#lookup).

New to Swift? The [Swift quick reference](./Swift.md) does the same for the language. Coming from p5.js or Processing, [Appendix C](../Guide/C-ComingFromP5.md) of the Guide translates the API you know, and [Appendix E](../Guide/E-ComingFromOpenFrameworksAndOPENRNDR.md) does it for openFrameworks and OPENRNDR.

### Contents

- [A sketch](#sketch)
- [The clock and randomness](#clock)
- [The calls, by area](#calls)
- [Names you might reach for](#names)
- [Units and conventions](#units)
- [Parameters](#params)
- [The command line](#cli)
- [Looking something up](#lookup)
- [Things that fail quietly](#quiet)
- [Checking your work](#checking)

<a name="sketch"></a>

### A sketch

A sketch is a class that builds on `Sketch`. `setup()` runs once, and `draw()` runs every frame at the display's rate, so anything that reads `time` moves.

```swift
import Ollin

@main
final class Rings: Sketch {
    override var canvasSize: CanvasSize { .vertical1080 }
    override var loopDuration: Double? { 6 }

    @Param(4...40) var count = 12
    @Param var ink: Color = .black

    override func setup() {
        seed(7)
    }

    override func draw() {
        background(.white)
        noFill()
        stroke(ink)
        strokeWeight(2 * scale)
        let t = loopProgress(over: 6)
        for i in 0..<count {
            let wobble = sin((t + Double(i) / Double(count)) * .tau) * 12
            drawCircle(width / 2, height / 2, (40 + Double(i) * 30 + wobble) * scale)
        }
    }
}
```

- **Configuration is overridden, not called.** `canvasSize`, `windowMode`, `loopDuration`, `title`, and `colorOutput` are properties a sketch overrides.
- **The hooks** are `setup()`, `draw()`, `mousePressed()`, `mouseReleased()`, `mouseScrolled()`, `keyPressed()`, `keyReleased()`, `filesDropped()`, and `reloaded()` (after a hot swap). Mouse movement has no hook; read `mouseX`, `mouseY`, and `mouseIsPressed` in `draw()`.
- **Draw in `draw()`, not in `setup()`.** The frame's geometry is emptied before the first `draw()`, and per-frame state (the camera, lights, shadows) resets each frame.
- **`draw*` calls emit shapes**; `fill`, `stroke`, and `background` set state; `translate`, `rotate`, and `scale` move the coordinates. `withState { }` keeps a change of state or transform inside its block.
- **Keep state in properties.** A `Feedback`, an `Accumulator`, a loaded `Image`, or a `Mesh` is made once, in `setup()` or as a stored property, and used every frame.

[Sketch](./Core/Sketch.md) covers the lifecycle and [Canvas](./Core/Canvas.md) the canvas and window.

<a name="clock"></a>

### The clock and randomness

- **`time`** is seconds since `setup()`. In a window it adds up the real frame steps, each capped at 0.25 s, so a stall pauses the clock rather than jumping it. In an export it is exactly the frame number over the frame rate.
- **`frameCount`** is 1 during the first `draw()`. **`deltaTime`** is the step since the last frame: 0 on the first frame in a window, exactly `1 / fps` in an export.
- **`loopProgress(over:phase:)`** runs from 0 up to 1 over the given seconds and wraps. **`pingPong(over:phase:)`** goes 0 to 1 and back.
- **`loopDuration`** declares the length of one lap. It does not change `time`. It tells `--export-loop` how many frames make exactly one lap, and makes a web export loop.
- **`noLoop()`** stops the window's timer after the current frame. Exports ignore it and draw every frame they advance through.
- **`random()`** returns 0 up to but not including 1, `random(a, b)` a up to b, and `randomGaussian()` has mean 0 and deviation 1.
- **`seed(n)`** fixes both `random` and `noise` and sets `variation`. `randomSeed` and `noiseSeed` fix one each. A sketch that never seeds gets a different variation at every launch.

[Animation](./Helpers/Animation.md), [Random](./Generators/Random.md), and [Determinism](./Concepts/Determinism.md) have the rest.

<a name="calls"></a>

### The calls, by area

The names a sketch reaches for first in each area. `ollin api <name>` gives any of them in full.

| Area | Calls | Page |
| --- | --- | --- |
| Canvas and frame | `background`, `width`, `height`, `center`, `scale`, `noClear`, `makeAccumulator`, `withAccumulator`, `noLoop` | [Sketch](./Core/Sketch.md), [Accumulation](./Drawing/Accumulation.md) |
| 2D shapes | `drawCircle`, `drawEllipse`, `drawRect`, `drawLine`, `drawPoint`, `drawTriangle`, `drawArc`, `drawPolygon`, `drawNgon`, `drawStar`, `drawRing`, `drawBezier`, `drawArrow` | [Drawing](./Drawing/Drawing.md) |
| Style | `fill`, `noFill`, `stroke`, `noStroke`, `strokeWeight`, `strokeCap`, `strokeJoin`, `strokeDash`, `strokeAlign`, `blendMode`, `hollow`, `solid` | [Drawing](./Drawing/Drawing.md) |
| Transforms | `translate`, `rotate`, `scale`, `withState`, `mirrored`, `repeated`, `withClip` | [Drawing](./Drawing/Drawing.md) |
| Outlines | `drawShape`, `drawCurve`, `drawPolyline`, `Path`, `Shape`, `Contour`, `Vector2`, `drawSVG` | [Geometry](./Drawing/Geometry.md) |
| Text | `drawText`, `textFont`, `textSize`, `textAlign`, `textWidth`, `textToShapes` | [Text](./Drawing/Text.md) |
| Images | `loadImage`, `drawImage`, `Image`, `tint`, `noTint` | [Images](./Drawing/Images.md) |
| Color | `Color`, `Palette`, `Ramp`, `Gradient`, `CosinePalette`, `Colormap`, `OKLCH` | [Color](./Drawing/Color.md) |
| Math and noise | `map`, `lerp`, `clamp`, `smoothstep`, `polar`, `random`, `noise`, `signedNoise`, `fbm`, `curlNoise` | [Math](./Helpers/Math.md), [Noise](./Generators/Noise.md) |
| Motion | `loopProgress`, `pingPong`, `Easing`, `Eased`, `Sprung`, `every`, `after` | [Animation](./Helpers/Animation.md) |
| Layers and effects | `makeRenderTarget`, `withTarget`, `filtered`, `Filter`, `combined`, `postProcess`, `makeFeedback`, `withFeedback`, `generate` | [Effects](./Drawing/Effects.md) |
| Your own shaders | `Shader`, `Filter`, `Generator`, `Visual`, `drawVisual`, `compute` | [Shaders](./Shaders/Shaders.md) |
| 3D | `camera`, `Camera3D`, `cameraControl`, `drawBox`, `drawSphere`, `drawMesh`, `Mesh`, `material`, `Material`, `directionalLight`, `pointLight`, `environment`, `castShadows`, `temporalAntialiasing`, `motionBlur` | [3D](./3D/3D.md) |
| Input | `mouseX`, `mouseY`, `mouse`, `mouseIsPressed`, `key`, `keyIsPressed`, `isKeyDown` | [Input](./Helpers/Input.md) |
| Parameters | `Param`, `ParamGroup`, `Saved`, `variation` | [Parameters](./Helpers/Parameters.md) |
| Techniques | `poissonDisk`, `voronoi`, `delaunay`, `flowField`, `drawLSystem`, `drawWFC`, `packCircles`, `drawTruchet`, `stipple` | [Generators](./Generators/README.md) |

<a name="names"></a>

### Names you might reach for

Some names from other frameworks mean something else here, or nothing. `ollin api` catches the near misses and lists the sketch calls spelled like the name you typed. It cannot catch these:

| You might type | In Ollin |
| --- | --- |
| `circle(x, y, d)` | `drawCircle(x, y, radius)`, which takes a radius rather than a diameter |
| `strokeWidth`, `lineWidth` | `strokeWeight` |
| `push()` and `pop()` | `withState { }` |
| `createCanvas(w, h)` | `override var canvasSize: CanvasSize { .size(w, h) }` |
| `saveFrame` | `--export` or `--export-sequence` on the command line, or `OllinApp.image(of:frame:)` in code |
| `millis()` | `time`, in seconds |
| `radians(45)` | `.degrees(45)`, which converts degrees to the radians every drawing call takes |
| `beginShape()` and `endShape()` | `drawShape { }` with a `Path`, or `drawPolyline` for points |
| a Poisson fill, a Laplace or membrane fill of the space between marks | [`.diffuse()`](Drawing/Effects.md#generate) filtered over a layer holding the marks. `poissonDisk` is something else: it scatters points. |

<a name="units"></a>

### Units and conventions

| What | Convention |
| --- | --- |
| 2D coordinates | The origin is the top-left corner and y points down. `width` and `height` are the canvas in pixels. |
| `scale` (the property) | `min(width, height) / 1000`. Write sizes for a 1000-pixel canvas and multiply by it, and the sketch holds at any canvas size. It is separate from the `scale(_:)` transform. |
| 2D angles | Radians, 0 along +x, turning clockwise on screen because y points down. `rotate`, `drawArc`, `polar`, and `Vector2(angle:length:)` all work this way. |
| Degrees | `.degrees(45)` and `.turns(0.125)` convert to radians. The few calls that take degrees say so: an `LSystem` angle, `Ocean.windDirection`, the `Physarum` angles, and the latitude, longitude, and sun position of a `Place`. |
| Hue | A turn from 0 to 1 that wraps, in `Color(hue:saturation:brightness:)` and in `OKLCH` and `OKHSL`. |
| 3D coordinates | Right-handed with y up, and the camera looks down its own −z. Nothing draws in 3D until a camera is set with `camera`, `cameraControl`, or the like, and the camera resets every frame. |
| Field of view | Vertical, in radians, `.pi / 3` by default. A taller canvas keeps the height and shows less width, so a portrait render of a scene framed wide crops its sides. |
| Orbit | `Camera3D.orbiting(target:radius:azimuth:elevation:)` takes radians. Elevation 0 is the horizon and positive looks down from above. Azimuth 0 puts the eye on +z looking toward −z, and π/2 puts it on +x. |
| Spot light | `coneAngle` is the full cone in radians, `.pi / 6` by default. `penumbra` runs from 0 to 1. |
| Color | A `Color` holds sRGB components with straight alpha. Fills, strokes, lights, materials, and tints are converted to linear light for you. `linearRGB` and `Color(linear:green:blue:alpha:)` cross over by hand. |
| Brighter than white | A component can pass 1: `Color(linear: c.linearRGB * 3)`. It only shows brighter than white on screen when the sketch overrides `colorOutput` with `.extended`; otherwise the tone map clips it. |
| Noise | `noise`, `simplexNoise`, and `fbm` return 0 to 1. The `signed` forms (`signedNoise`, `signedFbm`) return −1 to 1. `curlNoise` returns a vector that is not normalized. `noise(loop:radius:)` loops as `loop` runs 0 to 1. |
| Export time | `--frame N` counts from 0 and draws at N / fps. In `--export-sequence`, file n is drawn at (n − 1) / fps. `--skip` is in seconds and `--start` only renumbers the files. |
| Depth-of-field light | A `SprayLine`'s `light` is the whole segment's, not light per unit length. A long line and a short one at the same `light` put down the same amount of light. |

<a name="params"></a>

### Parameters

`@Param` makes a property tunable. The live hosts show a control for it, and the command line can set it.

```swift
@Param(0...200) var radius = 120.0                     // a slider
@Param("Speed", 0.1...4, step: 0.1) var rate = 1.0    // a label and a step
@Param(1...12) var rings = 5                           // an Int is a stepper
@Param var tint: Color = .purple                       // a color well
@Param(x: 0...1080, y: 0...1080) var origin = Vector2(540, 540)
@Param(group: .folded("Advanced")) var jitter = false  // a card that starts closed
```

- An enum that is `ParamOption` (`CaseIterable`) becomes a menu, and `style: .segmented` shows every case at once.
- `group:` puts a parameter in a titled card, and parameters with no group come first. `icon:` takes an SF Symbol name.
- `$rate.show(when: $mode) { $0 == .fast }` in `setup()` hides a row. The value still holds.
- A value tuned in the inspector lives in that window until "Save parameters to Sketch.swift" writes it into the source. An export never opens the inspector, so it uses the values written in the source.
- `ollin api Param` lists every form a parameter can be declared with.

[Parameters](./Helpers/Parameters.md) has the rest.

<a name="cli"></a>

### The command line

A packaged sketch runs with `swift run <Target> <flags>`, and a single file with `ollin Sketch.swift <flags>`. With no flag the sketch opens in a window. With an export flag it renders without one and exits.

| Flag | What it does |
| --- | --- |
| `--export frame.png` | One still. `--frame N` picks the frame (from 0, default 0) and `--fps` sets the rate (default 60). Every frame before N is drawn first. |
| `--export-sequence dir` | `frame-00001.png`, `frame-00002.png`, and so on, for `--seconds S` or `--frames N`. `--skip S` runs S seconds before the first file is written. |
| `--export-video out.mp4`, `--export-gif out.gif` | A movie or a GIF, with the same `--seconds`, `--frames`, `--fps`, and `--skip`. |
| `--export-loop out.mp4` | Exactly one lap of `loopDuration`. |
| `--seed N` | The variation to render, set before `setup()`. A `seed(n)` in `setup()` overrides it. |
| `--param name=value` | Sets a parameter, before `canvasSize` is read and before and after `setup()`. Repeat it for more. A color is `#RRGGBB`, a vector `x,y`, a menu its label. |
| `--list-params` | Prints every parameter in the form `--param` takes, and stops. |
| `--settle N` | Draws each written frame N times with the clock held. A `LineSpray` and an `Accumulator` need it to converge. Anti-aliasing over time and path tracing don't. |
| `--render-quality` | `performance`, `default`, or `detail`: the sampling budgets for soft shadows, depth of field, and ambient occlusion. Exports default to `detail`. |
| `--render-scale N` | Draws each frame N times larger and averages it down. It smooths fills and polygons; shapes and strokes are already smooth. |
| `--bench` | Times 600 frames and reports the cost per frame, without writing anything. `--gpu` adds the GPU's side. |

[Export](./Output/Export.md) has every flag.

<a name="lookup"></a>

### Looking something up

Three commands answer most questions without a browser. They read the checkout you build against, so they describe the version you are running.

```sh
ollin api drawCircle           # what a name takes, what its comment says, where it is used
ollin docs Drawing/Color#ramp  # one section of one page
ollin examples ocean --source  # an example that does it, as source
```

- **`ollin api <name>`** answers "what is it called, what does it take, and is it public". It reads the listings under [`API/`](../API/README.md), which hold every public declaration, so a name it does not know cannot be reached from a sketch. It prints each declaration as its source writes it, with the comment above it, where units and ranges are written down. `ollin api Mesh.tube` picks one type's member, and `ollin api Param` lists a whole type.
- **`ollin docs <topic>`** opens a page by name or path, and `<topic>#<heading>` opens one section. `ollin docs --search "long exposure"` finds every line that says it.
- **`ollin examples <word>`** lists the sketches whose name, folder, or description matches, and `--source` prints one.

`ollin` is `Scripts/ollin` in the checkout, and it works from any folder. `ollin install` puts it on your `PATH`. Its output is plain text under a pipe, so it composes with `grep`. [The reference offline](./Tools/Reference.md) has the rest.

<a name="quiet"></a>

### Things that fail quietly

Each of these gives a wrong or empty picture and no error.

- **`background()` after drawing into layers.** Outside a `withTarget` block it clears everything recorded so far this frame, layers included, so their composite comes out black. Call it first in `draw()`. See [Effects](./Drawing/Effects.md#withtarget).
- **A layer that is drawn into but never drawn.** Nothing reaches the canvas until its image does: `drawImage(layer.image, 0, 0)`. A `LineSpray`'s pass count climbs all the same, and the canvas shows only the background until `drawImage(spray.developed(exposure: 1).image, 0, 0)`.
- **Drawing in `setup()`.** The geometry is thrown away before the first frame, and a camera, a light, or shadows set there are gone by the first `draw()`. Draw and set per-frame state in `draw()`.
- **A concave outline through `drawPolygon`.** It fills as a fan from the first point, which only works for a convex shape. A concave one goes through `drawShape { }` or a `Shape`.
- **A `Feedback` or `Accumulator` made inside `draw()`.** A fresh one every frame never builds up. Make it once, in `setup()`.
- **A long, faint sum on a `noClear()` canvas.** The canvas is half-float, so a light added a little at a time stops brightening. Use `makeFeedback(precision: .float32)` or an `Accumulator`.
- **A still at frame 0.** `--export` draws frame 0 unless told otherwise, and nothing came before it: motion blur is off and a trail or a pile holds one frame. Pick a later frame with `--frame N`. A `LineSpray` or an `Accumulator` is the exception: `--settle N` redraws the frame with the clock held, so it converges even at frame 0.
- **Motion driven by `frameCount` under `--settle`.** The clock holds for the extra draws but `frameCount` keeps counting, so a camera driven by it moves and restarts the converging picture. Drive motion from `time`.
- **Values tuned in the inspector, in an export.** The export uses the values in the source. Save them first, or pass `--param`.
- **Values the command line reads loosely.** A `--param` outside the declared range is clamped, an unknown `--render-quality` becomes `detail`, and an `--fps` that does not parse becomes the default. None of them says so.
- **`Filter.grain` in the shadows.** It adds noise and clips it, which lifts black. `.filmGrain` leaves black and white alone, though its grain still shows most in near-black tones.
- **A `@Param` icon that is not an SF Symbol.** The row shows an empty space where the icon goes.
- **3D on a `noClear()` canvas.** Nothing is sorted by depth and nothing casts a shadow.
- **A texture on a mesh with no texture coordinates.** The texture is ignored, and the mesh draws in its base color.
- **A `print` during an exported sequence.** It lands on the same terminal line as the progress text, and later than expected when the output is piped. Write to standard error with a newline first, or read the value after the run.

<a name="checking"></a>

### Checking your work

- **Judge speed in a release build.** `swift run` builds the framework for debugging, which runs several times slower. Use `swift run -c release`, or `ollin`, which runs a release host and compiles the sketch optimized. `--bench` gives numbers.
- **Judge motion in a sequence, not a still.** Anything that needs earlier frames (motion blur, trails, a pile, a settling picture) shows properly only a few frames in. A short `--export-sequence` shows it.
- **Compare pixels, not bytes.** Every exported PNG carries its recipe in its description: the seed, every parameter, the commit, the frame, and the frame rate. Two files with the same pixels differ when any of those do, so compare the pictures, for instance with `compare -metric AE a.png b.png null:` from ImageMagick.
- **Fix the seed before comparing two runs.** Call `seed(n)` in `setup()` or pass `--seed N`, or every run is a new variation.

---

### See also

- [Documentation index](./README.md): every page, by area
- [Swift quick reference](./Swift.md): the language, at the same length
- [The reference offline](./Tools/Reference.md): `ollin docs`, `ollin examples`, and `ollin api`
- [Guide Chapter 1](../Guide/01-HelloOllin.md): the first sketch, run and changed
