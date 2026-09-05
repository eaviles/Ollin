#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Straight skeleton`</sup>

---

## Straight skeleton

**`straightSkeleton`** takes a shape and shrinks its boundary inward at a uniform speed. Every edge slides parallel to itself. As the boundary shrinks, corners travel along straight lines, edges vanish, and spikes pinch off. The paths the corners travel form the skeleton.

The [medial axis](MedialAxis.md) bends into curves around reflex corners, but the straight skeleton is made of straight segments only. Because of that, it is the geometry of *mitered insets*. The shrunken boundary at distance `d` is the shape inset by `d` with sharp corners. So one skeleton gives you a ladder of concentric contours.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/InsetLadder-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/InsetLadder.jpg" alt="Two panels of the same pinched two-lobed blob: on the left the straight skeleton, faint lines rising from every corner into an accented ridge running lobe to lobe, and on the right a ladder of concentric mitered insets that separates into two nests of rings where the waist pinches" width="680">
</picture>

The skeleton also divides the shape into faces, one face per boundary edge. If you raise every point to its inset distance, each face becomes a flat plane. That is the classic roof model, and it gives you a ready-made paneling of any polygon.

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

Returns the straight skeleton of `shape`. The computation is exact, with no boundary resampling. Every boundary vertex starts an arc, and arcs meet at nodes. Each node carries the inset distance at which the shrinking boundary reached it. Contours must be simple rings that do not cross. Nesting decides which rings are holes, and an island inside a hole starts a new region.

```swift
let skeleton = straightSkeleton(of: island)
stroke(.black)
for arc in skeleton.arcs {
    drawLine(arc.start, arc.end)
}
```

Extraction is a one-time cost, so run it once in `setup()` and keep the result. `straightSkeleton` handles right angles, collinear runs, and symmetric shapes where many events land on one point, and it leaves no cracks. The faces always tile the shape exactly.

<a name="inset"></a>

#### inset(by:)

```swift
skeleton.inset(by distance: Double) -> Shape
```

Returns the shape inset by `distance` with mitered corners. The inset is read from the skeleton, so nothing is computed again. Each face is a flat plane in the roof model, which means the inset is a straight cut through each face. A deep inset splits where the shape pinches, so one region becomes several rings. A hole's ring grows as the shape around it gets thinner. `skeleton.maxInset` is the depth at which the shape vanishes, and past it the result is empty. `distance <= 0` returns the shape itself.

```swift
noFill()
stroke(.black)
for d in stride(from: 8.0, to: skeleton.maxInset, by: 8) {
    drawShape(skeleton.inset(by: d))
}
```

That loop draws contour lines like a topographic map in four lines. Every ring is vector geometry, so it goes to [SVG and PDF export](../Output/Export.md) directly, and concentric mitered fills are a classic pen-plotter pattern. The Clipper2-backed [`offset(by:)`](../Drawing/Geometry.md#shape-offset) is still the general tool. It goes outward as well as inward, it offers a choice of corner joins, and it does fresh work for each ring. The skeleton's inset goes inward only, and it is exact. Every corner keeps its true miter with no bevel cutoff, and the whole family of rings comes from one build.

<a name="types"></a>

#### Arc and Face

| Member | Meaning |
|---|---|
| `skeleton.arcs` | every skeleton segment, deduplicated, in a canonical order |
| `skeleton.faces` | one `Face` per boundary edge, in boundary order |
| `skeleton.maxInset` | the largest inset distance before the shape vanishes |
| `arc.start` / `arc.end` | the segment's endpoints, where `start` is the shallower end |
| `arc.startDistance` / `arc.endDistance` | the inset distance at each endpoint (0 at a boundary vertex) |
| `face.edgeStart` / `face.edgeEnd` | the boundary edge the face grew from |
| `face.points` / `face.distances` | the face boundary and the inset distance at each point, 1:1 |
| `face.contour` | the face as a plain closed `Contour` |

`arc.startDistance == 0` separates the two kinds of arc. An arc that rises off the boundary has `startDistance == 0`, and there is one per vertex, so together they form a comb along the boundary. A true interior ridge has both ends off the boundary. You can shade the faces by depth in a few lines:

```swift
noStroke()
for face in skeleton.faces {
    let depth = (face.distances.max() ?? 0) / skeleton.maxInset
    fill(Color.mix(.white, .black, depth))
    drawShape(Shape(face.points))
}
```

<a name="notes"></a>

#### Practical notes

- **Skeleton or medial axis?** The medial axis is the "bones" of a shape. It is equidistant from the boundary, each point carries a radius, and it comes from a boundary sampling. The straight skeleton is the mitered-offset structure, so it gives exact straight arcs, faces, and insets. Use [`medialAxis`](MedialAxis.md) for organic centerlines. Use `straightSkeleton` for contour ladders, roof panelings, and anything built from a mitered inset.
- **Every vertex grows an arc.** A densely sampled outline, such as a traced image or a resampled contour, grows one arc per sample point. That is the correct skeleton for that outline. For clean line work, simplify the outline first.
- **The inset ladder is cheap.** Building the skeleton does all the work. Each `inset(by:)` after that is a linear pass over the faces, so you can call it every frame with a moving distance.

The worked example is [`Examples/Shapes/StraightSkeleton`](../../Examples/Shapes/StraightSkeleton/Sketch.swift). It draws an island with a lake, its ridge network, and an animated contour ladder that splits where the land pinches.
