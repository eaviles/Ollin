#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → 3D</sup>

---

## 3D

These sketches opt into Ollin's 3D mode. 2D stays the default. A sketch becomes
3D when it sets a `camera` (`perspective`/`ortho`/`camera`). The renderer then
adds a depth buffer and draws 3D geometry through that camera. World space is
right-handed and y-up.

The section is large, so the sketches are grouped by topic, one page each.


| [![Camera](https://media.ollin.art/groups/3D-Camera-640.jpg?v=c76cca23)](Camera/) | [![Depth](https://media.ollin.art/groups/3D-Depth-640.jpg?v=ba453c33)](Depth/) | [![Effects](https://media.ollin.art/groups/3D-Effects-640.jpg?v=113e3b33)](Effects/) | [![Environments](https://media.ollin.art/groups/3D-Environments-640.jpg?v=fa8ce933)](Environments/) |
|---|---|---|---|
| [Camera](Camera/) | [Depth](Depth/) | [Effects](Effects/) | [Environments](Environments/) |
| [![Geometry](https://media.ollin.art/groups/3D-Geometry-640.jpg?v=d15e0d14)](Geometry/) | [![Lighting](https://media.ollin.art/groups/3D-Lighting-640.jpg?v=9ab2ae97)](Lighting/) | [![Materials](https://media.ollin.art/groups/3D-Materials-640.jpg?v=58f2fd81)](Materials/) | [![Physics](https://media.ollin.art/groups/3D-Physics-640.jpg?v=f964ce02)](Physics/) |
| [Geometry](Geometry/) | [Lighting](Lighting/) | [Materials](Materials/) | [Physics](Physics/) |
| [![Raymarching](https://media.ollin.art/groups/3D-Raymarching-640.jpg?v=fb0b045e)](Raymarching/) |  |  |  |
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
