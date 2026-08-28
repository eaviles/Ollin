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
| [ShadowArt](Geometry/ShadowArt/) | A solid carved so that it throws a ring from the front and a cross from the side, with what it really throws drawn beside what was asked for (`shadowArt`, `shadow(from:)`). |
| [ShapeFactory](Geometry/ShapeFactory/) | The parametric/profile mesh set (Möbius, Klein, superellipsoid, supershape, extrude, lathe) morphing on `time`. |
| [Ocean](Geometry/Ocean/) | A sea built from its own wave spectrum: one inverse Fourier transform on the GPU makes the surface, drawn as water with no geometry anywhere (`oceanField`, `drawOcean`). |
| [LoadedMesh](Geometry/LoadedMesh/) | A mesh loaded from a file (`.obj`/`.usdz`/`.gltf`/…); drop one in with `OLLIN_MESH=<path>` (or use the bundled crystal), recentered, scaled to fit, and lit. |
| [TexturedMesh](Geometry/TexturedMesh/) | A UV-gridded globe textured with an image over a base-color-tinted floor, both lit. |
| [Wireframe](Geometry/Wireframe/) | Orbiting solids drawn as their triangle edges (`wireframe()`), faces see-through. |
| [SurfaceScatter](Geometry/SurfaceScatter/) | Trees standing on a globe: `surfacePoints` scatters over the skin by area, `alignment` stands each one up, and the `spread` knob compares an even covering, a plain draw, and the vertex-list shortcut. |
| [Terrain](Geometry/Terrain/) | Generated terrain, weathered: a heightfield grown by diamond-square subdivision, then eroded by tens of thousands of simulated raindrops carving ravines and building sediment fans. |
| [Metaballs](Geometry/Metaballs/) | Soft spheres that reach for each other and fuse: every ball adds a bump to one shared field, and `isosurface` walks it into a mesh. |
| [MeshGrowth](Geometry/MeshGrowth/) | A surface that makes more of itself than it has room for: vertices pushed apart, faster where the surface is already crowded, until it buckles. |
| [SubdivisionSurfaces](Geometry/SubdivisionSurfaces/) | A chunky low-poly cage refined into a smooth solid (`mesh.subdivided(_:levels:)`). |
| [SurfaceFromPoints](Geometry/SurfaceFromPoints/) | From points back to a surface, two ways: a knot sampled into a bare cloud and reconstructed from it. |
| [HopfFibration](Geometry/HopfFibration/) | A sphere's worth of circles, no two of which meet and every two of which are linked exactly once. |
| [LoadedScene](Geometry/LoadedScene/) | A whole authored scene drawn in place, opening on its own camera and lights. |
| [SceneExplorer](Geometry/SceneExplorer/) | A read-only lens on a scene file: point it at a glTF or USD scene and look around it, part by part. |
| [AnimatedScene](Geometry/AnimatedScene/) | A scene file's authored animation played back: keyframe tracks posing named nodes. |
| [SkinnedScene](Geometry/SkinnedScene/) | A scene file's deforming animation: skins that bend meshes and morph targets that blend them. |
| [USDScene](Geometry/USDScene/) | A USD scene loaded with its structure kept, drawn under its own authored camera and lights. |
| [USDAnimatedScene](Geometry/USDAnimatedScene/) | A USD file's authored transform animation played on the sketch clock. |
| [USDSkinnedScene](Geometry/USDSkinnedScene/) | A USD file's skeletal animation and blend shapes, read by Ollin's own parser. |
| [Fabrication](Geometry/Fabrication/) | A generated shape written out as something a 3D printer can build, with a report on whether it can be. |
| [SpatialExport](Geometry/SpatialExport/) | A sketch that leaves as a model instead of a picture: ordinary 3D written out as USDZ. |
| [SpatialVideo](Geometry/SpatialVideo/) | A sketch that leaves as something you can look into: a scene built for depth rather than for a flat frame. |

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
| [Rigging](Physics/Rigging/) | Three lines hanging from a gantry, all built from a polyline: a limp rope, a chain whose links interlock because every other one is rolled a quarter turn about the rope's own axis, and a vine stiff enough to hold a curve with leaves carried along it. Drag any of them; space stills the wind. `addRope`, `Rope3D.segments`, `withSegment`, `bend`. |
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
| [Explorer](Materials/Explorer/) | The material explorer: every finish in the hand, on one shape, with its knobs. |
| [SurfaceMaps](Materials/SurfaceMaps/) | The rest of the surface-map set: metallic-roughness, occlusion, and emissive maps varying a finish per pixel. |
| [NormalMaps](Materials/NormalMaps/) | Per-pixel surface relief without per-pixel geometry. |
| [Detail](Materials/Detail/) | Detail maps: texture that survives a close look. |
| [Parallax](Materials/Parallax/) | One height map read two ways: parallax occlusion, and real displacement. |
| [Triplanar](Materials/Triplanar/) | Texture for meshes that have no uvs at all, projected from three directions. |
| [Decals](Materials/Decals/) | Pictures stamped onto the scene, projected rather than mapped. |
| [Glass](Materials/Glass/) | Physically-based transmission and refraction. |
| [SoapBubble](Materials/SoapBubble/) | Thin glass with a living, swirling film. |
| [SeeThrough](Materials/SeeThrough/) | The scene showing through glass, with no ray tracing. |
| [CoatAndCloth](Materials/CoatAndCloth/) | Clearcoat and sheen, the two layered finishes on the physically-based material. |
| [Subsurface](Materials/Subsurface/) | Light that travels under the surface before it comes back out. |
| [BrushedMetal](Materials/BrushedMetal/) | Anisotropic specular: brushed, turned, and satin finishes whose highlight is a streak instead of a dot. |
| [ThinFilm](Materials/ThinFilm/) | Thin-film interference: color made by a film's thickness rather than by pigment. |

