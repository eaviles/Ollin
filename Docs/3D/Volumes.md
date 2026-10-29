#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Volumes`</sup>

---

## Volumes

A cloud, a column of smoke, a glowing gas, a drop of ink spreading in water: things with no surface, only a thickness that light passes through. A `Volume` is a box of density samples. `drawVolume` draws it in a 3D scene as a medium that blocks light, scatters the scene's lights toward the eye, and can glow by itself. Solids sit inside it: the medium in front of a solid veils it, and the solid hides the medium behind it.

<img src="../Images/Volumes.jpg" alt="Three balls of noisy cloud on a dark floor. On the left, white smoke lit from above by a warm spot, a small ball inside it half veiled by the smoke in front, and the ball's shadow running down through the smoke. In the middle, orange fire glowing from inside, a thin dark ring passing through it. On the right, gray-black ink in front of a pale wall, darkening the wall most where the ink is thickest" width="680">

```swift
let smoke = Volume(width: 48, height: 48, depth: 48) { u, v, w in
    let fromCenter = Vector3(u, v, w).distance(to: Vector3(0.5, 0.5, 0.5))
    return max(0, fbm(u * 4, v * 4, w * 4) - 2 * fromCenter)
}
spotLight(.white, at: Vector3(0, 6, 0), direction: Vector3(0, -1, 0))
drawVolume(smoke, size: 4, medium: .smoke)
```

### The grid

A `Volume` holds `width` by `height` by `depth` samples on a lattice that runs corner to corner across a box. `x` runs along the box's width, `y` up its height, and `z` through its depth toward the viewer. Between samples the value is read trilinearly, and outside the box it is zero. A value of 1 is the medium at its full thickness, and a value below 0 reads as 0.

