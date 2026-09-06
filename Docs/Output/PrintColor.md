#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Print color`</sup>

---

## Print color

A screen makes color with light, and a press makes color with ink on paper. The screen can show more colors than the press can print. The bright cyan of a backlit pixel is not a color that four inks can produce. Send that cyan to the press and it comes back as the nearest color the ink can make. Blacks come back lighter for the same reason. Ink on paper does not get as dark as a black pixel.

A **soft proof** makes that round trip on purpose. It converts every color on the canvas into the printer's profile and back out again. Any color that comes back changed is a color the press is going to change. The same profile also answers the two other questions a print job depends on. The **gamut check** names which colors cannot be printed at all. The **plates** say how much of each ink the artwork needs.

```swift
let press = SoftProof(.genericCMYK)                   // or a profile the shop hands out
postProcess(.softProof(press))                        // the canvas, as it will print
postProcess(.softProof(press, warning: .magenta))     // and what will not survive
```

The color transforms come from the system. ColorSync is the color engine that every color-managed application on this Mac already shares. It reads the same `.icc` files a print shop hands out, so Ollin asks ColorSync for the transforms rather than reimplementing them.

### Profiles

An `ICCProfile` describes what one device does with color. The built-in profiles cover the everyday cases, and a real press supplies its own file:

```swift
ICCProfile.sRGB                                 // what an Ollin canvas is, by default
ICCProfile.displayP3                            // what a `.wide` or `.extended` canvas is
ICCProfile.genericCMYK                          // a generic four-ink press
ICCProfile(contentsOf: url)                     // the shop's own profile
ICCProfile(resource: "press", in: .module)      // one bundled with the sketch
ICCProfile.installed()                          // every profile on this machine
ICCProfile.installed(named: "US Web Coated (SWOP) v2")
```

A profile reports what it is through `name`, `space`, `channelCount`, `channelNames`, and `isOutputDevice`. That is enough to build a menu of the presses a studio has installed. Profiles are values. They are `Sendable` and `Hashable`, so they are cheap to pass around and to key on.

The generic four-ink profile is close enough to show which colors will not print well, but it does not describe any particular press. Ask the shop for its own profile before you trust a proof for a real job.

### The proof

A `SoftProof` describes the printing condition: which press, from which canvas, and under which rendering intent.

```swift
var press = SoftProof(.genericCMYK, from: .sRGB, intent: .relative)
press.simulatesPaper = true                      // show the stock's own color too
```

`intent` decides where a color the press cannot reach ends up inside the press's gamut. `.relative` is the default. It keeps every printable color exactly as it is and clips each unprintable color to the nearest one the press can print. That is what flat graphic work wants. `.perceptual` compresses the whole picture so that the relationships between colors survive, at the cost of shifting colors that would have printed correctly. This intent is only as good as the tables the profile carries for it, and a profile without those tables falls back to relative. `.saturation` favors vividness over accuracy, which suits charts. `.absolute` is the same as relative but does not remap white, and that is what puts the paper's own color into the picture.

The proof always shows two changes, and a third is opt-in. Saturated colors come back duller, and black comes back lighter. The proof runs without black point compensation on purpose, so it shows the real limit on contrast rather than hiding it. Paper color is the opt-in change, controlled by `simulatesPaper`. It is off by default, because the white in a proof on cream stock looks wrong until you know to expect it.

Proofing an `Image` is one call:

```swift
let proofed = artwork.softProofed(press)                     // as the press will print it
let flagged = artwork.softProofed(press, warning: .magenta)  // with the losses marked
```

### The gamut check

The proof shows what changes. The gamut check names the colors that cannot be printed at all. ColorSync answers that question directly, so the check is a color transform rather than a guess about how far apart two colors look.

```swift
artwork.outOfGamutFraction(press)      // 0…1, how much of the picture will not print
artwork.gamutMask(press)               // white where it will not print, black where it will
```

The fraction is the number to watch while you tune a palette. A value under a few percent is ordinary. A value near a third of the canvas means the piece is drawn in colors that will not survive printing.

### Proofing live

The full transform takes about 150 ms on a 1080 by 1080 canvas, which is too slow to run every frame. So the live filter bakes the printing condition into a 33 by 33 by 33 lattice once, in about 4 ms. Then it samples that lookup table per pixel. A proofing view in any color-managed application works the same way.

