#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `L-systems`</sup>

---

## L-systems

An **L-system** (Lindenmayer system) grows a string by rewriting its symbols, then a **turtle** walks that string and draws it. String rewriting plus turtle interpretation is the whole trick, and a small rule set unfolds into enormous self-similar detail: plants, snowflakes, dragon curves, space-filling curves.

Three pieces define one: an **axiom** (the starting string), **production rules** (how each symbol rewrites, applied to *every* symbol at once each pass), and the number of **iterations** (rewrite passes). The turtle then reads the final string left to right.

```
  axiom:  F              rule:  F -> F+F-F-F+F           angle 90

  iter 0:  F
  iter 1:  F+F-F-F+F          every F becomes the rule,
  iter 2:  F+F-F-F+F +        the +/- carried along, so
           F+F-F-F+F -        the string grows ~5x a pass
           F+F-F-F+F - ...
```

The output is a set of open `[Contour]`s (the line-work), so it feeds straight into stroking, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export for the pen plotter. A run is a pure function of the grammar (and, for a stochastic one, the [`seed`](./Random.md#seed)), so the same seed always grows the same form.

### The turtle alphabet

```
  F, G   move forward one step, drawing a line
  f      move forward one step, pen up (a gap)
  +  -   turn left / right by the angle
  |      turn around (180 degrees)
  [  ]   push / pop the turtle's position and heading  (the branch mechanism)
  X, Y   draw nothing; they only steer the rewriting
```

The `[` / `]` stack is what makes plants possible: `[` remembers where you are, `]` teleports you back, so a branch can sprout and the turtle returns to the trunk to keep going.

### Contents

- [drawLSystem / lSystem](#draw)
- [Presets](#presets)
- [Building one by hand](#build)
- [Stochastic systems](#stochastic)
- [Standalone (outside a sketch)](#standalone)

<a name="draw"></a>

#### drawLSystem / lSystem

```swift
drawLSystem(_ system: LSystem, iterations: Int,
            in bounds: Rectangle? = nil, padding: Double = 60)

lSystem(_ system: LSystem, iterations: Int,
        in bounds: Rectangle? = nil, padding: Double = 60) -> [Contour]
```

`drawLSystem` strokes an L-system with the current `stroke`; `lSystem` returns its `[Contour]` line-work for you to color, transform, or feed onward. Both **scale and center the result to fill `bounds`** (the whole canvas by default) with a `padding` margin, so a preset fills the frame regardless of its iteration count. For a stochastic system they draw from the seeded `random`, so `seed(_:)` fixes the form.

```swift
seed(3)
stroke(.white); strokeWeight(2); strokeCap(.round); noFill()
drawLSystem(.plant, iterations: 5)
```

Because the line-work is a pure function of the grammar, compute it once and hold it (in a stored property) rather than every frame; see the `LSystem` example, which caches its whole catalog.

<a name="presets"></a>

#### Presets

Each preset is a ready-made `LSystem` with its canonical rules and angle. Pick an iteration count for the detail you want (curves take more passes than plants).

| Preset | What it is |
| --- | --- |
| `.kochCurve` | a line that grows a square bump on each segment |
| `.kochSnowflake` | three Koch curves closed into a star of frost |
| `.sierpinskiTriangle` | the Sierpinski gasket traced as one connected curve |
| `.sierpinskiArrowhead` | the same gasket drawn as a single unbroken path |
| `.dragonCurve` | the Heighway dragon, a folded space-filling curve |
| `.hilbertCurve` | a space-filling curve that visits every cell of a grid |
| `.gosperCurve` | the flowsnake, a hexagonal space-filling curve |
| `.levyCurve` | the Lévy C curve, nested right-angle bends |
| `.peanoCurve` | an early space-filling curve on a square grid |
| `.plant` | a fern-like plant that branches and droops |
| `.bush` | an upright bushy weed, the classic branching plant |
| `.tree` | a symmetric binary tree that forks at every tip |
| `.randomPlant` | a stochastic plant, a different form per seed |

```swift
// A contact sheet of presets, each fit to a grid cell:
let g = grid(columns: 4, rows: 4)
let presets: [(LSystem, Int)] = [(.dragonCurve, 12), (.hilbertCurve, 5), (.plant, 5), (.tree, 4)]
for (i, (system, iters)) in presets.enumerated() {
    drawLSystem(system, iterations: iters, in: g.cells[i].frame, padding: 10)
}
```

<a name="build"></a>

#### Building one by hand

```swift
LSystem(axiom: String, rules: [Character: String], angle: Double)   // angle in degrees
```

An `LSystem` is a value you build from an axiom, a production per symbol, and the turn angle (in degrees). A symbol with no rule is left unchanged, so control symbols like `X` fall through.

```swift
let koch = LSystem(axiom: "F", rules: ["F": "F+F-F-F+F"], angle: 90)
for c in lSystem(koch, iterations: 4) { drawPolyline(c.points) }

// A plant uses X to steer the rewriting while F draws and [ ] branch:
let fern = LSystem(axiom: "X", rules: ["X": "F+[[X]-X]-F[-FX]+X", "F": "FF"], angle: 25)
```

For full manual control (an explicit step, start point, and heading, with no fit), call the value's own `contours(iterations:step:start:heading:)`.

<a name="stochastic"></a>

#### Stochastic systems

Give a symbol *several* productions and one is chosen at random each time it rewrites, so every run varies while staying reproducible for a given seed. This is what turns a perfect fractal into a plant that looks grown rather than printed.

```swift
LSystem(axiom: String, choices: [Character: [String]], angle: Double)
```

```swift
seed(9)
let weed = LSystem(axiom: "X",
                   choices: ["X": ["F[+X]F[-X]+X", "F[-X]F[+X]-X", "F[+X][-X]FX"],
                             "F": ["FF"]],
                   angle: 22)
drawLSystem(weed, iterations: 6)
```

<a name="standalone"></a>

#### Standalone (outside a sketch)

The `Sketch` methods are sugar over the `LSystem` value type, which is self-contained. Its `expanded(iterations:)` gives the rewritten string, and `contours(iterations:step:start:heading:)` walks the turtle; a stochastic system takes a random source (`using rng:`), a deterministic one needs none.

```swift
let string = LSystem.dragonCurve.expanded(iterations: 6)          // "F+G+..."
let lines  = LSystem.plant.contours(iterations: 5, step: 8)        // [Contour]
```

---

Related: [`Truchet tiling`](../Drawing/Truchet.md) (another seed-driven line-work generator), [`Geometry`](../Drawing/Geometry.md) (the `Contour` type and the shape booleans the output feeds), [`Random`](./Random.md) (the seed that drives a stochastic system).
