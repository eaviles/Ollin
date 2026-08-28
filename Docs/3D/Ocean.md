#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `The ocean`</sup>

---

## The ocean

A sea, built the way the ocean is measured. `oceanField(_:)` writes a wave spectrum on the
GPU, which says how much water stands at each wavelength and heading for a given wind, and
one [inverse Fourier transform](../Drawing/Fourier.md) turns that whole field of frequencies
into the moving surface in a single step. `drawOcean(_:)` draws it as water.

Nothing here places a wave, and no wave is animated. What moves is the spectrum's own clock:
a long wave travels faster than a short one, which is why a sea looks like a sea and not
like a shaking sheet.

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

    let sea = oceanField(.breeze)            // the transform runs here
    drawOcean(sea, segments: 320, tiles: 5)
}
```

<a id="the-sea-state"></a>
### The sea state

`Ocean` is the physics: how hard the wind has blown, and for how long.

**`waveHeight` is a measurement, not a dial.** It is the significant wave height in world
units, what a sailor means by the height of a sea: the average of the tallest third, four
times the surface's standard deviation. Ask for 3 and the water stands 3, whatever else is
set, because the scale is worked out from a closed form of the spectrum rather than tuned by
eye. It holds across grid sizes and wind speeds, and the tests measure it off the GPU's own
output.

**`windSpeed` decides *which* waves carry that height.** The longest wave a wind can raise
grows with the square of its speed, so a high number moves the energy into long, slow swell
and a low one into short chop. The height stays where you put it either way.

**`choppiness`** moves water sideways toward the crests, which is what makes them narrow and
the troughs wide. At 0 the surface is the plain sum of its waves, which is round and soft;
past about 1.5 the crests fold through themselves, which shows up as foam rather than as
shape.

**`patchSize`** is the width of one period in world units, and it is the scale everything
else is read against: a 200 unit patch holding a 2 unit wave is open water, and a 20 unit
patch holding the same wave is a pond.

The rest shape it further: `windDirection` (degrees, in the ground plane), `smallestWave`
(ripples shorter than this are damped out, since a field cannot carry detail below two of
its own texels), `spread` (how tightly the waves line up with the wind), `loopSeconds` (see
below), and `seed`.

Four presets to start from: `.calm`, `.breeze` (the default), `.swell`, `.storm`.

<a id="the-field"></a>
### The field

`oceanField` returns an `OceanField`. That is one frame of the sea. It is per-frame work
like a generator. Call it in `draw()`.

```swift
let sea = oceanField(.swell, resolution: 512)
```

`resolution` is how many texels the field carries along each side (256 by default), rounded
to the nearest power of two between 32 and 1024, because that is what the transform works
on. Higher carries finer chop and costs more passes.

The field is an ordinary layer underneath (`sea.layer`, `sea.image`), holding the surface in
world units: red and blue are how far each point has moved sideways, green is how high it
stands, and alpha is how hard the surface is folding there. It is signed data rather than a
picture, so most of it draws as black until it is mapped through a filter, but everything
that works on a layer works on it.

To scrub, or to run the water at its own speed, name the instant:

```swift
let sea = oceanField(.breeze, at: time * 0.4)
```

**A looping sea.** With `loopSeconds` set, every wave's frequency is rounded down to a
multiple of one step, which makes the whole surface repeat exactly on that period. A ten
second export then loops with no seam. It coarsens the motion a little, so keep the period
long unless a short loop is the point.

<a id="drawing-it"></a>
### Drawing it

```swift
let sea = oceanField(.breeze)
drawOcean(sea, segments: 320, tiles: 5, water: .open)
```

`segments` is how finely the grid is cut. `tiles` is how many periods of the field the water
covers, which is how it reaches the horizon without the waves growing.

The transform stack places the patch, so `translate`/`rotate`/`scale` before the call move
the whole sea. The current camera decides the view, and the call is a no-op without one.

There is no geometry anywhere: each vertex works out which corner of which cell it is from
its own index and reads the field for where the water has carried it. `segments: 320` is
614,400 vertices from a call that uploads nothing.

<a id="how-it-looks"></a>
### How the water looks

`WaterSurface` is the look, separate from the physics:

- `deep` and `shallow`, the water where it is flat and where a crest stands up
- `sky`, what a flat surface reflects when no environment is set
- `foam` and `foamAmount`, the color of a folding crest and how much of a fold turns white
- `reflectance`, how much light the surface returns looked at straight down (0.02 is water)
- `glitter` and `glitterTightness`, the sun's own highlight

Four to start from: `.open`, `.tropical`, `.dusk`, `.ink`.

With an environment set (`environment(.sky(...))` or a loaded HDRI) the surface reflects that
environment, and the water and the sky behind it agree. The first directional light in the
scene is the sun the glitter comes from; with no light set the water is body color and
reflection alone.

<a id="cost"></a>
### What it costs

The field is one spectrum pass, `2 · log2(n)` butterfly passes, and one resolve: 18 passes at
256 texels, 20 at 512, each over a small square. The draw is `segments² · 6` vertices and
four texture reads per pixel for the normal.

Measured on an M2 at 1080 square, with the sky environment and a sun (`Scripts/benchmark.sh
ocean`): **1.4 ms** of GPU at 160 segments over a 256 field, **1.8 ms** at 320 over 256,
**2.8 ms** at 320 over 512, and **3.7 ms** at 512 over 512. Doubling either the grid or the
field costs about a millisecond at this size.

<a id="limits"></a>
### What it will not do

- **The surface is not in the shadow map, the ray-traced structures, or a vector or spatial
  export.** Like a strand field, its geometry exists only inside the draw call, so nothing
  that walks the scene's geometry can see it.
- **`material(_:)` does not apply.** Water is a reflection and a body color rather than a
  material, so it shades through its own fragment. `WaterSurface` is the whole of its look.
- **A tiled sea repeats.** The field is one period, and `tiles` lays that period out again
  and again, which a viewer can see in a still if the patch is small and the tiling wide. A
  larger `patchSize` with more texels is the answer.
- **There is nothing under the water.** No refraction, no bottom, no floating bodies. A
  reflected ray that dips below the horizon is read mirrored off the surface, which keeps the
  reflection continuous rather than showing the environment's flat ground.

<a id="how-it-works"></a>
### How it works

The spectrum is the Phillips form for a wind-driven sea, written from Tessendorf's published
account and credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md). Each wave vector gets an
amplitude from that spectrum and a random phase (Gaussian, by Box-Muller from a hash of the
grid position, so the same seed is the same sea), then turns at its own deep-water frequency,
`sqrt(g·k)`.

Two complex fields ride the one transform: the height in the first pair of channels, and the
two sideways shifts packed as one complex number in the second, since both are real fields.
One inverse transform therefore carries the whole surface. The resolve reads the fold out of
the same result, as the Jacobian of the sideways shift, which costs four neighbor reads and
no second transform.

The amplitude is the part worth knowing about. The height at a point is the sum of every
wave in the field, so its variance is the sum of the spectrum over the whole grid. That sum
is a closed form of the sea state, so the CPU works it out once per sea state and scales the
spectrum by it. That is what turns `waveHeight` from a dial into a measurement, and what
keeps it steady when the resolution or the wind changes.

---

Worked example: [`Examples/3D/Geometry/Ocean`](../../Examples/3D/Geometry/Ocean/Sketch.swift).

See also [The frequency domain](../Drawing/Fourier.md) for the transform underneath,
[Strand fields](Strands.md) for the other surface the GPU builds inside the draw call, and
[3D](3D.md) for the camera, lights, and environment around it.
