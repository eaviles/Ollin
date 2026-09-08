#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Isosurfaces</sup>

---

## Isosurfaces and metaballs

An isosurface is a contour line in three dimensions. The **`isosurface`** function takes any scalar field over space and builds the skin where that field crosses a level. It returns a `Mesh`, so you draw, light, and export it like any other mesh. **`Metaballs`** is the field to start with. It holds soft spheres whose values add, so the spheres bulge toward each other and fuse.

```swift
var blobs = Metaballs()
blobs.add(at: Vector3(-40, 0, 0), radius: 50)
blobs.add(at: Vector3(40 * sin(time), 0, 0), radius: 40)
drawMesh(blobs.mesh())
```

This is the same idea as [isolines](Isolines.md), one dimension up. There, a field over the plane traces closed curves. Here, a field over space encloses a solid.

<img src="../../Guide/Images/26-SculptingWithFields/FieldToMesh.jpg" alt="Two panels: a chain of three pale blobs fused by smooth necks, and the same form again as a light blue wireframe showing the triangles it is made of" width="680">

### Contents

- [Metaballs](#metaballs)
- [Any field at all](#fields)
- [Resolution and cost](#resolution)
- [Which side is inside](#inside)
- [How the march works](#march)
- [Sharp features: dual contouring](#sharp)
- [Practical notes](#notes)

<a name="metaballs"></a>

#### Metaballs

```swift
var field = Metaballs(level: 0.5)
field.add(at: center, radius: 50)
field.add(at: other, radius: 30, strength: 1.4)
let mesh = field.mesh(resolution: 56)
```

`radius` is the size a ball has **on its own**, so a single ball meshes to a sphere of exactly that radius. Bring a second ball within reach and the two fields add together. The value in the gap then rises above what either ball makes there alone. The surface swells across the gap, so the pair fuses into one skin. Pull the two apart and the bridge between them thins and breaks.

Three parameters control the merging:

| Parameter | Effect |
|---|---|
| `level` | The field value the surface is drawn at. A lower value fattens every ball and makes the balls merge from further apart. A higher value thins them and keeps them separate. |
| `strength` | How strongly one ball pushes. Above `1` the ball swells and reaches further. A **negative** value carves into its neighbors instead of joining them. |
| `radius` | The ball's own size, which also sets how far its influence carries. |

A ball's influence stops at a finite distance instead of trailing off forever. A ball on the far side of the scene therefore costs nothing, and the field has an exact extent. `mesh(resolution:)` uses that extent. It takes the box from the balls themselves and pads it, so the surface always closes instead of being clipped.

`value(at:)` reads the raw field and `bounds` reports the box, so a sketch can drive something else with them.

<a name="fields"></a>

#### Any field at all

`isosurface` works with numbers from any source:

```swift
let box = Box3(min: Vector3(-100, -100, -100), max: Vector3(100, 100, 100))

// A noise volume, carved into caves.
let caves = isosurface(at: 0.55, in: box, resolution: 64) { p in
    fbm(p.x * 0.01, p.y * 0.01, p.z * 0.01, octaves: 4)
}

// A gyroid, the classic triply-periodic surface.
let gyroid = isosurface(at: 0, in: box, resolution: 96) { p in
    let q = p * 0.05
    return cos(q.x) * sin(q.y) + cos(q.y) * sin(q.z) + cos(q.z) * sin(q.x)
}
```

Anything that returns one number per point works, such as a distance function, a physics field, an accumulated density, or a sampled volume.

<a name="resolution"></a>

#### Resolution and cost

`resolution` is how many cells fit across the **longest** side of the box, and the cells stay cubic. A long thin box therefore gets proportionally fewer cells across its short sides, rather than stretched ones. Cost grows with the cube of that number. Doubling it takes eight times as many field samples and roughly four times as many triangles.

The defaults are chosen so that a modest field rebuilds every frame comfortably. Past about 96, march once in `setup()` and keep the mesh, the way [terrain](Terrain.md) does.

<a name="inside"></a>

#### Which side is inside

**The surface encloses the region where the field is greater than `level`.** Normals point out of that region, and the triangles wind to match.

A signed distance function runs the other way, because it is negative inside. Negate it to mesh it:

```swift
isosurface(at: 0, in: box) { -myDistanceFunction($0) }
```

If you get this backwards, the mesh comes out inside out. It still draws, but it lights as if the light came from inside it.

<a name="march"></a>

#### How the march works

Marching cubes walks a grid of cubes over the box. Each corner of a cube is either inside the surface or outside it. Where an edge joins one inside corner to one outside corner, the surface crosses that edge. Interpolating the two corner values says where the crossing sits. Ollin then stitches those crossings into triangles, one cube at a time.

Some corner arrangements can be stitched in more than one way. If two neighboring cubes pick differently, the surface tears open along the face between them. Ollin settles each shared face by reading the four values on that face alone. Both cubes therefore reach the same answer, and the seam always closes. Ollin also welds vertices across cubes and takes their normals from the field's own gradient. A smooth field then gives a smooth surface with no shading facets.

<a name="sharp"></a>

#### Sharp features: dual contouring

Marching cubes puts every vertex on an edge of the grid. A corner of the field that falls inside a cube can therefore only come out as a bevel across it. A block reads as a pebble at any resolution you can afford. `method: .dualContouring` puts one vertex inside each cube instead, where the field's own normals say the surface is:

```swift
let block = isosurface(at: 0, in: box, resolution: 24, method: .dualContouring) { p in
    let q = Vector3(abs(p.x) - 1, abs(p.y) - 1, abs(p.z) - 1)
    let walls = Vector3(max(q.x, 0), max(q.y, 0), max(q.z, 0)).length + min(max(q.x, max(q.y, q.z)), 0)
    let bore = (p.x * p.x + p.y * p.y).squareRoot() - 0.5
    return -max(walls, -bore)
}
```

At every crossing it reads the point on the true surface and the field's normal there. Three faces meet at a corner, so the vertex lands on the corner. Two meet along an edge, so it lands on the edge. On a smooth patch it lands on the patch. Each crossed edge of the grid then becomes one quad joining the four cubes around it. A block's corners land exactly at any resolution, and a bored hole keeps its rim.

<img src="../../Guide/Images/26-SculptingWithFields/SharpFields.jpg" alt="Two panels: a block with a hole bored through it, its corners rounded off and the rim of its hole softened on the left, and the same block on the same coarse grid with square corners and a crisp rim on the right" width="680">

What it costs, and what to know:

- **More field calls.** Each crossing is refined onto the surface and its normal read there, about a dozen calls per crossing on top of the one per lattice point. The mesh is setup-shaped work either way.
- **Shading follows the creases.** A cube on a crease carries one vertex per side. A block's faces therefore shade flat right up to its edges, while a sphere still shades smooth. The mesh has more vertices than distinct positions where that happens.
- **It reads the field between the samples.** The refinement asks the field between lattice points, so a field that only exists at the samples cannot use it. `Metaballs.mesh()` and `reconstructSurface` stay on marching cubes, since a smooth field gains nothing from the corners.
- **A knife edge shows the grid.** Where two curved surfaces meet at a shallow angle, a cube can hold a sliver of one surface without any of its edges crossing the other. The crease steps by the cell there. Raise `resolution`, or keep such a meeting off the picture.
- **The default is unchanged.** No `method` reads as marching cubes, vertex for vertex.

<a name="notes"></a>

#### Practical notes

- **The mesh is watertight** wherever the surface stays inside `bounds`. Where the surface runs out through a wall, the mesh is left open there. A contour that leaves its rectangle comes back open in the same way. `Metaballs.mesh()` pads its box so that this doesn't happen.
- **It's deterministic.** The same field and the same arguments give the same mesh, vertex for vertex, so an animated blob's export is frame-accurate.
- **No texture coordinates.** A blob has no natural parameterization, so the mesh carries none. Use a [material](../3D/3D.md) rather than a texture.
- **A moving field is CPU work.** The [raymarched fields](../Drawing/Combinators.md) shade on the GPU instead, but they produce no geometry. Use a mesh when you need real geometry, to light with shadows, to export, or to hand to something else. Use a raymarched field when you only want it on screen.

### See also

- [Isolines](Isolines.md), the same idea one dimension down.
- The [SharpFields](../../Examples/3D/Geometry/SharpFields/) example, a bored block meshed both ways under a switch.
- [Terrain](Terrain.md), the other generator that returns a `Mesh`.
- [3D mode](../3D/3D.md), for drawing, lighting, and materials.
- [SDF combinators](../Drawing/Combinators.md), for fields shaded directly on the GPU.
