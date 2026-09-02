#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Print color`</sup>

---

## Print color

A screen makes color with light and a press makes it with ink on paper, and the screen wins. The electric cyan of a backlit pixel is not a color four inks can lay down. It reaches the press and comes back as the nearest thing ink can do. The blacks come back lighter for the same reason: ink on paper does not reach a black pixel's black.

A **soft proof** runs that trip on purpose. Every color on the canvas is carried into the printer's profile and back out again, and what comes home changed is exactly what the press is going to change. The same profile also answers the two other questions a print job turns on: which colors are unreachable (the **gamut check**), and how much of each ink the artwork asks for (the **plates**).

```swift
let press = SoftProof(.genericCMYK)                   // or a profile the shop hands out
postProcess(.softProof(press))                        // the canvas, as it will print
postProcess(.softProof(press, warning: .magenta))     // and what will not survive
```

The transforms are the system's own. ColorSync is the color engine every color-managed application on this Mac already shares, it reads the same `.icc` files a print shop hands out, and Ollin asks it rather than reimplementing it.

### Profiles

An `ICCProfile` describes what one device does with color. The built-ins cover the everyday cases, and a real press hands out its own file:

```swift
ICCProfile.sRGB                                 // what an Ollin canvas is, by default
ICCProfile.displayP3                            // what a `.wide` or `.extended` canvas is
ICCProfile.genericCMYK                          // a generic four-ink press
ICCProfile(contentsOf: url)                     // the shop's own profile
ICCProfile(resource: "press", in: .module)      // one bundled with the sketch
ICCProfile.installed()                          // every profile on this machine
ICCProfile.installed(named: "US Web Coated (SWOP) v2")
```

A profile reports what it is (`name`, `space`, `channelCount`, `channelNames`, `isOutputDevice`), which is enough to build a menu of the presses a studio has installed. Profiles are values: `Sendable`, `Hashable`, cheap to pass around and to key on.

The generic four-ink profile is close enough to show which colors are in trouble, but it is not any particular press. Ask the shop for theirs before trusting a proof for a real job.

### The proof

A `SoftProof` is the printing condition: which press, from which canvas, under which intent.

```swift
var press = SoftProof(.genericCMYK, from: .sRGB, intent: .relative)
press.simulatesPaper = true                      // show the stock's own color too
```

`intent` decides how a color the press cannot reach is brought inside its gamut. `.relative` (the default) keeps every reproducible color exactly and clips the rest to the nearest one it holds, which is what flat graphic work wants. `.perceptual` compresses the whole picture so the relationships between colors survive, at the price of shifting colors that would have printed correctly. It is only as good as the tables the profile carries for it, and a profile without them falls back to relative. `.saturation` favors vividness over accuracy, for charts. `.absolute` is relative without remapping white, which is what puts the paper's own color into the picture.

Two things are always shown and one is opt-in. Saturated colors always come back duller, and black always comes back lighter (the proof runs without black point compensation on purpose, so it shows the real ceiling on contrast rather than hiding it). Paper color is `simulatesPaper`, off by default, because a proof of cream stock reads as a wrong-looking white until you are expecting it.

Proofing an `Image` is one call:

```swift
let proofed = artwork.softProofed(press)                     // as the press will print it
let flagged = artwork.softProofed(press, warning: .magenta)  // with the losses marked
```

### The gamut check

The proof shows what changes; the gamut check names what is unreachable at all. ColorSync answers that question directly, so this is a transform rather than a guess about how far apart two colors look.

```swift
artwork.outOfGamutFraction(press)      // 0…1, how much of the picture will not print
artwork.gamutMask(press)               // white where it will not print, black where it will
```

The fraction is the number to print while tuning a palette. Under a few percent is ordinary; a third of the canvas means the piece is being drawn in colors that will not survive.

### Proofing live

The full transform costs about 150 ms on a 1080 by 1080 canvas, far too slow per frame. So the live filter bakes the printing condition into a 33 by 33 by 33 lattice once, in about 4 ms, and samples that lookup per pixel. It is how a proofing view in any color-managed application works.

```swift
postProcess(.softProof(press))                              // the whole frame
layer.filtered(.softProof(press, warning: .magenta))        // one layer
postProcess(.softProof(press, warning: .magenta, amount: 0))  // flag only, colors untouched
```

