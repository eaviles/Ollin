#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Atmosphere`</sup>

---

## Atmosphere: fog & volumetric light

A rendered scene's air is normally a vacuum: every surface arrives at the eye untouched, however far away it is. Two calls give the air a presence. [`fog`](#fog) makes distance visible - surfaces fade toward the fog color the farther the light travels, so depth reads at a glance and far geometry recedes into atmosphere. [`volumetricLight`](#volumetric) makes the *lights* visible in the air itself - a spot's cone becomes a stage beam, a [cookie](./3D.md#lights) projects patterns through haze, and cast shadows carve crepuscular shafts. Both are per-frame state like the lights and camera: call them in `draw()`, and a frame that calls neither renders exactly as before.

```swift
override func draw() {
    camera(...)
    fog(Color(hex: 0xB4BDC9), density: 0.16, heightFalloff: 0.55)
    // ... draw the scene: near things crisp, far things dissolving low
}
```

### Contents

- [Fog](#fog) - `fog(_:density:heightFalloff:)` / `noFog()`
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

`density` is how thick the air is, in inverse world units: at the default `0.08`, a surface about 9 units away reads half fog. Double it for soup, halve it for haze. The fade is computed exactly (a closed-form transmittance along each eye-to-surface path, not a screen blur), so it costs almost nothing and animating the density is just a parameter moving.

`heightFalloff` above 0 thins the fog with altitude - the density becomes `density · e^(−falloff·height)`, full at height 0 and thinner going up. That is the morning-mist look: column feet drown while their tops rise clear. The integral along a slanted ray still has an exact closed form, so a grazing ray costs the same as a level one.

The fog color is also the air's own glow (the ambient light the mist scatters toward you), so empty sky washes toward it with distance. The air backdrop draws in the same slot as the environment skybox: behind everything 3D, underneath anything 2D you draw.

The example `3D/Effects/Fog` is a colonnade in pooled mist; a new `variation` re-scatters it.

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

`volumetricLight()` marches the air along each view ray and accumulates the light scattered toward the eye, so **directional and spot lights become visible as beams and shafts**. Everything a light carries shapes its beam: the spot's cone and penumbra, a projected [cookie](./3D.md#lights) (the panes of a window gobo read as tilted bars of bright air), an [IES profile](./3D.md#lights)'s measured throw, and - with [`castShadows()`](./3D.md#shadows) - the dark shafts occluders carve out of the beam.

`amount` scales the glow. `anisotropy` (−1…1) is how strongly the medium scatters forward: near 1, beams flare when the view swings toward the light (the headlights-in-fog effect); 0 glows evenly from every angle; the 0.5 default leans gently forward.

It composes with `fog` two ways:

- **With fog**: the beams live in the fog's medium - they ride its density and height falloff, and dim along their own length through it.
- **Without fog** (beams only): the air stays clear and nothing dims; only the beams appear, glowing as if through a thin invisible haze. The dark-stage look: `3D/Lighting/VolumetricLight` is a gobo key and a crossing rim beam over a black set.

<a id="quality"></a>
### Quality

The march's cost is its step count per pixel (one shadow-map read each). It rides the same three-tier `RenderQuality` model as the other sampling knobs ([soft shadows](./3D.md#soft-shadows), the raymarch resolution, the bokeh taps):

```swift
volumetricQuality(.performance)  // 16 steps
volumetricQuality(.default)      // 32 live; exports lift to .detail automatically
volumetricQuality(.detail)       // 64 steps
volumetricSteps(96)              // an exact, hardware-independent count (8…128)
```

The march is deterministic: its per-pixel jitter is a pure function of pixel position, so the same sketch exports the same pixels every time, with no temporal accumulation and no warmup.

<a id="scope"></a>
### What participates

Fog applies to the lit 3D surfaces (solid and textured meshes), the raymarched [SDF fields](../Drawing/Combinators.md), the environment skybox behind them, and the empty air. Ray-traced [reflections](./3D.md#ray-traced-reflections) see a fogged scene too: the reflected leg dims through the same medium, so a mirror never shows a crisply clear copy of a hazed room.

Beams come from **directional and spot** lights. Point and area lights keep lighting surfaces but do not glow in the air: Ollin's punctual lights have no distance falloff, which is fine on a surface but gives an omnidirectional glow no shape to march. Only the shadow-casting light's beam is carved by shadows (the same one-caster rule as the surfaces).

Not fogged, by design: 2D drawing (fog is a property of the 3D air), point-cloud splats and particles (they composite *over* the fogged backdrop, so beams still read through them), matcap surfaces (their whole look is baked into the capture), and the live ground grid (host chrome).

<a id="notes"></a>
### Notes

- Both calls are per-frame state like the lights: set them in `draw()`. The quality setting persists like `shadowQuality`.
- Fog does not need lights: an unlit (`noLights()`) scene still fogs. Only the beams need lights.
- The air's wash is capped at the camera's `far` plane. If a distant scene cuts off oddly, raise `far`.
- A frame that draws no geometry at all skips rendering entirely, air included - beams need at least one mesh in the frame (a floor does it).
- In beams-only mode the beam brightness is referenced to a thin standard haze, so `amount` behaves comparably with and without `fog`.
- An environment's reflection of the *sky* stays clear in mirrors (only traced geometry fogs); under dense fog prefer dimmer environments.
