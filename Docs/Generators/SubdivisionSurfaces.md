#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Subdivision surfaces</sup>

---

## Subdivision surfaces

The classic way to model something smooth out of almost nothing. **`mesh.subdivided(_:levels:)`** refines a coarse `Mesh`, the *control cage*. Each level splits every face and eases every vertex toward a weighted average of its neighbors. After a few levels the faceted cage has converged to a soft, organic solid.

```swift
drawMesh(Mesh.box(size: 200).subdivided(levels: 3))            // the classic rounded cube

let star = Mesh.extrude(Profile.star(), depth: 0.5)
drawMesh(star.subdivided(levels: 3))                           // a puffy star
```

A dozen boxes and extrusions, subdivided, read as sculpture. The cage stays tiny and editable, and the smoothness is computed.

<img src="../../Guide/Images/22-Meshes/SubdivisionCage.jpg" alt="Three views of the same extruded five-pointed star: the control cage as a pale cyan wireframe, one level of subdivision as a plump amber star with soft edges, and two levels as a much softer orange form sitting inside the ghosted wireframe of the cage whose points now reach far past it" width="680">

### Contents

- [Two schemes](#schemes)
- [Cages that just work](#cages)
- [Open edges and corners](#boundaries)
- [Levels and cost](#levels)
- [What the result carries](#result)

<a name="schemes"></a>

#### Two schemes

| Scheme | Works on | Reach for it when |
|---|---|---|
| `.catmullClark` (default) | quads and any polygon | smoothing a modeled cage: boxes, extrusions, platonic solids |
| `.loop` | triangles | refining triangle-native geometry: an icosphere, a marching-cubes surface, a loaded scan |

```swift
mesh.subdivided(levels: 2)                 // quad rules
mesh.subdivided(.loop, levels: 2)          // triangle rules
```

Both converge to a smooth limit surface, by different routes. The quad rules rebuild the surface out of quads each level, which is what gives the familiar rounded-cube look. The triangle rules split each triangle into four. The result is then pushed the rest of the way to its limit positions. What you draw is therefore the surface the refinement is heading for.

<a name="cages"></a>

#### Cages that just work

`Mesh` generators emit flat-shaded, duplicated vertices, so a box is 24 vertices, four per face. A triangle mesh has no quads at all. `subdivided` repairs both before refining:

- **Coincident vertices weld** into shared topology, so a box rounds as one closed surface instead of six drifting plates. The weld closes generator seams and the slight numeric fuzz a triangulated cap carries. The tolerance is about a millionth of the mesh's extent.
- **Grid quads are recovered** from the exact triangle pattern the generators emit, so a sphere, plane, or extrusion wall subdivides on its intended quads rather than on diagonal-biased triangles.
- **Flat tessellated patches merge back into whole faces.** An extruded star's cap becomes the ten-sided polygon it is, and a pentagon fan becomes a pentagon. Without this, the triangulation's arbitrary diagonals would smooth one arm differently from the next. The merge is conservative. It only joins exactly flat neighbors, so a flat grid with interior vertices is left alone, such as a `plane(segments: 8)` you tessellated on purpose.

The upshot: any built-in primitive, extrusion, lathe, or loaded model works as a cage with no preparation.

<a name="boundaries"></a>

#### Open edges and corners

An open sheet doesn't shrink away, whether it is a `plane` or a capless `cylinder`. Its rim follows the matching B-spline curve rules, smoothing *along* the rim rather than pulling inward off it. A corner with a single incident face holds its position exactly, so a sheet keeps its extent. Non-manifold edges, shared by more than two faces, are treated as open edges.

<a name="levels"></a>

#### Levels and cost

Each level multiplies the face count by about four, so cost climbs fast and smoothness saturates early. Level 2 or 3 is almost always enough, and past two million faces refinement stops early with a note. Subdivision is CPU work shaped like `setup()`. Refine once and keep the mesh, or cache it and rebuild when a parameter changes, rather than re-subdividing every frame.

<a name="result"></a>

#### What the result carries

- **Smooth normals**, computed from the refined surface, so it lights cleanly.
- **The cage's shading orientation.** Where the input carries normals, the output's winding and normals follow them, whichever way the source happened to wind.
- **No texture coordinates.** A welded, re-knit surface has no single parameterization to keep, so use a [material](../3D/3D.md) rather than a texture. The base `material` color carries over.
- **Per-vertex colors**, refined by the same rules the positions take. A painted cage therefore smooths into a painted surface, and the color follows the shape it was painted onto. A cage with no `colors` produces a mesh with none, which is the plain single-color path. Where two coincident cage vertices were painted differently the weld keeps the first, since a smoothed surface has no hard edge left to carry the split.
- **Determinism.** The same cage and arguments give the same mesh, vertex for vertex.

### See also

- [Isosurfaces](Isosurface.md) and [Terrain](Terrain.md), the other generators that emit a `Mesh`.
- [3D mode](../3D/3D.md), for drawing, lighting, and materials.
- [Wireframe](../3D/3D.md), for showing the cage next to its smooth form.
