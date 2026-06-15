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

See [`Docs/3D.md`](../../Docs/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/Record3D.md`](../../Docs/Record3D.md).
