#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Wide gamut & HDR output`</sup>

---

## Wide gamut & HDR output

Every frame is composited in a linear, floating-point buffer, so it already holds more color than an ordinary screen shows. It holds saturations that sRGB has no room for, and light that has piled up past full brightness. All of that is thrown away at the last step, where the frame is encoded for an 8-bit sRGB display.

`colorOutput` decides how much of it survives instead. You declare it as a property rather than call it, because the window's drawable is built from it once:

```swift
final class Glow: Sketch {
    override var colorOutput: ColorOutput { .extended }
}
```

A sketch that sets nothing stays on `.standard`, which is byte-for-byte what Ollin has always rendered, dither included.

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

Each setting includes the one before it, so `.extended` is `.wide` plus the range.

Gamut and range are two separate things, and they answer different questions.

- **Gamut** is *which* colors you get, and asking for a wider one costs nothing. A P3 red is a red no sRGB screen can make, and you get it whenever the display can show it.
- **Range** is *how bright* those colors go, and it depends on the display having headroom to spare at that moment.

<a id="wide-colors"></a>
### Naming a color outside sRGB

`Color` is an sRGB type, and it stays one. You name a color outside that gamut in Display P3. Ollin stores it as the sRGB components that mean the same color, so some of those components land outside 0…1:

```swift
let wideRed = Color(displayP3: 1, green: 0, blue: 0)
// wideRed.red is about 1.08, .green about -0.08: outside sRGB, on purpose
wideRed.isOutsideSRGB          // true
wideRed.displayP3Components    // back to (1, 0, 0)
```

Nothing clamps that value on the way through. The whole pipeline carries it, and the present pass converts it into the display's gamut, where it comes back positive. On a `.standard` sketch the same color clips to the nearest sRGB color at the very end. So naming a P3 color is always safe. It is deeper where there is room for it, and ordinary where there is not.

White is exactly the same in both gamuts. `Color(displayP3: 1, green: 1, blue: 1)` is `Color.white`, not a near miss.

<a id="headroom"></a>
### Brightness above white

In `.extended`, 1.0 is paper white at whatever the display's brightness makes that, and higher values are highlights above it. How far above is not up to the sketch. The system grants headroom, and it takes that headroom back as the display's brightness and the surrounding content change. Read how much headroom you have right now:

```swift
displayHeadroom     // 1.0 = none, 2.0 = values up to 2.0 are shown
```

Turning the screen brightness *down* usually gives you more headroom, because headroom is measured against how bright white already is.

Two things follow from this, and both are worth knowing before you use `.extended`:

- **It does nothing for a frame that never leaves 0…1.** The setting keeps the highlights a sketch already makes. Additive blending, a bloom, and accumulated light all produce them. It does not invent them.
- **Tone-mapping works against it.** The curves [`ToneMap.reinhard` and `.aces`](./HDR.md) squeeze out-of-range values into 0…1 for an ordinary screen. An HDR display does not need that. Leave the tone-map at its `.clamp` default here and the highlights keep their brightness. Set a curve instead and they are compressed back to white before the display ever sees them.

<a id="exports"></a>
### What exports carry

| Export | `.standard` | `.wide` | `.extended` |
| --- | --- | --- | --- |
| `--export` (PNG) | 8-bit sRGB | 16-bit Display P3 | 16-bit Display P3, highlights clipped to white |
| `--export` (HEIC) | 8-bit sRGB | 8-bit Display P3 | Display P3 **plus an ISO gain map**: the highlights ride along |
| `--export-video` | Rec. 709 | P3-D65 | **HDR10**: Rec. 2020 primaries, PQ transfer, 10-bit HEVC |
| `--export-gif` | sRGB | converted to sRGB | converted to sRGB |
| `--export-svg` / `--export-pdf` | unaffected (vector output carries its own color) |

An `.extended` video is written as HDR10, and you need no further flags for it. If the codec was left at the h264 default, Ollin forces it to `hevc`, because eight bits cannot carry HDR10. The encoder works out the mastering-display and content-light-level metadata that the file declares. In the file, 1.0 is the standard's reference white of 203 cd/m², so an exported clip's paper white lands where every other HDR video's does. The peak the file carries is 1000 cd/m², about 4.9x white.

**A HEIC still keeps the range as well as the gamut.** The file name picks the format, so `--export frame.heic` writes HEIC and `--export frame.png` writes PNG. PNG stops at white. HEIC carries a second image beside the picture, called a gain map, which records how much light was thrown away in making the picture. A display with headroom multiplies the two together and gets the frame back.

```sh
swift run --package-path Examples Example-Rendering-ColorOutput --export lamp.heic
# Ollin: exported frame 0 → lamp.heic (1080×1080, highlights to 2.70x white in a gain map)
```

That line reports what the file carries. A frame that never went above white carries no gain map, and the line says so.

The file guarantees three things:

- The picture inside it is the PNG. A reader that knows nothing of gain maps shows the frame clamped at white.
- The map's ceiling is the frame's own brightest value, so a small highlight keeps its brightness. A lamp core covers a fraction of a percent of the canvas. A map whose ceiling comes from frame statistics loses a highlight that small.
- The map holds a gain per channel, so a bright amber core stays amber. Reconstruction is accurate to about one percent, and the 8-bit picture under the map sets that floor.

The gain map is written in ISO 21496-1, the cross-vendor gain-map standard, not in a private format that only one viewer reads.

PNG is still the deeper file in one way. It writes 16 bits a channel where HEIC writes 8, so a slow gradient has more levels to work with. Pick HEIC when the highlights matter, and PNG when precision matters.

<a id="notes"></a>
### Notes

- **`.standard` is untouched.** It is unchanged, not merely close. The 8-bit path runs the same present shader it always did, and the whole snapshot suite renders byte-for-byte identically. The wider outputs run a separate shader beside it.
- **It isn't slower.** A float drawable writes twice the bytes. Even so, the 8-bit path pays for its dither and its transfer curve on every pixel, which costs more than those bytes save. Measured on an M2 at 1080², the present pass is about 0.2 ms *cheaper* in `.wide` than in `.standard`. The reason to stay on `.standard` is compatibility with whatever reads your output, not speed.
- **It takes effect at launch.** Live reload cannot swap the window's drawable under a running frame. Editing `colorOutput` in a live-reloading host therefore prints a note and applies on the next launch.
- **Headroom is read every frame, not at launch.** The system moves it around while the sketch runs. A sketch that draws its own brightness reference should read `displayHeadroom` instead of assuming a value.
- **Off-screen there is no display to ask.** A headless render of an `.extended` sketch keeps its highlights unclamped. That is what lets an exported HDR video have any.
- **The gamut conversion is exact.** Linear sRGB to linear Display P3 is a change of primaries between two D65 spaces. No white point moves, and each matrix row sums to 1. The conversion to Rec. 2020 for video works the same way.
- **Spatial video stays standard.** `--export-spatial` writes its stereo pair at `.standard`, because HDR and MV-HEVC together are not wired up.

### See also

- [`HDR & tone mapping`](./HDR.md) - the float pipeline underneath, and the curves that map it down
- [`Color`](./Color.md) - the `Color` type, the OKLab family, ramps and palettes
- [`Export`](../Output/Export.md) - every export flag, and what each one writes
