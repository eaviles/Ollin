#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Low-discrepancy sampling`</sup>

---

## Low-discrepancy sampling

Plain [`random`](./Random.md) scatter clumps and leaves holes. [Blue noise](./BlueNoise.md) fixes the spacing, but it's one fixed layout for one radius. A **low-discrepancy sequence** is the third option: an ordered, deterministic *stream* of points that covers a region evenly at **every** count, where growing the count only adds points and never moves the ones already placed.

```
  haltonPoints(count: 4)          haltonPoints(count: 8)

    ·         ·                     · ·       · ·
                          →
         ·         ·                  ·  ·      ·  ·

  the first 4 points of the longer run are the same 4 points,
  in the same places; the new ones land in the largest gaps
```

That *prefix property* is the whole trick: draft a piece with 100 points and render it with 10,000, and the draft is a subset of the final. There's no seed and no rng anywhere; index in, point out.

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

The first `count` points of the 2D Halton sequence, scaled into `bounds` (the whole canvas by default). Each axis mirrors the point's index digits in its own base; with **coprime** bases the two axes stay uncorrelated. The defaults (2 and 3) are the canonical pair; don't pass bases that share a factor, or the points collapse onto lines.

```swift
for (i, p) in haltonPoints(count: 800).enumerated() {
    fill(Colormap.viridis.color(at: halton(i + 1, base: 5)))
    drawCircle(center: p, radius: 4)
}
```

`startIndex` defaults to 1 because index 0 of every Halton sequence is exactly 0, a point pinned in the corner.

<a name="sobolPoints"></a>

#### sobolPoints

```swift
sobolPoints(count: Int,
            in bounds: Rectangle? = nil,
            startIndex: Int = 1) -> [Vector2]
```

The first `count` points of the 2D Sobol sequence, the more uniform sibling. Its binary construction gives it a stronger guarantee: every aligned power-of-two block of the stream lands exactly one point in each cell of the matching power-of-two grid. Same prefix property, same determinism, slightly more visible dyadic structure if you look closely.

<a name="halton"></a>

#### halton (the 1D scalar)

```swift
halton(_ index: Int, base: Int = 2) -> Double   // a value in [0, 1)
```

The scalar building block (the radical inverse), useful on its own whenever you want a 1D stream that fills the unit interval evenly: spacing hues around a wheel, offsetting animation phases, picking sample times. `halton(i)` for i = 1, 2, 3, 4… yields 1/2, 1/4, 3/4, 1/8…, each value landing in the largest gap left so far.

<a name="choosing"></a>

#### Choosing between them

- **Need the count to grow or shrink live, or draft-then-refine?** A sequence (either one); that's the prefix property, and neither blue noise nor `random` has it.
- **Want the most even single layout and the count is free?** [`poissonDisk`](./BlueNoise.md); its minimum-distance guarantee is stronger than either sequence.
- **Want honest clumps?** Plain [`random`](./Random.md); clumping *is* a look.

Both sequences are pure functions of the index, so they don't consume the sketch's seeded `random` and never affect reproducibility.

<a name="standalone"></a>

#### Standalone (outside a sketch)

The free functions take an explicit rectangle:

```swift
let points = haltonPoints(count: 500, in: Rectangle(x: 0, y: 0, width: 400, height: 300))
let finer = sobolPoints(count: 5000, in: bounds)
```

---

Related: [`Blue noise`](./BlueNoise.md) (the fixed-layout even scatter), [`Random`](./Random.md) (seeded uniform scatter), [`Stippling`](./Stippling.md) (density-weighted placement), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (turn any point set into cells).