`amount` blends between the canvas as drawn and the proof. At `0` the colors are left alone and only the warning shows, which is the mode for checking a palette without living inside the proof. The lattice is cached per printing condition, so changing the intent or the paper parameter answers immediately and costs one bake the first time.

### Plates

A process-color separation splits the canvas into one grayscale plate per channel the profile describes, black where that ink lands. Unlike the [spot-ink separation](PrintSeparations.md), nothing is searched or modeled: the profile already describes what that press does with color, so the channel values come straight from the color engine.

```swift
let plates = artwork.separated(into: press)      // or .separated(into: .genericCMYK)
drawImage(plates.preview())                      // the print, as the profile predicts it
drawImage(plates.plates[3].master)               // the black plate on its own
plates.plates[0].name                            // "Cyan"
plates.peakTotalInk                              // 2.89 means 289% ink at the heaviest spot
plates.averageTotalInk
```

**Total area coverage** is the number a shop asks for and a screen never shows: the sum of all four coverages at one spot. 400% is every ink solid on the same square millimeter, sheet-fed presses hold around 300%, and newsprint gives up closer to 240%. Ollin reports it rather than enforcing it, because the fix is in the artwork. (On *screened* plates the same figures count overlapping dots instead of continuous coverage, so read them off the unscreened separation.)

The plates screen like the spot-ink masters, at the conventional four-color angles:

```swift
plates.halftoned(pitch: 8)      // cyan 15, magenta 75, yellow 0, black 45 degrees
plates.dithered()               // blue-noise grain (or pass any Dither)
```

Separation is per-pixel CPU work, so run it in `setup()` (or offline) and hold the result. A GPU-backed image has no CPU pixels and separates into nothing (`snapshot()` first), as does a profile the system cannot read. Everything is deterministic, so plates are safe to snapshot and export.

### Exporting print files

A sketch made for printing declares its printing condition the way a looping sketch declares `loopDuration`:

```swift
final class Poster: Sketch {
    override var printProfile: ICCProfile? { .genericCMYK }
    // draw the poster normally...
}
```

Then the export flag does the rest:

```sh
swift run Poster --export-plates poster.png
swift run Poster --export-plates poster.png --screen halftone --pitch 8
swift run Poster --export-plates poster.png --profile ~/Profiles/press.icc --intent perceptual
```

This renders one frame headlessly (`--frame N` picks which), separates it, and writes one grayscale PNG per channel plus the proof of the finished print:

```
poster-1-cyan.png        1/4  Cyan  42% ink
poster-2-magenta.png     2/4  Magenta  55% ink
poster-3-yellow.png      3/4  Yellow  35% ink
poster-4-black.png       4/4  Black  10% ink
poster-preview.png       proof  Generic CMYK Profile  289% peak ink
```

Every file carries a white margin band with **registration targets** at the four corners and the plate's label along the bottom. It is the same band the spot-ink masters wear, so the two paths hand a shop the same kind of file. `--no-marks` writes the bare canvas instead. `--profile` takes a path or the name of a profile installed on this machine, `--intent` picks the rendering intent, `--paper` puts the stock's color into the proof, `--screen dither|halftone` pre-screens the plates (`--pitch` sets the halftone cell in pixels), and `--seed`/`--render-quality` work as on every export path. Each PNG embeds the standard [reproduction recipe](Export.md) plus the plate names and the printing condition.

The same work is available programmatically:

```swift
OllinApp.plates(of: sketch, profile: press, frame: 30)        // -> ProcessSeparation?
OllinApp.exportPlates(sketch, to: "poster.png") { $0.halftoned(pitch: 8) }
```

### Which separation

Two paths lead to a press, and the profile is what tells them apart. Reach for **[print separations](PrintSeparations.md)** when the shop prints one spot ink at a time from a named ink line, which is riso and screen printing: there is no profile for those inks, so Ollin models the overprint physically and searches for the coverages. Reach for **plates** when the press runs process color through a profile that has actually been measured on it, which is offset and most digital printing: there is nothing to model, so the profile answers directly.

See `Examples/Color/SoftProof` for a poster that wipes the proof across itself, flags what will not print, and shows the four plates.

---

Next: [Print separations](PrintSeparations.md) for the spot-ink path this sits beside, and [Color output](../Drawing/ColorOutput.md) for the other end of the pipeline, where a canvas decides how wide its own color is.
