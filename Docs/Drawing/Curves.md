#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Classic curves`</sup>

---

## Classic curves

These are the curve builders of the generative-art canon, and each one is a **pure closed form**. You give them numbers and get geometry back. They return ordinary values (`[Vector2]` points or a `Contour`), so everything downstream already works: `drawPolyline` and `drawShape`, the [shape booleans](./Geometry.md#shape-booleans), [Chaikin smoothing](#smoothing), hatching, and [SVG export](../Output/Export.md) for the pen plotter. None of them touch `random` or `noise`, so the same arguments always produce the same curve, a fixed frame reproduces, and exports are recipe-safe.

```swift
drawPolyline(rose(n: 5, radius: 300).points, closed: true)
drawPolyline(hypotrochoid(ring: 84, wheel: 33, pen: 26).points, closed: true)
for (i, p) in phyllotaxis(count: 600, spacing: 9).enumerated() {
    drawCircle(p.x, p.y, 2 + Double(i) * 0.008)
}
```

(The space-filling curves, Hilbert, Peano, Gosper, and the dragon, live with the [L-systems](../Generators/LSystem.md) as built-in presets. The related drawing machine for arbitrary outlines is [Fourier epicycles](./Epicycles.md). The curve written as a bend rather than a position, which is what rounds a corner so that the *turning* is smooth and not just the outline, is the [clothoid](./Clothoid.md).)

### Contents

- [Phyllotaxis: the sunflower scatter](#phyllotaxis)
- [Lissajous figures](#lissajous)
- [Rose curves](#rose)
- [Superellipse: the squircle family](#superellipse)
- [Supershape: the superformula](#supershape)
- [Spirograph: hypotrochoids and epitrochoids](#spirograph)
- [Guilloche: the rose engine](#guilloche)
- [The harmonograph](#harmonograph)
- [Chaikin smoothing](#smoothing)

<a name="phyllotaxis"></a>

#### Phyllotaxis: the sunflower scatter

```swift
phyllotaxis(count: Int, spacing: Double, angle: Double = .goldenAngle) -> [Vector2]
```

This is Vogel's model of the sunflower seed-head. Point `i` sits `i * angle` around and `spacing * sqrt(i)` out from the center, so every new seed lands in the gap the earlier ones left and the disk stays evenly filled at any count. The default `angle` is `Double.goldenAngle` (`pi * (3 - sqrt(5))`, about 137.5°), the "most irrational" slice of a turn, which is exactly why the spacing works. Nudge it a few hundredths of a degree and the even scatter collapses into spokes, itself a classic study.

The points are centered on the origin (place them with `translate`), and the array index is the seed's age, oldest at the center, which is the natural handle for size and color ramps. Example: `Patterns/Phyllotaxis`. (A pixel-field sibling lives in the effect generators as `Generator.phyllotaxis`.)

<a name="lissajous"></a>

#### Lissajous figures

```swift
lissajous(a: Int, b: Int, phase: Double = .pi / 2,
          width: Double, height: Double? = nil, samples: Int = 512) -> Contour
```

This is the curve two sine waves make when they meet, a point swinging side to side `a` times while it bobs up and down `b` times. Equal frequencies give a circle that collapses toward a line as `phase` heads to `0`, while unequal ones weave. `width` and `height` are the figure's full extents, `height` defaulting to `width`, and the returned contour is closed, centered on the origin, and exactly one period long. Shared factors cancel (`a: 2, b: 4` is the same curve as `a: 1, b: 2`).

Animate `phase` and a figure rolls through its whole family. A grid of them, column frequency against row frequency, is the classic Lissajous table. Example: `Motion/Lissajous`.

<a name="rose"></a>

#### Rose curves

```swift
rose(n: Int, d: Int = 1, radius: Double, samples: Int? = nil) -> Contour
```

Petals from one polar equation, `r = radius * cos(k * theta)` with `k = n / d`. With the default `d: 1`, an odd `n` draws `n` petals and an even `n` draws `2n`, while a fractional `k` (say `n: 7, d: 3`) interleaves the petals into woven, open stars. The sampling covers exactly the span that closes the curve once (the span depends on the parity of `n * d`), so there is no retraced doubling in the geometry, and what you plot is what exists. Leave `samples` nil and the density scales with that span.

The contour starts at `(radius, 0)` and is centered on the origin. A rose has as many symmetry steps as petals, so rotating by one petal per loop makes a seamless lap. Example: `Patterns/Roses`.

<a name="superellipse"></a>

#### Superellipse: the squircle family

```swift
superellipse(width: Double, height: Double? = nil, n: Double = 4,
             samples: Int = 256) -> Contour
```

The Lamé curve `|x/a|^n + |y/b|^n = 1`: the whole family between diamond and rectangle in one exponent. `n: 2` is the ellipse. `n: 4` is the classic squircle, the shape of app icons and mid-century tabletops. Higher values square up toward the bounding rectangle. `n: 1` is the diamond, and lower values pinch inward to a four-point star (`n: 2/3` is the astroid). `width` and `height` are the full extents, `height` defaulting to `width`.

The contour is closed and centered on the origin. The sampling is uniform in the sweep angle, so at extreme exponents follow with [`resampled(spacing:)`](./Geometry.md) for a plotter-even outline. Animate `n` and a mark breathes between round and square. Example: `Shapes/Superellipse`.

<a name="supershape"></a>

#### Supershape: the superformula

```swift
supershape(radius: Double, m: Double = 7, n1: Double = 0.2,
           n2: Double = 1.7, n3: Double = 1.7, samples: Int = 512) -> Contour
```

The 2D superformula, the same one behind [`Mesh.supershape`](../3D/3D.md): `r(θ) = (|cos(mθ/4)|^n2 + |sin(mθ/4)|^n3)^(-1/n1)`. A handful of parameters sweeps through star, flower, gear, and organic forms. `m` sets the symmetry (the lobe count), and `n1`/`n2`/`n3` shape the lobes: `m: 0, n*: 1` is a circle, small `n1` sharpens, unequal `n2`/`n3` leans the petals. It generalizes the [rose](#rose) and the [superellipse](#superellipse) into one dial-covered surface.

The contour is closed and centered on the origin. **Keep `m` a whole number**: the formula only closes in one turn for integer `m`, and a fractional `m` leaves a visible seam where the end meets the start. The formula's own radius tops out at 1 on the symmetry axes and is clamped to 4 between them (the same guard the mesh uses), so `radius` stays an honest size. Great driven by `time` or a `@Param`. Example: `Shapes/Supershape`.

<a name="spirograph"></a>

#### Spirograph: hypotrochoids and epitrochoids

```swift
hypotrochoid(ring: Int, wheel: Int, pen: Double, samples: Int? = nil) -> Contour
epitrochoid(ring: Int, wheel: Int, pen: Double, samples: Int? = nil) -> Contour
```

These are the toy gear set. A `wheel`-radius gear rolls around a fixed `ring`-radius gear, inside it for the hypotrochoid, outside for the epitrochoid, with the pen `pen` units from the wheel's center. Integer radii stand in for the gears' teeth, which guarantees that the pen eventually lines back up with its start, and the sampling covers exactly the `wheel / gcd(ring, wheel)` laps that close the curve once. The pen distance sets the character: less than `wheel` rounds the lobes, equal gives cusps (the hypocycloid and epicycloid), more loops them over themselves.

Both return a closed, origin-centered contour. The finished figure repeats every `ring / gcd(ring, wheel)` lobes around the center, so spinning by one lobe per loop is seamless. Nested pen distances from one gear pair stack into the woven rosette every childhood knows; for the engraved, many-ring version of that idea, see [guilloche](#guilloche). Example: `Patterns/Spirograph`.

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

The engine-turned ornament of watch faces, banknotes, and certificates. The machine behind the look is a lathe whose cams rock the cutter as the piece turns. Each pass cuts one wavy ring, and the piece is turned a hair between passes. This traces the same recipe: `rings` concentric closed curves from `innerRadius` out to `outerRadius`, each one `r(θ) = base + Σ amplitude·sin(bumps·θ + phase)` over the stacked `rosettes`, with ring `k` rotated by `k · twist`. The creeping rotation is what weaves neighboring rings into the braided moiré.

Stack a coarse rosette and a fine one and the ripple rides the wave, the layered look the craft is known for. One rosette is common enough to have its own overload. The result is one closed `Contour` per ring, innermost first, centered on the origin, so the line-work strokes, hatches, and exports to SVG for a pen plotter. Keep `bumps` whole so every ring closes. Example: `Patterns/Guilloche`.

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

A harmonograph is the Victorian drawing machine whose pen hangs from swinging pendulums, each losing a little energy per swing. Every pendulum contributes one damped sine wave, the `x` list sums into the horizontal position and the `y` list into the vertical. Two pendulums per axis is the classic instrument, and one per axis draws damped [Lissajous figures](#lissajous).

The signature look comes from **near-unison detune**. Frequencies like `2` against `2.01` make the trace precess slowly while the damping reels each lap inside the last, weaving the nested web. You can read the machine two ways. `point(at:)` with a growing `t` performs the drawing live, pen and all, and `contour()` bakes the whole trace at once, by default through `settleTime`, when the slowest-decaying pendulum has shrunk to 1% of its starting swing. There is no randomness inside, so the same pendulums always draw the same figure. Roll the *parameters* from the sketch's seeded `random` and every [variation](../Core/Variations.md) commissions a new one. Example: `Motion/Harmonograph`.

<a name="smoothing"></a>

#### Chaikin smoothing

```swift
Contour.smoothed(iterations: Int = 2) -> Contour
Shape.smoothed(iterations: Int = 2) -> Shape
```

Chaikin's corner cutting rounds a path one pass at a time. Each pass replaces every corner with two points, a quarter and three quarters of the way along its adjoining segments. Two or three passes relax any jagged polyline into a flowing curve, and a few more converge toward a smooth spline. Each pass doubles the point count (`iterations` caps at 10), a closed contour rounds all the way around, and an **open contour keeps its exact endpoints**, so a smoothed connector still lands where it aimed. The `Shape` form smooths every contour and keeps the winding rule.

It pairs with everything that emits raw line-work: a random walk, [streamlines](../Generators/FlowField.md), [L-system](../Generators/LSystem.md) turtle paths, hand-placed zigzags. Example: `Shapes/CornerCutting`.

---

#### Where this comes from

These curves come from Vogel's phyllotaxis model, the classical Lissajous, rose, and trochoid parametric forms, Lamé's superellipse, Gielis's superformula, the rose engine's guilloche, the damped-pendulum harmonograph, and Chaikin's corner-cutting algorithm. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md) for the sources.

#### Go deeper

- [Geometry](./Geometry.md): `Vector2`, `Contour`, resampling, booleans, offsets
- [Fourier epicycles](./Epicycles.md): rebuild *any* closed outline from spinning circles
- [L-systems](../Generators/LSystem.md): the space-filling curves and branching grammars
- [Export](../Output/Export.md): SVG and PDF vector output, hatching for plotters
