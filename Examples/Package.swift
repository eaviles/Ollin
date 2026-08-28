// swift-tools-version: 6.0
import PackageDescription

// The example sketches, as a package of their own.
//
// Run one from this directory:
//
//     cd Examples
//     swift run Example-Basic-HelloCircle
//
// or from anywhere with `--package-path`:
//
//     swift run --package-path Examples Example-Basic-HelloCircle
//
// They live here rather than in the root manifest because SwiftPM builds every
// target of the root package, with no way to scope a build to the tests and
// their dependencies (`--target` and `--product` are both refused alongside
// `--build-tests`). With these 350 executables in the root package, running the
// tests also builds 350 sketch binaries that no test target depends on: a cold
// `swift test` measures 7m23s and 13 GB that way, against 1m30s and 1.7 GB with
// them declared here instead.
//
// Splitting them costs nothing at the seams, because nothing reaches an example
// through its *target*. The gallery, OllinLive, OllinLiveCoding and the figure
// runner all compile a sketch from its source file, finding the modules from
// their own binary's location and resolving `Bundle.module` to the sketch's own
// folder. These targets serve exactly two callers: `swift run Example-X`, and
// the build that checks every sketch still compiles against the current API.

// The satellite libraries a sketch can link beside the core. Typed (not raw
// strings) so a call site can't misspell one.
enum Satellite: String, CaseIterable {
    case audio = "OllinAudio"
    case osc = "OllinOSC"
    case dmx = "OllinDMX"
    case laser = "OllinLaser"
    case midi = "OllinMIDI"
    case serial = "OllinSerial"
    case remote = "OllinRemote"
    case room = "OllinRoom"
    case physics = "OllinPhysics"
    case vision = "OllinVision"
    case video = "OllinVideo"
    case syphon = "OllinSyphon"
    case camera = "OllinCamera"
    case record3D = "OllinRecord3D"
    case phone = "OllinPhone"
    case screen = "OllinScreen"
    case controller = "OllinController"
    case haptics = "OllinHaptics"
    case bluetooth = "OllinBluetooth"

    var dependency: Target.Dependency { .product(name: rawValue, package: "Ollin") }
}

// One example sketch = one line in the targets list. The target name is derived
// from the folder path ("Basic/HelloCircle" -> Example-Basic-HelloCircle), so
// name and path can't drift apart; satellite libraries ride the second argument
// and co-located assets `resources:`.
func example(
    _ folder: String,
    _ satellites: [Satellite] = [],
    resources: [Resource]? = nil,
    dependencies extra: [Target.Dependency] = []
) -> Target {
    .executableTarget(
        name: "Example-" + folder.split(separator: "/").joined(separator: "-"),
        dependencies: [.product(name: "Ollin", package: "Ollin")]
            + satellites.map(\.dependency) + extra,
        path: folder,
        resources: resources
    )
}