### Lighting

Light kinds, curated rigs, and cast shadows.

| Sketch | What it shows |
| --- | --- |
| [Lighting](Lighting/Lighting/) | The three light kinds shading solids by hand (a fixed directional key, an orbiting point bulb, a sweeping spot), with a rising-shininess sphere row. |
| [LightingPresets](Lighting/LightingPresets/) | One call relights the whole scene: the curated `LightingPreset`s (`.standard`/`.threePoint`/`.goldenHour`/`.noir`/`.studio`/`.moonlight`) cycling over one still life, plus a sketch-built custom rig. Click or press a key to step. |
| [Shadows](Lighting/Shadows/) | Directional cast shadows: solids drop shadows onto a floor and onto one another via `castShadows()`. |
| [SpotShadow](Lighting/SpotShadow/) | A spot light as the shadow caster: a perspective shadow map fit to its cone, so the solids inside the beam drop crisp shadows. |
| [PointShadow](Lighting/PointShadow/) | An omnidirectional point-light caster: a bulb at the center throws shadows in every direction (ray-traced on an RT GPU, a depth cube elsewhere). |
| [TwoCasters](Lighting/TwoCasters/) | A warm key and a cool spot, each throwing its own shadow. |
| [PointCasters](Lighting/PointCasters/) | A key light and two lamps in the room, all three throwing shadows. |
| [AreaLights](Lighting/AreaLights/) | Rect, disk, and tube sources shading a small studio set. |
| [AreaShadows](Lighting/AreaShadows/) | A softbox panel casting shadows whose softness is its size. |
| [LightShaping](Lighting/LightShaping/) | Photometric profiles and a projected cookie, the two ways a real fixture shapes its beam. |
| [VolumetricLight](Lighting/VolumetricLight/) | Beams, gobos, and shafts you can see in the air. |
| [Caustics](Lighting/Caustics/) | The light a glass or a polished metal focuses onto what is around it. |
| [GlobalIllumination](Lighting/GlobalIllumination/) | Light that bounces, so a red wall reddens what stands beside it. |

### Environments

Image-based lighting: HDRIs bundled, downloaded, loaded from a URL, or synthesized.

