#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Math`</sup>

---

## Math helpers

A small, growing set of the familiar creative-coding math functions, callable bare in `draw()`.

### Contents

- [map](#map)
- [dist](#dist)
- [lerp](#lerp)
- [Shaping scalars](#shaping): `clamp`, `fract`, `step`, `smoothstep`
- [Primes](#primes)
- [Constants](#constants)

<a name="map"></a>

### map

```swift
map(_ value: Double, _ start1: Double, _ stop1: Double, _ start2: Double, _ stop2: Double, clamp: Bool = false) -> Double
```

Linearly re-map `value` from one range onto another: the result sits at the same fraction along `start2...stop2` that `value` sat along `start1...stop1`. By default it extrapolates past the range; pass `clamp: true` to hold the result inside `start2...stop2`.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/03-MotionAndTime/MapAndLerp-dark.jpg">
  <img src="../../Guide/Images/03-MotionAndTime/MapAndLerp.jpg" alt="Top: a value carried between two number lines by its fraction along, map. Bottom: dots walking a segment from a to b as t runs 0 to 1, lerp" width="680">
</picture>

```swift
let r = map(sin(time), -1, 1, 60, 200)   // -1...1 → 60...200
drawCircle(width / 2, height / 2, r)      // a breathing circle
```

<a name="dist"></a>

### dist

```swift
dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double
```

The Euclidean distance between two points.

```swift
let d = dist(mouseX, mouseY, width / 2, height / 2)
let r = map(d, 0, 400, 80, 10, clamp: true) // large at the center, small toward the edges
drawCircle(width / 2, height / 2, r)
```

<a name="lerp"></a>

### lerp

```swift
lerp(_ a: Double, _ b: Double, _ t: Double) -> Double
```

The point `t` of the way from `a` to `b`. `t` is not clamped, so values outside `0...1` extrapolate past the ends. Reshape `t` with an [`Easing`](../Helpers/Animation.md) curve for non-linear motion.

```swift
let x = lerp(120, width - 120, Easing.easeInOut(progress))
```

A looping `t` driven by the sketch clock comes from [`loopProgress(over:)` and `pingPong(over:)`](../Helpers/Animation.md#loop).

<a name="shaping"></a>

### Shaping scalars

```swift
clamp(_ x: Double, _ minValue: Double, _ maxValue: Double) -> Double
fract(_ x: Double) -> Double
step(_ edge: Double, _ x: Double) -> Double
smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double
```

The bare shaping vocabulary, spelled with the same names and argument order as
the [shader library](../Shaders/ShaderLibrary.md), so an expression you write in
`draw()` carries verbatim into per-pixel shader code. The
[`Easing`](../Helpers/Animation.md) catalog stays the curve library; these are
its primitives.

- `clamp(x, lo, hi)` holds `x` within the range.
- `fract(x)` keeps the fractional part: `fract(2.75)` is `0.75`. Floor-based, so
  it stays continuous through negative values and wrapping a growing value never
  jumps.
- `step(edge, x)` is `0` below `edge` and `1` from it on: an `if` as a function,
  the hard switch for blinks and flips.
- `smoothstep(edge0, edge1, x)` is the smooth S-ramp between two edges: `0` at
  or below `edge0`, `1` at or above `edge1`, no corners in between. The edges
  cut a soft window out of any signal (reverse them to fade the other way):

```swift
let lit = smoothstep(0.3, 1.0, sin(angle * 3 - time))  // a soft traveling window
fill(Color.mix(.navy, .white, t: lit))
```

`smoothstep(0, 1, t)` is the plain `0...1` reshape, the same curve as
[`Easing.smoothstep`](../Helpers/Animation.md#catalog).

<a name="constants"></a>

### Primes

```swift
primes(upTo limit: Int) -> [Int]
isPrime(_ number: Int) -> Bool
```

Whole numbers as material. `primes(upTo:)` is the sieve of Eratosthenes and answers the whole run at once, which is what makes a field of thousands of numbers cheap. `isPrime` is the shorter way round for a single number. Negative numbers, zero, and one are not prime.

```swift
for p in primes(upTo: 500) { drawCircle(Double(p), height / 2, 3) }
```

The picture these are best known for is the [Ulam spiral](../Generators/UlamSpiral.md), which writes the numbers in a square spiral and marks the primes.

The other exact whole-number type is `Fraction`, a fraction in lowest terms with `mediant`, `isNeighbor`, and comparison by cross-multiplication. It lives with [Ford circles](../Generators/FordCircles.md) and `fareySequence`, the picture it was made for.

### Constants

`Double.tau` is the full turn (2π), which is what most angle work wants.

```swift
rotate(Double.tau / 6)   // a sixth of a turn
```

<img src="../../Guide/Images/B-JustEnoughMath/TauClock.jpg" alt="A dial with 0, tau over 4, tau over 2, and 3 tau over 4 marked around it, an accent wedge of tau over 8, and three mini dials showing tau over 12, 6, and 3" width="680">
