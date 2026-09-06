#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Classic curves`</sup>

---

## Classic curves

These are the classic curve builders of generative art. Each one is a **pure function of its numbers**, so you pass numbers in and get geometry back. All of them are closed forms except the [spirolateral](#spirolateral), which is a walk. They return ordinary values, either `[Vector2]` points or a `Contour`, so everything downstream already works with them. That includes `drawPolyline` and `drawShape`, the [shape booleans](./Geometry.md#shape-booleans), [Chaikin smoothing](#smoothing), hatching, and [SVG export](../Output/Export.md) for the pen plotter. None of them read `random` or `noise`, so the same arguments always produce the same curve. That means a fixed frame renders the same way every time, and an export can be rebuilt from the same arguments.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/ClassicCurves-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/ClassicCurves.jpg" alt="Nine panels: a sunflower seed spiral, a woven Lissajous figure, a five-petal rose, a squircle holding a pinched four-point star, a looping spirograph curve, a decaying harmonograph tangle, a seven-lobed supershape star, a braided guilloche rosette of wavy rings, and a rough polygon shown beside its smoothed version" width="680">
</picture>

```swift
drawPolyline(rose(n: 5, radius: 300).points, closed: true)
drawPolyline(hypotrochoid(ring: 84, wheel: 33, pen: 26).points, closed: true)
for (i, p) in phyllotaxis(count: 600, spacing: 9).enumerated() {
    drawCircle(p.x, p.y, 2 + Double(i) * 0.008)
}
```

The space-filling curves (Hilbert, Peano, Gosper, and the dragon) live with the [L-systems](../Generators/LSystem.md) as built-in presets. The related drawing machine for any outline is [Fourier epicycles](./Epicycles.md). The [clothoid](./Clothoid.md) is the curve written as a bend rather than a position. That is what rounds a corner so that the *turning* is smooth, not only the outline.

### Contents

- [Phyllotaxis: the sunflower scatter](#phyllotaxis)
- [Lissajous figures](#lissajous)
- [Rose curves](#rose)
- [Superellipse: the squircle family](#superellipse)
- [Supershape: the superformula](#supershape)
- [Spirograph: hypotrochoids and epitrochoids](#spirograph)
- [Guilloche: the rose engine](#guilloche)
- [The harmonograph](#harmonograph)
- [Spirolaterals: a walk that comes home](#spirolateral)
- [Chaikin smoothing](#smoothing)

<a name="phyllotaxis"></a>

#### Phyllotaxis: the sunflower scatter

```swift
phyllotaxis(count: Int, spacing: Double, angle: Double = .goldenAngle) -> [Vector2]
```

This is Vogel's model of the sunflower seed head. Point `i` sits `i * angle` around the center and `spacing * sqrt(i)` out from it. So every new seed lands in the gap the earlier ones left, and the disk stays evenly filled at any count. The default `angle` is `Double.goldenAngle` (`pi * (3 - sqrt(5))`, about 137.5°). That is the "most irrational" slice of a turn, which is why the spacing works. Move it by a few hundredths of a degree and the even scatter collapses into spokes. That spoked pattern is itself a classic study.

The points are centered on the origin, so place them with `translate`. The array index is the seed's age, with the oldest at the center, so it is the natural handle for size and color ramps. Example: `Patterns/Phyllotaxis`. A pixel-field version of the same pattern lives in the effect generators as `Generator.phyllotaxis`.

<a name="lissajous"></a>

#### Lissajous figures

```swift
lissajous(a: Int, b: Int, phase: Double = .pi / 2,
          width: Double, height: Double? = nil, samples: Int = 512) -> Contour
```

This is the curve two sine waves make together. A point swings side to side `a` times while it moves up and down `b` times. Equal frequencies give a circle, which collapses toward a line as `phase` goes to `0`, while unequal ones weave. `width` and `height` are the figure's full extents, and `height` defaults to `width`. The returned contour is closed, centered on the origin, and exactly one period long. Shared factors cancel, so `a: 2, b: 4` is the same curve as `a: 1, b: 2`.

Animate `phase` and the figure moves through its whole family. A grid of figures, with the column frequency against the row frequency, is the classic Lissajous table. Example: `Motion/Lissajous`.

<a name="rose"></a>

#### Rose curves

```swift
rose(n: Int, d: Int = 1, radius: Double, samples: Int? = nil) -> Contour
```

A rose curve draws petals from one polar equation, `r = radius * cos(k * theta)` with `k = n / d`. With the default `d: 1`, an odd `n` draws `n` petals and an even `n` draws `2n`. A fractional `k` (for example `n: 7, d: 3`) interleaves the petals into woven, open stars. The sampling covers exactly the span that closes the curve once, and that span depends on whether `n * d` is odd or even. So the geometry contains no retraced lines. Leave `samples` nil and the density scales with that span.

The contour starts at `(radius, 0)` and is centered on the origin. A rose has as many symmetry steps as petals, so rotating it by one petal per loop makes a seamless lap. Example: `Patterns/Roses`.

<a name="superellipse"></a>

#### Superellipse: the squircle family

```swift
superellipse(width: Double, height: Double? = nil, n: Double = 4,
             samples: Int = 256) -> Contour
```

This is the Lamé curve `|x/a|^n + |y/b|^n = 1`. One exponent, `n`, covers the whole family between diamond and rectangle. `n: 2` is the ellipse. `n: 4` is the classic squircle, the shape of app icons and mid-century tabletops. Higher values square up toward the bounding rectangle. `n: 1` is the diamond, and lower values pinch inward to a four-point star (`n: 2/3` is the astroid). `width` and `height` are the full extents, and `height` defaults to `width`.

The contour is closed and centered on the origin. The sampling is uniform in the sweep angle, so at extreme exponents the spacing along the outline is uneven. Follow with [`resampled(spacing:)`](./Geometry.md) to get an evenly spaced outline for a plotter. Animate `n` and the mark moves between round and square. Example: `Shapes/Superellipse`.

<a name="supershape"></a>

#### Supershape: the superformula

```swift
supershape(radius: Double, m: Double = 7, n1: Double = 0.2,
           n2: Double = 1.7, n3: Double = 1.7, samples: Int = 512) -> Contour
```

This is the 2D superformula, the same one behind [`Mesh.supershape`](../3D/3D.md): `r(θ) = (|cos(mθ/4)|^n2 + |sin(mθ/4)|^n3)^(-1/n1)`. A few parameters cover star, flower, gear, and organic forms. `m` sets the symmetry, which is the lobe count. `n1`/`n2`/`n3` shape the lobes: `m: 0, n*: 1` is a circle, a small `n1` sharpens them, and unequal `n2` and `n3` lean the petals. It generalizes the [rose](#rose) and the [superellipse](#superellipse) into one formula with a few controls.

The contour is closed and centered on the origin. **Keep `m` a whole number.** The formula closes in one turn only for an integer `m`. A fractional `m` leaves a visible seam where the end meets the start. The formula's own radius reaches at most 1 on the symmetry axes. Between them it is clamped to 4, the same guard the mesh uses. So `radius` stays a true size. Drive it from `time` or a `@Param`. Example: `Shapes/Supershape`.

<a name="spirograph"></a>

#### Spirograph: hypotrochoids and epitrochoids

```swift
hypotrochoid(ring: Int, wheel: Int, pen: Double, samples: Int? = nil) -> Contour
epitrochoid(ring: Int, wheel: Int, pen: Double, samples: Int? = nil) -> Contour
```

These are the toy gear set. A gear of radius `wheel` rolls around a fixed gear of radius `ring`. It rolls inside the ring for the hypotrochoid and outside it for the epitrochoid. The pen sits `pen` units from the wheel's center. Integer radii stand in for the gears' teeth, which guarantees that the pen eventually lines up with its start again. The sampling covers exactly the `wheel / gcd(ring, wheel)` laps that close the curve once. The pen distance sets the character of the curve. A distance less than `wheel` rounds the lobes. A distance equal to `wheel` gives cusps (the hypocycloid and epicycloid). A larger distance loops the lobes over themselves.

Both return a closed contour centered on the origin. The finished figure repeats every `ring / gcd(ring, wheel)` lobes around the center, so turning it by one lobe per loop is seamless. Several pen distances from one gear pair stack into the woven rosette the toy draws. For the engraved, many-ring version of that idea, see [guilloche](#guilloche). Example: `Patterns/Spirograph`.

<a name="guilloche"></a>

#### Guilloche: the rose engine

```swift
guilloche(rings: Int, innerRadius: Double, outerRadius: Double,
          rosettes: [Rosette], twist: Double = .pi / 90,
          samples: Int? = nil) -> [Contour]

guilloche(rings: Int, innerRadius: Double, outerRadius: Double,
          bumps: Int, amplitude: Double, twist: Double = .pi / 90,
          samples: Int? = nil) -> [Contour]

Rosette(bumps: Int, amplitude: Double, phase: Double = 0)
```

Guilloche is the engine-turned ornament of watch faces, banknotes, and certificates. The machine behind the look is a lathe whose cams rock the cutter as the piece turns. Each pass cuts one wavy ring, and the piece is turned a little between passes. This function traces the same recipe. It returns `rings` concentric closed curves from `innerRadius` out to `outerRadius`. Each one is `r(θ) = base + Σ amplitude·sin(bumps·θ + phase)` over the stacked `rosettes`, and ring `k` is rotated by `k · twist`. That small rotation is what weaves neighboring rings into the braided moiré.

Stack a coarse rosette and a fine one, and the fine ripple sits on the coarse wave. That is the layered look the craft is known for. One rosette is common enough to have its own overload. The result is one closed `Contour` per ring, innermost first, centered on the origin. So you can stroke the line-work, hatch it, and export it to SVG for a pen plotter. Keep `bumps` a whole number so every ring closes. Example: `Patterns/Guilloche`.

```swift
withState {
    translate(width / 2, height / 2)
    stroke(.white); strokeWeight(1); noFill()
    for ring in guilloche(rings: 36, innerRadius: 90, outerRadius: 320,
                          rosettes: [Rosette(bumps: 8, amplitude: 24),
                                     Rosette(bumps: 40, amplitude: 4)]) {
        drawPolyline(ring.points, closed: true)
    }
}
```

<a name="harmonograph"></a>

#### The harmonograph

```swift
struct Harmonograph {
    struct Pendulum {           // amplitude * sin(frequency * tau * t + phase) * exp(-damping * t)
        var amplitude: Double   // starting half-swing, canvas units
        var frequency: Double   // full swings per unit of time
        var phase: Double       // radians
        var damping: Double     // decay per unit of time; 0.01...0.05 is the classic range
    }
    var x: [Pendulum]           // summed into the horizontal position
    var y: [Pendulum]           // summed into the vertical

    func point(at t: Double) -> Vector2
    var settleTime: Double
    func contour(duration: Double? = nil, samples: Int? = nil) -> Contour
}
```

A harmonograph is the Victorian drawing machine whose pen hangs from swinging pendulums. Each pendulum loses a little energy per swing, and each one contributes one damped sine wave. The `x` list sums into the horizontal position and the `y` list into the vertical. Two pendulums per axis is the classic instrument, and one per axis draws damped [Lissajous figures](#lissajous).

The signature look comes from **near-unison detune**. Frequencies like `2` against `2.01` make the trace turn slowly. Meanwhile the damping draws each lap inside the last, which weaves the nested web. You can use the machine in two ways. `point(at:)` with a growing `t` draws the figure live, so you can show the pen as it moves. `contour()` computes the whole trace at once. By default it runs through `settleTime`, the moment when the slowest-decaying pendulum has shrunk to 1% of its starting swing. There is no randomness inside, so the same pendulums always draw the same figure. Take the *parameters* from the sketch's seeded `random` and every [variation](../Core/Variations.md) draws a new figure. Example: `Motion/Harmonograph`.

<a name="spirolateral"></a>

#### Spirolaterals: a walk that comes home

```swift
spirolateral(order: Int, turn: Double = .pi / 2, step: Double = 1,
             reversed: Set<Int> = [], repeats: Int? = nil,
             maxRepeats: Int = 360) -> Spirolateral

struct Spirolateral {
    var points: [Vector2]       // every corner, in the order it was walked
    var contour: Contour        // the same walk, closed when it comes home
    var run: Contour            // one run on its own
    var repeats: Int            // how many runs were walked
    var closingRepeats: Int?    // how many it takes to come home, nil if never
    var closes: Bool
    var netTurn: Double         // how far one run turns the walker
    var center: Vector2?        // the point the figure turns about
    var length: Double
}
```

Step one length, turn, step two lengths, turn again, and keep going up to `order` lengths. Then run the whole sequence again. That is the entire rule. The figures it makes are not obvious from it: pinwheels, square knots, and walks that leave and never return. Frank Odds named and studied them in 1973, and the same walk is a standard turtle-geometry exercise.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/Spirolaterals-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/Spirolaterals.jpg" alt="Three panels on paper. On the left an orange spiral of seven growing steps. In the middle the same orange run inside a black square knot made of four of them. On the right a walk of eight steps repeated three times, marching off toward the bottom right instead of closing" width="680">
</picture>

**Whether the walk closes follows from arithmetic.** One run turns the walker through `netTurn`. So run `m` is run 1 rotated by `m` times that angle. The runs close into a ring as soon as a whole number of them makes a whole number of turns. At the classic quarter turn that means `4 / gcd(order, 4)` runs. The one exception is an order that is a multiple of four. A run of that order comes back facing the way it set off, so every repeat lands further away in the same direction. The walk leaves the page. In that case `closes` reads false, `center` is nil, and the walk is drawn open.

`turn` has to be an exact fraction of a full turn for any of this to happen. An angle swept between two such fractions never closes, so `turn` is not a good value to animate. Animate the *order* instead, or the set of `reversed` steps. A reversed step turns the other way, which changes both the figure and the count.

```swift
let figure = spirolateral(order: 7, step: 26)
noFill(); stroke(.white); strokeWeight(2)
drawPolyline(fitted(figure.points, in: bounds.inset(by: 60)), closed: figure.closes)
```

Fit the *points*, as above, rather than calling `scale()`, because the transform would scale the stroke width with the figure. The whole figure is `run` turned about `center`, once per repeat. Draw the run in one color over the figure in another and the repeats become visible. Example: `Patterns/Spirolateral`.

<a name="smoothing"></a>

#### Chaikin smoothing

```swift
Contour.smoothed(iterations: Int = 2) -> Contour
Shape.smoothed(iterations: Int = 2) -> Shape
```

Chaikin's corner cutting rounds a path one pass at a time. Each pass replaces every corner with two points, a quarter and three quarters of the way along its adjoining segments. Two or three passes turn any jagged polyline into a flowing curve, and a few more converge toward a smooth spline. Each pass doubles the point count, and `iterations` caps at 10. A closed contour rounds all the way around. An **open contour keeps its exact endpoints**, so a smoothed connector still reaches the same two points. The `Shape` form smooths every contour and keeps the winding rule.

It pairs with anything that emits raw line-work: a random walk, [streamlines](../Generators/FlowField.md), [L-system](../Generators/LSystem.md) turtle paths, or hand-placed zigzags. Example: `Shapes/CornerCutting`.

---

#### Where this comes from

These curves come from Vogel's phyllotaxis model, the classical Lissajous, rose, and trochoid parametric forms, Lamé's superellipse, and Gielis's superformula. The rest come from the rose engine's guilloche, the damped-pendulum harmonograph, Odds's spirolaterals, and Chaikin's corner-cutting algorithm. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md) for the sources.

#### Go deeper

- [Geometry](./Geometry.md): `Vector2`, `Contour`, resampling, booleans, offsets
- [Fourier epicycles](./Epicycles.md): rebuild *any* closed outline from spinning circles
- [L-systems](../Generators/LSystem.md): the space-filling curves and branching grammars
- [Export](../Output/Export.md): SVG and PDF vector output, hatching for plotters
