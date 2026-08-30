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

Both are deterministic given their inputs. Both come back as ordinary meshes, which take materials, lighting, shadows, subdivision, and export. Both are setup-shaped CPU work, so build once and keep the mesh.

### Contents

- [Skinning points](#skin)
- [Rebuilding a sampled surface](#reconstruct)
- [The fitting: planes or robust](#fitting)
- [Orientation: cameras first](#orientation)
- [Holes are honest](#holes)
- [Colors carry](#colors)
- [Sweeping a room](#rooms)
- [Cost and knobs](#cost)

<a name="skin"></a>

#### Skinning points

`particleSurface(of:radius:blend:resolution:)` needs nothing but the points. Each becomes a ball of `radius`. Where balls overlap, the surface follows a smooth local average instead of the lumpy union of spheres, which is the surfacing look particle fluids use. `blend` is how far that averaging reaches, as a multiple of `radius`. Higher values melt neighbors together from farther apart, and `1` approaches separate spheres. A single isolated point comes back as an exact ball.

```swift
let blob = particleSurface(of: points, radius: 0.08, blend: 2.5, resolution: 96)
```

There is no orientation problem and no hole concept here, because the skin always closes around whatever the points are. That simplicity is why it is the right tool for generated point sets. It is the wrong one for a scan, where it would wrap the wall in a two-sided shell instead of giving the wall back.

<a name="reconstruct"></a>

#### Rebuilding a sampled surface

`reconstructSurface(of:spacing:resolution:orientedToward:maxGap:neighbors:fitting:keepingLargestComponent:)` is the faithful tool. It fits a small plane to every point's neighborhood, then turns the planes to agree on which side is outside. It pulls the surface out of the resulting signed distance field with marching cubes. The result passes through the samples' true positions, with noise averaged by the plane fits rather than reproduced. It keeps topology, so a sampled knot comes back knotted. And it reports missing data honestly.

`spacing` is the typical distance between neighboring samples. Leave it nil to have it estimated. If the cloud came from a [`WorldCloud`](../3D/RGBD.md), pass the accumulator's `voxelSize`, or slightly more, which is exactly that number.

<a name="fitting"></a>

#### The fitting: planes or robust

`fitting:` chooses how the fitted neighborhoods become a distance. It is an artwork parameter like `resolution`, so it changes the piece, not just its cost.

- **`.planes`**, the default. Every evaluation reads its single nearest plane. It is fast and faithful. On noisy or unevenly captured data the piecewise planes can read slightly faceted, and where coverage runs out, disagreeing planes can shed stray shreds of surface.
- **`.robust`**, robust kernel regression over the same planes, the RIMLS method. Every evaluation blends all the nearby samples, then re-weights the blend a few times. Samples that disagree with the local consensus fade out of the fit: noise, outliers, and the far side of a crease. The result is smoother where the surface is smooth, keeps its edges where it is not, and resists phantom shreds around partially observed objects. It costs more than the plane fit, from a few percent on a real scan to roughly double on dense synthetic clouds.

```swift
let room = reconstructSurface(of: world.cloud, spacing: world.voxelSize * 2,
                              orientedToward: path, fitting: .robust)
```

`.robust` takes two knobs when you want them, as `.robust(sharpness:iterations:)`. `sharpness` is how eagerly disagreeing samples are set aside. 1 is the balanced default, and below 1 is softer. 2 is the sharpest useful setting, and it clamps there, where the fit would start to disconnect. `iterations` is the number of re-weighting passes. The first pass is always the plain unweighted blend, so `iterations: 1` is a smooth blend with no re-weighting at all. The default 3 is enough for nearly everything.

<a name="orientation"></a>

#### Orientation: cameras first

A plane fitted to points has two sides, and the reconstruction needs every plane to agree on which one faces out. Two ways:

- **Pass viewpoints.** `orientedToward:` takes the positions the cloud was seen from: the camera translations of a sweep, one per captured frame or a handful along the path. Each plane turns by a distance-weighted vote of the cameras near it. A sample its nearest camera only grazed is still settled by the healthier angles along the sweep, and a far camera never outvotes a near one through a wall. If the cloud came from any kind of camera, use this.
- **No viewpoints.** Orientation propagates point-to-point along a spanning tree of the neighbor graph, preferring to cross flat ground. This works well on a smooth single surface, and a sampled sphere or terrain needs nothing. It is the fallback for purely generated clouds. Its known limit is thin double-sided structure. Where two opposite-facing sheets come closer than the neighborhood size, propagation can walk through the wall and flip a region.

<a name="holes"></a>

#### Holes are honest

Where the cloud has no samples, the reconstruction has no opinion. The distance field is *undefined* there rather than guessed, so an unscanned region stays an open hole instead of growing a fictitious cap. `maxGap` is the dial. Gaps smaller than it close, and larger ones stay open. Nil derives it per point from the local sampling density, roughly the neighborhood radius, capped so a region nobody sampled reads as a hole. That is the right default for scans. For a cloud known to sample a closed surface, pass `.infinity` and every gap closes.

The flip side of honesty is that coverage is everything. A body observed from only one side keeps an unobserved back. Under the default plane fit the rebuilt surface then frays into a fringe just past where its data stops. Each fitted plane extends a little beyond its last samples. The `.robust` fitting suppresses most of that fraying. On a staged partial-coverage scene it removed over 99% of the mid-air shreds while keeping every observed surface. Reach for it when a scan's open edges look torn. The honest fix is still coverage: sweep around the things you care about, and the fringe goes away with the gap it marks.

Scan noise also tends to leave a few small shells floating off the real surface. `keepingLargestComponent: true` keeps only the largest connected piece, by area. It keeps exactly one. A real separate object in the scan goes out with the noise, such as a ball whose contact with the floor fell below the sampling. Reach for it when the scan is one connected space.

<a name="colors"></a>

#### Colors carry

Give `reconstructSurface` a `PointCloud` instead of bare positions, and the cloud's colors carry onto the mesh. Each vertex takes its nearest sample's color, so a captured scan rebuilds in the colors it was seen in. The colors ride the mesh as per-vertex `Mesh.colors`, which *multiply* the current `fill` at draw time. That is the texture contract. With the default white fill the scan shows its true colors untouched. `fill` stays a whole-mesh tint, so `fill(Color(white: 0.5))` dims the room without touching its hues. An all-white cloud skips the transfer.

The same transfer is available on any mesh as `colored(from:)`. A procedural sibling, `colored(by:)`, computes a color from each vertex's position and normal:

```swift
let skin = particleSurface(of: cloud, radius: 0.05).colored(from: cloud)

let globe = Mesh.sphere(radius: 1).colored { p, _ in
    p.y > 0 ? .white : Color(hex: 0x2B6CB0)
}
```

Lighting shades a vertex color exactly as it shades the fill. A wireframe draws its edges in the stroke color and ignores them. Drop the colors with `mesh.colors = []` when you want the plain fill back.

<a name="rooms"></a>

#### Sweeping a room

The reconstruction pairs with the depth stack: sweep a phone through a room, fuse the frames, rebuild the room as one mesh.

```swift
var world = WorldCloud(voxelSize: 0.02)
var path: [Vector3] = []

// Each frame, while scanning:
if let frame = device.latestFrame, let pose = device.latestPose {
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

<img src="../../Guide/Images/27-DepthAndThePhone/RoomRebuilt.jpg" alt="The staged room corner rebuilt as one solid plaster-like surface, the floor meeting two walls in a crisp crease, the sweep's camera positions floating as small blue spheres, the surface ending in a torn rim where the sweep stopped" width="680">

The camera path is the orientation, and because the fused cloud carries the capture's colors, the room comes back colored. Doorways, windows, and everything the sweep missed stay open, which is the truthful shape of a scan.

A recorded clip works the same way without the live tether. `Record3DRecording` exposes `poses`, camera-to-world, one per frame. A sweep saved on the phone therefore fuses frame by frame with `pose(at:)`, and reconstructs with the pose translations as the camera path.

<a name="cost"></a>

#### Cost and knobs

| Knob | Does | Notes |
|---|---|---|
| `resolution` | grid cells across the longest side | detail finer than the sampling cannot be recovered, so past `bounds / spacing` it only costs |
| `spacing` | the sampling density the cloud was taken at | nil estimates it; a `WorldCloud` knows it as `voxelSize` |
| `neighbors` | how many samples fit each plane | more smooths noise; fewer preserves fine detail |
| `maxGap` | how large a data gap still closes | nil adapts to local density; `.infinity` closes everything |
| `fitting` | nearest plane, or the robust blend | `.planes` is fast and faithful; `.robust` smooths noise, keeps creases, and resists phantom shreds |
| `blend` | (`particleSurface`) how far balls melt together | 1 is separate spheres; 2 to 3 is the liquid look |

Cost concentrates in two places: one plane fit per point, and the field samples near the surface. The far grid is skipped cheaply. Both scale with what you ask for, so reconstruct once in `setup()` and keep the mesh, the way the other mesh generators are used.

### See also

- [`Isosurfaces`](./Isosurface.md) - the marching-cubes substrate both tools contour with
- [`RGBD & WorldCloud`](../3D/RGBD.md) - the depth frames and the sweep accumulator the room recipe uses
- [`Mesh growth`](./MeshGrowth.md) - grow a surface instead of recovering one
- [`Subdivision surfaces`](./SubdivisionSurfaces.md) - smooth the rebuilt mesh further
