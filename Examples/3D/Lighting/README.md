#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Lighting</sup>

---

## Lighting

| [![AreaLights](https://media.ollin.art/examples/3D/Lighting/AreaLights/still-640.jpg?v=26651171)](AreaLights/) | [![Caustics](https://media.ollin.art/examples/3D/Lighting/Caustics/still-640.jpg?v=7e80ac52)](Caustics/) | [![GlobalIllumination](https://media.ollin.art/examples/3D/Lighting/GlobalIllumination/still-640.jpg?v=d0d77e2f)](GlobalIllumination/) | [![LightShaping](https://media.ollin.art/examples/3D/Lighting/LightShaping/still-640.jpg?v=03521fd0)](LightShaping/) |
|---|---|---|---|
| [AreaLights](AreaLights/) | [Caustics](Caustics/) | [GlobalIllumination](GlobalIllumination/) | [LightShaping](LightShaping/) |
| [![Lighting](https://media.ollin.art/examples/3D/Lighting/Lighting/still-640.jpg?v=d9b4e3a4)](Lighting/) | [![LightingPresets](https://media.ollin.art/examples/3D/Lighting/LightingPresets/still-640.jpg?v=bc241a49)](LightingPresets/) | [![ManyCasters](https://media.ollin.art/examples/3D/Lighting/ManyCasters/still-640.jpg?v=df8f82ec)](ManyCasters/) | [![PointShadow](https://media.ollin.art/examples/3D/Lighting/PointShadow/still-640.jpg?v=8c544921)](PointShadow/) |
| [Lighting](Lighting/) | [LightingPresets](LightingPresets/) | [ManyCasters](ManyCasters/) | [PointShadow](PointShadow/) |
| [![Shadows](https://media.ollin.art/examples/3D/Lighting/Shadows/still-640.jpg?v=cdacd4a7)](Shadows/) | [![SpotShadow](https://media.ollin.art/examples/3D/Lighting/SpotShadow/still-640.jpg?v=f3b187db)](SpotShadow/) | [![VolumetricLight](https://media.ollin.art/examples/3D/Lighting/VolumetricLight/still-640.jpg?v=3a7e02d7)](VolumetricLight/) |  |
| [Shadows](Shadows/) | [SpotShadow](SpotShadow/) | [VolumetricLight](VolumetricLight/) |  |

This group covers the light kinds, curated rigs, and cast shadows.

| Sketch | What it shows |
| --- | --- |
| [Lighting](Lighting/) | The three light kinds placed by hand to shade solids: a fixed directional key, an orbiting point bulb, and a sweeping spot. A row of spheres shows rising `specularSharpness`. |
| [LightingPresets](LightingPresets/) | One call relights the whole scene. The curated `LightingPreset`s (`.standard`/`.threePoint`/`.goldenHour`/`.noir`/`.studio`/`.moonlight`) cycle over one still life, plus a custom rig built in the sketch. Click or press a key to step. |
| [Shadows](Shadows/) | Directional cast shadows. Solids drop shadows onto a floor and onto one another through `castShadows()`. |
| [SpotShadow](SpotShadow/) | A spot light as the shadow caster. A perspective shadow map is fit to its cone, so the solids inside the beam drop crisp shadows. |
| [PointShadow](PointShadow/) | A point light as an omnidirectional caster. A bulb at the center throws shadows in every direction, ray-traced on an RT GPU and through a depth cube elsewhere. |
| [ManyCasters](ManyCasters/) | Several casters at once. A warm key is joined by a swinging spot or by two circling point lamps, and each throws its own shadow. |
| [AreaLights](AreaLights/) | Rect, disk, and tube sources shading a small studio set. The softbox grows and shrinks, and the softness of its shadows follows its size. |
| [LightShaping](LightShaping/) | Photometric profiles and a projected cookie, the two ways a real fixture shapes its beam. |
| [VolumetricLight](VolumetricLight/) | Beams, gobos, and shafts you can see in the air. |
| [Caustics](Caustics/) | The light a glass or a polished metal focuses onto what is around it. |
| [GlobalIllumination](GlobalIllumination/) | Light that bounces, so a red wall reddens what stands beside it. |

Run one with `swift run Example-3D-Lighting-<Name>`, for example `swift run Example-3D-Lighting-Lighting`.
