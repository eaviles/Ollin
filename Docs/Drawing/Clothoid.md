#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Clothoid`</sup>

---

## Clothoid: the curve that bends at a steady rate

Every other curve in the toolbox is written as a position. This one is written as a *turn rate*. Start somewhere, face a direction, and turn a little more sharply with every step you take. That single rule is the whole definition. It produces the one shape that joins a straight line to a circle with no kink in the bend.

The kink is the point of it. Put a straight road against a circular curve and the bend jumps from nothing to `1 / radius` at the join. The wheel has to be turned instantly. Put a clothoid between them and the bend climbs through every value in between, which is what a hand actually does. Roads, railways, and roller coasters are laid out this way. It is why a motorway curve feels different from a curve drawn with a compass.

<img src="../../Guide/Images/15-ShapesAsMaterial/ClothoidCorner.jpg" alt="The same right-angle corner rounded two ways. On the left one arc, and under it a graph of the bend that is a flat-topped rectangle with vertical sides. On the right the corner eased at both ends, and under it the same graph as a trapezoid that ramps up, holds, and ramps back down" width="680">

```
   the bend along a plain arc corner       the bend along an eased corner

   1/R  |      .-----------.               1/R  |        _.-----._
        |      |           |                    |     _.'         '._
        |      |           |                    |   .'               '.
      0 +------'           '------            0 +--'                   '--
        |  straight  arc  straight              | straight  ease arc ease
```

