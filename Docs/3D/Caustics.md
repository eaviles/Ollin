#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Caustics`</sup>

---

## Caustics: the light glass and metal focus

A shadow says where light can't reach. A caustic says where a lens or a mirror concentrated it instead. It is the bright loop under a wine glass, the dancing net a chrome ring throws beside itself, the colored spill through a stained pane. Direct lighting can't see any of it, because it stops at the first thing between a surface and the light.

`caustics()` renders that missing light. The renderer traces photons from the caster light through every transmissive ([`Material.glass`](./3D.md#materials)) and mirror-polished metallic surface. It follows each one through up to eight refractions and reflections, and draws where it lands as a small elliptical spot whose shape comes from how the path focused. A converging path draws small and bright. A spreading one draws wide and dim, with the same total energy. That is why the patterns come out sharp without noise.

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

Per-frame state like the lights and camera: call it in `draw()`, after both. A frame that doesn't call it renders exactly as before.

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

- `intensity` scales the brightness of every pattern. `1` is physical. Where nothing focuses, the caustic adds back exactly the light the glass took out of the direct path.
- `dispersion` splits refracted photons by wavelength, `0` (none) to `1` (full rainbow). See [Dispersion](#dispersion).

Needs a ray-tracing GPU (Apple silicon), an active 3D camera, and a light; a no-op otherwise. Inert (and free) while no material in the frame casts.

<a id="casts"></a>
### What casts, what receives

Casting is automatic, read from the materials in the frame:

- **Transmissive surfaces cast refractive caustics.** Any mesh drawn with [`Material.glass`](./3D.md#materials). Photons refract at each interface, weighted by Fresnel, so a grazing pane reflects more than it passes. They take the glass's `fill` as a tint, and darken through a solid's interior by its `attenuationColor` over the traveled span. Bottle-green glass throws a bottle-green spot. Total internal reflection bounces inside the solid and carries on.
- **Mirror-polished metals cast reflective caustics.** A physically based metal with roughness below about `0.25` reflects its photons onward, tinted by the metal's color.
- **Everything else receives.** The first rough opaque surface a photon reaches gets the light, shaded with that surface's own color and finish. Matte surfaces take it as diffuse. Glossier ones streak it toward the eye the way they streak their lights.

A photon that never crosses a caster is dropped. Light going straight from the sun to the floor is the direct lighting the scene already has, and caustics never double it.

<a id="light"></a>
### The light that emits

One light emits the photons, chosen the way the [shadow system](./3D.md#shadows) picks its caster. The `castShadows()` caster wins if it is a directional, spot, or point light. Otherwise the first directional light does, then the first spot, then the first point. A directional sun emits a fitted patch of parallel photons over the casting geometry. A spot emits over its own cone, and a point over the cone that covers the casters, so no photon is wasted on empty sky.

Caustics pair naturally with `castShadows()`. The glass's shadow goes dark, the focused spot lands *inside* it, and that is exactly how a glass on a sunlit table looks.

<a id="dispersion"></a>
### Dispersion

White light is every wavelength at once, and glass bends each one slightly differently. `dispersion:` gives each photon its own wavelength. Its refraction index shifts a few percent across the visible range, and its energy is tinted so the ensemble still sums to white. At `0` there is no split. At `1` a prism edge fans into a full rainbow, and even a plain sphere's spot picks up red and blue fringes.

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

`causticsQuality(_:)` is the `shadowQuality` dial's caustics sibling, and it scales with the GPU. `.performance` favors frame rate with a coarser pattern. `.detail` traces more photons for a finer one, and `.default` is the balanced choice for the hardware. Exports and snapshots resolve `.detail` automatically. Persistent; set it once in `setup()` or `draw()`.

<a id="how"></a>
### How it works

Photon mapping, in the adaptive real-time form (see `ATTRIBUTION.md`, Techniques). Each frame the renderer emits a budget of photons from the light, guided by a light-space density map. The emission adapts, frame to frame. Photons concentrate where the pattern is detailed or still flickering, and thin out where it is smooth. Every photon carries *differentials*, two neighbor offsets updated through each refraction and reflection, the surface's curvature included. When it lands, its footprint is the true image of the little patch of light it started as. The footprints draw additively into a screen-space layer, each an ellipse shaded with the receiving surface's own attributes, and the lit surfaces add that layer back. Live, the layer is temporally accumulated. An export emits uniformly at the full budget within its one frame, so a still or a video is a pure function of each frame.

<a id="notes"></a>
### Notes

- **Screen-space apply.** Caustics land on what the camera sees directly: a caustic on a surface seen only in a mirror, or through glass, doesn't appear there.
- **Sharp caustics from rough glass.** Photon paths treat every caster as polished (roughness does not widen the differentials), so a frosted glass still throws a sharp pattern. Its *look* through the glass frosts; the light it casts does not.
- **One caster light** per frame emits photons; the other lights shade normally.
- **Glass refracts, metal reflects.** A glass surface's own specular reflection doesn't spawn a second photon family (tracing both would double the cost); a mirror-polished metal's does the reflecting.
- **Area lights** (rect/disk/tube) don't emit photons yet; the soft-caustics extension is a follow-up.
- The example is [`Examples/3D/Lighting/Caustics`](../../Examples/3D/Lighting/Caustics/Sketch.swift); run it with `swift run --package-path Examples Example-3D-Lighting-Caustics`.
