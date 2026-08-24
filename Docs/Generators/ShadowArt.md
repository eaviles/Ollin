#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Shadow art`</sup>

---

## Shadow art

**`shadowArt`** carves the solid that throws the shadows you ask for: one shape from the front, another from the side, a third from above.

```swift
let art = shadowArt(fromFront: ring, fromSide: cross, resolution: 56)
drawMesh(art.mesh)
```

The reasoning is one line. A lit point casts its shadow along the light's direction, so a point can only be part of the solid if it lands inside the shadow in *every* direction it is lit from. Keep exactly those points:

```
   front says:  a ring        every voxel is kept only where all of the
   side says:   a cross       silhouettes say solid, so the solid is the
                              silhouettes swept through each other and
   what is left is neither    cut where they cross
```

What is left is the **visual hull**: the largest solid that could cast them.

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
          in bounds: (min: Vector3, max: Vector3)? = nil) -> ShadowArt
```

Each picture is read as a silhouette: **bright means solid** (a white shape on black), and `threshold` is where the line falls. `inverted` reads dark as solid instead, which is what a scanned drawing looks like.

- `front` is the shadow cast along z, seen looking at the xy face.
- `side` is the shadow cast along x, seen looking at the zy face.
- `above` is the shadow cast along y, seen looking at the xz face.

A side left out places no constraint at all, so **one picture alone gives a prism**. The cost is the cube of `resolution`, and the default two-unit cube about the origin can be replaced with any box.

<a name="reading"></a>

#### Reading it back

```swift
struct ShadowArt {
    let resolution: Int
    let occupied: [Bool]                       // x + y*n + z*n*n
    let bounds: (min: Vector3, max: Vector3)
    var voxelSize: Double
    var count: Int
    var boxes: [Vector3]                       // the middle of every solid voxel
    var mesh: Mesh                             // the carved surface
    func isSolid(_ x: Int, _ y: Int, _ z: Int) -> Bool
    func shadow(from side: Side) -> [Bool]     // what it really throws
}
```

`boxes` is the blocky reading, one cube per voxel, and `mesh` is the surface, built by marching the occupancy field so the skin steps over the voxels rather than guessing at a smooth shape behind them.

**`shadow(from:)` is the important one.** It hands back what the carved solid actually throws, which is the honest thing to compare with what was asked for.

<a name="limits"></a>

#### What can and cannot be cast

**The shadows thrown are never larger than the ones asked for, and can be smaller.** The catch is that two views share an axis. The front and the side are seen from either end of the same vertical, so a row that is empty in one empties it in the other: no solid can throw a shadow where nothing is lit.

- **Two silhouettes come out exact when they are solid in the same rows.** That is why the classic circle-and-square works, and why a shape reaching further down than its partner has its bottom cut off.
- **Three agree far less often.** A point of one shadow may have nothing behind it that survives the other two, and then that part of the shadow is simply not cast. The famous three-letter sculptures are designed around this, not in spite of it.
- Compare `shadow(from:)` against the silhouette you handed in, and where they differ, the one that is true is the one thrown.

Example: `3D/Geometry/ShadowArt`. Guide: [Chapter 26](../../Guide/26-SculptingWithFields.md).

---

#### Where this comes from

Carving a solid down to what its silhouettes allow is **shape from silhouette**, and the result is the visual hull named by Aldo Laurentini ("How Far 3D Shapes Can Be Understood from 2D Silhouettes", *IEEE PAMI* 16/2, 1994). Sculptures built to throw two or three chosen shadows are older, and the computational version was set out by Niloy Mitra and Mark Pauly ("Shadow Art", *SIGGRAPH Asia* 2009). See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Isosurfaces and metaballs](./Isosurface.md): the marching that turns the carved voxels into a surface
- [3D](../3D/3D.md): drawing the mesh, lighting it, and casting its shadows for real
- [Fabrication export](../Output/Fabrication.md): sending the solid to a printer, which is where a shadow sculpture wants to end up
