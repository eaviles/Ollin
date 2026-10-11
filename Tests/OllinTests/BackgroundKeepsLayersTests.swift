import Testing
import CoreGraphics
@testable import Ollin

/// A background on the canvas wipes the canvas and nothing else. What a frame
/// drew into a layer (`withTarget`, `withField`) before it stays in that
/// layer, and the frame renders exactly as if the canvas had drawn nothing
/// before the wipe: the same pixels as the frame that sets its background
/// first.
@Suite
@MainActor
struct BackgroundKeepsLayersTests {

    /// A field seeded before the canvas background keeps its seed. A 2x2
    /// block is a still life under Life, so after the frame's step the block
    /// is still there, and the frame is the frame of the other order.
    @Test func aFieldSeededBeforeTheBackgroundKeepsItsSeed() throws {
        let after = try OllinApp.image(of: SeededField.make(backgroundFirst: false), frame: 1)
        let before = try OllinApp.image(of: SeededField.make(backgroundFirst: true), frame: 1)
        let cells = Pixels(after)
        for (x, y) in SeededField.block {
            #expect(cells.gray(x, y) > 200, "cell (\(x), \(y)) reads \(cells.gray(x, y))")
        }
        #expect(cells.gray(8, 8) < 30)
        #expect(pixels(of: after) == pixels(of: before))
    }

    /// Every kind of flat mark, on the canvas and in two layers, interleaved
    /// before the wipe: the frame equals the one whose canvas drew nothing
    /// before it, and the one that set its background first.
    @Test func everyFlatKindStaysInItsLayer() throws {
        let interleaved = try OllinApp.image(of: FlatKinds.make(.canvasBetweenLayers), frame: 1)
        let layersOnly = try OllinApp.image(of: FlatKinds.make(.layersOnly), frame: 1)
        let backgroundFirst = try OllinApp.image(of: FlatKinds.make(.backgroundFirst), frame: 1)
        let noLayers = try OllinApp.image(of: FlatKinds.make(.noLayers), frame: 1)
        #expect(pixels(of: interleaved) == pixels(of: layersOnly))
        #expect(pixels(of: interleaved) == pixels(of: backgroundFirst))
        #expect(pixels(of: interleaved) != pixels(of: noLayers))
        let p = Pixels(interleaved)
        #expect(p.gray(5, 5) > 200, "the first layer's disc, drawn at half size, reads \(p.gray(5, 5))")
    }

    /// The same for what a camera draws: solid and instanced meshes, their
    /// feature edges, lines through the camera, point splats, a 3D distance
    /// field, and a volume, which composites over its own pass.
    @Test func everySpatialKindStaysInItsLayer() throws {
        let interleaved = try OllinApp.image(of: SpatialKinds.make(.canvasBetweenLayers), frame: 1)
        let layersOnly = try OllinApp.image(of: SpatialKinds.make(.layersOnly), frame: 1)
        let backgroundFirst = try OllinApp.image(of: SpatialKinds.make(.backgroundFirst), frame: 1)
        let noLayers = try OllinApp.image(of: SpatialKinds.make(.noLayers), frame: 1)
        #expect(pixels(of: interleaved) == pixels(of: layersOnly))
        #expect(pixels(of: interleaved) == pixels(of: backgroundFirst))
        #expect(pixels(of: interleaved) != pixels(of: noLayers))
        // The volume shows, so a layer that lost it would read differently.
        let withoutVolume = SpatialKinds.make(.backgroundFirst)
        withoutVolume.drawsVolume = false
        #expect(pixels(of: backgroundFirst) != pixels(of: try OllinApp.image(of: withoutVolume, frame: 1)))
    }

