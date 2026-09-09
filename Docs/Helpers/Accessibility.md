# Accessibility

A sketch can do three things for somebody whose eyes or preferences differ from yours. It can describe what it shows, check that its colors hold apart, and offer quieter motion.

Ollin applies none of this for you. It gives you the Reduce Motion setting, the color vision simulation, and the `describe` call. Your sketch decides what to do with them.

## Saying what the sketch shows

A generative piece carries no caption. A screen reader that reaches the window finds a rectangle of pixels, so it has nothing to read out. `describe` gives it a sentence to read.

```swift
override func draw() {
    // ... your sketch ...
    describe("A pale field with one red circle drifting across it.")
}
```

That sentence becomes the canvas's accessible name. Turn on VoiceOver (⌘F5), and the window reads it out.

### Naming the parts

A piece with more than one thing in it can name each of them.

```swift
describe("the sun", as: "a yellow disc high on the left")
describe("the boat", as: "a small dark hull, halfway across", in: hull)
```

A part is one shape, or a group of shapes that mean one thing together. Each part becomes an element a screen reader can move to. The screen reader reads it as `name: description`, and it visits the parts in the order they were first named.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/SayingWhatItShows-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/SayingWhatItShows.jpg" alt="Two columns: on the left a small seascape with a yellow sun high on the left, a blue band of water and a dark sailboat; on the right the four lines the sketch says about itself, a summary followed by the sun, the water and the boat" width="680">
</picture>

The `in:` region is optional, but it is worth giving. A part that has a region can be found by position, not only in order, and the accessibility inspector draws a box around it.

### Describing something that moves

Write the description from the same numbers that draw the picture. Then the description always matches what the sketch draws.

```swift
let p = Vector2(x, y)
drawCircle(center: p, radius: r)
describe("the sun", as: "a yellow disc \(p.y < height / 2 ? "high" : "low")",
         in: Rectangle(center: p, width: r * 2, height: r * 2))
```

Calling `describe` every frame is the normal case, and it needs one line of code:

- Naming the same part again **replaces** what you said. The list does not grow.
- Empty text **removes** a part from the description. Naming it again puts it back **in the same place**, so a part that comes and goes does not make the reading order jump.
- `noDescription()` clears everything.

Ollin tells the screen reader to look again only when the set of parts changes. Rewording a part sends no notice, so a sketch that describes every frame does not interrupt sixty times a second.

### What to write

Describe what is there, not how it is made. Use one or two sentences in the present tense, the way you would describe the picture to somebody over the telephone. Write "A red circle drifting left across a pale field", not "a `drawCircle` driven by `sin(time)`".

Keep the parts few, because a list of fifty shapes tells nobody what the piece looks like. Texture is not a part, so leave it out. Draw the glow around a sun and the shimmer on water, but do not name them.

You can also show the words on the canvas. `drawCaption(_:)` draws one line, and `accessibleDescription.lines` holds everything the sketch has said.

### Where the words go

| Where | What carries it |
|---|---|
| the window | the canvas's accessible name, and one element per part |
| `--export-svg` | `<title>` and `<desc>`, which is how an SVG drawing carries its description |
| `--export-pdf` | the document title |
| PNG, GIF, video | nothing, because there is no standard place to put it |

An export carries the words the sketch said on the frame being exported.

### Ollin does not write it for you

There is no call that reads your shapes and produces a description. A list of what was drawn does not say what it means, and only you know which circle is the sun. So you write the words yourself.

## Seeing your colors as somebody else does

About one man in twelve and one woman in two hundred sees color differently from the palette most work is designed against. A `ColorVision` value stands for one of those ways of seeing, and the calls below take one to simulate it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/02-Color/ColorVision-dark.jpg">
  <img src="../../Guide/Images/02-Color/ColorVision.jpg" alt="A photograph of woven blankets and two palettes, each drawn in four columns: as most people see them, then under protanopia, deuteranopia and tritanopia. The blankets' reds and greens flatten into one olive band in the middle two columns while the blues hold. In the chart set the orange, green and red arrive as that same olive. The safe set stays separable" width="680">
</picture>

```swift
let seen = Color.red.simulated(.deuteranopia)
```

The three kinds are named after the cone whose response is shifted:

| Kind | The cone | How common |
|---|---|---|
| `.protanomaly` | long wavelength, nearest red | about 1 man in 100 |
| `.deuteranomaly` | middle wavelength | the most common kind |
| `.tritanomaly` | short wavelength, nearest blue | rare, and usually acquired |

