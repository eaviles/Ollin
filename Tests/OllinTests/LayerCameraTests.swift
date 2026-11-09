import CoreGraphics
import Foundation
import Metal
import Testing
import simd
@testable import Ollin

/// A camera of its own for a layer.
///
/// A camera set inside a layer's block (`withTarget`) is that layer's: the layer
/// is drawn through it, and the canvas and every other layer keep theirs. Each
/// statement below is two pictures checked against two twins, never one view
/// against itself: the layer against the same scene drawn alone on a canvas of
/// the layer's size through the layer's camera, and the canvas against the
/// scene drawn alone through the canvas's camera. The canvas sets its camera
/// *after* the layer's block in the main statements, so a pass that reads the
/// frame's camera where it should read the layer's draws the wrong view.
@MainActor
@Suite(.serialized)
struct LayerCameraTests {

    // MARK: The stage

    /// A sketch whose frame is a closure, with two layers of another shape than
    /// its canvas.
    final class Stage: Sketch {
        var size = (200, 140)
        var layerSize = (160, 90)
        var body: (Stage) -> Void = { _ in }
        var view: RenderTarget!
        var second: RenderTarget!
        var feedback: Feedback!
        var accumulator: Accumulator!
        var field: SimField!
        override var canvasSize: CanvasSize { .size(size.0, size.1) }
        override func setup() {
            view = makeRenderTarget(width: layerSize.0, height: layerSize.1)
            second = makeRenderTarget(width: layerSize.0, height: layerSize.1)
            feedback = makeFeedback(width: layerSize.0, height: layerSize.1)
            accumulator = makeAccumulator(width: layerSize.0, height: layerSize.1)
            field = makeSimField(.gameOfLife(), width: layerSize.0, height: layerSize.1)
        }
        override func draw() { body(self) }
    }

    private func stage(canvas: (Int, Int) = (200, 140), layer: (Int, Int) = (160, 90),
                       _ body: @escaping (Stage) -> Void) -> Stage {
        let sketch = Stage()
        sketch.size = canvas
        sketch.layerSize = layer
        sketch.body = body
        return sketch
    }

    static let layerShape = (160, 90)
    static let ground = Color(white: 0.1)
    static let fromTheStage = Camera3D.perspective(eye: Vector3(0, 1.2, 5), target: .zero, fieldOfView: .pi / 4)
    static let fromAbove = Camera3D.perspective(eye: Vector3(0.4, 6, 0.6), target: .zero, fieldOfView: .pi / 4)
    static let fromTheSide = Camera3D.perspective(eye: Vector3(5, 1.4, 0.8), target: .zero, fieldOfView: .pi / 4)
    static let box = Mesh.box(width: 1.2, height: 0.6, depth: 2)

    /// The frame's lights: set once, they light every view.
    static func keyAndFill(_ s: Sketch) {
        s.directionalLight(.white, direction: Vector3(0.4, -0.8, -0.45), intensity: 1)
        s.ambientLight(Color(white: 0.25))
    }

    static func block(_ s: Sketch, _ material: Material = .matte) {
        s.fill(Color(red: 0.9, green: 0.5, blue: 0.2))
        s.material(material)
        s.drawMesh(box)
    }

    // MARK: Rendering

    /// One headless frame of `sketch`: its canvas, and the renderer that drew
    /// it, which still holds every layer the frame drew.
    private func shoot(_ sketch: Sketch) throws -> (canvas: CGImage, renderer: MetalRenderer) {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let canvas = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
        return (canvas, renderer)
    }

    /// `scene` drawn alone on a canvas of `size` through `camera`, under `frame`'s
    /// lights and air: the twin a view is checked against.
    private func alone(size: (Int, Int), camera: Camera3D?, frame: @escaping (Sketch) -> Void,
                       scene: @escaping (Sketch) -> Void) throws -> CGImage {
        try shoot(stage(canvas: size) { s in
            s.background(Self.ground)
            frame(s)
            if let camera { s.camera(camera) }
            scene(s)
        }).canvas
    }

