#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Complex`</sup>

---

## Complex numbers

A `Complex` is a point of the plane that knows how to multiply. Adding two of them adds their coordinates, exactly as `Vector2` does. Multiplying them multiplies their lengths and *adds their angles*. That is the one thing a plain vector cannot do, and the reason so much generative work is written in them. An escape-time fractal is `z * z + c` repeated. A [domain coloring](../Drawing/Effects.md#generate) paints a function of `z` over the plane it acts on. A Möbius map turns the plane inside out around a point, and a conformal warp keeps every small square a square.

```swift
var z = Complex(0.3, 0.5)
let c: Complex = -0.8 + 0.156 * .i
for _ in 0 ..< 40 { z = z * z + c }      // one Julia orbit
let turned = z * .unit(.pi / 6)          // the same point, turned thirty degrees
drawCircle(center: Vector2(turned), radius: 4)
```

The same arithmetic runs on the GPU as the [shader library's `complex` module](../Shaders/ShaderLibrary.md#complex-numbers), one function per operation with the same meaning. A curve worked out here in `draw()` lands on the pixels a shader paints. `Examples/Shaders/ComplexPlane` draws both halves over each other.

### Contents

- [Making one](#making)
- [Arithmetic](#arithmetic)
- [Reading one](#reading)
- [Functions](#functions)
- [The plane and the canvas](#canvas)
- [See also](#see-also)

<a name="making"></a>

### Making one

```swift
Complex(_ real: Double, _ imaginary: Double = 0)
Complex(real: Double, imaginary: Double)
Complex(magnitude: Double, argument: Double)    // the polar form
Complex(_ vector: Vector2)                      // vector.x + vector.y·i
Complex.zero, Complex.one, Complex.i
Complex.unit(_ angle: Double)                   // e^(i·angle), on the unit circle
```

A `Complex` is a `Numeric` value, so a plain number is one too. `let z: Complex = 3` is the real number three, `2 * z` doubles it, and an array of them sums under `reduce(0, +)`. `.i` is the imaginary unit, so `1 + 2 * .i` reads as it is written, and `.unit(angle)` is the number that turns whatever it multiplies by that angle.

```swift
let z = Complex(1, 2)                            // 1 + 2i
let w = Complex(magnitude: 1, argument: .pi / 4)  // a unit number at 45 degrees
let sum = [z, w, .i].reduce(0, +)
```

<a name="arithmetic"></a>

### Arithmetic

`+`, `-`, `*`, and `/` work between two complex numbers and between a complex number and a `Double` on either side, with the compound forms `+=`, `-=`, `*=`, `/=`. Multiplication is the whole point: the lengths multiply and the angles add, so multiplying by `.unit(a)` turns a number by `a` without moving it in or out.

```swift
let a = Complex(2, 1), b = Complex(0, 1)
let product = a * b            // -1 + 2i: a turned by ninety degrees
let quotient = a / b           // 1 - 2i
let scaled = a * 0.5           // 1 + 0.5i
let shifted = a + 1            // 3 + i
```

A real number mixes in as a literal or as a `Double`. There is no conversion the other way, so a `Complex` never lands where a `Double` was expected.

<a name="reading"></a>

### Reading one

| Property | What it is |
| --- | --- |
| `real`, `imaginary` | the two parts |
| `magnitude` | the distance from the origin, `\|z\|` (the modulus) |
| `magnitudeSquared` | `\|z\|²` without the root: cheaper for an escape test |
| `argument` | the angle from the positive real axis, radians in `(-pi, pi]` |
| `conjugate` | the mirror image across the real axis, `real - imaginary·i` |
| `reciprocal` | `1 / z` |
| `vector` | the same point as a `Vector2` |
| `isFinite` | whether both parts are finite |
| `rotated(by:)` | the number turned by an angle about the origin |
| `squareRoot()` | the principal square root (the other root is its negative) |
| `description` | reads as written: `1 + 2i`, `1 - 2i`, `2i`, `-i`, `3` |

```swift
let z = Complex(3, 4)
let r = z.magnitude            // 5
let theta = z.argument         // 0.927...
let back = Complex(magnitude: r, argument: theta)   // 3 + 4i again
```

<a name="functions"></a>

### Functions

The transcendental functions are static members, `Complex.exp(z)`, the spelling the Swift numerics package uses. They are not free functions on purpose. A free `pow(z, n)` or `sin(z)` would join the candidates for every `pow` and `sin` in your sketch. A plain line of doubles such as `pow(2, 20 * t - 10) * sin(x)` would then have to rule this type out each time, which the compiler does slowly and sometimes not at all. Every multi-valued function takes the **principal branch**: the argument in `(-pi, pi]`, so the values jump across the negative real axis. That cut is real, and a domain coloring shows it.

| Function | What it is |
| --- | --- |
| `Complex.exp(z)` | `e^z`: the modulus is `e` to the real part, the argument is the imaginary part |
| `Complex.log(z)` | the natural logarithm, `log\|z\| + i·arg z` |
| `Complex.pow(z, 2.5)` | `z` to a real power by the polar form; a whole number winds the plane cleanly, a fraction shows the seam |
| `Complex.pow(z, w)` | `z` to a complex power `w`, `exp(w·log z)` |
| `Complex.pow(z, 3)` | `z` to a whole power by repeated squaring: exact where the polar form would round, which is what an orbit iterated thousands of times wants |
| `Complex.sqrt(z)` | the principal square root, the same as `z.squareRoot()` |
| `Complex.sin(z)`, `.cos(z)`, `.tan(z)` | the trigonometric functions |
| `Complex.sinh(z)`, `.cosh(z)`, `.tanh(z)` | the hyperbolic functions |

```swift
let z = Complex(0.5, 1.2)
let back = Complex.log(Complex.exp(z))   // z again, since its imaginary part is inside (-pi, pi]
let cube = Complex.pow(z, 3)             // exact
let root = Complex.sqrt(Complex(-4))     // 2i
let euler = Complex.exp(Complex(0, .pi)) // -1, within rounding
```

<a name="canvas"></a>

### The plane and the canvas

Mathematics draws the plane with the imaginary axis pointing **up**. A `Vector2` is a canvas point, with y pointing **down**. `Complex(v)` and `Vector2(z)` copy the coordinates as they are and leave the flip to you. That keeps both conversions honest: a number read off a canvas point is that point, and the other way round. When a picture should read as mathematics writes it, flip the imaginary part once at the edge. The shader library's `complexPlane` does that for a layer:

```swift
let scale = min(width, height) / 3        // three units across the canvas
func place(_ z: Complex) -> Vector2 {
    Vector2(width / 2 + z.real * scale, height / 2 - z.imaginary * scale)
}
drawCircle(center: place(Complex.unit(time)), radius: 6)   // a dot going round counter-clockwise
```

A [domain coloring](../Drawing/Effects.md#generate) generator frames its plane the same way, three units across at zoom 1. A point placed with this `place` lands on the generator's picture of that point.

<a name="see-also"></a>

### See also

- [The shader library's `complex` module](../Shaders/ShaderLibrary.md#complex-numbers): the same functions on a `float2` inside a shader, plus `complexPlane` to frame a layer as the plane and `domainColor` to paint a value.
- [Domain coloring](../Drawing/Effects.md#generate): the built-in generator that paints a named function or a rational one over the plane.
- [Fractals](../Generators/Fractals.md): the escape-time generators, the Kleinian and Schottky limit sets, all of them this arithmetic iterated.
- [Geometry](../Drawing/Geometry.md#vector): `Vector2`, the value a `Complex` shares its coordinates with.
- Worked example: [`Examples/Shaders/ComplexPlane`](../../Examples/Shaders/ComplexPlane/Sketch.swift), a shader coloring the ratio of two moving points and `draw()` laying the circles that ratio is made of over it.
