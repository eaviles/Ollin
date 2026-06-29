#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → 3D</sup>

---

## 3D

- [`3D`](./3D.md) - opt into a 3D camera and depth buffer: orbit a `Camera3D` (perspective or orthographic) and draw `PointCloud`s as instanced disc splats and a catalog of solid primitives (box, sphere, capsule, the Platonic solids, …) plus parametric and profile shapes (supershape, extrude, lathe), meshes loaded from file (`.obj`, `.usdz`/`.stl`/`.ply`, `.gltf`/`.glb`), textured surfaces, and a live webcam depth cloud
- [`Camera control`](./Camera.md) - move the camera by hand (`cameraControl()`: drag to orbit, scroll to dolly, right or modifier-drag to pan, damped) or play a ready-made cinematic move (`cameraMove(_:)`: turntable, push-in, tilt, orbit-and-rise, reveal, handheld), both opt-in over the orbit pose
- [`Depth compositing`](./DepthCompositing.md) - place 2D drawing *inside* a 3D scene so it occludes and is occluded by the geometry: `depth(at:)`, `project`, and `withBillboard` (a 2D label hidden when it swings behind the cloud)
- [`Record3D`](./Record3D.md) - `import OllinRecord3D` to turn an iPhone's color-plus-depth into a 3D point cloud — from a recorded `.r3d` file or a tethered phone's live USB stream
- [`RGBD`](./RGBD.md) - the source-agnostic `RGBDFrame` (color + depth + intrinsics) any depth source produces: unproject a point cloud, lift a single image point to metric 3D, or lift a 2D body pose into space (`Body.lifted(through:)`)
- [`Phone`](./Phone.md) - `import OllinPhone` to read a tethered iPhone's live on-device ARKit sensor stream from Ollin's own capture app: a 3D body skeleton, a face mesh with expression blendshapes, world-facing rear-LiDAR depth (a metric point cloud with the camera's 6DoF pose), and device motion, over the USB cable
