#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Caustics`</sup>

---

## Caustics: the light glass and metal focus

A shadow shows where light cannot reach. A caustic shows where a lens or a mirror concentrated light instead. The bright loop under a wine glass is one example. Others are the moving net of light a chrome ring throws beside itself, and the colored spill through a stained-glass pane. Direct lighting cannot produce any of these, because it stops at the first object between a surface and the light.

`caustics()` renders that missing light. The renderer traces photons from the caster light through every transmissive surface ([`Material.glass`](./3D.md#materials)) and every mirror-polished metallic surface. It follows each photon through up to eight refractions and reflections. Where the photon lands, the renderer draws a small elliptical spot. The shape of that spot comes from how the path focused. A converging path draws a small, bright spot. A spreading path draws a wide, dim spot with the same total energy. That is why the patterns come out sharp and without noise.

<img src="../../Guide/Images/26-SculptingWithFields/CausticLight.jpg" alt="Two glass spheres and a chrome ring on a sunlit matte table. The clear sphere throws a tight bright spot inside its own shadow, the bottle-green sphere throws a green-tinted one, and the ring, lying almost flat, folds light into a radial fan across its middle" width="680">

```swift
override func draw() {
    camera(...)
    directionalLight(.white, direction: Vector3(-0.3, -1, -0.2))
    castShadows()
    caustics()

    material(.glass(thickness: 1.8))
    drawSphere(radius: 0.9)          // throws its bright spot into its own shadow
}
```

`caustics()` is per-frame state, like the lights and the camera, so call it in `draw()` after both of them. A frame that does not call it renders exactly as before.

### Contents

- [Turning it on](#on) - `caustics(intensity:dispersion:)` / `noCaustics()`
- [What casts, what receives](#casts)
- [The light that emits](#light)
- [Dispersion](#dispersion)
- [Quality](#quality) - `causticsQuality(_:)`
- [How it works](#how)
- [Notes](#notes)

<a id="on"></a>
### Turning it on

```swift
caustics()                                  // physical brightness, no dispersion
caustics(intensity: 1.6)                    // brighter than physical, for drama
caustics(intensity: 1, dispersion: 0.5)     // split refracted light by wavelength
noCaustics()                                // back off (the default)
```

- `intensity` scales the brightness of every pattern. `1` is physical brightness. Where nothing focuses, the caustic adds back exactly the light that the glass removed from the direct path.
- `dispersion` splits refracted photons by wavelength, from `0` (no split) to `1` (a full rainbow). See [Dispersion](#dispersion).

Caustics need a ray-tracing GPU (Apple silicon), an active 3D camera, and a light. Without all three, the call does nothing. If no material in the frame casts, the feature does no work and costs nothing.

<a id="casts"></a>
### What casts, what receives

Casting is automatic. The renderer reads it from the materials in the frame:

- **Transmissive surfaces cast refractive caustics.** This means any mesh drawn with [`Material.glass`](./3D.md#materials). Photons refract at each interface, weighted by Fresnel, so a pane seen at a grazing angle reflects more light than it passes. The photons take the glass's `fill` as a tint. Inside a solid, they darken by its `attenuationColor` over the distance they travel, so bottle-green glass throws a bottle-green spot. A photon that meets total internal reflection bounces inside the solid and continues.
- **Mirror-polished metals cast reflective caustics.** A physically based metal with a roughness below about `0.25` reflects its photons onward, tinted by the metal's color.
- **Everything else receives.** The first rough opaque surface that a photon reaches gets the light, shaded with that surface's own color and finish. A matte surface takes the light as diffuse. A glossier surface streaks it toward the eye, in the same way that it streaks its lights.

A photon that never crosses a caster is dropped. Light that goes straight from the sun to the floor is the direct lighting the scene already has. Caustics never add that light a second time.

<a id="light"></a>
### The light that emits

One light emits the photons. The renderer chooses it the same way the [shadow system](./3D.md#shadows) chooses its caster. The renderer uses the `castShadows()` caster if it is a directional, spot, or point light. Otherwise it uses the first directional light, then the first spot light, then the first point light. A directional sun emits a patch of parallel photons fitted over the casting geometry. A spot light emits over its own cone. A point light emits over the cone that covers the casters, so no photon is wasted on empty sky.

Caustics work well with `castShadows()`. The glass's shadow goes dark and the focused spot lands *inside* it, which is exactly how a glass on a sunlit table looks.

<a id="dispersion"></a>
### Dispersion

White light contains every wavelength at once, and glass bends each wavelength slightly differently. `dispersion:` gives each photon its own wavelength. The photon's refraction index shifts by a few percent across the visible range. The renderer tints the photon's energy so that all the photons together still sum to white. At `0` there is no split. At `1` a prism edge fans out into a full rainbow, and even the spot from a plain sphere picks up red and blue fringes. The scale is the same as a material's own [`dispersion`](3D.md#glass), which fringes the *view* through a solid body. So a prism that throws its light at `caustics(dispersion: 0.3)` fringes what shows through it at `.glass(thickness: 2, dispersion: 0.3)`.

```swift
caustics(dispersion: 1)
material(.glass(ior: 1.6, thickness: 1))
drawExtrude(triangle, depth: 2)             // a prism, fanning its rainbow
```

<a id="quality"></a>
### Quality

```swift
causticsQuality(.detail)      // more photons, finer patterns
```

`causticsQuality(_:)` is the caustics counterpart of `shadowQuality`, and it scales with the GPU. `.performance` favors frame rate and gives a coarser pattern. `.detail` traces more photons and gives a finer pattern. `.default` is the balanced choice for the hardware. Exports and snapshots use `.detail` automatically. The setting persists, so set it once in `setup()` or `draw()`.

<a id="how"></a>
### How it works

The technique is photon mapping, in its adaptive real-time form (see `ATTRIBUTION.md`, Techniques). Each frame, the renderer emits a budget of photons from the light, guided by a light-space density map. The emission adapts from frame to frame. Photons concentrate where the pattern is detailed or still flickering, and they thin out where it is smooth. Every photon carries *differentials*, which are two neighbor offsets updated through each refraction and reflection, including the surface's curvature. When the photon lands, its footprint is the true image of the small patch of light it started as. The footprints draw additively into a screen-space layer, and each one is an ellipse shaded with the receiving surface's own attributes. The lit surfaces then add that layer back. In a live window, the renderer accumulates the layer over time. An export instead emits photons uniformly at the full budget within its one frame. A still or a video is therefore a pure function of each frame.

<a id="notes"></a>
### Notes

- **Screen-space apply.** Caustics land only on what the camera sees directly. A caustic on a surface that is seen only in a mirror, or only through glass, does not appear there.
- **Sharp caustics from rough glass.** Photon paths treat every caster as polished, because roughness does not widen the differentials. So a frosted glass still throws a sharp pattern. The *view* through the glass is frosted, but the light it casts is not.
- **One caster light** per frame emits photons. The other lights shade normally.
- **Glass refracts, metal reflects.** A glass surface's own specular reflection does not spawn a second family of photons. Tracing both would double the cost. Only a mirror-polished metal's reflection spawns photons.
- **Area lights** (rect/disk/tube) do not emit photons yet. The soft-caustics extension is a follow-up.
- The example is [`Examples/3D/Lighting/Caustics`](../../Examples/3D/Lighting/Caustics/Sketch.swift). Run it with `swift run --package-path Examples Example-3D-Lighting-Caustics`.
