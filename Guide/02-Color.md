#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 2</sup>

---

# 2. Color that works

<img src="Images/02-Color/ColorField.jpg" alt="A quilt of colored cells running diagonally from deep indigo through coral to warm cream, on a dark ground" width="560">

Color is where a sketch gets its voice, and it's also where beginners lose the most time: mixes that turn to mud, palettes that fight each other, colors that read brighter or darker than their numbers say. This chapter is the toolbox that avoids all of that. You'll learn the ways to name a color, how to think in hue, mixing that trusts your eye instead of the machine's arithmetic, palettes and ramps as kits you carry, and gradients as paint. It ends in the poster above, which redraws itself as a fresh variation on every click.

Everything here builds on [Chapter 1](01-HelloOllin.md); keep working the same way, one file under `OllinLive`, saving as you go.

## Naming a color

You've been writing `Color(hex: 0x2B2B2B)` since your first sketch. Here is the full menu:

```swift
fill(.coral)                                   // the CSS named set
fill(Color(hex: 0x5E60CE))                     // six hex digits, straight from a color picker
fill(Color(hex: 0xE4572E, alpha: 0.5))         // alpha is its own parameter
fill(Color(white: 0.15))                       // a quick gray
fill(Color(red: 0.95, green: 0.45, blue: 0.25))
```

The named constants cover the essentials (`.white`, `.black`, `.red`, ...) plus the standard CSS list, so `.coral`, `.teal`, `.crimson`, and `.lavender` all read like what they are. The integer hex form is the everyday workhorse: any color picker gives you those six digits. Go back to `FirstCircle.swift` and try a few of these in its `fill` line; this chapter is best read with a sketch open.

