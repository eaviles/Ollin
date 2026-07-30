#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Hulls`</sup>

---

## Hulls

Three answers to "what shape are these points?", in rising fidelity. [`convexHull`](../Drawing/Geometry.md#convex-hull) snaps a rubber band around a scatter; **`concaveHull`** lets the band sink into the gulfs between clusters while staying one simple polygon with every point inside; and **`alphaShape`** rolls a probe disk over the points and keeps only what the disk can't pass through, so the same scatter can come back as several islands with holes. The concave hull is the characteristic-shape ("chi-shape") construction of Duckham, Kulik, Worboys, and Galton; the alpha shape is Edelsbrunner's alpha complex. Both are carved out of the same [Delaunay triangulation](../Drawing/Voronoi.md#delaunay) that powers Voronoi diagrams and the spanning tree.

```
  the scatter          convexHull          concaveHull          alphaShape

   ···   ··            _________           __    ___            ___    __
  ·····  ···          /         \         /  \__/   \          (···)  (··)
   ···   ··           \_________/         \____   __/           (·)    --
                     one taut band       dips the gulfs      islands and holes
```

The results are ordinary geometry: the hull comes back as points to wrap in a `Contour` or `Shape`, the alpha shape as ready `Shape`s, so both feed `drawPolygon`/`drawShape`, the [booleans](../Drawing/Geometry.md#shape-booleans), [hatching, and SVG export](../Output/Export.md) directly.

### Contents

- [concaveHull](#concave)
- [alphaShape](#alpha)
- [Practical notes](#notes)

<a name="concave"></a>

#### concaveHull

```swift
concaveHull(of points: [Vector2], concavity: Double = 0.5) -> [Vector2]
```

One simple polygon that follows the scatter's actual outline instead of bridging its gulfs, with every input point inside or on it. `concavity` runs `0...1`: 0 is the convex hull, 1 hugs the points as tightly as their spacing allows, and values between slide smoothly from one to the other. Like `convexHull`, the return is the boundary points in order.

```swift
let outline = concaveHull(of: scatter, concavity: 0.7)
noFill()
stroke(.black)
drawPolygon(outline)
```

Under the hood the Delaunay triangulation's border triangles erode longest-boundary-edge-first, but a triangle may only go while the polygon stays simple, which is also what keeps every point inside. The knob interpolates a length threshold between the triangulation's shortest and longest edge, so it's scale-free: the same value reads the same on a 400-pixel sketch and a 4000-pixel export.

<a name="alpha"></a>

#### alphaShape

```swift
alphaShape(of points: [Vector2], alpha: Double) -> [Shape]
```

The scatter's true footprint at the scale of a probe disk with radius `alpha` (in the same units as the points): every Delaunay triangle whose circumcircle the probe can't enter is kept, and the boundary of what remains is the alpha shape. Unlike the hulls it can split apart and carry holes, so it returns one `Shape` per island, each with its outer contour first and any hole contours after (even-odd).

```swift
for island in alphaShape(of: scatter, alpha: 40) {
    fill(.gray)
    drawShape(island)
}
```

Small `alpha` dissolves the scatter into dust (an empty array at the extreme); large `alpha` approaches the convex hull. A good starting value is a bit above the typical spacing between neighboring points.

<a name="notes"></a>

#### Practical notes

- **Pick the tool by the question.** One outline that must stay a simple polygon (a plotter path, a clip region, a shape to offset): `concaveHull`. The honest footprint of a clustered scatter (islands, holes): `alphaShape`. The loosest wrap: `convexHull`.
- **`concavity` near 1 goes labyrinthine.** The tightest setting erodes every bridge wider than the closest pair, which reads as a maze rather than an outline. The expressive range for "hug the clusters" sits around `0.5...0.8`.
- **`alpha` is a radius, in point units.** Below the local point spacing the shape crumbles; a couple of spacings gives a snug footprint; the hole in a ring survives as long as `alpha` stays below the hole's inradius.
- **Both are deterministic** given the points: same scatter, same knob, same output, on any run. Cost is the Delaunay build plus near-linear work on top, comfortable at tens of thousands of points.
- **Erosion only shrinks.** Raising `concavity` never grows the hull, so a knob sweep animates cleanly from band to wrap (the `Shapes/Hulls` example breathes exactly this).

---

Related: [`Geometry`](../Drawing/Geometry.md#convex-hull) (`convexHull`, the booleans, `Shape.contains`), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (the triangulation underneath), [`Medial axis`](./MedialAxis.md) (the skeleton these regions collapse to), [`Export`](../Output/Export.md) (SVG and the plotter path).
