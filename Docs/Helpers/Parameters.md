#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Parameters`</sup>

---

## Parameters

A `@Param` is a tunable knob. Declare one on a sketch and read it like a normal property; the live host discovers it and shows a slider for it, so a value you would otherwise hand-edit and recompile becomes something you adjust while the sketch runs. The same knob can also be driven from hardware: an OSC address or a MIDI controller binds straight onto it.

```swift
final class Pulse: Sketch {
    @Param(0...200) var radius = 120.0        // slider "Radius", from the name
    @Param("Speed", 0.1...4) var rate = 1.0   // explicit label

    override func draw() {
        background(.white)
        drawCircle(width / 2, height / 2, radius + sin(time * rate) * 40)
    }
}
```

### Contents

- [Declaring a parameter](#declaring)
- [Where the sliders appear](#sliders)
- [Smoothing](#smoothing)
- [Driving a knob from outside](#binding)
- [The parameter object](#param-object)

<a name="declaring"></a>

### Declaring a parameter

```swift
@Param(_ range: ClosedRange<Double>, smoothing: ParamSmoothing? = nil)
@Param(_ label: String, _ range: ClosedRange<Double>, smoothing: ParamSmoothing? = nil)
```

A parameter holds a `Double`, always clamped to its range; the property's default is the starting value. The slider label is derived from the property name (`noiseScale` becomes "Noise Scale"), or pass one explicitly when the name reads poorly as a label.

For a count, keep the parameter a `Double` and round where you use it:

```swift
@Param(1...12) var rings = 5.0

override func draw() {
    for i in 0..<Int(rings) { … }
}
```

<a name="sliders"></a>

### Where the sliders appear

Under the live-reload host (`swift run OllinLive path/to/Sketch.swift`), every `@Param` is a slider in the inspector sidebar. Tuned values survive a reload: when you save the file and the sketch hot-swaps, the host re-applies what you dialed in, so a knob doesn't snap back to its default mid-session.

A standalone run (`swift run Example-…`) gets the same sliders in the inspector panel, under View ▸ Show Inspector (⌘/).

Headless export never opens an inspector, so a render uses the defaults written in code. Once a tuned value feels right, copy it back into the declaration.

<a name="smoothing"></a>

### Smoothing

```swift
@Param(20...400, smoothing: .eased(0.3)) var radius = 120.0   // 0.3s glide
@Param(0...1, smoothing: .smoothed) var mix = 0.5             // adaptive 1€ filter
```

Pass a `smoothing:` and the knob glides into each new value instead of snapping. `.eased(duration, curve:)` glides over a fixed time along an [`Easing`](../Helpers/Animation.md#easing) curve, crisp and predictable. `.smoothed(minCutoff:beta:)` runs the value through the [1€ filter](../Helpers/Animation.md#smoothed), which stays steady while the knob rests and opens up as it moves; that tends to feel better under a hand on live hardware.

The softening lives on the parameter, so every source gets it: a MIDI fader, an OSC message, and a drag of the inspector slider all glide the same way. The sketch advances the glide each frame on its own, like `@Eased` and `@Smoothed`.

<a name="binding"></a>

### Driving a knob from outside

The projected value (`$radius`) is the parameter object itself, and it's what the integration libraries bind to:

```swift
osc.bind("/radius", to: $radius)            // an OSC address (OllinOSC)
midi.bind(controlChange: 7, to: $radius)    // a MIDI CC knob (OllinMIDI)
```

Each incoming value is mapped into the parameter's range and assigned, and a bound knob updates on its own as messages arrive. The inspector slider, the binding, and plain assignment in code all drive the same value; whichever moved most recently wins. The `from:` input ranges and the rest of the details are on the [OSC](../Integration/OSC.md#binding-to-a-param) and [MIDI](../Integration/MIDI.md#binding-to-a-param) pages.

A parameter is safe to read and write from any thread: the inspector drives it from the main thread while an OSC or MIDI callback writes from its own queue.

<a name="param-object"></a>

### The parameter object

Two more things live on `$radius`:

```swift
$radius.set(200)    // jump straight there, skipping any smoothing glide
$radius.range       // the declared bounds
```

Assignment retargets (and glides, when smoothed); `set(_:)` lands immediately. The live host uses `set` to restore your tuned values across a reload, where gliding in from the default would look wrong.

For building your own control surface, `parameters()` returns the sketch's knobs as `[ParamHandle]`: a stable `name` key, a display `label`, and the `param` itself. The live host builds its sliders from exactly this; most sketches never call it.

The [Parameters example](../../Examples/Live/Parameters/Sketch.swift) is the worked demo: three knobs driving a ring pattern, made for `swift run OllinLive Examples/Live/Parameters/Sketch.swift`.
