#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Random`</sup>

---

## Random

`random` is seedable and lives on the sketch, so two sketches never share hidden global state. By default the seed is entropy-based (an unseeded sketch differs each run); seed for a reproducible image. It's Ollin's own generator (SplitMix64), so a seed reproduces Ollin's output rather than p5's. The smooth, coherent counterpart is [Noise](../Generators/Noise.md).

### Contents

- [random](#random)
- [randomGaussian](#randomGaussian)
- [randomVector](#randomVector)
- [ring](#ring)
- [randomChoice](#randomChoice)
- [shuffled](#shuffled)
- [randomSeed](#randomSeed)
- [seed](#seed)

### Generators

<a name="random"></a>

#### random

```swift
random() -> Double
random(_ max: Double) -> Double
random(_ min: Double, _ max: Double) -> Double
```

A uniform random `Double`: in `0..<1`, in `0..<max`, or between `min` and `max` (order-independent).

```swift
let y = 400 + random(-100, 100)        // jitter around 400
if random() < 0.2 { /* runs about a fifth of the time */ }
```

One gotcha for seeded sketches: a zero-width range short-circuits, so `random(a, a)` returns `a` *without consuming a roll*. If a knob or an animated value scales a jitter amount that can reach exactly zero, write the jitter as a scaled unit roll, `random(-1, 1) * amount`, not `random(-amount, amount)`: the first always draws, so the seeded sequence (and the piece's whole pattern of later rolls) stays stable as `amount` crosses zero.

<a name="randomGaussian"></a>

#### randomGaussian

```swift
randomGaussian() -> Double
randomGaussian(mean: Double, deviation: Double) -> Double
```

A normally distributed random `Double` (Marsaglia polar method): standard normal, or with the given mean and standard deviation. Reads as more natural scatter than the flat spread of `random`. See the `Gaussian` example.

```
  Bell-curve scatter: samples cluster near the mean, thin out farther away.

            ▁▄█▄▁
          ▁▄█████▄▁          ~68% land within 1 deviation (d) of the mean
        ▁▄█████████▄▁        ~95% within 2 deviations
      ────┼────┼────┼────
         m−d   m   m+d
```

```swift
let x = randomGaussian(mean: width / 2, deviation: 80)  // clustered near the middle
drawCircle(x, height / 2, 4)
```

<a name="randomVector"></a>

#### randomVector

```swift
randomVector(in rect: Rectangle) -> Vector2
```

A random point inside `rect`, each coordinate uniform within its bounds.

```swift
let p = randomVector(in: Rectangle(x: 0, y: 0, width: width, height: height))
drawCircle(center: p, radius: 3)
```

<a name="ring"></a>

#### ring

```swift
ring(innerRadius: Double, outerRadius: Double) -> Vector2
```

A random point in the ring between the two radii, centered on the origin. Add a center to place it. See the `Ring` example.

```
  ring(innerRadius: r, outerRadius: R) gives a uniform random point whose
  distance from the origin O lands between r and R (a ring).

  By distance from O (a ray pointing outward):

     O ●────── r ──────○════════════○
                  inner edge     outer edge (R)

     a point lands on the ═══ band: farther than r, out to R.

  As a ring centered on O:
        ___________
      ╱   _______   ╲
     │   ╱       ╲   │      hole = closer than r        (no points)
     │  │    O    │  │      band = between the circles   (points here)
      ╲   ╲_____╱   ╱
        ‾‾‾‾‾‾‾‾‾‾‾

   add a center to place it:  center + ring(innerRadius: r, outerRadius: R)
```

```swift
let center = Vector2(width / 2, height / 2)
let p = center + ring(innerRadius: 50, outerRadius: 100)
drawCircle(center: p, radius: 3)
```

### Choices

<a name="randomChoice"></a>

#### randomChoice

```swift
randomChoice<T>(_ choices: [T]) -> T
randomChoice<T>(_ choices: [T], weights: [Double]) -> T
```

A random element of `choices`: each equally likely, or biased by `weights`. The everyday palette pick, without indexing arithmetic. Weights are one per choice, non-negative, in any scale (they need not sum to 1); a choice weighted 0 is never picked. `choices` must not be empty. Seeded like everything `random`, so `randomSeed` makes the picks reproducible.

```swift
fill(randomChoice(palette))                            // any of them
fill(randomChoice(palette, weights: [6, 3, 1]))        // a dominant, a support, a spice
let move = randomChoice(["up", "down", "hold"], weights: [1, 1, 4])
```

<a name="shuffled"></a>

#### shuffled

```swift
shuffled<T>(_ array: [T]) -> [T]
```

The elements of `array` in a random order, drawn from the sketch's seeded generator, so a seeded shuffle reproduces run to run. (An array's own `shuffled()` rolls the system's dice instead and differs every run.)

```swift
randomSeed(9)
let order = shuffled(palette)   // the same reordering every run
```

### Seeding

<a name="randomSeed"></a>

#### randomSeed

```swift
randomSeed(_ seed: Int)
```

Seed the generator behind `random*` for reproducible runs. The same seed yields the same sequence. To reseed `noise` as well, see [`seed`](#seed).

```swift
randomSeed(42)   // same scatter every run
```

<a name="seed"></a>

#### seed

```swift
seed(_ seed: Int)
```

Seed *both* `random` and `noise` from one value, locking the whole sketch's randomness so it reproduces exactly, so reach for this when one seed should fully determine a piece. Use `randomSeed` or [`noiseSeed`](../Generators/Noise.md#noiseSeed) to reseed only one.

```swift
seed(7)   // random and noise both reproducible
```

This is also what sets the sketch's `variation`, the seed the run grew from. Every sketch is born on one (rolled fresh unless you call `seed`), reads it back as `variation`, records it in every export's recipe, and can be walked through it from the inspector's Variation card or rendered at any seed with `--seed N`. See [Variations](../Core/Variations.md).

```swift
override func draw() {
    drawCaption("Variation \(variation)")
}
```
