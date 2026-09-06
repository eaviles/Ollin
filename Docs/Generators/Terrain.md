#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Terrain</sup>

---

## Terrain

A generated landscape is data you shape first and then use anywhere. A **`Heightfield`** is a grid of heights that you build from noise or from fractal subdivision, and then weather under simulated rain and gravity. You read it back as a solid `Mesh` for [3D mode](../3D/3D.md), as a grayscale heightmap `Image`, or as per-point samples for contours and fields.

```swift
var land = Heightfield.diamondSquare(size: 257, seed: 7)
land = land.eroded(.hydraulic())          // rain carves ravines and fans
           .eroded(.thermal())            // steep slopes settle into scree
drawMesh(land.mesh(width: 10, depth: 10, height: 2.2))
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/23-Landscapes/Erosion-dark.jpg">
  <img src="../../Guide/Images/23-Landscapes/Erosion.jpg" alt="Three grayscale heightmaps: raw diamond-square noise with soft blobby light and dark regions, the same field after rain with branching valleys carved through it, and after gravity with those valley walls slightly settled" width="680">
</picture>

### Contents

- [Building a field](#build)
- [Diamond-square](#diamond-square)
- [Hydraulic erosion](#hydraulic)
- [Thermal erosion](#thermal)
- [Meshes, images, and contours](#emit)
- [Practical notes](#notes)

<a name="build"></a>

#### Building a field

```swift
Heightfield(columns: 257, rows: 257) { u, v in fbm(u * 3, v * 3, octaves: 6) }
Heightfield(columns: 129, rows: 129, repeating: 0.5)      // flat
Heightfield(columns: w, rows: h, values: rowMajorHeights) // explicit data
```

The closure form samples any per-point field at normalized coordinates, so every function in the [noise family](Noise.md) works as a terrain generator. `fbm` gives you classic rolling hills, `ridgedFbm` creases them into mountain ridges, and `warpedFbm` distorts them.

Heights are plain `Double`s in a row-major `values` array, and by convention they run from `0…1`. The generators produce that range, and the erosion defaults assume it, so call `normalized()` to restore it after you edit heights by hand. Use `field[x, y]` to read and write single samples, and `value(u:v:)` to sample anywhere with bilinear interpolation.

<a name="diamond-square"></a>

#### Diamond-square

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.5, seed: 7)
```

Diamond-square is the classic terrain fractal. It seeds the four corners, then alternates between setting each square's center in the *diamond* step and each edge midpoint in the *square* step. Each new sample takes the average of its neighbors plus a random offset. The grid step halves at every level, and the offsets shrink by `roughness`.

A low roughness rolls smoothly, a high one stays jagged at every scale, and a value around `0.5` reads as natural landscape. `size` rounds up to the power-of-two-plus-one grid the subdivision needs, so 65, 129, 257, 513, and on. The result is normalized to `0…1`, and the same `seed` always grows the same terrain. A generic `using:` form accepts any `RandomNumberGenerator`.

<a name="hydraulic"></a>

#### Hydraulic erosion

```swift
land.eroded(.hydraulic(), seed: 7)
land.eroded(.hydraulic(drops: 100_000, inertia: 0.1, radius: 4), seed: 7)
```

Hydraulic erosion is what turns noise into landscape. Tens of thousands of simulated raindrops each land at a random point and roll downhill. A drop picks up sediment while it runs fast and full, and it lays that sediment down as it slows or dries. Ravines deepen where many drops take the same path, and sediment fans build below them. The result drains the way real rain drains off real slopes. This is the particle method, also called the droplet method, implemented from the published technique.

The parameters, roughly in order of how much they change the look:

- `drops` sets how much rain history falls on the terrain.
- `inertia` at 0 follows every wrinkle, which cuts dense fine ravines, while higher values plow straighter.
- `capacity` sets how hard each drop can carve.
- `radius` is the brush a drop erodes with. A radius of 1 cuts wire-thin, and 3 to 4 reads natural.
- `deposition` and `erosion` set how readily sediment drops out and how readily it is picked up.
- `evaporation` sets how long a drop's reach lasts.
- `minSlope`, `gravity`, and `maxSteps` complete the set.

