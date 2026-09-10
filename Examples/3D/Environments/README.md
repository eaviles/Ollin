#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Environments</sup>

---

## Environments

| [![Cloudscape](https://media.ollin.art/examples/3D/Environments/Cloudscape/still-640.jpg?v=9a6c5f83)](Cloudscape/) | [![EnvironmentGallery](https://media.ollin.art/examples/3D/Environments/EnvironmentGallery/still-640.jpg?v=e5907d9f)](EnvironmentGallery/) | [![ImageBasedLighting](https://media.ollin.art/examples/3D/Environments/ImageBasedLighting/still-640.jpg?v=009c09c9)](ImageBasedLighting/) | [![LiveEnvironment](https://media.ollin.art/examples/3D/Environments/LiveEnvironment/still-640.jpg?v=4b42560e)](LiveEnvironment/) |
|---|---|---|---|
| [Cloudscape](Cloudscape/) | [EnvironmentGallery](EnvironmentGallery/) | [ImageBasedLighting](ImageBasedLighting/) | [LiveEnvironment](LiveEnvironment/) |
| [![ProceduralSky](https://media.ollin.art/examples/3D/Environments/ProceduralSky/still-640.jpg?v=d60a8682)](ProceduralSky/) | [![RemoteEnvironment](https://media.ollin.art/examples/3D/Environments/RemoteEnvironment/still-640.jpg?v=f6f0bfec)](RemoteEnvironment/) |  |  |
| [ProceduralSky](ProceduralSky/) | [RemoteEnvironment](RemoteEnvironment/) |  |  |

This group covers image-based lighting, with HDRIs that are bundled, downloaded, loaded from a URL, or synthesized.

| Sketch | What it shows |
| --- | --- |
| [ImageBasedLighting](ImageBasedLighting/) | `environment(_:)` lights the scene from an HDRI, so physically-based metals fill in with real reflections instead of reading near-black. The same environment also serves as the skybox backdrop. |
| [EnvironmentGallery](EnvironmentGallery/) | The eight bundled CC0 HDRI environments (studio, courtyard, forest, interior, city, sunrise, sunset, night) stepped through over one PBR still life. They advance on their own, or you can step with the arrow keys. |
| [RemoteEnvironment](RemoteEnvironment/) | Environments fetched from the web: a sharper 2K/4K/8K backdrop for a bundled environment (`highResolution(_:)`), or any equirectangular HDRI URL (`Environment.hdri(downloadURL:)`). Each is downloaded once and cached. Any key switches. |
| [ProceduralSky](ProceduralSky/) | A daylight dome with no asset. `environment(.sky(...))` synthesizes a physically-based sky at runtime and sweeps its sun through a full day. |
| [Cloudscape](Cloudscape/) | A raymarched cloudscape over the procedural sky. |
| [LiveEnvironment](LiveEnvironment/) | A live camera environment: the room the sketch is in lights the scene. |

Run one with `swift run Example-3D-Environments-<Name>`, for example `swift run Example-3D-Environments-ImageBasedLighting`.
