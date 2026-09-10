#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Camera</sup>

---

## Camera

| [![CameraControl](https://media.ollin.art/examples/3D/Camera/CameraControl/still-640.jpg?v=1f5259ec)](CameraControl/) | [![CameraMoves](https://media.ollin.art/examples/3D/Camera/CameraMoves/still-640.jpg?v=4f28469d)](CameraMoves/) | [![SceneViews](https://media.ollin.art/examples/3D/Camera/SceneViews/still-640.jpg?v=51f1e4f7)](SceneViews/) |  |
|---|---|---|---|
| [CameraControl](CameraControl/) | [CameraMoves](CameraMoves/) | [SceneViews](SceneViews/) |  |

This group covers driving the view: interactive control, cinematic moves, and snaps to inspection views.

| Sketch | What it shows |
| --- | --- |
| [CameraControl](CameraControl/) | Interactive camera control. `cameraControl()` lets the viewer drag to orbit a still life, scroll to dolly, and right-drag (or shift/option-drag) to pan. The motion is damped, so it settles, and a flick keeps a little spin. |
| [CameraMoves](CameraMoves/) | Cinematic camera moves over one still life: a `.turntable` spin, a `.sway`, a `.pushIn`/`.pullOut` dolly, a `.tilt`, the `.orbitAndRise` beauty pass, a `.reveal`, and a `.handheld` drift. Each is one `cameraMove(_:)` call, and it composes over the pose the last move left. Click or press a key to step. |
| [SceneViews](SceneViews/) | The host's **Camera** menu snaps an auto-orbiting scene to the standard inspection views (Front/Back/Left/Right/Top/Bottom/Isometric and Reset, ⌘0–⌘7), the way a modeling tool's numpad does. |

Run one with `swift run Example-3D-Camera-<Name>`, for example `swift run Example-3D-Camera-CameraControl`.
