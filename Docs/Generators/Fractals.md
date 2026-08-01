#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Fractals`</sup>

---

## Fractals

Five ways a handful of numbers unfolds into infinite detail: **iterated function systems** (a few affine maps condensing onto a fern), **fractal flames** (the chaos game grown up, with nonlinear warps and a log-density display), **circle-inversion limit sets** (lace living in the gaps of a mirror arrangement), **Kleinian limit sets** (the fractal boundary curves of Möbius groups, traced in order), and **Schottky circle orbits** (circles paired off by Möbius maps, nesting forever). All five are deterministic: the point emitters run off a seedable generator, the Kleinian walk uses no randomness at all. The escape-time siblings (`.mandelbrot`, `.julia`) live on the GPU as [generators](../Drawing/Effects.md#generate).

```
  IFS                    flame                  inversion            Kleinian

  a few affine maps      affine + nonlinear     mirrors turn the     two complex traces
  played at random       warps, density         plane inside out     pick a Mobius group
  condense onto one      counted per pixel,     around each circle   whose boundary is
  shape                  shown through log      and lace remains     one fractal curve
```

### Contents

- [IFS (the chaos game)](#ifs)
- [FractalFlame](#flame)
- [inversionLimitSet](#inversion)
- [kleinianLimitSet](#kleinian)
- [schottkyCircles](#schottky)
- [fitted](#fitted)

<a name="ifs"></a>

#### IFS (the chaos game)

```swift
IFS(maps: [IFS.Map])                                   // x' = a·x + b·y + e, y' = c·x + d·y + f
system.points(count: Int, burnIn: Int = 20,
              using rng: inout some RandomNumberGenerator) -> [Vector2]
ifsPoints(_ system: IFS, count: Int) -> [Vector2]      // the sketch form, seeded by `variation`
```

An iterated function system is a small set of affine contractions with pick `weight`s; the chaos game applies a randomly chosen map over and over, and every orbit condenses onto the maps' common attractor. Three classics come bundled: `.barnsleyFern` (four maps, the famous coefficient table), `.sierpinskiTriangle`, and `.sierpinskiCarpet`.

```swift
let cloud = ifsPoints(.barnsleyFern, count: 60_000)
    .map { Vector2($0.x, -$0.y) }                     // the fern grows upward
fill(.white)
drawPoints(fitted(cloud, in: canvasRectangle.inset(by: 80)), size: 1.5)
```

Points return in the system's own coordinates; place them with [`fitted`](#fitted). Build your own system by writing each map's six numbers; weights steer how often each map is visited (the fern spends 85 percent of its time in the map that draws the main copy).

<a name="flame"></a>

#### FractalFlame

```swift
FractalFlame(transforms: [FractalFlame.Transform], colors: [Color], gamma: 2.2,
             vibrancy: 1, brightness: 1, window: Rectangle)
FractalFlame.random(using: &rng)                       // a few contractive maps, one variation each
flame.render(width: Int, height: Int, quality: Double = 60,
             supersample: Int = 1, using: &rng) -> Image
FractalFlame.Renderer(flame, width: Int, height: Int, seed: Int)   // the progressive form
```

The flame algorithm extends the chaos game three ways. Each transform follows its affine map with a weighted blend of **variations**, nonlinear plane-warps (`.sinusoidal`, `.spherical`, `.swirl`, `.horseshoe`, `.polar`, `.handkerchief`, `.heart`, `.disc`, `.spiral`, `.hyperbolic`, `.diamond`, `.ex`, `.julia`); the orbit carries a color coordinate that averages toward each visited transform's palette index, so color encodes *which maps* shaped each region (structural coloring); and the render accumulates a per-pixel density histogram displayed through a logarithm, which is why filaments, veils, and cores all stay visible at once. `gamma` (up to 4 for faint detail), `vibrancy` (1 keeps saturation under strong gamma), and `brightness` tune the development.

```swift
let renderer = FractalFlame.Renderer(flame, width: 560, height: 560, seed: variation)
// each frame:
renderer.accumulate(samples: 120_000)
drawImage(renderer.image(), in: canvasRectangle)
```

`quality` is chaos-game samples per output pixel: a few dozen previews, hundreds make a clean still. The `Renderer` is the live form: feed it a slice of samples per frame and the picture rises out of the noise. Both are deterministic for a fixed seed and sample count. `FractalFlame.random` rolls a new flame from contractive affines, one variation each; some rolls are duds, so reroll the seed until one sings.

<a name="inversion"></a>

#### inversionLimitSet

```swift
inverted(_ point: Vector2, in circle: Circle) -> Vector2
inversionLimitSet(of circles: [Circle], count: Int, burnIn: Int = 16,
                  using rng: inout some RandomNumberGenerator) -> [Vector2]
inversionLimitSet(of circles: [Circle], count: Int) -> [Vector2]   // seeded by `variation`
```

Inversion in a circle turns the plane inside out around it: centers map far away, the rim stays put, and `d · d' = r²` along every ray. Play the inversions of an arrangement against each other, choosing a random circle at each step but never the one just used (inversion is its own inverse, so that would undo the step), and the orbit converges onto the arrangement's limit set. Circles live in canvas coordinates, so the dust needs no fitting: it lands among the mirrors that made it.

```swift
let mirrors = /* a ring of tangent circles */
fill(Color(hex: 0xE8C97D, alpha: 0.6))
drawPoints(inversionLimitSet(of: mirrors, count: 30_000), size: 1.5)
```

Tangent rings give the classic gasket-like lace; separated circles give Cantor dust; overlapping ones tear the lace apart. The regions near tangency points fill slowly (inversions move points very little there), so give dense arrangements more `count`.

<a name="kleinian"></a>

#### kleinianLimitSet

```swift
kleinianLimitSet(ta: Vector2, tb: Vector2, epsilon: Double = 0.002,
                 maxDepth: Int = 60) -> Contour
kleinianLimitSet(_ preset: KleinianPreset, ...) -> Contour
```

Two complex traces (carried as `Vector2(re, im)`) pick a two-generator Möbius group by the classic recipe, and a depth-first walk of the group's reduced words traces its limit set as **one ordered closed curve**: subdivision stops when an arc drops under `epsilon` (in limit-set units, roughly ±2 across), so points come back evenly spaced along the curve, plotter-ready. No randomness at all.

```swift
let curve = kleinianLimitSet(.lace)
noFill()
drawPolyline(fitted(curve.points, in: canvasRectangle.inset(by: 100)), closed: true)
```

`KleinianPreset` names the landmarks: `.gasket` (the Apollonian gasket at traces `(2, 2)`), `.spiralPair`, `.lace`, `.doubleCusp` (the celebrated 1/15 cusp), `.cusp`, and `.symmetricCusps`. Custom traces just inside the quasi-Fuchsian region spiral tighter and tighter; outside it there is no curve to trace, and the polyline degenerates. Cusps converge slowly, so they reward a larger `maxDepth`.

<a name="schottky"></a>

#### schottkyCircles

```swift
schottkyCircles(pairing: [SchottkyPairing], minRadius: Double = 0.5,
                maxDepth: Int = 40) -> [Circle]
schottkyCircles(_ preset: SchottkyPreset, in bounds: Rectangle, ...) -> [Circle]
schottkyLimitSet(pairing: [SchottkyPairing], ...) -> [Vector2]
```

Take an even number of circles and pair them up. A `SchottkyPairing` is the Möbius map carrying the *outside* of one circle onto the *inside* of its partner, so applying it drops whatever it touches into the partner disc, smaller. Apply the pairings and their inverses in every order and the circles nest forever; what they close down onto is the group's limit set.

The output is real `Circle`s, not a flattened polyline, because a Möbius map carries a circle to a circle. `drawCircles` renders them analytically and the vector-export path writes true circle geometry, so the whole lace goes to a plotter as circles.

```swift
noFill()
drawCircles(schottkyCircles(.kissing, in: canvasRectangle.inset(by: 80)))
```

Circles come back in canvas coordinates, needing no fitting: the lace lands among the circles that made it. The walk is rng-free and adaptive, stopping a branch once its circle falls under `minRadius`, since everything below nests inside it. `schottkyLimitSet` keeps the centers of those stopped circles instead, each within `minRadius` of the limit set, and uses no randomness where the chaos game behind [`inversionLimitSet`](#inversion) does.

**Tangency is what fills the picture.** When a pairing's two circles *touch*, its generator holds the tangency point fixed and is parabolic: it barely contracts near that point, so the orbit keeps producing large circles for many generations and they crowd into a fan at the tangency. Pair circles across a ring instead and every generator contracts hard, leaving a thin dust. The difference is not subtle, and it is why there are two family builders:

```swift
schottkyCuspedPairs(in: Rectangle, spread: Double = 1,
                    lean: Double = 0, twist: Double = 0) -> [SchottkyPairing]
schottkyNecklace(pairs: Int, in: Rectangle,
                 tightness: Double = 0.9, twist: Double = 0) -> [SchottkyPairing]
```

`schottkyCuspedPairs` is the dense one: four circles in two touching pairs. `spread` slides the pairs apart (at `1` all four circles are mutually tangent and the limit set closes into a round circle with four cusps; above `1` the top and bottom tangencies open into gaps); `lean` swings each pair about its own tangency point, in opposite senses, which keeps both generators parabolic and so keeps the lace dense all the way along it; `twist` turns each pairing off its tangency-preserving setting, winding the limit set into a spiral but thinning it as it goes. `lean` is the dial to animate, `twist` the one that costs you density.

`SchottkyPreset` names the landmarks: `.kissing`, `.leaning`, `.cusped`, `.spiral`, and `.dust` (the thin cross-ring pairing, for contrast).

Discs should be disjoint, tangency allowed. Overlapping circles make the group non-discrete and the lace turns to mud; a hard ceiling on emitted circles keeps such an arrangement from running away rather than letting it exhaust memory.

<a name="fitted"></a>

#### fitted

```swift
fitted(_ points: [Vector2], in frame: Rectangle) -> [Vector2]
```

Uniformly scale and center a point cloud into a frame, keeping its aspect: the "fit the points, not the transform" rule as a helper, so a generated figure lands in place without `scale()` fattening its strokes. It serves any of the point emitters here, and walks, attractors, and harmonographs just as well.

---

Related: [`Random & noise`](./Random.md) (the seeded generators these draw from), [`Attractors`](../Drawing/Attractors.md) (the strange-attractor cousins), [`Tiling`](../Drawing/Tiling.md) (the Apollonian gasket by Descartes' theorem), [`Effects`](../Drawing/Effects.md#generate) (the GPU escape-time fractals), [`L-systems`](./LSystem.md) (growth by rewriting instead of iteration).
