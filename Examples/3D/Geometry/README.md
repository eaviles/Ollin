#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Geometry</sup>

---

## Geometry

| [![AnimatedScene](https://media.ollin.art/examples/3D/Geometry/AnimatedScene/still-640.jpg?v=d2631355)](AnimatedScene/) | [![Fabrication](https://media.ollin.art/examples/3D/Geometry/Fabrication/still-640.jpg?v=aca68699)](Fabrication/) | [![HopfFibration](https://media.ollin.art/examples/3D/Geometry/HopfFibration/still-640.jpg?v=d4647092)](HopfFibration/) | [![LoadedMesh](https://media.ollin.art/examples/3D/Geometry/LoadedMesh/still-640.jpg?v=4c133c2f)](LoadedMesh/) |
|---|---|---|---|
| [AnimatedScene](AnimatedScene/) | [Fabrication](Fabrication/) | [HopfFibration](HopfFibration/) | [LoadedMesh](LoadedMesh/) |
| [![LoadedScene](https://media.ollin.art/examples/3D/Geometry/LoadedScene/still-640.jpg?v=9e509559)](LoadedScene/) | [![MeshGrowth](https://media.ollin.art/examples/3D/Geometry/MeshGrowth/still-640.jpg?v=143d39f7)](MeshGrowth/) | [![Metaballs](https://media.ollin.art/examples/3D/Geometry/Metaballs/still-640.jpg?v=4507ba55)](Metaballs/) | [![Ocean](https://media.ollin.art/examples/3D/Geometry/Ocean/still-640.jpg?v=dc7d3567)](Ocean/) |
| [LoadedScene](LoadedScene/) | [MeshGrowth](MeshGrowth/) | [Metaballs](Metaballs/) | [Ocean](Ocean/) |
| [![Planet](https://media.ollin.art/examples/3D/Geometry/Planet/still-640.jpg?v=0c173659)](Planet/) | [![PointCloud](https://media.ollin.art/examples/3D/Geometry/PointCloud/still-640.jpg?v=c8438425)](PointCloud/) | [![SceneExplorer](https://media.ollin.art/examples/3D/Geometry/SceneExplorer/still-640.jpg?v=aa3cdd0b)](SceneExplorer/) | [![ShadowArt](https://media.ollin.art/examples/3D/Geometry/ShadowArt/still-640.jpg?v=0eb69678)](ShadowArt/) |
| [Planet](Planet/) | [PointCloud](PointCloud/) | [SceneExplorer](SceneExplorer/) | [ShadowArt](ShadowArt/) |
| [![ShapeFactory](https://media.ollin.art/examples/3D/Geometry/ShapeFactory/still-640.jpg?v=5401aed8)](ShapeFactory/) | [![SharpFields](https://media.ollin.art/examples/3D/Geometry/SharpFields/still-640.jpg?v=272b4036)](SharpFields/) | [![SkinnedScene](https://media.ollin.art/examples/3D/Geometry/SkinnedScene/still-640.jpg?v=2605b9da)](SkinnedScene/) | [![SolidType](https://media.ollin.art/examples/3D/Geometry/SolidType/still-640.jpg?v=42ce73a5)](SolidType/) |
| [ShapeFactory](ShapeFactory/) | [SharpFields](SharpFields/) | [SkinnedScene](SkinnedScene/) | [SolidType](SolidType/) |
| [![Solids](https://media.ollin.art/examples/3D/Geometry/Solids/still-640.jpg?v=f6447643)](Solids/) | [![SpatialExport](https://media.ollin.art/examples/3D/Geometry/SpatialExport/still-640.jpg?v=dc5aac05)](SpatialExport/) | [![SpatialVideo](https://media.ollin.art/examples/3D/Geometry/SpatialVideo/still-640.jpg?v=4909ec0c)](SpatialVideo/) | [![StrangeAttractor](https://media.ollin.art/examples/3D/Geometry/StrangeAttractor/still-640.jpg?v=58701d72)](StrangeAttractor/) |
| [Solids](Solids/) | [SpatialExport](SpatialExport/) | [SpatialVideo](SpatialVideo/) | [StrangeAttractor](StrangeAttractor/) |
| [![SubdivisionSurfaces](https://media.ollin.art/examples/3D/Geometry/SubdivisionSurfaces/still-640.jpg?v=c0a24636)](SubdivisionSurfaces/) | [![SurfaceFromPoints](https://media.ollin.art/examples/3D/Geometry/SurfaceFromPoints/still-640.jpg?v=1f71c874)](SurfaceFromPoints/) | [![SurfaceScatter](https://media.ollin.art/examples/3D/Geometry/SurfaceScatter/still-640.jpg?v=9ce4eb54)](SurfaceScatter/) | [![Terrain](https://media.ollin.art/examples/3D/Geometry/Terrain/still-640.jpg?v=ad2260c6)](Terrain/) |
| [SubdivisionSurfaces](SubdivisionSurfaces/) | [SurfaceFromPoints](SurfaceFromPoints/) | [SurfaceScatter](SurfaceScatter/) | [Terrain](Terrain/) |
| [![TexturedMesh](https://media.ollin.art/examples/3D/Geometry/TexturedMesh/still-640.jpg?v=b0c35cde)](TexturedMesh/) | [![Transforms](https://media.ollin.art/examples/3D/Geometry/Transforms/still-640.jpg?v=e2fc0089)](Transforms/) | [![Wireframe](https://media.ollin.art/examples/3D/Geometry/Wireframe/still-640.jpg?v=e69ea91c)](Wireframe/) |  |
| [TexturedMesh](TexturedMesh/) | [Transforms](Transforms/) | [Wireframe](Wireframe/) |  |

This group covers meshes, point clouds, and the 3D transform stack.

| Sketch | What it shows |
| --- | --- |
| [PointCloud](PointCloud/) | A rippling heightfield drawn as an orbiting 3D point cloud. It shows the camera, the depth buffer, and instanced disc splats. |
| [StrangeAttractor](StrangeAttractor/) | A Lorenz attractor integrated with Runge-Kutta and splatted as a 150k-point cloud. The points are colored by orbit speed and lit additively. Grab and orbit it (`StrangeAttractor.lorenz`). |
| [Transforms](Transforms/) | The 3D transform stack: a sun, planets orbiting it, and a moon orbiting each planet. Nested `withState` blocks make the orbits within orbits, and one point-cloud blob is placed many ways by `translate`/`rotateY`/`scale`. |
| [Solids](Solids/) | The closed-solid catalog (box, sphere, cylinder, torus, the Platonics, and more), drawn as colorful clay and shaded by the auto-lit default. |
| [ShadowArt](ShadowArt/) | A solid carved so that it throws a ring from the front and a cross from the side. The shadow it really throws is drawn beside the shadow that was asked for (`shadowArt`, `shadow(from:)`). |
| [ShapeFactory](ShapeFactory/) | The parametric and profile mesh set (Möbius, Klein, superellipsoid, supershape, extrude, lathe), morphing on `time`. |
| [SolidType](SolidType/) | A word extruded into a solid that catches the light and throws a shadow. The same word is also drawn one letter at a time, and each letter nods about its own center (`drawText3D`, `Mesh.text`, `Mesh.textGlyphs`). |
| [Ocean](Ocean/) | A sea built from its own wave spectrum. One inverse Fourier transform on the GPU makes the surface, which is drawn as water with no geometry anywhere (`oceanField`, `drawOcean`). |
| [Planet](Planet/) | A world with nothing loaded. Six compute kernels bake its elevation, surface, relief, finish, city lights, and weather once. Spheres wear those maps under one sun, and the terminator decides both where the cities show and where the air glows. |
| [LoadedMesh](LoadedMesh/) | A mesh loaded from a file (`.obj`/`.usdz`/`.gltf`/…). Point it at your own file with `OLLIN_MESH=<path>`, or use the bundled crystal. Either way the mesh is recentered, scaled to fit, and lit. |
| [TexturedMesh](TexturedMesh/) | A UV-gridded globe textured with an image, standing over a floor tinted by a base color. Both are lit. |
| [Wireframe](Wireframe/) | Orbiting solids drawn as their triangle edges (`wireframe()`), so the faces are see-through. |
| [SurfaceScatter](SurfaceScatter/) | Trees standing on a globe. `surfacePoints` scatters them over the skin by area, and `alignment` stands each one up. The `spread` parameter compares an even covering, a plain draw, and the vertex-list shortcut. |
| [Terrain](Terrain/) | Generated terrain, then weathered. A heightfield is grown by diamond-square subdivision, then eroded by tens of thousands of simulated raindrops that carve ravines and build sediment fans. |
| [Metaballs](Metaballs/) | Soft spheres that merge as they come close. Every ball adds a bump to one shared field, and `isosurface` walks that field into a mesh. |
| [SharpFields](SharpFields/) | A block with a hole bored through it and a corner bitten out, meshed so the corners stay. `isosurface` with `method: .dualContouring` puts each cell's vertex where the field's normals meet, beside marching cubes for the difference. |
| [MeshGrowth](MeshGrowth/) | A surface that grows more than it has room for. Its vertices are pushed apart, faster where the surface is already crowded, until it buckles. |
| [SubdivisionSurfaces](SubdivisionSurfaces/) | A coarse low-poly cage refined into a smooth solid (`mesh.subdivided(_:levels:)`). |
| [SurfaceFromPoints](SurfaceFromPoints/) | A surface rebuilt from points, two ways. A knot is sampled into a bare point cloud and then reconstructed from that cloud. |
| [HopfFibration](HopfFibration/) | A sphere's worth of circles. No two of them meet, and every two of them are linked exactly once. |
| [LoadedScene](LoadedScene/) | A whole authored scene drawn in place, opening on its own camera and lights. F swaps the glTF stage for its USD version, a sculpture court lit by UsdLux, through the same loadScene call. |
| [SceneExplorer](SceneExplorer/) | A read-only viewer for a scene file. Point it at a glTF or USD scene and look around it, part by part. |
| [AnimatedScene](AnimatedScene/) | A scene file's authored animation played back, with keyframe tracks posing named nodes. F swaps the glTF orrery for a USD kinetic mobile, whose timeSamples play the same way. |
| [SkinnedScene](SkinnedScene/) | A scene file's deforming animation: skins that bend meshes and morph targets that blend them. F swaps the glTF tidepool for a USD pond, whose UsdSkel rig is read by Ollin's own parser. |
| [Fabrication](Fabrication/) | A generated shape written out as a file a 3D printer can build, with a report on whether the printer can build it. |
| [SpatialExport](SpatialExport/) | A sketch exported as a model instead of a picture. Ordinary 3D is written out as USDZ. |
| [SpatialVideo](SpatialVideo/) | A sketch exported as something you can look into. The scene is built for depth rather than for a flat frame. |

Run one with `swift run Example-3D-Geometry-<Name>`, for example `swift run Example-3D-Geometry-PointCloud`.
