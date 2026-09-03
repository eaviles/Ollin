#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `HDR & tone-mapping`</sup>

---

## HDR & tone-mapping

Ollin composites every frame in a **linear, high-precision floating-point** buffer, then maps it down to the screen in a final pass. Two things fall out of that:

- **Color can exceed full brightness.** Additive light piling up through [`blendMode(.add)`](../Drawing/Drawing.md#blendmode), a bright gradient, or overlapping glows all push past 1.0. The intermediate holds those values instead of clipping them mid-render. What happens to those values when the frame reaches an ordinary 8-bit screen is your choice, set with `toneMap(_:)`.
- **No 8-bit banding.** Smooth gradients and the many translucent layers a busy sketch stacks all composite at float precision. Gradients that an 8-bit intermediate would step into visible bands stay smooth. This is automatic, with nothing to turn on.

By default a sketch behaves exactly as a standard renderer, so anything brighter than full clips to white. The interesting part is opting into a curve that *rolls* highlights off instead.

### Contents

- [toneMap](#tonemap) - map high-dynamic-range color to the screen
- [exposure](#exposure) - the brightness dial
- [The modes](#modes) - clamp, Reinhard, ACES
- [Notes](#notes)

<a id="tonemap"></a>
### toneMap(_:exposure:)

Choose how out-of-range (brighter-than-1.0) color is brought back into displayable range.

```swift
override func setup() {
    toneMap(.aces)          // roll highlights off with a film-like curve
}
```

It's a **frame-wide setting**, not per-shape state. One mapping is applied to the finished frame, so unlike `fill` or `blendMode` it isn't saved by `withState { }`. Set it once in `setup()` and it persists until changed. Called with no arguments it defaults to `.reinhard`:

```swift
toneMap()                   // == toneMap(.reinhard, exposure: 1)
```

Pair it with additive light accumulation for the glow look:

```swift
override func draw() {
    background(.black)
    toneMap(.aces, exposure: 1.6)
    blendMode(.add)                 // lights sum past 1.0…
    // …draw bright overlapping shapes; ACES rolls the hot cores off smoothly
}
```

<a id="exposure"></a>
### exposure

`exposure` scales the whole image *before* the tone-map, like a camera's brightness dial. Turn it up to pull faint accumulation into view, down to tame a scene that saturates:

```swift
toneMap(.aces, exposure: 2.0)   // brighter, more of the scene pushed up the curve
toneMap(.aces, exposure: 0.5)   // dimmer
```

It applies under every mode, including `.clamp` (where it just brightens before the clip).

<a id="modes"></a>
### The modes

| Mode | Curve | Look |
| --- | --- | --- |
| `.clamp` | clip to [0, 1] | **The default.** Standard dynamic range, so anything past full saturates to white, exactly as before. An in-range frame renders identically. |
| `.reinhard` | `x / (1 + x)` | Squeezes every value under 1.0 so highlights never fully clip. Cheap and gentle, though it tends to desaturate bright areas. |
| `.aces` | ACES filmic S-curve | Rolls highlights off while holding contrast and saturation in the midtones. The richer choice for glow and light-accumulation looks. |

<img src="../../Guide/Images/16-LayersAndEffects/ToneClamp.jpg" alt="Three overlapping tinted lamps under the default clamp tone map: the entire overlapping middle blows out to a flat white slab with hard seams" width="680">

<img src="../../Guide/Images/16-LayersAndEffects/ToneAces.jpg" alt="The same three lamps through the ACES film curve: the middle stays bright but keeps its warm, mint, and blue tints, rolling off softly like film" width="680">

See the `Rendering/ToneMapping` example. Colored lamps orbit and overlap additively, and a key cycles the three mappings. Watch the bright cores clip, compress, or roll off.

<a id="notes"></a>
### Notes

- **`.clamp` is byte-for-byte the old look.** The float pipeline doesn't change a standard-dynamic-range sketch. With the default `.clamp` and `exposure: 1`, an in-range frame renders the same as it always did. Tone-mapping is purely opt-in.
- **The sandpainting look needs a divide, not only a curve.** Faint samples summed additively need float precision to accumulate without quantizing away, and a tone-map rolls the built-up light onto the screen. But a sum on a [`noClear`](../Drawing/Accumulation.md) surface keeps growing, so the tone map only postpones the moment the picture goes white. The look is built on the running **mean**, the sum divided by the passes drawn, which an [`Accumulator`](../Drawing/Accumulation.md#accumulator) keeps, printed through [`Filter.develop`](../Drawing/DepthOfField.md#develop): exposure, a Reinhard roll-off, and a ground added after the curve. The [depth-of-field particle rendering](../../Examples/Rendering/DepthOfField/Sketch.swift) is built that way.
- **Output is 8-bit unless you ask otherwise.** The screen and exported PNGs are 8-bit sRGB by default. The float precision lives in the *intermediate*, which is why banding disappears and HDR values survive compositing even though the final image is 8-bit. A triangular dither is applied at that 8-bit step to keep gradients smooth. The last step opens up through [`colorOutput`](./ColorOutput.md), where `.wide` presents through Display P3 in float. Under `.extended`, values above 1.0 stay as highlights brighter than white instead of being mapped down.
- **Exports tone-map identically.** The headless still `--export`, the sequence, video, and GIF exports, and live frame-sharing all run the same present pass. Frame-sharing covers Syphon and the virtual camera. What you export and share matches what you see.
