#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `The Hopf fibration`</sup>

---

## The Hopf fibration

A sphere's worth of circles, no two of which meet, and every two of which are linked
exactly once.

Take an ordinary sphere. Every point of it stands for a whole circle living in a
sphere-in-four-dimensions, and those circles fill that space completely without one of them
ever touching another. Bring them down into three dimensions and they come out as nested
tori of interlocking rings.

`hopfFibers` hands you those circles as plain `[Vector3]` paths, ready for `drawTube` or any
other 3D path.

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

Each `HopfFiber` carries three things: the `base` point on the sphere it came from, the
`points` of its circle in space, and `isStraight` for the one that is a line rather than a
loop.

<a id="bases"></a>
### Choosing the base points

This is the decision that makes the figure read or not read, so it is worth a moment.

The linking is only visible when neighboring circles are neighbors. A scattered set of base
points draws as a ball of wool, however correct it is. Two structured sets are supplied:

```swift
hopfBases(latitudes: 4, perCircle: 16)   // rings of latitude: nested tori
hopfBases(spiral: 200)                   // spread evenly over the whole sphere
```

`hopfBases(latitudes:perCircle:spanning:)` is the arrangement to start with. Each ring of
base points lifts to one torus of circles, and the rings nest inside each other, which is
the picture the fibration is known by. Each ring is turned slightly against the last so the
circles interleave rather than lining up into visible spokes.

`spanning` is the range of heights the rings sit at, from -1 at the bottom of the sphere to
1 at the top. It defaults to keeping clear of the bottom, and the next section says why.

Any `[Vector3]` on the unit sphere works, so a set of your own is fine. Just keep it ordered.

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

This is not decoration. Reading the color off the base point rather than off a counter is
what shows that the whole tangle is a picture of a sphere, with the hue running around it
and the lightness running up it. A rainbow assigned in draw order says nothing.

<a id="straight"></a>
### The one that comes back straight

The circles grow without limit as the base point approaches the bottom of the sphere,
because that is where the projection sends things to infinity. The base point exactly at the
bottom lifts to a circle that runs through that point, so it comes down as **a straight
line**: the vertical axis every other ring is threaded onto.

It is handed over rather than dropped, as a two-point path with `isStraight` set:

```swift
let spine = hopfFiber(over: Vector3(0, -1, 0), reach: 6)
// spine.isStraight == true, spine.points == [(0, -6, 0), (0, 6, 0)]
```

`reach` is how long to make it, since a line has no size of its own to take. Leaving it out
takes the middle out of the picture, so add it by hand when your base points keep clear of
the bottom:

```swift
let bases = hopfBases(latitudes: 4, perCircle: 16) + [Vector3(0, -1, 0)]
```

`hopfBases(spiral:)` already reaches the bottom on its own.

<a id="costs"></a>
### What it costs

Each fiber is `segments` points of plain arithmetic, so the geometry is cheap. What costs is
what you draw it with: a `drawTube` per fiber is a mesh per fiber, so a hundred fibers at 200
segments is a hundred swept tubes every frame. Build them once into meshes if the base points
are not moving, or drop `segments` and the tube's `sides` if they are.

---

See also [3D](3D.md) for `drawTube`, the camera, and the lighting around it,
[Instancing](Instancing.md) for drawing many copies of one shape cheaply, and
[Geometry](../Drawing/Geometry.md) for the value types it hands back.
