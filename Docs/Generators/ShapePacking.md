#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Shape packing`</sup>

---

## Shape packing

Fill a region with any shapes you like. Each shape grows until it touches its neighbors, the way [circle packing](./Packing.md) fills a region with circles. The difference is that `packShapes` grows each shape until it meets its neighbors' **outlines**, not just their bounding circles. That is why a small shape settles into the concave gaps left by a star's notches or a triangle's edges. `packShapes` places the big shapes first, then fills the space between them with progressively smaller ones. Each shape is a random pick from a bag, rotated and scaled to fit.

The output is `[Shape]`, so you can pass it to fills, strokes, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export. A run depends only on the [`seed`](./Random.md#seed), so the same seed always gives the same packing.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/ShapePacking-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/ShapePacking.jpg" alt="Two panels of the same dense packing of dark triangles, squares, hexagons, and four- and five-pointed stars on cream. The left panel also draws each shape's bounding circle in faint gray, and those circles visibly overlap and cross each other. The right panel shows the shapes alone, with small stars tucked into the notches of larger shapes" width="680">
</picture>

### Contents

- [packShapes](#pack)
- [Continuous packing (animated)](#continuous)
- [From a set of points](#around)
- [Building the shape bag](#bag)

<a name="pack"></a>

#### packShapes

```swift
packShapes(_ shapes: [Shape], in bounds: Rectangle? = nil,
           count: Int, minRadius: Double, maxRadius: Double = .infinity,
           padding: Double = 0, rotation: ClosedRange<Double> = 0 ... Double.tau,
           scale: Double = 1) -> [Shape]
```

Pack up to `count` shapes into `bounds`, which is the canvas by default. `minRadius` is the smallest shape to place, measured by bounding-circle radius, and `maxRadius` caps the largest. `padding` opens a gap between shapes. `rotation` is a range of angles in radians. `packShapes` turns each shape by a random angle from that range, so `0 ... 0` leaves every shape upright. `scale` is how much of its bounding circle a shape fills. At `1` the shape touches the circle, and anything less leaves a margin.

```swift
seed(4)
let bag = [triangle, square, pentagon, star]
for shape in packShapes(bag, count: 500, minRadius: 6, maxRadius: 120, padding: 4, scale: 0.9) {
    fill(.white); drawShape(shape)
}
```

Compute the packing once and hold it in a stored property. Then animate something visual, such as each shape's color, so the drawing moves without the shapes jumping.

<a name="continuous"></a>

#### Continuous packing (animated)

`packShapes` fills the region in one call. `ContinuousPacking` runs the same packing, but it stays open across frames. You call `step()` on it each frame, so the packing *fills in over time*. Big gaps fill first, so each new shape is smaller than the last. The region therefore grows denser over time, from a few large shapes to a scatter of tiny ones.

```swift
ContinuousPacking(shapes: [Shape] = [], in: Rectangle, seed: UInt64 = 0,
                  minRadius: Double, maxRadius: Double, padding: Double = 0,
                  rotation: ClosedRange<Double> = 0 ... Double.tau, scale: Double = 1,
                  attemptsPerStep: Int = 10)
```

Pair it with accumulation by calling `noClear()`. A placed shape never moves, so each frame draws only the *new* shapes. Those are the ones added since the last frame, which you find from the growth in `packer.count`. The per-frame cost stays flat no matter how full the region gets.

```swift
let packer = ContinuousPacking(shapes: bag, in: bounds, seed: 4,
                               minRadius: 3, maxRadius: 130, padding: 4)

override func setup() { noClear() }
override func draw() {
    let start = packer.count
    packer.step()                       // add a few this frame
    for i in start ..< packer.count {   // draw only the new ones
        fill(.white); drawShape(packer.shapes[i])
    }
}
```

Pass an empty bag to pack plain circles instead, then read `packer.circles`. See the `ShapePacking` example.

<a name="around"></a>

#### From a set of points

Use the `around:` form to place *one* shape at each of a set of points, which gives you a scatter rather than a dense fill. Each shape's bounding circle grows until it touches the nearest other point, so a [blue-noise](./BlueNoise.md) set makes an even scatter with no overlaps.

```swift
seed(7)
let sites = poissonDisk(radius: 60)
for shape in packShapes(bag, around: sites, padding: 4) { fill(.white); drawShape(shape) }
```

<a name="bag"></a>

#### Building the shape bag

Any `Shape` works, so you decide what goes in the bag. You can use regular polygons, stars, glyphs from [`textToShapes`](../Drawing/Text.md), and booleans of other shapes. The packing sets each shape's position and size, so build each one at any convenient size around the origin. This function returns a regular polygon or a star:

```swift
func polygon(_ sides: Int, star: Bool = false) -> Shape {
    let count = star ? sides * 2 : sides
    let points = (0..<count).map { i -> Vector2 in
        let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
        let r = (star && i % 2 == 1) ? 0.46 : 1.0
        return Vector2(cos(a) * r, sin(a) * r)
    }
    return Shape(points, closed: true)
}

let bag = [polygon(3), polygon(4), polygon(6), polygon(5, star: true)]
```

---

Related: [`Circle packing`](./Packing.md) (the round case and its parameters), [`Blue noise`](./BlueNoise.md) (the even point set the `around:` form scatters over), and [`Geometry`](../Drawing/Geometry.md) (the `Shape` type, and the booleans the output feeds).
