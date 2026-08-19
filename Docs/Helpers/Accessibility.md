# Accessibility

A sketch can do three things for somebody whose eyes or preferences differ from yours. It can say what it shows, check that its colors hold apart, and offer quieter motion.

None of it is applied for you. Ollin gives you the reading, the preview and the words, and the sketch decides what to do with them.

## Saying what the sketch shows

A generative piece is a picture with no caption. A screen reader arrives at the window and finds a rectangle of pixels with nothing to say about it. `describe` is how the sketch answers.

```swift
override func draw() {
    // ... your sketch ...
    describe("A pale field with one red circle drifting across it.")
}
```

That sentence becomes the canvas's accessible name. Turn on VoiceOver (⌘F5) and the window reads it out.

### Naming the parts

A piece with more than one thing in it can name them.

```swift
describe("the sun", as: "a yellow disc high on the left")
describe("the boat", as: "a small dark hull, halfway across", in: hull)
```

A part is a shape, or a group of shapes that mean one thing together. Each one becomes something a screen reader can move to, read as `name: description`, in the order the parts were first named.

The `in:` region is optional and worth giving. A part that carries one can be found by position rather than only in order. The accessibility inspector draws a box around it too.

### Describing something that moves

Write the description from the same numbers that draw the picture, and it cannot go stale.

```swift
let p = Vector2(x, y)
drawCircle(center: p, radius: r)
describe("the sun", as: "a yellow disc \(p.y < height / 2 ? "high" : "low")",
         in: Rectangle(center: p, width: r * 2, height: r * 2))
```

Calling `describe` every frame is the normal case, and it costs one line:

- Naming the same part again **replaces** what you said. The list does not grow.
- Empty text **takes a part out** of the picture. Naming it again puts it back **in the same place**, so a part that comes and goes does not send the reading order jumping.
- `noDescription()` clears everything.

A screen reader is told to look again only when the set of parts changes. Rewording a part stays quiet, which is what stops a sketch from interrupting sixty times a second.

### What to write

Describe what is there, not how it is made. One or two sentences, present tense, the way you would tell somebody over the telephone. "A red circle drifting left across a pale field", not "a `drawCircle` driven by `sin(time)`".

Keep the parts few. A list of fifty shapes tells nobody what the piece looks like. Texture is not a part: the glow around a sun and the shimmer on water are worth drawing and not worth naming.

To show the words as well as say them, draw them. `drawCaption(_:)` puts a line on the canvas, and `accessibleDescription.lines` is everything the sketch has said.

### Where the words go

| Where | What carries it |
|---|---|
| the window | the canvas's accessible name, and one element per part |
| `--export-svg` | `<title>` and `<desc>`, which is how a drawing carries its description |
| `--export-pdf` | the document title |
| PNG, GIF, video | nothing; there is no standard place to put it |

An export writes what the sketch said on the frame being exported.

### Ollin does not write it for you

There is no call that reads your shapes and produces a description. A list of what was drawn is not a description of what it means, and only the sketch knows which circle is the sun. The words are yours, the same way the colors are.

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

## See also

- [Describing](../../Examples/Basic/Describing/Sketch.swift) - a sketch that says what it shows while it shows it
- [Text](../Drawing/Text.md#scripts) - complex-script shaping: Arabic, Devanagari, Thai, vertical layouts
- [Color](../Drawing/Color.md) - the color type, palettes, ramps and mixing
- [Effects](../Drawing/Effects.md) - the rest of the filter catalog
- [Parameters](./Parameters.md) - putting the kind on a knob
