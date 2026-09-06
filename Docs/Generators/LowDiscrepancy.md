#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Low-discrepancy sampling`</sup>

---

## Low-discrepancy sampling

Plain [`random`](./Random.md) scatter clumps and leaves holes. [Blue noise](./BlueNoise.md) fixes the spacing, but it gives you one fixed layout for one radius. A **low-discrepancy sequence** is the third option. It is an ordered, deterministic *stream* of points that covers a region evenly at **every** count. Growing the count only adds points, and never moves the ones already placed.

That *prefix property* is the point of the whole technique. Draft a piece with 100 points and render it with 10,000, and the draft is a subset of the final render. There is no seed and no random number generator anywhere, because you pass in an index and get back a point.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/HaltonGrowth-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/HaltonGrowth.jpg" alt="Three panels showing the first 40, 160, and 640 points of one Halton sequence; the earlier points appear in identical positions in every panel, drawn dark, while the new points fill the remaining gaps in orange" width="680">
</picture>

### Contents

- [haltonPoints](#haltonPoints)
- [sobolPoints](#sobolPoints)
- [halton (the 1D scalar)](#halton)
- [Choosing between them](#choosing)
- [Standalone (outside a sketch)](#standalone)

<a name="haltonPoints"></a>

#### haltonPoints

```swift
haltonPoints(count: Int,
             in bounds: Rectangle? = nil,
             bases: (Int, Int) = (2, 3),
             startIndex: Int = 1) -> [Vector2]
```

This returns the first `count` points of the 2D Halton sequence, scaled into `bounds`. `bounds` is the whole canvas by default. Each axis mirrors the point's index digits in its own base, and with **coprime** bases the two axes stay uncorrelated. The defaults, 2 and 3, are the canonical pair. Bases that share a factor collapse the points onto lines.

```swift
for (i, p) in haltonPoints(count: 800).enumerated() {
    fill(Colormap.viridis.color(at: halton(i + 1, base: 5)))
    drawCircle(center: p, radius: 4)
}
```

`startIndex` defaults to 1 because index 0 of every Halton sequence is exactly 0, which is a point pinned in the corner.

<a name="sobolPoints"></a>

#### sobolPoints

```swift
sobolPoints(count: Int,
            in bounds: Rectangle? = nil,
            startIndex: Int = 1) -> [Vector2]
```

This returns the first `count` points of the 2D Sobol sequence, which is the more uniform of the two. Its binary construction gives it a stronger guarantee. Every aligned power-of-two block of the stream lands exactly one point in each cell of the matching power-of-two grid. It has the same prefix property and the same determinism as Halton, with slightly more visible dyadic structure if you look closely.

<a name="halton"></a>

#### halton (the 1D scalar)

```swift
halton(_ index: Int, base: Int = 2) -> Double   // a value in [0, 1)
```

This is the scalar building block, the radical inverse. Use it on its own whenever you want a 1D stream that fills the unit interval evenly. Uses include spacing hues around a wheel, offsetting animation phases, and picking sample times. `halton(i)` for i = 1, 2, 3, 4… yields 1/2, 1/4, 3/4, 1/8…, and each value lands in the largest gap left so far.

<a name="choosing"></a>

#### Choosing between them

- **Need the count to grow or shrink live, or to draft then refine?** Use a sequence, either one. This is the prefix property, and neither blue noise nor `random` has it.
- **Want the most even single layout, and the count is free?** Use [`poissonDisk`](./BlueNoise.md). Its minimum-distance guarantee is stronger than either sequence.
- **Want honest clumps?** Use plain [`random`](./Random.md), because clumping is a look of its own.

Both sequences are pure functions of the index, so they do not consume the sketch's seeded `random` and never affect reproducibility.

<a name="standalone"></a>

#### Standalone (outside a sketch)

The free functions take an explicit rectangle:

```swift
let points = haltonPoints(count: 500, in: Rectangle(x: 0, y: 0, width: 400, height: 300))
let finer = sobolPoints(count: 5000, in: bounds)
```

---

Related: [`Blue noise`](./BlueNoise.md) (the fixed-layout even scatter), [`Random`](./Random.md) (seeded uniform scatter), [`Stippling`](./Stippling.md) (density-weighted placement), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (turn any point set into cells).