```swift
postProcess(.softProof(press))                              // the whole frame
layer.filtered(.softProof(press, warning: .magenta))        // one layer
postProcess(.softProof(press, warning: .magenta, amount: 0))  // flag only, colors untouched
```

`amount` blends between the canvas as drawn and the proof. At `0` the colors are left alone and only the warning shows. That is the mode for checking a palette without working inside the proof the whole time. The lattice is cached per printing condition. A change to the intent or to `simulatesPaper` costs one bake the first time, and after that the filter answers immediately.

### Plates

A process-color separation splits the canvas into one grayscale plate per channel the profile describes. Each plate is black where that ink lands. Plates need no search and no model, unlike the [spot-ink separation](PrintSeparations.md). The profile already describes what that press does with color, so the channel values come straight from the color engine.

```swift
let plates = artwork.separated(into: press)      // or .separated(into: .genericCMYK)
drawImage(plates.preview())                      // the print, as the profile predicts it
drawImage(plates.plates[3].master)               // the black plate on its own
plates.plates[0].name                            // "Cyan"
plates.peakTotalInk                              // 2.89 means 289% ink at the heaviest spot
plates.averageTotalInk
```

**Total area coverage** is the sum of every ink's coverage at one spot. A shop asks for that number, and a screen never shows it. Its ceiling is 100% per ink, so a four-ink press tops out at 400%, which is every ink solid on the same square millimeter. A profile with more inks tops out higher. Sheet-fed presses accept around 300%, and newsprint's limit is closer to 240%. Ollin reports the number rather than enforcing it, because the fix is in the artwork. On *screened* plates the same figures count overlapping dots instead of continuous coverage, so read them from the unscreened separation.

The plates screen in the same way as the spot-ink masters, at the conventional four-color angles:

```swift
plates.halftoned(pitch: 8)      // cyan 15, magenta 75, yellow 0, black 45 degrees
plates.dithered()               // blue-noise grain (or pass any Dither)
```

Separation is per-pixel work on the CPU, so run it in `setup()` or offline and keep the result. A GPU-backed image has no CPU pixels, so it separates into nothing. Call `snapshot()` on it first. Separation also produces nothing when the system cannot read the profile. Everything is deterministic, so plates are safe to snapshot and export.

### Exporting print files

A sketch made for printing declares its printing condition, in the same way that a looping sketch declares `loopDuration`:

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

This renders one frame headlessly, and `--frame N` picks which frame. It separates that frame and writes one grayscale PNG per channel plus a proof of the finished print:

```
poster-1-cyan.png        1/4  Cyan  42% ink
poster-2-magenta.png     2/4  Magenta  55% ink
poster-3-yellow.png      3/4  Yellow  35% ink
poster-4-black.png       4/4  Black  10% ink
poster-preview.png       proof  Generic CMYK Profile  289% peak ink
```

Every file carries a white margin band with **registration targets** at the four corners and the plate's label along the bottom. It is the same band the spot-ink masters carry, so the two paths hand a shop the same kind of file. `--no-marks` writes the bare canvas instead. `--profile` takes a path or the name of a profile installed on this machine. `--intent` picks the rendering intent. `--paper` puts the stock's color into the proof. `--screen dither|halftone` pre-screens the plates, and `--pitch` sets the halftone cell in pixels. `--seed` and `--render-quality` work as they do on every export path. Each PNG embeds the standard [reproduction recipe](Export.md) plus the plate names and the printing condition.

The same work is available from code:

```swift
OllinApp.plates(of: sketch, profile: press, frame: 30)        // -> ProcessSeparation?
OllinApp.exportPlates(sketch, to: "poster.png") { $0.halftoned(pitch: 8) }
```

### Which separation

Two paths lead to a press, and the profile is the difference between them. Use **[print separations](PrintSeparations.md)** when the shop prints one spot ink at a time from a named ink line. That is how riso and screen printing work. There is no profile for those inks, so Ollin models the overprint physically and searches for the coverages. Use **plates** when the press runs process color through a profile measured on that press. That is how offset and most digital printing work. There is nothing to model, so the profile answers directly.

See `Examples/Color/SoftProof` for a poster that wipes the proof across itself, flags what will not print, and shows the four plates.

---

Next: [Print separations](PrintSeparations.md) covers the spot-ink path, the other route to a press. After that, [Color output](../Drawing/ColorOutput.md) covers the other end of the pipeline, where a canvas decides how wide its own color is.
