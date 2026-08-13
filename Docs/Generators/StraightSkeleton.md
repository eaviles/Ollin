#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Straight skeleton`</sup>

---

## Straight skeleton

**`straightSkeleton`** traces what happens when a shape's boundary shrinks inward at uniform speed, every edge sliding parallel to itself. Corners travel along straight lines, edges vanish, and spikes pinch off. The paths the corners take form the skeleton.

Where the [medial axis](MedialAxis.md) bends into curves around reflex corners, the straight skeleton stays piecewise straight. That is what makes it the geometry of *mitered insets*. The shrinking boundary at distance `d` is the shape inset by `d` with sharp corners, so one skeleton yields a whole ladder of concentric contours.

```
  the shape              its straight skeleton         inset(by: d)

  +----------+             +----------+                +----------+
  |          |             | \      / |                | +------+ |
  |          |      →      |  +----+  |                | |      | |
  |          |             | /      \ |                | +------+ |
  +----------+             +----------+                +----------+
                        corners run diagonals,       the wavefront at d,
                        edges meet on the ridge      corners still sharp
```

The skeleton also partitions the shape into one face per boundary edge. Raise every point to its inset distance and each face becomes a flat plane. That is the classic roof model, and a ready-made paneling of any polygon.

### Contents

- [straightSkeleton](#extract)
- [inset(by:)](#inset)
- [Arc and Face](#types)
- [Practical notes](#notes)

<a name="extract"></a>

#### straightSkeleton

```swift
straightSkeleton(of shape: Shape) -> StraightSkeleton
```

The straight skeleton of `shape`, computed exactly, with no boundary resampling. Every boundary vertex launches an arc, arcs meet at nodes, and each node carries the inset distance at which the wavefront reached it. Contours must be simple, non-crossing rings. Nesting decides which rings are holes, and an island inside a hole starts a fresh region.

```swift
let skeleton = straightSkeleton(of: island)
stroke(.black)
for arc in skeleton.arcs {
    drawLine(arc.start, arc.end)
}
```

Extraction is setup-time-shaped, so run it once in `setup()` and hold the result. Right angles, collinear runs, and symmetric shapes where many events land on one point are all handled crack-free. The faces always tile the shape exactly.

<a name="inset"></a>

#### inset(by:)

```swift
skeleton.inset(by distance: Double) -> Shape
```

The shape inset by `distance` with mitered corners, extracted from the skeleton without re-running anything. Each face is a flat plane in the roof model, so the inset is a straight cut through it. A deep inset splits where the shape pinches, turning one region into several rings. A hole's ring grows as the land around it thins. Past `skeleton.maxInset`, the depth at which the shape vanishes, the result is empty. `distance <= 0` returns the shape itself.

```swift
noFill()
stroke(.black)
for d in stride(from: 8.0, to: skeleton.maxInset, by: 8) {
    drawShape(skeleton.inset(by: d))
}
```

That loop is the topographic-contour look in four lines. Every ring is real geometry, so it feeds [SVG and PDF export](../Output/Export.md) directly, and concentric mitered fills are a classic pen-plotter pattern. The Clipper2-backed [`offset(by:)`](../Drawing/Geometry.md#shape-offset) stays the general tool, going outward as well as inward, with a choice of corner joins and fresh work per ring. The skeleton's inset is inward only and exact. Every corner keeps its true miter with no bevel cutoff, and the whole family comes from one build.

<a name="types"></a>

#### Arc and Face

| Member | Meaning |
|---|---|
| `skeleton.arcs` | every skeleton segment, deduplicated, in a canonical order |
| `skeleton.faces` | one `Face` per boundary edge, in boundary order |
| `skeleton.maxInset` | the largest inset distance before the shape vanishes |
| `arc.start` / `arc.end` | the segment's endpoints, `start` the shallower end |
| `arc.startDistance` / `arc.endDistance` | the inset distance at each endpoint (0 at a boundary vertex) |
| `face.edgeStart` / `face.edgeEnd` | the boundary edge the face grew from |
| `face.points` / `face.distances` | the face boundary and the inset distance at each point, 1:1 |
| `face.contour` | the face as a plain closed `Contour` |

`arc.startDistance == 0` separates the two kinds of line. Arcs rising off the boundary give one per vertex, the comb, while true interior ridges have both ends off the boundary. Faces shade naturally by depth:

```swift
noStroke()
for face in skeleton.faces {
    let depth = (face.distances.max() ?? 0) / skeleton.maxInset
    fill(Color.mix(.white, .black, t: depth))
    drawShape(Shape(face.points))
}
```

<a name="notes"></a>

#### Practical notes

- **Skeleton or medial axis?** The medial axis is the true "bones" of a shape, equidistant from the boundary with radii attached, and it comes from a boundary sampling. The straight skeleton is the mitered-offset structure, giving exact straight arcs, faces, and insets. For organic centerlines reach for [`medialAxis`](MedialAxis.md). For contour ladders, roof panelings, and anything a mitered inset drives, reach for `straightSkeleton`.
- **Every vertex grows an arc.** A densely sampled outline, such as a traced image or a resampled contour, grows one arc per sample point. That is the honest skeleton. For clean line work, simplify the outline first.
- **The inset ladder is cheap.** Building the skeleton does all the work. Each `inset(by:)` afterward is a linear pass over the faces, which is fine to call every frame at a moving distance.

The worked example is [`Examples/Shapes/StraightSkeleton`](../../Examples/Shapes/StraightSkeleton/Sketch.swift). It draws an island with a lake, its ridge network, and an animated contour ladder that splits where the land pinches.