    /// The two views of one frame against their twins: `scene` drawn into the
    /// layer through `own`, and on the canvas through `canvas`, set after the
    /// layer's block. Returns the two pictures for a statement that wants more.
    @discardableResult
    private func expectTwoViews(_ what: String, canvas canvasCamera: Camera3D = Self.fromTheStage,
                                own: Camera3D = Self.fromAbove, tolerance: Int = 3,
                                frame lightsAndAir: ((Sketch) -> Void)? = nil,
                                scene: @escaping (Sketch) -> Void,
                                sourceLocation: SourceLocation = #_sourceLocation) throws -> (canvas: CGImage, layer: CGImage) {
        let frame: (Sketch) -> Void = lightsAndAir ?? { Self.keyAndFill($0) }
        let sketch = stage { s in
            s.background(Self.ground)
            frame(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(own)
                scene(s)
            }
            s.camera(canvasCamera)
            scene(s)
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer),
                                 "\(what): the layer was given no picture", sourceLocation: sourceLocation)
        let layerTwin = try alone(size: Self.layerShape, camera: own, frame: frame, scene: scene)
        let canvasTwin = try alone(size: (200, 140), camera: canvasCamera, frame: frame, scene: scene)
        // The twins are two different pictures with something in each, or the
        // comparison below proves nothing.
        let elsewhere = try alone(size: Self.layerShape, camera: canvasCamera, frame: frame, scene: scene)
        let apart = try #require(imageDifference(layerTwin, elsewhere))
        #expect(apart.max > 40, "\(what): the two cameras draw the same picture, so this proves nothing",
                sourceLocation: sourceLocation)

        let layerOff = try #require(imageDifference(layer, layerTwin))
        #expect(layerOff.max <= tolerance,
                "\(what): the layer is off its own camera's picture by up to \(layerOff.max) levels (mean \(layerOff.mean))",
                sourceLocation: sourceLocation)
        let canvasOff = try #require(imageDifference(shot.canvas, canvasTwin))
        #expect(canvasOff.max <= tolerance,
                "\(what): the canvas is off its own camera's picture by up to \(canvasOff.max) levels (mean \(canvasOff.mean))",
                sourceLocation: sourceLocation)
        return (shot.canvas, layer)
    }

    // MARK: The statement

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerLooksThroughItsOwnCameraAndTheCanvasKeepsItsOwn() throws {
        try expectTwoViews("a lit block") { Self.block($0) }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theOrderTheTwoCamerasAreSetInDoesNotMatter() throws {
        // The canvas's camera first, then the layer's block: the layer's camera
        // must not replace it.
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.camera(Self.fromTheStage)
            Self.block(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(Self.fromAbove)
                Self.block(s)
            }
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let layerTwin = try alone(size: Self.layerShape, camera: Self.fromAbove, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        let canvasTwin = try alone(size: (200, 140), camera: Self.fromTheStage, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        let layerOff = try #require(imageDifference(layer, layerTwin))
        let canvasOff = try #require(imageDifference(shot.canvas, canvasTwin))
        #expect(layerOff.max <= 3, "the layer is off its camera's picture by up to \(layerOff.max) levels")
        #expect(canvasOff.max <= 3, "the layer's camera moved the canvas by up to \(canvasOff.max) levels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerThatSetsNoCameraIsDrawnThroughTheCanvass() throws {
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.camera(Self.fromTheSide)
            Self.block(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                Self.block(s)
            }
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let twin = try alone(size: Self.layerShape, camera: Self.fromTheSide, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        let off = try #require(imageDifference(layer, twin))
        #expect(off.max <= 3, "a layer with no camera of its own is off the canvas's view by up to \(off.max) levels")
        #expect(sketch.drawer.layerCameras.isEmpty)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func twoLayersKeepTwoCameras() throws {
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(Self.fromAbove)
                Self.block(s)
            }
            s.withTarget(s.second) {
                s.background(Self.ground)
                s.camera(Self.fromTheSide)
                Self.block(s)
            }
            s.camera(Self.fromTheStage)
            Self.block(s)
        }
        let shot = try shoot(sketch)
        let first = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let second = try #require(shot.renderer.layerImage(of: sketch.second, drawer: sketch.drawer))
        let above = try alone(size: Self.layerShape, camera: Self.fromAbove, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        let side = try alone(size: Self.layerShape, camera: Self.fromTheSide, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        let stage = try alone(size: (200, 140), camera: Self.fromTheStage, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        #expect(try #require(imageDifference(first, above)).max <= 3)
        #expect(try #require(imageDifference(second, side)).max <= 3)
        #expect(try #require(imageDifference(shot.canvas, stage)).max <= 3)
        #expect(try #require(imageDifference(above, side)).max > 40, "the two layer cameras draw one picture")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerDrawnInTwoBlocksKeepsTheCameraItSet() throws {
        // The second block of the same layer sets no camera: it is still drawn
        // through the one the first block set, and reads it as the active one.
        var seenInSecondBlock: Camera3D?
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(Self.fromAbove)
            }
            s.camera(Self.fromTheStage)
            Self.block(s)
            s.withTarget(s.view) {
                seenInSecondBlock = s.activeCamera
                Self.block(s)
            }
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let twin = try alone(size: Self.layerShape, camera: Self.fromAbove, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        #expect(try #require(imageDifference(layer, twin)).max <= 3)
        #expect(seenInSecondBlock == Self.fromAbove)
    }

    // MARK: What the sketch reads while it draws

    @Test func theActiveCameraIsTheSurfacesOwn() throws {
        var inside: Camera3D?, insideBeforeSetting: Camera3D?, nested: Camera3D?
        var afterBlock: Camera3D?, inBare: Camera3D?
        let sketch = stage { s in
            s.camera(Self.fromTheStage)
            s.withTarget(s.view) {
                insideBeforeSetting = s.activeCamera      // none of its own yet: the canvas's
                s.camera(Self.fromAbove)
                inside = s.activeCamera
                s.withTarget(s.second) {
                    nested = s.activeCamera               // another layer, no camera: the canvas's
                }
                #expect(s.activeCamera == Self.fromAbove, "a nested block changed the outer layer's camera")
            }
            afterBlock = s.activeCamera
            s.withTarget(s.second) { inBare = s.activeCamera }
        }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(insideBeforeSetting == Self.fromTheStage)
        #expect(inside == Self.fromAbove)
        #expect(nested == Self.fromTheStage, "a layer with no camera read the enclosing layer's, not the canvas's")
        #expect(afterBlock == Self.fromTheStage, "the layer's camera reached the canvas")
        #expect(inBare == Self.fromTheStage)
        #expect(sketch.drawer.camera(for: sketch.view) == Self.fromAbove)
        #expect(sketch.drawer.camera(for: sketch.second) == Self.fromTheStage)
        #expect(sketch.drawer.camera(for: nil) == Self.fromTheStage)
        #expect(sketch.drawer.layerCameras[ObjectIdentifier(sketch.view)] == Self.fromAbove)
        #expect(sketch.drawer.layerCameras[ObjectIdentifier(sketch.second)] == nil)

        // The next frame starts with no camera anywhere.
        sketch.body = { _ in }
        sketch.advance(time: 1 / 60, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(sketch.drawer.camera3D == nil && sketch.drawer.layerCameras.isEmpty)
        #expect(sketch.drawer.previousCamera3D == Self.fromTheStage,
                "the camera motion blur measures against is the canvas's last one")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCameraSetInALayerIsNotTheCanvass() throws {
        // The layer sets the frame's only camera. The canvas has none, so a mesh
        // drawn on it after the block is not drawn, and the canvas stays flat.
        var afterBlock: Camera3D? = Self.fromAbove
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(Self.fromAbove)
                Self.block(s)
            }
            afterBlock = s.activeCamera
            Self.block(s)
        }
        let shot = try shoot(sketch)
        #expect(afterBlock == nil, "the layer's camera reached the canvas")
        let flat = try alone(size: (200, 140), camera: nil, frame: { _ in }, scene: { _ in })
        #expect(try #require(imageDifference(shot.canvas, flat)).max <= 1, "the canvas drew through the layer's camera")
        // And the layer still draws: a sketch whose only camera is its layer's keeps working.
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let twin = try alone(size: Self.layerShape, camera: Self.fromAbove, frame: { Self.keyAndFill($0) }) { Self.block($0) }
        #expect(try #require(imageDifference(layer, twin)).max <= 3)
    }

    @Test func aCameraSetWhileRecordingABatchInALayerIsTheLayers() throws {
        // A batch recording sets the layer stack aside while it records. A
        // camera set in there, inside a layer's block, is still that layer's.
        var afterBlock: Camera3D? = Self.fromAbove
        let sketch = stage { s in
            s.camera(Self.fromTheStage)
            s.withTarget(s.view) {
                _ = s.makeBatch { s.camera(Self.fromAbove) }
            }
            afterBlock = s.activeCamera
        }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(sketch.drawer.camera(for: sketch.view) == Self.fromAbove)
        #expect(afterBlock == Self.fromTheStage)
        #expect(sketch.drawer.camera3D == Self.fromTheStage)
    }

    @Test func aFrameWhoseOnlyCameraIsALayersBorrowsItOnceDrawn() throws {
        // While `draw()` runs the canvas has no camera. Once it returns, the
        // frame's own passes (the shadow maps, the probes, the light grid) are
        // built around the one view the frame has, as they always were.
        var duringDraw: Camera3D? = Self.fromAbove
        let sketch = stage { s in
            s.withTarget(s.view) { s.camera(Self.fromAbove) }
            s.withTarget(s.second) { s.camera(Self.fromTheSide) }
            duringDraw = s.activeCamera
        }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(duringDraw == nil)
        #expect(sketch.drawer.camera3D == Self.fromAbove, "the frame took no camera, or not the first layer's")
        #expect(sketch.drawer.camera(for: sketch.second) == Self.fromTheSide)

        // A canvas with a camera of its own lends nothing and borrows nothing.
        sketch.body = { s in
            s.withTarget(s.view) { s.camera(Self.fromAbove) }
            s.camera(Self.fromTheStage)
        }
        sketch.advance(time: 1 / 60, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(sketch.drawer.camera3D == Self.fromTheStage)
    }

    @Test func aPointIsProjectedOntoTheSurfaceBeingDrawn() throws {
        // Inside a layer's block a projection answers in the layer's points,
        // through the layer's camera; outside, in the canvas's, through its own.
        let point = Vector3(0.5, 0.2, -0.3)
        var onLayer: Vector2?, onCanvas: Vector2?
        var ray: (origin: Vector3, direction: Vector3)?
        var lines: [[Vector2]] = []
        let sketch = stage { s in
            s.withTarget(s.view) {
                s.camera(Self.fromAbove)
                onLayer = s.project(point)
                ray = onLayer.flatMap { s.cameraRay(through: $0) }
                lines = s.lineDrawing(of: Self.box).paths.map(\.points)
            }
            s.camera(Self.fromTheStage)
            onCanvas = s.project(point)
        }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()

        func expected(_ camera: Camera3D, _ size: (Int, Int)) -> Vector2 {
            let clip = camera.viewProjectionMatrix(aspect: Double(size.0) / Double(size.1)) * SIMD4<Float>(point.simd3, 1)
            return Vector2((Double(clip.x / clip.w) + 1) / 2 * Double(size.0),
                           (1 - Double(clip.y / clip.w)) / 2 * Double(size.1))
        }
        let layerPlace = try #require(onLayer), canvasPlace = try #require(onCanvas)
        let wantLayer = expected(Self.fromAbove, Self.layerShape), wantCanvas = expected(Self.fromTheStage, (200, 140))
        #expect((layerPlace - wantLayer).length < 1e-3, "on the layer: \(layerPlace), wanted \(wantLayer)")
        #expect((canvasPlace - wantCanvas).length < 1e-3, "on the canvas: \(canvasPlace), wanted \(wantCanvas)")
        // The ray back through that place on the layer passes through the point.
        let back = try #require(ray)
        #expect((back.origin - Self.fromAbove.eye).length < 1e-9)
        let toPoint = (point - back.origin).normalized
        #expect((toPoint - back.direction).length < 1e-4, "the ray through the layer's point misses the point")
        // A line drawing made inside the block is the layer's: its camera, its size.
        let wanted = LineDrawing(of: [Self.box], camera: Self.fromAbove,
                                 size: Vector2(Double(Self.layerShape.0), Double(Self.layerShape.1))).paths.map(\.points)
        #expect(!lines.isEmpty, "a line drawing inside the layer found no lines")
        #expect(lines == wanted, "a line drawing inside the layer is not the layer's view at the layer's size")
    }

    // MARK: Everything a pass asks of the camera

    @Test(.enabled(if: Snapshot.hasMetal))
    func theHighlightFollowsTheLayersEye() throws {
        // A glossy finish's highlight sits where the eye sees the light
        // mirrored, so it reads the lighting's eye and not only the projection.
        let sphere = Mesh.sphere(radius: 0.9)
        try expectTwoViews("a glossy sphere", own: Self.fromTheSide) { s in
            s.fill(Color(red: 0.2, green: 0.3, blue: 0.8))
            s.material(.polished)
            s.drawMesh(sphere)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLightGivenInCameraSpaceFollowsEachView() throws {
        try expectTwoViews("a headlight", own: Self.fromTheSide, frame: { s in
            s.light(.headlight())
            s.ambientLight(Color(white: 0.1))
        }) { Self.block($0) }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theAirIsMeasuredFromEachViewsEye() throws {
        // Three blocks at three depths, so the fog thickens with distance from
        // whichever eye is looking.
        try expectTwoViews("fog", own: Self.fromTheSide, frame: { s in
            Self.keyAndFill(s)
            s.fog(Color(white: 0.75), density: 0.22)
        }) { s in
            for z in [-2.5, 0.0, 2.5] {
                s.withState {
                    s.translate(Vector3(0, 0, z))
                    Self.block(s)
                }
            }
        }
        try expectTwoViews("a fog value framed by the camera", own: Self.fromAbove, frame: { s in
            Self.keyAndFill(s)
            s.fog(Fog(Color(white: 0.75), veil: 0.7))
        }) { s in
            for z in [-2.5, 0.0, 2.5] {
                s.withState {
                    s.translate(Vector3(0, 0, z))
                    Self.block(s)
                }
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func pointsAndLinesInSpaceGoThroughTheLayersCamera() throws {
        let cloud = PointCloud(positions: [Vector3(0.9, 0.5, 0.5), Vector3(-0.9, -0.5, 0.5),
                                           Vector3(0.2, 0.9, -0.8), Vector3(-0.4, 0.1, 1.1)],
                               color: .red, size: 0.3)
        try expectTwoViews("points and lines in space") { s in
            s.drawPointCloud(cloud)
            s.stroke(Color(red: 0.2, green: 0.9, blue: 0.5))
            s.strokeWeight(3)
            s.drawLine(Vector3(-1.2, -0.6, 0.4), Vector3(1.2, 0.8, -0.6))
            s.noStroke()
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func instancedCopiesGoThroughTheLayersCamera() throws {
        let small = Mesh.box(size: 0.5)
        let copies = [MeshInstance(position: Vector3(-1, 0, 0)), MeshInstance(position: Vector3(1, 0.4, 0.5)),
                      MeshInstance(position: Vector3(0, -0.3, -1))]
        try expectTwoViews("instanced copies") { s in
            s.fill(Color(red: 0.3, green: 0.8, blue: 0.5))
            s.material(.matte)
            s.drawMesh(small, instances: copies)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMarchedFieldIsMarchedThroughTheLayersCamera() throws {
        let field = SDF3D.sphere(radius: 0.7).at(-0.5, 0, 0).union(SDF3D.sphere(radius: 0.45).at(0.6, 0.3, 0.4))
        try expectTwoViews("a marched field", tolerance: 4) { s in
            s.fill(Color(red: 0.85, green: 0.6, blue: 0.3))
            s.drawSDF3D(field)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aVolumeIsMarchedThroughTheLayersCamera() throws {
        let volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
        try expectTwoViews("a volume", tolerance: 4) { s in
            Self.block(s)
            s.withState {
                s.translate(Vector3(0.8, 0.8, 0.4))
                s.drawVolume(volume, size: 0.9)
            }
        }
    }

    // MARK: A field of copies

    /// A row of boxes long enough that each camera sees a different part of it.
    private func row() -> MeshField {
        let field = MeshField()
        field.place(.box(size: 0.5), at: (-12 ... 12).map { MeshInstance(position: Vector3(Double($0) * 1.1, 0, 0)) })
        return field
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldOfCopiesInALayerIsCulledThroughTheLayersView() throws {
        // The field is drawn in the layer alone, through a camera that sees the
        // row's far end; the canvas's camera, set after, looks at its middle.
        // Culled through the canvas's view the layer would lose the far end.
        let field = row()
        let own = Camera3D.perspective(eye: Vector3(10, 2, 5), target: Vector3(10, 0, 0), fieldOfView: .pi / 4)
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(own)
                s.fill(Color(red: 0.3, green: 0.6, blue: 0.9))
                s.drawMeshField(field)
            }
            s.camera(Self.fromTheStage)
            Self.block(s)
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let twinField = row()
        let twin = try alone(size: Self.layerShape, camera: own, frame: { Self.keyAndFill($0) }) { s in
            s.fill(Color(red: 0.3, green: 0.6, blue: 0.9))
            s.drawMeshField(twinField)
        }
        let off = try #require(imageDifference(layer, twin))
        #expect(off.max <= 3, "the layer's field is off its own view by up to \(off.max) levels")
        let flat = try alone(size: Self.layerShape, camera: nil, frame: { _ in }, scene: { _ in })
        #expect(try #require(imageDifference(twin, flat)).max > 40, "the twin shows no boxes")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func twoFieldsOfTheSameCopiesShowOneWorldInTwoViews() throws {
        // A field keeps one visible set a frame, so it is drawn once a frame;
        // a second view of the same copies takes a second field. Each is culled
        // through its own view: the layer sees the row's right end, the canvas
        // its left, and neither loses what the other's camera cannot see.
        let forCanvas = row(), forLayer = row()
        let left = Camera3D.perspective(eye: Vector3(-10, 2, 5), target: Vector3(-10, 0, 0), fieldOfView: .pi / 4)
        let right = Camera3D.perspective(eye: Vector3(10, 2, 5), target: Vector3(10, 0, 0), fieldOfView: .pi / 4)
        func drawRow(_ s: Sketch, _ f: MeshField) {
            s.fill(Color(red: 0.3, green: 0.6, blue: 0.9))
            s.drawMeshField(f)
        }
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(right)
                drawRow(s, forLayer)
            }
            s.camera(left)
            drawRow(s, forCanvas)
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let rightField = row(), leftField = row()
        let layerTwin = try alone(size: Self.layerShape, camera: right, frame: { Self.keyAndFill($0) }) { drawRow($0, rightField) }
        let canvasTwin = try alone(size: (200, 140), camera: left, frame: { Self.keyAndFill($0) }) { drawRow($0, leftField) }
        let layerOff = try #require(imageDifference(layer, layerTwin))
        let canvasOff = try #require(imageDifference(shot.canvas, canvasTwin))
        #expect(layerOff.max <= 3, "the layer's end of the row is off by up to \(layerOff.max) levels")
        #expect(canvasOff.max <= 3, "the canvas's end of the row is off by up to \(canvasOff.max) levels")
    }

    // MARK: What a layer hands on

    @Test(.enabled(if: Snapshot.hasMetal))
    func theDepthALayerHandsOnIsItsOwnCamerasDepth() throws {
        // The layer's depth, drawn into a second layer to be read: with a camera
        // of its own while the canvas looks elsewhere, against the same layer
        // drawn through the same camera as the frame's only one.
        let near = Camera3D.perspective(eye: Vector3(0, 1.5, 4), target: .zero, fieldOfView: .pi / 4, near: 1, far: 12)
        let far = Camera3D.perspective(eye: Vector3(0, 6, 9), target: .zero, fieldOfView: .pi / 4, near: 0.5, far: 400)
        func depthPicture(ownCamera: Bool) throws -> CGImage {
            let sketch = stage { s in
                s.background(Self.ground)
                Self.keyAndFill(s)
                if !ownCamera { s.camera(near) }
                s.withTarget(s.view) {
                    s.background(Self.ground)
                    if ownCamera { s.camera(near) }
                    Self.block(s)
                }
                if ownCamera { s.camera(far) }
                Self.block(s)
                s.withTarget(s.second) {
                    s.background(.black)
                    s.drawImage(s.view.depth.image, 0, 0)
                }
            }
            let shot = try shoot(sketch)
            return try #require(shot.renderer.layerImage(of: sketch.second, drawer: sketch.drawer))
        }
        let own = try depthPicture(ownCamera: true)
        let twin = try depthPicture(ownCamera: false)
        let off = try #require(imageDifference(own, twin))
        #expect(off.max <= 2, "the layer's depth is off its own camera's range by up to \(off.max) levels")
        // Something is in it: the block reads nearer than the cleared far plane.
        var darkest = 255
        let pixels = try #require(rgba(own))
        for i in stride(from: 0, to: pixels.count, by: 4) { darkest = min(darkest, Int(pixels[i])) }
        #expect(darkest < 200, "the depth picture is blank (darkest \(darkest))")
    }

    // MARK: The other kinds of layer

    /// The picture a persistent layer holds after one frame in which `draw`
    /// filled it with points through a camera: its own, with the canvas's set
    /// after, or the canvas's, set before.
    private func persistentPicture(ownCamera: Bool,
                                   layer: @escaping (Stage) -> RenderTarget,
                                   into block: @escaping (Stage, () -> Void) -> Void) throws -> CGImage {
        let cloud = PointCloud(positions: [Vector3(0.9, 0.5, 0.5), Vector3(-0.9, -0.5, 0.5),
                                           Vector3(0.2, 0.9, -0.8), Vector3(-0.4, 0.1, 1.1)],
                               color: .white, size: 0.5)
        let sketch = stage { s in
            s.background(Self.ground)
            if !ownCamera { s.camera(Self.fromAbove) }
            block(s) {
                if ownCamera { s.camera(Self.fromAbove) }
                s.drawPointCloud(cloud)
            }
            if ownCamera { s.camera(Self.fromTheSide) }
            s.drawPointCloud(cloud)
        }
        let shot = try shoot(sketch)
        return try #require(shot.renderer.layerImage(of: layer(sketch), drawer: sketch.drawer),
                            "the layer was given no picture")
    }

    private func expectPersistent(_ what: String, layer: @escaping (Stage) -> RenderTarget,
                                  into block: @escaping (Stage, () -> Void) -> Void) throws {
        let own = try persistentPicture(ownCamera: true, layer: layer, into: block)
        let twin = try persistentPicture(ownCamera: false, layer: layer, into: block)
        let off = try #require(imageDifference(own, twin))
        #expect(off.max <= 2, "\(what): drawn through its own camera it is off by up to \(off.max) levels")
        let pixels = try #require(rgba(twin))
        var brightest = 0
        for i in stride(from: 0, to: pixels.count, by: 4) { brightest = max(brightest, Int(pixels[i])) }
        #expect(brightest > 60, "\(what): the twin is blank, so this proves nothing")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFeedbackLayerKeepsItsCamera() throws {
        try expectPersistent("a feedback layer", layer: { $0.feedback.writeLayer }) { s, body in
            s.withTarget(s.feedback) { body() }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anAccumulatorKeepsItsCamera() throws {
        try expectPersistent("an accumulator", layer: { $0.accumulator.writeLayer }) { s, body in
            s.withAccumulator(s.accumulator) { body() }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSimulationFieldsSeedsKeepTheirCamera() throws {
        try expectPersistent("a simulation field", layer: { $0.field.writeLayer }) { s, body in
            s.withField(s.field) { body() }
        }
    }

    // MARK: The frame's own caches

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerWithItsOwnCameraNeverTakesTheCanvassLightGrid() throws {
        // Twelve lamps: past the inline eight, the frame culls a grid of light
        // lists over the canvas's view. A layer the canvas's size looking from
        // elsewhere must not read that grid, whose tiles are another view's; it
        // shades by the frame's first eight, as a layer of another size does.
        let lamps: [(Vector3, Color)] = (0 ..< 12).map { i in
            let a = Double(i) / 12 * 2 * Double.pi
            return (Vector3(cos(a) * 1.6, 0.9, sin(a) * 1.6),
                    Color(red: 0.5 + 0.5 * cos(a), green: 0.5 + 0.5 * cos(a + 2), blue: 0.5 + 0.5 * cos(a + 4)))
        }
        func lights(_ s: Sketch, count: Int) {
            for (place, color) in lamps.prefix(count) { s.pointLight(color, at: place, intensity: 1.2) }
        }
        func floorAndBlock(_ s: Sketch) {
            s.fill(Color(white: 0.8))
            s.material(.matte)
            s.withState {
                s.translate(Vector3(0, -0.4, 0))
                s.drawPlane(width: 6, depth: 6)
            }
            Self.block(s)
        }
        let size = (192, 128)
        let sketch = stage(canvas: size, layer: size) { s in
            s.background(Self.ground)
            lights(s, count: 12)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(Self.fromAbove)
                floorAndBlock(s)
            }
            s.camera(Self.fromTheSide)
            floorAndBlock(s)
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let firstEight = try alone(size: size, camera: Self.fromAbove, frame: { lights($0, count: 8) }, scene: floorAndBlock)
        let off = try #require(imageDifference(layer, firstEight))
        #expect(off.max <= 3, "the layer read the canvas's light grid: off the first eight lamps by up to \(off.max) levels")
        // The canvas itself is still lit by all twelve, through its grid.
        let allTwelve = try alone(size: size, camera: Self.fromTheSide, frame: { lights($0, count: 12) }, scene: floorAndBlock)
        #expect(try #require(imageDifference(shot.canvas, allTwelve)).max <= 3)
        let canvasEight = try alone(size: size, camera: Self.fromTheSide, frame: { lights($0, count: 8) }, scene: floorAndBlock)
        #expect(try #require(imageDifference(allTwelve, canvasEight)).max > 20, "the last four lamps light nothing, so this proves nothing")
    }

    // MARK: Where it stops

    @Test func thePageStillRefusesThreeDimensionsInALayer() throws {
        // The recorded page carries one camera a frame, the canvas's, and takes
        // no 3D drawing inside a layer at all: a layer with a camera of its own
        // is refused under that name, as it was before it had one.
        let field = SDF3D.sphere(radius: 0.7)
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.camera(Self.fromTheStage)
            s.drawSDF3D(field)
            s.withTarget(s.view) {
                s.camera(Self.fromAbove)
                s.drawSDF3D(field)
            }
        }
        var refusal: WebExportRefusal?
        do { _ = try OllinApp.recordWebFrames(of: sketch, frames: 1, fps: 30) }
        catch let refused as WebExportRefusal { refusal = refused }
        let named = try #require(refusal, "the page took a layer's own camera")
        #expect(named.call == "3D drawing inside a layer", "\(named.call)")
    }

    /// A marched field drawn in a layer alone stays in the layer. The canvas's
    /// reduced-resolution march once drew every field of the frame, so a
    /// layer's field showed on the canvas wherever the canvas's camera saw it,
    /// and a field drawn in both counted twice toward the canvas's coverage.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayersFieldStaysOffTheCanvas() throws {
        // Big enough on the canvas that its march runs at reduced resolution.
        let onCanvas = SDF3D.sphere(radius: 1.0).at(-1.1, 0, 0)
        let inLayer = SDF3D.sphere(radius: 1.0).at(1.1, 0, 0)
        let sketch = stage { s in
            s.background(Self.ground)
            Self.keyAndFill(s)
            s.camera(Self.fromTheStage)
            s.fill(.white)
            s.drawSDF3D(onCanvas)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.fill(.red)
                s.drawSDF3D(inLayer)
            }
        }
        let shot = try shoot(sketch)
        let twin = try alone(size: (200, 140), camera: Self.fromTheStage, frame: { Self.keyAndFill($0) }) { s in
            s.fill(.white)
            s.drawSDF3D(onCanvas)
        }
        let off = try #require(imageDifference(shot.canvas, twin))
        #expect(off.max <= 1, "the layer's field shows on the canvas: off by up to \(off.max) levels (mean \(off.mean))")
        // And the layer holds its own field, through the canvas's camera.
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let layerTwin = try alone(size: Self.layerShape, camera: Self.fromTheStage, frame: { Self.keyAndFill($0) }) { s in
            s.fill(.red)
            s.drawSDF3D(inLayer)
        }
        #expect(try #require(imageDifference(layer, layerTwin)).max <= 4)
    }

    /// A mesh drawn into a layer receives no cast shadow: a layer's pass is
    /// handed no shadow map, whatever camera it looks through. Pinned as a known
    /// issue: the day a layer's meshes are shadowed this stops failing, and the
    /// pin and the pages' sentence about it come off.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMeshInALayerReceivesNoCastShadowYet() throws {
        func floorAndBlock(_ s: Sketch) {
            s.fill(Color(white: 0.85))
            s.material(.matte)
            s.withState {
                s.translate(Vector3(0, -0.3, 0))
                s.drawPlane(width: 8, depth: 8)
            }
            s.withState {
                s.translate(Vector3(0, 0.6, 0))
                Self.block(s)
            }
        }
        func frame(_ s: Sketch) {
            s.directionalLight(.white, direction: Vector3(0.5, -0.8, -0.3), intensity: 1)
            s.ambientLight(Color(white: 0.25))
            s.castShadows()
        }
        let sketch = stage { s in
            s.background(Self.ground)
            frame(s)
            s.withTarget(s.view) {
                s.background(Self.ground)
                s.camera(Self.fromAbove)
                floorAndBlock(s)
            }
            s.camera(Self.fromTheStage)
            floorAndBlock(s)
        }
        let shot = try shoot(sketch)
        let layer = try #require(shot.renderer.layerImage(of: sketch.view, drawer: sketch.drawer))
        let shadowed = try alone(size: Self.layerShape, camera: Self.fromAbove, frame: frame, scene: floorAndBlock)
        let unshadowed = try alone(size: Self.layerShape, camera: Self.fromAbove, frame: { s in
            s.directionalLight(.white, direction: Vector3(0.5, -0.8, -0.3), intensity: 1)
            s.ambientLight(Color(white: 0.25))
        }, scene: floorAndBlock)
        // The shadow is there to be seen on a canvas, and the canvas of this
        // frame has it.
        #expect(try #require(imageDifference(shadowed, unshadowed)).max > 40, "the block throws no shadow to look for")
        let canvasTwin = try alone(size: (200, 140), camera: Self.fromTheStage, frame: frame, scene: floorAndBlock)
        #expect(try #require(imageDifference(shot.canvas, canvasTwin)).max <= 3)
        // What the layer shows today is the scene with no shadow.
        #expect(try #require(imageDifference(layer, unshadowed)).max <= 3,
                "the layer is neither the shadowed nor the unshadowed picture")
        withKnownIssue("a layer's pass is handed no shadow map") {
            let off = try #require(imageDifference(layer, shadowed))
            #expect(off.max <= 3, "the layer's floor is missing the block's shadow (off by up to \(off.max) levels)")
        }
    }

    // MARK: Support

    private func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: data, count: w * h * 4))
    }
}
