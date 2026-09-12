#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Combining 3D features`</sup>

---

## Combining 3D features

The 3D features are designed to stack. Lights go over materials, an environment goes over both, and shadows and reflections go on top. Not every finish applies to every kind of geometry, though, and two reflection systems solve the same problem in different ways. This page maps what works with what, and which tool to use.

### Contents

- [Two ways to get reflections](#reflections)
- [What lights and shades what](#shading)
- [Who casts, receives, and appears in reflections](#matrix)
- [Which lights cast, and which one the rest follows](#casters)
- [Effects that read depth](#depth-effects)
- [Atmosphere and the temporal passes](#atmosphere)
- [What the path-traced export leaves behind](#traced)
- [Paths that skip parts of 3D](#skips)
- [The realism recipe](#realism)
- [Quick recipes](#recipes)

<a id="reflections"></a>
### Two ways to get reflections

Ollin has two reflection systems. Each one can do something the other can't, which is why both are here.

**Screen-space reflections** ([`.screenSpaceReflections`](../Drawing/Effects.md#combined)) are an *image effect*. They take the finished picture plus its depth layer and paint reflections into it, which is like making a mirror out of a photograph. Because they only need the picture, they run on any Mac and reflect any surface, whatever its material. They even work on a hand-made depth layer that never came from a 3D scene. A photograph doesn't contain the back of anything, though, so whatever the camera can't see, the mirror can't show. That's why an object resting on a reflective floor shows a soft, imperfect zone right where it touches. The underside of the object isn't in the picture, so its reflection can't be computed, only approximated.

**Ray-traced reflections** ([`rayTracedReflections()`](./3D.md#ray-traced-reflections)) are part of the 3D renderer itself. Each reflective pixel fires a real ray at the actual scene geometry and shades whatever it hits, including surfaces the camera can't see. So contacts, undersides, and off-screen objects reflect correctly. In return, the requirements are narrower. You need a ray-tracing GPU, which means Apple silicon. You need an [`environment(_:)`](./3D.md#environment) to light the scene and to catch rays that fly off into the sky. The reflecting surface also needs a [physically based material](./3D.md#materials), because a metal is what mirrors.

| | Screen-space (`.screenSpaceReflections`) | Ray-traced (`rayTracedReflections()`) |
| --- | --- | --- |
| Runs on | any Mac | ray-tracing GPUs (Apple silicon) |
| What reflects | every surface in the layer | physically based metals |
| What appears in the mirror | only what's already on screen | the real geometry, hidden and off-screen parts included |
| Needs | a render target and its `depth` | an `environment(_:)`, a PBR material |
| Where it shines | glossy floors and stylized looks, any hardware, hand-made depth | mirror finishes, object-floor contacts, realism |
| Honest limit | can't show hidden surfaces (contact zones approximate) | costs rays, and only PBR metals mirror the scene |

As a rule of thumb, use `rayTracedReflections()` for a realistic scene with metallic materials on Apple silicon. For everything else, use `.screenSpaceReflections` and give the floor a little `roughness`, which turns its limits into a natural-looking gloss. That covers stylized work, reflections from any material, machines without ray tracing, and reflections over a depth layer you drew yourself.

<a id="shading"></a>
### What lights and shades what

Five kinds of thing can appear in a 3D frame, and they don't all take the same finish:

| | Lights + `material(_:)` | `matcap(_:)` | `environment(_:)` light | Gradient paint |
| --- | --- | --- | --- | --- |
| Solid / textured meshes | yes | yes (replaces the lit model) | yes | no (solid `fill` only) |
| Instanced meshes, mesh fields, strand fields | yes | no | yes | no |
| Wireframe meshes | no (edges take `stroke`) | no | no | no |
| Point clouds | no (each point has its own color) | no | no | no (color per point instead) |
| Raymarched fields (`drawSDF3D`) | yes | no | yes | yes (screen-space) |
| 2D drawing placed in depth | no (2D paint as usual) | no | no | yes (the 2D gradients) |

A few notes on the table:

- **Geometry drawn in bulk shades like a mesh.** `drawMesh(_:instances:)`, `drawMeshField(_:)` and `drawStrands(_:)` all run the same lit fragment as a solid mesh. So they take lights, materials, the environment, the shadows they receive, bounce light and fog, exactly as one copy drawn on its own does. What they don't join is the ray-traced side, below.
- **Meshes** take every finish: Blinn-Phong by default, the stylized `material(_:)` library, the physically based metals, and textures. Lights and the environment light all of them together.
- **A matcap replaces lighting** for the meshes it wraps. The whole look is painted into its sphere image, so lights, materials, shadows, and the environment don't apply to a mesh with a matcap.
- **Point clouds are unlit on purpose.** Each point carries its own color, usually sampled from a camera or an image. Lighting them would work against the data they carry.
- **Raymarched fields** shade through the same material and lighting model as meshes, environment light included. The one finish they don't take is a matcap.
- **Wireframes** have no surface to shade, so they draw in the `stroke` color and stay out of lighting entirely.

<a id="matrix"></a>
### Who casts, receives, and appears in reflections

Shadows (with [`castShadows()`](./3D.md#shadows)), the two reflection systems, and [global illumination](./3D.md#global-illumination) each see a different part of the scene:

| | Casts shadows | Receives shadows | Appears in ray-traced reflections | Can mirror the scene (ray-traced) | Appears in screen-space reflections | Gathers bounce light (GI) |
| --- | --- | --- | --- | --- | --- | --- |
| Solid / textured meshes | yes | yes | yes | yes, with a PBR material | yes | yes |
| Instanced meshes, mesh fields | yes (not for a point light on a ray-tracing GPU) | yes | no | no | yes | yes |
| Strand fields | no | yes | no | no | yes | yes |
| Wireframe meshes | no | no | no | no | yes (their visible edges) | no |
| Point clouds | no | no | no | no | yes | no |
| Raymarched fields | yes | yes | no | yes, with a PBR finish | yes | yes |
| 2D drawing placed in depth | no | no | no | no | yes | no |

Those differences, spelled out:

- **Geometry drawn in bulk is shaded, but not traced.** The ray-tracing acceleration structure holds solid mesh batches only. Instanced meshes, mesh fields and strand fields are absent from it, so they never appear inside a traced mirror. On a ray-tracing GPU a point light's shadow doesn't see them either, because that shadow is traced too. Their shadows from directional and spot lights are ordinary shadow maps, and those work normally. Strand fields receive shadows without casting any, which is what keeps a field of grass affordable.

- **Screen-space reflections mirror the *picture*, so everything visible appears in them**, point clouds and wireframes included. Ray-traced reflections trace the *mesh geometry*, so only solid meshes appear inside a traced mirror image.
- **A raymarched field can show traced reflections on its own surface** if you give it a PBR finish. It doesn't *appear* in another object's traced reflection, though, because it isn't part of the mesh index the rays test. If you need a merged-blob sculpture visible in a chrome sphere, build it from meshes instead. One honest limit sits at the field's silhouette. A field traces its reflections one ray per pixel, while a mesh's traced reflections are supersampled and averaged. Right at the rim the mirror image compresses into the last pixel or two. So a field's edge can carry a single bright fleck where a mesh's edge stays averaged. It only shows where the reflected scene is bright.
- **Bounce light travels through meshes only, but it lands on fields too.** The probe rays bounce off the mesh geometry. So a field neither reflects bounce light onto its neighbors nor blocks it. A field's own surface still gathers the probes' light like any mesh. A surface seen *inside* a traced mirror keeps its direct-only shading, the same mirror-interior envelope that glass and the layered lobes have.

[Glass](./3D.md#glass) adds two differences of its own. A glass mesh still **casts a solid shadow**, because the shadow passes don't read transmission. Glass also **appears opaque inside a mirror or through other glass**. A traced hit shades as the surface it struck, and never re-enters the transmission math. The view *through* a glass surface you look at directly is the full story. You get the environment everywhere, plus the actual scene on a ray-tracing GPU with `rayTracedReflections()` on.

**Glass on a marched field absorbs like glass on a mesh.** The traced view through a solid glass body finds its far side by tracing. A `drawSDF3D` field owns no geometry the rays can hit, so a field marches its own far side instead. The same `Material.glass(...)`, with the same `attenuationColor` and `attenuationDistance`, comes out the same on a field as on the mesh of that shape. What lies *behind* a glass field still comes from the mesh scene. That is the rule above read from the other side, so a second field standing behind one is not visible through it.

The layered [clearcoat and sheen](./3D.md#clearcoat-sheen) lobes share the mirror half of that envelope. A coated or sheened surface seen *inside* a traced reflection shades as its base material there. [Decals](./3D.md#decals) follow the same split. Every solid, textured, or mapped mesh receives them, while wireframes, matcaps, point clouds, and raymarched fields don't. A stamped surface seen *inside* a traced reflection shows its base without the decal.

<a id="casters"></a>
### Which lights cast, and which one the rest follows

The table above is about geometry. This section covers the other half of the same question: which of the lights in the frame throw a shadow.

Under [`castShadows()`](./3D.md#shadows) every light casts a shadow, up to **four** of them, in the order you set them. Three kinds of light sit outside that:

| | Casts | Why |
| --- | --- | --- |
| Directional, spot, rect, disk | yes | Each renders its own 2D shadow map, one layer per caster |
| Point | yes | Each gets its own cube map, or its own rays on a ray-tracing GPU. This is the expensive kind, because it casts every way at once |
| Tube | no | It emits radially, so there is no side to render a map from |
| A light with `castsShadow: false` | no | You said so |
| The fill and rim of a `lightingPreset(_:)` rig | no | The rigs set `castsShadow: false` on them. See [Lighting presets](./3D.md#lights) |

The last row is the one to read twice. `lightingPreset(.studio)` installs three lights, and you get one shadow rather than three. A fill light exists to open the shadow side, not to make a shadow of its own. Every caster also costs a pass over the scene from its own point of view, so the rigs stay at one. To change that, copy the rig and set the flag yourself.

<a id="primary-caster"></a>
Almost everything follows the whole list of casters. One feature reads a single caster instead, and that caster is the **primary** one. Ollin picks it in this order: the first directional light, then the first spot, then the first point, then the first rect or disk panel.

| Feature | Follows |
| --- | --- |
| Solid, textured, instanced, field and strand geometry | every caster |
| [Volumetric shafts](./Atmosphere.md) | every caster that renders a map (a directional or a spot) |
| [Contact shadows](./3D.md#contact-shadows) | every caster |
| [Subsurface transmission](./3D.md#subsurface-scattering) | every caster |
| [Global illumination](./3D.md#global-illumination) | every caster |
| A [marched SDF field](../Drawing/Combinators.md), throwing and receiving | every caster |
| [Caustics](./Caustics.md) | the primary caster only |

So a scene with a key and a stage light gets two shadows on the floor. It also gets two carved shafts in the air, and two contact seams under a resting object. Each of those is another march or another pass, so more casters cost more.

Caustics stay with one caster because a frame traces a fixed number of photons. Split between two lights, each pattern gets noisier rather than richer. So put the light you want the caustics to follow first.

<a id="depth-effects"></a>
### Effects that read depth

Three of the two-layer combine effects read a depth layer as their second input: [`.defocus`](../Drawing/Effects.md#combined) (depth of field), [`.ambientOcclusion`](../Drawing/Effects.md#combined), and [`.screenSpaceReflections`](../Drawing/Effects.md#combined). The usual source is a 3D scene's own depth. Draw the scene into a render target and pass `scene.depth`. Two things follow from that:

- **The 3D has to be drawn *into the target*.** A 2D-only target has no depth buffer. Its `depth` layer stays empty, and the combine then does nothing, with no warning.
- **`.defocus` also accepts a depth layer you draw by hand**, where the luminance is the depth. So tilt-shift gradients and hand-painted focus maps work with no 3D at all.

Ambient occlusion and screen-space reflections read true surface normals where meshes provided them. Over point clouds and raymarched fields they rebuild the normals from depth. That works, but it is a little less stable at silhouettes.

<a id="atmosphere"></a>
### Atmosphere and the temporal passes

[`fog(_:density:heightFalloff:)`](./Atmosphere.md#fog) tints every 3D surface by its own depth. **2D drawing never fogs**, and neither does the backdrop. So a sketch keeps its overlays and its sky clear while the geometry recedes. [`volumetricLight()`](./Atmosphere.md#volumetric) makes the beams in the air visible. It pairs with fog but doesn't need it. On its own, the air stays clear and only the beams appear.

Three passes work on the finished frame rather than on any one surface, and they share one set of limits. Those passes are [temporal anti-aliasing](./3D.md#temporal-antialiasing), [motion blur](./3D.md#motion-blur) and [temporal upscaling](./3D.md#temporal-upscaling). All three apply to the **main canvas with an active 3D camera**, and to nothing else. A 2D sketch gets a note rather than an effect. Render targets, the accumulation surface and the texture hand-off are outside them too. Upscaling replaces temporal anti-aliasing rather than stacking with it, and an export never upscales.

<a id="traced"></a>
### What the path-traced export leaves behind

[`--path-traced`](../Output/PathTraced.md) is the biggest single split on this page, because it swaps the renderer rather than adding to it. The trace covers the **solid 3D meshes**. Everything else keeps its ordinary pipeline, then composites with the traced layer by depth, in draw order:

- 2D drawing, before and after the 3D.
- Wireframes, the ground grid, and matcap meshes. A matcap is an unlit finish, so a glowing prop drawn over an area light keeps its glow and never blocks the light's rays.
- Point clouds, strand fields, raymarched fields, instanced meshes, and mesh fields.

Two more things thin out inside a traced frame. First, the **layered lobes simplify**. Clearcoat, sheen, the thin film, iridescence, anisotropy and subsurface all trace as their metallic-roughness base, and toon and gooch trace as matte. Second, three **surface tricks stay raster**: a height map's parallax relief, the tiled detail pair, and decals. So a traced hit reads the flat surface at its plain uv.

What that means in practice is simple. A scene built from meshes and physically based finishes gains the most from tracing. A scene built from fields, clouds, strands or stylized finishes gains the least. [Caustics](./Caustics.md) are the clearest example. The bent, focused bright lines under glass are a live feature only, so the trace puts a straight tinted shadow there instead.

<a id="skips"></a>
### Paths that skip parts of 3D

Two output paths draw 3D geometry but skip parts of it. The accumulation surface ([`noClear()`](../Drawing/Accumulation.md)) and the texture hand-off used by [Syphon](../Integration/Syphon.md) render 3D **without depth sorting and without shadows**. The live window and the image, video, and snapshot exports render everything.

<a id="realism"></a>
### The realism recipe

If you want *the most realistic scene Ollin can render*, this is the stack, in the order you'd add each piece:

1. **Build the scene from solid meshes.** They're the only geometry that takes the whole pipeline: physically based materials, environment light, shadows, and ray-traced reflections. The tables above show why.
2. **Light it with an `environment(_:)`.** A real captured surrounding is the single biggest step toward realism. Every material picks up believable ambient light and reflections, and the backdrop comes with it. Use [`.studio`, `.sunset`, or another bundled HDRI](./3D.md#environment), or the procedural `.sky(...)`.
3. **Use the physically based materials.** Reach for [`material(.metal(roughness:))`, `.dielectric(roughness:)`, or the built-ins like `.polishedMetal` and `.roughPlastic`](./3D.md#materials), with `fill` as the surface color. These are the finishes that respond correctly to the environment and can mirror the scene. [Textures](./3D.md#textures) still apply. A textured mesh keeps its image as the surface color under any material. So a `.dielectric` shows that image as a lit, correctly specular surface, and a `.metal` tints its reflections by it. The one thing a texture can't drive yet is the *finish itself*. `material(_:)` sets metallic and roughness per mesh, not per pixel from an image. So you can't paint a surface rusty in one spot and polished in another.
4. **Add one key light and shadows.** A `directionalLight` gives the scene a direction, and `castShadows()` grounds every object with soft, contact-hardening shadows. Set the softness with `shadowSoftness(_:)`.
5. **Turn on `rayTracedReflections()`.** On Apple silicon the metals now mirror the actual scene, contacts included. On other machines the call does nothing and is safe to leave in, and the environment reflection remains.
6. **Tone-map the result.** `toneMap(.aces)` rolls the environment's bright highlights off filmically instead of clipping them.

```swift
override func draw() {
    camera(.orbiting(target: .zero, radius: 8, azimuth: time * 0.1, elevation: 0.35))
    environment(.studio)
    directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 0.8)
    castShadows()
    rayTracedReflections()
    toneMap(.aces)

    material(.roughPlastic); fill(Color(white: 0.9))
    withState { translate(0, -1.05, 0); drawBox(width: 20, height: 0.1, depth: 20) }

    material(.polishedMetal); fill(Color(hex: 0xf2f3f7))
    drawSphere(radius: 1)
}
```

Two optional layers sit on top, with one trade to know about:

- **Grounding and lens looks** come from the depth effects. Draw the scene into a render target, then `.ambientOcclusion(...)` darkens the contacts and crevices and `.defocus(...)` adds depth of field. Here is the trade. Inside a render target the ray-traced reflections take their simpler single-ray form, because the anti-aliased, frame-accumulated version covers the canvas itself. So use the target pass when the occlusion or the lens matters more than the mirror edges.
- **Exports take care of quality by themselves.** The live window trades a little quality for frame rate on the expensive passes. The image, video, and snapshot exporters set those dials to their highest tier, so an export is always the best version of the frame.

The `3D/RayTracedReflections` and `3D/ImageBasedLighting` examples show this recipe in working code.

<a id="recipes"></a>
### Quick recipes

- **A mirror floor under objects, done right**: physically based materials + `environment(_:)` + `rayTracedReflections()` (Apple silicon).
- **A glossy floor that runs anywhere**: draw the scene into a target and apply `.screenSpaceReflections(roughness: 0.3)`, or anything around 0.2 to 0.4. The roughness turns the technique's limits into gloss.
- **A strong finish with no lighting setup**: `matcap(_:)`, one call, one image, no lights.
- **Merging, blobby shapes that still take materials and shadows**: [`drawSDF3D`](../Drawing/Combinators.md), with `material(_:)` and `castShadows()`.
- **A scanned or generated point cloud with readable structure**: color the points from the data. Add lit meshes around them for the shading the cloud itself won't take.
