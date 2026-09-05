#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Subdivision surfaces</sup>

---

## Subdivision surfaces

Subdivision is the classic way to model something smooth out of almost nothing. **`mesh.subdivided(_:levels:)`** refines a coarse `Mesh`, which is called the *control cage*. Each level splits every face and moves every vertex toward a weighted average of its neighbors. After a few levels the faceted cage has converged to a soft, organic solid.

```swift
drawMesh(Mesh.box(size: 200).subdivided(levels: 3))            // the classic rounded cube

let star = Mesh.extrude(Profile.star(), depth: 0.5)
drawMesh(star.subdivided(levels: 3))                           // a puffy star
```

A dozen boxes and extrusions, subdivided, look like sculpture. The cage stays small and easy to edit, because the smoothness is computed rather than modeled.

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

Both schemes converge to a smooth limit surface, but they take different routes there. The quad rules rebuild the surface out of quads at each level, which is what gives the familiar rounded-cube look. The triangle rules split each triangle into four. The result is then moved the rest of the way to its limit positions. What you draw is therefore the surface the refinement is heading for.

<a name="cages"></a>

#### Cages that just work

`Mesh` generators emit flat-shaded, duplicated vertices, so a box is 24 vertices, four per face. A triangle mesh has no quads at all. `subdivided` repairs both of those before it refines:

- **Coincident vertices weld** into shared topology, so a box rounds as one closed surface instead of six plates that drift apart. The weld closes generator seams, and it closes the slight numeric error a triangulated cap carries. The tolerance is about a millionth of the mesh's extent.
- **Grid quads are recovered** from the exact triangle pattern the generators emit. A sphere, plane, or extrusion wall therefore subdivides on the quads it was meant to have, rather than on triangles biased along a diagonal.
- **Flat tessellated patches merge back into whole faces.** An extruded star's cap becomes the ten-sided polygon it is. A pentagon fan becomes a pentagon. Without the merge, the arbitrary diagonals of the triangulation would smooth one arm differently from the next. The merge is conservative, because it joins only neighbors that are exactly flat. A flat grid with interior vertices is therefore left alone, such as a `plane(segments: 8)` you tessellated on purpose.

Because of those repairs, any built-in primitive, extrusion, lathe, or loaded model works as a cage with no preparation.

<a name="boundaries"></a>

#### Open edges and corners

An open sheet does not shrink away, whether it is a `plane` or a capless `cylinder`. Its rim follows the matching B-spline curve rules, so the rim smooths *along* its own length rather than pulling inward off it. A corner with a single incident face holds its position exactly, so a sheet keeps its extent. Non-manifold edges, which more than two faces share, are treated as open edges.

<a name="levels"></a>

#### Levels and cost

Each level multiplies the face count by about four, so the cost climbs fast while the added smoothness stops being visible early. Level 2 or 3 is almost always enough, and past two million faces refinement stops early with a note. Subdivision is CPU work of the kind that belongs in `setup()`. Refine once and keep the mesh, or cache it and rebuild it when a parameter changes, rather than subdividing again every frame.

<a name="result"></a>

#### What the result carries

- **Smooth normals**, computed from the refined surface, so the mesh lights cleanly.
- **The cage's shading orientation.** Where the input carries normals, the output's winding and normals follow them, whichever way the source happened to wind.
- **No texture coordinates.** A welded and re-knit surface has no single parameterization to keep, so use a [material](../3D/3D.md) rather than a texture. The base `material` color carries over.
- **Per-vertex colors**, refined by the same rules the positions take. A painted cage therefore smooths into a painted surface, and the color follows the shape it was painted onto. A cage with no `colors` produces a mesh with none, which is the plain single-color path. Where two coincident cage vertices have different colors, the weld keeps the first. A smoothed surface has no hard edge left to carry the split.
- **Determinism.** The same cage and arguments give the same mesh, vertex for vertex.

### See also

- [Isosurfaces](Isosurface.md) and [Terrain](Terrain.md), the other generators that emit a `Mesh`.
- [3D mode](../3D/3D.md), for drawing, lighting, and materials.
- [Wireframe](../3D/3D.md), for showing the cage next to its smooth form.