    /// The recorded frame itself, past its pixels: with the web record on,
    /// the runs, their geometry, and the strokes and fills a web page expands
    /// come out of the wipe exactly as they come out of a frame whose canvas
    /// drew nothing before it.
    @Test func theRecordAfterTheWipeIsTheRecordWithoutTheCanvas() {
        func record(canvasBetweenLayers: Bool) -> Drawer {
            let drawer = Drawer()
            drawer.beginFrame()
            drawer.recordsWebSources = true
            let layer = RenderTarget(width: 64, height: 64, scale: 1, drawer: drawer)
            func marks(_ o: Double) {
                drawer.stroke(.white)
                drawer.strokeWeight(2)
                drawer.drawLine(Vector2(o, o), Vector2(o + 20, o + 10))
                drawer.noStroke()
                drawer.fill(.red)
                drawer.drawPolygon([Vector2(o, o), Vector2(o + 12, o), Vector2(o + 12, o + 4),
                                    Vector2(o + 4, o + 4), Vector2(o + 4, o + 10), Vector2(o, o + 10)])
                drawer.drawCircle(o, o, 5)
            }
            drawer.withTarget(layer) { marks(0) }
            if canvasBetweenLayers { marks(30) }
            drawer.withTarget(layer) { marks(10) }
            if canvasBetweenLayers { marks(40) }
            drawer.background(.black)
            return drawer
        }
        let wiped = record(canvasBetweenLayers: true), plain = record(canvasBetweenLayers: false)
        #expect(wiped.batches.map(\.kind) == plain.batches.map(\.kind))
        #expect(wiped.batches.map(\.vertexStart) == plain.batches.map(\.vertexStart))
        #expect(wiped.batches.map(\.instanceStart) == plain.batches.map(\.instanceStart))
        #expect(wiped.batches.allSatisfy { $0.target != nil })
        #expect(bytes(wiped.vertices) == bytes(plain.vertices))
        #expect(bytes(wiped.sdfInstances) == bytes(plain.sdfInstances))
        #expect(!plain.webSources.isEmpty)
        #expect(wiped.webSources.map(\.vertexRange) == plain.webSources.map(\.vertexRange))
        #expect(wiped.webSources.map(\.points) == plain.webSources.map(\.points))
    }

    private func bytes<T>(_ list: [T]) -> [UInt8] {
        list.withUnsafeBytes { Array($0) }
    }

    /// A background inside a layer still clears that layer alone and leaves
    /// the canvas's marks where they are.
    @Test func aBackgroundInsideALayerClearsOnlyThatLayer() throws {
        let p = Pixels(try OllinApp.image(of: LayerWipe(), frame: 1))
        #expect(p.gray(10, 10) < 30, "the wiped layer's square reads \(p.gray(10, 10))")
        #expect(p.gray(54, 54) > 200, "the canvas's square reads \(p.gray(54, 54))")
    }
}

/// Where a probe sets the canvas background against its layers.
private enum DrawOrder { case backgroundFirst, layersOnly, canvasBetweenLayers, noLayers }

@MainActor
private final class SeededField: Sketch {
    static let block = [(20, 20), (21, 20), (20, 21), (21, 21)]
    var backgroundFirst = false
    private var field: SimField!

    static func make(backgroundFirst: Bool) -> SeededField {
        let sketch = SeededField()
        sketch.backgroundFirst = backgroundFirst
        return sketch
    }

    override var canvasSize: CanvasSize { .square(48) }
    override func setup() { field = makeSimField(.gameOfLife(), scale: 1) }
    override func draw() {
        if backgroundFirst { background(.black) }
        withField(field) {
            noStroke()
            fill(.white)
            // Polygons, whose coverage is geometric, so each stamped texel is
            // exactly alive and its neighbors exactly not.
            for (x, y) in Self.block {
                let x = Double(x), y = Double(y)
                drawPolygon([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
            }
        }
        if !backgroundFirst { background(.black) }
        drawImage(field.image, 0, 0)
    }
}

/// Each flat kind once per call, offset so no two calls overlap: an SDF disc,
/// a concave polygon, a stroked line, an image, atlas text, and a smooth union.
@MainActor
private final class FlatKinds: Sketch {
    var order = DrawOrder.layersOnly
    private let swatch = Image(width: 4, height: 4,
                               premultipliedRGBA: (0 ..< 16).flatMap { [UInt8($0 * 16), 80, 200, 255] })!

    static func make(_ order: DrawOrder) -> FlatKinds {
        let sketch = FlatKinds()
        sketch.order = order
        return sketch
    }

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        let gray = Color(white: 0.2)
        if order == .backgroundFirst { background(gray) }
        let first = makeRenderTarget(), second = makeRenderTarget()
        if order != .noLayers { withTarget(first) { background(.black); marks(at: 0) } }
        if order == .canvasBetweenLayers { marks(at: 64) }
        if order != .noLayers { withTarget(second) { marks(at: 32) } }
        if order == .canvasBetweenLayers { marks(at: 96) }
        if order != .backgroundFirst { background(gray) }
        if order != .noLayers {
            drawImage(first.image, 0, 0, 64, 64)
            drawImage(second.image, 0, 0)
        }
        marks(at: 80)
    }

    private func marks(at o: Double) {
        noStroke()
        fill(.white)
        drawCircle(10 + o, 10 + o, 6)
        fill(Color(red: 0.9, green: 0.4, blue: 0.1))
        drawPolygon([Vector2(o, 20 + o), Vector2(o + 12, 20 + o), Vector2(o + 12, 24 + o),
                     Vector2(o + 4, 24 + o), Vector2(o + 4, 30 + o), Vector2(o, 30 + o)])
        stroke(Color(red: 0.2, green: 0.8, blue: 0.4))
        strokeWeight(2)
        drawLine(o + 16, o + 2, o + 28, o + 14)
        noStroke()
        drawImage(swatch, o + 16, o + 18, 8, 8)
        textMode(.atlas)
        fill(.white)
        drawText("Ag", o + 2, o + 6, size: 10)
        textMode(.outline)
        fill(Color(red: 0.3, green: 0.5, blue: 1))
        smoothUnion(k: 3) {
            drawCircle(o + 24, o + 26, 3)
            drawCircle(o + 28, o + 26, 3)
        }
    }
}

/// Each kind a camera draws once per call, offset along x.
@MainActor
private final class SpatialKinds: Sketch {
    var order = DrawOrder.layersOnly
    var drawsVolume = true

