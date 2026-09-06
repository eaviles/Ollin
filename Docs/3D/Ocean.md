#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `The ocean`</sup>

---

## The ocean

Ollin builds the ocean from a wave spectrum, the same way a real sea is measured.
`makeOceanField(_:)` writes a wave spectrum on the GPU. The spectrum says how much water
stands at each wavelength and heading for a given wind. One
[inverse Fourier transform](../Drawing/Fourier.md) then turns that whole
field of frequencies into the moving surface in a single step. `drawOcean(_:)` draws the
result as water.

Nothing here places a wave, and no wave is animated by hand. The motion comes from the
spectrum itself. A long wave travels faster than a short one, so the surface looks like a
sea rather than a sheet shaking in place.

### Contents

- [Quick start](#quick-start)
- [The sea state](#the-sea-state)
- [The field](#the-field)
- [Drawing it](#drawing-it)
- [How the water looks](#how-it-looks)
- [What it costs](#cost)
- [What it will not do](#limits)
- [How it works](#how-it-works)

<a id="quick-start"></a>
### Quick start

```swift
override func draw() {
    background(Color(hex: 0x8FB6D4))
    environment(.sky(turbidity: 2.6, sunElevation: 0.13))
    light(.directional(Color(hex: 0xFFF1DC), direction: Vector3(0, -0.13, -0.99)))
    camera(.perspective(eye: Vector3(0, 4.6, -95), target: Vector3(0, 2.6, 220)))

    let sea = makeOceanField(.breeze)            // the transform runs here
    drawOcean(sea, segments: 320, tiles: 5)
}
```

<a id="the-sea-state"></a>
### The sea state

`Ocean` holds the physics: how hard the wind has blown, and for how long.

**`waveHeight` is a measurement, not a dial.** It is the significant wave height in world
units, which is what a sailor means by the height of a sea. That is the average height of
the tallest third of the waves, which equals four times the standard deviation of the
surface. Ask for 3 and the water stands 3, whatever else is set. The scale is worked
out from a closed form of the spectrum rather than tuned by eye. The height holds across
grid sizes and wind speeds, and the tests measure it from the GPU's own output.

**`windSpeed` decides *which* waves carry that height.** The longest wave a wind can raise
grows with the square of the wind speed. So a high value moves the energy into long, slow
swell, and a low value moves it into short chop. The height stays where you set it either
way.

**`choppiness`** moves water sideways toward the crests. That is what makes the crests narrow
and the troughs wide. At 0 the surface is the plain sum of its waves, which looks round and
soft. Past about 1.5 the crests fold through themselves, and the fold shows up as foam
rather than as shape.

**`patchSize`** is the width of one period in world units. Every other value is read against
that scale. A 200 unit patch holding a 2 unit wave is open water, and a 20 unit patch holding
the same wave is a pond.

The remaining values shape the sea further: `windDirection` (degrees, in the ground plane),
`smallestWave` (ripples shorter than this are damped out, because a field cannot carry detail
below two of its own texels), `spread` (how tightly the waves line up with the wind),
`loopSeconds` (see *The field* below), and `seed`.

Four presets give you a starting point: `.calm`, `.breeze` (the default), `.swell`, and
`.storm`.

<a id="the-field"></a>
### The field

`makeOceanField` returns an `OceanField`, which is one frame of the sea. Building it is per-frame
work, like a generator, so call it in `draw()`.

```swift
let sea = makeOceanField(.swell, resolution: 512)
```

`resolution` is how many texels the field carries along each side (256 by default). The
value is rounded to the nearest power of two between 32 and 1024, because that is what the
transform works on. A higher resolution carries finer chop and costs more passes.

Underneath, the field is an ordinary layer (`sea.layer`, `sea.image`) that holds the surface
in world units. Red and blue are how far each point has moved sideways. Green is how high it
stands, and alpha is how hard the surface is folding there. The layer holds signed data
rather than a picture, so most of it draws as black until you map it through a filter. Even
so, everything that works on a layer still works on it.

To move the sea to a chosen time, or to run the water at its own speed, pass that time:

```swift
let sea = makeOceanField(.breeze, at: time * 0.4)
```

**A looping sea.** With `loopSeconds` set, the frequency of every wave is rounded down to a
multiple of one step. The whole surface then repeats exactly on that period, so a ten second
export loops with no seam. The rounding coarsens the motion a little, so keep the period
long unless a short loop is the point.

<a id="drawing-it"></a>
### Drawing it

```swift
let sea = makeOceanField(.breeze)
drawOcean(sea, segments: 320, tiles: 5, water: .open)
```

`segments` is how finely the grid is cut. `tiles` is how many periods of the field the water
covers. Tiling is how the water reaches the horizon without the waves growing larger.

The transform stack places the patch, so `translate`, `rotate`, and `scale` before the call
move the whole sea. The current camera decides the view. Without a camera, the call does
nothing.

No geometry is stored for the water. Each vertex works out from its own index which corner of
which cell it is. It then reads the field to find where the water has carried it.
`segments: 320` gives 614,400 vertices from a call that uploads nothing.

<a id="how-it-looks"></a>
### How the water looks

`WaterSurface` is the look, and it is separate from the physics:

- `deep` and `shallow`, the water where it is flat and where a crest stands up
- `sky`, what a flat surface reflects when no environment is set
- `foam` and `foamAmount`, the color of a folding crest and how much of a fold turns white
- `reflectance`, how much light the surface returns when you look straight down at it (0.02 is water)
- `sparkle` and `sparkleTightness`, the sun's own highlight

Four presets are built in: `.open`, `.tropical`, `.dusk`, and `.ink`.

With an environment set (`environment(.sky(...))` or a loaded HDRI), the surface reflects that
environment, so the water and the sky behind it agree. The first directional light in the
scene is the sun, and the sparkle comes from it. With no light set, the water is body color
and reflection alone.

<a id="cost"></a>
### What it costs

The field costs one spectrum pass, `2 · log2(n)` butterfly passes, and one resolve. That is
18 passes at 256 texels and 20 at 512, each over a small square. The draw costs
`segments² · 6` vertices and four texture reads per pixel for the normal.

The numbers below were measured on an M2 at 1080 square, with the sky environment and a sun
(`Scripts/benchmark.sh ocean`). The GPU spends **1.4 ms** at 160 segments over a 256 field,
and **1.8 ms** at 320 over 256. It spends **2.8 ms** at 320 over 512, and **3.7 ms** at 512
over 512. Doubling either the grid or the field costs about a millisecond at this size.

<a id="limits"></a>
### What it will not do

- **The surface is not in the shadow map, the ray-traced structures, or a vector or spatial
  export.** Like a strand field, its geometry exists only inside the draw call. So nothing
  that walks the scene's geometry can see it.
- **`material(_:)` does not apply.** Water is a reflection and a body color rather than a
  material, so it shades through its own fragment shader. `WaterSurface` is the whole of its
  look.
- **A tiled sea repeats.** The field is one period, and `tiles` lays that period out again
  and again. A viewer can see the repeat in a still if the patch is small and the tiling
  wide. Use a larger `patchSize` with more texels to hide it.
- **There is nothing under the water.** There is no refraction, no bottom, and no floating
  body. A reflected ray that dips below the horizon is read mirrored off the surface. That
  keeps the reflection continuous instead of showing the environment's flat ground.

<a id="how-it-works"></a>
### How it works

The spectrum is the Phillips form for a wind-driven sea. It is written from Tessendorf's
published account and credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md). Each wave vector
gets an amplitude from that spectrum and a random phase. The phase is Gaussian, drawn by
Box-Muller from a hash of the grid position, so the same seed gives the same sea. Each wave
then turns at its own deep-water frequency, `sqrt(g·k)`.

Two complex fields share the one transform. The height goes in the first pair of channels.
The two sideways shifts are both real fields, so they pack together as one complex number in
the second pair. One inverse transform therefore carries the whole surface. The resolve reads
the fold out of the same result, as the Jacobian of the sideways shift. That costs four
neighbor reads and no second transform.

The amplitude scale is what makes `waveHeight` exact. The height at a point is the sum of
every wave in the field. Its variance is therefore the sum of the spectrum over the whole
grid. That sum is a closed form of the sea state. The CPU works it out once per sea state and
scales the spectrum by it. That scaling is what makes `waveHeight` a measurement, and it
keeps the height steady when the resolution or the wind changes.

---

Worked example: [`Examples/3D/Geometry/Ocean`](../../Examples/3D/Geometry/Ocean/Sketch.swift).

See also [The frequency domain](../Drawing/Fourier.md) for the transform underneath,
[Strand fields](Strands.md) for the other surface the GPU builds inside the draw call, and
[3D](3D.md) for the camera, lights, and environment around the sea.
