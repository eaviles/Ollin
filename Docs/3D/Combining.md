#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Combining 3D features`</sup>

---

## Combining 3D features

The 3D features are designed to stack: lights over materials, an environment over both, shadows and reflections on top. But not every finish applies to every kind of geometry, and there are two reflection systems that solve the same problem in different ways. This page is the practical map: what works with what, and which tool to reach for.

### Contents

- [Two ways to get reflections](#reflections)
- [What lights and shades what](#shading)
- [Who casts, receives, and appears in reflections](#matrix)
- [Effects that read depth](#depth-effects)
- [Paths that skip parts of 3D](#skips)
- [The realism recipe](#realism)
- [Quick recipes](#recipes)

<a id="reflections"></a>
### Two ways to get reflections

Ollin has two reflection systems. They exist because each one can do something the other can't.

**Screen-space reflections** ([`.screenSpaceReflections`](../Drawing/Effects.md#combined)) are an *image effect*: they take the finished picture plus its depth layer and paint reflections into it. Think of it as making a mirror out of a photograph. Because it only needs the picture, it runs on any Mac, reflects any surface regardless of material, and even works on a hand-made depth layer that never came from a 3D scene. But a photograph doesn't contain the back of anything: whatever the camera can't see, the mirror can't show. That's why an object resting on a reflective floor shows a soft, imperfect zone right where it touches: the underside of the object isn't in the picture, so its reflection can't be computed, only approximated.

**Ray-traced reflections** ([`rayTracedReflections()`](./3D.md#ray-traced-reflections)) are part of the 3D renderer itself: each reflective pixel fires a real ray at the actual scene geometry and shades whatever it hits, including surfaces the camera can't see, so contacts, undersides, and off-screen objects reflect correctly. The price is a narrower set of requirements: a ray-tracing GPU (Apple silicon), an [`environment(_:)`](./3D.md#environment) to light the scene and catch rays that fly off into the sky, and the reflecting surface must wear a [physically based material](./3D.md#materials) (a metal is what mirrors).

| | Screen-space (`.screenSpaceReflections`) | Ray-traced (`rayTracedReflections()`) |
| --- | --- | --- |
| Runs on | any Mac | ray-tracing GPUs (Apple silicon) |
| What reflects | every surface in the layer | physically based metals |
| What appears in the mirror | only what's already on screen | the real geometry, hidden and off-screen parts included |
| Needs | a render target and its `depth` | an `environment(_:)`, a PBR material |
| Where it shines | glossy floors and stylized looks, any hardware, hand-made depth | mirror finishes, object-floor contacts, realism |
| Honest limit | can't show hidden surfaces (contact zones approximate) | costs rays; only PBR metals mirror the scene |

Rule of thumb: for a realistic scene with metallic materials on Apple silicon, reach for `rayTracedReflections()`. For everything else (stylized work, any-material reflections, machines without ray tracing, or reflections over a depth layer you drew yourself), use `.screenSpaceReflections` and give the floor a touch of `roughness`, which turns its limits into a natural-looking gloss.

<a id="shading"></a>
### What lights and shades what

Five kinds of things can be on screen in a 3D frame, and they don't all take the same finish:

| | Lights + `material(_:)` | `matcap(_:)` | `environment(_:)` light | Gradient paint |
| --- | --- | --- | --- | --- |
| Solid / textured meshes | yes | yes (replaces the lit model) | yes | no (solid `fill` only) |
| Wireframe meshes | no (edges take `stroke`) | no | no | no |
| Point clouds | no (each point has its own color) | no | no | no (color per point instead) |
| Raymarched fields (`drawSDF3D`) | yes | no | yes | yes (screen-space) |
| 2D drawing placed in depth | no (2D paint as usual) | no | no | yes (the 2D gradients) |

Notes worth knowing:

- **Meshes** are the full-featured citizens: Blinn-Phong by default, the stylized `material(_:)` library, the physically based metals, textures, all of it lit by lights and the environment together.
- **A matcap replaces lighting** for the meshes it wraps: the whole look is painted into its sphere image, so lights, materials, shadows, and the environment don't apply to a matcap'd mesh.
- **Point clouds are unlit on purpose**: each point carries its own color (usually sampled from a camera or an image), so lighting them would fight the data they carry.
- **Raymarched fields** shade through the same material and lighting model as meshes, environment light included; the one finish they don't take is a matcap.
- **Wireframes** have no surface to shade, so they draw in the `stroke` color and stay out of lighting entirely.

<a id="matrix"></a>
### Who casts, receives, and appears in reflections

Shadows (with [`castShadows()`](./3D.md#shadows)) and the two reflection systems each see a different subset of the scene:

| | Casts shadows | Receives shadows | Appears in ray-traced reflections | Can mirror the scene (ray-traced) | Appears in screen-space reflections |
| --- | --- | --- | --- | --- | --- |
| Solid / textured meshes | yes | yes | yes | yes, with a PBR material | yes |
| Wireframe meshes | no | no | no | no | yes (their visible edges) |
| Point clouds | no | no | no | no | yes |
| Raymarched fields | yes | yes | no | yes, with a PBR finish | yes |
| 2D drawing placed in depth | no | no | no | no | yes |

The two asymmetries that surprise people:

- **Screen-space reflections mirror the *picture*, so everything visible appears in them**, point clouds and wireframes included. Ray-traced reflections trace the *mesh geometry*, so only solid meshes appear inside a traced mirror image.
- **A raymarched field can show traced reflections on its own surface** (give it a PBR finish), but it doesn't *appear* in another object's traced reflection, because it isn't part of the mesh index the rays test. If you need a merged-blob sculpture visible in a chrome sphere, build it from meshes instead.

And [glass](./3D.md#glass) adds two of its own: a glass mesh still **casts a solid shadow** (the shadow passes don't read transmission), and glass **appears opaque inside a mirror or through other glass** (a traced hit shades as the surface it struck without re-entering the transmission math). The view *through* a glass surface you look at directly is the full story: the environment everywhere, and the actual scene on a ray-tracing GPU with `rayTracedReflections()` on. The layered [clearcoat and sheen](./3D.md#clearcoat-sheen) lobes share the mirror half of that envelope: a coated or sheened surface seen *inside* a traced reflection shades as its base material there.

<a id="depth-effects"></a>
### Effects that read depth

Three of the two-layer combine effects read a depth layer as their second input: [`.defocus`](../Drawing/Effects.md#combined) (depth of field), [`.ambientOcclusion`](../Drawing/Effects.md#combined), and [`.screenSpaceReflections`](../Drawing/Effects.md#combined). The usual source is a 3D scene's own depth: draw the scene into a render target and pass `scene.depth`. Two things follow from that:

- **The 3D has to be drawn *into the target*.** A 2D-only target has no depth buffer, so its `depth` layer stays empty and the combine quietly does nothing.
- **`.defocus` also accepts a depth layer you draw by hand** (its luminance is the depth), so tilt-shift gradients and hand-painted focus maps work with no 3D at all.

Ambient occlusion and screen-space reflections read true surface normals where meshes provided them; over point clouds and raymarched fields they reconstruct normals from depth, which works but is a little less stable at silhouettes.

<a id="skips"></a>
### Paths that skip parts of 3D

Two output paths draw 3D geometry but skip some of its machinery: the accumulation surface ([`noClear()`](../Drawing/Accumulation.md)) and the texture hand-off used by [Syphon](../Integration/Syphon.md) render 3D **without depth sorting and without shadows**. The live window and the image/video/snapshot exports render everything.

<a id="realism"></a>
### The realism recipe

If the goal is simply *the most realistic scene Ollin can render*, this is the stack, in the order you'd add each piece:

1. **Build the scene from solid meshes.** They're the only geometry that takes the full pipeline: physically based materials, environment light, shadows, and ray-traced reflections (the tables above are the reason).
2. **Light it with an `environment(_:)`.** A real captured surrounding ([`.studio`, `.sunset`, and the other bundled HDRIs](./3D.md#environment), or the procedural `.sky(...)`) is the single biggest realism step: every material picks up believable ambient light and reflections, and the backdrop comes with it.
3. **Use the physically based materials.** [`material(.metal(roughness:))`, `.dielectric(roughness:)`, or the built-ins like `.polishedMetal` and `.roughPlastic`](./3D.md#materials), with `fill` as the surface color. These are the finishes that respond correctly to the environment and can mirror the scene. [Textures](./3D.md#textures) still apply: a textured mesh keeps its image as the surface color under any material, so a `.dielectric` shows it as a lit, correctly specular surface and a `.metal` tints its reflections by it. The one thing a texture can't drive yet is the *finish itself*: metallic and roughness are set per mesh by `material(_:)`, not per pixel by an image, so a surface can't be painted rusty in one spot and polished in another.
4. **Add one key light and shadows.** A `directionalLight` gives the scene a direction, and `castShadows()` grounds every object with soft, contact-hardening shadows (dial the softness with `shadowSoftness(_:)`).
5. **Turn on `rayTracedReflections()`.** On Apple silicon the metals now mirror the actual scene, contacts included; on other machines the call is a safe no-op and the environment reflection remains.
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

- **Grounding and lens looks** come from the depth effects: draw the scene into a render target, then `.ambientOcclusion(...)` darkens the contacts and crevices and `.defocus(...)` adds depth of field. The trade: inside a render target the ray-traced reflections take their simpler single-ray form (the anti-aliased, frame-accumulated version covers the canvas itself), so reserve the target pass for when the occlusion or the lens matters more than the mirror edges.
- **Exports take care of quality by themselves.** The live window trades a little quality for frame rate on the expensive passes; the image, video, and snapshot exporters resolve those dials to their highest tier, so the exported art is always the best version of the frame.

The `3D/RayTracedReflections` and `3D/ImageBasedLighting` examples are this recipe in working form.

<a id="recipes"></a>
### Quick recipes

- **A mirror floor under objects, done right**: physically based materials + `environment(_:)` + `rayTracedReflections()` (Apple silicon).
- **A glossy floor that runs anywhere**: draw the scene into a target and apply `.screenSpaceReflections(roughness: 0.3)` (anywhere around 0.2 to 0.4 works); the roughness turns the technique's limits into gloss.
- **A striking finish with zero lighting setup**: `matcap(_:)`, one call, one image, no lights.
- **Merging, blobby shapes that still take materials and shadows**: [`drawSDF3D`](../Drawing/Combinators.md), with `material(_:)` and `castShadows()`.
- **A scanned or generated point cloud with readable structure**: color the points from the data and add lit meshes around them for the shading the cloud itself won't take.
