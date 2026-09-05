#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `The Hopf fibration`</sup>

---

## The Hopf fibration

The Hopf fibration is a set of circles, one for every point of a sphere. No two of the
circles meet, and every two of them are linked exactly once.

Start with an ordinary sphere. Every point on it stands for one whole circle in a sphere in
four dimensions. Those circles fill that space completely. When you project them down into
three dimensions, they become nested tori of interlocking rings.

`hopfFibers` returns those circles as plain `[Vector3]` paths, so you can pass them to
`drawTube` or to any other call that takes a 3D path.

<img src="../../Guide/Images/22-Meshes/HopfFibration.jpg" alt="Nested rings of colored tubing seen at an angle, running from pink and violet at the tight center out through green and blue to orange at the widest, every ring passing through every other, with a thin red line standing vertically through the middle of them all" width="680">

### Contents

- [Quick start](#quick-start)
- [Choosing the base points](#bases)
- [Taking the color from the base point](#color)
- [The one that comes back straight](#straight)
- [What it costs](#costs)

<a id="quick-start"></a>
### Quick start

```swift
override func draw() {
    background(Color(hex: 0x05070C))
    cameraShowcase(radius: 7)

    for fiber in hopfFibers(over: hopfBases(latitudes: 4, perCircle: 16)) {
        fill(color(for: fiber.base))
        drawTube(fiber.points, radius: 0.02, closed: !fiber.isStraight)
    }
}
```

Each `HopfFiber` carries three things. The `base` is the point on the sphere it came from.
The `points` are its circle in space. `isStraight` is true for the one fiber that is a line
rather than a loop.

<a id="bases"></a>
### Choosing the base points

The set of base points decides whether the linking is visible in the picture, so choose it
with care.

You can see the linking only when base points that sit next to each other lift to circles
that sit next to each other. A scattered set of base points is just as correct, but the
picture then looks like a ball of wool. Ollin supplies two structured sets:

```swift
hopfBases(latitudes: 4, perCircle: 16)   // rings of latitude: nested tori
hopfBases(spiralCount: 200)                   // spread evenly over the whole sphere
```

Start with `hopfBases(latitudes:perCircle:spanning:)`. Each ring of base points lifts to one
torus of circles. The rings nest inside each other, and that is the picture the fibration is
known by. Each ring is turned slightly against the last, so the circles interleave instead
of lining up into visible spokes.

`spanning` is the range of heights the rings sit at, from -1 at the bottom of the sphere to
1 at the top. The default range keeps clear of the bottom, and the next section explains why.

Any `[Vector3]` on the unit sphere works, so you can pass a set of your own. Keep the points
in order, for the same reason: neighboring base points have to lift to neighboring circles.

<a id="color"></a>
### Taking the color from the base point

Color each circle by where it came from:

```swift
func color(for base: Vector3) -> Color {
    let around = (atan2(base.z, base.x) / .tau + 1).truncatingRemainder(dividingBy: 1)
    let up = (base.y + 1) / 2
    return Color(hue: around, saturation: 0.42 + (1 - up) * 0.48, brightness: 0.55 + up * 0.45)
}
```

The color carries information here, so it is not decoration. Read it from the base point
rather than from a counter. In the code above, the hue runs around the sphere and the
lightness runs up it. Reading the color that way is what shows the whole tangle is a picture
of a sphere. A rainbow assigned in draw order tells the reader nothing.

<a id="straight"></a>
### The one that comes back straight

The circles grow without limit as the base point approaches the bottom of the sphere, because
that is where the projection sends things to infinity. The base point exactly at the bottom
lifts to a circle that runs through that point, so that circle projects to **a straight
line**. That line is the vertical axis that passes through the middle of every other ring.

Ollin returns that line as a two-point path with `isStraight` set:

```swift
let spine = hopfFiber(over: Vector3(0, -1, 0), reach: 6)
// spine.isStraight == true, spine.points == [(0, -6, 0), (0, 6, 0)]
```

`reach` sets how long to make it, because a line has no size of its own. Leaving the line out
leaves the middle of the picture empty. Add its base point by hand when your own base points
keep clear of the bottom:

```swift
let bases = hopfBases(latitudes: 4, perCircle: 16) + [Vector3(0, -1, 0)]
```

`hopfBases(spiral:)` already reaches the bottom on its own.

<a id="costs"></a>
### What it costs

Each fiber is `segments` points of plain arithmetic, so the geometry is cheap. The cost is in
what you draw it with. One `drawTube` per fiber is one mesh per fiber, so a hundred fibers at
200 segments is a hundred swept tubes every frame. Build them once into meshes if the base
points are not moving, or lower `segments` and the tube's `sides` if they are.

---

See also [3D](3D.md) for `drawTube`, the camera, and the lighting around it,
[Instancing](Instancing.md) for drawing many copies of one shape cheaply, and
[Geometry](../Drawing/Geometry.md) for the value types it returns.
