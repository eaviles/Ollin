#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Blue noise`</sup>

---

## Blue noise

Plain [`random`](./Random.md) scatter clumps, so some points land almost on top of each other while elsewhere gaps open up. **Blue-noise** (Poisson-disk) sampling fixes that by laying down points spread *evenly but organically*, with **no two closer than a radius** and no visible clustering. It's the distribution behind natural-looking stippling, object scatter, and the even seed sets the [Voronoi](../Drawing/Voronoi.md) and packing paths like to consume.

`poissonDisk` is Bridson's dart-throwing sampler, and it's driven by the seedable `random`, so the same [`seed`](./Random.md#seed) always lays the points down the same way.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/ScatterCompare-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/ScatterCompare.jpg" alt="Two panels with the same number of dots: on the left plain random placement with clumps and bare gaps, on the right a blue-noise scatter, even but organic" width="680">
</picture>

### Contents

- [poissonDisk](#poissonDisk)
- [Feeding the tessellators](#feeding)
- [Standalone (outside a sketch)](#standalone)

<a name="poissonDisk"></a>

#### poissonDisk

```swift
poissonDisk(in bounds: Rectangle? = nil,
            radius: Double,
            candidates: Int = 30,
            maxCount: Int? = nil) -> [Vector2]
```

A blue-noise scatter of `bounds` (the whole canvas by default), with points spread evenly and no two closer than `radius`. The number of points follows from `radius` and the area rather than being requested directly (halving the radius roughly quadruples the points). Pass `maxCount` to stop once enough have landed. `candidates` is how many darts are thrown around each point before it's retired (Bridson's `k`, 30 by default, and more is slightly tighter and slower).

```swift
seed(9)
let dots = poissonDisk(radius: 22)
noStroke(); fill(.black)
drawPoints(dots, size: 4)
```

Because the layout is a pure function of the seed, compute it once and hold it (in a stored property) rather than every frame, then animate something visual (a dot's size, its color) so the field moves without the points jumping. See the `BlueNoise` example.

<a name="feeding"></a>

#### Feeding the tessellators

The output is an ordinary `[Vector2]`, so it drops straight into [`voronoi`](../Drawing/Voronoi.md) or `delaunay`. Blue-noise sites give strikingly uniform cells with **no Lloyd relaxation needed**, since the even spacing is already there:

```swift
seed(9)
let sites = poissonDisk(radius: 30)
for (i, cell) in voronoi(sites).cells.enumerated() {
    fill(Colormap.viridis.color(at: Double(i) / Double(sites.count)))
    drawShape(cell)
}
```

<a name="standalone"></a>

#### Standalone (outside a sketch)

The `Sketch` method is sugar over a free function that takes any random source, so geometry code outside a sketch can sample reproducibly too. Hand it a seeded [`SplitMix64`](./Random.md), Ollin's PRNG:

```swift
var rng = SplitMix64(seed: 9)
let points = poissonDisk(in: bounds, radius: 24, using: &rng)
```

---

Related: [`Random`](./Random.md) (uniform scatter and the `randomVector`/`ring` helpers), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (tessellate the points into cells and meshes).
