# Accessibility

Two things a sketch can do for somebody whose eyes or preferences differ from yours: check that its colors still hold apart, and offer a quieter version of its motion.

Neither is applied for you. Ollin gives you the reading and the preview, and the sketch decides what to do with them.

## Seeing your colors as somebody else does

About one man in twelve and one woman in two hundred sees color differently from the palette most work is designed against. `ColorVision` names one such way of seeing.

```swift
let seen = Color.red.simulated(.deuteranopia)
```

The three kinds are named after the cone whose response is shifted:

| Kind | The cone | How common |
|---|---|---|
| `.protanomaly` | long wavelength, nearest red | about 1 man in 100 |
| `.deuteranomaly` | middle wavelength | the commonest kind |
| `.tritanomaly` | short wavelength, nearest blue | rare, and usually acquired |

Severity runs from 0, which changes nothing, to 1, which is dichromacy: the cone is missing rather than shifted. `.protanopia`, `.deuteranopia` and `.tritanopia` are the three at full severity. Anything between is anomalous trichromacy, which is the far commoner case.

```swift
ColorVision.deuteranopia            // the cone is gone
ColorVision.deuteranomaly(0.4)      // it is shifted, not gone
```

`Kind` is a `ParamOption`, so it can be a knob in the live inspector, with a `Double` beside it for the severity.

### A whole sketch at once

`Filter.colorVision` puts the same reading over everything you drew.

```swift
override func draw() {
    // ... your sketch ...
    postProcess(.colorVision(.deuteranopia))
}
```

Put it behind a `@Param` toggle and you can flip in and out of the check while you work. It costs one full-screen pass, and it belongs in linear light, which is what a layer already holds, so nothing is encoded on the way through.

`Palette` and `Ramp` have `simulated(_:)` too, for drawing a comparison rather than replacing the frame.

### Whether a palette holds apart

`confusions(under:)` names the pairs that land on each other.

```swift
for pair in myPalette.confusions(under: .deuteranopia) {
    print("colors \(pair.first) and \(pair.second) are \(pair.distance) apart")
}

if !myPalette.isColorblindSafe() { /* pick again */ }
```

`confusions()` with no argument checks all three kinds at full severity. Either way the worst pair comes first, so the first entry is the one to fix.

**Lightness is what saves a pair.** The check measures the whole distance, lightness as well as hue, because that is the whole judgement. Red and green look alike to a protanope in hue, but one is much darker than the other, so the pair is still usable. Two colors of the same lightness that differ only in hue are the ones that merge. Measured on a red and a green matched for lightness: 0.281 apart for average vision, and 0.014 apart under the worst kind. Step them apart in lightness and the same two hues stay 0.601 apart.

So the practical rule is to vary lightness, not only hue, and to give a shape or a label to anything that color alone distinguishes.

### A set that already works

```swift
fill(Palette.colorblindSafe[i])
```

Eight colors published for color universal design by Okabe and Ito, and the usual answer when a piece needs categories anybody can follow. Its closest pair under the worst kind sits at 0.076. A familiar six-color chart set falls to 0.007 under the same test.

### The tolerance

The default tolerance of 0.06 is measured rather than guessed. It sits between those two numbers with room on either side. Pass your own if a piece needs a stricter or looser bar.

### What the model is

The simulation is the physiologically based model of Machado, Oliveira and Fernandes (2009), which treats color vision deficiency as a shift in a cone's spectral absorption. A color is linearized, multiplied by a 3x3 matrix chosen by kind and severity, and encoded back. The published table gives a matrix every 0.1 of severity, and a value in between interpolates its two neighbours, which is the approximation the model's authors describe.

The matrices weight the power of the display primaries, so they belong in linear light. Applying them to display values instead is a common mistake and gives a visibly different color.

A simulation is a working aid rather than a report of somebody's experience. It shows where a design leans on a distinction that will not survive. It does not tell you what another person sees.

## Motion

Ollin animates by default. For some people that is a problem rather than a feature, and macOS carries a Reduce Motion setting to say so.

```swift
let speed = prefersReducedMotion ? 0.1 : 1.0
```

The setting is read fresh, so turning it on reaches a running sketch on the next frame. A headless render always reads `false`, so an export is the same file on any machine.

Nothing changes on its own. A sketch decides what less movement means, because only the sketch knows which of its movements carries the piece and which is decoration. Common answers: slow a drift, hold a value that was oscillating, drop a flash, or cut a camera move to a still framing.

## What is not here yet

- **A description for a screen reader.** The counterpart of p5's `textOutput()`, so a generative piece is not opaque. See the [roadmap](../../ROADMAP.md#accessibility-and-inclusive-text).
- **Complex-script text.** Core Text shapes right-to-left scripts, CJK and combining marks correctly, but that path is not yet verified or surfaced here.

## See also

- [Color](../Drawing/Color.md) - the color type, palettes, ramps and mixing
- [Effects](../Drawing/Effects.md) - the rest of the filter catalog
- [Parameters](./Parameters.md) - putting the kind on a knob
