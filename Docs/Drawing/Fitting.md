#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Fitting`</sup>

---

## Fitting

This page covers two helpers. One turns a few numbers into a whole picture, and the other
works back to a few numbers from a measure of how wrong they are.

[`RadialBasis`](#radial-basis) goes outward. You know a value at a handful of scattered
places, and it gives you a value everywhere. [`Fit.minimize`](#minimize) goes inward. You
have a handful of parameters, and a way to measure how wrong a setting of them is. You want
the setting that is least wrong.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/14-FieldsAndFlow/Fitting-dark.jpg">
  <img src="../../Guide/Images/14-FieldsAndFlow/Fitting.jpg" alt="Three panels. A soft field of orange, pink, blue, green and yellow filling a square with six small dark rings marking the points it was fitted through; a white grid on black bent into curves by six orange arrows pulling on it; and a ring of pale dots wobbling around a circle, with a gold circle drawn through the middle of them and a gold dot at its center" width="680">
</picture>

### Contents

- [A field through scattered values](#radial-basis)
- [Choosing a kernel](#kernels)
- [Fields of vectors, and warps](#warps)
- [Smoothing](#smoothing)
- [Finding a handful of numbers](#minimize)
- [What each one costs](#costs)

<a id="radial-basis"></a>
### A field through scattered values

You can interpolate a grid by looking at the cells around a spot. Scattered points have no
such neighbors, so the answer has to come from all of them at once. A radial basis function
does this by giving every known point a bump centered on it. It then weights the bumps so
that their sum passes exactly through every value you gave:

```swift
let field = RadialBasis(points: [Vector2(120, 140), Vector2(700, 300), Vector2(400, 860)],
                        values: [0.1, 0.9, 0.4])!

for y in stride(from: 0.0, to: height, by: 10) {
    for x in stride(from: 0.0, to: width, by: 10) {
        fill(Color(white: field.value(at: Vector2(x + 5, y + 5))))
        drawRect(x, y, 11, 11)
    }
}
```

The values can be `Double`s, `Vector2`s, `Vector3`s, or `Color`s, and the points can be
`Vector2` or `Vector3`. All the channels of a value share one solve, so a field of colors
costs the same as a field of numbers.

The initializer returns `nil` when the points cannot define a field. That happens when
there are no points, or when the two lists have different lengths. It also happens when two
points in the same place carry different values, or when all the points sit on one straight
line.

<a id="kernels"></a>
### Choosing a kernel

The kernel is the shape of each bump. Six are available, and the default is a good first
choice for almost everything:

| Kernel | Shape | When |
|---|---|---|
| `.thinPlate` | `r² log r` | The default. The shape a pinned steel sheet takes, which is the smoothest surface through the points |
| `.linear` | `r` | Cones. Sharp ridges at each point, and the cheapest |
| `.cubic` | `r³` | Smoother than thin plate, and more likely to overshoot |
| `.multiquadric(scale:)` | `√(r² + s²)` | Broad and smooth |
| `.inverseMultiquadric(scale:)` | `1 / √(r² + s²)` | Fades, so distant points stop affecting the field |
| `.gaussian(scale:)` | `exp(-(r/s)²)` | Fades fast. Tight and local |

The first three grow without limit away from their point. That sounds wrong, but it is not,
because only the sum matters. A flat plane is fitted alongside the bumps, and it cancels the
growth. So those three extrapolate sensibly past the edge of the data. The last three fade
instead, so the field settles far from every point rather than running off. Each of those
three takes a `scale` in the same units as your points, and a good value is about the
spacing between them.

<a id="warps"></a>
### Fields of vectors, and warps

A field of `Vector2`s is a warp. You pin a few places to where they should move, and
everything between them follows smoothly:

```swift
let warp = RadialBasis(points: pins, values: targets)!
let bent = straightLine.map { warp.value(at: $0) }
```

When you read every point of a shape through the warp, the shape bends. When you read a
grid through it, you get the classic rubber-sheet picture. Each pinned place lands exactly
on its target, because the field interpolates the values you gave.

<a id="smoothing"></a>
### Smoothing

At `smoothing: 0` the field passes through every value exactly. That is right for clean
data, but it makes noisy data ring. When you raise the value, the field is allowed to miss
the points, and the higher the value, the more it may miss. In exchange, there are fewer
wobbles between the points:

```swift
RadialBasis(points: samples, values: readings, smoothing: 0.05)
```

The value is measured against the scale of the fit, not in raw units. So the same number
means the same thing whether your points are spread over a thousand pixels or over one.
Around 0.01 is light smoothing, and 1 is heavy.

<a id="minimize"></a>
### Finding a handful of numbers

`Fit.minimize` goes the other direction. You give it a starting setting and a cost
function, and it moves the setting downhill, toward a lower cost:

```swift
// The circle that passes closest to a set of marks.
let best = Fit.minimize(from: [width / 2, height / 2, 100]) { p in
    marks.reduce(0.0) { total, mark in
        let off = Vector2(p[0], p[1]).distance(to: mark) - p[2]
        return total + off * off
    }
}
drawCircle(best.values[0], best.values[1], best.values[2])
```

| | |
|---|---|
| `from` | the setting to start at. Its length sets how many parameters there are |
| `bounds` | an optional range per parameter. The walk stays inside it |
| `steps` | the most steps to take |
| `rate` | how far a step moves a parameter, in that parameter's own units |
| `tolerance` | the walk settles once a step improves the cost by less than this |

The result carries the best setting found, its cost, and how many steps it took. It also
tells you whether it `settled` on its own rather than running out of steps. A walk that used
every step may need more steps, or a larger `rate`.

Two things are worth knowing. First, each parameter moves by about `rate` per step, whatever
the slope is at that point. So one `rate` works for a parameter measured in pixels beside a
parameter measured in turns. Second, the walk goes **downhill from where you start**. So
when a cost has several separate valleys, the walk settles in whichever valley your starting
point sat in. When that matters, start the walk from several places and keep the best answer.

<a id="costs"></a>
### What each one costs

**Fitting a field** solves a dense system, so its cost grows with about the cube of the
number of points. A few hundred points fit in milliseconds. For tens of thousands of points,
this is the wrong tool. Reading the field afterward costs one term per point, on every read.
So for a large fit read over a whole canvas, the reading is the expensive half. Fit once
in `setup()`, and read in `draw()`.

**Minimizing** measures the slope rather than deriving it. It does this by trying each
parameter a little to either side of where it stands. So your cost function is called about
twice per parameter per step. Keep the cost function cheap. Remember that 300 steps over 3
parameters is already 1,800 calls.

---

See also [Geometry](Geometry.md) for the value types both helpers work with,
[Spatial queries](SpatialIndex.md) for finding which scattered points are near a place, and
[Flow fields](../Generators/FlowField.md) for a field generated from noise rather than
fitted through values you chose.
