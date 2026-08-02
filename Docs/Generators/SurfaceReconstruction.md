#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Surface reconstruction</sup>

---

## Surface reconstruction

From points back to a surface. Two tools turn a bag of 3D points into a triangle `Mesh`, and they answer two different questions:

- **`particleSurface`** treats the points as *material*: every point becomes a small ball and nearby balls melt together into one smooth skin. A splash, a blob, a swarm dense enough to read as a body.
- **`reconstructSurface`** treats the points as *samples of a surface that existed*: a depth-camera room sweep, a scanned object, a sampled form. It rebuilds that surface, holes and all.

```swift
let skin = particleSurface(of: positions, radius: 0.1)

let room = reconstructSurface(of: world.cloud, spacing: world.voxelSize * 2,
                              orientedToward: cameraPath)
drawMesh(room)
```

Both are deterministic given their inputs, both come back as ordinary meshes (materials, lighting, shadows, subdivision, export), and both are setup-shaped CPU work: build once, keep the mesh.

### Contents

- [Skinning points](#skin)
- [Rebuilding a sampled surface](#reconstruct)
- [Orientation: cameras first](#orientation)
- [Holes are honest](#holes)
- [Sweeping a room](#rooms)
- [Cost and knobs](#cost)

<a name="skin"></a>

#### Skinning points

`particleSurface(of:radius:blend:resolution:)` needs nothing but the points. Each becomes a ball of `radius`; where balls overlap, the surface follows a smooth local average instead of the lumpy union of spheres, which is the surfacing look particle fluids use. `blend` is how far that averaging reaches, as a multiple of `radius`: higher melts neighbors together from farther apart, `1` approaches separate spheres. A single isolated point comes back as an exact ball.

```swift
let blob = particleSurface(of: points, radius: 0.08, blend: 2.5, resolution: 96)
```

There is no orientation problem and no hole concept here: the skin always closes around whatever the points are. That simplicity is why it is the right tool for generated point sets, and the wrong one for a scan, where it would wrap the wall in a two-sided shell instead of giving the wall back.

<a name="reconstruct"></a>

#### Rebuilding a sampled surface

`reconstructSurface(of:spacing:resolution:orientedToward:maxGap:neighbors:keepingLargestComponent:)` is the faithful tool. It fits a small plane to every point's neighborhood, turns the planes to agree on which side is outside, and pulls the surface out of the resulting signed distance field with marching cubes. The result passes through the samples' true positions (noise is averaged by the plane fits, not reproduced), keeps topology (a sampled knot comes back knotted), and reports missing data honestly.

`spacing` is the typical distance between neighboring samples. Leave it nil to have it estimated; if the cloud came from a [`WorldCloud`](../3D/RGBD.md), pass the accumulator's `voxelSize` (or slightly more), which is exactly that number.

<a name="orientation"></a>

#### Orientation: cameras first

A plane fitted to points has two sides, and the reconstruction needs every plane to agree on which one faces out. Two ways:

- **Pass viewpoints.** `orientedToward:` takes the positions the cloud was seen from: the camera translations of a sweep, one per captured frame or a handful along the path. Each plane turns by a distance-weighted vote of the cameras near it, so a sample its nearest camera only grazed is still settled by the healthier angles along the sweep, and a far camera never outvotes a near one through a wall. If the cloud came from any kind of camera, use this.
- **No viewpoints.** Orientation propagates point-to-point along a spanning tree of the neighbor graph, preferring to cross flat ground. This works well on a smooth single surface (a sampled sphere or terrain needs nothing), and it is the fallback for purely generated clouds. Its known limit is thin double-sided structure: where two opposite-facing sheets come closer than the neighborhood size, propagation can walk through the wall and flip a region.

<a name="holes"></a>

#### Holes are honest

Where the cloud has no samples, the reconstruction has no opinion: the distance field is *undefined* there rather than guessed, so an unscanned region stays an open hole instead of growing a fictitious cap. `maxGap` is the dial. Gaps smaller than it close; larger ones stay open; nil derives it per point from the local sampling density (roughly the neighborhood radius, capped so a region nobody sampled reads as a hole), which is the right default for scans. For a cloud known to sample a closed surface, pass `.infinity` and every gap closes.

The flip side of honesty is that coverage is everything. A body observed from only one side keeps an unobserved back, and the rebuilt surface frays into a fringe just past where its data stops, because each fitted plane extends a little beyond its last samples. The fringe is not a knob problem; it is the shape of missing data. Sweep around the things you care about, and it goes away with the gap it marks.

Scan noise also tends to leave a few small shells floating off the real surface. `keepingLargestComponent: true` keeps only the largest connected piece, by area. It keeps exactly one: a real separate object in the scan (a ball whose contact with the floor fell below the sampling) goes out with the noise, so reach for it when the scan is one connected space.

<a name="rooms"></a>

#### Sweeping a room

The reconstruction pairs with the depth stack: sweep a phone through a room, fuse the frames, rebuild the room as one mesh.

```swift
var world = WorldCloud(voxelSize: 0.02)
var path: [Vector3] = []

// Each frame, while scanning:
if let frame = device.latestDepthFrame, let pose = device.latestPose {
    world.add(frame.pointCloud(), transformedBy: pose)
    path.append(Vector3(Double(pose.columns.3.x),
                        Double(pose.columns.3.y),
                        Double(pose.columns.3.z)))
}

// When the sweep is done:
let room = reconstructSurface(of: world.cloud, spacing: world.voxelSize * 2,
                              orientedToward: path,
                              keepingLargestComponent: true)
```

The camera path is the orientation. Doorways, windows, and everything the sweep missed stay open, which is the truthful shape of a scan.

<a name="cost"></a>

#### Cost and knobs

| Knob | Does | Notes |
|---|---|---|
| `resolution` | grid cells across the longest side | detail finer than the sampling cannot be recovered, so past `bounds / spacing` it only costs |
| `spacing` | the sampling density the cloud was taken at | nil estimates it; a `WorldCloud` knows it as `voxelSize` |
| `neighbors` | how many samples fit each plane | more smooths noise; fewer preserves fine detail |
| `maxGap` | how large a data gap still closes | nil adapts to local density; `.infinity` closes everything |
| `blend` | (`particleSurface`) how far balls melt together | 1 is separate spheres; 2 to 3 is the liquid look |

Cost concentrates in two places: one plane fit per point, and the field samples near the surface (the far grid is skipped cheaply). Both scale with what you ask for, so reconstruct once in `setup()` and keep the mesh, the way the other mesh generators are used.

### See also

- [`Isosurfaces`](./Isosurface.md) - the marching-cubes substrate both tools contour with
- [`RGBD & WorldCloud`](../3D/RGBD.md) - the depth frames and the sweep accumulator the room recipe uses
- [`Mesh growth`](./MeshGrowth.md) - grow a surface instead of recovering one
- [`Subdivision surfaces`](./SubdivisionSurfaces.md) - smooth the rebuilt mesh further
