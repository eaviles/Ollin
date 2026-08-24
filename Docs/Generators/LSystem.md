#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `L-systems`</sup>

---

## L-systems

An **L-system** (Lindenmayer system) grows a string by rewriting its symbols, then a **turtle** walks that string and draws it. String rewriting plus turtle interpretation is the whole trick, and a small rule set unfolds into enormous self-similar detail: plants, snowflakes, dragon curves, space-filling curves.

Three pieces define one: an **axiom** (the starting string), **production rules** (how each symbol rewrites, applied to *every* symbol at once each pass), and the number of **iterations** (rewrite passes). The turtle then reads the final string left to right.

<img src="../../Guide/Images/13-GrowingThings/LSystemExpansion.jpg" alt="Four panels of the same plant grammar drawn after one to four rounds of rewriting, growing from a bare stalk to a full fern, with the letter count under each panel rising from 18 to 1551" width="680">

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
- [Parametric L-systems](#parametric)

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

<a name="parametric"></a>

## Parametric L-systems

A plain grammar can only choose *which* symbols come next. Every length it draws is a whole multiple of one step. A **parametric** L-system carries the numbers themselves. Its symbols are modules like `A(1.5)` or `F(x, t)`, and its rules do arithmetic on them.

Three things follow that a symbolic grammar cannot state:

- a segment exactly three tenths as long as its parent,
- a bud that counts down a few passes before it opens,
- a trunk given its own width as well as its own length, so it tapers.

<img src="../../Guide/Images/13-GrowingThings/CarryingNumbers.jpg" alt="Three panels. A plain grammar tree of uniform segments, a parametric branch whose segments shrink by a ratio each fork, and a parametric tree drawn with a thick trunk tapering to fine twigs" width="680">

```swift
// A branch that halves at every fork and stops once it gets too short:
let system = ParametricLSystem(
    axiom: "A(1)",
    rules: ["A(s) : s > 0.02 -> F(s)[+A(s*0.5)][-A(s*0.5)]"],
    angle: 30)

stroke(.white); strokeWeight(2); noFill()
drawLSystem(system, iterations: 8)
```

`ParametricLSystem` is a separate type. The `Sketch` calls are overloads on the same names, so `lSystem(…)`, `lSystemMarks(…)`, and `drawLSystem(…)` each take either kind.

### Writing a rule

Each rule is one string, in the notation the literature uses:

```
  predecessor  :  condition  ->  successor  :  weight
       A(s)    :   s > 0.02  ->  F(s)[+A(s/2)]
```

- The **predecessor** is a module with *names* for its parameters. Those names are what the condition and the successor may use. A name may appear only once.
- The **condition** is optional. Write `*`, or leave it out, for a rule that always applies. A false condition is not an error. The rule does not apply, and the next one is tried.
- The **successor** is the modules that replace it, with an expression wherever a number goes.
- The **weight** is optional; see [Choosing among rules](#weights).

A module matches a rule only when the letter **and the number of parameters** agree. So `A`, `A(x)`, and `A(x, y)` are three different things. All three may live in one system:

```swift
ParametricLSystem(axiom: "A A(1) A(1,2)",
                  rules: ["A -> B", "A(x) -> C(x)", "A(x,y) -> D"],
                  angle: 90)
    .expanded(iterations: 1)     // "BC(1)D"
```

A module that matches no rule is left exactly as it is. That is why the turtle's own `+`, `-`, and `[` need no rules. It is also how a form settles. Once a condition stops holding, that bud stands still.

Write the arrow as `->`, `-->`, or `→`, whichever your source uses.

### Arithmetic

Expressions take `+ - * / %`, exponentiation `^`, comparison `< <= > >= == !=`, and `&& || !`. A comparison is worth `1` when it holds and `0` when it does not, so it can be used as a number. The functions are `sin cos tan asin acos atan floor ceil trunc abs exp log sqrt sign`, and `ran(x)` for a random number in `0 ..< x`.

**Two precedence rules are not the ones Swift uses.** Both come from the published table:

```
  2^3^2   is  2^(3^2)  =  512      exponentiation groups to the RIGHT
  2*3^2   is  2*(3^2)  =  18       and binds TIGHTER than multiplication
  -2^2    is  (-2)^2   =  4        unary minus binds tighter still
```

Trigonometry is in **radians**. Every angle the turtle turns is in **degrees**.

Numbers worth naming go in `constants`. Any rule may then use them:

```swift
ParametricLSystem(axiom: "A(1)",
                  rules: ["A(s) -> F(s)[+A(s/R)][-A(s/R)]"],
                  angle: 85,
                  constants: ["R": 1.456])
```

Comparing with `==` is exact, as floating point always is. Use a counter that steps down by whole numbers. Guard one rule with `d > 0` and the next with `d == 0`, which is what the published grammars do.

<a name="weights"></a>

### Choosing among rules

With no weights anywhere, **the first matching rule wins**. Rules are tried in the order you wrote them. A grammar can spell its cases as a list and let the earlier one take precedence.

Give rules a weight and one is picked at random instead:

```swift
ParametricLSystem(axiom: "A(1)",
                  rules: ["A(s) -> F(s)[+A(s*0.6)]A(s*0.8) : 2",
                          "A(s) -> F(s)[-A(s*0.6)]A(s*0.8) : 1"],
                  angle: 25)
```

The numbers are **weights, not probabilities**: they need not add up to one. They are shared out among whichever rules actually matched. A condition rules candidates out first.

A weight may be an expression in the module's own parameters, so the odds can change as a form grows.

Weighting is all or nothing per system. As soon as *any* rule carries a weight, every choice is made by weight rather than by order. Since conditions filter first, a grammar whose guards do not overlap behaves the same either way.

### The turtle

The turtle is the one on this page, with each symbol now able to carry its own number:

```
  F(a) G(a)   move forward a, drawing
  f(a) g(a)   move forward a, pen up
  +(a) -(a)   turn left / right by a degrees   (a may be negative)
  |           turn around
  [  ]        push / pop position, heading, and width
  !(w) #(w)   set the line width to w
  %           cut: abandon the rest of this branch
```

A symbol with no parameter falls back to the system's own `angle` and step. So `+` means `+(angle)`, and `F` means `F(1)`. **Extra parameters are ignored.** That is what lets `F(x, t)` draw `x` while `t` carries a counter the drawing never reads.

Ollin's turtle draws in the plane. It handles the published three-dimensional symbols only where those stay in it. A roll or a pitch of half a turn stays: `/(180)` keeps the drawing plane and swaps left for right. That is enough for the mirrored members of the tree family below.

Any other roll or pitch draws nothing, and neither do the polygon, color, and surface symbols. They are still carried through the rewriting untouched. Each says so once on the console, rather than flattening a solid model without a word.

### Width, and drawing it

`!(w)` sets the pen width. `[` and `]` save and restore it along with the pose, so a thin twig never thins the trunk carrying it. Ask for marks instead of contours and the widths come with them:

```swift
stroke(.white); strokeWeight(14)
for mark in lSystemMarks(.taperedTree(), iterations: 10) { drawMark(mark) }

// or, the same thing in one call:
drawLSystem(.taperedTree(), iterations: 10, tapered: true)
```

Widths come back as multiples of `strokeWeight`, scaled so the widest is exactly 1. So `strokeWeight` sets the thickness of the trunk. Width is carried at each point and interpolates between them. A branch therefore tapers smoothly rather than stepping at every segment.

Ordinary `lSystem(…)` returns `[Contour]` exactly as the symbolic form does. The line-work still feeds the shape booleans, hatching, and SVG export for the pen plotter.

### Presets

| Preset | What it is |
| --- | --- |
| `.triangleCurve` | one unbroken line that packs itself into a triangle, cut into four unequal pieces each pass |
| `.delayedTriangleCurve` | the same, with a counter holding the short pieces back so it fills evenly |
| `.selfSimilarBranch` | a binary branch, each child shorter than its parent by a fixed ratio |
| `.growingBranch` | the same proportions built the other way round, by lengthening every old segment |
| `.compoundLeaf` | a stalk making leaflets in facing pairs while every part goes on lengthening |
| `.alternatingLeaf` | the same, with leaflets on alternate sides |
| `.snowflake` | the snowflake curve written with thirds rather than whole steps |
| `.mesotonicBranch` | a form widest partway up, which a plain grammar provably cannot make |
| `.taperedTree(…)` | a tree given its own width as well as its own length; draw it `tapered` |
| `.randomBranch` | a weighted branch that leans differently every seed |

`taperedTree` is the one preset with knobs, because it is a whole family. Its defaults are the first row of a published table of nine trees. Here are three more worth typing out:

```swift
.taperedTree(contraction1: 0.65, contraction2: 0.71, angle1: 27, angle2: -68,
             width: 20, split: 0.53, exponent: 0.5, minimumLength: 1.7)   // 12 passes
.taperedTree(contraction1: 0.50, contraction2: 0.85, angle1: 25, angle2: -15,
             roll1: 180, width: 20, split: 0.45, exponent: 0.5, minimumLength: 0.5)  // 9
.taperedTree(contraction1: 0.92, contraction2: 0.37, angle1: 0, angle2: 60,
             roll1: 180, width: 2, split: 0.5, exponent: 0, minimumLength: 0.5)      // 15
```

`minimumLength` is the termination guard. Growth stops in a branch once it would be shorter than that. The form settles instead of running out of passes.

### Reading the word yourself

The turtle is not the only way out. `modules(iterations:)` hands back the grown word as its modules, so a sketch can draw something of its own for each one:

```swift
for module in system.modules(iterations: 6) where module.letter == "F" {
    let length = module.parameters.first ?? 1
    // ... place a leaf, a glyph, a mesh, whatever the length suggests
}
```

`expanded(iterations:)` gives the same word written back out as text. That is the quickest way to see what a rule is doing.

### When a rule will not read

A rule that cannot be parsed costs that rule and not the sketch. It is left out, and the modules it should have rewritten stand still. The reason is printed once, and it is also on the value:

```swift
let system = ParametricLSystem(axiom: "A(1)", rules: ["A(s) -> F(q)"], angle: 90)
system.errors     // ["rule 'A(s) -> F(q)': 'q' is not a parameter of this rule, a constant, or a function"]
```

---

Related: [`Marks`](../Drawing/Marks.md) (the `StrokeMark` a tapered system draws through), [`Truchet tiling`](../Drawing/Truchet.md) (another seed-driven line-work generator), [`Geometry`](../Drawing/Geometry.md) (the `Contour` type and the shape booleans the output feeds), [`Random`](./Random.md) (the seed that drives a stochastic system).
