#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Parameters`</sup>

---

## Parameters

A `@Param` is a tunable knob. Declare one on a sketch and read it like a normal property, and the live host discovers it and shows a control for it, so a value you would otherwise hand-edit and recompile becomes something you adjust while the sketch runs. The control follows the property's type, so a `Double` gets a slider, a `Bool` a toggle, and a `Color` a color well. The same knob can also be driven from hardware, since an OSC address or a MIDI controller binds straight onto it.

```swift
final class Pulse: Sketch {
    @Param(0...200) var radius = 120.0        // slider "Radius", from the name
    @Param("Speed", 0.1...4) var rate = 1.0   // explicit label
    @Param var filled = true                  // toggle

    override func draw() {
        background(.white)
        if filled { fill(.black) } else { noFill() }
        drawCircle(width / 2, height / 2, radius + sin(time * rate) * 40)
    }
}
```

### Contents

- [The typed family](#family)
- [Groups and icons](#groups)
- [Where the controls appear](#controls)
- [Scrubbing values](#scrubbing)
- [Smoothing](#smoothing)
- [Driving a knob from outside](#binding)
- [The parameter object](#param-object)

<a name="family"></a>

### The typed family

Each supported type declares itself the same way and gets the matching inspector control:

| Property type | Control | Declaration |
| --- | --- | --- |
| `Double` | slider + value field | `@Param(0...200) var radius = 120.0` |
| `Int` | stepper (− value +) | `@Param(1...12) var rings = 5` |
| `Bool` | toggle | `@Param var filled = true` |
| enum (`ParamOption`) | pop-up menu | `@Param var style: Style = .dots` |
| `Color` | color well | `@Param var ink: Color = .black` |
| `Vector2` | paired x/y fields | `@Param(x: 0...1080, y: 0...1080) var anchor = Vector2(540, 540)` |
| `Vector3` | x/y/z fields | `@Param(x: -1...1, y: -1...1, z: 0...10) var eye = Vector3(0, 0, 5)` |
| `Rectangle` | x/y and w/h fields | `@Param(x: 0...1080, y: 0...1080, width: 10...1080, height: 10...1080) var region = …` |
| `Insets` | t/r/b/l fields | `@Param(0...200) var margins = Insets.all(40)` |
| `ClosedRange<Double>` | two-thumb slider + min/max fields | `@Param(in: 1...60) var sizes = 6.0...24.0` |
| `String` | text field | `@Param var caption = "hello"` |
| `ParamChoices` type | pop-up menu | `@Param var mood: LightingPreset = .standard` |

A numeric value is always clamped to its range, and the property's default is the starting value. The label is derived from the property name (`noiseScale` becomes "Noise Scale"), or pass one explicitly as the first argument when the name reads poorly.

A `Double` can also take a `step:`, which snaps every write to that increment (so the sketch reads exactly the values the slider offers):

```swift
@Param(0...1, step: 0.25) var mix = 0.5
```

An enum becomes a menu by conforming to `ParamOption` (declare it `CaseIterable`):

```swift
enum Style: String, CaseIterable, ParamOption { case dots, rings, meshLines }
@Param var style: Style = .dots
```

The menu shows humanized case names ("Mesh Lines"), and `optionLabel` overrides the wording. The persisted selection keys on the case *name*, so renaming a case forgets a tuned choice while reordering is safe. Ollin's own mode enums (`BlendMode`, `StrokeCap`, `StrokeJoin`, `Colormap`) already conform, so `@Param var blend: BlendMode = .normal` gets its menu with no declaration at all.

A type that isn't an enum but has a fixed roster of named built-ins joins the menu tier through `ParamChoices` instead. Provide `paramChoices`, a list of `(name, value)` pairs, and the inspector shows the humanized names. `LightingPreset` conforms out of the box. The type's `Equatable` is what lets the menu find the current selection, which is also why `Easing` (a closure wrapper, no equality) and the parameterized `Material` finishes don't take this route.

The color well opens the system color panel, eyedropper included, so a sketch's palette is tunable live. The vector, rectangle, and insets forms take a range per field and clamp each independently, and the min/max pair stays ordered inside its `in:` bounds, with a minimum dragged past the maximum pushing the maximum along.

#### Control styles

A few kinds take a `style:` when the default control isn't the right feel:

```swift
@Param(1...100_000, style: .field) var iterations = 2000.0    // no track, just the value box
@Param(x: 0...1080, y: 0...1080, style: .pad) var anchor = …  // adds a draggable XY pad
@Param(in: 1...60, style: .field) var sizes = 6.0...24.0      // fields only, no two-thumb track
@Param(style: .segmented) var mode: Style = .dots             // every case visible at once
```

`.field` drops a numeric control's track, the fit for a precise quantity or a range too wide for a slider to resolve. The XY pad maps its square to the two ranges with the top-left corner at both lower bounds, matching the canvas origin, so dragging the dot feels like dragging on the canvas. A segmented control suits two to four short names. When the segments don't fit beside the label the row wraps them to a full-width control underneath, and longer case lists should stay on the default menu.

#### Your own types

`ParamValue` is public, so you conform a type by providing the clamp, the `ParamStored` round-trip, and the `ParamControl` it edits with. The control must be one of the existing kinds (a custom type presents as a slider, menu, fields, and so on; the inspector doesn't take custom rows), so the conformance is really a mapping from your type onto the closest built-in control. `ParamOption` covers the common case (any `CaseIterable` enum) and `ParamChoices` the named-catalog one, both with almost no work, so reach for a full `ParamValue` conformance only when a wrapped scalar or compound type genuinely wants to be a knob.

<a name="groups"></a>

### Groups and icons

Every form takes an optional `icon:` and `group:`:

```swift
@Param(10...375, icon: "circle.dashed", group: "Rings") var radius = 175.0
@Param(1...12, icon: "circle.grid.2x2", group: "Rings") var rings = 5
@Param(0...4, icon: "speedometer", group: "Motion") var speed = 1.0
```

`group:` names an inspector section, so each group renders as its own titled card, in the order groups first appear in the sketch. Knobs without a group lead the list under the default "Parameters" header. `icon:` is an SF Symbol name shown leading the row, and rows without one stay aligned when the card mixes both.

<a name="controls"></a>

### Where the controls appear

Under the live-reload host (`swift run OllinLive path/to/Sketch.swift`), every `@Param` is a control in the inspector sidebar. Tuned values survive a reload, so when you save the file and the sketch hot-swaps, the host re-applies what you dialed in and a knob doesn't snap back to its default mid-session. If an edit changes a property's *type*, the stale tuned value is dropped and the freshly written default wins.

A standalone run of an example gets the same controls in the inspector panel, under View ▸ Show Inspector (⌘/), and the examples gallery shows them in its right sidebar.

Headless export never opens an inspector, so a render uses the defaults written in code. Once a tuned value feels right, copy it back into the declaration.

<a name="scrubbing"></a>

### Scrubbing values

Every numeric value box scrubs, so drag horizontally across it to change the value, the way pro inspectors do. Hold **Option** while dragging for a fine adjust (a tenth of the speed), **Shift** for a coarse one (ten times). A plain click starts typing instead, and a typed value is clamped to the range on commit. The slider, the box, and the scrub all drive the same knob.

<a name="smoothing"></a>

### Smoothing

```swift
@Param(20...400, smoothing: .eased(0.3)) var radius = 120.0   // 0.3s glide
@Param(0...1, smoothing: .smoothed) var mix = 0.5             // adaptive 1€ filter
```

Pass a `smoothing:` and the knob glides into each new value instead of snapping. `.eased(duration, curve:)` glides over a fixed time along an [`Easing`](../Helpers/Animation.md#easing) curve, crisp and predictable. `.smoothed(minCutoff:beta:)` runs the value through the [1€ filter](../Helpers/Animation.md#smoothed), which stays steady while the knob rests and opens up as it moves, and that tends to feel better under a hand on live hardware.

The softening lives on the parameter, so every source gets it, and a MIDI fader, an OSC message, and a drag of the inspector slider all glide the same way. The sketch advances the glide each frame on its own, like `@Eased` and `@Smoothed`. Smoothing is a `Double` affair, and the other kinds switch instantly.

<a name="binding"></a>

### Driving a knob from outside

The projected value (`$radius`) is the parameter object itself, and it's what the integration libraries bind to:

```swift
osc.bind("/radius", to: $radius)            // an OSC address (OllinOSC)
midi.bind(controlChange: 7, to: $radius)    // a MIDI CC knob (OllinMIDI)
```

Each incoming value is mapped into the parameter's range and assigned, and a bound knob updates on its own as messages arrive. The inspector control, the binding, and plain assignment in code all drive the same value, and whichever moved most recently wins. Bindings target `Double` parameters. The `from:` input ranges and the rest of the details are on the [OSC](../Integration/OSC.md#binding-to-a-param) and [MIDI](../Integration/MIDI.md#binding-to-a-param) pages.

A parameter is safe to read and write from any thread, so the inspector drives it from the main thread while an OSC or MIDI callback writes from its own queue.

<a name="param-object"></a>

### The parameter object

Two more things live on `$radius`:

```swift
$radius.set(200)    // jump straight there, skipping any smoothing glide
$radius.range       // the declared bounds (Double and Int parameters)
```

Assignment retargets (and glides, when smoothed), while `set(_:)` lands immediately. The live host uses `set` to restore your tuned values across a reload, where gliding in from the default would look wrong.

A knob is also sweepable offline. `--export-sweep` renders a proof sheet along one parameter's range, one tile per value, and every tile is pinned to the same seed, so the knob is the only thing changing across the sheet. Seeds stay what they are on the [Variations](../Core/Variations.md) page, a sketch's identity; a sweep is a tuning tool, the inspector's drag laid out as a sheet:

```sh
swift run --package-path Examples Example-Live-Parameters --export-sweep sweep.png --param radius --from 40 --to 360
```

The full flag list is on the [Export](../Output/Export.md#contact-sheets-proofing-a-variation-space) page, and `OllinApp.contactSheet(of:sweeping:values:seed:)` is the code form.

For building your own control surface, `parameters()` returns the sketch's knobs as `[ParamHandle]`: a stable `name` key, a display `label`, the `icon` and `group` metadata, and the type-erased `param`. Its `control` describes the matching UI (kind, ranges, options, and live get/set closures), and `stored` / `restore(_:)` round-trip the value through the small `ParamStored` payload the hosts persist. The live host builds its inspector from exactly this, and most sketches never call it.

The [Parameters example](../../Examples/Live/Parameters/Sketch.swift) is the worked demo, a spread of the typed family in three groups driving a ring pattern, made for `swift run OllinLive Examples/Live/Parameters/Sketch.swift`.
