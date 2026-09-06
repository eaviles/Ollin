#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → 3D</sup>

---

## 3D

These sketches opt into Ollin's 3D mode. 2D stays the default. A sketch becomes
3D when it sets a `camera` (`perspective`/`ortho`/`camera`). The renderer then
adds a depth buffer and draws 3D geometry through that camera. World space is
right-handed and y-up.

The section is large, so the sketches are grouped by topic:
[Geometry](#geometry) · [Physics](#physics) · [Camera](#camera) ·
[Materials](#materials) · [Lighting](#lighting) · [Environments](#environments) ·
[Effects](#effects) · [Raymarching](#raymarching) · [Depth](#depth) ·
[Phone](#phone)

### Geometry

This group covers meshes, point clouds, and the 3D transform stack.

| Sketch | What it shows |
| --- | --- |
| [PointCloud](Geometry/PointCloud/) | A rippling heightfield drawn as an orbiting 3D point cloud. It shows the camera, the depth buffer, and instanced disc splats. |
| [StrangeAttractor](Geometry/StrangeAttractor/) | A Lorenz attractor integrated with Runge-Kutta and splatted as a 150k-point cloud. The points are colored by orbit speed and lit additively. Grab and orbit it (`StrangeAttractor.lorenz`). |
| [Transforms](Geometry/Transforms/) | The 3D transform stack: a sun, planets orbiting it, and a moon orbiting each planet. Nested `withState` blocks make the orbits within orbits, and one point-cloud blob is placed many ways by `translate`/`rotateY`/`scale`. |
| [Solids](Geometry/Solids/) | The closed-solid catalog (box, sphere, cylinder, torus, the Platonics, and more), drawn as colorful clay and shaded by the auto-lit default. |
| [ShadowArt](Geometry/ShadowArt/) | A solid carved so that it throws a ring from the front and a cross from the side. The shadow it really throws is drawn beside the shadow that was asked for (`shadowArt`, `shadow(from:)`). |
| [ShapeFactory](Geometry/ShapeFactory/) | The parametric and profile mesh set (Möbius, Klein, superellipsoid, supershape, extrude, lathe), morphing on `time`. |
| [SolidType](Geometry/SolidType/) | A word extruded into a solid that catches the light and throws a shadow. The same word is also drawn one letter at a time, and each letter nods about its own center (`drawText3D`, `Mesh.text`, `Mesh.textGlyphs`). |
| [Ocean](Geometry/Ocean/) | A sea built from its own wave spectrum. One inverse Fourier transform on the GPU makes the surface, which is drawn as water with no geometry anywhere (`oceanField`, `drawOcean`). |
| [Planet](Geometry/Planet/) | A world with nothing loaded. Six compute kernels bake its elevation, surface, relief, finish, city lights, and weather once. Spheres wear those maps under one sun, and the terminator decides both where the cities show and where the air glows. |
| [LoadedMesh](Geometry/LoadedMesh/) | A mesh loaded from a file (`.obj`/`.usdz`/`.gltf`/…). Point it at your own file with `OLLIN_MESH=<path>`, or use the bundled crystal. Either way the mesh is recentered, scaled to fit, and lit. |
| [TexturedMesh](Geometry/TexturedMesh/) | A UV-gridded globe textured with an image, standing over a floor tinted by a base color. Both are lit. |
| [Wireframe](Geometry/Wireframe/) | Orbiting solids drawn as their triangle edges (`wireframe()`), so the faces are see-through. |
| [SurfaceScatter](Geometry/SurfaceScatter/) | Trees standing on a globe. `surfacePoints` scatters them over the skin by area, and `alignment` stands each one up. The `spread` parameter compares an even covering, a plain draw, and the vertex-list shortcut. |
| [Terrain](Geometry/Terrain/) | Generated terrain, then weathered. A heightfield is grown by diamond-square subdivision, then eroded by tens of thousands of simulated raindrops that carve ravines and build sediment fans. |
| [Metaballs](Geometry/Metaballs/) | Soft spheres that merge as they come close. Every ball adds a bump to one shared field, and `isosurface` walks that field into a mesh. |
| [MeshGrowth](Geometry/MeshGrowth/) | A surface that grows more than it has room for. Its vertices are pushed apart, faster where the surface is already crowded, until it buckles. |
| [SubdivisionSurfaces](Geometry/SubdivisionSurfaces/) | A coarse low-poly cage refined into a smooth solid (`mesh.subdivided(_:levels:)`). |
| [SurfaceFromPoints](Geometry/SurfaceFromPoints/) | A surface rebuilt from points, two ways. A knot is sampled into a bare point cloud and then reconstructed from that cloud. |
| [HopfFibration](Geometry/HopfFibration/) | A sphere's worth of circles. No two of them meet, and every two of them are linked exactly once. |
| [LoadedScene](Geometry/LoadedScene/) | A whole authored scene drawn in place, opening on its own camera and lights. F swaps the glTF stage for its USD version, a sculpture court lit by UsdLux, through the same loadScene call. |
| [SceneExplorer](Geometry/SceneExplorer/) | A read-only viewer for a scene file. Point it at a glTF or USD scene and look around it, part by part. |
| [AnimatedScene](Geometry/AnimatedScene/) | A scene file's authored animation played back, with keyframe tracks posing named nodes. F swaps the glTF orrery for a USD kinetic mobile, whose timeSamples play the same way. |
| [SkinnedScene](Geometry/SkinnedScene/) | A scene file's deforming animation: skins that bend meshes and morph targets that blend them. F swaps the glTF tidepool for a USD pond, whose UsdSkel rig is read by Ollin's own parser. |
| [Fabrication](Geometry/Fabrication/) | A generated shape written out as a file a 3D printer can build, with a report on whether the printer can build it. |
| [SpatialExport](Geometry/SpatialExport/) | A sketch exported as a model instead of a picture. Ordinary 3D is written out as USDZ. |
| [SpatialVideo](Geometry/SpatialVideo/) | A sketch exported as something you can look into. The scene is built for depth rather than for a flat frame. |

### Physics

This group covers bodies inside the scene, rigid and soft: stacks and joints, cloth, rope, and floating. A Jolt-backed `World3D` is stepped each frame
(`import OllinPhysics`), and every body is drawn from its pose with `withBody`.
See the [3D physics reference](../../Docs/Simulation/Physics3D.md).

| Sketch | What it shows |
| --- | --- |
| [Stack](Physics/Stack/) | A crate pyramid on a floor. Click to fire a heavy ball from the camera and knock it down, and press space to rebuild it. Shows `addBody`, `ground`, and an opening `velocity`. |
| [Tumble](Physics/Tumble/) | A rain of mixed solids (boxes, balls, capsules, drums) piling up. Drag any shape to fling it. Shows the `Collider3D` catalog plus `grabBody`/`dragGrab`. |
| [Chain](Physics/Chain/) | A wrecking ball on a chain of capsule links, each joined by a `.ball` joint. Drag it back and let it swing into the crates. Shows `connect` and the joint kinds. |
| [Windmill](Physics/Windmill/) | A motored blade cross batting balls through swing gates that springs hold shut. Space cuts the power, and friction slows it to a stop. Shows `.compound` bodies, `drive(at:)`/`drive(to:)`, limits, and `softenLimits`. |
| [Rockslide](Physics/Rockslide/) | Rocks tumbling down an eroded mountainside. The collider traces the same surface the mesh draws. Shows the `.heightfield` collider over a generated `Heightfield`. |
| [Trigger](Physics/Trigger/) | Balls dropped through a scoring hoop into a tray. The tray lights up with its load, and each knock rings at the speed the ball landed. Shows contact events (`world.contacts`) and sensor bodies (`isSensor`). |
| [Stroll](Physics/Stroll/) | Walk a figure over an eroded island. Use the arrows or WASD to move and space to jump. Stairs lead up to a lookout that lights as you arrive. Shows `addCharacter`, `move`/`jump`, `stepHeight`, and `withCharacter`. |
| [Crawler](Physics/Crawler/) | A machine on tracks working a quarry. Use the arrows or WASD to drive, and hold both to spin it on the spot. The gearing, the track grip, and the springs are on live sliders. Its track bands are drawn as links that scroll at the speed the solver reports. Shows `tracked:`, `trackSpeed`, and `wheels(on:)`. |
| [Joyride](Physics/Joyride/) | Drive a car over an eroded island. Use the arrows or WASD to drive and space for the hand brake. The gearing, the springs, and the tire grip are on live sliders. Shows `addVehicle`, `Wheel3D`, `throttle`/`steering`/`handBrake`, and `withWheel`. |
| [Ragdoll](Physics/Ragdoll/) | A skinned figure given weight. It stands and waves while its joints are powered, and collapses when they are not. Either way you can drag it around by an arm. Shows `addRagdoll`, `scene.apply(ragdoll)`, `drive(toward:)`, and `withLimb`. |
| [Drape](Physics/Drape/) | A washing line in the wind: a banner pegged along its top edge that flaps, a sheet thrown over a crate, and a beach ball you can let the air out of. Drag any of them. Shows `addSoftBody`, `pinned:`, `pressure`, `applyForce`, `drawSoftBody`, and `grabSoftBody`. |
| [Rigging](Physics/Rigging/) | Three lines hanging from a gantry, all built from a polyline. One is a limp rope. One is a chain whose links interlock, because every other link is rolled a quarter turn about the rope's own axis. One is a vine stiff enough to hold a curve, with leaves carried along it. Drag any of them, and press space to stop the wind. Shows `addRope`, `Rope3D.segments`, `withSegment`, and `bend`. |
| [Cape](Physics/Cape/) | A figure striding with a cape clasped at the neck. The collar is carried by the skeleton under the skin, and everything below it hangs and swings. Space collapses the figure, and the cape comes down with it. F cuts the leash. Shows `skinnedTo:`, `carriedBy:`, `sway:`, `backStop:`, `maxStretch:`, and `follow(_:)`. |
| [Raft](Physics/Raft/) | A raft made of cloth riding a swell with cargo on it. Drag the deck under a sounding line that stops at it, or through a harbour gate that reports the raft passing. This is a soft body as a member of the world. Shows `SoftBody3D.density`, `world.contacts` naming a cloth, `raft.touching`, and `raycast` seeing a cloth. |
| [Flotsam](Physics/Flotsam/) | A harbour after a spill. Crates from cork-light to nearly waterlogged ride a swell, each at its own depth. A stone anchor sits on the bottom, and a current carries the lot past. Drag a crate under and let go. Shows `world.water`, `Water.Waves`, `density`, `waterMesh`, and `flow`. |
| [Sightlines](Physics/Sightlines/) | A yard under watch. A lamp lights only the crates in its line of sight. A drone holds its clearance over whatever passes below, and a pulse pushes everything inside a sphere. Drag a crate into cover. Shows `raycast`, `sweep`, and `bodiesOverlapping`. |
| [Sieve](Physics/Sieve/) | Beads of three colors sorted down one ramp. Each window in the ramp is told to ignore one color, so that color falls through it and the rest roll over. Space withdraws the rules, and everything rolls to the end. Shows `group:`, `ignoreCollisions(between:and:)`, and `raycast(as:)`. |
| [Bagatelle](Physics/Bagatelle/) | A pin table in a 3D world with its third dimension removed. Every ball is held to the board's plane, so the machine works however hard the pins knock the ball about. Turn that off and the balls wander out of the board. Space fires a shot fast enough to pass through a thin rail unless its path is checked. Shows `freedom:`, `gravityScale`, and `checksPath`. |
| [Contraption](Physics/Contraption/) | A workshop of machines, each built on a joint a hinge cannot make: a gear pair driving a rack through the same shaft, a rope over two hooks trading a tray for a counterweight, a platter allowed only to rise and spin, and a cart threaded onto a track. Space loads the tray. Shows `.gear`, `.rackAndPinion`, `.pulley`, `.allowing`, and `.path`. |
| [Imported](Physics/Imported/) | A scene whose physics was written down in a file. `yard.usda` says which prims fall, what shape they collide as, how heavy they are, and where the hinges go, and one call builds the lot. The scene holds a seesaw, a stack, a hammer that is one body wearing two shapes, and a sign hinged to the world. Shows `world.addBodies(from:)`. |
| [Yard](Physics/Yard/) | A whole yard saved and restored: a truck you drive with the arrows, a figure pacing across it, a second figure lying where it fell, and a banner strung up over it. S writes the lot to a file, and L reads it back, so a restore comes back mid-drive and mid-stride. The terrain floor and the cloth are named rather than held, and the figure's skin stays the sketch's own asset. R also puts back the exact arrangement the yard settled into, before anything is saved. Shows `snapshot()`, `assetName`, `restore(_:resolving:)`, `world.vehicles`, `world.characters`, `world.ragdolls`, and `world.softBodies`. |

### Camera

This group covers driving the view: interactive control, cinematic moves, and snaps to inspection views.

| Sketch | What it shows |
| --- | --- |
| [CameraControl](Camera/CameraControl/) | Interactive camera control. `cameraControl()` lets the viewer drag to orbit a still life, scroll to dolly, and right-drag (or shift/option-drag) to pan. The motion is damped, so it settles, and a flick keeps a little spin. |
| [CameraMoves](Camera/CameraMoves/) | Cinematic camera moves over one still life: a `.turntable` spin, a `.sway`, a `.pushIn`/`.pullOut` dolly, a `.tilt`, the `.orbitAndRise` beauty pass, a `.reveal`, and a `.handheld` drift. Each is one `cameraMove(_:)` call, and it composes over the pose the last move left. Click or press a key to step. |
| [SceneViews](Camera/SceneViews/) | The host's **Camera** menu snaps an auto-orbiting scene to the standard inspection views (Front/Back/Left/Right/Top/Bottom/Isometric and Reset, ⌘0–⌘7), the way a modeling tool's numpad does. |

### Materials

This group covers what surfaces are made of: stylized finishes, physically based metal, glass, subsurface, thin film, and the map set that varies any of them per pixel.

| Sketch | What it shows |
| --- | --- |
| [Materials](Materials/Materials/) | The material library. One orbiting sphere grid wears each built-in `Material` (`.iridescent`/`.soapBubble`/`.velvet`/`.jade`/`.toon`/`.gooch`/…), and the view-angle finishes shift as it turns. |
| [PhysicalMaterials](Materials/PhysicalMaterials/) | The physically-based finish as a metallic × roughness sweep. `Material.physicallyBased` shades one sphere grid from tight mirror highlights to matte, and from dielectric to metal. |
| [Matcap](Materials/Matcap/) | Matcaps. A whole surface-and-lighting look is baked into one sphere texture and sampled by the view normal (`matcap(_:)`). That gives chrome, clay, wax, or a cel look with no scene lights at all. |
| [Explorer](Materials/Explorer/) | The material explorer. Every finish is shown on one shape, with its parameters to adjust. |
| [SurfaceMaps](Materials/SurfaceMaps/) | The rest of the surface-map set: metallic-roughness, occlusion, and emissive maps, each varying a finish per pixel. |
| [NormalMaps](Materials/NormalMaps/) | Normal maps: per-pixel surface relief without per-pixel geometry. |
| [Detail](Materials/Detail/) | Detail maps: texture that stays sharp under a close look. |
| [Parallax](Materials/Parallax/) | One height map read two ways: parallax occlusion and real displacement. |
| [Triplanar](Materials/Triplanar/) | Texture for meshes with no uvs at all, projected from three directions. |
| [Decals](Materials/Decals/) | Pictures stamped onto the scene, projected rather than mapped. |
| [Glass](Materials/Glass/) | Physically-based transmission and refraction. |
| [SeeThrough](Materials/SeeThrough/) | The scene showing through glass, with no ray tracing. |
| [LiveSurface](Materials/LiveSurface/) | The camera frame wraps a globe and lights it, so a live feed serves as a surface. |
| [CoatAndCloth](Materials/CoatAndCloth/) | Clearcoat and sheen, the two layered finishes on the physically-based material. |
| [Subsurface](Materials/Subsurface/) | Light that travels under the surface before it comes back out. |
| [BrushedMetal](Materials/BrushedMetal/) | Anisotropic specular: brushed, turned, and satin finishes whose highlight is a streak instead of a dot. |
| [ThinFilm](Materials/ThinFilm/) | Thin-film interference two ways: a series of nm thicknesses on a physically-based surface, and animated soap bubbles on thin glass. |

### Lighting

This group covers the light kinds, curated rigs, and cast shadows.

| Sketch | What it shows |
| --- | --- |
| [Lighting](Lighting/Lighting/) | The three light kinds placed by hand to shade solids: a fixed directional key, an orbiting point bulb, and a sweeping spot. A row of spheres shows rising `specularSharpness`. |
| [LightingPresets](Lighting/LightingPresets/) | One call relights the whole scene. The curated `LightingPreset`s (`.standard`/`.threePoint`/`.goldenHour`/`.noir`/`.studio`/`.moonlight`) cycle over one still life, plus a custom rig built in the sketch. Click or press a key to step. |
| [Shadows](Lighting/Shadows/) | Directional cast shadows. Solids drop shadows onto a floor and onto one another through `castShadows()`. |
| [SpotShadow](Lighting/SpotShadow/) | A spot light as the shadow caster. A perspective shadow map is fit to its cone, so the solids inside the beam drop crisp shadows. |
| [PointShadow](Lighting/PointShadow/) | A point light as an omnidirectional caster. A bulb at the center throws shadows in every direction, ray-traced on an RT GPU and through a depth cube elsewhere. |
| [ManyCasters](Lighting/ManyCasters/) | Several casters at once. A warm key is joined by a swinging spot or by two circling point lamps, and each throws its own shadow. |
| [AreaLights](Lighting/AreaLights/) | Rect, disk, and tube sources shading a small studio set. The softbox grows and shrinks, and the softness of its shadows follows its size. |
| [LightShaping](Lighting/LightShaping/) | Photometric profiles and a projected cookie, the two ways a real fixture shapes its beam. |
| [VolumetricLight](Lighting/VolumetricLight/) | Beams, gobos, and shafts you can see in the air. |
| [Caustics](Lighting/Caustics/) | The light a glass or a polished metal focuses onto what is around it. |
| [GlobalIllumination](Lighting/GlobalIllumination/) | Light that bounces, so a red wall reddens what stands beside it. |

### Environments

This group covers image-based lighting, with HDRIs that are bundled, downloaded, loaded from a URL, or synthesized.

| Sketch | What it shows |
| --- | --- |
| [ImageBasedLighting](Environments/ImageBasedLighting/) | `environment(_:)` lights the scene from an HDRI, so physically-based metals fill in with real reflections instead of reading near-black. The same environment also serves as the skybox backdrop. |
| [EnvironmentGallery](Environments/EnvironmentGallery/) | The eight bundled CC0 HDRI environments (studio, courtyard, forest, interior, city, sunrise, sunset, night) stepped through over one PBR still life. They advance on their own, or you can step with the arrow keys. |
| [RemoteEnvironment](Environments/RemoteEnvironment/) | Environments fetched from the web: a sharper 2K/4K/8K backdrop for a bundled environment (`highResolution(_:)`), or any equirectangular HDRI URL (`Environment.hdri(downloadURL:)`). Each is downloaded once and cached. Any key switches. |
| [ProceduralSky](Environments/ProceduralSky/) | A daylight dome with no asset. `environment(.sky(...))` synthesizes a physically-based sky at runtime and sweeps its sun through a full day. |
| [Cloudscape](Environments/Cloudscape/) | A raymarched cloudscape over the procedural sky. |
| [LiveEnvironment](Environments/LiveEnvironment/) | A live camera environment: the room the sketch is in lights the scene. |

### Effects

This group covers the scene-wide realism passes over the 3D frame.

| Sketch | What it shows |
| --- | --- |
| [SceneDefocus](Effects/SceneDefocus/) | Depth of field on a 3D scene, defocused by its own depth buffer. A row of orbs is drawn into a render target, then `scene.combined(with: scene.depth, .defocus(...))` racks focus through them. Drag to rack focus by hand. |
| [AmbientOcclusion](Effects/AmbientOcclusion/) | Screen-space ambient occlusion from the scene's own depth and normals. It adds the soft darkening in crevices and contact gaps that grounds a brightly lit scene. |
| [ScreenSpaceReflections](Effects/ScreenSpaceReflections/) | Surfaces reflecting the scene around them. SSR is traced over the frame and shown on a ring of reflective spheres in different metal finishes. |
| [RayTracedReflections](Effects/RayTracedReflections/) | Metals mirroring the actual scene, off-screen geometry included and with none of SSR's streaks. Rough surfaces spread their rays for a glossy result, and there is a `reflectionBounces` parameter. Needs a ray-tracing GPU and an environment. |
| [ContactShadows](Effects/ContactShadows/) | The fine dark seam that seats an object on the surface it stands on. |
| [Atmosphere](Effects/Atmosphere/) | Fog as a cue for distance and height, and physical aerial perspective, both over one colonnade. Hold space to switch. |
| [MotionBlur](Effects/MotionBlur/) | The streak a real camera's open shutter leaves on something moving. |
| [TemporalAA](Effects/TemporalAA/) | Edges refined past MSAA by accumulating jittered frames. |
| [SpecularAntialias](Effects/SpecularAntialias/) | Highlights smaller than their pixel, held still instead of crawling. |
| [Upscaling](Effects/Upscaling/) | The frame is rendered small and reconstructed at full size, which keeps the frame rate up. |
| [FrameInterpolation](Effects/FrameInterpolation/) | The sketch draws half as often, and a generated frame between each pair lets the display keep its rate. |
| [LensFlare](Effects/LensFlare/) | The light a camera adds to a picture on its own. |
| [PathTraced](Effects/PathTraced/) | Tune the scene live, then render the same frame offline with a path tracer. |

### Raymarching

This group covers the 3D SDF combinators: distance fields that merge, sphere-traced beside the meshes.

| Sketch | What it shows |
| --- | --- |
| [RaymarchedSDF](Raymarching/RaymarchedSDF/) | The 3D SDF combinators sphere-traced as one surface. Spheres melt together by smooth-union, and their colors blend through the seam. One sphere orbits, and a bite is carved out by subtraction. |
| [RaymarchedShapes](Raymarching/RaymarchedShapes/) | The raymarched primitive catalog beyond the first four (rounded box, cylinder, cone, octahedron, ellipsoid). Each is a field traced into the shared depth buffer. |
| [RaymarchedSculpt](Raymarching/RaymarchedSculpt/) | The scoped block form. Inside `smoothUnion(k:) { … }`, bare mesh calls (`drawSphere`, `drawCapsule`, `drawCone`, …) are captured as fields and melt into one traced surface. |
| [RaymarchedDomain](Raymarching/RaymarchedDomain/) | Domain operators. `repeated(spacing:count:)` tiles a unit cell into a finite lattice, and `mirrored(x:y:z:)` folds one built lobe into a symmetric form. The whole thing stays one surface. |
| [RaymarchedRadial](Raymarching/RaymarchedRadial/) | Polar repetition. `repeatedRadially` folds one wedge into an evenly spaced rosette around an axis, with no draw cost per copy. |
| [RaymarchedPlane](Raymarching/RaymarchedPlane/) | The infinite plane leaf. An unbounded ground is merged into the field and marched to the far plane, and it catches the shapes' soft shadows. |
| [RaymarchedStretch](Raymarching/RaymarchedStretch/) | Per-axis sizing. `stretched` is exact elongation, so a sphere becomes a capsule. Beside it, `scaled(x:y:z:)` is a true non-uniform scale, marched conservatively. |
| [RaymarchedGradient](Raymarching/RaymarchedGradient/) | Gradient paint on a merged field. A gradient `fill` paints the whole sphere-traced surface, sampled at each hit's projected screen position. |
| [RaymarchedEnvironment](Raymarching/RaymarchedEnvironment/) | Raymarched fields lit by an environment. They get the same image-based lighting and traced reflections the meshes get. |
| [RaymarchedShadow](Raymarching/RaymarchedShadow/) | A field shadowing itself under `castShadows()`. A soft penumbra is marched toward the light and evaluated as part of the surface shading. |
| [RaymarchedCastShadow](Raymarching/RaymarchedCastShadow/) | A field casting a shadow onto meshes under a directional or point light (any key switches). Either the field renders into the 2D shadow map, or the lit mesh fragments march the field inline toward the light. |
| [RaymarchedReceiveShadow](Raymarching/RaymarchedReceiveShadow/) | A field receiving a mesh's cast shadow under a directional or point light (any key switches). The traced surface samples the 2D map, the shadow cube, or the acceleration structure at its hit. |
| [RaymarchedClay](Raymarching/RaymarchedClay/) | The sculpt block. The combine mode and melt amount are held as state, so a form reads top to bottom like working clay. |
| [RaymarchedJoinery](Raymarching/RaymarchedJoinery/) | Machined joints and hardware: chamfered and stepped unions, a hanging chain, a capped-torus hook. |
| [RaymarchedDetailing](Raymarching/RaymarchedDetailing/) | The detailing ops: fluted seams, engraved rings, grooved bands, beading, and a pipe bead left hanging where two bodies crossed. |
| [RaymarchedDistort](Raymarching/RaymarchedDistort/) | The sculpting distortions: twisted, bent, displaced, and roughened, one plinth each. |
| [RaymarchedFractals](Raymarching/RaymarchedFractals/) | The fractal leaves: a Mandelbulb, a Menger sponge, and a Mandelbox. Each is a distance estimate that the same sphere tracer draws. A menu picks one, and the bulb's power, the sponge's depth, and the box's scale are each a parameter of their own. |

### Depth

This group covers depth feeds and depth-aware compositing: cameras, recordings, and metric space.

| Sketch | What it shows |
| --- | --- |
| [DepthCloud](Depth/DepthCloud/) | A live 3D point cloud from one webcam. A neural depth model lifts each pixel into space, the camera image colors it, and the cloud orbits. Needs `Scripts/fetch-models.sh`. |
| [Record3DCloud](Depth/Record3DCloud/) | An iPhone RGBD point cloud orbited in 3D. By default it plays the newest `.r3d` clip in `~/Downloads`, and it switches to the live USB stream as soon as a tethered phone offers one. Either way the cloud is unprojected with the true camera intrinsics. Needs `import OllinRecord3D`. |
| [DepthCompositing](Depth/DepthCompositing/) | Depth-aware compositing, with a 2D card standing between two point-cloud orbs. The near orb draws over the card, and the far one is hidden behind it. Each orb has its own billboard pin. |
| [DepthOcclusion](Depth/DepthOcclusion/) | 2D drawing hung at a depth plane and occluded by whoever stands nearer. A webcam depth model places it at a normalized `0...1` plane, and **M** switches to real meters from a tethered LiDAR iPhone (`camera(.intrinsic(...))`). Needs `import OllinVision`/`OllinRecord3D` + `Scripts/fetch-models.sh`. |
| [DepthLiftedPose](Depth/DepthLiftedPose/) | A 2D body pose lifted into metric 3D through a depth frame. The tethered phone's depth back-projects each tracked joint, and the skeleton is drawn in space over the person's own cloud. Needs `import OllinVision`/`OllinRecord3D`. |
| [ClosedLoopScan](Depth/ClosedLoopScan/) | A made-up hall walked all the way around and back, scanned twice side by side. The left half lines each frame up. The right half does the same, and `ScanGraph` also recognizes the place it started. The true walls are drawn over both. There is nothing to plug in. **R** walks it again, and **C** cycles the right half between the reported pose, lined-up frames, and the closed loop. |

### Phone

These sketches read the **Ollin Capture** iPhone app, which streams ARKit perception over USB.

| Sketch | What it shows |
| --- | --- |
| [PhoneBodyPose](Phone/PhoneBodyPose/) | A live 3D body skeleton streamed from **Ollin Capture** on a tethered iPhone. ARKit body pose arrives over USB and is orbited as a stick figure. Needs `import OllinPhone`. |
| [PhoneBodyFigure](Phone/PhoneBodyFigure/) | A solid mannequin posed by the richer half of that same stream. Joint orientations turn its parts, the world anchor stands it where the person stands, the scale sizes it, and the tracked flags tint it. Needs `import OllinPhone`. |
| [PhoneCostume](Phone/PhoneCostume/) | A costume worn by the live skeleton, inspired by Universal Everything's *Super You*. It is either ribbon trails that only exist in motion, or plumage whose twist follows the joint rotations. Needs `import OllinPhone`. |
| [PhoneFace](Phone/PhoneFace/) | Ollin Capture's live face mesh and its 52 expression blendshapes, orbited as a point cloud with expression bars. Tap **Face** on the phone. Needs `import OllinPhone`. |
| [PhoneGaze](Phone/PhoneGaze/) | The eyes and the gaze from that same Face mode. Eyeballs stand at the streamed eye poses and blink with their blendshapes, beams converge on the look-at point, and a bead marks where they meet. Needs `import OllinPhone`. |
| [PhoneDepthCloud](Phone/PhoneDepthCloud/) | A live rear-LiDAR RGBD cloud from Ollin Capture (tap **World**). This is the world-facing depth feed from Ollin's own app, unprojected with the stream's true intrinsics and orbited. Needs `import OllinPhone`. |
| [PhoneWorldScan](Phone/PhoneWorldScan/) | Sweep the phone (tap **World**). Each depth frame is lined up against the scan so far. The frames fuse into one `WorldCloud` of the room. **C** turns the drift correction off, and **R** resets. Needs `import OllinPhone`. |
| [PhoneSegmentation](Phone/PhoneSegmentation/) | Ollin Capture's on-device person matte (tap **Segment**). The cutout is placed on a live gradient backdrop, and the tinted matte serves as its drop shadow. Needs `import OllinPhone`. |
| [PhoneRoomMesh](Phone/PhoneRoomMesh/) | Walk the phone around (tap **Room**), and the room arrives as a solid surface, with each triangle painted by what it is. Keys: **space**, **F**, **R**. Needs `import OllinPhone`. |
| [PhoneRoomPlanes](Phone/PhoneRoomPlanes/) | The flat surfaces in that same room, each drawn as its real outline. A ball stands on the biggest one, and the scene is lit by the room's own light. Keys: **space**, **F**, **M**, **L**, **R**. Needs no LiDAR. Needs `import OllinPhone`. |
| [PhoneHands](Phone/PhoneHands/) | The hands the phone sees (tap **Hands**, up to 4), drawn as small solid skeletons standing in the room. They are lifted to metric 3D through the LiDAR depth. A pinch closes into a bright bead. Without LiDAR the same stream draws as a flat overlay. Needs `import OllinPhone`. |
| [PhoneWorldText](Phone/PhoneWorldText/) | The words the phone can read (tap **Text**), placed where they sit in the room. Each line is wire-frame type on a framed panel, lifted through the LiDAR depth. Without LiDAR it draws as a flat overlay. Needs `import OllinPhone`. |
| [PhoneMarkers](Phone/PhoneMarkers/) | The pictures and objects the phone knows (tap **Markers**), found in the room. A city of columns rises from every print it recognizes, framed by the print's own edge. A scanned object arrives as the box its scan measured. To add a picture, drop it into the app's folder, named with its printed width. Needs `import OllinPhone`. |
| [PhonePointer](Phone/PhonePointer/) | The phone held as a pointer (tap **Wand**). A beam from the back of the phone lands on a ball. A press on the pad picks the ball up, sliding the thumb pushes it away or pulls it in, and letting go drops it. Needs no LiDAR. Needs `import OllinPhone`. |
| [PhoneAttention](Phone/PhoneAttention/) | Where the phone's picture draws the eye (tap **Attention**). The heat map shows as a warm glow over the live frame. A frame surrounds each region the model picks out, and an eased bead trails where the attention has been. Needs no LiDAR. Needs `import OllinPhone`. |

See [`Docs/3D/3D.md`](../../Docs/3D/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/3D/Record3D.md`](../../Docs/3D/Record3D.md). The Ollin Capture stream is documented in [`Docs/3D/Phone.md`](../../Docs/3D/Phone.md).
