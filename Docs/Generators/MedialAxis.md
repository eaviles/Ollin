#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Medial axis`</sup>

---

## Medial axis

**`medialAxis`** reduces a shape to its skeleton: the curve traced by the centers of every disk that fits inside the region while touching the boundary in two or more places (Blum's medial axis). A blob collapses to its centerline veins, a letterform to the stroke of the pen that could have written it. Every skeleton point carries the radius of its inscribed disk, so the skeleton knows how fat the shape is everywhere along it: stroke the branches for pure line work, size marks by the radii, or draw the disks themselves for a packed, cellular fill.

```
  the shape                its medial axis

   ________                 ________
  /        \___            /        \___
 |   ___       \    →     |  ---·---    \       every · carries r,
 |  /   \      |          |  ring    ·--|       the inscribed-disk
  \ \___/     /            \  ---   /           radius there
   \_________/              \______/
```

The skeleton comes back as polyline branches (open runs between branch points; a closed ring around a hole), so it feeds `drawPolyline`, [hatching and SVG export](../Output/Export.md) directly: each branch is one pen-down stroke on a plotter.

### Contents

- [medialAxis](#extract)
- [MedialAxis and Branch](#types)
- [Practical notes](#notes)

<a name="extract"></a>

#### medialAxis

```swift
medialAxis(of shape: Shape, spacing: Double = 4, prune: Double = 0) -> MedialAxis
```

The skeleton of `shape`, approximated the standard way: the boundary is sampled every `spacing` units, and the Voronoi diagram of the samples keeps exactly the edges that run between non-neighboring samples without leaving the region, which converges to the true axis as `spacing` shrinks. Finer spacing, more faithful skeleton, more setup work.

`prune` trims the whiskers: terminal twigs shorter than it (in shape units) are removed, which cleans the side branches that boundary corners and sampling noise grow. A couple of spacings is a good starting value; 0 keeps the exact approximation, corner branches and all.

```swift
let skeleton = medialAxis(of: blob, spacing: 3, prune: 6)
noFill()
stroke(.black)
for branch in skeleton.branches {
    drawPolyline(branch.points, closed: branch.isClosed)
}
```

Holes are honored (their skeleton rings survive as closed branches), a multi-contour shape skeletonizes region by region, and glyph shapes from [`textToShapes`](../Drawing/Text.md) work as-is, counters included. Extraction is setup-time-shaped: run it once in `setup()` and hold the result.

<a name="types"></a>

#### MedialAxis and Branch

| Member | Meaning |
|---|---|
| `axis.branches` | the skeleton as `Branch` values, in a canonical, reproducible order |
| `axis.contours` | every branch as a plain `Contour`, radii dropped |
| `branch.points` | the branch's polyline vertices |
| `branch.radii` | the inscribed-disk radius at each point, 1:1 with `points`: the shape's local half-thickness |
| `branch.isClosed` | whether the branch loops (a hole's ring does) |
| `branch.contour` | the branch as a `Contour`, ready for `drawPolyline`, smoothing, or export |

The radii are what make the skeleton more than a line drawing. The largest radius marks the shape's deepest point (the biggest disk that fits anywhere); walking a branch and drawing `drawCircle(center: p, radius: r)` reconstructs the shape as a train of inscribed disks.

<a name="notes"></a>

#### Practical notes

- **Prune with a couple of spacings.** The raw approximation grows a twig into every convex corner (that's the true axis, not a bug) plus whiskers from sampling noise; `prune: 2 * spacing` keeps the trunk lines and drops the fuzz. A whole branch that is its own component never prunes away, so small regions keep their skeletons.
- **Spacing sets cost and fidelity together.** The Delaunay build over the boundary samples dominates; a 1000-sample boundary extracts in well under a second, so per-glyph or per-blob use in `setup()` is comfortable. Halving `spacing` roughly quadruples the work.
- **The radii are exact clearances** to the sampled boundary (each skeleton vertex is a Voronoi vertex, equidistant from its nearest samples), so disks drawn from them kiss the outline instead of crossing it.
- **Deterministic** given the shape: same shape, same knobs, same branches in the same order, on any run.

---

Related: [`Hulls`](./Hulls.md) (concave hulls and alpha shapes, the regions to skeletonize), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (the machinery underneath), [`Text`](../Drawing/Text.md) (`textToShapes`, letterforms as shapes), [`Export`](../Output/Export.md) (SVG and the plotter path).
