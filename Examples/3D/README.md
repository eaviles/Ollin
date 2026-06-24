#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → 3D</sup>

---

## 3D

Sketches that opt into Ollin's 3D mode. 2D stays the default — a sketch becomes
3D by setting a `camera` (`perspective`/`ortho`/`camera`), which makes the renderer
add a depth buffer and draw 3D geometry through the camera. World space is
right-handed and y-up.

| Sketch | What it shows |
| --- | --- |
| [PointCloud](PointCloud/) | A rippling heightfield drawn as an orbiting 3D point cloud — camera, depth, and instanced disc splats. |
| [Transforms](Transforms/) | The 3D transform stack: a sun, planets orbiting it, and a moon orbiting each planet — orbits within orbits via nested `withState`, one point-cloud blob placed many ways by `translate`/`rotateY`/`scale`. |
| [Solids](Solids/) | The closed-solid catalog — box, sphere, cylinder, torus, the Platonics, and more — as colorful clay shaded by the auto-lit default. |
| [ShapeFactory](ShapeFactory/) | The parametric/profile mesh set (Möbius, Klein, superellipsoid, supershape, extrude, lathe) morphing on `time`. |
| [Lighting](Lighting/) | The three light kinds shading solids by hand — a fixed directional key, an orbiting point bulb, a sweeping spot — with a rising-shininess sphere row. |
| [LightingPresets](LightingPresets/) | One call relights the whole scene: the curated `LightingPreset`s (`.standard`/`.threePoint`/`.goldenHour`/`.noir`/`.studio`/`.moonlight`) cycling over one still life, plus a sketch-built custom rig. Click or press a key to step. |
| [Materials](Materials/) | The material library — one orbiting sphere grid wearing each built-in `Material` (`.iridescent`/`.soapBubble`/`.velvet`/`.jade`/`.toon`/`.gooch`/…), the view-angle finishes shifting as it turns. |
| [Shadows](Shadows/) | Directional cast shadows: solids drop shadows onto a floor and onto one another via `castShadows()`. |
| [LoadedMesh](LoadedMesh/) | A mesh loaded from a file (`.obj`/`.usdz`/`.gltf`/…) — drop one in with `OLLIN_MESH=<path>`, or the bundled crystal — recentered, scaled to fit, and lit. |
| [TexturedMesh](TexturedMesh/) | A UV-gridded globe textured with an image over a base-color-tinted floor, both lit. |
| [Wireframe](Wireframe/) | Orbiting solids drawn as their triangle edges (`wireframe()`), faces see-through. |
| [SceneDefocus](SceneDefocus/) | Depth of field on a 3D scene defocused by its *own* depth buffer: a row of orbs drawn into a render target, then `scene.combined(with: scene.depth, .defocus(...))` racks focus through them. Drag to rack by hand. |
| [DepthCloud](DepthCloud/) | A live 3D point cloud from one webcam: a neural depth model lifts each pixel into space, colored by the camera image, orbiting. Needs `Scripts/fetch-models.sh`. |
| [Record3DCloud](Record3DCloud/) | An iPhone RGBD recording orbited as a point cloud: a `.r3d` clip from the Record3D app, unprojected with its true camera intrinsics. Drop a recording in `~/Downloads`. Needs `import OllinRecord3D`. |
| [Record3DLiveCloud](Record3DLiveCloud/) | A **live** RGBD cloud streamed from a tethered iPhone: open Record3D, turn on USB streaming, and the phone's depth camera becomes a real-time point cloud on the Mac. Needs `import OllinRecord3D`. |
| [DepthCompositing](DepthCompositing/) | A 2D card standing between two point-cloud orbs — depth-aware compositing: the near orb draws over the card, the far one is hidden behind it, with per-orb billboard pins. |
| [DepthOcclusion](DepthOcclusion/) | 2D discs hung at a draggable depth plane over a live webcam depth feed (a neural model), occluded by whoever stands nearer. Needs `import OllinVision` + `Scripts/fetch-models.sh`. |
| [MetricDepthScene](MetricDepthScene/) | 2D markers floating at **true metric depths** (meters) inside a live LiDAR feed: a `Camera3D.fromIntrinsics` makes the feed metric, so a marker at a real distance is blocked when you step closer than it. Needs `import OllinRecord3D`. |
| [DepthLiftedPose](DepthLiftedPose/) | A 2D body pose lifted into metric 3D through a depth frame: the tethered phone's depth back-projects each tracked joint, and the skeleton is drawn in space over the person's own cloud. Needs `import OllinVision`/`OllinRecord3D`. |
| [PhoneBodyPose](PhoneBodyPose/) | A live 3D body skeleton streamed from **Ollin Capture** on a tethered iPhone — ARKit body pose over USB, orbited as a stick figure. Needs `import OllinPhone`. |
| [PhoneFace](PhoneFace/) | Ollin Capture's live face mesh and 52 expression blendshapes, orbited as a point cloud with expression bars (tap **Face** on the phone). Needs `import OllinPhone`. |
| [PhoneDepthCloud](PhoneDepthCloud/) | A **live** rear-LiDAR RGBD cloud from Ollin Capture (tap **World**): Ollin's own-app world-facing depth feed, unprojected with the stream's true intrinsics and orbited. Needs `import OllinPhone`. |
| [PhoneWorldScan](PhoneWorldScan/) | Sweep the phone (tap **World**) and each depth frame is placed by its camera pose into one fused `WorldCloud` of the room — **R** to reset. Needs `import OllinPhone`. |
| [PhoneSegmentation](PhoneSegmentation/) | Ollin Capture's on-device person matte (tap **Segment**): the cutout lifted onto a live gradient backdrop, the tinted matte as a drop shadow. Needs `import OllinPhone`. |

See [`Docs/3D/3D.md`](../../Docs/3D/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/3D/Record3D.md`](../../Docs/3D/Record3D.md); the Ollin Capture stream is documented in [`Docs/3D/Phone.md`](../../Docs/3D/Phone.md).