Severity runs from 0 to 1. At 0 nothing changes. At 1 the cone is missing rather than shifted, which is dichromacy. `.protanopia`, `.deuteranopia` and `.tritanopia` are the three kinds at full severity. Any value between is anomalous trichromacy, which is the more common case.

```swift
ColorVision.deuteranopia            // the cone is gone
ColorVision.deuteranomaly(0.4)      // it is shifted, not gone
```

`Kind` is a `ParamOption`, so it can be a parameter in the live inspector, with a `Double` beside it for the severity.

### A whole sketch at once

`Filter.colorVision` applies the same simulation to everything you drew.

```swift
override func draw() {
    // ... your sketch ...
    postProcess(.colorVision(.deuteranopia))
}
```

Put it behind a `@Param` toggle, and you can switch the check on and off while you work. It costs one full-screen pass. The simulation belongs in linear light, which is what a layer already holds, so nothing is encoded on the way through.

`Palette` and `Ramp` have `simulated(_:)` too. Use those to draw a comparison rather than replace the whole frame.

### Whether a palette holds apart

`confusions(under:)` lists the pairs of colors that merge under a given kind.

```swift
for pair in myPalette.confusions(under: .deuteranopia) {
    print("colors \(pair.first) and \(pair.second) are \(pair.distance) apart")
}

if !myPalette.isColorblindSafe() { /* pick again */ }
```

`confusions()` with no argument checks all three kinds at full severity. Either way the worst pair comes first, so the first entry is the one to fix.

**Lightness is what keeps a pair apart.** The check measures the whole distance, lightness as well as hue, because a person judges both. To somebody with protanopia, red and green look alike in hue, but one is darker than the other, so the pair is still usable. Two colors of the same lightness that differ only in hue are the ones that merge. A red and a green matched for lightness measure 0.281 apart for average vision and 0.014 apart under the worst kind. Move them apart in lightness, and the same two hues stay 0.601 apart.

So the practical rule is to vary lightness as well as hue. Give a shape or a label to anything that color alone tells apart.

### A set that already works

```swift
fill(Palette.colorblindSafe[i])
```

`Palette.colorblindSafe` is the eight colors that Okabe and Ito published for color universal design. It is the usual choice when a piece needs categories anybody can follow. Its closest pair under the worst kind is 0.076 apart. A familiar six-color chart set falls to 0.007 under the same test.

### The tolerance

The default tolerance of 0.06 comes from measurement. It sits between the 0.076 and the 0.007 above, with room on either side. Pass your own tolerance if a piece needs a stricter or looser threshold.

### What the model is

The simulation uses the physiologically based model of Machado, Oliveira and Fernandes (2009). That model treats color vision deficiency as a shift in a cone's spectral absorption. A color is linearized, multiplied by a 3x3 matrix chosen by kind and severity, and encoded back. The published table gives a matrix at every 0.1 of severity. A value in between interpolates between its two neighbors, which is the approximation the model's authors describe.

The matrices weight the power of the display primaries, so they belong in linear light. Applying them to display values instead is a common mistake, and it gives a visibly different color.

A simulation is a working aid, not a report of somebody's experience. It shows where a design depends on a difference that disappears for a viewer with that kind of vision. It does not tell you what that person sees.

## Motion

Ollin animates by default. Some people do not want that motion, so macOS has a Reduce Motion setting they can turn on to say so.

```swift
let speed = prefersReducedMotion ? 0.1 : 1.0
```

Ollin reads the setting fresh, so turning it on reaches a running sketch on the next frame. A headless render always reads `false`, so an export is the same file on any machine.

Nothing changes on its own. You decide what less movement means, because only you know which movements matter to the piece and which are decoration. Common answers are to slow a drift, hold a value that was oscillating, drop a flash, or replace a camera move with a still framing.

## See also

- [Describing](../../Examples/Basic/Describing/Sketch.swift) - a sketch that says what it shows while it shows it
- [Text](../Drawing/Text.md#scripts) - complex-script shaping: Arabic, Devanagari, Thai, vertical layouts
- [Color](../Drawing/Color.md) - the color type, palettes, ramps and mixing
- [Effects](../Drawing/Effects.md) - the rest of the filter catalog
- [Parameters](./Parameters.md) - putting the kind on a parameter
