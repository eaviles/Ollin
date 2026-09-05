#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Math`</sup>

---

## Math helpers

Ollin has a small and growing set of the familiar creative-coding math functions, and you call them bare in `draw()`.

### Contents

- [map](#map)
- [dist](#dist)
- [lerp](#lerp)
- [Shaping scalars](#shaping): `clamp`, `wrap`, `fract`, `step`, `smoothstep`, `unipolar`, `bipolar`
- [Dividing a whole](#dividing): `fractions`, `angles`
- [polar](#polar)
- [Primes](#primes)
- [Constants and angle units](#constants)

<a name="map"></a>

### map

```swift
map(_ value: Double, _ start1: Double, _ stop1: Double, _ start2: Double, _ stop2: Double, clamp: Bool = false) -> Double
```

Re-map `value` linearly from one range onto another. The result sits at the same fraction along `start2...stop2` that `value` sat along `start1...stop1`. By default the result extrapolates past the range. Pass `clamp: true` to hold it inside `start2...stop2`.

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

The point `t` of the way from `a` to `b`. `t` is not clamped, so a value outside `0...1` extrapolates past the ends. For non-linear motion, reshape `t` with an [`Easing`](../Helpers/Animation.md) curve.

```swift
let x = lerp(120, width - 120, Easing.easeInOut(progress))
```

For a `t` that loops with the sketch clock, use [`loopProgress(over:)` and `pingPong(over:)`](../Helpers/Animation.md#loop).

<a name="shaping"></a>

### Shaping scalars

```swift
clamp(_ x: Double, _ minValue: Double, _ maxValue: Double) -> Double
clamp<T: Comparable>(_ x: T, _ minValue: T, _ maxValue: T) -> T
clamp<T: Comparable>(_ x: T, to range: ClosedRange<T>) -> T
wrap(_ x: Double, _ minValue: Double, _ maxValue: Double) -> Double
fract(_ x: Double) -> Double
step(_ edge: Double, _ x: Double) -> Double
smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double
unipolar(_ x: Double) -> Double
bipolar(_ x: Double) -> Double
```

These are the basic shaping functions. They use the same names and argument
order as the [shader library](../Shaders/ShaderLibrary.md), so an expression you
write in `draw()` carries unchanged into per-pixel shader code. The
[`Easing`](../Helpers/Animation.md) catalog is the curve library, and these
functions are the primitives it is built from.

- `clamp(x, lo, hi)` holds `x` within the range. The generic form clamps any
  comparable type, for example `clamp(i, 0, columns - 1)` for an `Int` index.
  `clamp(t, to: 0...1)` takes the range as one value.
- `wrap(x, lo, hi)` brings `x` back into `lo..<hi` by whole laps. It is the
  circular form of `clamp`. A walker that leaves one edge of the canvas comes
  back in at the other, as in `x = wrap(x + step, 0, width)`. An angle stays
  within one turn with `wrap(a, 0, .tau)`. It is floor-based like `fract`, so
  it stays continuous through negative values.
- `fract(x)` keeps the fractional part, so `fract(2.75)` is `0.75`. It is
  floor-based, which means it stays continuous through negative values and
  wrapping a growing value never jumps.
- `step(edge, x)` is `0` below `edge` and `1` from `edge` on. It works like an
  `if` written as a function, so use it as a hard switch for a blink or a flip.
- `smoothstep(edge0, edge1, x)` is the smooth S-ramp between two edges. It is
  `0` at or below `edge0` and `1` at or above `edge1`, with no corners in
  between. The two edges pick a soft window out of a signal, and swapping
  `edge0` and `edge1` fades the other way. Here the window travels across the
  shape:

```swift
let lit = smoothstep(0.3, 1.0, sin(angle * 3 - time))  // a soft traveling window
fill(Color.mix(.navy, .white, lit))
```

`smoothstep(0, 1, t)` is the plain `0...1` reshape. It is the same curve as
[`Easing.smoothstep`](../Helpers/Animation.md#catalog).

- `unipolar(x)` remaps a signed `-1...1` signal onto `0...1` (`x * 0.5 + 0.5`).
  This is a common remap, because it turns a wave or a signed
  noise sample into a usable fraction. `bipolar(x)` is its inverse
  (`x * 2 - 1`). For noise there is a shorter way. `noise(x)` already returns a
  value in `0...1`, so `unipolar(signedNoise(x))` is the same as `noise(x)`.

```swift
fill(palette.color(at: unipolar(sin(time))))
```

<a name="dividing"></a>

### Dividing a whole

```swift
fractions(_ count: Int, inclusive: Bool = false) -> [Double]
angles(_ count: Int, from start: Double = 0, turns: Double = 1) -> [Double]
```

These return the normalized loop index as a sequence, so you no longer write
`Double(i) / Double(count)` by hand. `fractions(n)` is `n` evenly spaced
fractions of `0...1`, running from `0` up to but not including `1`. That
spacing tiles a circle or a repeating strip with no doubled seam. Pass
`inclusive: true` to get `n` values from `0` through `1` exactly, which counts
the fence posts instead of the panels between them.

```swift
for t in fractions(12) {
    drawCircle(lerp(80, width - 80, t), height / 2, 20)
}
```

`angles(n)` is the same division expressed in radians, one full turn by
default. It gives you the spokes of a wheel as a sequence. `from` rotates the
whole wheel, so pass it `time` and the wheel turns. `turns` spreads the spokes
over less or more than a full circle.

```swift
for a in angles(12, from: time * 0.1) {
    drawCircle(center: polar(a, 300, around: center), radius: 20)
}
```

<a name="polar"></a>

### polar

```swift
polar(_ angle: Double, _ radius: Double, around center: Vector2 = .zero) -> Vector2
```

The point at `angle` and `radius` from `center`. This is polar coordinates as
one call, in place of the spelled-out `center + Vector2(cos(a), sin(a)) * r`.
The angle is in radians. `0` points right, and the angle increases clockwise on
screen, because y grows downward. With no `around:` the point is measured from
the origin, which composes with `translate`. When there is no center to add,
use `Vector2(angle:length:)`, which gives the same point as a direction vector.

```swift
drawLine(center, polar(time, 300, around: center))
```

<a name="primes"></a>

### Primes

```swift
primes(upTo limit: Int) -> [Int]
isPrime(_ number: Int) -> Bool
```

These two functions work with prime numbers. `primes(upTo:)` is the sieve of Eratosthenes. It returns the whole list at once, so drawing a field of thousands of numbers stays cheap. `isPrime` is the shorter way for a single number. Negative numbers, zero, and one are not prime.

```swift
for p in primes(upTo: 500) { drawCircle(Double(p), height / 2, 3) }
```

The picture these are best known for is the [Ulam spiral](../Generators/UlamSpiral.md). It writes the numbers in a square spiral and marks the primes.

`Fraction` is the exact whole-number type that goes with these. It is a fraction in lowest terms, with `mediant`, `isNeighbor`, and comparison by cross-multiplication. It is documented with [Ford circles](../Generators/FordCircles.md) and `fareySequence`, because that is the picture it was made for.

<a name="constants"></a>

### Constants and angle units

`Double.tau` is the full turn (2π), and most angle work uses that unit.

```swift
rotate(Double.tau / 6)   // a sixth of a turn
```

The drawing calls all take radians. `.degrees(_:)` and `.turns(_:)` convert a
familiar unit into radians at the call site:

```swift
rotate(.degrees(45))
rotate(.turns(0.25))     // a quarter circle
```

<img src="../../Guide/Images/B-JustEnoughMath/TauClock.jpg" alt="A dial with 0, tau over 4, tau over 2, and 3 tau over 4 marked around it, an accent wedge of tau over 8, and three mini dials showing tau over 12, 6, and 3" width="680">