let package = Package(
    name: "Examples",
    platforms: [
        .macOS("26.0")
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        example("Basic/HelloCircle"),
        example("Basic/NormalizedCoordinates"),
        example("Basic/Guides"),
        example("Basic/Describing"),
        example("Export/Capture"),
        example("Export/Record", [.audio]),
        example("Export/VectorExport"),
        example("Export/Hatching"),
        example("Export/Toolpath"),
        example("Installation/Unattended"),
        example("Installation/Resuming"),
        example("Installation/Watched"),
        example("Installation/Hours"),
        example("Installation/Fitted"),
        example("Installation/ManyWindows"),
        example("Installation/ManyDisplays"),
        example("Rendering/Blending"),
        example("Effects/Bloom"),
        example("Shapes/Combinators"),
        example("Shapes/CombinatorsGradient"),
        example("Shapes/CombinatorsStretch"),
        example("Shapes/CombinatorsJoinery"),
        example("Shapes/CombinatorsDetailing"),
        example("3D/Raymarching/RaymarchedReceiveShadow"),
        example("3D/Raymarching/RaymarchedPointCast"),
        example("3D/Raymarching/RaymarchedPointReceive"),
        example("3D/Raymarching/RaymarchedStretch"),
        example("3D/Raymarching/RaymarchedEnvironment"),
        example("Effects/Feedback"),
        example("Effects/Fourier"),
        example("Effects/Compose"),
        example("Effects/Aside"),
        example("Effects/Defocus"),
        example("Effects/Bokeh"),
        example("Rendering/Accumulation"),
        example("Effects/ColorFilters"),
        example("Effects/BlurFilters"),
        example("Effects/StylizeFilters"),
        example("Effects/Antialias"),
        example("Effects/RetroFilters"),
        example("Effects/Relight"),
        example("Effects/Glitter"),
        example("Effects/SoapFilm"),
        example("Effects/MeshGradient"),
        example("Effects/DesignPatterns"),
        example("Effects/PatternFields"),
        example("Effects/DesignFilters"),
        example("Effects/Distortion"),
        example("Effects/DistanceField"),
        example("Effects/Light"),
        example("Effects/Dispersion"),
        example("Simulation/GrayScott"),
        example("Simulation/GameOfLife"),
        example("Simulation/BriansBrain"),
        example("Simulation/CyclicAutomaton"),
        example("Simulation/Excitable"),
        example("Simulation/Hodgepodge"),
        example("Simulation/Lenia"),
        example("Simulation/MultiScaleTuring"),
        example("Simulation/Sandpile"),
        example("Simulation/Fluid"),
        example("Simulation/SelfWarp"),
        example("Simulation/Ripples"),
        example("Simulation/Watercolor"),
        example("Simulation/Attractor"),
        example("Simulation/Breeding"),
        example("Simulation/Evolution"),
        example("Simulation/Swarm"),
        example("Simulation/ParticleLife"),
        example("Simulation/ParticleLenia"),
        example("Simulation/SwarmChemistry"),
        example("Simulation/PrimordialParticles"),
        example("Simulation/Physarum"),
        example("Simulation/ParticleFluid"),
        example("Simulation/SoftBodies"),
        example("Effects/Fractals"),
        example("Effects/OrbitTraps"),
        example("Effects/Droste"),
        example("Effects/DomainColoring"),
        example("Effects/DiffusionCurves"),
        example("Effects/SeamlessClone"),
        example("Effects/SummedArea"),
        example("Effects/Patterns"),
        example("Effects/Cellular"),
        example("Shaders/HelloShader"),
        example("Shaders/ShaderFilter"),
        example("Shaders/ShaderBlend"),
        example("Shaders/ShaderFile", resources: [.copy("ripple.metal")]),
        example("Shaders/VisualSynth"),
        example("Shaders/DomainWarp"),
        example("Rendering/ToneMapping"),
        example("Rendering/ColorOutput"),
        example("Rendering/DepthOfField"),
        example("Rendering/RetainedBatch"),
        example("Rendering/ViewBoxes"),
        example("Rendering/InstancedMesh"),
        example("Rendering/MeshField"),
        example("Rendering/Grassland"),
        example("Compute/CurlField"),
        // The kernels live in their own .metal file (highlighted, editor-checked);
        // .copy ships the source for Ollin's runtime compiler to read + splice.
        example("Compute/ReactionDiffusion", resources: [.copy("Kernels.metal")]),
        // Drives the raw SpatialHash, so it constructs OllinParticle buffers directly
        // and needs the shared-struct module (which the typed sims hide).
        example("Compute/NeighborSearch", dependencies: [.product(name: "COllinShaders", package: "Ollin")]),
        example("3D/Geometry/PointCloud"),
        example("3D/Geometry/StrangeAttractor"),
        example("3D/Geometry/Transforms"),
        example("3D/Geometry/Solids"),
        example("3D/Geometry/HopfFibration"),
        example("3D/Geometry/Ocean"),
        // 3D rigid bodies (Jolt-backed World3D): a crate pyramid under cannon
        // fire, a mixed-solid pile you can drag, a wrecking-ball chain, and a
        // motor-driven windmill with spring-shut gates.
        example("3D/Physics/Stack", [.physics]),
        example("3D/Physics/Tumble", [.physics]),
        example("3D/Physics/Chain", [.physics]),
        example("3D/Physics/Windmill", [.physics]),
        example("3D/Physics/Raft", [.physics]),
        example("3D/Physics/Rigging", [.physics]),
        example("3D/Physics/Rockslide", [.physics]),
        example("3D/Physics/Stroll", [.physics]),
        example("3D/Physics/Trigger", [.physics]),
        example("3D/Physics/Joyride", [.physics]),
        example("3D/Physics/Crawler", [.physics]),
        example("3D/Physics/Ragdoll", [.physics], resources: [.copy("figure.gltf")]),
        example("3D/Physics/Cape", [.physics], resources: [.copy("figure.gltf")]),
        example("3D/Physics/Drape", [.physics]),
        example("3D/Physics/Flotsam", [.physics]),
        example("3D/Physics/Sightlines", [.physics]),
        example("3D/Physics/Sieve", [.physics]),
        example("3D/Physics/Bagatelle", [.physics]),
        example("3D/Physics/Contraption", [.physics]),
        example("3D/Physics/Cairn", [.physics]),
        example("3D/Physics/Yard", [.physics], resources: [.copy("figure.gltf")]),
        example("3D/Physics/Imported", [.physics], resources: [.copy("yard.usda")]),
        example("3D/Raymarching/RaymarchedSDF"),
        example("3D/Raymarching/RaymarchedShapes"),
        example("3D/Raymarching/RaymarchedSculpt"),
        example("3D/Raymarching/RaymarchedJoinery"),
        example("3D/Raymarching/RaymarchedDistort"),
        example("3D/Raymarching/RaymarchedDetailing"),
        example("3D/Raymarching/RaymarchedClay"),
        example("3D/Raymarching/RaymarchedDomain"),
        example("3D/Raymarching/RaymarchedRadial"),
        example("3D/Raymarching/RaymarchedPlane"),
        example("3D/Raymarching/RaymarchedCastShadow"),
        example("3D/Raymarching/RaymarchedGradient"),
        example("3D/Raymarching/RaymarchedShadow"),
        example("3D/Effects/SceneDefocus"),
        example("3D/Effects/AmbientOcclusion"),
        example("3D/Effects/ScreenSpaceReflections"),
        example("3D/Effects/Fog"),
        example("3D/Effects/AerialPerspective"),
        example("3D/Effects/ContactShadows"),
        example("3D/Effects/MotionBlur"),
        example("3D/Effects/LensFlare"),
        example("3D/Effects/TemporalAA"),
        example("3D/Effects/Upscaling"),
        example("3D/Effects/RayTracedReflections"),
        example("3D/Effects/MirrorTunnel"),
        example("3D/Effects/GlossyReflections"),
        example("3D/Effects/PathTraced"),
        example("3D/Geometry/TexturedMesh"),
        example("3D/Geometry/Wireframe"),
        example("3D/Geometry/LoadedMesh", resources: [.copy("model.gltf"), .copy("model.obj")]),
        example("3D/Geometry/LoadedScene", resources: [.copy("scene.gltf")]),
        example("3D/Geometry/SceneExplorer", resources: [.copy("scene.gltf"), .copy("stage.usda")]),
        example("3D/Geometry/AnimatedScene", resources: [.copy("scene.gltf")]),
        example("3D/Geometry/SkinnedScene", resources: [.copy("scene.gltf")]),
        example("3D/Geometry/USDScene", resources: [.copy("stage.usda")]),
        example("3D/Geometry/USDAnimatedScene", resources: [.copy("stage.usda")]),
        example("3D/Geometry/USDSkinnedScene", resources: [.copy("stage.usda")]),
        example("3D/Geometry/ShapeFactory"),
        example("3D/Geometry/Terrain"),
        example("3D/Geometry/Metaballs"),
        example("3D/Geometry/ShadowArt"),
        example("3D/Geometry/SubdivisionSurfaces"),
        example("3D/Geometry/MeshGrowth"),
        example("3D/Geometry/SurfaceFromPoints"),
        example("3D/Geometry/SurfaceScatter"),
        example("3D/Geometry/Fabrication"),
        example("3D/Geometry/SpatialExport"),
        example("3D/Geometry/SpatialVideo"),
        example("3D/Camera/CameraControl"),
        example("3D/Camera/CameraMoves"),
        example("3D/Camera/SceneViews"),
        example("3D/Lighting/Lighting"),
        example("3D/Lighting/AreaLights"),
        example("3D/Lighting/GlobalIllumination"),
        example("3D/Lighting/AreaShadows"),
        example("3D/Lighting/Caustics"),
        example("3D/Lighting/LightShaping",
                resources: [.copy("downlight.ies"), .copy("batwing.ies"), .copy("wallwash.ies")]),
        example("3D/Lighting/VolumetricLight"),
        example("3D/Lighting/LightingPresets"),
        example("3D/Materials/Materials"),
        example("3D/Materials/Explorer"),
        example("3D/Materials/NormalMaps"),
        example("3D/Materials/Parallax"),
        example("3D/Materials/SurfaceMaps"),
        example("3D/Materials/Triplanar"),
        example("3D/Materials/Detail"),
        example("3D/Materials/Decals"),
        example("3D/Materials/PhysicalMaterials"),
        example("3D/Materials/CoatAndCloth"),
        example("3D/Materials/BrushedMetal"),
        example("3D/Materials/Glass"),
        example("3D/Materials/SeeThrough"),
        example("3D/Materials/SoapBubble"),
        example("3D/Materials/ThinFilm"),
        example("3D/Materials/Subsurface"),
        example("3D/Environments/ImageBasedLighting"),
        example("3D/Environments/EnvironmentGallery"),
        example("3D/Environments/ProceduralSky"),
        example("3D/Environments/Cloudscape"),
        example("3D/Environments/HighResEnvironment"),
        example("3D/Environments/EnvironmentURL"),
        example("3D/Environments/LiveEnvironment", [.vision]),
        example("3D/Materials/Matcap"),
        example("3D/Lighting/Shadows"),
        example("3D/Lighting/SpotShadow"),
        example("3D/Lighting/TwoCasters"),
        example("3D/Lighting/PointShadow"),
        example("3D/Lighting/PointCasters"),
        example("3D/Depth/DepthCompositing"),
        example("3D/Depth/DepthCloud", [.vision]),
        example("3D/Depth/DepthOcclusion", [.vision]),
        example("3D/Depth/Record3DCloud", [.record3D]),
        example("3D/Depth/Record3DLiveCloud", [.record3D]),
        // 2D markers floating at true metric depths inside a live RGBD feed — the
        // metric (meters) sibling of DepthOcclusion, via a Camera3D.fromIntrinsics.
        example("3D/Depth/MetricDepthScene", [.record3D]),
        example("3D/Depth/DepthLiftedPose", [.vision, .record3D]),
        // The same made-up room swept twice side by side, once trusting the reported
        // camera pose and once lining each frame up against what is already fused.
        example("3D/Depth/ClosedLoopScan"),
        example("3D/Depth/DriftCorrectedScan"),
        // The Ollin iPhone capture app's live body pose drawn as an orbiting 3D
        // stick figure — the own-app sibling of Record3DLiveCloud.
        example("3D/Phone/PhoneBodyPose", [.phone]),
        // A solid mannequin posed by the stream's richer half: the world anchor
        // stands it where the person stands, joint orientations turn its parts.
        example("3D/Phone/PhoneBodyFigure", [.phone]),
        // A costume worn by the live skeleton: ribbon trails that only exist in
        // motion, or plumage whose twist follows the joint rotations.
        example("3D/Phone/PhoneCostume", [.phone]),
        // The Ollin capture app's live face mesh + blendshapes, orbited as a point
        // cloud with expression bars — the front-camera sibling of PhoneBodyPose.
        example("3D/Phone/PhoneFace", [.phone]),
        // The eyes and the gaze from that same Face mode: eyeballs at the streamed
        // eye poses, beams converging on the look-at point, a bead where they meet.
        example("3D/Phone/PhoneGaze", [.phone]),
        // The Ollin capture app's live rear-LiDAR RGBD cloud — the depth sibling of
        // PhoneBodyPose and PhoneFace.
        example("3D/Phone/PhoneDepthCloud", [.phone]),
        // Sweep the phone around a room and fuse every depth frame, by its camera
        // pose, into one accumulated world cloud — the fusion sibling of PhoneDepthCloud.
        example("3D/Phone/PhoneWorldScan", [.phone]),
        // The phone's on-device person segmentation lifted onto a live backdrop —
        // the rear-camera Segment-mode sibling of the depth/pose/face examples.
        example("3D/Phone/PhoneSegmentation", [.phone]),
        // The room the phone reconstructs as a solid surface, block by block, painted
        // by what each triangle is. The Room-mode sibling of PhoneWorldScan.
        example("3D/Phone/PhoneRoomMesh", [.phone]),
        // The flat surfaces in that same room, each as its real outline, with a ball
        // standing on the biggest one and the scene lit by the room's own light.
        example("3D/Phone/PhoneRoomPlanes", [.phone]),
        // The hands the phone sees as solid little skeletons in the room, lifted to
        // metric 3D through the LiDAR depth, with a pinch closing into a bead.
        example("3D/Phone/PhoneHands", [.phone]),
        // The words the phone can read, standing in the room where they really are:
        // each line a framed panel of glowing wire type, facing the way it faces.
        example("3D/Phone/PhoneWorldText", [.phone]),
        example("Motion/Breathing"),
        example("Motion/SineSweep"),
        example("Motion/Easing"),
        example("Motion/EasingGallery"),
        example("Motion/Smoothing"),
        example("Motion/Timeline"),
        example("Motion/Orbits"),
        example("Motion/Linkage"),
        example("Motion/Petals"),
        example("Live/DragToEdit"),
        example("Live/Parameters"),
        example("Motion/Trail"),
        example("Motion/Steering"),
        example("Motion/PerfectLoop"),
        example("Motion/Epicycles", resources: [.copy("whale.svg")]),
        example("Motion/Morphing"),
        example("Motion/Lissajous"),
        example("Motion/Harmonograph"),
        example("Motion/Springs"),
        example("Motion/InverseKinematics"),
        example("Motion/DoublePendulum"),
        example("Motion/NBody"),
        example("Data/Readings", resources: [.copy("readings.csv")]),
        example("Data/Places", resources: [.copy("places.json")]),
        example("Data/Quakes"),
        example("Data/Edits"),
        example("Color/ColorVision"),
        example("Color/ColorWaves"),
        example("Color/HSBWheel"),
        example("Color/Mixing"),
        example("Color/Gradients"),
        example("Color/Harmonies"),
        example("Color/Swatchbook"),
        example("Color/Palettes"),
        example("Color/PaletteFile", resources: [.copy("palettes.csv"), .copy("sunset.hex")]),
        example("Color/PaletteFromImage"),
        example("Color/Dithering"),
        example("Color/PrintSeparation"),
        example("Color/SoftProof"),
        example("Color/Colormaps"),
        example("Motion/FlowField"),
        example("Motion/EllipseField"),
        example("Motion/Attractor"),
        example("Motion/Myriad"),
        example("Motion/RectField"),
        example("Motion/Spokes"),
        example("Motion/Star"),
        example("Motion/Polygons"),
        example("Motion/ArcField"),
        example("Motion/ArcModes"),
        example("Motion/Automation"),
        example("Motion/Formula"),
        example("Motion/FormulaParts"),
        example("Motion/Beats"),
        example("Motion/Sway"),
        example("Randomness/Gaussian"),
        example("Randomness/Ring"),
        example("Randomness/Walk"),
        example("Randomness/Variations"),
        example("Patterns/CliffordAttractor"),
        example("Patterns/GumowskiMira"),
        example("Patterns/Bifurcation"),
        example("Patterns/DotGrid"),
        example("Patterns/Grid"),
        example("Patterns/Phyllotaxis"),
        example("Input/RepelGrid"),
        example("Input/Keys"),
        example("Input/PanAndZoom"),
        example("Patterns/WarpGrid"),
        example("Patterns/EnergyGrid"),
        example("Randomness/NoiseField"),
        example("Randomness/TilingNoise"),
        example("Randomness/RandomBand"),
        example("Randomness/NoiseWave"),
        example("Motion/Triangles"),
        example("Patterns/LifeQuilt"),
        example("Shapes/Markers"),
        example("Shapes/NamedPolygons"),
        example("Shapes/Superellipse"),
        example("Shapes/Supershape"),
        example("Shapes/ShapeMenagerie"),
        example("Shapes/Primitives"),
        example("Shapes/Booleans"),
        example("Shapes/Clipping"),
        example("Shapes/InkRibbon"),
        example("Shapes/RubberBand"),
        example("Shapes/Hulls"),
        example("Shapes/MedialAxis"),
        example("Shapes/Neighbors"),
        example("Shapes/Scattered"),
        example("Shapes/StraightSkeleton"),
        example("Shapes/CornerCutting"),
        example("Shapes/Watercolor"),
        example("Shapes/SVGImport", resources: [.copy("rocket.svg")]),
        example("Patterns/Topography"),
        example("Patterns/ContourMap"),
        example("Patterns/RidgeLines"),
        example("Patterns/Voronoi"),
        example("Patterns/BlueNoise"),
        example("Patterns/LowDiscrepancy"),
        example("Patterns/Stippling"),
        example("Patterns/LevyFlight"),
        example("Patterns/SelfAvoidingWalk"),
        example("Patterns/Kaleidoscope"),
        example("Patterns/TenPrint"),
        example("Patterns/UlamSpiral"),
        example("Patterns/Spirolateral"),
        example("Patterns/FordCircles"),
        example("Patterns/PowerDiagram"),
        example("Patterns/Pentominoes"),
        example("Patterns/DeBruijn"),
        example("Patterns/Caustic"),
        example("Patterns/Wavefront"),
        example("Patterns/Truchet"),
        example("Patterns/Hitomezashi"),
        example("Patterns/Kolam"),
        example("Patterns/Knotwork"),
        example("Patterns/Pursuit"),
        example("Patterns/CreasePattern"),
        example("Patterns/Anamorphosis"),
        example("Patterns/Rivers"),
        example("Patterns/Billiards"),
        example("Patterns/ShapeGrammar"),
        example("Patterns/Penrose"),
        example("Patterns/WangTiles"),
        example("Patterns/Girih"),
        example("Patterns/Spectre"),
        example("Patterns/HyperbolicTiling"),
        example("Patterns/CirclePacking"),
        example("Patterns/LSystem"),
        example("Patterns/ParametricLSystem"),
        example("Patterns/DifferentialGrowth"),
        example("Patterns/Meander"),
        example("Patterns/WaveFunctionCollapse"),
        example("Patterns/TextureSynthesis"),
        example("Patterns/ElementaryCA"),
        example("Patterns/Turmites"),
        example("Patterns/ShapePacking"),
        example("Patterns/Streamlines"),
        example("Patterns/Spirograph"),
        example("Patterns/Guilloche"),
        example("Patterns/Roses"),
        example("Patterns/Flocking"),
        example("Patterns/ForceGraph"),
        example("Patterns/Venation"),
        example("Patterns/Dendrite"),
        example("Patterns/Lichtenberg"),
        example("Patterns/AntColony"),
        example("Patterns/HexGrid"),
        example("Patterns/TriangleGrid"),
        example("Patterns/Subdivision"),
        example("Patterns/Maze"),
        example("Patterns/Apollonian"),
        example("Patterns/IteratedFunctions"),
        example("Patterns/FractalFlame"),
        example("Patterns/Buddhabrot"),
        example("Patterns/Percolation"),
        example("Patterns/InversionFractal"),
        example("Patterns/Kleinian"),
        example("Patterns/Schottky"),
        example("Patterns/Marbling"),
        example("Patterns/Chladni"),
        example("Patterns/Cracks"),
        example("Patterns/Clothoid"),
        example("Shapes/HollowShapes"),
        example("Shapes/StrokeAlignment"),
        example("Shapes/StrokeJoinsAndCaps"),
        example("Shapes/Brushes"),
        example("Shapes/StrokeProfiles"),
        example("Shapes/Brushwork"),
        example("Motion/Mandala"),
        example("Text/HelloText"),
        example("Text/TextVolume"),
        // The font lives beside the sketch (the per-example asset convention)
        // and loads at runtime through the Playdate `.fnt` loader.
        example("Text/PlaydateFont", resources: [.copy("MarbleMadness.fnt")]),
        example("Text/OutlineText"),
        example("Text/GlyphWave"),
        example("Text/TextOnPath"),
        example("Text/TextBox"),
        example("Text/VariableFont"),
        example("Text/StrokeText"),
        example("Text/TextMetrics"),
        example("Text/GlyphContours"),
        example("Text/PointShimmer"),
        example("Text/JitterType"),
        example("Text/Scripts"),
        example("Text/Columns"),
        example("Text/MongolianColumns"),
        example("Text/HangingStops"),
        example("Images/GlyphMosaic"),
        example("Images/PhotoMosaic"),
        example("Images/Autostereogram"),
        example("Images/Fit"),
        example("Images/Halftone"),
        example("Images/LuminanceMelt"),
        example("Images/PixelField"),
        example("Images/PixelSort"),
        example("Images/SeamCarve"),
        example("Images/SingleLine"),
        example("Images/SlitScan"),
        example("Images/SpanningTree"),
        example("Images/StringArt"),
        example("Audio/Synth", [.audio]),
        example("Audio/Generative", [.audio]),
        example("Audio/Strings", [.audio]),
        example("Audio/StruckShapes", [.audio]),
        example("Audio/SoundInAnExport", [.audio]),
        example("Audio/Spatial", [.audio]),
        example("Audio/Sonification", [.audio]),
        example("Audio/Bowing", [.audio]),
        example("Audio/Changes", [.audio]),
        example("Audio/Patching", [.audio]),
        example("Audio/Shaping", [.audio]),
        example("Audio/Sampler", [.audio]),
        example("Audio/Spectrum", [.audio]),
        example("Audio/Microphone", [.audio]),
        example("Audio/Listening", [.audio]),
        example("Audio/ChladniResonance", [.audio]),
        // The bundled clip the sketch loads via Bundle.module (a launch path
        // overrides it). CC BY-SA, provenance in THIRD-PARTY-NOTICES.md.
        example("Audio/FilePlayer", [.audio], resources: [.copy("fandanguito.m4a")]),
        // Integration tier — OSC, and (later) MIDI/Syphon. Self-contained: the
        // sketch sends OSC to itself on loopback and visualizes what it receives,
        // so it needs no external app to run.
        example("Integration/OSCLoopback", [.osc]),
        // Listens for OSC and prints/draws every message — point a phone or any
        // OSC source at this Mac to discover what its controls send.
        example("Integration/OSCMonitor", [.osc]),
        // Self-contained: a DMX sender drives a drawn rig of pars over sACN on
        // loopback and the receiver lights them from what arrives, so the stage
        // you see is the round trip (like OSCLoopback). Point it at a real
        // node's IP and the same universe drives real lights.
        example("Integration/DMXLoopback", [.dmx]),
        example("Integration/LEDMapping", [.dmx]),
        // The optimizer made visible: the beam's own path across a drawing,
        // with the knobs that decide what it costs. Runs with no hardware; the
        // header says the two lines that point it at a real projector.
        example("Integration/LaserPreview", [.laser]),
        // Self-contained: a virtual-source output sends animated MIDI to itself and
        // the input draws it back, so it runs with no hardware (like OSCLoopback).
        example("Integration/MIDILoopback", [.midi]),
        // Listens to every MIDI source and prints/draws what arrives — connect a
        // controller and discover what each knob/pad sends just by touching it.
        example("Integration/MIDIMonitor", [.midi]),
        // Self-contained: an internal timer sends MIDI clock to itself and a
        // TempoClock locks the visuals to it; point real gear at the Mac and the
        // same sketch follows that instead.
        example("Integration/TempoSync", [.midi]),
        // Self-contained: a fake device on the manager side of a pty pair prints
        // a sensor value and a SerialPort reads the other side, so the classic
        // physical-computing loop runs with no hardware (like OSCLoopback);
        // clicking writes a line back and the wave flips.
        example("Integration/SerialLoopback", [.serial]),
        // Lists every serial device live and scrolls whatever the open one
        // prints: plug a microcontroller in and its lines (and a numeric
        // value bar) appear; keys pick a device and send a line back.
        example("Integration/SerialMonitor", [.serial]),
        // Serves its own @Param knobs to a phone on the same network: open the
        // address the canvas shows and every slider, toggle, menu, color, pad,
        // and stepper appears as a touch control, live both ways.
        example("Integration/RemoteSurface", [.remote]),
        // One piece across several machines: open it on two Macs on the same
        // network and they find each other by the room's name, sharing a clock,
        // a seat each, and every knob. It runs alone as one seat of one.
        example("Integration/RoomCanvas", [.room]),
        // Self-contained: two rooms inside one sketch trade values over a
        // transport that never leaves the process (like OSCLoopback), so the
        // whole loop is on one screen and the space bar cuts the wire.
        example("Integration/RoomLoopback", [.room]),
        // Self-contained: publishes its own frames as a Syphon source and
        // subscribes to them, so the feedback inset is the round-trip (like
        // OSCLoopback). Open Syphon's Simple Client to see it cross-app.
        example("Integration/SyphonLoopback", [.syphon]),
        // Subscribes to any external Syphon source (openFrameworks, Resolume, …)
        // and draws it letterboxed — the "see what's out there" viewer.
        example("Integration/SyphonViewer", [.syphon]),
        // Publishes its frames to the Ollin Camera virtual camera, so any
        // webcam app (Photo Booth, Zoom, a browser) reads the sketch as a live
        // camera; the canvas shows the connection state. Needs the Ollin
        // Camera extension installed (Apps/OllinCameraApp).
        example("Integration/VirtualCamera", [.camera]),
        // Takes the Mac's own screen as material: the whole display, one app, or
        // a single window, drawn and filtered like any image. `tunnel` leaves the
        // sketch's own window in the capture, so the picture recedes into itself.
        example("Integration/ScreenCapture", [.screen]),
        // A game controller as a drawing instrument: sticks steer the pen,
        // triggers set its weight, and a pad that reports motion tips the page.
        example("Integration/ControllerInput", [.controller]),
        example("Integration/HapticRidges", [.haptics]),
        // Every Bluetooth device around the Mac, drawn as a room: each one
        // sits at the distance its signal suggests, so a phone in a pocket
        // moves a dot. Needs no gear of your own, since a room is already
        // full of devices announcing themselves.
        example("Integration/BluetoothRoom", [.bluetooth]),
        // One Bluetooth device, connected and read: type part of a name into
        // the knob and every value it offers appears as it arrives, with a
        // heart rate driving the disc.
        example("Integration/BluetoothSensor", [.bluetooth]),
        // Physics — a Verlet world stepped each frame. Packing is a field of
        // colliding discs; Blobs are spring-built soft bodies that squish.
        example("Physics/Packing", [.physics]),
        example("Physics/Blobs", [.physics]),
        example("Physics/Stack", [.physics]),
        example("Physics/Tumble", [.physics]),
        example("Physics/Chain", [.physics]),
        // Video — plays a bundled clip (or a path passed on launch) as a live
        // image. The clip is the example's own asset (CC BY-SA, provenance in
        // THIRD-PARTY-NOTICES.md), per the per-example asset convention.
        example("Video/VideoPlayback", [.video], resources: [.copy("voladores.mp4")]),
        // The video's soundtrack analyzed live: a Soundtrack taps the playing
        // clip's audio (the core AudioTapSource seam) and the sketch draws its
        // bands and beats over the footage. Its clip pairs the voladores
        // footage with the fandanguito violin recording as the soundtrack
        // (both CC BY-SA; provenance in THIRD-PARTY-NOTICES.md).
        example("Video/SoundReactive", [.video, .audio], resources: [.copy("voladores-fandanguito.mp4")]),
        // Vision — the Mac's camera plus Apple Vision perception. WebcamFeed draws
        // the live feed; FaceTracking overlays detected faces and landmarks. Both
        // need a camera and grant camera permission on first run.
        example("Vision/WebcamFeed", [.vision]),
        example("Vision/FaceTracking", [.vision]),
        // The camera transformed so the face stays locked level and centered —
        // the room moves, not the head.
        example("Vision/FaceAlign", [.vision]),
        // Traces the camera's edges into vector contours (Shapes); self-contained,
        // falling back to a generated pattern when there's no camera.
        example("Vision/ContourTrace", [.vision]),
        // Hand skeletons (21 joints, up to two hands) drawn over the live feed.
        example("Vision/HandTracking", [.vision]),
        // A person's 2D pose drawn as a stick figure over the live feed.
        example("Vision/BodyPose", [.vision]),
        // The 3D pose: the skeleton in meters, overlaid on the feed and re-drawn
        // from the side — a view no camera is at.
        example("Vision/BodyPose3D", [.vision]),
        // People lifted off the background and composited over a drawn gradient
        // (background replacement; the matte doubles as the drop shadow).
        example("Vision/PersonSegmentation", [.vision]),
        // The person matte as a reaction-diffusion regime map: maze chemistry on
        // your silhouette, spots everywhere else, one continuous field.
        example("Vision/TuringMirror", [.vision]),
        // The salient subject lifted into a spotlight: dimmed frame, full-color
        // cutout, matte halo.
        example("Vision/SubjectLift", [.vision]),
        // Click a thing and it lifts out: point-prompted segmentation over the
        // feed, shift-click trims, C clears (fetched model).
        example("Vision/PointLift", [.vision]),
        // Rectangular shapes (paper, screens, cards) highlighted as quads.
        example("Vision/RectangleScan", [.vision]),
        // Barcodes / QR codes outlined and their payload printed.
        example("Vision/BarcodeReader", [.vision]),
        // OCR — text read from the feed, each line boxed and printed.
        example("Vision/TextScan", [.vision]),
        // Object tracking — click to lock onto a patch and follow it across frames.
        example("Vision/ObjectTracking", [.vision]),
        // Optical flow — the camera's motion as a field of arrows, with dust
        // particles riding it.
        example("Vision/OpticalFlow", [.vision]),
        // Image classification — what the camera sees, named live as animated
        // label bars.
        example("Vision/SceneLabels", [.vision]),
        // Saliency — where the eye goes, as a warm heat-map glow over the feed
        // with the salient regions boxed and a marker gliding to the hottest spot.
        example("Vision/EyeCatcher", [.vision]),
        // A custom Core ML model (monocular depth) over the live feed — the
        // depth map sampled into a relief of disks. The model weights download
        // via Scripts/fetch-models.sh (never committed).
        example("Vision/DepthRelief", [.vision]),
        // Object detection (YOLOv3-tiny) — labeled boxes over the live feed.
        // The model weights download via Scripts/fetch-models.sh (never
        // committed).
        example("Vision/ObjectDetection", [.vision]),
        // Semantic segmentation (DeepLabV3) — every pixel painted by class.
        // The model weights download via Scripts/fetch-models.sh (never
        // committed).
        example("Vision/PaintByClass", [.vision]),
        // A model reading the sketch's own pixels — draw a digit with the
        // mouse, MNIST classifies it; no camera at all. The model weights
        // download via Scripts/fetch-models.sh (never committed).
        example("Vision/DigitReader", [.vision]),
        // The camera through a Create ML style-transfer model you train
        // yourself (no download — the model is the user's own work).
        example("Vision/StyleMirror", [.vision]),
        // Typed phrases as live knobs (ConceptTracker): two phrases pull on
        // one rope by how well each matches the frame. The model weights
        // download via Scripts/fetch-models.sh (never committed).
        example("Vision/TugOfWords", [.vision]),
        // Trajectory detection — ballistic arcs found in a synthetic feed (a
        // custom FrameSource the example conforms itself).
        example("Vision/TrajectoryTracking", [.vision]),
        // Vision over recorded footage — contours traced from a playing video
        // (the frame-source seam: a tracker attached to a VideoPlayer the way
        // it attaches to a Camera). Bundles the same CC BY-SA clip as
        // VideoPlayback; provenance in THIRD-PARTY-NOTICES.md.
        example("Vision/VideoTrace", [.vision, .video], resources: [.copy("voladores.mp4")]),
        // Recreations — sketches recreating past computer artists, namespaced by
        // artist (see Examples/Recreations/README.md).
        example("Recreations/VeraMolnar/Interruptions"),
        example("Recreations/VeraMolnar/DesOrdres"),
        example("Recreations/GeorgNees/Schotter"),
        example("Recreations/BridgetRiley/Fragment3"),
        example("Recreations/BridgetRiley/Current"),
        example("Recreations/OsamuSato/Totem"),
        example("Recreations/OsamuSato/Alphabet"),
        // A raffia suit that conceals its dancer and rustles when the body moves,
        // after Nick Cave's Soundsuits; the tethered phone can wear it live.
        example("Recreations/NickCave/Soundsuit", [.audio, .phone]),
        example("Recreations/JaredTarbell/Substrate"),
        // A machine that composes in an artist's own language and weighs the
        // result, after Manuel Felguerez's "La maquina estetica".
        example("Recreations/ManuelFelguerez/MaquinaEstetica"),
        // The cube as an instrument: its twelve lines as an alphabet, and the
        // diagonal paths of its four-dimensional relative, after Manfred Mohr.
        example("Recreations/ManfredMohr/CubicLimit"),
        example("Recreations/ManfredMohr/DiagonalPath"),
    ]
)