    static func make(_ order: DrawOrder) -> SpatialKinds {
        let sketch = SpatialKinds()
        sketch.order = order
        return sketch
    }

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        let gray = Color(white: 0.2)
        if order == .backgroundFirst { background(gray) }
        perspective(eye: Vector3(0, 3, 9))
        let first = makeRenderTarget(), second = makeRenderTarget()
        // The layers' distance fields are longer programs than the canvas's,
        // so a field left pointing past the canvas's nodes reads the middle
        // of its own program rather than a copy of it.
        if order != .noLayers { withTarget(first) { background(.black); solids(at: -2, parts: 3) } }
        if order == .canvasBetweenLayers { solids(at: 2, parts: 1) }
        if order != .noLayers { withTarget(second) { solids(at: 0, parts: 3) } }
        if order == .canvasBetweenLayers { solids(at: -1, parts: 1) }
        if order != .backgroundFirst { background(gray) }
        if order != .noLayers {
            drawImage(first.image, 0, 0)
            drawImage(second.image, 0, 0)
        }
        solids(at: 3, parts: 2)
    }

    private func solids(at x: Double, parts: Int) {
        withState {
            translate(Vector3(x, 0, 0))
            noStroke()
            fill(.white)
            drawMesh(.box(size: 0.6))
            stroke(.black)
            strokeWeight(1.5)
            featureEdges(creaseAngle: 30)
            fill(Color(red: 0.9, green: 0.5, blue: 0.2))
            drawMesh(.box(size: 0.25), instances: [MeshInstance(position: Vector3(0, 1, 0)),
                                                    MeshInstance(position: Vector3(0, -1, 0))])
            noFeatureEdges()
            stroke(Color(red: 0.2, green: 0.9, blue: 0.5))
            drawLine(Vector3(0, -1.5, 0), Vector3(0, 1.5, 0))
            noStroke()
            drawPointCloud(PointCloud(positions: [Vector3(0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
                                      color: .red, size: 0.08))
            var field = SDF3D.sphere(radius: 0.3).at(0, 0, 1)
            for part in 1 ..< parts {
                field = field.union(SDF3D.sphere(radius: 0.15).at(0.3 * Double(part), 0, 1))
            }
            drawSDF3D(field)
            if drawsVolume {
                translate(Vector3(0, 0, -1))
                drawVolume(Volume(width: 8, height: 8, depth: 8, repeating: 1), size: 0.8)
            }
        }
    }
}

/// A square on the canvas, then a layer that draws a square and wipes it.
@MainActor
private final class LayerWipe: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        drawRect(48, 48, 12, 12)
        let layer = makeRenderTarget()
        withTarget(layer) {
            fill(.white)
            drawRect(0, 0, 20, 20)
            background(.clear)
        }
        drawImage(layer.image, 0, 0)
    }
}
