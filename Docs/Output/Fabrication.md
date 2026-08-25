#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Fabrication`</sup>

---

## Fabrication

A `Mesh` is geometry, and geometry can be built. Writing one out as STL, OBJ, or 3MF is how a generated form leaves the screen. It turns up as an object you can hold, the counterpart of sending vector line-work to a [pen plotter](./Export.md#vector-svg).

```swift
sculpture.write(to: "sculpture.3mf")
```

That is the whole call. The format comes from the extension. The mesh is prepared on the way out, so what arrives is a solid rather than a picture of one.

### Size is yours to set

A `Mesh` carries bare numbers. A printer needs millimeters. The two are joined by declaring what one model unit means, and by scaling the mesh to the size you actually want:

```swift
sculpture.normalized(scale: 60).write(to: "pendant.3mf")             // 60 mm across
sculpture.normalized(scale: 6).write(to: "pendant.3mf", unit: .centimeter)
```

`normalized(scale:)` does the two things a build platform wants. It centers the mesh on the origin, and it fits the longest side to the size you ask for. The `unit` then says how to read those numbers. It defaults to millimeters, because that is how nearly everything reads a file that does not say.

Only 3MF records the unit. STL and OBJ have nowhere to put it. Declaring one for them changes nothing about the bytes, and a consumer reading either will assume millimeters.

### What happens on the way out

Four things, and a mesh coming from a sketch needs all of them:

- **Coincident vertices are merged.** Ollin's generators are flat-shaded: every triangle carries its own three corners so each face can hold its own normal, which means neighboring triangles share no vertex at all. Read as a solid, that is not a surface with holes in it, it is nothing but holes. The writers merge the duplicate corners first, which is what turns a bag of triangles into a skin.
- **Degenerate triangles are dropped.** A triangle with no area has no side facing out, and is a crack to anything working out what is inside.
- **The winding is settled against the mesh's own normals.** A surface can be shaded from one side and wound from the other, which is how a mesh built by extruding a profile usually arrives. The normals are the side you saw when you made it, so they win, judged over the whole surface by area so a few odd normals cannot outvote the body of it. A mesh carrying no normals is judged by the volume it encloses instead: a closed surface enclosing a negative volume is inside out.
- **The mesh is turned upright.** Ollin's world is y-up and fabrication is z-up, so the writers rotate the mesh a quarter turn about x and a model that stood up in the sketch stands up on the platform. Pass `upAxis: .y` to leave the coordinates exactly as authored, which is what you want when the mesh is headed back into a graphics tool rather than onto a printer.

### Choosing a format

| | carries | reach for it when |
|---|---|---|
| `.3mf` | units, an explicitly manifold mesh, compressed | the mesh is going to be built |
| `.stl` | triangles only, no units, no shared vertices | something in the way only reads STL |
| `.obj` | triangles with shared vertices, text, no units | the mesh is going somewhere to be edited |

3MF is the one to prefer. It records the size you meant, and it states that the mesh is a solid rather than leaving that to be inferred. It also compresses. A 9,360-triangle knot that is 457 KB of STL and 291 KB of OBJ is 118 KB of 3MF.

STL is the format everything reads, which is its whole argument. It repeats each triangle's corners rather than sharing them. A consumer has to weld it back together to know what is joined to what.

OBJ is text, so it stays readable and editable, and it keeps shared vertices. It is written as geometry only, without normals. Any consumer works those out from the triangles. Writing them would mean one of two bad trades. A merged corner would get one averaged normal, which rounds off the very edges the merge just joined. The other trade is to unpick the shared vertices, and those are what make the mesh a solid.

### Asking before you write

A printer has to decide what is inside the surface and what is outside. On screen an open or inside-out mesh looks exactly as convincing as a closed one. So this is a check your eyes cannot do for you:

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

`MeshPrintCheck` reports `isClosed`, `isConsistentlyOriented`, `isInsideOut`, the `boundaryEdgeCount` (edges with a hole on one side), the `nonManifoldEdgeCount` (edges where more than two triangles meet), the `degenerateTriangleCount`, and the `size` and `volume` the file will describe. `problems` puts whatever went wrong in plain words, and `isPrintable` is all of it at once.

Everything it reports describes the mesh *as it would be written*, after the merging and the winding pass. So the counts will not match the mesh's own `positions` and `triangleCount`. That is deliberate. On the raw numbers every Ollin generator would read as broken.

A mesh that fails the check is still written, with a note saying so. An open surface is a perfectly good thing to draw, and only fabrication needs it closed.

### What makes a shape closed

Some generators produce closed surfaces by construction, and starting from one is much easier than repairing an open one:

- [`Metaballs`](../Generators/Isosurface.md) and `isosurface(at:in:resolution:field:)`, which close by definition: the surface is where a field crosses a level, and a field has an inside.
- The solid primitives, `Mesh.box`, `.sphere`, `.icosphere`, `.torus`, `.torusKnot`, `.capsule`, and the rest of the [catalog](../3D/3D.md).
- `Mesh.tube(along:radius:sides:closed:)` with `closed: true`, which joins the last ring back to the first so the tube has no ends.
- [`reconstructSurface`](../Generators/SurfaceReconstruction.md) over a point cloud that covers its subject from every side. Partial coverage leaves the surface open where the data stops, which is honest rather than broken.

`Mesh.plane`, a lathe or extrusion without caps, and a tube with open ends are all open surfaces, and a printer will say so.

### What is not written

Vertex colors, uvs, and materials are dropped. All three formats in their base form carry geometry, and what a printer builds is the surface. A multi-material or full-color print needs the 3MF extensions that describe them, which Ollin does not write yet.

### Worked example

`Examples/3D/Geometry/Fabrication` builds a torus knot you can tune and save, with the check drawn next to it. Turning its `sealed` knob off opens the tube's ends: the shape on screen barely changes, and the report underneath turns red.

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

`MeshFileFormat` is `.stl`, `.obj`, `.threeMF`, each with a `fileExtension`, and `init?(fileExtension:)` for going the other way. `ModelUnit` is `.micron`, `.millimeter`, `.centimeter`, `.inch`, `.foot`, `.meter`, each reporting its size in `millimeters`. `UpAxis` is `.z` (upright, the default) or `.y` (as authored).

Writing is deterministic. The same mesh written twice gives the same bytes, package timestamps included. So a generated model can be compared and committed like any other artifact.

---

Next: [Export](./Export.md) for getting frames and vector line-work out of the window, [3D](../3D/3D.md) for the mesh catalog these are written from, and [Isosurfaces and metaballs](../Generators/Isosurface.md) for generating closed shapes to begin with.