The curve is also called the **Euler spiral**, and the **Cornu spiral** when it is drawn whole. Nothing here is random, so the same numbers always produce the same curve. What comes out is ordinary geometry, ready for stroking, filling, the [shape booleans](./Geometry.md#shape-booleans), hatching, and [SVG export](../Output/Export.md) for the pen plotter.

### Contents

- [The four numbers](#numbers)
- [Reading a curve](#reading)
- [The easement](#easement)
- [Joining two points with two headings](#fit)
- [A smooth path through points](#spline)
- [Corners a vehicle could take](#corners)
- [Driving a chain](#driving)
- [The whole spiral](#spiral)
- [How exact it is](#exact)

<a name="numbers"></a>

#### The four numbers

```swift
Clothoid(start: Vector2 = .zero,
         heading: Double = 0,
         curvature: Double = 0,
         curvatureRate: Double,
         length: Double)
```

They read left to right along the curve:

| | |
|---|---|
| `start` | where it begins |
| `heading` | the way it faces there, in radians, measured the way `Vector2.angle` measures |
| `curvature` | how hard it is already bending at the start, as `1 / radius`. Zero is straight, and positive turns to the left |
| `curvatureRate` | how much the bend grows over one unit of length. This is the number that makes it a clothoid |
| `length` | how far along to go |

Two ordinary curves fall out of the same four numbers. A `curvatureRate` of zero holds the bend, which is a circular arc, and if `curvature` is zero too it is a straight line. Neither is a special case here, which is why a chain of clothoids can carry its own straights and arcs with no separate kinds and no seams to manage.

<a name="reading"></a>

#### Reading a curve

```swift
let curve = Clothoid(start: Vector2(200, 900), heading: 0,
                     curvatureRate: 0.00002, length: 600)

curve.point(at: 120)        // where it is 120 along
curve.heading(at: 120)      // the way it faces there
curve.curvature(at: 120)    // how hard it bends there
curve.tangent(at: 120)      // the same heading as a unit vector

curve.end                   // point(at: length)
curve.endHeading            // heading(at: length)
curve.endCurvature          // curvature(at: length)
curve.turn                  // how far the heading turns over the whole curve
```

Distances are measured **along the curve**, not along a parameter that speeds up and slows down. Ask for the point 120 along and you have gone exactly 120 of travel. That is what makes a clothoid drivable at a steady speed with no arc-length table.

Three ways to get points out:

```swift
curve.points(count: 200)              // evenly spaced by length
curve.points(spacing: 2)              // about 2 apart, and more where it bends hard
curve.contour(spacing: 2)             // the same, as an open Contour
```

`points(spacing:)` also honors `angle:`, the most the heading may turn between one point and the next (0.05 radians by default), so a short hard corner does not go faceted just because it is short.

<a name="easement"></a>

#### The easement

```swift
Clothoid.easement(from: Vector2, heading: Double, radius: Double, length: Double) -> Clothoid
```

The piece that takes a straight run into a turn of `radius` over `length` of travel. It starts straight and ends bending exactly as hard as the arc it hands over to, so the two meet with no kink. Positive `radius` turns left, negative turns right.

```swift
let ease = Clothoid.easement(from: Vector2(120, 540), heading: 0, radius: 200, length: 260)
drawPolyline(ease.points(count: 120))
```

Its heading turns by `length / (2 * radius)`, which is **half** of what the same length of arc would turn. A clothoid spends the first part of the piece hardly bending at all, and that is exactly the head start a wheel needs.

<a name="fit"></a>

#### Joining two points with two headings

```swift
Clothoid(from: Vector2, heading: Double, to: Vector2, heading: Double) -> Clothoid?
```

Two points and two directions are four facts, and a clothoid has exactly the freedom to meet them: how hard it bends at the start, how fast that grows, and how long it runs.

```swift
if let join = Clothoid(from: Vector2(200, 200), heading: 0,
                       to: Vector2(800, 700), heading: .pi / 2) {
    drawPolyline(join.points(count: 200))
}
```

There are infinitely many answers, because a curve may loop around before it arrives. The one returned is the plain one: the answer whose two headings each stay within half a turn of the straight line between the points. It returns `nil` only when the two points are the same, which asks for no curve at all.

A straight line and a circular arc are ordinary members of the family here. Ask for two headings that are both along the line between the points and you get a straight run back, with a `curvatureRate` of zero and a `length` equal to the gap.

<a name="spline"></a>

#### A smooth path through points

```swift
clothoidSpline(through points: [Vector2], closed: Bool = false) -> [Clothoid]
```

One clothoid per gap, each leaving a point facing the way the one before it arrived. The path passes through every point exactly and never kinks at one.

```swift
let path = clothoidSpline(through: waypoints)
drawPolyline(path.contour().points)
```

The heading at each point is read off its two neighbors, which is what makes the path depend on the whole list rather than one gap at a time. The bend itself may still jump at a point, because a single clothoid per gap has no freedom left to match it as well. That is the usual trade: a path with no kink, worked out in one pass with nothing to solve across the whole list. When the bend matters more than the points, reach for [`clothoidCorners`](#corners) instead, which gives up passing through the corners and gets a continuous bend in return.

<a name="corners"></a>

#### Corners a vehicle could take

```swift
clothoidCorners(_ points: [Vector2], radius: Double, easement: Double,
                closed: Bool = false) -> [Clothoid]
```

Every corner of a polyline replaced by an easement in, an arc of `radius`, and an easement back out. The straight runs between the corners come back as part of the chain, so the whole route is one list from the first point to the last.

```swift
let route = clothoidCorners(waypoints, radius: 90, easement: 70)
drawPolyline(route.contour().points)
```

A plain rounded corner is one arc, and the bend jumps at both ends of it. Here the bend climbs from nothing to `1 / radius` over `easement` of travel, holds through the arc, and falls away again, so the bend never jumps anywhere along the route.

A corner is fitted only as large as its two legs allow. When it does not fit, the radius and the easement are both scaled down by the same factor **for that corner alone**, which keeps the shape of the turn and only makes it smaller. Each corner may take at most half of each leg it touches, so two corners sharing a leg never run into each other.

<a name="driving"></a>

#### Driving a chain

Both builders hand back `[Clothoid]`, and an array of them reads as one path:

```swift
route.length                  // how far the whole chain runs
route.point(at: s)            // the point s along the chain
route.heading(at: s)          // the way it faces there
route.curvature(at: s)        // how hard it bends there
route.position(at: s)         // the piece it is on, and how far along that piece
route.contour(spacing: 2, closed: true)   // the whole chain as one Contour
```

`s` is clamped to the chain, so a distance past the end reads the end. Because a chain is measured by length, driving it is one line:

```swift
let along = (time * 260).truncatingRemainder(dividingBy: route.length)
if let here = route.point(at: along), let facing = route.heading(at: along) {
    withState {
        translate(here)
        rotate(facing)
        drawTriangle(Vector2(16, 0), Vector2(-10, 9), Vector2(-10, -9))
    }
}
```

The point of the whole curve shows up in `curvature(at:)`. Read it while you drive and it is the steering wheel: on a clothoid route it moves smoothly, and on an arc route it snaps.

<a name="spiral"></a>

#### The whole spiral

```swift
eulerSpiral(size: Double, turns: Double = 2.5, count: Int = 500) -> [Vector2]
```

The Cornu spiral: one clothoid read in both directions from the point where it is straight. The bend grows without limit either way, so each arm winds into a tighter and tighter circle around a point it never reaches. Those two points are the eyes.

```swift
drawPolyline(eulerSpiral(size: 700, turns: 2.5))
```

`size` is how far apart the two ends of the drawn curve are, and `turns` is how many full turns each arm makes before it stops. Past about three, the arms are drawing on top of themselves.

<a name="exact"></a>

#### How exact it is

There is no elementary formula for the position: it is the integral of the heading, and that integral is the Fresnel one. It is worked out here by quadrature. The range is cut into pieces that each sweep less than half a radian of phase. An eight-point Gauss-Legendre rule is applied to every piece. That lands within a few parts in `10^15`, however hard the curve winds. A clothoid whose bend grows at `pi` per unit is the Fresnel pair exactly. Its end lands on the published values of `C(t)` and `S(t)` to twelve decimal places.

The closed form in Fresnel integrals is faster, and it is not used. It loses precision exactly as the bend rate goes to zero, which is the arc and straight-line cases a chain hits most often. The steady method wins here.

`points(count:)` works the points out one span at a time rather than each from the start. A thousand points therefore cost about what one costs, per point. A polyline is always slightly shorter than the curve it samples, by the square of the step.

### See also

- [Classic curves](./Curves.md) - the other curves you can write down, including Chaikin smoothing for when a rounded corner is all you need
- [Geometry](./Geometry.md) - `Vector2`, `Contour`, and the shape booleans everything here feeds
- [Fabrication export](../Output/Fabrication.md) - where a continuously bending path matters most, on a machine that has to physically follow it
- [Steering](../Generators/Steering.md) - the other way to get a smooth path, by giving something momentum and letting it turn

### Where this comes from

The curve was described by Leonhard Euler in 1744, rediscovered by Augustin-Jean Fresnel in his work on diffraction, and named the clothoid by Ernesto Cesaro. Arthur Talbot brought it into railway practice in 1890. The fit in [Joining two points with two headings](#fit) follows the reduction published by Enrico Bertolazzi and Marco Frego in 2015. It collapses three nonlinear equations to one unknown. Written from the published results, credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

### Example

[`Examples/Patterns/Clothoid`](../../Examples/Patterns/Clothoid/Sketch.swift) drives a closed route at a steady speed with the bend combed off it and a steering wheel that reads it. Pull `easement` to zero and watch the comb turn into a square step.
