#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Atmosphere`</sup>

---

## Atmosphere: fog, aerial perspective & volumetric light

A rendered scene's air is normally a vacuum: every surface arrives at the eye untouched, however far away it is. Three calls give the air a presence.

[`fog`](#fog) makes distance visible. Surfaces fade toward the fog color the farther the light travels, so depth reads at a glance and far geometry recedes into atmosphere. [`aerialPerspective`](#aerial) is fog's physical cousin for outdoor scale. The fade is split by wavelength and lit by the sun. Far ridges veil blue and melt into the sky instead of into one flat color. [`volumetricLight`](#volumetric) makes the *lights* visible in the air itself. A spot's cone becomes a stage beam, a [cookie](./3D.md#lights) projects patterns through haze, and cast shadows carve crepuscular shafts.

All are per-frame state like the lights and camera. Call them in `draw()`, and a frame that calls none renders exactly as before.

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

`density` is how thick the air is, in inverse world units. At the default `0.08`, a surface about 9 units away reads half fog. Double it for soup, halve it for haze. The fade is computed exactly, as a closed-form transmittance along each eye-to-surface path rather than a screen blur. So it costs almost nothing, and animating the density is just a parameter moving.

`heightFalloff` above 0 thins the fog with altitude. The density becomes `density · e^(−falloff·height)`, full at height 0 and thinner going up. That is the morning-mist look: column feet drown while their tops rise clear. The integral along a slanted ray still has an exact closed form, so a grazing ray costs the same as a level one.

The fog color is also the air's own glow, the ambient light the mist scatters toward you. Empty sky washes toward it with distance. The air backdrop draws in the same slot as the environment skybox: behind everything 3D, underneath anything 2D you draw.

The example `3D/Effects/Fog` is a colonnade in pooled mist; a new `variation` re-scatters it.

<a id="aerial"></a>
### Aerial perspective

```swift
aerialPerspective()                                  // scale-aware defaults
aerialPerspective(density: 0.008, haziness: 0.3)     // your own air
aerialPerspective(density: 0.01, sun: Vector3(1, 0.3, 0))
noAerialPerspective()
```

Fog paints every distance the same color; real outdoor air does two different things at once. The light *from* a far surface loses its short wavelengths first, by the 1/λ⁴ law, so a distant ridge warms and darkens. Meanwhile sunlight scatters *into* the view path along the way. It veils the same ridge in blue from the side, and in a bright whiter glow toward the sun.

`aerialPerspective()` computes both in closed form, the same exact integral as fog, split by wavelength. That is the depth cue that makes a landscape read as kilometers instead of meters. It replaces `fog` for the frame, since the last call wins, and `volumetricLight` beams ride it exactly as they ride fog.

- **`density`** is the optical depth per world unit, like fog's, except it decides *where the scale illusion sits*. At `0.008` a surface 60 units away is about 40% veiled, so a 200-unit scene reads like a mountain range. Leave it `nil` and a default derives from the camera framing, as a fraction of the eye-to-target distance, so a bare call reads alike at any scene scale.
- **`haziness`** (0…1, default 0.3) is how much of the air is aerosol rather than molecules. At 0 the veil is the crisp Rayleigh blue-shift of a clear day. At 1 it is a gray haze whose forward-scattering lobe puts a strong halo around the sun.
- **`heightFalloff`** thins the air with altitude exactly as in `fog`: valley haze under clear peaks.
- **`sun`** points **toward** the sun. Leave it `nil` and it resolves from the [`.sky` environment](./3D.md#environment), rotation included, so the haze follows the sky's own sun. Failing that it takes the first directional light, then a pleasant default. The sun's light warms automatically as it drops, so a horizon sun feeds the air sunset color.

Two behaviors are worth knowing. Over long paths the veil *saturates* toward the sky's own tone, so a silhouette at great distance melts seamlessly into the horizon. That convergence is the effect working, not washout. If the whole frame looks milky, the density is high for the framing.

Behind an environment skybox the air veil deliberately steps aside. The sky already *is* this scattering carried to infinity, so painting more would double-count. With no environment, the air paints its own implied horizon glow over the 2D clear.

The example `3D/Effects/AerialPerspective` is a file of ridgelines stepping away under a procedural sky, with the density, haziness, and sun on knobs.

<a id="volumetric"></a>
### Volumetric light

```swift
spotLight(.white, at: Vector3(-4, 6, 3), direction: Vector3(0.6, -0.7, -0.3),
          angle: .pi / 8, cookie: gobo)
castShadows()
volumetricLight()                     // the beams appear
volumetricLight(0.7, anisotropy: 0.8) // dimmer, flaring hard toward the light
noVolumetricLight()
```

`volumetricLight()` marches the air along each view ray and accumulates the light scattered toward the eye. So **directional and spot lights become visible as beams and shafts**. Everything a light carries shapes its beam: the spot's cone and penumbra, a projected [cookie](./3D.md#lights), an [IES profile](./3D.md#lights)'s measured throw. The panes of a window gobo read as tilted bars of bright air. And with [`castShadows()`](./3D.md#shadows), occluders carve dark shafts out of the beam.

`amount` scales the glow. `anisotropy` (−1…1) is how strongly the medium scatters forward. Near 1, beams flare when the view swings toward the light, the headlights-in-fog effect. At 0 the air glows evenly from every angle, and the 0.5 default leans gently forward.

It composes with `fog` two ways:

- **With fog**: the beams live in the fog's medium. They ride its density and height falloff, and dim along their own length through it.
- **Without fog**, beams only: the air stays clear and nothing dims. Only the beams appear, glowing as if through a thin invisible haze. That is the dark-stage look. `3D/Lighting/VolumetricLight` is a gobo key and a crossing rim beam over a black set.

<a id="quality"></a>
### Quality

The march's cost is its step count per pixel, one shadow-map read each. It rides the same three-tier `RenderQuality` model as the other sampling knobs: [soft shadows](./3D.md#soft-shadows), the raymarch resolution, the bokeh taps.

```swift
volumetricQuality(.performance)  // 16 steps
volumetricQuality(.default)      // 32 live; exports lift to .detail automatically
volumetricQuality(.detail)       // 64 steps
volumetricSteps(96)              // an exact, hardware-independent count (8…128)
```

The march is deterministic. Its per-pixel jitter is a pure function of pixel position, so the same sketch exports the same pixels every time. There is no temporal accumulation and no warmup.

<a id="scope"></a>
### What participates

Fog applies to the lit 3D surfaces (solid and textured meshes), the raymarched [SDF fields](../Drawing/Combinators.md), the environment skybox behind them, and the empty air. Ray-traced [reflections](./3D.md#ray-traced-reflections) see a fogged scene too. The reflected leg dims through the same medium, so a mirror never shows a crisply clear copy of a hazed room. Aerial perspective reaches the same carriers, with the skybox exception above: the sky keeps its own color.

Beams come from **directional and spot** lights. Point and area lights keep lighting surfaces but do not glow in the air. Ollin's punctual lights have no distance falloff, which is fine on a surface but gives an omnidirectional glow no shape to march. Every shadow-casting light's beam is carved, each by what stands in it, so a frame with two casting spots gets two sets of shafts.

Four things are not fogged, by design. **2D drawing**, since fog is a property of the 3D air. **Point-cloud splats and particles**, which composite *over* the fogged backdrop, so beams still read through them. **Matcap surfaces**, whose whole look is baked into the capture. And **the live ground grid**, which is host chrome.

<a id="notes"></a>
### Notes

- Both calls are per-frame state like the lights, so set them in `draw()`. The quality setting persists like `shadowQuality`.
- Fog does not need lights: an unlit (`noLights()`) scene still fogs. Only the beams need lights.
- The air's wash is capped at the camera's `far` plane. If a distant scene cuts off oddly, raise `far`.
- A frame that draws no geometry at all skips rendering entirely, air included. Beams need at least one mesh in the frame, and a floor does it.
- In beams-only mode the beam brightness is referenced to a thin standard haze, so `amount` behaves comparably with and without `fog`.
- An environment's reflection of the *sky* stays clear in mirrors, since only traced geometry fogs. Under dense fog, prefer dimmer environments.
- Volumetric **clouds** are the environment's half of the atmosphere. They bake into the procedural sky (`.sky(...).clouds(...)`) rather than marching per frame, so the backdrop, lighting, and reflections share one weather. See [3D ▸ Clouds over the procedural sky](./3D.md#sky-clouds).
