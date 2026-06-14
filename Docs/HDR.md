#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `HDR & tone-mapping`</sup>

---

## HDR & tone-mapping

Ollin composites every frame in a **linear, high-precision floating-point** buffer, then maps it down to the screen in a final pass. Two things fall out of that:

- **Color can exceed full brightness.** Additive light piling up ([`blendMode(.add)`](./Drawing.md#blendmode)), a bright gradient, overlapping glows — the intermediate holds values above 1.0 instead of clipping them mid-render. What happens to those values when the frame reaches an ordinary 8-bit screen is your choice, set with `toneMap(_:)`.
- **No 8-bit banding.** Smooth gradients and the many translucent layers a busy sketch stacks composite at float precision, so the gradients that an 8-bit intermediate would step into visible bands stay smooth. This is automatic — there's nothing to turn on.

By default a sketch behaves exactly as a standard renderer: anything brighter than full clips to white. The interesting part is opting into a curve that *rolls* highlights off instead.

### Contents

- [toneMap](#tonemap) — map high-dynamic-range color to the screen
- [exposure](#exposure) — the brightness dial
- [The modes](#modes) — clamp, Reinhard, ACES
- [Notes](#notes)

<a id="tonemap"></a>
### toneMap(_:exposure:)

Choose how out-of-range (brighter-than-1.0) color is brought back into displayable range.

```swift
override func setup() {
    toneMap(.aces)          // roll highlights off with a film-like curve
}
```

It's a **frame-wide setting**, not per-shape state: one mapping is applied to the finished frame, so — unlike `fill` or `blendMode` — it isn't saved by `withState { }`. Set it once in `setup()` (it persists until changed). Called with no arguments it defaults to `.reinhard`:

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
toneMap(.aces, exposure: 2.0)   // brighter — more of the scene pushed up the curve
toneMap(.aces, exposure: 0.5)   // dimmer
```

It applies under every mode, including `.clamp` (where it just brightens before the clip).

<a id="modes"></a>
### The modes

| Mode | Curve | Look |
| --- | --- | --- |
| `.clamp` | clip to [0, 1] | **The default.** Standard-dynamic-range: anything past full saturates to white, exactly as before. An in-range frame renders identically. |
| `.reinhard` | `x / (1 + x)` | Squeezes every value under 1.0 so highlights never fully clip. Cheap and gentle; tends to desaturate bright areas. |
| `.aces` | ACES filmic S-curve | Rolls highlights off while holding contrast and saturation in the midtones. The richer choice for glow and light-accumulation looks. |

See the `Basic/ToneMapping` example: colored lamps orbit and overlap additively, and a key cycles the three mappings so you can watch the bright cores clip, compress, or roll off.

<a id="notes"></a>
### Notes

- **`.clamp` is byte-for-byte the old look.** The float pipeline doesn't change a standard-dynamic-range sketch: with the default `.clamp` and `exposure: 1`, an in-range frame renders the same as it always did. Tone-mapping is purely opt-in.
- **It's the foundation of the sandpainting track.** Faint samples summed additively on a [`noClear`](./Accumulation.md) surface need float precision to accumulate without quantizing away, and a tone-map to bring the built-up light back to the screen. The depth-of-field particle rendering on the roadmap builds directly on this.
- **Output is still 8-bit.** The screen and exported PNGs are 8-bit sRGB; the float precision lives in the *intermediate*, which is why banding disappears and HDR values survive compositing even though the final image is 8-bit. A triangular dither is applied at the 8-bit step to keep gradients smooth.
- **Exports tone-map identically.** The headless still (`--export`), the sequence/video/GIF exports, and live frame-sharing (Syphon, the virtual camera) all run the same present pass, so what you export and share matches what you see.
