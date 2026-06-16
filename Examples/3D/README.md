# 3D

Sketches that opt into Ollin's 3D mode. 2D stays the default — a sketch becomes
3D by setting a `camera` (`perspective`/`ortho`/`camera`), which makes the renderer
add a depth buffer and draw 3D geometry through the camera. World space is
right-handed and y-up.

| Sketch | What it shows |
| --- | --- |
| [PointCloud](PointCloud/) | A rippling heightfield drawn as an orbiting 3D point cloud — camera, depth, and instanced disc splats. |
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

See [`Docs/3D.md`](../../Docs/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/Record3D.md`](../../Docs/Record3D.md); the Ollin Capture stream is documented in [`Docs/Phone.md`](../../Docs/Phone.md).
