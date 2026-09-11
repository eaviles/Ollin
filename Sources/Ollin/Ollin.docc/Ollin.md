# ``Ollin``

Creative coding in Swift, drawn by Metal.

## Overview

A sketch is a class with a `setup()` that runs once and a `draw()` that runs every frame, at the
display's refresh rate. Animation is the default rather than something to switch on.

```swift
import Ollin

@main
final class BreathingCircle: Sketch {
    override func draw() {
        background(.white)
        fill(.black)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

The bare calls in that example are sugar over a typed core, so anything `drawCircle` can do is also
reachable by composing values: a `Vector2`, a `Shape`, a `Color`, a `Filter`. This page is the
generated surface, every public symbol in the module. The written reference at
[ollin.art](https://ollin.art/docs/) is the curated one, and the guide there teaches the same
material in order.

Importing Ollin also brings in CoreGraphics, so a sketch can write `sin(time)` and name a `CGRect`
without a second import. That is why the standard math functions appear here under Functions
alongside Ollin's own.

## Topics

### The sketch

A sketch is a class with a `setup()` and a `draw()`. These are the pieces around it: the window, the run loop, the frame, and the seam other features bolt onto.

- ``CanvasSize``
- ``FrameInfo``
- ``FrameProfile``
- ``Installation``
- ``KeyboardFocus``
- ``OllinApp``
- ``OllinCameraCommands``
- ``Sketch``
- ``SketchExtension``
- ``SketchRunner``
- ``SketchSaverView``
- ``SketchView``
- ``StatusStyle``
- ``WindowMode``
- ``sketchResource(_:in:from:)``

### Drawing

What a stroke and a fill are made of: caps, joins, dashes, blend modes, brushes, and the retained batch for geometry that does not change.

- ``ArcMode``
- ``Batch``
- ``BlendMode``
- ``Brush``
- ``PathTracing``
- ``PointMarker``
- ``RenderQuality``
- ``SDF``
- ``SDF3D``
- ``StrokeAlign``
- ``StrokeCap``
- ``StrokeDash``
- ``StrokeDynamics``
- ``StrokeInput``
- ``StrokeJoin``
- ``StrokeMark``
- ``StrokeProfile``
- ``StrokeResponse``
- ``ToneMap``

### Color

Color as a value, in the spaces that keep mixing predictable, with palettes, ramps, dither, and the print and color-vision paths.

- ``Color``
- ``ColorConfusion``
- ``ColorOutput``
- ``ColorSpace``
- ``ColorVision``
- ``Colormap``
- ``CosinePalette``
- ``Dither``
- ``Gradient``
- ``ICCProfile``
- ``Ink``
- ``OKHSL``
- ``OKLCH``
- ``OKLab``
- ``Paint``
- ``Palette``
- ``PaletteFormat``
- ``PrintSeparation``
- ``ProcessSeparation``
- ``Ramp``
- ``RenderingIntent``
- ``SoftProof``
- ``Spectrum``

### Shapes, paths, and spatial structure

The geometry value types you build, transform, and hand to the drawing calls, plus the structures that answer questions about a set of points.

- ``Circle``
- ``Clothoid``
- ``Contour``
- ``Delaunay``
- ``FillWinding``
- ``Fit``
- ``Grid``
- ``Heightfield``
- ``HexGrid``
- ``HobbySpline``
- ``Insets``
- ``IsosurfaceMethod``
- ``MedialAxis``
- ``Metaballs``
- ``Path``
- ``Polyomino``
- ``PolyominoPlacement``
- ``PowerDiagram``
- ``Ray2``
- ``Rectangle``
- ``SVG``
- ``Shape``
- ``ShapeMorph``
- ``SpatialIndex``
- ``Spline``
- ``StraightSkeleton``
- ``Subdivision``
- ``SubdivisionScheme``
- ``SurfaceSample``
- ``Triangle``
- ``TriangleGrid``
- ``Voronoi``

### Generative geometry

The technique catalog: tilings, fractals, packings, growth, flow, agents, and the rest, each emitting geometry a sketch draws.

- ``Anamorphosis``
- ``AntColony``
- ``Billiard``
- ``Boids``
- ``ChaoticMap``
- ``ContinuousPacking``
- ``CrackGrowth``
- ``CreasePattern``
- ``DielectricBreakdown``
- ``DifferentialGrowth``
- ``DiffusionLimitedAggregation``
- ``DoublePendulum``
- ``Drainage``
- ``Epicycles``
- ``Erosion``
- ``FlowField``
- ``ForceLayout``
- ``FordCircle``
- ``Genome``
- ``Girih``
- ``GrowthDriver``
- ``Harmonograph``
- ``Hitomezashi``
- ``HopfFiber``
- ``HyperbolicTiling``
- ``IFS``
- ``IKChain``
- ``IteratedMap``
- ``KleinianPreset``
- ``Knotwork``
- ``Kolam``
- ``LSystem``
- ``LSystemModule``
- ``LightSource``
- ``MarbledInk``
- ``Marbling``
- ``Maze``
- ``Meander``
- ``MeshGrowth``
- ``MeshReactionDiffusion``
- ``MiuraFold``
- ``NBody``
- ``OverlappingWFC``
- ``ParametricLSystem``
- ``ParquetDeformation``
- ``Penrose``
- ``Percolation``
- ``Population``
- ``Pursuit``
- ``RadialBasis``
- ``RadialBasisPoint``
- ``RadialBasisValue``
- ``River``
- ``Rosette``
- ``RotatingSquares``
- ``SchottkyPairing``
- ``SchottkyPreset``
- ``ShadowArt``
- ``ShapeGrammar``
- ``SpaceColonization``
- ``Spectre``
- ``Spirolateral``
- ``StrangeAttractor``
- ``StringArt``
- ``SurfaceChemistry``
- ``SurfaceFitting``
- ``SurfaceScatter``
- ``TenPrint``
- ``Tensegrity``
- ``Truchet``
- ``Turmite``
- ``UlamSpiral``
- ``Vehicle``
- ``WFCSymmetry``
- ``WFCTile``
- ``WangTile``
- ``WangTiling``
- ``Watercolor``
- ``WaveFunctionCollapse``
- ``WeightedSite``
- ``alphaShape(of:alpha:)``
- ``apollonianGasket(in:minRadius:rotation:maxCount:)``
- ``caustic(off:from:closed:)``
- ``clothoidCorners(_:radius:easement:closed:)``
- ``clothoidSpline(through:closed:)``
- ``concaveHull(of:concavity:)``
- ``convexHull(of:)``
- ``elementaryCA(rule:width:generations:from:wrap:)``
- ``envelope(of:closed:)``
- ``epitrochoid(ring:wheel:pen:samples:)``
- ``eulerSpiral(size:turns:count:)``
- ``fitted(_:in:)``
- ``fordCircles(order:in:interval:)``
- ``guilloche(rings:innerRadius:outerRadius:rosettes:twist:samples:)``
- ``halton(_:base:)``
- ``haltonPoints(count:in:bases:startIndex:)``
- ``hopfBases(spiralCount:)``
- ``hopfFiber(over:segments:reach:)``
- ``hopfFibers(over:segments:reach:)``
- ``huygensFront(from:advancing:closed:)``
- ``hypotrochoid(ring:wheel:pen:samples:)``
- ``inversionLimitSet(of:count:settle:using:)``
- ``inverted(_:in:)``
- ``isolines(at:in:resolution:field:)-(Double,_,_,_)``
- ``isosurface(at:in:resolution:method:field:)``
- ``kleinianLimitSet(_:epsilon:maxDepth:)``
- ``levyFlight(from:steps:minStep:maxStep:exponent:using:)``
- ``lissajous(a:b:phase:width:height:samples:)``
- ``medialAxis(of:spacing:prune:)``
- ``packCircles(around:in:minRadius:maxRadius:padding:)``
- ``packShapes(_:in:count:minRadius:maxRadius:padding:rotation:scale:using:)``
- ``particleSurface(of:radius:blend:resolution:)-(PointCloud,_,_,_)``
- ``phyllotaxis(count:spacing:angle:)``
- ``poissonDisk(in:radius:candidates:maxCount:using:)``
- ``powerDiagram(sites:in:)``
- ``randomWalk(from:steps:stepLength:using:)``
- ``reconstructSurface(of:spacing:resolution:orientedToward:maxGap:neighbors:fitting:keepingLargestComponent:)-(PointCloud,_,_,_,_,_,_,_)``
- ``reflectedRays(off:from:closed:)``
- ``refractedRays(through:from:index:closed:)``
- ``relaxCircles(_:in:iterations:padding:)``
- ``Penrose``
- ``schottkyCircles(_:in:minRadius:maxDepth:)``
- ``schottkyCuspedPairs(in:spread:lean:twist:)``
- ``schottkyLimitSet(_:in:minRadius:maxDepth:)``
- ``schottkyNecklace(pairs:in:tightness:twist:)``
- ``selfAvoidingWalk(in:cellSize:from:maxLength:using:)``
- ``ShadowArt``
- ``singleLine(through:closed:)``
- ``sobolPoints(count:in:startIndex:)``
- ``spanningTree(through:)``
- ``spirolateral(order:turn:step:reversed:repeats:maxRepeats:)``
- ``stipple(of:count:in:iterations:using:)``
- ``straightSkeleton(of:)``
- ``superellipse(width:height:n:samples:)``
- ``supershape(radius:m:n1:n2:n3:samples:)``
- ``surfacePoints(on:count:scatter:using:)``
- ``tilePolyominoes(_:covering:reuse:reflections:)``
- ``totalisticCA(code:colors:width:generations:from:wrap:)``

### Text

Type as geometry: the font kinds, glyphs, alignment, direction, and the set of characters a sketch draws with.

- ``BitmapFont``
- ``BitmapGlyph``
- ``GlyphMosaicCell``
- ``GlyphPair``
- ``GlyphSet``
- ``HorizontalTextAlign``
- ``OutlineFont``
- ``StrokeFont``
- ``StrokeGlyph``
- ``TextDirection``
- ``TextGlyph``
- ``TextMode``
- ``VerticalTextAlign``

### Pictures

Pictures as material: loading, fitting, and the techniques that take one apart.

- ``Autostereogram``
- ``Buddhabrot``
- ``FractalFlame``
- ``HalftoneDot``
- ``Image``
- ``ImageFit``
- ``MosaicTile``
- ``PhotoMosaic``
- ``PixelSortDirection``
- ``PixelSortKey``
- ``SeamDirection``
- ``SeamEnergy``
- ``SeamMap``
- ``SlitScan``

### Effects and shaders

The layered-effects substrate: render targets, the filter catalog, generators, feedback, simulation fields, and a shader of your own.

- ``Accumulator``
- ``Bokeh``
- ``CellNeighborhood``
- ``Combine``
- ``ComposeBuilder``
- ``ComposeLayer``
- ``Feedback``
- ``Filter``
- ``Generator``
- ``LayerPrecision``
- ``LineSpray``
- ``RenderTarget``
- ``SandMaterial``
- ``Shader``
- ``ShaderCompileError``
- ``Sim``
- ``SimField``
- ``SprayLine``
- ``TuringScale``
- ``Visual``
- ``WatercolorField``
- ``WatercolorPigment``

### Simulation on the GPU

Compute-shader tiers where the state lives on the GPU: particles, artificial life, fluids, swarms, and evolution.

- ``AttractorFlow``
- ``AttractorSystem``
- ``ComputeBindable``
- ``ComputeBuffer``
- ``ComputeKernel``
- ``ComputeParams``
- ``ComputeTexture``
- ``ComputeTextureFormat``
- ``Evolution``
- ``PPS``
- ``ParticleFluid``
- ``ParticleLenia``
- ``ParticleLife``
- ``ParticleStyle``
- ``Particles``
- ``Physarum``
- ``PingPong``
- ``PingPongTexture``
- ``Simulation``
- ``SoftBodies``
- ``SpatialHash``
- ``Swarm``
- ``SwarmChemistry``

### 3D

The opt-in third dimension: camera, meshes, materials, lights, environments, clouds, and the scene loader.

- ``Camera3D``
- ``CameraIntrinsics``
- ``CameraMove``
- ``CameraView``
- ``CloudAlignment``
- ``Clouds``
- ``Decal``
- ``DepthConfidence``
- ``Environment``
- ``Fog``
- ``IESProfile``
- ``Lens``
- ``LensFlare``
- ``LensInterface``
- ``Light``
- ``LightCookie``
- ``LightingPreset``
- ``LineDrawing``
- ``Matcap``
- ``Material``
- ``Mesh``
- ``MeshField``
- ``MeshFileFormat``
- ``MeshInstance``
- ``MeshMaterial``
- ``MeshPrintCheck``
- ``MeshTangent``
- ``ModelUnit``
- ``Ocean``
- ``OceanField``
- ``PointCloud``
- ``Profile``
- ``RGBDFrame``
- ``ScanGraph``
- ``Scene``
- ``SceneAnimation``
- ``SceneFileFormat``
- ``SceneNode``
- ``StereoEye``
- ``StereoGeometry``
- ``StrandField``
- ``TextureWrap``
- ``UpAxis``
- ``WaterSurface``
- ``WorldCloud``

### Math and motion

Vectors, ranges, easing, springs, noise, tempo, and the small helpers that shape a number over time.

- ``Box3``
- ``DampedSpring``
- ``DeBruijnCode``
- ``Eased``
- ``Easing``
- ``Formula``
- ``FormulaError``
- ``Fraction``
- ``GaborNoise``
- ``NoteLength``
- ``OneEuroFilter``
- ``Ray3``
- ``Rotation3D``
- ``Smoothable``
- ``Smoothed``
- ``SplitMix64``
- ``Sprung``
- ``SwayShape``
- ``Tempo``
- ``Timeline``
- ``Tweenable``
- ``Vector2``
- ``Vector3``
- ``WorleyFeature``
- ``angles(_:from:turns:)``
- ``bipolar(_:)``
- ``chladni(_:_:m:n:a:b:)``
- ``clamp(_:to:)``
- ``deBruijnSequence(symbols:window:)``
- ``dist(_:_:_:_:)``
- ``fareySequence(order:)``
- ``fract(_:)``
- ``fractions(_:inclusive:)``
- ``isPrime(_:)``
- ``lerp(_:_:_:)``
- ``lyndonWords(symbols:maxLength:)``
- ``map(_:_:_:_:_:clamp:)``
- ``polar(_:_:around:)``
- ``primes(upTo:)``
- ``smoothstep(_:_:_:)``
- ``step(_:_:)``
- ``unipolar(_:)``
- ``wrap(_:_:_:)``

### Parameters

A `@Param` property becomes a control in the inspector, driven by hand, by a formula, by an automation track, or over the wire.

- ``AnyParam``
- ``Param``
- ``ParamChoices``
- ``ParamColorStop``
- ``ParamControl``
- ``ParamGroup``
- ``ParamHandle``
- ``ParamMenuStyle``
- ``ParamNumericConstraints``
- ``ParamNumericStyle``
- ``ParamOption``
- ``ParamRangeConstraints``
- ``ParamRectangleConstraints``
- ``ParamSmoothing``
- ``ParamStored``
- ``ParamSwatchConstraints``
- ``ParamSwatchStyle``
- ``ParamValue``
- ``ParamVector3Constraints``
- ``ParamVectorConstraints``
- ``ParamVectorStyle``

### The world as input

Feeds a sketch reads while it runs: data, tables, video, audio taps, and the frames another source hands over.

- ``AudioTap``
- ``AudioTapSource``
- ``ClipPlayback``
- ``DataFeed``
- ``FrameSource``
- ``FrameTap``
- ``JSON``
- ``Place``
- ``PushFeed``
- ``StillFrames``
- ``SunPosition``
- ``Table``
- ``TableFormat``
- ``VideoFeed``
- ``Weather``

### Input devices

The keys, modifiers, and pen the sketch reads directly.

- ``KeyCode``
- ``ModifierKeys``
- ``Stylus``

### Recording, cues, and takes

What survives a run: a recorded session, a named cue, a saved value, and a take of the rendered frames.

- ``Automation``
- ``AutomationError``
- ``Cue``
- ``CueRequest``
- ``CueSheet``
- ``Saved``
- ``SavedHandle``
- ``SavedProperty``
- ``Take``
- ``TakeError``

### Export and fabrication

Leaving the screen: video, vector, stitch, toolpath, and the machine formats.

- ``DXF``
- ``Drafting``
- ``Embroidery``
- ``GCode``
- ``Hatching``
- ``SessionRecorder``
- ``SlowMotion``
- ``Stitch``
- ``Stitching``
- ``Toolpath``
- ``VideoCodec``
- ``WebExportRefusal``
- ``WebPageForm``
- ``WebWeightRefusal``

### Describable output

What a sketch says about itself, for a caption or a reader.

- ``CaptionEdge``
- ``DescribedElement``
- ``SketchDescription``

### For a host app

The chrome a host window puts around a sketch. A sketch never needs these; the live hosts and the gallery do.

- ``CuesCardView``
- ``FrameStats``
- ``InspectorStatus``
- ``MonitorCardView``
- ``MonitorIdentity``
- ``OllinCameraCommands``
- ``OllinHUD``
- ``OllinHUDCommands``
- ``OllinInspector``
- ``ParamSaveAction``
- ``ParametersListView``
- ``SidebarVibrancy``
- ``StatusChip``
- ``TimelineModel``
- ``TitleBarAccessory``
- ``VariationCardView``
- ``WindowCustomizer``
