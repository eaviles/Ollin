#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Depth</sup>

---

## Depth

This group covers depth feeds and depth-aware compositing: cameras, recordings, and metric space.

| [![ClosedLoopScan](https://media.ollin.art/examples/3D/Depth/ClosedLoopScan/still-640.jpg?v=1ea29b94)](ClosedLoopScan/) | [![DepthCloud](https://media.ollin.art/examples/3D/Depth/DepthCloud/still-640.jpg?v=683508e7)](DepthCloud/) | [![DepthCompositing](https://media.ollin.art/examples/3D/Depth/DepthCompositing/still-640.jpg?v=52ae3f2f)](DepthCompositing/) |  |
|---|---|---|---|
| [ClosedLoopScan](ClosedLoopScan/) | [DepthCloud](DepthCloud/) | [DepthCompositing](DepthCompositing/) |  |

| Sketch | What it shows |
| --- | --- |
| [DepthCloud](DepthCloud/) | A live 3D point cloud from one webcam. A neural depth model lifts each pixel into space, the camera image colors it, and the cloud orbits. Needs `Scripts/fetch-models.sh`. |
| [Record3DCloud](Record3DCloud/) | An iPhone RGBD point cloud orbited in 3D. By default it plays the newest `.r3d` clip in `~/Downloads`, and it switches to the live USB stream as soon as a tethered phone offers one. Either way the cloud is unprojected with the true camera intrinsics. Needs `import OllinRecord3D`. |
| [DepthCompositing](DepthCompositing/) | Depth-aware compositing, with a 2D card standing between two point-cloud orbs. The near orb draws over the card, and the far one is hidden behind it. Each orb has its own billboard pin. |
| [DepthOcclusion](DepthOcclusion/) | 2D drawing hung at a depth plane and occluded by whoever stands nearer. A webcam depth model places it at a normalized `0...1` plane, and **M** switches to real meters from a tethered LiDAR iPhone (`camera(.intrinsic(...))`). Needs `import OllinVision`/`OllinRecord3D` + `Scripts/fetch-models.sh`. |
| [DepthLiftedPose](DepthLiftedPose/) | A 2D body pose lifted into metric 3D through a depth frame. The tethered phone's depth back-projects each tracked joint, and the skeleton is drawn in space over the person's own cloud. Needs `import OllinVision`/`OllinRecord3D`. |
| [ClosedLoopScan](ClosedLoopScan/) | A made-up hall walked all the way around and back, scanned twice side by side. The left half lines each frame up. The right half does the same, and `ScanGraph` also recognizes the place it started. The true walls are drawn over both. There is nothing to plug in. **R** walks it again, and **C** cycles the right half between the reported pose, lined-up frames, and the closed loop. |

Run one with `swift run Example-3D-Depth-<Name>`, for example `swift run Example-3D-Depth-DepthCloud`.
