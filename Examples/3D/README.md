# 3D

Sketches that opt into Ollin's 3D mode. 2D stays the default — a sketch becomes
3D by setting a `camera` (`perspective`/`ortho`/`camera`), which makes the renderer
add a depth buffer and draw 3D geometry through the camera. World space is
right-handed and y-up.

| Sketch | What it shows |
| --- | --- |
| [PointCloud](PointCloud/) | A rippling heightfield drawn as an orbiting 3D point cloud — camera, depth, and instanced disc splats. |
| [DepthCloud](DepthCloud/) | A live 3D point cloud from one webcam: a neural depth model lifts each pixel into space, colored by the camera image, orbiting. Needs `Scripts/fetch-models.sh`. |

See [`Docs/3D.md`](../../Docs/3D.md) for the 3D guide.