| Sketch | What it shows |
| --- | --- |
| [ImageBasedLighting](Environments/ImageBasedLighting/) | `environment(_:)` lights the scene from an HDRI, so physically-based metals fill in with real reflections instead of reading near-black; the environment also doubles as the skybox backdrop. |
| [EnvironmentGallery](Environments/EnvironmentGallery/) | The eight bundled CC0 HDRI environments (studio, courtyard, forest, interior, city, sunrise, sunset, night) stepped through over one PBR still life, auto-advancing (or arrow keys to step). |
| [HighResEnvironment](Environments/HighResEnvironment/) | `highRes(_:)` fetches a sharper 2K/4K/8K backdrop for a bundled environment on first run (the 1K shows meanwhile), lighting unchanged. |
| [EnvironmentURL](Environments/EnvironmentURL/) | An environment loaded from any equirectangular HDRI URL (`Environment.hdri(downloadURL:)`), downloaded once and cached. |
| [ProceduralSky](Environments/ProceduralSky/) | A zero-asset daylight dome: `environment(.sky(...))` synthesizes a physically-based sky at runtime and sweeps its sun through a full day. |
| [Cloudscape](Environments/Cloudscape/) | A raymarched cloudscape over the procedural sky. |
| [LiveEnvironment](Environments/LiveEnvironment/) | A live camera environment: the room the sketch is in lights the scene. |

### Effects

Scene-wide realism passes over the 3D frame.