A given seed always gives the same result. Heights clamp at 0, so runoff at the border cannot dig drains without limit.

<a name="thermal"></a>

#### Thermal erosion

```swift
land.eroded(.thermal())
land.eroded(.thermal(talus: 0.01, amount: 0.5, iterations: 100))
```

Thermal erosion is the gravity half of weathering. Wherever two neighboring samples step more than `talus` apart, part of that excess slides to the lower side on each iteration. `amount` sets how much of it moves. Cliffs shed into scree aprons and jagged spikes settle at a resting angle, while slopes already at rest don't move at all. The pass runs as an order-free relaxation, so it computes every transfer against the frozen field and then applies them together. It uses no randomness, and it conserves mass exactly. Run it after `.hydraulic()` to soften fresh ravine walls the way real slopes weather.

<a name="emit"></a>

#### Meshes, images, and contours

```swift
let mesh = land.mesh(width: 10, depth: 10, height: 2.2)   // centered, y-up
drawMesh(mesh.textured(colorTexture))                     // e.g. a height ramp
let map = land.image()                                    // grayscale heightmap
```

<img src="../../Guide/Images/23-Landscapes/TerrainMesh.jpg" alt="The eroded terrain standing up as a lit 3D mesh in warm low sunlight, green in the valleys and pale on the ridges, with the carved drainage lines visible across it" width="560">

`mesh(...)` emits a solid terrain. It is a `width × depth` grid centered on the origin in the ground plane, with heights lifted to `height · value` on +y, smooth normals, and `0…1` UVs. The UVs map the sheet in plan view. A texture built by running each sample's height through a [`Ramp`](../Drawing/Color.md) therefore paints altitude bands, and each step of that is a single call. `image(_ ramp:in:)` paints each sample through the ramp, and its optional `range` maps a height span onto the ramp. `coloredMesh(width:depth:height:_:in:)` hands back the mesh already wearing that texture. Build the mesh when the field changes, not once per frame. The `3D/Geometry/Terrain` example uses exactly this. `image()` gives you the heightmap as pixels, ready to inspect, [dither](../Drawing/Color.md#dithering), or feed to the image form of [`isolines`](Isolines.md). The field form draws a contour map directly:

```swift
let sheet = Rectangle(x: 90, y: 90, width: 900, height: 900)
let levels = stride(from: 0.1, through: 0.9, by: 0.1).map { $0 }
let contours = isolines(at: levels, in: sheet, resolution: 220) { p in
    let uv = sheet.uv(of: p)
    return land.value(u: uv.x, v: uv.y)
}
```

<a name="notes"></a>

#### Practical notes

- **Erode once, in `setup()`.** A big erosion pass is real work, because tens of thousands of drops each walk dozens of steps. Generate and weather the field once, keep the mesh, and redraw that mesh. The `weathered` toggle in the example builds both meshes ahead of time, so flipping between them is instant.
- **Resolution before drops.** A 257² field erodes convincingly with 50 to 70k drops. If you double the grid, you need roughly 4× the drops to reach the same texture.
- **Hydraulic then thermal.** Run the rain first, because it needs the sharp relief to carve into. Run gravity second, so it settles what the rain left too steep. Thermal alone is also the cheap way to age any spiky field.
- **Mass is honest.** Thermal conserves material exactly. Hydraulic can only lose it, because drops carry sediment off the map's edge, so repeated passes lower the extremes rather than inventing height. Call `normalized()` if a long weathering chain should span `0…1` again.
- **Not a per-frame simulation.** `Heightfield` is CPU geometry you build in `setup()`, like the [painterly tools](Marbling.md). For a surface that evolves while the sketch runs, use the GPU [`Sim` fields](../Drawing/Effects.md#simfield) instead.

---

Related: [`Noise`](Noise.md) (the field generators), [`Isolines`](Isolines.md) (contour maps), [`3D`](../3D/3D.md) (drawing the mesh), [`Marbling`](Marbling.md) / [`Watercolor`](Watercolor.md) (the other setup-shaped catalogs).
