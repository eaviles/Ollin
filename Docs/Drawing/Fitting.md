#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Fitting`</sup>

---

## Fitting

Two helpers for getting from a few numbers to a whole picture, and back.

[`RadialBasis`](#radial-basis) goes outward: you know a value at a handful of scattered
places and want one everywhere. [`Fit.minimize`](#minimize) goes inward: you have a handful
of knobs and a way of saying how wrong a setting of them is, and you want the setting that
is least wrong.

### Contents

- [A field through scattered values](#radial-basis)
- [Choosing a kernel](#kernels)
- [Fields of vectors, and warps](#warps)
- [Smoothing](#smoothing)
- [Finding a handful of numbers](#minimize)
- [What each one costs](#costs)

<a id="radial-basis"></a>
### A field through scattered values

A grid can be interpolated by looking at the cells around a spot. Scattered points have no
such neighbors, so the answer has to come from all of them at once. A radial basis function
gives every known point a bump centered on it, and weights the bumps so their sum passes
exactly through every value you gave:

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
costs what a field of numbers costs.

The initializer returns `nil` when the points cannot pin a field down: no points, a
mismatched pair of lists, two points in the same place disagreeing, or points that all sit
on one straight line.

<a id="kernels"></a>
### Choosing a kernel

The kernel is the shape of each bump. Six are available, and the default is a good first
choice for almost everything:

| Kernel | Shape | When |
|---|---|---|
| `.thinPlate` | `r² log r` | The default. The shape a pinned steel sheet takes, which is the smoothest surface through the points |
| `.linear` | `r` | Cones. Sharp ridges at each point, and the cheapest |
| `.cubic` | `r³` | Smoother than thin plate, keener to overshoot |
| `.multiquadric(scale:)` | `√(r² + s²)` | Broad and smooth |
| `.inverseMultiquadric(scale:)` | `1 / √(r² + s²)` | Fades, so distant points stop having a say |
| `.gaussian(scale:)` | `exp(-(r/s)²)` | Fades fast. Tight and local |

The first three grow without limit away from their point, which sounds wrong and is not.
What matters is the sum, and a flat plane is fitted alongside the bumps and cancels the
growth. Those three extrapolate gracefully past the edge of the data. The last three fade
instead, so far from every point the field settles rather than running off, and each takes
a `scale` in the same units as your points, which wants to be about the spacing between
them.

<a id="warps"></a>
### Fields of vectors, and warps

A field carrying `Vector2`s is a warp. Pin a few places to where they should move to, and
everything between follows smoothly:

```swift
let warp = RadialBasis(points: pins, values: targets)!
let bent = straightLine.map { warp.value(at: $0) }
```

Read every point of a shape through the warp and the shape bends. Read a grid through it
and you get the classic rubber-sheet picture. Each pinned place lands exactly on its target,
because that is what interpolating means.

<a id="smoothing"></a>
### Smoothing

At `smoothing: 0` the field hits every value exactly, which is what clean data wants and
what makes noisy data ring. Raise it and the field is allowed to miss, by more the higher
it goes, in exchange for fewer wobbles between the points:

```swift
RadialBasis(points: samples, values: readings, smoothing: 0.05)
```

It is measured against the scale of the fit rather than in raw units, so the same number
means the same thing whether your points are spread over a thousand pixels or over one.
Around 0.01 is a light touch and 1 is heavy.

<a id="minimize"></a>
### Finding a handful of numbers

`Fit.minimize` is the other direction. Give it a starting setting and a cost, and it walks
the setting downhill:

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
| `from` | the setting to start at, and how many knobs there are |
| `bounds` | an optional range per knob, which the walk is held inside |
| `steps` | the most steps to take |
| `rate` | how far a step moves a knob, in that knob's own units |
| `tolerance` | settle once a step improves the cost by less than this |

The result carries the best setting found, its cost, how many steps it took, and whether it
`settled` on its own rather than running out. A walk that used every step may just need more
of them, or a larger `rate`.

Two things to know. Each knob moves by about `rate` per step whatever the slope is there,
so one `rate` serves a knob measured in pixels beside a knob measured in turns. And the walk
goes **downhill from where you start**, so a cost with several separate valleys hands back
whichever one your starting point sat in. When that matters, start it from several places
and keep the best answer.

<a id="costs"></a>
### What each one costs

**Fitting a field** solves a dense system, so it costs about the cube of the number of
points. A few hundred fit in milliseconds; tens of thousands are the wrong tool. Reading the
field afterward costs one term per point, every time, so a large fit read over a whole
canvas is the expensive half. Fit once in `setup()`, read in `draw()`.

**Minimizing** measures the slope rather than deriving it, by trying each knob a little
either side of where it stands, so your cost is called about twice per knob per step. Keep
it cheap, and remember that 300 steps over 3 knobs is already 1,800 calls.

---

See also [Geometry](Geometry.md) for the value types both of these work over,
[Spatial queries](SpatialIndex.md) for finding which scattered points are near a place, and
[Flow fields](../Generators/FlowField.md) for a field generated from noise rather than
fitted through values you chose.