| Sketch | What it shows |
| --- | --- |
| [SceneDefocus](Effects/SceneDefocus/) | Depth of field on a 3D scene defocused by its *own* depth buffer: a row of orbs drawn into a render target, then `scene.combined(with: scene.depth, .defocus(...))` racks focus through them. Drag to rack by hand. |
| [AmbientOcclusion](Effects/AmbientOcclusion/) | Screen-space ambient occlusion from the scene's own depth and normals: the soft darkening in crevices and contact gaps that grounds a brightly lit scene. |
| [ScreenSpaceReflections](Effects/ScreenSpaceReflections/) | Surfaces reflecting the scene around them: SSR traced over the frame, on a ring of reflective spheres in different metal finishes. |
| [RayTracedReflections](Effects/RayTracedReflections/) | Metals mirroring the *actual* scene (off-screen geometry included, none of SSR's streaks) by tracing reflection rays into the image-based lighting. Needs a ray-tracing GPU and an environment. |
| [ContactShadows](Effects/ContactShadows/) | The fine dark seam that seats an object on the surface it stands on. |
| [GlossyReflections](Effects/GlossyReflections/) | A satin surface shows the room rather than the sky. |
| [MirrorTunnel](Effects/MirrorTunnel/) | How far a reflection is allowed to travel (`reflectionBounces`). |
| [Fog](Effects/Fog/) | Distance and height atmosphere over a colonnade. |
| [AerialPerspective](Effects/AerialPerspective/) | The depth cue that sells scale outdoors: air itself, between you and the far hill. |
| [MotionBlur](Effects/MotionBlur/) | The streak a real camera's open shutter leaves on something moving. |
| [TemporalAA](Effects/TemporalAA/) | Edges refined past MSAA by accumulating jittered frames. |
| [Upscaling](Effects/Upscaling/) | Render small, reconstruct full size, keep the frame rate. |
| [FrameInterpolation](Effects/FrameInterpolation/) | Draw half as often and let the display keep its rate, with a made frame in between. |
| [LensFlare](Effects/LensFlare/) | The light a camera adds to a picture all by itself. |
| [PathTraced](Effects/PathTraced/) | Tune the scene live, then render the same frame offline with a path tracer. |

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
| [RaymarchedClay](Raymarching/RaymarchedClay/) | The sculpt block: combine mode and melt amount held as state, so a form reads top to bottom like working clay. |
| [RaymarchedJoinery](Raymarching/RaymarchedJoinery/) | Machined joints and hardware: chamfered and stepped unions, a hanging chain, a capped-torus hook. |
| [RaymarchedDetailing](Raymarching/RaymarchedDetailing/) | The detailing ops: fluted seams, engraved rings, grooved bands, beading, and a pipe bead left hanging where two bodies crossed. |
| [RaymarchedDistort](Raymarching/RaymarchedDistort/) | The sculpting distortions: twisted, bent, displaced, and roughened, one plinth each. |

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
| [DriftCorrectedScan](Depth/DriftCorrectedScan/) | The same made-up room swept twice side by side: once trusting the reported camera pose, once lining each frame up against the scan with `add(_:correcting:)`. Nothing to plug in; **R** runs the sweep again. |
| [ClosedLoopScan](Depth/ClosedLoopScan/) | A made-up hall walked all the way around and back, scanned twice side by side: lining each frame up on the left, and `ScanGraph` also recognizing the place it started on the right. The true walls are drawn over both. Nothing to plug in; **R** walks it again. |

### Phone

The **Ollin Capture** iPhone app streaming ARKit perception over USB.

| Sketch | What it shows |
| --- | --- |
| [PhoneBodyPose](Phone/PhoneBodyPose/) | A live 3D body skeleton streamed from **Ollin Capture** on a tethered iPhone: ARKit body pose over USB, orbited as a stick figure. Needs `import OllinPhone`. |
| [PhoneBodyFigure](Phone/PhoneBodyFigure/) | A solid mannequin posed by that same stream's richer half: joint orientations turn its parts, the world anchor stands it where the person stands, the scale sizes it, tracked flags tint it. Needs `import OllinPhone`. |
| [PhoneCostume](Phone/PhoneCostume/) | A costume worn by the live skeleton, inspired by Universal Everything's *Super You*: ribbon trails that only exist in motion, or plumage whose twist follows the joint rotations. Needs `import OllinPhone`. |
| [PhoneFace](Phone/PhoneFace/) | Ollin Capture's live face mesh and 52 expression blendshapes, orbited as a point cloud with expression bars (tap **Face** on the phone). Needs `import OllinPhone`. |
| [PhoneGaze](Phone/PhoneGaze/) | The eyes and the gaze from that same Face mode: eyeballs standing at the streamed eye poses (blinking with their blendshapes), beams converging on the look-at point, a bead where they meet. Needs `import OllinPhone`. |
| [PhoneDepthCloud](Phone/PhoneDepthCloud/) | A **live** rear-LiDAR RGBD cloud from Ollin Capture (tap **World**): Ollin's own-app world-facing depth feed, unprojected with the stream's true intrinsics and orbited. Needs `import OllinPhone`. |
| [PhoneWorldScan](Phone/PhoneWorldScan/) | Sweep the phone (tap **World**) and each depth frame is lined up against the scan so far and fused into one `WorldCloud` of the room; **C** turns the drift correction off, **R** resets. Needs `import OllinPhone`. |
| [PhoneSegmentation](Phone/PhoneSegmentation/) | Ollin Capture's on-device person matte (tap **Segment**): the cutout lifted onto a live gradient backdrop, the tinted matte as a drop shadow. Needs `import OllinPhone`. |
| [PhoneRoomMesh](Phone/PhoneRoomMesh/) | Walk the phone around (tap **Room**) and the room arrives as a solid surface, painted by what each triangle is; **space**, **F**, **R**. Needs `import OllinPhone`. |
| [PhoneRoomPlanes](Phone/PhoneRoomPlanes/) | The flat surfaces in that same room, each as its real outline, with a ball standing on the biggest one and the scene lit by the room's own light; **space**, **F**, **M**, **L**, **R**. Needs no LiDAR. Needs `import OllinPhone`. |
| [PhoneHands](Phone/PhoneHands/) | The hands the phone sees (tap **Hands**, up to 4) as solid little skeletons standing in the room, lifted to metric 3D through the LiDAR depth; a pinch closes into a bright bead, and without LiDAR the same stream draws as a flat overlay. Needs `import OllinPhone`. |
| [PhoneWorldText](Phone/PhoneWorldText/) | The words the phone can read (tap **Text**), placed where they hang in the room. Each line is wire-frame type on a framed panel, lifted through the LiDAR depth. Without LiDAR it draws as a flat overlay. Needs `import OllinPhone`. |

See [`Docs/3D/3D.md`](../../Docs/3D/3D.md) for the 3D guide. Record3D recordings have their own guide in [`Docs/3D/Record3D.md`](../../Docs/3D/Record3D.md); the Ollin Capture stream is documented in [`Docs/3D/Phone.md`](../../Docs/3D/Phone.md).