- **`Volume(width:height:depth:_:)`** calls a function once per sample with `u`, `v`, `w` in `0…1`, corner to corner. This is the usual way to build one, from the sketch's own `fbm`, a distance, or both.
- **`Volume(width:height:depth:values:)`** takes the samples in a list, `x` fastest, then `y`, then `z`. A scan or a simulation's output arrives this way.
- **`Volume(width:height:depth:repeating:)`** is one value everywhere, a uniform block.
- **`Volume.noise(width:height:depth:frequency:octaves:seed:)`** fills a grid with fractal noise across every core. Each sample is the `fbm` a sketch seeded with `noiseSeed(seed)` reads, so it gives what the function form gives over that `fbm`, only faster. The form with `loop:` and `radius:` reads [noise that loops](../Generators/Noise.md#looping-noise-loop), so a grid refilled each frame comes back to where it started.

`subscript(x, y, z)` reads and writes one sample, and `value(u:v:w:)` reads between samples the way the march does. A volume is a value: copies share their samples until one is written. A grid reaches the GPU once, so a volume built in `setup()` costs nothing to draw again.

### A grid a kernel writes

Every form above fills the grid on the CPU, which holds 60 frames a second to about 32 samples a side. For a cloud that changes every frame at a finer grid, a **`ComputeTexture3D`** is the same box of samples kept on the GPU, and a compute kernel of the sketch's own fills it through `compute(_:writing:)`, one thread per sample, the way a [`ComputeTexture`](../Shaders/Compute.md#computetexture) is filled. `drawVolume` takes it in place of a `Volume`:

```swift
let cloud = ComputeTexture3D(width: 128, height: 128, depth: 128)

let fill = ComputeKernel(entry: "cloud", """
    kernel void cloud(texture3d<float, access::write> out [[texture(0)]],
                      constant OllinComputeUniforms &u [[buffer(10)]],
                      uint3 gid [[thread_position_in_grid]]) {
        float3 p = float3(gid) / float3(out.get_width() - 1, out.get_height() - 1, out.get_depth() - 1);
        float fromCenter = distance(p, float3(0.5));
        out.write(float4(max(0.0, fbm(p * 4.0 + u.time * 0.1) - 2.0 * fromCenter)), gid);
    }
""")

override func draw() {
    compute(fill, writing: cloud)                 // refilled every frame
    drawVolume(cloud, size: 4, medium: .cloud)
}
```

The kernel writes the density into each sample's red channel; the samples sit on the same corner-to-corner lattice a `Volume`'s do, `gid` running `x` along the width, `y` up the height, and `z` through the depth. The texture is one 16-bit channel by default and starts at zero, so a volume drawn before its first kernel is empty. A kernel in a `.metal` file beside the sketch loads with `ComputeKernel(entry:resource:in:)`, as the `Volumes` example does. For a field that evolves from its own last state, `PingPongTexture3D` pairs two grids and `compute(_:reading:writing:)` steps them, so a step never reads the grid it is writing. The grid never leaves the GPU: 128 samples a side refill in under a millisecond, and a grid the same samples as a `Volume` draws the same picture to the byte.

### What it is made of

**`drawVolume(_:size:medium:)`** draws the grid filling a cube `size` units on each side, centered at the model origin, and **`drawVolume(_:width:height:depth:medium:)`** fills a box. Both follow `translate`, `rotate`, and `scale` like any solid. The `Medium` says what the box holds:

- **`density`** is how thickly the medium blocks light where the grid reads 1, per world unit, the unit `fog(_:density:)` takes. Light crossing `d` units keeps `exp(-density * d)` of itself, which is Beer's law. At density 0 the medium blocks nothing.
- **`color`** is what the medium does with the light it blocks: each channel, in linear light, is the share it scatters back out. White scatters everything, like a cloud. Black scatters nothing, like soot or ink, and only darkens.
- **`glow`** and **`glowIntensity`** are light the medium gives off itself, per world unit where the grid reads 1. A glow with no density adds over what is behind it, like a hot thin gas. With density, the deep glow is dimmed by the medium in front of it, so a thick glowing ball reads brightest at its center and settles at its glow divided by its density.
- **`anisotropy`**, from -0.95 to 0.95, is which way the medium scatters: 0 evenly, toward 1 mostly onward (a cloud with a light behind it shines at its edges), toward -1 mostly back. It is the same dial `volumetricLight` takes.
- **`bounce`**, from 0 to 1, is how much of the light the medium stops it passes on to itself. At 0 each point is lit once by what reaches it through the medium, so a thick cloud is bright at its lit face and dark a short way in. At 1, the default, the light bounces around inside. The interior glows, the far side keeps some light, and a cloud lit from behind shines through at its thin edges. See [Light and shadow](#light-and-shadow) for what it follows and what it never exceeds.

`Medium(density:color:glow:glowIntensity:anisotropy:bounce:)` builds one from these dials, and each is a property to change on a copy. The presets are `.smoke`, `.cloud`, `.fire`, `.ink`, and `.nebula`, and a `@Param var medium: Medium = .smoke` puts them on the inspector's menu. Every dial scales with the grid, so where it reads 0.5 the medium is half as thick and glows half as bright.

### In front of and behind

Volumes draw after the frame's solids, over the finished picture. Each pixel's ray through the box ends at the first solid it meets. So a solid inside a volume is veiled by the medium in front of it and hides the medium behind it. Call order does not matter: a volume drawn before a solid in `draw()` still ends at it. Several volumes are drawn farthest first, by the distance to each box's center. So two volumes that pass through each other are ordered as wholes. Two boxes whose centers are the same distance away keep their call order, and the later one draws on top. A medium that only glows adds its light whatever its place in that order, so only an absorbing one needs placing. Drawn after a glow over the same box, it dims the glow. Drawn before it, it dims only what lies behind both. A volume drawn into a [layer](../Concepts/Layers.md) does the same over that layer's own solids. The same holds for 2D: a caption drawn after a volume in `draw()` lies under the cloud. Draw anything meant to sit on top in `withOverlay { }`.

### Light and shadow

The medium scatters the scene's directional, point, and spot lights, with a spot's cone, its light profile, and its cookie. It also scatters the flat ambient and, under an `environment`, the environment's light from every side. The light reaching a point inside the medium has crossed the medium on its way there. So a cloud shades itself, lit on the side facing the light and dark on the far side. This self-shadow covers the first four lights in the frame, and further lights scatter without it. A solid between a directional or spot light and the medium throws its shadow into the medium, through the light's shadow map.

**The cloud's shadow.** With `castShadows()` on, the medium throws its shadow onto the solids around it: a floor under a cloud reads darker by the light the cloud keeps from each casting light, and a ball inside the cloud is shadowed by the smoke above it. The shadow is read from the same light-transmittance grid the cloud shades itself by, at the point where the surface's ray toward the light enters the box, so it is exact to the grid's resolution and as soft as the grid is fine. It falls from every light that casts, whatever the kind of its shadow, and covers the first four lights the medium is lit by. A scene that never calls `castShadows()` draws as it always did, and a medium with no `density` casts nothing. Four volumes can cast into one frame, and a surface lit by a scoped light set (`withLights`) takes no cloud's shadow, since only the frame's own lights cast.

**The light the medium bounces to itself.** Light that enters a cloud is scattered again and again before it leaves. That is why a real cloud is white all the way through and glows at its edges against the sun. Following every bounce is out of reach in a frame, so the medium uses the approximation the film and game renderers use, Magnus Wrenninge's octaves. Each light is added several times over. Each time it comes through a shadow thinned to half the one before, so the light reaches twice as deep, at two fifths of the share, and spread toward even. There are eight such octaves, and `bounce` scales the share each one keeps: at 1 the full amount, at 0 a single octave, which is the light taken once. The share never outruns the thinning, so no octave scatters more light than the medium stops. The share is also set so the sum lands on the exact answer for a thick, even, white medium, the one Subrahmanyan Chandrasekhar worked out in 1950. Lit and seen along the normal, such a medium reads 1.06 of a white matte wall under the same light, where a single scattering gives 0.5. The anchor holds at full thickness only. The single scattering under it keeps the fog's convention, about four times what nature gives for the same light. So a thin wisp reads brighter than a real one would beside the same surfaces. A solid's shadow blocks every octave, since the bounce thins only the medium. A light past the first four has no shadow grid and takes one octave.

**Fog.** Under `fog` or `aerialPerspective`, a volume is veiled as a solid is. The medium's light is dimmed by the air in front of it, and the air's own light is added over the share of the pixel the volume covers. Both are read at the volume's mean depth along the ray, the depth of each step weighted by what it covers. A glow with no thickness covers nothing and is only dimmed. A dense slab under fog reads, within a level, as a solid standing where the slab turns opaque.

Some light is not followed:

- **A panel or tube light** scatters nothing in the medium. A point light's shadow, which has no flat map, does not fall into it.
- **The medium's shadow** falls on meshes only: not into fog or a beam, and not onto a raymarched field. A reflection or a refraction through glass does not show the medium.

### Where volumes go

- **Exports.** A still, a video, and the temporal anti-aliasing passes draw volumes. Under temporal anti-aliasing each pass starts its march at a different offset, so their average smooths the march's fine grain.
- **Depth of field and motion blur** read the depth and motion of the solid behind a volume, so a volume in focus in front of a far wall blurs with the wall.
- **Not carried:** a vector export (SVG) leaves volumes out, and a spatial export (USD) skips them. A web page export stops at `drawVolume` and names it, and the sketch exports as video instead.

### What it costs

A grid reaches the GPU once, as half floats, so redrawing a volume costs only its march. Filling one on the CPU costs what its function costs, once per sample. On an M2 in a release build, a 64-sample cube of `Volume.noise` takes 4.9 milliseconds. The same noise through the function form, on one core, takes 24.5. The looping form reads a larger noise lattice and costs about eight times as much: 5.8 milliseconds at 32 samples a side, 18 at 48, and 40 at 64. So a grid refilled every frame on the CPU holds 60 frames a second at about 32 a side. A kernel fills a grid on the GPU for almost nothing: the `Volumes` example's four octaves of noise take 0.1 milliseconds at 64 a side, 0.5 at 96 by 144 by 96, and 0.8 at 128 a side.

The march is the cost. It takes GPU time for each pixel the box covers, at a number of steps for every sample spacing it crosses that follows `volumetricQuality`: one and a half at the live default, one at `.performance`, and two at `.detail`, which every export and test runs at. Each step inside the medium reads the grid, takes a shadow tap, reads each lit light's transmittance, and sums the bounce's octaves. The octaves cost little beside the reads: with the bounce on, the `Volumes` example's frame is about 0.3 milliseconds dearer on an M2. Lighting every other step instead of every one was measured and saves nothing, so every step is lit in full. Each light's transmittance grid is worked out in a compute pass. It is worked out again only when the grid, its placement, or the light changes, which for a grid a kernel rewrites is every frame.

The empty part of the box costs little. The march keeps a map of which blocks of the grid hold anything. It steps past the empty blocks and the margin around the cloud. It skips only steps that would have read nothing, so the picture is the same to the byte. Measured with `--bench --gpu` on an M2, the `Volumes` example's plume takes 7.3 milliseconds a frame at 1080 by 1080. That is a 96 by 144 by 96 grid covering about a third of the frame, with one spot light, its shadow, and temporal anti-aliasing. It takes 8.3 at `.detail`, 18 at 1800 by 1800, and 4.1 with no volume at all. Most of what is left is the light inside the cloud. So a larger or thicker cloud costs more, and a roomy box around it costs almost nothing.

---

See also [Atmosphere](Atmosphere.md) for fog that fills the whole scene and the light shafts in it, [Compute](../Shaders/Compute.md) for the kernels, and the `Environment.clouds` sky for a cloudscape overhead. The [`Volumes`](../../Examples/3D/Effects/Volumes/Sketch.swift) example draws a column of smoke rising from a kernel's repeating noise, with a ball hanging in it and the plume's shadow on the pedestal.
