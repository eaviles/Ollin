#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Fabrication`</sup>

---

## Fabrication

A `Mesh` is geometry, and geometry can be built. Writing a mesh out as STL, OBJ, or 3MF is how a generated form leaves the screen and becomes an object you can hold. This is the 3D counterpart of sending vector line-work to a [pen plotter](./Export.md#vector-svg).

```swift
sculpture.write(to: "sculpture.3mf")
```

That is the whole call. The format comes from the file extension. Ollin prepares the mesh on the way out, so the file describes a solid rather than a picture of one.

### Size is yours to set

A `Mesh` carries bare numbers, and a printer needs millimeters. To join the two, you declare what one model unit means, and you scale the mesh to the size you want:

```swift
sculpture.normalized(scale: 60).write(to: "pendant.3mf")             // 60 mm across
sculpture.normalized(scale: 6).write(to: "pendant.3mf", unit: .centimeter)
```

`normalized(scale:)` does the two things a build platform needs. It centers the mesh on the origin, and it fits the longest side to the size you ask for. The `unit` argument then says how to read those numbers. It defaults to millimeters, because nearly every consumer assumes millimeters when a file does not say.

Only 3MF records the unit. STL and OBJ have no place for it. Declaring a unit for them changes nothing in the bytes, and a consumer reading either format assumes millimeters.

### What happens on the way out

The writers do four things to the mesh, and a mesh coming from a sketch needs all of them:

- **Coincident vertices are merged.** Ollin's generators are flat-shaded. Every triangle carries its own three corners, so each face can hold its own normal. That means neighboring triangles share no vertex at all. Read as a solid, such a mesh has a hole at every edge, not a few holes in an otherwise closed surface. So the writers merge the duplicate corners first, which joins the separate triangles into one connected surface.
- **Degenerate triangles are dropped.** A triangle with no area has no side that faces out. Any tool working out what is inside the mesh reads that triangle as a crack in the surface.
- **The winding is corrected to match the mesh's own normals.** A surface can be shaded from one side and wound from the other. A mesh built by extruding a profile usually arrives that way. The normals are the side you saw when you made the mesh, so the writers keep the normals and set the winding to match. The writers judge them over the whole surface, weighted by area, so a few odd normals cannot outvote the body of the mesh. A mesh that carries no normals is judged by the volume it encloses instead. A closed surface that encloses a negative volume is inside out.
- **The mesh is turned upright.** Ollin's world is y-up, and fabrication is z-up, so the writers rotate the mesh a quarter turn about x. A model that stood up in the sketch then stands up on the build platform. Pass `upAxis: .y` to leave the coordinates exactly as authored. That is what you want when the mesh is going back into a graphics tool rather than onto a printer.

### Choosing a format

| | carries | reach for it when |
|---|---|---|
| `.3mf` | units, an explicitly manifold mesh, compressed | the mesh is going to be built |
| `.stl` | triangles only, no units, no shared vertices | a tool in the path only reads STL |
| `.obj` | triangles with shared vertices, text, no units | the mesh is going somewhere to be edited |

Prefer 3MF. It records the size you meant, and it states that the mesh is a solid instead of leaving a consumer to infer that. It also compresses. A 9,360-triangle knot that takes 457 KB as STL and 291 KB as OBJ takes 118 KB as 3MF.

STL is the format that everything reads, and that is its only advantage. It repeats each triangle's corners rather than sharing them. A consumer has to weld the triangles back together to know what is joined to what.

OBJ is text, so it stays readable and editable, and it keeps shared vertices. Ollin writes it as geometry only, without normals, because any consumer works those out from the triangles. Writing normals would force one of two bad trades. The first gives a merged corner one averaged normal, which rounds off the edges the merge just joined. The second splits the shared vertices apart again, and those shared vertices are what make the mesh a solid.

### Asking before you write

A printer has to decide what is inside the surface and what is outside. On screen, an open or inside-out mesh looks exactly as convincing as a closed one. So this is a check that your eyes cannot do for you:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/Fabrication-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/Fabrication.jpg" alt="Two identical-looking gold torus knots side by side; the left is labeled closed and ready to print, the right open at the ends with 36 edges bordering a hole" width="680">
</picture>

```swift
let check = sculpture.printCheck()
print(check.summary)          // "9360 triangles, 60.00 x 52.50 x 26.02 units: ready to print"

if check.isPrintable {
    sculpture.write(to: "sculpture.3mf")
} else {
    for problem in check.problems { print(problem) }
}
```

`MeshPrintCheck` reports `isClosed`, `isConsistentlyOriented`, and `isInsideOut`. It also reports three counts. The `boundaryEdgeCount` is the number of edges with a hole on one side. The `nonManifoldEdgeCount` is the number of edges where more than two triangles meet. The `degenerateTriangleCount` is the number of triangles with no area. It also reports the `size` and `volume` that the file will describe. `problems` lists whatever went wrong in plain words, and `isPrintable` combines all of it into one answer.

Everything it reports describes the mesh *as it would be written*, after the merging and the winding pass. So the counts will not match the mesh's own `positions` and `triangleCount`. That is deliberate, because on the raw numbers every Ollin generator would read as broken.

A mesh that fails the check is still written, with a note that says so. An open surface is a perfectly good thing to draw. Only fabrication needs it closed.

### What makes a shape closed

Some generators produce closed surfaces by construction. Starting from one of these is much easier than repairing an open surface:

- [`Metaballs`](../Generators/Isosurface.md) and `isosurface(at:in:resolution:field:)`. These close by definition, because the surface is where a field crosses a level, and a field has an inside.
- The solid primitives, `Mesh.box`, `.sphere`, `.icosphere`, `.torus`, `.torusKnot`, `.capsule`, and the rest of the [catalog](../3D/3D.md).
- `Mesh.tube(along:radius:sides:closed:)` with `closed: true`, which joins the last ring back to the first so the tube has no ends.
- [`reconstructSurface`](../Generators/SurfaceReconstruction.md) over a point cloud that covers its subject from every side. Partial coverage leaves the surface open where the data stops. That is the correct result, not a defect.

`Mesh.plane`, a lathe or extrusion without caps, and a tube with open ends are all open surfaces, and a printer will say so.

### What is not written

Vertex colors, uvs, and materials are dropped. All three formats carry only geometry in their base form, and a printer builds only the surface. A multi-material or full-color print needs the 3MF extensions that describe color and material, and Ollin does not write those yet.

### Worked example

`Examples/3D/Geometry/Fabrication` builds a torus knot that you can tune and save, and it draws the check next to the knot. Turning its `sealed` parameter off opens the tube's ends. The shape on screen barely changes, but the report underneath turns red.

```sh
swift run --package-path Examples Example-3D-Geometry-Fabrication
```

### Reference

```swift
mesh.write(to: url, as: MeshFileFormat? = nil, unit: ModelUnit = .millimeter, upAxis: UpAxis = .z) -> Bool
mesh.write(to: path, …)                  // same, taking a file path
mesh.data(as: .stl, unit:, upAxis:)      // the bytes, for handing on rather than writing
mesh.printCheck(upAxis: .z)              // what a printer will make of it

saveMesh(sculpture, to: "sculpture.3mf") // the sketch-level sugar, loadMesh's counterpart
```

`MeshFileFormat` is `.stl`, `.obj`, or `.threeMF`. Each has a `fileExtension`, and `init?(fileExtension:)` goes the other way. `ModelUnit` is `.micron`, `.millimeter`, `.centimeter`, `.inch`, `.foot`, or `.meter`, and each reports its size in `millimeters`. `UpAxis` is `.z` (upright, the default) or `.y` (as authored).

Writing is deterministic. The same mesh written twice gives the same bytes, package timestamps included. That means a generated model can be compared and committed like any other artifact.

---

Next: [Export](./Export.md) covers getting frames and vector line-work out of the window. The [3D](../3D/3D.md) page covers the mesh catalog these files are written from. The [Isosurfaces and metaballs](../Generators/Isosurface.md) page covers generating closed shapes to begin with.
