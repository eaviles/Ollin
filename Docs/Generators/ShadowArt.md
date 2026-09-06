#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Shadow art`</sup>

---

## Shadow art

**`shadowArt`** carves a solid that throws the shadows you ask for. You give it one shape for the front, another for the side, and a third for above.

```swift
let art = shadowArt(fromFront: ring, fromSide: cross, resolution: 56)
drawMesh(art.mesh)
```

A lit point casts its shadow along the direction of the light. A point can therefore belong to the solid only if it lands inside the shadow in *every* direction it is lit from. Keep exactly those points:

```
   front says:  a ring        every voxel is kept only where all of the
   side says:   a cross       silhouettes say solid, so the solid is the
                              silhouettes swept through each other and
   what is left is neither    cut where they cross
```

What is left is the **visual hull**, the largest solid that could cast those shadows.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/26-SculptingWithFields/TwoShadowsOneSolid-dark.jpg">
  <img src="../../Guide/Images/26-SculptingWithFields/TwoShadowsOneSolid.jpg" alt="Five panels: a ring and a cross asked for as shadows, the lumpy solid they carve shown lit in the middle, and the two shadows it really throws, matching the ones asked for" width="680">
</picture>

### Contents

- [shadowArt](#carve)
- [Reading it back](#reading)
- [What can and cannot be cast](#limits)

<a name="carve"></a>

#### shadowArt

```swift
shadowArt(fromFront front: Image? = nil,
          fromSide side: Image? = nil,
          fromAbove above: Image? = nil,
          resolution: Int = 48,
          threshold: Double = 0.5,
          inverted: Bool = false,
          in bounds: Box3? = nil) -> ShadowArt
```

Each picture is read as a silhouette, and **bright means solid**, which means a white shape on a black background. `threshold` sets where that brightness cutoff falls. Set `inverted` to read dark as solid instead, which is the usual case for a scanned drawing.

- `front` is the shadow cast along z, seen looking at the xy face.
- `side` is the shadow cast along x, seen looking at the zy face.
- `above` is the shadow cast along y, seen looking at the xz face.

A side you leave out places no constraint, so **one picture alone gives a prism**. The cost is the cube of `resolution`. The bounds default to a two-unit cube around the origin, and you can pass any box instead.

<a name="reading"></a>

#### Reading it back

```swift
struct ShadowArt {
    let resolution: Int
    let occupied: [Bool]                       // x + y*n + z*n*n
    let bounds: Box3
    var voxelSize: Double
    var count: Int
    var boxes: [Vector3]                       // the middle of every solid voxel
    var mesh: Mesh                             // the carved surface
    func isSolid(_ x: Int, _ y: Int, _ z: Int) -> Bool
    func shadow(from side: Side) -> [Bool]     // what it really throws
}
```

`boxes` is the blocky reading, one cube per voxel. `mesh` is the surface, built by marching the occupancy field. The surface therefore steps over the voxels rather than approximating a smooth shape behind them.

**`shadow(from:)` reports what the carved solid actually throws.** Compare its result against the shadow you asked for.

<a name="limits"></a>

#### What can and cannot be cast

**The shadows thrown are never larger than the ones asked for, and can be smaller.**

The reason is that the front view and the side view share the same vertical axis, so their rows line up. A row that is empty in one view is therefore empty in the other, because no solid throws a shadow where nothing is lit.

- **Two silhouettes come out exact when they are solid in the same rows.** That is why the classic circle-and-square works. It is also why a shape that reaches further down than the other silhouette has its bottom cut off.
- **Three agree far less often.** A point of one shadow may have nothing behind it that survives the other two. That part of the shadow is then not cast. The three-letter sculptures are designed around this limit.
- Compare `shadow(from:)` against the silhouette you passed in. Where the two differ, the thrown shadow is the one you get.

Example: `3D/Geometry/ShadowArt`. Guide: [Chapter 26](../../Guide/26-SculptingWithFields.md).

---

#### Where this comes from

Carving a solid down to what its silhouettes allow is **shape from silhouette**. The result is the visual hull, named by Aldo Laurentini ("How Far 3D Shapes Can Be Understood from 2D Silhouettes", *IEEE PAMI* 16/2, 1994). Sculptures built to throw two or three chosen shadows are older. Niloy Mitra and Mark Pauly set out the computational version ("Shadow Art", *SIGGRAPH Asia* 2009). See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Isosurfaces and metaballs](./Isosurface.md): the marching that turns the carved voxels into a surface
- [3D](../3D/3D.md): drawing the mesh, lighting it, and casting real shadows from it
- [Fabrication export](../Output/Fabrication.md): sending the solid to a printer, the usual last step for a shadow sculpture
