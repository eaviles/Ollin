#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Terrain</sup>

---

## Terrain

Generated landscapes as data you sculpt and then spend anywhere: a **`Heightfield`** is a grid of heights that grows from noise or fractal subdivision, weathers under simulated rain and gravity, and reads out as a solid `Mesh` for [3D mode](../3D/3D.md), a grayscale heightmap `Image`, or per-point samples for contours and fields.

```swift
var land = Heightfield.diamondSquare(size: 257, seed: 7)
land = land.eroded(.hydraulic())          // rain carves ravines and fans
           .eroded(.thermal())            // steep slopes settle into scree
drawMesh(land.mesh(width: 10, depth: 10, height: 2.2))
```

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

The closure form samples any per-point field at normalized coordinates, so the whole [noise family](Noise.md) is a terrain generator: `fbm` rolls classic hills, `ridgedFbm` creases into mountain ridges, `warpedFbm` melts them. Heights are plain `Double`s in a row-major `values` array, `0…1` by convention (the generators emit that range, the erosion defaults assume it, and `normalized()` restores it after hand edits). `field[x, y]` reads and writes samples; `value(atU:v:)` samples anywhere bilinearly.

<a name="diamond-square"></a>

#### Diamond-square

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.5, seed: 7)
```

The classic terrain fractal: seed the four corners, then alternately set each square's center (the *diamond* step) and each edge midpoint (the *square* step) to the average of its neighbors plus a random offset, halving the grid step while the offsets shrink by `roughness` per level. Low roughness rolls smoothly, high roughness stays jagged at every scale, and around `0.5` reads as natural landscape. `size` rounds up to the power-of-two-plus-one grid the subdivision needs (65, 129, 257, 513…), the result is normalized to `0…1`, and the same `seed` always grows the same terrain (a generic `using:` form accepts any `RandomNumberGenerator`).

<a name="hydraulic"></a>

#### Hydraulic erosion

```swift
land.eroded(.hydraulic(), seed: 7)
land.eroded(.hydraulic(drops: 100_000, inertia: 0.1, radius: 4), seed: 7)
```

What turns "noise" into "landscape": tens of thousands of simulated raindrops, each landing at a random point and rolling downhill, picking up sediment while it runs fast and full and laying it down as it slows or dries. Ravines deepen where drops agree, sediment fans build below them, and the result carries the drainage language of real rain on real slopes. This is the particle (droplet) method, implemented from the published technique.

The knobs, roughly in order of how much they change the look: `drops` (how much history rains on the terrain), `inertia` (0 hugs every wrinkle into dense fine ravines, higher plows straighter), `capacity` (how hard each drop can carve), `radius` (the brush a drop erodes with: 1 cuts wire-thin, 3–4 reads natural), `deposition`/`erosion` (how eagerly sediment drops out and gets picked up), `evaporation` (how long a drop's reach lasts), plus `minSlope`, `gravity`, and `maxSteps`. Determinism is exact per seed; heights clamp at 0 so border runoff can't dig unbounded drains.

<a name="thermal"></a>

#### Thermal erosion

```swift
land.eroded(.thermal())
land.eroded(.thermal(talus: 0.01, amount: 0.5, iterations: 100))
```

Gravity's half of weathering: wherever neighboring samples step more than `talus` apart, a share (`amount`) of the excess slides to the lower side each iteration, so cliffs shed into scree aprons and jagged spikes settle at a resting angle, while slopes already at rest don't move at all. It runs as an order-free relaxation (every transfer computed against the frozen field, then applied together), uses no randomness, and conserves mass exactly. Run it after `.hydraulic()` to soften fresh ravine walls the way real slopes weather.

<a name="emit"></a>

#### Meshes, images, and contours

```swift
let mesh = land.mesh(width: 10, depth: 10, height: 2.2)   // centered, y-up
drawMesh(mesh.textured(colorTexture))                     // e.g. a height ramp
let map = land.image()                                    // grayscale heightmap
```

`mesh(...)` emits a solid terrain: a `width × depth` grid centered on the origin in the ground plane, heights lifted to `height · value` on +y, with smooth normals and `0…1` UVs. Because UVs map the sheet in plan view, a texture built by walking each sample's height through a [`Ramp`](../Drawing/Color.md) paints altitude bands (the `3D/Geometry/Terrain` example does exactly this). `image()` is the heightmap as pixels, ready to inspect, [dither](../Drawing/Color.md#dithering), or feed the image form of [`isolines`](Isolines.md); the field form draws a contour map directly:

```swift
let sheet = Rectangle(x: 90, y: 90, width: 900, height: 900)
let levels = stride(from: 0.1, through: 0.9, by: 0.1).map { $0 }
let contours = isolines(at: levels, in: sheet, resolution: 220) { p in
    let uv = sheet.uv(of: p)
    return land.value(atU: uv.x, v: uv.y)
}
```

<a name="notes"></a>

#### Practical notes

- **Erode once, in `setup()`.** A big erosion pass is real work (tens of thousands of drops each walking dozens of steps); generate and weather the field once, keep the mesh, and redraw that. The `weathered` toggle in the example precomputes both meshes for instant flipping.
- **Resolution before drops.** 257² erodes convincingly with 50–70k drops; doubling the grid wants roughly 4× the drops to reach the same texture.
- **Hydraulic then thermal.** Rain first (it needs the sharp relief to carve), gravity second (it settles what the rain left too steep). Thermal alone is also the cheap way to age any spiky field.
- **Mass is honest.** Thermal conserves material exactly; hydraulic can only lose it (drops carry sediment off the map's edge), so repeated passes lower the extremes rather than inventing height. Renormalize with `normalized()` if a long weathering chain should span `0…1` again.
- **Not a per-frame simulation.** `Heightfield` is setup-shaped CPU geometry, like the [painterly tools](Marbling.md). For live evolving surfaces, the GPU [`Sim` fields](../Drawing/Effects.md#simfield) are the right substrate.

---

Related: [`Noise`](Noise.md) (the field generators), [`Isolines`](Isolines.md) (contour maps), [`3D`](../3D/3D.md) (drawing the mesh), [`Marbling`](Marbling.md) / [`Watercolor`](Watercolor.md) (the other setup-shaped catalogs).
