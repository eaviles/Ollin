#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → 3D</sup>

---

## 3D

These sketches opt into Ollin's 3D mode. 2D stays the default. A sketch becomes
3D when it sets a `camera` (`perspective`/`ortho`/`camera`). The renderer then
adds a depth buffer and draws 3D geometry through that camera. World space is
right-handed and y-up.

The section is large, so the sketches are grouped by topic, one page each.


| [![Camera](https://media.ollin.art/examples/3D/Camera/CameraMoves/still-640.jpg)](Camera/) | [![Depth](https://media.ollin.art/examples/3D/Depth/DepthCompositing/still-640.jpg)](Depth/) | [![Effects](https://media.ollin.art/examples/3D/Effects/PathTraced/still-640.jpg)](Effects/) | [![Environments](https://media.ollin.art/examples/3D/Environments/RemoteEnvironment/still-640.jpg)](Environments/) |
|---|---|---|---|
| [Camera](Camera/) | [Depth](Depth/) | [Effects](Effects/) | [Environments](Environments/) |
| [![Geometry](https://media.ollin.art/examples/3D/Geometry/Solids/still-640.jpg)](Geometry/) | [![Lighting](https://media.ollin.art/examples/3D/Lighting/AreaLights/still-640.jpg)](Lighting/) | [![Materials](https://media.ollin.art/examples/3D/Materials/Materials/still-640.jpg)](Materials/) | [![Physics](https://media.ollin.art/examples/3D/Physics/Contraption/still-640.jpg)](Physics/) |
| [Geometry](Geometry/) | [Lighting](Lighting/) | [Materials](Materials/) | [Physics](Physics/) |
| [![Raymarching](https://media.ollin.art/examples/3D/Raymarching/RaymarchedFractals/still-640.jpg)](Raymarching/) |  |  |  |
| [Raymarching](Raymarching/) |  |  |  |

| Group | What it covers |
| --- | --- |
| [Geometry](Geometry/) | This group covers meshes, point clouds, and the 3D transform stack. (27 sketches) |
| [Physics](Physics/) | This group covers bodies inside the scene, rigid and soft: stacks and joints, cloth, rope, and floating. A Jolt-backed `World3D` is stepped each frame (`import OllinPhysics`), and every body is drawn from its pose with `withBody`. See the [3D physics reference](../../Docs/Simulation/Physics3D.md). (22 sketches) |
| [Camera](Camera/) | This group covers driving the view: interactive control, cinematic moves, and snaps to inspection views. (3 sketches) |
| [Materials](Materials/) | This group covers what surfaces are made of: stylized finishes, physically based metal, glass, subsurface, thin film, and the map set that varies any of them per pixel. (17 sketches) |
| [Lighting](Lighting/) | This group covers the light kinds, curated rigs, and cast shadows. (11 sketches) |
| [Environments](Environments/) | This group covers image-based lighting, with HDRIs that are bundled, downloaded, loaded from a URL, or synthesized. (6 sketches) |
| [Effects](Effects/) | This group covers the scene-wide realism passes over the 3D frame. (13 sketches) |
| [Raymarching](Raymarching/) | This group covers the 3D SDF combinators: distance fields that merge, sphere-traced beside the meshes. (17 sketches) |
| [Depth](Depth/) | This group covers depth feeds and depth-aware compositing: cameras, recordings, and metric space. (6 sketches) |
| [Phone](Phone/) | These sketches read the **Ollin Capture** iPhone app, which streams ARKit perception over USB. (15 sketches) |

See [`Docs/3D/3D.md`](../../Docs/3D/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/3D/Record3D.md`](../../Docs/3D/Record3D.md). The Ollin Capture stream is documented in [`Docs/3D/Phone.md`](../../Docs/3D/Phone.md).
