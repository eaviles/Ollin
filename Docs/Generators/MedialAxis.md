#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Medial axis`</sup>

---

## Medial axis

**`medialAxis`** reduces a shape to its skeleton. The skeleton is the set of centers of every disk that fits inside the region and touches its boundary twice or more. Blum called that set the medial axis. A blob reduces to the lines running down the middle of its lobes. A letterform reduces to the stroke of the pen that could have written it. Every skeleton point carries the radius of its own inscribed disk, so the skeleton also records how thick the shape is at that point. You can stroke the branches for plain line work, size marks by the radii, or draw the disks themselves for a packed, cellular fill.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/Skeleton-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/Skeleton.jpg" alt="Two panels of the same lobed blob: on the left its medial axis as branching lines down the middle of each lobe, on the right the inscribed disks those branches carry, each disk touching the outline" width="680">
</picture>

The skeleton comes back as polyline branches. The open runs join branch points, and a closed ring goes around each hole. Those branches feed `drawPolyline` and [hatching and SVG export](../Output/Export.md) directly, so each branch is one pen-down stroke on a plotter.

### Contents

- [medialAxis](#extract)
- [MedialAxis and Branch](#types)
- [Practical notes](#notes)

<a name="extract"></a>

#### medialAxis

```swift
medialAxis(of shape: Shape, spacing: Double = 4, prune: Double = 0) -> MedialAxis
```

`medialAxis` returns the skeleton of `shape`, approximated the standard way. It samples the boundary every `spacing` units. It then builds the Voronoi diagram of those samples and keeps exactly the edges that run between non-neighboring samples without leaving the region. The result converges to the true axis as `spacing` shrinks, so a finer spacing gives a more faithful skeleton and costs more setup work.

`prune` removes the stray twigs. It drops any terminal twig shorter than its value, measured in shape units. That clears the side branches that boundary corners and sampling noise grow. A couple of spacings is a good starting value. Passing 0 keeps the exact approximation, corner branches and all.

```swift
let skeleton = medialAxis(of: blob, spacing: 3, prune: 6)
noFill()
stroke(.black)
for branch in skeleton.branches {
    drawPolyline(branch.points, closed: branch.isClosed)
}
```

Holes are kept, and the skeleton ring around each hole comes back as a closed branch. A shape with several contours is skeletonized region by region, and glyph shapes from [`textToShapes`](../Drawing/Text.md) work as they are, counters included. Extraction belongs at setup time, so run it once in `setup()` and hold the result.

<a name="types"></a>

#### MedialAxis and Branch

| Member | Meaning |
|---|---|
| `axis.branches` | the skeleton as `Branch` values, in a fixed, reproducible order |
| `axis.contours` | every branch as a plain `Contour`, without the radii |
| `branch.points` | the polyline vertices of the branch |
| `branch.radii` | the inscribed-disk radius at each point, 1:1 with `points`, which is the local half-thickness of the shape |
| `branch.isClosed` | whether the branch loops (a hole's ring does) |
| `branch.contour` | the branch as a `Contour`, ready for `drawPolyline`, smoothing, or export |

The radii carry the thickness that a line drawing on its own does not have. The largest radius marks the deepest point of the shape, where the biggest disk fits. Walk a branch and call `drawCircle(center: p, radius: r)` at each point, and the shape comes back as a row of inscribed disks.

<a name="notes"></a>

#### Practical notes

- **Prune with a couple of spacings.** The raw approximation grows a twig into every convex corner. That twig is part of the true axis rather than a bug, and sampling noise adds more twigs on top. Set `prune: 2 * spacing` to keep the main lines and drop the rest. A branch that is a component on its own is never pruned away, so small regions keep their skeletons.
- **Spacing sets cost and fidelity together.** Most of the cost is the Delaunay build over the boundary samples. A 1000-sample boundary extracts in well under a second, so using it per glyph or per blob in `setup()` is comfortable. Halving `spacing` roughly quadruples the work.
- **The radii are exact clearances** to the sampled boundary. Each skeleton vertex is a Voronoi vertex, so it sits the same distance from each of its nearest samples. A disk drawn from one of them therefore touches the outline instead of crossing it.
- **Deterministic** given the shape. The same shape and the same parameters give the same branches in the same order on any run.

---

Related: [`Hulls`](./Hulls.md) (concave hulls and alpha shapes, the regions to skeletonize), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (the machinery underneath), [`Text`](../Drawing/Text.md) (`textToShapes`, letterforms as shapes), [`Export`](../Output/Export.md) (SVG and the plotter path).
