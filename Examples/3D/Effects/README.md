#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Effects</sup>

---

## Effects

| [![AmbientOcclusion](https://media.ollin.art/examples/3D/Effects/AmbientOcclusion/still-640.jpg?v=58a7c12d)](AmbientOcclusion/) | [![Atmosphere](https://media.ollin.art/examples/3D/Effects/Atmosphere/still-640.jpg?v=9ddb09d3)](Atmosphere/) | [![ContactShadows](https://media.ollin.art/examples/3D/Effects/ContactShadows/still-640.jpg?v=666d2617)](ContactShadows/) | [![FrameInterpolation](https://media.ollin.art/examples/3D/Effects/FrameInterpolation/still-640.jpg?v=ff8e6ab9)](FrameInterpolation/) |
|---|---|---|---|
| [AmbientOcclusion](AmbientOcclusion/) | [Atmosphere](Atmosphere/) | [ContactShadows](ContactShadows/) | [FrameInterpolation](FrameInterpolation/) |
| [![LensFlare](https://media.ollin.art/examples/3D/Effects/LensFlare/still-640.jpg?v=eb7e0717)](LensFlare/) | [![MotionBlur](https://media.ollin.art/examples/3D/Effects/MotionBlur/still-640.jpg?v=33b9dfa5)](MotionBlur/) | [![PathTraced](https://media.ollin.art/examples/3D/Effects/PathTraced/still-640.jpg?v=6cc33dd0)](PathTraced/) | [![RayTracedReflections](https://media.ollin.art/examples/3D/Effects/RayTracedReflections/still-640.jpg?v=5a07a8cf)](RayTracedReflections/) |
| [LensFlare](LensFlare/) | [MotionBlur](MotionBlur/) | [PathTraced](PathTraced/) | [RayTracedReflections](RayTracedReflections/) |
| [![SceneDefocus](https://media.ollin.art/examples/3D/Effects/SceneDefocus/still-640.jpg?v=7fa5dce5)](SceneDefocus/) | [![ScreenSpaceReflections](https://media.ollin.art/examples/3D/Effects/ScreenSpaceReflections/still-640.jpg?v=e167c52e)](ScreenSpaceReflections/) | [![SpecularAntialias](https://media.ollin.art/examples/3D/Effects/SpecularAntialias/still-640.jpg?v=fc004d3a)](SpecularAntialias/) | [![TemporalAA](https://media.ollin.art/examples/3D/Effects/TemporalAA/still-640.jpg?v=e0b0f49e)](TemporalAA/) |
| [SceneDefocus](SceneDefocus/) | [ScreenSpaceReflections](ScreenSpaceReflections/) | [SpecularAntialias](SpecularAntialias/) | [TemporalAA](TemporalAA/) |
| [![Upscaling](https://media.ollin.art/examples/3D/Effects/Upscaling/still-640.jpg?v=80242487)](Upscaling/) |  |  |  |
| [Upscaling](Upscaling/) |  |  |  |

This group covers the scene-wide realism passes over the 3D frame.

| Sketch | What it shows |
| --- | --- |
| [SceneDefocus](SceneDefocus/) | Depth of field on a 3D scene, defocused by its own depth buffer. A row of orbs is drawn into a render target, then `scene.combined(with: scene.depth, .defocus(...))` racks focus through them. Drag to rack focus by hand. |
| [AmbientOcclusion](AmbientOcclusion/) | Screen-space ambient occlusion from the scene's own depth and normals. It adds the soft darkening in crevices and contact gaps that grounds a brightly lit scene. |
| [ScreenSpaceReflections](ScreenSpaceReflections/) | Surfaces reflecting the scene around them. SSR is traced over the frame and shown on a ring of reflective spheres in different metal finishes. |
| [RayTracedReflections](RayTracedReflections/) | Metals mirroring the actual scene, off-screen geometry included and with none of SSR's streaks. Rough surfaces spread their rays for a glossy result, and there is a `reflectionBounces` parameter. Needs a ray-tracing GPU and an environment. |
| [ContactShadows](ContactShadows/) | The fine dark seam that seats an object on the surface it stands on. |
| [Atmosphere](Atmosphere/) | Fog as a cue for distance and height, and physical aerial perspective, both over one colonnade. Hold space to switch. |
| [MotionBlur](MotionBlur/) | The streak a real camera's open shutter leaves on something moving. |
| [TemporalAA](TemporalAA/) | Edges refined past MSAA by accumulating jittered frames. |
| [SpecularAntialias](SpecularAntialias/) | Highlights smaller than their pixel, held still instead of crawling. |
| [Upscaling](Upscaling/) | The frame is rendered small and reconstructed at full size, which keeps the frame rate up. |
| [FrameInterpolation](FrameInterpolation/) | The sketch draws half as often, and a generated frame between each pair lets the display keep its rate. |
| [LensFlare](LensFlare/) | The light a camera adds to a picture on its own. |
| [PathTraced](PathTraced/) | Tune the scene live, then render the same frame offline with a path tracer. |

Run one with `swift run Example-3D-Effects-<Name>`, for example `swift run Example-3D-Effects-SceneDefocus`.
