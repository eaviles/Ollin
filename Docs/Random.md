#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Random`</sup>

---

## Random

`random` is seedable and lives on the sketch, so two sketches never share hidden global state. By default the seed is entropy-based (an unseeded sketch differs each run); seed for a reproducible image. It's Ollin's own generator (SplitMix64), so a seed reproduces Ollin's output rather than p5's. The smooth, coherent counterpart is [Noise](./Noise.md).

### Contents

- [random](#random)
- [randomGaussian](#randomGaussian)
- [randomVector](#randomVector)
- [ring](#ring)
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

<a name="randomGaussian"></a>

#### randomGaussian

```swift
randomGaussian() -> Double
randomGaussian(mean: Double, deviation: Double) -> Double
```

A normally-distributed random `Double` (Marsaglia polar method): standard normal, or with the given mean and standard deviation. Reads as more natural scatter than the flat spread of `random`. See the `Gaussian` example.

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

A random point in the annulus between the two radii, centered on the origin. Add a center to place it. See the `Ring` example.

```
  ring(innerRadius: r, outerRadius: R) — a uniform random point whose
  distance from the origin O lands between r and R (a ring / annulus).

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

Seed *both* `random` and `noise` from one value, locking the whole sketch's randomness so it reproduces exactly; reach for this when one seed should fully determine a piece. Use `randomSeed` or [`noiseSeed`](./Noise.md#noiseSeed) to reseed only one.

```swift
seed(7)   // random and noise both reproducible
```
