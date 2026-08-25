#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Print separations`</sup>

---

## Print separations

Risograph and screen-print presses have no full-color mode. They print one *spot ink* at a time. Each pass lays down a translucent layer of a single color, and the picture emerges where the layers overlap on the paper, blue over yellow reading green, pink over blue reading violet. What the press needs from you is one **grayscale master per ink**, black where that drum should print, plus faith that the overprint will look the way you hope.

Print separations give you both the masters and an honest on-screen preview of the overprint.

```swift
let separation = artwork.separated(into: [.fluorescentPink, .blue, .yellow])
drawImage(separation.preview())          // how the print will read
drawImage(separation.layers[0].master)   // pink's master: black = full ink
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/Separations-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/Separations.jpg" alt="Four panels: three grayscale masters labeled fluorescent pink, blue, and yellow, each carrying a different part of the same image, followed by the color preview of the three overprinted" width="680">
</picture>

For every pixel, `separated(into:paper:)` finds the ink coverages whose overprint comes closest to the pixel's color. The model is the physical one: each ink is a translucent filter, coverage mixes in linear light, and layers multiply on the paper. Which mix *looks* closest is judged perceptually (OKLab), the same split the [dithering](../Drawing/Color.md) pass uses. Drawing with an ink's own color separates exactly; everything else lands on the nearest reachable mix, so gradients, overlaps, and photographs all separate into the same few drums.

The model's limits are physical too. Inks only darken, so nothing lighter than the paper is reachable, and an opaque white ink on dark stock is outside the model. The catalog's ink colors are the community-measured screen approximations (soy inks do not conform exactly to any color standard). The printed proof is the ground truth, so treat the preview as a good sketch of it.

### Inks

An `Ink` is a name and the color it prints at full coverage on white stock. The built-in catalog carries the standard risograph ink line, 78 inks named the way a print shop stocks them:

```swift
let inks: [Ink] = [.black, .fluorescentPink, .mediumBlue]
Ink.named("flat gold")                   // catalog lookup, forgiving about case and spaces
Ink.catalog                              // all 78, in catalog order
let shop = Ink(name: "Shop Blue", color: Color(hex: 0x2B5DD7))   // your own
```

### Screening the masters

The masters come back with continuous tones, which most riso RIPs accept directly. For 1-bit films, or for the classic dotted look, screen them first. The preview of a screened separation shows the actual dots:

```swift
separation.dithered()                    // blue-noise grain (or pass any Dither)
separation.dithered(.floydSteinberg)
separation.halftoned(pitch: 8)           // classic round-dot screens
```

`halftoned` rotates each layer's dot grid to its own angle, the darkest ink taking the least visible 45 degrees, so the drums overprint into the traditional rosette instead of moire (pass `angles:` in radians to choose your own). Both passes preserve tone exactly, so a 30% gray becomes dots covering 30% of the paper. Both also drop coverage below 2% to bare paper (and above 98% to solid ink), which is the minimum dot a press can hold. Without that floor, the invisible sub-1% residue that 8-bit rounding leaves in "white" areas would screen into stray specks.

Separation and screening are per-pixel CPU work, memoized per distinct color, so run them in `setup()` and hold the result rather than once per frame. A GPU-backed image has no CPU pixels to read and returns an empty separation (`snapshot()` first). Everything is deterministic. The same image, inks, and paper always give the same masters, so separations are safe to snapshot and export.

### Exporting print files

A sketch made for printing declares its inks the way a looping sketch declares `loopDuration`:

```swift
final class Poster: Sketch {
    override var printInks: [Ink]? { [.fluorescentPink, .blue, .yellow] }
    // draw the poster normally...
}
```

Then the export flag does the rest:

```sh
swift run Poster --export-separations poster.png
swift run Poster --export-separations poster.png --screen halftone --pitch 8
swift run Poster --export-separations poster.png --inks "black, flat gold" --paper FFF7E8
```

This renders one frame headlessly (`--frame N` picks which), separates it, and writes one grayscale PNG per ink plus the composite preview:

```
poster-1-fluorescent-pink.png    1/3  Fluorescent Pink  29% ink
poster-2-blue.png                2/3  Blue  23% ink
poster-3-yellow.png              3/3  Yellow  22% ink
poster-preview.png               overprint preview
```

Every file carries a white margin band with **registration targets** at the four corners and the layer's label along the bottom, drawn in full ink on every layer. Each drum prints its own targets, and when the crosses stack cleanly on paper the print is in register. `--no-marks` writes the bare canvas instead. The rest of the flags fill in the details. `--inks` overrides the declared set by catalog name, `--paper` tints the stock (hex), `--screen dither|halftone` pre-screens the masters (`--pitch` sets the halftone cell in pixels), and `--seed`/`--render-quality` work as on every export path. Each PNG embeds the standard [reproduction recipe](Export.md) plus the ink list.

The same work is available programmatically:

```swift
OllinApp.separations(of: sketch, frame: 30)                   // -> PrintSeparation?
OllinApp.exportSeparations(sketch, to: "poster.png") { $0.dithered() }
```

The average coverage each layer reports (`layer.averageInk`, also printed at export) is worth a glance before printing, because layers much above a third of the sheet are heavy for most presses.

See `Examples/Color/PrintSeparation` for a poster that declares its inks and flips between artwork, masters, and preview in the inspector.
