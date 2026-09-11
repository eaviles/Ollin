#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Hulls`</sup>

---

## Hulls

These are three answers to the question "what shape are these points?", each closer to the scatter than the last. The loosest is [`convexHull`](../Drawing/Geometry.md#convex-hull), which wraps a rubber band around a scatter. Then **`concaveHull`** lets that band sink into the gaps between clusters, and it stays one simple polygon with every point inside. Finally, **`alphaShape`** rolls a probe disk over the points and keeps only what the disk cannot pass through. The same scatter can therefore come back as several islands with holes.

In space the question has one answer rather than three: [`convexHull(of:)`](Fracture.md#hull) takes a cloud of `Vector3` and returns the solid around it as a `Mesh`.

The concave hull is the characteristic-shape construction of Duckham, Kulik, Worboys, and Galton, which is also called the chi-shape. The alpha shape is Edelsbrunner's alpha complex. Both are built from the same [Delaunay triangulation](../Drawing/Voronoi.md#delaunay) that Voronoi diagrams and the spanning tree use.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/HullTrio-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/HullTrio.jpg" alt="Three panels over one scatter of a dotted ring plus a small offshore cluster: the convex hull as one taut band around everything, the concave hull dipping a channel toward the cluster, and the alpha shape resolving the ring's hole and the island separately" width="680">
</picture>

Both results are ordinary geometry. The hull comes back as points, which you wrap in a `Contour` or a `Shape` yourself. The alpha shape comes back as ready `Shape`s. You can pass either one straight to `drawPolygon` and `drawShape`, to the [booleans](../Drawing/Geometry.md#shape-booleans), and to [hatching and SVG export](../Output/Export.md).

### Contents

- [concaveHull](#concave)
- [alphaShape](#alpha)
- [Practical notes](#notes)

<a name="concave"></a>

#### concaveHull

```swift
concaveHull(of points: [Vector2], concavity: Double = 0.5) -> [Vector2]
```

This returns one simple polygon that follows the actual outline of the scatter instead of bridging its gaps. Every input point lies inside that polygon or on it. `concavity` runs `0...1`. At 0 you get the convex hull, and at 1 the band hugs the points as tightly as their spacing allows. A value in between moves smoothly from one to the other. The return value is the boundary points in order, the same as for `convexHull`.

```swift
let outline = concaveHull(of: scatter, concavity: 0.7)
noFill()
stroke(.black)
drawPolygon(outline)
```

Internally, `concaveHull` erodes the border triangles of the Delaunay triangulation, longest boundary edge first. It removes a triangle only while the polygon stays simple, and that rule is also what keeps every point inside. The parameter interpolates a length threshold between the shortest and the longest edge of the triangulation, so it is scale-free. The same value reads the same on a 400-pixel sketch and on a 4000-pixel export.

<a name="alpha"></a>

#### alphaShape

```swift
alphaShape(of points: [Vector2], alpha: Double) -> [Shape]
```

This returns the true footprint of the scatter at the scale of a probe disk of radius `alpha`. The radius is measured in the same units as the points. The function keeps every Delaunay triangle whose circumcircle the probe cannot enter, and the boundary of what remains is the alpha shape. Unlike the hulls, this result can split apart and carry holes. It therefore returns one `Shape` per island, each with its outer contour first and any hole contours after it, wound even-odd.

```swift
for island in alphaShape(of: scatter, alpha: 40) {
    fill(.gray)
    drawShape(island)
}
```

A small `alpha` dissolves the scatter into dust, and at the extreme it returns an empty array. A large `alpha` approaches the convex hull. Start a little above the typical spacing between neighboring points.

<a name="notes"></a>

#### Practical notes

- **Pick the tool by the question.** For one outline that must stay a simple polygon, use `concaveHull`. That covers a plotter path, a clip region, or a shape to offset. For the honest footprint of a clustered scatter, islands and holes included, use `alphaShape`. For the loosest wrap, use `convexHull`.
- **`concavity` near 1 gets tangled.** The tightest setting erodes every bridge wider than the closest pair. What you get then reads as a maze rather than an outline. For a band that hugs the clusters, stay around `0.5...0.8`.
- **`alpha` is a radius, in point units.** Below the local point spacing, the shape crumbles. A couple of spacings gives a snug footprint. The hole in a ring survives as long as `alpha` stays below the inradius of that hole.
- **Both are deterministic** given the points. The same scatter and the same parameter give the same output on any run. The cost is the Delaunay build plus near-linear work on top of it, which stays comfortable at tens of thousands of points.
- **Erosion only shrinks.** Raising `concavity` never grows the hull, so a parameter sweep animates cleanly from band to wrap. The `Shapes/Hulls` example shows exactly that sweep.

---

Related: [`Geometry`](../Drawing/Geometry.md#convex-hull) (`convexHull`, the booleans, `Shape.contains`), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (the triangulation underneath), [`Medial axis`](./MedialAxis.md) (the skeleton these regions collapse to), [`Export`](../Output/Export.md) (SVG and the plotter path).
