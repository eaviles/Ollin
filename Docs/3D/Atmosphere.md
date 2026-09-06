#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Atmosphere`</sup>

---

## Atmosphere: fog, aerial perspective & volumetric light

By default, the air in a rendered scene is a vacuum, so every surface reaches the eye unchanged, however far away it is. Three calls make the air visible.

[`fog`](#fog) makes distance visible. The farther light travels to reach the eye, the more a surface fades toward the fog color. Depth then reads at a glance, and far geometry recedes into the air. [`aerialPerspective`](#aerial) is the physical form of fog, for outdoor scale. Its fade is split by wavelength and lit by the sun. Far ridges then turn blue and blend into the sky instead of into one flat color. The third call, [`volumetricLight`](#volumetric), makes the *lights* themselves visible in the air. A spot's cone becomes a stage beam, and a [cookie](./3D.md#lights) projects its pattern through the haze. Cast shadows cut dark shafts, called crepuscular rays, out of the beam.

All three are per-frame state, like the lights and the camera. Call them in `draw()`. A frame that calls none of them renders exactly as it did before.

```swift
override func draw() {
    camera(...)
    fog(Color(hex: 0xB4BDC9), density: 0.16, heightFalloff: 0.55)
    // ... draw the scene: near things crisp, far things dissolving low
}
```

### Contents

- [Fog](#fog) - `fog(_:density:heightFalloff:)` / `noFog()`
- [Aerial perspective](#aerial) - `aerialPerspective(density:haziness:heightFalloff:sun:)` / `noAerialPerspective()`
- [Volumetric light](#volumetric) - `volumetricLight(_:anisotropy:)` / `noVolumetricLight()`
- [Quality](#quality) - `volumetricQuality(_:)` / `volumetricSteps(_:)`
- [What participates](#scope)
- [Notes](#notes)

<a id="fog"></a>
### Fog

```swift
fog(Color(hex: 0xB4BDC9), density: 0.08)                      // even haze
fog(Color(hex: 0xB4BDC9), density: 0.16, heightFalloff: 0.55) // low-lying mist
noFog()
```

`density` is how thick the air is, in inverse world units. At the default `0.08`, a surface about 9 units away is half covered by fog. Double the density for thick fog, and halve it for a light haze. The fade is computed exactly, as a closed-form transmittance along each path from the eye to the surface, not as a screen blur. So it costs almost nothing, and animating the density only changes a parameter.

`heightFalloff` above 0 thins the fog with altitude. The density becomes `density · e^(−falloff·height)`, which is the full density at height 0 and less as the height increases. That gives the look of morning mist, where the base of a column sinks into the fog while its top stays clear. The integral along a slanted ray still has an exact closed form, so a grazing ray costs the same as a level one.

The fog color is also the glow of the air itself, the ambient light the mist scatters toward you. Empty sky fades toward that color with distance. The air backdrop draws in the same slot as the environment skybox: behind everything 3D, and under anything 2D you draw.

The example `3D/Effects/Atmosphere` is a colonnade standing in pooled mist. Hold space to switch it to aerial perspective, and a new `variation` scatters the scene again.

<a id="aerial"></a>
### Aerial perspective

```swift
aerialPerspective()                                  // scale-aware defaults
aerialPerspective(density: 0.008, haziness: 0.3)     // your own air
aerialPerspective(density: 0.01, sun: Vector3(1, 0.3, 0))
noAerialPerspective()
```

Fog paints every distance the same color, but real outdoor air does two different things at once. The light *from* a far surface loses its short wavelengths first, by the 1/λ⁴ law, so a distant ridge turns warmer and darker. At the same time, sunlight scatters *into* the view path along the way. That scattered light veils the same ridge in blue when the sun is to the side. When you look toward the sun, the veil is a brighter, whiter glow.

<img src="../../Guide/Images/21-3DGently/DistantAir.jpg" alt="A file of dark ridgelines stepping away under a pale sky, each silhouette a step paler and bluer than the one in front, the farthest melting into the horizon, the air brightening toward the sun on the right" width="680">

`aerialPerspective()` computes both effects in closed form. It uses the same exact integral as fog, split by wavelength. That is the depth cue that makes a landscape read as kilometers instead of meters. It replaces `fog` for the frame, because the last call wins. `volumetricLight` beams follow it exactly as they follow fog.

- **`density`** is the optical depth per world unit, as in fog. Here it also decides how large the scene appears. At `0.008` a surface 60 units away is about 40% veiled, so a 200-unit scene reads like a mountain range. Leave it `nil` and Ollin derives the default from the camera framing, as a fraction of the distance from the eye to the target. So a bare call reads the same at any scene scale.
- **`haziness`** (0…1, default 0.3) is how much of the air is aerosol rather than molecules. At 0 the veil is the sharp Rayleigh blue shift of a clear day. At 1 it is a gray haze, and its forward-scattering lobe puts a strong halo around the sun.
- **`heightFalloff`** thins the air with altitude, exactly as in `fog`. That gives haze in the valleys under clear peaks.
- **`sun`** points **toward** the sun. Leave it `nil` and the direction comes from the [`.sky` environment](./3D.md#environment), rotation included, so the haze follows the sky's own sun. If there is no sky environment, the direction comes from the first directional light. If there is no directional light either, Ollin uses a pleasant default. The sun's light warms automatically as the sun drops, so a sun at the horizon gives the air a sunset color.

Two behaviors are worth knowing. Over long paths the veil *saturates* toward the sky's own tone, so a silhouette at a great distance blends smoothly into the horizon. That convergence is the effect working as intended, not washout. If the whole frame looks milky, the density is too high for the framing.

Behind an environment skybox, Ollin deliberately does not apply the air veil. The sky already *is* this same scattering carried to infinity, so painting more of it would count it twice. With no environment, the air paints its own implied horizon glow over the 2D clear color.

The example `3D/Effects/Atmosphere` shows the aerial haze over the same colonnade its fog mode uses. The density, haziness, and sun are parameters.

<a id="volumetric"></a>
### Volumetric light

```swift
spotLight(.white, at: Vector3(-4, 6, 3), direction: Vector3(0.6, -0.7, -0.3),
          coneAngle: .pi / 8, cookie: gobo)
castShadows()
volumetricLight()                     // the beams appear
volumetricLight(0.7, anisotropy: 0.8) // dimmer, flaring hard toward the light
noVolumetricLight()
```

`volumetricLight()` marches through the air along each view ray and adds up the light scattered toward the eye. So **directional and spot lights become visible as beams and shafts**. Everything a light carries shapes its beam: the spot's cone and penumbra, a projected [cookie](./3D.md#lights), and the measured throw of an [IES profile](./3D.md#lights). The panes of a window gobo read as tilted bars of bright air. With [`castShadows()`](./3D.md#shadows), objects that stand in the beam cut dark shafts out of it.

<img src="../../Guide/Images/21-3DGently/VisibleAir.jpg" alt="A dark set under a warm window-gobo beam slanting down from the upper left: the panes read as bars of bright air, land as a window of light on the floor, and a cylinder, sphere, and box carve dark shafts out of the beam. A faint cool beam crosses low behind the props" width="680">

`amount` scales the glow. `anisotropy` (−1…1) is how strongly the medium scatters forward. Near 1, beams flare when the view turns toward the light, like headlights in fog. At 0 the air glows evenly from every angle. The default of 0.5 leans a little toward forward scattering.

It combines with `fog` in two ways:

- **With fog**: the beams live in the fog's medium. They follow its density and height falloff, and they dim along their own length as they pass through it.
- **Without fog**, beams only: the air stays clear and nothing dims. Only the beams appear, and they glow as if through a thin invisible haze. That is the dark-stage look. The example `3D/Lighting/VolumetricLight` is a gobo key light and a crossing rim beam over a black set.

<a id="quality"></a>
### Quality

The cost of the march is its step count per pixel, with one shadow-map read per step. It uses the same three-tier `RenderQuality` model as the other sampling parameters: [soft shadows](./3D.md#soft-shadows), the raymarch resolution, and the bokeh taps.

```swift
volumetricQuality(.performance)  // 16 steps
volumetricQuality(.default)      // 32 live; exports lift to .detail automatically
volumetricQuality(.detail)       // 64 steps
volumetricSteps(96)              // an exact, hardware-independent count (8…128)
```

The march is deterministic. Its per-pixel jitter is a pure function of the pixel position, so the same sketch exports the same pixels every time. There is no temporal accumulation and no warmup.

<a id="scope"></a>
### What participates

Fog applies to the lit 3D surfaces (solid and textured meshes), the raymarched [SDF fields](../Drawing/Combinators.md), the environment skybox behind them, and the empty air. Ray-traced [reflections](./3D.md#ray-traced-reflections) see a fogged scene too. The reflected leg dims through the same medium, so a mirror never shows a clear copy of a hazed room. Aerial perspective reaches the same carriers, with the skybox exception above, where the sky keeps its own color.

Beams come from **directional and spot** lights. Point and area lights still light surfaces, but they do not glow in the air. Ollin's punctual lights have no distance falloff. That is fine on a surface, but it makes a point light glow in every direction, which leaves the march no shape to follow. Every shadow-casting light's beam is cut by what stands in it, so a frame with two casting spots gets two sets of shafts.

Four things are not fogged, by design. Fog is a property of the 3D air, so **2D drawing** stays clear. Beams still read through **point-cloud splats and particles**, because they composite *over* the fogged backdrop. A **matcap surface** keeps its look, because that look is baked into the capture. The **live ground grid** is host chrome, so it stays clear too.

<a id="notes"></a>
### Notes

- All three calls are per-frame state, like the lights, so set them in `draw()`. The quality setting persists, like `shadowQuality`.
- Fog does not need lights. An unlit (`noLights()`) scene still fogs. Only the beams need lights.
- The air's wash stops at the camera's `far` plane. If a distant scene cuts off in an odd way, raise `far`.
- A frame that draws no geometry at all skips rendering entirely, air included. So beams need at least one mesh in the frame, and a floor is enough.
- In beams-only mode, the beam brightness is measured against a thin standard haze, so `amount` behaves about the same with and without `fog`.
- An environment's reflection of the *sky* stays clear in mirrors, because only traced geometry fogs. Under dense fog, prefer dimmer environments.
- Volumetric **clouds** are the environment's half of the atmosphere. They bake into the procedural sky (`.sky(...).clouds(...)`) instead of marching each frame, so the backdrop, lighting, and reflections share one weather. See [3D ▸ Clouds over the procedural sky](./3D.md#sky-clouds).
