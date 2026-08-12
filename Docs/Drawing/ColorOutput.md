#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Wide gamut & HDR output`</sup>

---

## Wide gamut & HDR output

Every frame is composited in a linear, floating-point buffer, so it already holds more color than an ordinary screen shows: saturations sRGB has no room for, and light piled up past full brightness. All of it is thrown away at the last step, where the frame is encoded for an 8-bit sRGB display.

`colorOutput` decides how much survives instead. It is a declared property, not a call, because the window's drawable is built from it once:

```swift
final class Glow: Sketch {
    override var colorOutput: ColorOutput { .extended }
}
```

Nothing changes for a sketch that says nothing: `.standard` is byte-for-byte what Ollin has always rendered, dither included.

### Contents

- [The three settings](#settings)
- [Naming a color outside sRGB](#wide-colors) - `Color(displayP3:green:blue:)`
- [Brightness above white](#headroom) - what `.extended` needs from the display
- [What exports carry](#exports) - HDR10 video, wide-gamut stills
- [Notes](#notes)

<a id="settings"></a>
### The three settings

| Setting | Gamut | Range | Drawable |
| --- | --- | --- | --- |
| `.standard` | sRGB | 0…1 | 8-bit sRGB, dithered. The default. |
| `.wide` | Display P3 | 0…1 | 16-bit float. Colors outside sRGB reach the screen, and gradients stop banding. |
| `.extended` | Display P3 | above 1 | 16-bit float, with headroom asked of the system. Values over 1.0 show as highlights brighter than white. |

Each step is strictly deeper than the last: `.extended` is `.wide` plus the range.

The two axes are worth keeping apart, because they answer different questions. **Gamut** is *which* colors, and it costs nothing to ask for: a P3 red is a red no sRGB screen can make, and it is there whenever the display can show it. **Range** is *how bright*, and it depends on the display having headroom to spare at that moment.

<a id="wide-colors"></a>
### Naming a color outside sRGB

`Color` is an sRGB type, and it stays one. A color outside that gamut is named in Display P3 and stored as the sRGB components that mean the same thing, which lands some of them outside 0…1:

```swift
let wideRed = Color(displayP3: 1, green: 0, blue: 0)
// wideRed.red is about 1.08, .green about -0.08: outside sRGB, on purpose
wideRed.isOutsideSRGB          // true
wideRed.displayP3Components    // back to (1, 0, 0)
```

Nothing clamps it on the way through. The whole pipeline carries the out-of-range value, and the present pass converts it into the display's gamut, where it comes back positive. On a `.standard` sketch the same color simply clips to the nearest sRGB one at the very end, so naming a P3 color is always safe: it is deeper where there is room and ordinary where there is not.

White is white in both gamuts, exactly. `Color(displayP3: 1, green: 1, blue: 1)` is `Color.white`, not a near miss.

<a id="headroom"></a>
### Brightness above white

In `.extended`, 1.0 is paper white, whatever the display's brightness makes that, and higher values are highlights above it. How far above is not up to the sketch: the system grants headroom and takes it back as the display's brightness and the surrounding content change. Read what you actually have:

```swift
displayHeadroom     // 1.0 = none, 2.0 = values up to 2.0 are shown
```

Turning the screen brightness *down* usually grants more, since headroom is measured relative to how bright white already is.

Two consequences worth knowing before reaching for `.extended`:

- **It does nothing for a frame that never leaves 0…1.** The setting keeps highlights that a sketch already makes, with additive blending, a bloom, accumulated light. It does not invent them.
- **Tone-mapping pulls the other way.** [`ToneMap.reinhard` and `.aces`](./HDR.md) exist to squeeze out-of-range values into 0…1 for an ordinary screen, which is exactly what an HDR display does not need. Leave the tone-map at its `.clamp` default here and the highlights keep their brightness; set a curve and they are compressed back to white before the display ever sees them.

<a id="exports"></a>
### What exports carry

| Export | `.standard` | `.wide` | `.extended` |
| --- | --- | --- | --- |
| `--export` (PNG) | 8-bit sRGB | 16-bit Display P3 | 16-bit Display P3, highlights clipped to white |
| `--export-video` | Rec. 709 | P3-D65 | **HDR10**: Rec. 2020 primaries, PQ transfer, 10-bit HEVC |
| `--export-gif` | sRGB | converted to sRGB | converted to sRGB |
| `--export-svg` / `--export-pdf` | unaffected (vector output carries its own color) |

An `.extended` video is written as HDR10 with no further flags. The codec is forced to `hevc` if it was left at the h264 default, because eight bits cannot carry it, and the encoder is asked to work out the mastering-display and content-light-level metadata the file declares. In the file, 1.0 is the standard's reference white of 203 cd/m², so an exported clip's paper white lands where every other HDR video's does, and the peak carried is 1000 cd/m² (about 4.9x white).

**Stills keep the gamut but not the range.** PNG and HEIC have nowhere to put brightness above white without a gain map, so an `.extended` still is a wide-gamut one with its highlights clipped. If the highlights are the point, export video.

<a id="notes"></a>
### Notes

- **`.standard` is untouched.** Not "close": the 8-bit path runs the same present shader it always did, and the whole snapshot suite renders byte-for-byte identically. The wider outputs run a separate shader beside it.
- **It isn't slower.** A float drawable writes twice the bytes, but the 8-bit path pays for its dither and its transfer curve per pixel, which costs more than the bytes save. Measured on an M2 at 1080², the present pass is about 0.2 ms *cheaper* in `.wide` than in `.standard`. So the reason to stay on `.standard` is compatibility with whatever reads your output, not speed.
- **It takes effect at launch.** Live reload cannot swap the window's drawable under a running frame, so editing `colorOutput` in a live-reloading host prints a note and applies on the next launch.
- **Headroom is read every frame, not at launch.** The system moves it around; a sketch that draws its own brightness reference should read `displayHeadroom` rather than assume.
- **Off-screen there is no display to ask.** A headless render of an `.extended` sketch keeps its highlights unclamped, which is what lets an exported HDR video have any.
- **The gamut conversion is exact.** Linear sRGB to linear Display P3 (and to Rec. 2020 for video) is a change of primaries between two D65 spaces, so no white point moves and each matrix row sums to 1.
- **Spatial video stays standard.** `--export-spatial` writes its stereo pair at `.standard`; HDR and MV-HEVC together are not wired up.

### See also

- [`HDR & tone-mapping`](./HDR.md) - the float pipeline underneath, and the curves that map it down
- [`Color`](./Color.md) - the `Color` type, the OKLab family, ramps and palettes
- [`Export`](../Output/Export.md) - every export flag, and what each one writes