Colors can also arrive as *strings*, `Color(hex: "#ff0066")`, which matters once a color comes from somewhere else (a file, a website's palette). Strings can be malformed, so this form can fail, and Swift makes that visible:

> **Swift note.** `Color(hex: String)` returns an *optional*: a `Color?` that is either a color or nothing. Swift won't let you use it until you say what happens in the nothing case: `if let c = Color(hex: text) { fill(c) }` runs only when it parsed, and `Color(hex: "#ff0066")!` (the `!`) means "I promise this literal is well formed", crashing if you're wrong. You'll meet optionals again; this is the pattern.

## Thinking in hue

RGB is how the machine stores color: three amounts of light. It's good for storing, but hard to choose with: nobody thinks "a little less green" when they want a warmer orange. The painter's version is HSB: pick the hue on a wheel, then decide how vivid (saturation) and how bright (brightness):

<img src="Images/02-Color/HueWheels.jpg" alt="Left: RGB as three component bars adding up to an orange. Right: the HSB hue wheel with saturation and brightness sweeps" width="680">

```swift
fill(Color(hue: 0.07, saturation: 0.85, brightness: 0.95))   // a warm orange
```

All three run 0 to 1, and hue *wraps*: 1.2 means the same as 0.2, a full turn plus a bit. That makes hue safe to drive with `time` directly, no bookkeeping. Try it on Chapter 1's swinging circle (`FirstMotion.swift`), replacing its `fill` line:

```swift
fill(Color(hue: time * 0.1, saturation: 0.8, brightness: 0.95))
```

The circle now cycles the whole rainbow every ten seconds while it swings. One value in, continuous color out; this move alone powers a lot of generative color.

## Mixing you can trust

Here's the trap every beginner falls into. Take a blue and a yellow, average their RGB numbers to get the halfway color, and you get... mud. Averaging the machine's storage format says nothing about what the *eye* considers halfway:

<img src="Images/02-Color/MixingSpaces.jpg" alt="Three rows mixing the same blue and yellow: the RGB row passes through muddy olive, the HSB row detours through bright green, the OKLab row stays even" width="680">

Ollin gives you mixing as one call, with the space as a choice:

```swift
Color.mix(blue, yellow, t: 0.5)              // OKLab, the default
Color.mix(blue, yellow, t: 0.5, in: .rgb)    // the muddy one, when you want it
Color.mix(blue, yellow, t: 0.5, in: .hsb)    // walks the hue wheel between them
```

`t` is "how far along": 0 is the first color, 1 the second, 0.5 halfway. The default space, **OKLab**, is a way of arranging color's numbers so that equal moves *look* equal; a step in it changes the appearance by about the same amount wherever you are. Blue and yellow are opposites, so their midpoint is still a neutral, but it's an even, steady neutral with no lurch in brightness and no accidental detours through other hues. That's the whole idea. You don't need the math (there isn't any in this guide): just mix in OKLab unless you have a reason not to.

Try it live on the swinging circle:

```swift
fill(Color.mix(Color(hex: 0x2050C8), Color(hex: 0xFFC800), t: sin(time) * 0.5 + 0.5))
```

The `sin(time) * 0.5 + 0.5` squeezes the pendulum's −1...1 swing into `t`'s 0...1, so the circle breathes between the two colors. (That squeeze move is worth remembering; Chapter 3 turns it into a proper tool.)

The same perceptual model comes in two more shapes worth knowing about. **OKLCH** turns OKLab into dials (lightness, chroma, hue), so nudging a hue leaves lightness alone; `.oklch` mixing holds a color's identity while it arcs between hues. And **OKHSL** guarantees everything you ask for is displayable, which makes it the space for *generated* color. This chapter's favorite trick with it: hues that genuinely match in weight.

```swift
for i in 0..<12 {
    fill(Color(OKHSL(h: Double(i) / 12, s: 0.9, l: 0.65)))
    drawCircle(90 + Double(i) * 82, height / 2, 32)
}
```

Twelve different hues, and none of them shouts over the others, because they truly share a lightness. Do the same with `Color(hue:...)` and the yellow will glow while the blue turns heavy and dark.

## Kits you carry: Palette and Ramp

Individual colors get you started; finished pieces usually run on a *kit* chosen once. Ollin has two, plus two ready-made variants:

<img src="Images/02-Color/PaletteShelf.jpg" alt="Five rows: the set2 palette swatches, a triadic harmony, a smooth five-color ramp, the viridis colormap, and the sunset cosine palette" width="680">

A **`Palette`** is a discrete set. Indexing wraps in both directions, so any counter cycles it forever, and `color(at:)` slices 0...1 into equal bands:

```swift
let p = Palette.set2                  // eight ColorBrewer colors, ready to go
fill(p[i])                            // wraps: p[9] is p[1]
fill(p.color(at: t))                  // 0...1 quantized into eight bands
```

Eight classic sets ship built in (`.set1` through `.accent`), and the **harmony builders** grow a palette from one base color, computed in OKLCH so the companions keep the base's weight: `Palette.complementary(of: base)`, `.triadic(of: base)`, `.analogous(of: base)`, `.splitComplementary(of: base)`.

A **`Ramp`** is the continuous version: a gradient you sample. Give it colors (evenly spread) or explicit stops, and read it with `color(at:)`; blending runs through OKLab by default, so the in-betweens stay clean:

```swift
let dusk = Ramp([Color(hex: 0x14213D), Color(hex: 0x5E60CE),
                 Color(hex: 0xE56B6F), Color(hex: 0xFFB703), Color(hex: 0xFFF3E0)])
fill(dusk.color(at: t))
```

And two ramps come pre-made: **`Colormap`** (eight scientific maps like `.viridis` and `.magma`, built to keep perceived brightness marching evenly, the standard way to turn a number into legible color) and **`CosinePalette`** (seven cyclic palettes like `.sunset` and `.neon` from one small formula; they loop, so they're great fed with `time`). Both answer to the same `color(at:)`.

## Gradients as paint

A `Ramp` can also *be* the paint. Anywhere `fill` or `stroke` takes a color, it takes a gradient, laid over the canvas by one of three geometries:

<img src="Images/02-Color/GradientPaint.jpg" alt="Three panels: a rectangle with a vertical dusk gradient, a soft radial glow, and a ring stroked with a rainbow that sweeps around it" width="680">

```swift
fill(.linear(from: Vector2(0, 0), to: Vector2(0, height), dusk))   // along a line
fill(.radial(center: spot, radius: 260, glow))                     // out from a point
stroke(.alongPath(wheel))                                          // along the stroke itself
```

Each takes a `Ramp` or a plain color list. Alpha rides along, so a radial ramp that ends in a transparent color is an instant soft glow (the middle panel above). Coordinates live in drawing space, so gradients move with the shapes they paint. `.alongPath` runs start to end on a line; on a closed shape it sweeps once around, which is how the ring above became a color wheel.

## A recipe borrowed early: random

Chapter 1 borrowed `sin` from Chapter 3; this chapter's payoff borrows `random` from Chapter 4, and it needs only three lines of understanding. `random(-1, 1)` hands you a fresh unpredictable number in that range each call. On its own that's a problem for a piece that redraws sixty times a second, because every frame would roll new numbers and the canvas would boil. The fix is the third line: `randomSeed(n)` restarts the randomness from a fixed point, so the *same* seed always produces the *same* sequence of "random" numbers. Seed at the top of `draw()` and every frame makes identical choices; change the seed and you get a brand-new, equally coherent variation. Chapter 4 is the whole story; this is enough for now.

## The payoff: a color field poster

Now the poster. One ramp, a quilt of cells, and three ideas layered on top: each cell samples the ramp by its *diagonal position* (top-left is 0, bottom-right is 1), seeded randomness jitters every sample so the field reads organic instead of mechanical, and a slow `sin` shimmer keeps it alive. Make `MySketches/ColorField.swift`:

```swift
import Ollin

final class ColorField: Sketch {
    @Param("Columns", 4...28) var columns = 14
    @Param("Jitter", 0...1) var jitter = 0.4

    var fieldSeed = 7

    let ramp = Ramp([
        Color(hex: 0x14213D), Color(hex: 0x5E60CE),
        Color(hex: 0xE56B6F), Color(hex: 0xFFB703), Color(hex: 0xFFF3E0),
    ])

    override func draw() {
        randomSeed(fieldSeed)
        background(Color(hex: 0x0E1116))
        noStroke()
        let margin = 70.0, gutter = 7.0
        let cell = (width - margin * 2 - gutter * Double(columns - 1)) / Double(columns)
        for c in 0..<columns {
            for r in 0..<columns {
                let x = margin + Double(c) * (cell + gutter)
                let y = margin + Double(r) * (cell + gutter)
                let diagonal = Double(c + r) / Double(columns * 2 - 2)
                let t = diagonal
                    + random(-0.5, 0.5) * jitter * 0.5
                    + sin(time * 0.4 + diagonal * 3) * 0.05
                fill(ramp.color(at: t))
                drawRect(x, y, cell, cell)
            }
        }
    }

    override func mousePressed() {
        fieldSeed += 1
    }
}
```

Run it and walk the interesting lines:

- `randomSeed(fieldSeed)` runs at the top of every frame, so all the `random(-0.5, 0.5)` calls that follow roll the same numbers each time and the quilt holds still. Click the canvas: `mousePressed()` bumps the seed, and the next frame rolls an entirely new set of jitters. Same poster, new variation, as many as you can click.
- Two loops, one inside the other, visit every column and row; `diagonal` turns the cell's position into the ramp's 0...1.
- The `t` line is the whole aesthetic: position, plus seeded jitter (scaled by the knob), plus a slow shimmer. Comment out one term at a time and watch what each contributes; with jitter at zero it's a clean mechanical gradient, which is also a look worth keeping.
- The knobs do a lot here. `Columns` changes the piece's whole character (chunky at 5, woven at 28), and `Jitter` runs it from formal to painterly.

> **Swift note.** `var fieldSeed = 7` is a *property*, declared on the class rather than inside `draw()`, and that's what lets it survive between frames; a `let` or `var` inside `draw()` is born and dies with each frame. `mousePressed()` is another function Ollin calls for you, once per click. And a loop inside a loop is just that: for every column, visit every row.

Directions worth a try before Chapter 3:

- Swap the ramp for `Colormap.viridis` or `CosinePalette.sunset` (both answer `color(at:)`, so it's a one-line change).
- Make the cells circles, or shrink each one by a little `random(0, cell * 0.3)` for a hand-placed feel.
- Replace the flat background with a `.linear` gradient of the ramp's two end colors.
- Build the ramp from a harmony instead: `Palette.analogous(of: .coral, count: 5).ramp()`.

## Where this comes from

The OKLab family (OKLab, OKLCH, OKHSL) is the work of Björn Ottosson, published openly in 2020 and now part of the CSS color standard; it's why "mix in OKLab" is advice you'll meet across modern tools. The built-in qualitative palettes are Cynthia Brewer's ColorBrewer sets, designed for map readability and beloved far beyond maps. The colormaps come from the scientific-visualization world: viridis and friends from matplotlib (Stéfan van der Walt and Nathaniel Smith), turbo from Google. The cosine palette formula is Inigo Quilez's, a name that will keep coming up in this guide. Full credits live in the project's [attribution notes](../ATTRIBUTION.md#color).

## Go deeper

- [Color](../Docs/Drawing/Color.md): the complete reference, including color temperature (`Color(kelvin:)`) and the string-hex grammar.
- Worked examples, all in [`Examples/Color/`](../Examples/Color/): `Mixing` (the five spaces side by side), `Harmonies`, `Swatchbook`, `Palettes`, `Colormaps`, `HSBWheel`, and `Gradients`.
- [Drawing](../Docs/Drawing/Drawing.md): every place a `Paint` can go.

---

[Contents](README.md#contents) · Previous: [Chapter 1, Hello, Ollin](01-HelloOllin.md) · Next: [Chapter 3, Motion and time](03-MotionAndTime.md)
