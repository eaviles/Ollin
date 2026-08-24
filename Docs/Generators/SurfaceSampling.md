#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Points on a surface`</sup>

---

## Points on a surface

Scattering points over a mesh: trees on an island, moss on a rock, roots for hair, a point cloud made from geometry. `surfacePoints` covers the **skin** evenly, which is not the same as covering the **vertex list** evenly.

The difference is the whole feature. A mesh puts vertices where its *shape* needs them, so a flat wall carries four and a rounded corner carries hundreds. Points picked from that list crowd the corner and leave the wall bare. Shuffling does not help, because the list itself is the wrong thing to draw from.

```
  Over the vertex list                  Over the surface

     ····•····                             ·    ·   ·
   ··•·······•··                         ·   ·    ·    ·
  ·             ·                       ·    ·   ·   ·  ·
  ·             ·                        ·     ·    ·   ·
  ·             ·                       ·   ·    ·    ·
   ··•·······•··                          ·    ·   ·   ·
     ····•····                             ·   ·    ·

  a globe's rings crowd at the poles,   a spot is as likely anywhere the
  so the poles fill and the middle      surface holds the same area, which
  goes bare                             is what the eye reads as even
```

<img src="../../Guide/Images/23-Landscapes/ScatteredSpots.jpg" alt="Three dark blue globes side by side, each wearing the same number of small green cone trees: the first crowded at the poles with a bare middle and trees standing in pairs, the second clumped with visible clearings, the third spread evenly all over" width="640">

Every point comes back as a `SurfaceSample`. It knows more than the spot: the direction the surface faces there, the texture coordinate, and the triangle it landed on.

### Contents

- [surfacePoints](#surfacePoints)
- [By spacing instead of count](#spacing)
- [SurfaceSample](#sample)
- [Standing something up](#alignment)
- [surfaceArea](#area)
- [Standalone (outside a sketch)](#standalone)

<a name="surfacePoints"></a>

#### surfacePoints

```swift
surfacePoints(on mesh: Mesh,
              count: Int,
              scatter: SurfaceScatter = .blueNoise) -> [SurfaceSample]
```

`count` points scattered over `mesh`, in proportion to area. A triangle twice the size of its neighbor receives about twice as many, whatever either one cost in vertices. Driven by the seeded [`random`](./Random.md), so [`seed`](./Random.md#seed) makes the layout repeat.

```swift
seed(3)
let spots = surfacePoints(on: island, count: 400)
drawMesh(tree, instances: spots.map {
    MeshInstance(position: $0.position, rotation: $0.alignment(spin: random(.tau)), scale: 0.4)
})
```

Two spreads:

| `scatter` | What it does | When |
|---|---|---|
| `.blueNoise` (default) | Keeps neighbors apart, so nothing clumps and nothing leaves a hole | Props, roots, stipple, anything the eye reads as *placed* |
| `.random` | Each point independent of the ones before it | Splatter, thrown seed, and any case where clumping is the look |

`.blueNoise` draws several times `count` candidates and thins the crowded ones out, so it costs a few times what `.random` costs. **Ask for the count you want** rather than trimming the result yourself. The thinning is what makes the spacing even, and cutting the list afterward undoes it.

The mesh is read in place. Nothing is welded or rebuilt first, so two triangles meeting at a seam are simply two triangles. A triangle with no area never receives a point.

<a name="spacing"></a>

#### By spacing instead of count

```swift
surfacePoints(on mesh: Mesh,
              spacing: Double,
              scatter: SurfaceScatter = .blueNoise) -> [SurfaceSample]
```

The same scatter asked the other way around, the way [`poissonDisk`](./BlueNoise.md) takes a radius. State the distance you want between neighbors, and the count follows from the surface area. Useful when the mesh changes size or resolution and the *density* is what should stay put.

```swift
let roots = surfacePoints(on: scalp, spacing: 0.01)   // a strand every centimeter
```

Under `.random` the spacing only decides how many points are drawn, since a plain draw keeps no distance from anything.

<a name="sample"></a>

#### SurfaceSample

```swift
struct SurfaceSample {
    var position: Vector3      // where it landed
    var normal: Vector3        // which way the surface faces there
    var uv: Vector2            // the texture coordinate there
    var triangle: Int          // which triangle, in the mesh's own numbering
    var barycentric: Vector3   // how much of each corner, adding to 1
}
```

`normal` is blended from the mesh's vertex normals when it carries them, and taken from the triangle's winding when it does not. `uv` is `Vector2.zero` on a mesh with no texture coordinates.

`triangle` and `barycentric` are there to blend anything else the mesh holds per vertex. A per-vertex color, for instance:

```swift
let i = spot.triangle * 3
let a = mesh.colors[Int(mesh.indices[i])]
let b = mesh.colors[Int(mesh.indices[i + 1])]
let c = mesh.colors[Int(mesh.indices[i + 2])]
let w = spot.barycentric
let tint = Color.mix(Color.mix(a, b, t: w.y / max(w.x + w.y, 1e-9)), c, t: w.z)
```

They are also how a scatter is filtered by something the surface already knows. Keep the spots facing up, and only those:

```swift
let flat = surfacePoints(on: terrain, count: 800).filter { $0.normal.y > 0.8 }
```

<a name="alignment"></a>

#### Standing something up

```swift
func alignment(spin: Double = 0) -> Vector3
```

The turn that points a mesh's own **+y** along the sample's normal, given as the angles a [`MeshInstance`](../3D/Instancing.md) takes. `spin` turns it about that direction afterward, which is what keeps a scattered field from reading as a field of clones.

```swift
drawMesh(tree, instances: spots.map {
    MeshInstance(position: $0.position,
                 rotation: $0.alignment(spin: random(.tau)),
                 scale: 0.4)
})
```

A mesh built about its middle sits half-buried, so lift it along the normal by half its height:

```swift
MeshInstance(position: $0.position + $0.normal * 0.15, rotation: $0.alignment())
```

<a name="area"></a>

#### surfaceArea

```swift
mesh.surfaceArea -> Double
```

Every triangle's area added up, in the square of the mesh's own units. It is what turns a spacing into a count, and it is worth reading directly when a scatter should hold a **density** rather than a count:

```swift
let trees = surfacePoints(on: island, count: Int(island.surfaceArea * 12))
```

<a name="standalone"></a>

#### Standalone (outside a sketch)

The `Sketch` methods are sugar over free functions that take any random source, so geometry code outside a sketch can scatter reproducibly too:

```swift
var rng = SplitMix64(seed: 7)
let spots = surfacePoints(on: mesh, count: 500, using: &rng)
```

---

Related: [`Blue noise`](./BlueNoise.md) (the same even spacing on a flat rectangle), [`Instanced meshes`](../3D/Instancing.md) (drawing one prop thousands of times), [`Strand fields`](../3D/Strands.md) (grass grown inside the draw call), [`Random`](./Random.md) (the seeded source everything here draws from).
