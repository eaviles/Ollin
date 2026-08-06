#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → 3D</sup>

---

## 3D

Sketches that opt into Ollin's 3D mode. 2D stays the default; a sketch becomes
3D by setting a `camera` (`perspective`/`ortho`/`camera`), which makes the renderer
add a depth buffer and draw 3D geometry through the camera. World space is
right-handed and y-up.

The section is large, so the sketches are grouped by topic:
[Geometry](#geometry) · [Physics](#physics) · [Camera](#camera) ·
[Materials](#materials) · [Lighting](#lighting) · [Environments](#environments) ·
[Effects](#effects) · [Raymarching](#raymarching) · [Depth](#depth) ·
[Phone](#phone)

### Geometry

Meshes, point clouds, and the 3D transform stack.

| Sketch | What it shows |
| --- | --- |
| [PointCloud](Geometry/PointCloud/) | A rippling heightfield drawn as an orbiting 3D point cloud: camera, depth, and instanced disc splats. |
| [StrangeAttractor](Geometry/StrangeAttractor/) | A Lorenz attractor integrated with Runge-Kutta, splatted as a 150k-point cloud colored by orbit speed and lit additively; grab and orbit it (`StrangeAttractor.lorenz`). |
| [Transforms](Geometry/Transforms/) | The 3D transform stack: a sun, planets orbiting it, and a moon orbiting each planet; orbits within orbits via nested `withState`, one point-cloud blob placed many ways by `translate`/`rotateY`/`scale`. |
| [Solids](Geometry/Solids/) | The closed-solid catalog (box, sphere, cylinder, torus, the Platonics, and more) as colorful clay shaded by the auto-lit default. |
| [ShapeFactory](Geometry/ShapeFactory/) | The parametric/profile mesh set (Möbius, Klein, superellipsoid, supershape, extrude, lathe) morphing on `time`. |
| [LoadedMesh](Geometry/LoadedMesh/) | A mesh loaded from a file (`.obj`/`.usdz`/`.gltf`/…); drop one in with `OLLIN_MESH=<path>` (or use the bundled crystal), recentered, scaled to fit, and lit. |
| [TexturedMesh](Geometry/TexturedMesh/) | A UV-gridded globe textured with an image over a base-color-tinted floor, both lit. |
| [Wireframe](Geometry/Wireframe/) | Orbiting solids drawn as their triangle edges (`wireframe()`), faces see-through. |

### Physics

Rigid bodies inside the scene: a Jolt-backed `World3D` stepped each frame
(`import OllinPhysics`), every body drawn from its pose with `withBody`.
See the [3D physics reference](../../Docs/Simulation/Physics3D.md).

| Sketch | What it shows |
| --- | --- |
| [Stack](Physics/Stack/) | A crate pyramid on a floor; click to fire a heavy ball from the camera and knock it down, space rebuilds. `addBody`, `ground`, opening `velocity`. |
| [Tumble](Physics/Tumble/) | A rain of mixed solids (boxes, balls, capsules, drums) piling up; drag any shape to fling it. The `Collider3D` catalog plus `grabBody`/`dragGrab`. |
| [Chain](Physics/Chain/) | A wrecking ball on a chain of capsule links, each a `.ball` joint; drag it back, let it swing into the crates. `connect` and the joint kinds. |
| [Windmill](Physics/Windmill/) | A motored blade cross batting balls through spring-shut swing gates; space cuts the power and friction coasts it down. `.compound` bodies, `drive(at:)`/`drive(to:)`, limits, `softenLimits`. |
| [Rockslide](Physics/Rockslide/) | Rocks tumbling down an eroded mountainside, the collider tracing the same surface the mesh draws. The `.heightfield` collider over a generated `Heightfield`. |
| [Trigger](Physics/Trigger/) | Balls through a scoring hoop into a tray that lights with its load, each knock ringing at the speed it landed. Contact events (`world.contacts`) and sensor bodies (`isSensor`). |
| [Stroll](Physics/Stroll/) | Walk a figure over an eroded island: arrows or WASD to go, space to jump, stairs up to a lookout that lights as you arrive. `addCharacter`, `move`/`jump`, `stepHeight`, `withCharacter`. |
| [Crawler](Physics/Crawler/) | A machine on tracks working a quarry: arrows or WASD to drive, hold both to spin it on the spot, with the gearing, the track grip, and the springs on live sliders. Its bands are drawn as links that scroll at the speed the solver reports. `tracked:`, `trackSpeed`, `wheels(on:)`. |
| [Joyride](Physics/Joyride/) | Drive a car over an eroded island: arrows or WASD, space for the hand brake, with the gearing, the springs, and the tire grip on live sliders. `addVehicle`, `Wheel3D`, `throttle`/`steering`/`handBrake`, `withWheel`. |
| [Ragdoll](Physics/Ragdoll/) | A skinned figure given weight: it stands and waves while its joints are powered, collapses when they are not, and can be dragged around by an arm either way. `addRagdoll`, `scene.apply(ragdoll)`, `drive(toward:)`, `withLimb`. |
| [Drape](Physics/Drape/) | A washing line in the wind: a banner pegged along its top edge that flaps, a sheet thrown over a crate, and a beach ball you can let the air out of. Drag any of them. `addSoftBody`, `pinned:`, `pressure`, `applyForce`, `drawSoftBody`, `grabSoftBody`. |
| [Cape](Physics/Cape/) | A figure striding with a cape clasped at the neck: the collar is carried by the skeleton under the skin, everything below it hangs and swings. Space collapses the figure and the cape comes down with it; F cuts the leash. `skinnedTo:`, `carriedBy:`, `sway:`, `backStop:`, `maxStretch:`, `follow(_:)`. |
| [Raft](Physics/Raft/) | A raft made of cloth riding a swell with cargo on it: drag the deck under a sounding line that stops at it, or through a harbour gate that reports her passing. A soft body as a member of the world. `SoftBody3D.density`, `world.contacts` naming a cloth, `raft.touching`, `raycast` seeing one. |
| [Flotsam](Physics/Flotsam/) | A harbour after a spill: crates from cork to nearly waterlogged riding a swell at their own depths, a stone anchor on the bottom, and a current carrying the lot past. Drag one under and let go. `world.water`, `Water.Waves`, `density`, `waterMesh`, `flow`. |
| [Sightlines](Physics/Sightlines/) | A yard under watch: a lamp lighting only the crates it can actually see, a drone holding its clearance over whatever passes below, and a pulse that shoves everything inside a sphere. Drag a crate into cover. `raycast`, `sweep`, `bodiesOverlapping`. |
| [Sieve](Physics/Sieve/) | Beads of three colors sorted down one ramp: each window in the ramp is told to ignore one color, so that color falls through it and the rest roll over. Space withdraws the rules and everything rides to the end. `group:`, `ignoreCollisions(between:and:)`, `raycast(as:)`. |
| [Bagatelle](Physics/Bagatelle/) | A pin table in a 3D world talked out of its third dimension: every ball is held to the board's plane, so the machine works however hard the pins knock it about. Turn that off and the balls wander out of the board. Space fires a shot quick enough to leave through a thin rail unless its path is checked. `freedom:`, `gravityScale`, `checksPath`. |
| [Contraption](Physics/Contraption/) | A workshop of machines, each one a joint a hinge cannot make: a gear pair driving a rack through the same shaft, a rope over two hooks trading a tray for a counterweight, a platter allowed only to rise and spin, and a cart threaded onto a track. Space loads the tray. `.gear`, `.rackAndPinion`, `.pulley`, `.allowing`, `.path`. |
| [Cairn](Physics/Cairn/) | A heap of stones laid one at a time, kept. R puts back the arrangement it settled into, exactly; S writes it to a file and L reads it back, so quitting and running again finds the same cairn standing. Drag a stone to wreck it first. `snapshot()`, `restore(_:)`, `save(to:)`, `load(contentsOf:)`. |
| [Imported](Physics/Imported/) | A scene whose physics was written down somewhere else: `yard.usda` says which prims fall, what shape they collide as, how heavy they are, and where the hinges go, and one call makes the lot. A seesaw, a stack, a hammer that is one body wearing two shapes, and a sign hinged to the world. `world.addBodies(from:)`. |
| [Yard](Physics/Yard/) | A yard kept whole: a truck you drive with the arrows, a figure pacing across it, a second figure lying where it fell, and a banner strung up over it. S writes the lot to a file and L reads it back, so a restore comes back mid-drive and mid-stride. The terrain floor and the cloth are named rather than held, and the figure's skin stays the sketch's own asset. `snapshot()`, `assetName`, `restore(_:resolving:)`, `world.vehicles`, `world.characters`, `world.ragdolls`, `world.softBodies`. |

### Camera

Driving the view: interactive control, cinematic moves, and inspection snaps.

| Sketch | What it shows |
| --- | --- |
| [CameraControl](Camera/CameraControl/) | Interactive camera control: `cameraControl()` lets the viewer drag to orbit a still life, scroll to dolly, and right-drag (or shift/option-drag) to pan, damped so it settles and a flick keeps a little spin. |
| [CameraMoves](Camera/CameraMoves/) | Cinematic camera moves over one still life: a `.turntable` spin, a `.sway`, a `.pushIn`/`.pullOut` dolly, a `.tilt`, the `.orbitAndRise` beauty pass, a `.reveal`, and a `.handheld` drift, each one `cameraMove(_:)` call composing over the pose the last one left. Click or press a key to step. |
| [SceneViews](Camera/SceneViews/) | The host's **Camera** menu snapping an auto-orbiting scene to canonical inspection views (Front/Back/Left/Right/Top/Bottom/Isometric and Reset, ⌘0–⌘7), the way a modeling tool's numpad does. |

### Materials

What surfaces are made of, from stylized finishes to physically-based metal.

| Sketch | What it shows |
| --- | --- |
| [Materials](Materials/Materials/) | The material library: one orbiting sphere grid wearing each built-in `Material` (`.iridescent`/`.soapBubble`/`.velvet`/`.jade`/`.toon`/`.gooch`/…), the view-angle finishes shifting as it turns. |
| [PhysicalMaterials](Materials/PhysicalMaterials/) | The physically-based finish as a metallic × roughness sweep: `Material.physicallyBased` shades one sphere grid from tight mirror highlights to matte, dielectric to metal. |
| [Matcap](Materials/Matcap/) | Matcaps: a whole surface-and-lighting look baked into one sphere texture, sampled by the view normal (`matcap(_:)`), for chrome, clay, wax, or a cel look with no scene lights at all. |

### Lighting

Light kinds, curated rigs, and cast shadows.

| Sketch | What it shows |
| --- | --- |
| [Lighting](Lighting/Lighting/) | The three light kinds shading solids by hand (a fixed directional key, an orbiting point bulb, a sweeping spot), with a rising-shininess sphere row. |
| [LightingPresets](Lighting/LightingPresets/) | One call relights the whole scene: the curated `LightingPreset`s (`.standard`/`.threePoint`/`.goldenHour`/`.noir`/`.studio`/`.moonlight`) cycling over one still life, plus a sketch-built custom rig. Click or press a key to step. |
| [Shadows](Lighting/Shadows/) | Directional cast shadows: solids drop shadows onto a floor and onto one another via `castShadows()`. |
| [SpotShadow](Lighting/SpotShadow/) | A spot light as the shadow caster: a perspective shadow map fit to its cone, so the solids inside the beam drop crisp shadows. |
| [PointShadow](Lighting/PointShadow/) | An omnidirectional point-light caster: a bulb at the center throws shadows in every direction (ray-traced on an RT GPU, a depth cube elsewhere). |

### Environments

Image-based lighting: HDRIs bundled, downloaded, loaded from a URL, or synthesized.

| Sketch | What it shows |
| --- | --- |
| [ImageBasedLighting](Environments/ImageBasedLighting/) | `environment(_:)` lights the scene from an HDRI, so physically-based metals fill in with real reflections instead of reading near-black; the environment also doubles as the skybox backdrop. |
| [EnvironmentGallery](Environments/EnvironmentGallery/) | The eight bundled CC0 HDRI environments (studio, courtyard, forest, interior, city, sunrise, sunset, night) stepped through over one PBR still life, auto-advancing (or arrow keys to step). |
| [HighResEnvironment](Environments/HighResEnvironment/) | `highRes(_:)` fetches a sharper 2K/4K/8K backdrop for a bundled environment on first run (the 1K shows meanwhile), lighting unchanged. |
| [EnvironmentURL](Environments/EnvironmentURL/) | An environment loaded from any equirectangular HDRI URL (`Environment.hdri(downloadURL:)`), downloaded once and cached. |
| [ProceduralSky](Environments/ProceduralSky/) | A zero-asset daylight dome: `environment(.sky(...))` synthesizes a physically-based sky at runtime and sweeps its sun through a full day. |

### Effects

Scene-wide realism passes over the 3D frame.

| Sketch | What it shows |
| --- | --- |
| [SceneDefocus](Effects/SceneDefocus/) | Depth of field on a 3D scene defocused by its *own* depth buffer: a row of orbs drawn into a render target, then `scene.combined(with: scene.depth, .defocus(...))` racks focus through them. Drag to rack by hand. |
| [AmbientOcclusion](Effects/AmbientOcclusion/) | Screen-space ambient occlusion from the scene's own depth and normals: the soft darkening in crevices and contact gaps that grounds a brightly lit scene. |
| [ScreenSpaceReflections](Effects/ScreenSpaceReflections/) | Surfaces reflecting the scene around them: SSR traced over the frame, on a ring of reflective spheres in different metal finishes. |
| [RayTracedReflections](Effects/RayTracedReflections/) | Metals mirroring the *actual* scene (off-screen geometry included, none of SSR's streaks) by tracing reflection rays into the image-based lighting. Needs a ray-tracing GPU and an environment. |

### Raymarching

The 3D SDF combinators: fields that merge, sphere-traced beside the meshes.

| Sketch | What it shows |
| --- | --- |
| [RaymarchedSDF](Raymarching/RaymarchedSDF/) | The 3D SDF combinators sphere-traced as one surface: spheres melt by smooth-union (colors blending through the seam), one orbits, and a bite is carved out by subtraction. |
| [RaymarchedShapes](Raymarching/RaymarchedShapes/) | The raymarched primitive catalog beyond the first four (rounded box, cylinder, cone, octahedron, ellipsoid), each a field traced into the shared depth buffer. |
| [RaymarchedSculpt](Raymarching/RaymarchedSculpt/) | The scoped block form: inside `smoothUnion(k:) { … }` bare mesh calls (`drawSphere`, `drawCapsule`, `drawCone`, …) are captured as fields and melt into one traced surface. |
| [RaymarchedDomain](Raymarching/RaymarchedDomain/) | Domain operators: `repeated(spacing:count:)` tiles a unit cell into a finite lattice, `mirrored(x:y:z:)` folds one built lobe symmetric; the whole thing stays one surface. |
| [RaymarchedRadial](Raymarching/RaymarchedRadial/) | Polar repetition: `repeatedRadially` folds one wedge into an evenly spaced rosette around an axis, with no per-copy draw cost. |
| [RaymarchedPlane](Raymarching/RaymarchedPlane/) | The infinite plane leaf: an unbounded ground merged into the field, marched to the far plane, catching the shapes' soft shadows. |
| [RaymarchedStretch](Raymarching/RaymarchedStretch/) | Per-axis sizing: `stretched` (exact elongation, a sphere becomes a capsule) beside `scaled(x:y:z:)` (true non-uniform, conservatively marched). |
| [RaymarchedGradient](Raymarching/RaymarchedGradient/) | Gradient paint on a merged field: a gradient `fill` paints the whole sphere-traced surface, sampled by each hit's projected screen position. |
| [RaymarchedEnvironment](Raymarching/RaymarchedEnvironment/) | Raymarched fields lit by an environment: the same image-based lighting (and traced reflections) the meshes get. |
| [RaymarchedShadow](Raymarching/RaymarchedShadow/) | Field self-shadowing under `castShadows()`: a soft penumbra march toward the light, evaluated as part of the surface shading. |
| [RaymarchedCastShadow](Raymarching/RaymarchedCastShadow/) | A field casting onto meshes: the field renders into the directional/spot shadow map, so meshes receive its shadow like any other caster's. |
| [RaymarchedReceiveShadow](Raymarching/RaymarchedReceiveShadow/) | A field *receiving* a mesh's cast shadow: the traced surface samples the shadow map where the mesh's shadow lands. |
| [RaymarchedPointCast](Raymarching/RaymarchedPointCast/) | Field→mesh shadows under a *point* light: with no 2D map to render into, the lit mesh fragments march the field inline toward the light. |
| [RaymarchedPointReceive](Raymarching/RaymarchedPointReceive/) | Mesh→field shadows under a *point* light: the field samples the shadow cube (or, on an RT GPU, the acceleration structure) at its hit. |

### Depth

Depth feeds and depth-aware compositing: cameras, recordings, and metric space.

| Sketch | What it shows |
| --- | --- |
| [DepthCloud](Depth/DepthCloud/) | A live 3D point cloud from one webcam: a neural depth model lifts each pixel into space, colored by the camera image, orbiting. Needs `Scripts/fetch-models.sh`. |
| [Record3DCloud](Depth/Record3DCloud/) | An iPhone RGBD recording orbited as a point cloud: a `.r3d` clip from the Record3D app, unprojected with its true camera intrinsics. Drop a recording in `~/Downloads`. Needs `import OllinRecord3D`. |
| [Record3DLiveCloud](Depth/Record3DLiveCloud/) | A **live** RGBD cloud streamed from a tethered iPhone: open Record3D, turn on USB streaming, and the phone's depth camera becomes a real-time point cloud on the Mac. Needs `import OllinRecord3D`. |
| [DepthCompositing](Depth/DepthCompositing/) | Depth-aware compositing, a 2D card standing between two point-cloud orbs: the near orb draws over the card, the far one is hidden behind it, with per-orb billboard pins. |
| [DepthOcclusion](Depth/DepthOcclusion/) | 2D discs hung at a draggable depth plane over a live webcam depth feed (a neural model), occluded by whoever stands nearer. Needs `import OllinVision` + `Scripts/fetch-models.sh`. |
| [MetricDepthScene](Depth/MetricDepthScene/) | 2D markers floating at **true metric depths** (meters) inside a live LiDAR feed: a `Camera3D.fromIntrinsics` makes the feed metric, so a marker at a real distance is blocked when you step closer than it. Needs `import OllinRecord3D`. |
| [DepthLiftedPose](Depth/DepthLiftedPose/) | A 2D body pose lifted into metric 3D through a depth frame: the tethered phone's depth back-projects each tracked joint, and the skeleton is drawn in space over the person's own cloud. Needs `import OllinVision`/`OllinRecord3D`. |

### Phone

The **Ollin Capture** iPhone app streaming ARKit perception over USB.

| Sketch | What it shows |
| --- | --- |
| [PhoneBodyPose](Phone/PhoneBodyPose/) | A live 3D body skeleton streamed from **Ollin Capture** on a tethered iPhone: ARKit body pose over USB, orbited as a stick figure. Needs `import OllinPhone`. |
| [PhoneFace](Phone/PhoneFace/) | Ollin Capture's live face mesh and 52 expression blendshapes, orbited as a point cloud with expression bars (tap **Face** on the phone). Needs `import OllinPhone`. |
| [PhoneDepthCloud](Phone/PhoneDepthCloud/) | A **live** rear-LiDAR RGBD cloud from Ollin Capture (tap **World**): Ollin's own-app world-facing depth feed, unprojected with the stream's true intrinsics and orbited. Needs `import OllinPhone`. |
| [PhoneWorldScan](Phone/PhoneWorldScan/) | Sweep the phone (tap **World**) and each depth frame is placed by its camera pose into one fused `WorldCloud` of the room; **R** to reset. Needs `import OllinPhone`. |
| [PhoneSegmentation](Phone/PhoneSegmentation/) | Ollin Capture's on-device person matte (tap **Segment**): the cutout lifted onto a live gradient backdrop, the tinted matte as a drop shadow. Needs `import OllinPhone`. |

See [`Docs/3D/3D.md`](../../Docs/3D/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/3D/Record3D.md`](../../Docs/3D/Record3D.md); the Ollin Capture stream is documented in [`Docs/3D/Phone.md`](../../Docs/3D/Phone.md).
