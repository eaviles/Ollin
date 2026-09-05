#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Blue noise`</sup>

---

## Blue noise

A plain [`random`](./Random.md) scatter clumps, so some points land almost on top of each other while gaps open up elsewhere. A **blue-noise** (Poisson-disk) scatter places the points *evenly but organically* instead, with **no two closer than a radius** and no visible clustering. It is the distribution behind natural-looking stippling and object scatter, and it gives the [Voronoi](../Drawing/Voronoi.md) and packing paths the even seed sets they prefer.

`poissonDisk` is Bridson's dart-throwing sampler. It runs on the seedable `random`, so the same [`seed`](./Random.md#seed) always places the points the same way.

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

Returns a blue-noise scatter of `bounds`, which is the whole canvas by default. The points are spread evenly, and no two are closer than `radius`. You do not ask for a number of points. That number follows from `radius` and the area, so halving the radius roughly quadruples the points. Pass `maxCount` to stop once enough points have landed. `candidates` is how many darts are thrown around each point before it is retired. That is Bridson's `k`, 30 by default, and a higher value packs the points slightly tighter and runs slower.

```swift
seed(9)
let dots = poissonDisk(radius: 22)
noStroke(); fill(.black)
drawPoints(dots, size: 4)
```

The layout is a pure function of the seed. Compute it once and keep it in a stored property rather than recomputing it every frame. Then animate something visual, such as a dot's size or its color, so the field moves without the points jumping. See the `BlueNoise` example.

<a name="feeding"></a>

#### Feeding the tessellators

The output is an ordinary `[Vector2]`, so it goes straight into [`voronoi`](../Drawing/Voronoi.md) or `delaunay`. The spacing is already even, so blue-noise sites give very uniform cells with **no Lloyd relaxation needed**:

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

The `Sketch` method wraps a free function that takes any random source, so geometry code outside a sketch can sample reproducibly too. Pass it a seeded [`SplitMix64`](./Random.md), which is Ollin's PRNG:

```swift
var rng = SplitMix64(seed: 9)
let points = poissonDisk(in: bounds, radius: 24, using: &rng)
```

---

Related: [`Random`](./Random.md) (uniform scatter and the `randomVector`/`ring` helpers), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (tessellate the points into cells and meshes).
