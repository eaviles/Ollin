import Foundation
import Metal
import Testing
@testable import Ollin

/// Whether this machine has a GPU to present against. Read before the suite's
/// actor is entered, so it sits outside.
private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// Probes for a piece fitted to the wall it is thrown onto.
///
/// The map is arithmetic, so it is checked as arithmetic: the corners land where
/// they were put, and the map undoes itself. The two claims that would actually
/// ruin a wall are checked on pixels instead, because neither can be read off
/// the source. The picture must arrive the right way up and the right way round,
/// which a flipped coordinate would still let every corner test pass. And two
/// machines fading into each other must add up to exactly one coat, which is the
/// whole reason the fade is applied to light rather than to a code value.
@Suite
@MainActor
struct ProjectionTests {

    // MARK: The map

    /// A picture thrown from below and to the left: the far edge crowds
    /// together, the near one spreads.
    private static let keystone = [Vector2(0.18, 0.06), Vector2(0.92, 0.02),
                                   Vector2(0.97, 0.95), Vector2(0.05, 0.88)]

    private static func map(_ points: [Vector2]) -> Homography {
        guard let map = Homography(unitSquareTo: points[0], points[1], points[2], points[3]) else {
            Issue.record("the four corners made no shape with an inside")
            return Homography(unitSquareTo: Vector2(0, 0), Vector2(1, 0),
                              Vector2(1, 1), Vector2(0, 1))!
        }
        return map
    }

    @Test func theCornersLandWhereTheyWerePut() {
        let map = Self.map(Self.keystone)
        let square = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
        for (corner, target) in zip(square, Self.keystone) {
            let landed = map.map(corner)
            #expect(abs(landed.x - target.x) < 1e-9)
            #expect(abs(landed.y - target.y) < 1e-9)
        }
    }

    @Test func theMapUndoesItself() {
        let map = Self.map(Self.keystone)
        for u in stride(from: 0.0, through: 1.0, by: 0.125) {
            for v in stride(from: 0.0, through: 1.0, by: 0.125) {
                let there = map.map(Vector2(u, v))
                let back = map.unmap(there)
                #expect(abs(back.x - u) < 1e-9)
                #expect(abs(back.y - v) < 1e-9)
            }
        }
    }

    /// A shape with parallel sides has no perspective in it, and the general
    /// equations divide by zero for one. It takes its own path, so the middle of
    /// the square has to land in the middle of the shape.
    @Test func aParallelogramTakesItsOwnPath() {
        let map = Self.map([Vector2(0.1, 0.1), Vector2(0.7, 0.1),
                            Vector2(0.9, 0.6), Vector2(0.3, 0.6)])
        let middle = map.map(Vector2(0.5, 0.5))
        #expect(abs(middle.x - 0.5) < 1e-9)
        #expect(abs(middle.y - 0.35) < 1e-9)
    }

    /// A shape with no inside has no map back, and a run must not carry a matrix
    /// full of infinities.
    @Test func aFlatShapeHasNoMap() {
        #expect(Homography(unitSquareTo: Vector2(0, 0), Vector2(0.5, 0),
                           Vector2(1, 0), Vector2(0.5, 0)) == nil)
        #expect(Homography(unitSquareTo: Vector2(0.2, 0.2), Vector2(0.2, 0.2),
                           Vector2(0.2, 0.2), Vector2(0.2, 0.2)) == nil)
    }

    // MARK: What a fitted picture works out to

    @Test func aFitPictureKeepsItsProportions() {
        // A square canvas on a wide display: full height, centered, with a
        // quarter of the width dark on each side.
        let corners = Installation.Projection.Corners.fit
            .resolved(outputAspect: 2, pictureAspect: 1)
        #expect(abs(corners[0].x - 0.25) < 1e-12)
        #expect(abs(corners[0].y - 0) < 1e-12)
        #expect(abs(corners[2].x - 0.75) < 1e-12)
        #expect(abs(corners[2].y - 1) < 1e-12)
    }

    @Test func aFitPictureFillsAMatchingDisplay() {
        let corners = Installation.Projection.Corners.fit
            .resolved(outputAspect: 1.5, pictureAspect: 1.5)
        #expect(corners == [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
    }

    /// The fade is declared in canvas fractions, the same units as the part this
    /// machine shows, so that two machines are told the same number. The map
    /// runs in fractions of that part, so it has to be converted on the way in.
    @Test func theFadeIsMeasuredAgainstTheShownPart() throws {
        let projection = Installation.Projection(
            shows: Rectangle(x: 0, y: 0, width: 0.5, height: 1),
            blend: Insets(right: 0.1))
        let placement = try #require(ProjectionPlacement(projection,
                                                         canvas: Vector2(1000, 1000),
                                                         output: Vector2(1000, 1000)))
        #expect(abs(placement.fade.right - 0.2) < 1e-12)
        #expect(placement.fade.left == 0)
    }

    @Test func theStandardCurveNeedsNoCorrection() throws {
        let plain = try #require(ProjectionPlacement(Installation.Projection(),
                                                     canvas: Vector2(100, 100),
                                                     output: Vector2(100, 100)))
        #expect(abs(plain.gammaExponent - 1) < 1e-12)
        let dim = try #require(ProjectionPlacement(Installation.Projection(gamma: 1.1),
                                                   canvas: Vector2(100, 100),
                                                   output: Vector2(100, 100)))
        #expect(abs(dim.gammaExponent - 2) < 1e-12)
    }

    /// The pointer takes the warp backwards, or a piece being lined up reads a
    /// mouse somewhere else entirely.
    @Test func thePointerComesBackThroughTheWarp() throws {
        let projection = Installation.Projection(
            shows: Rectangle(x: 0.5, y: 0, width: 0.5, height: 1),
            corners: Installation.Projection.Corners(topLeft: Vector2(0, 0),
                                                     topRight: Vector2(0.5, 0),
                                                     bottomRight: Vector2(0.5, 1),
                                                     bottomLeft: Vector2(0, 1)))
        let placement = try #require(ProjectionPlacement(projection,
                                                         canvas: Vector2(1000, 1000),
                                                         output: Vector2(1000, 1000)))
        // The middle of the left half of the display is the middle of the right
        // half of the canvas.
        let middle = placement.canvasPoint(fromOutput: Vector2(0.25, 0.5))
        #expect(abs(middle.x - 0.75) < 1e-9)
        #expect(abs(middle.y - 0.5) < 1e-9)
    }

    /// A described part follows the picture onto the wall. A screen reader is
    /// handed a rectangle, so a warped part comes back as the box around it.
    @Test func aDescribedPartFollowsThePictureOntoTheWall() throws {
        let projection = Installation.Projection(
            corners: .init(topLeft: Vector2(0, 0), topRight: Vector2(0.5, 0),
                           bottomRight: Vector2(0.5, 1), bottomLeft: Vector2(0, 1)))
        let placement = try #require(ProjectionPlacement(projection,
                                                         canvas: Vector2(1000, 1000),
                                                         output: Vector2(1000, 1000)))
        let part = Rectangle(x: 400, y: 400, width: 200, height: 200)
        let box = viewRect(of: part, canvasWidth: 1000, canvasHeight: 1000,
                           in: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                           through: placement)
        // Half as wide, since the picture is; the same height; and the view
        // counts y up from the bottom where the canvas counts it down.
        #expect(abs(box.minX - 200) < 1e-9)
        #expect(abs(box.width - 100) < 1e-9)
        #expect(abs(box.minY - 400) < 1e-9)
        #expect(abs(box.height - 200) < 1e-9)
    }

    // MARK: The corners between runs

    @Test func theCornersSurviveTheirFile() throws {
        try withCalibrationDirectory { key in
            let corners = Installation.Projection.Corners(
                topLeft: Vector2(0.02, 0.01), topRight: Vector2(0.98, 0.03),
                bottomRight: Vector2(0.95, 0.99), bottomLeft: Vector2(0.05, 0.97))
            #expect(ProjectionCalibration.save(corners, forDisplay: key,
                                               displaySize: CGSize(width: 1920, height: 1080)))
            #expect(ProjectionCalibration.corners(forDisplay: key) == corners)
        }
    }

    @Test func anUnknownDisplayHasNoCorners() throws {
        try withCalibrationDirectory { _ in
            #expect(ProjectionCalibration.corners(forDisplay: "nothing-here") == nil)
        }
    }

    /// Nothing about reading the file may stop a piece from starting. The rule
    /// the checkpoint keeps, for the same reason: the alternative is a gallery
    /// wall that stays dark over a file nobody can see.
    @Test func aRuinedFileIsSkippedRatherThanTrusted() throws {
        try withCalibrationDirectory { key in
            let url = try #require(ProjectionCalibration.url(forDisplay: key))
            try Data("not json at all".utf8).write(to: url)
            #expect(ProjectionCalibration.corners(forDisplay: key) == nil)
        }
    }

    @Test func aFileFromAnOlderOllinIsSkipped() throws {
        try withCalibrationDirectory { key in
            let url = try #require(ProjectionCalibration.url(forDisplay: key))
            let older = """
            {"version":0,"savedAt":"2026-01-01T00:00:00Z","displayWidth":1920,\
            "displayHeight":1080,"corners":{"points":[]}}
            """
            try Data(older.utf8).write(to: url)
            #expect(ProjectionCalibration.corners(forDisplay: key) == nil)
        }
    }

    private func withCalibrationDirectory(_ body: (String) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-calibration-\(UUID().uuidString)")
        ProjectionCalibration.directoryOverride = directory
        defer {
            ProjectionCalibration.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try body("test-display")
    }

    // MARK: The handles

    /// A hand on the handles moves what the run is fitted with, and the first
    /// drag turns a fitted picture into its own four numbers. The gesture itself
    /// is SwiftUI's; everything under it is here.
    @Test func draggingACornerFitsThePictureToIt() {
        let calibrator = ProjectionCalibrator(projection: .direct, canvas: Vector2(1000, 1000),
                                              displayKey: "test-display", hidesPointer: false)
        let display = CGSize(width: 2000, height: 1000)
        #expect(calibrator.projection.corners.isFit)
        calibrator.move(0, to: Vector2(0.1, 0.1), output: display)
        #expect(!calibrator.projection.corners.isFit)

        let corners = calibrator.corners(output: display)
        #expect(corners[0] == Vector2(0.1, 0.1))
        // The other three stay where the fit put them: a square canvas on a
        // display twice as wide fills the height and half the width.
        #expect(corners[1] == Vector2(0.75, 0))
        #expect(corners[3] == Vector2(0.25, 1))
    }

    @Test func aNudgeIsMeasuredInPointsOnTheDisplay() {
        let calibrator = ProjectionCalibrator(projection: .direct, canvas: Vector2(1000, 1000),
                                              displayKey: "test-display", hidesPointer: false)
        let display = CGSize(width: 2000, height: 1000)
        calibrator.outputSize = display
        calibrator.move(2, to: Vector2(0.7, 0.9), output: display)
        calibrator.nudge(by: Vector2(10, -5))
        let moved = calibrator.corners(output: display)[2]
        #expect(abs(moved.x - 0.705) < 1e-12)      // ten points across two thousand
        #expect(abs(moved.y - 0.895) < 1e-12)      // five up across one thousand
    }

    /// A hand dragging one corner past another makes a shape with no inside for
    /// a moment. There is no map through it, and the handles have to stay under
    /// the fingers holding them: reading them back through the map instead would
    /// throw all four across the display.
    @Test func aFoldedShapeKeepsItsHandlesWhereTheHandPutThem() {
        let calibrator = ProjectionCalibrator(projection: .direct, canvas: Vector2(1000, 1000),
                                              displayKey: "test-display", hidesPointer: false)
        let display = CGSize(width: 2000, height: 1000)
        // Three of the four in a line: no inside, and no map.
        calibrator.move(2, to: Vector2(0.5, 0.5), output: display)
        #expect(calibrator.placement(output: display) == nil)
        #expect(calibrator.corners(output: display)[2] == Vector2(0.5, 0.5))
        // And the way back out is an ordinary drag.
        calibrator.move(2, to: Vector2(0.7, 0.9), output: display)
        #expect(calibrator.placement(output: display) != nil)
    }

    @Test func squaringUpPutsThePictureBack() {
        let calibrator = ProjectionCalibrator(projection: .direct, canvas: Vector2(1000, 1000),
                                              displayKey: "test-display", hidesPointer: false)
        calibrator.move(1, to: Vector2(0.6, 0.2), output: CGSize(width: 1000, height: 1000))
        calibrator.reset()
        #expect(calibrator.projection.corners.isFit)
    }

    /// Closing the handles keeps them, because the alternative is dragging a
    /// wall square twice.
    @Test func closingTheHandlesKeepsTheCorners() throws {
        try withCalibrationDirectory { key in
            let calibrator = ProjectionCalibrator(projection: .direct, canvas: Vector2(1000, 1000),
                                                  displayKey: key, hidesPointer: false)
            calibrator.outputSize = CGSize(width: 1000, height: 1000)
            calibrator.open()
            calibrator.move(0, to: Vector2(0.03, 0.04), output: calibrator.outputSize)
            calibrator.close()
            let kept = ProjectionCalibration.corners(forDisplay: key)
            #expect(kept?.isFit == false)
        }
    }

    // MARK: On pixels

    /// The picture arrives the right way up and the right way round.
    ///
    /// Every claim above would still pass with the picture mirrored, so this one
    /// hands the present pass a canvas whose four quarters are four colors and
    /// reads them back out of the corners of the warped picture. It also reads a
    /// point well outside the shape, which has to be black: a projector must
    /// light only what it was aimed at.
    @Test(.enabled(if: hasMetal))
    func theWarpedPictureKeepsItsCornersInOrder() throws {
        let wall = try Wall()
        // Tilted, and nowhere near the edges of the display, so "outside" is
        // unambiguous.
        let corners = Installation.Projection.Corners(
            topLeft: Vector2(0.2, 0.12), topRight: Vector2(0.86, 0.2),
            bottomRight: Vector2(0.8, 0.9), bottomLeft: Vector2(0.14, 0.82))
        let pixels = try wall.present(Installation.Projection(corners: corners))
        let placement = try #require(wall.placement(Installation.Projection(corners: corners)))

        // A little way in from each corner of the picture, which is where that
        // quarter of the canvas is.
        func inside(_ u: Double, _ v: Double) -> (Double, Double, Double) {
            let p = placement.homography.map(Vector2(u, v))
            return pixels.at(p)
        }
        let topLeft = inside(0.15, 0.15)
        #expect(topLeft.0 > 0.5 && topLeft.1 < 0.2 && topLeft.2 < 0.2, "top left should be red")
        let topRight = inside(0.85, 0.15)
        #expect(topRight.1 > 0.5 && topRight.0 < 0.2 && topRight.2 < 0.2, "top right should be green")
        let bottomRight = inside(0.85, 0.85)
        #expect(bottomRight.2 > 0.5 && bottomRight.0 < 0.2, "bottom right should be blue")
        let bottomLeft = inside(0.15, 0.85)
        #expect(bottomLeft.0 > 0.5 && bottomLeft.1 > 0.5 && bottomLeft.2 > 0.5,
                "bottom left should be white")

        // Outside the shape: unlit.
        let outside = pixels.at(Vector2(0.03, 0.03))
        #expect(outside.0 < 0.02 && outside.1 < 0.02 && outside.2 < 0.02)
    }

    /// Two machines fading into each other add up to one coat.
    ///
    /// The left one carries the left three fifths of the canvas onto the left
    /// three fifths of the wall, the right one the mirror of that, and they
    /// share a fifth in the middle. Across that shared band neither is at full
    /// brightness, and the sum of the light they make has to be flat: this is
    /// the whole reason the fade is applied while the frame is still linear.
    ///
    /// Measured in light rather than in the bytes, since the two are not the
    /// same distance apart. Reading the bytes would say the middle of the band
    /// is far too dark, which is exactly the mistake the fade is avoiding.
    @Test(.enabled(if: hasMetal))
    func twoMachinesFadingIntoEachOtherMakeOneCoat() throws {
        let wall = try Wall(canvas: .white)
        let left = try wall.present(Installation.Projection(
            shows: Rectangle(x: 0, y: 0, width: 0.6, height: 1),
            corners: .init(topLeft: Vector2(0, 0), topRight: Vector2(0.6, 0),
                           bottomRight: Vector2(0.6, 1), bottomLeft: Vector2(0, 1)),
            blend: Insets(right: 0.2)))
        let right = try wall.present(Installation.Projection(
            shows: Rectangle(x: 0.4, y: 0, width: 0.6, height: 1),
            corners: .init(topLeft: Vector2(0.4, 0), topRight: Vector2(1, 0),
                           bottomRight: Vector2(1, 1), bottomLeft: Vector2(0.4, 1)),
            blend: Insets(left: 0.2)))

        // Across the shared band, well inside it on both sides.
        for step in 0...20 {
            let x = 0.41 + 0.18 * Double(step) / 20
            let a = left.at(Vector2(x, 0.5)).0
            let b = right.at(Vector2(x, 0.5)).0
            let coat = a + b
            #expect(abs(coat - 1) < 0.03,
                    "at \(x) the two beams made \(coat) coats, not one")
        }
        // And the fade is a fade: each machine really does give up its half.
        #expect(left.at(Vector2(0.42, 0.5)).0 > left.at(Vector2(0.58, 0.5)).0)
        #expect(right.at(Vector2(0.42, 0.5)).0 < right.at(Vector2(0.58, 0.5)).0)
    }

    /// Every display of a wall carries its own part of the canvas.
    ///
    /// One machine driving several displays presents the same frame once per
    /// display, and each one has to arrive through its own placement. The claim
    /// cannot be read off the source, because reading the run's own placement
    /// instead compiles, runs, and puts the same part on every beam. So the run
    /// here is fitted to the right half while the left half is asked for: the
    /// left display must come back red over white, which is the left of the
    /// canvas, and never green over blue.
    @Test(.enabled(if: hasMetal))
    func everyDisplayCarriesItsOwnPart() throws {
        let wall = try Wall()
        let left = Installation.Projection(shows: Rectangle(x: 0, y: 0, width: 0.5, height: 1),
                                           corners: .filling)
        let right = Installation.Projection(shows: Rectangle(x: 0.5, y: 0, width: 0.5, height: 1),
                                            corners: .filling)

        let onTheLeft = try wall.present(part: left, whileFittedTo: right)
        let topLeft = onTheLeft.at(Vector2(0.5, 0.25))
        #expect(topLeft.0 > 0.5 && topLeft.1 < 0.2 && topLeft.2 < 0.2,
                "the left display should carry the red quarter, not \(topLeft)")
        let bottomLeft = onTheLeft.at(Vector2(0.5, 0.75))
        #expect(bottomLeft.0 > 0.5 && bottomLeft.1 > 0.5 && bottomLeft.2 > 0.5,
                "the left display should carry the white quarter, not \(bottomLeft)")

        let onTheRight = try wall.present(part: right, whileFittedTo: left)
        let topRight = onTheRight.at(Vector2(0.5, 0.25))
        #expect(topRight.1 > 0.5 && topRight.0 < 0.2 && topRight.2 < 0.2,
                "the right display should carry the green quarter, not \(topRight)")
        let bottomRight = onTheRight.at(Vector2(0.5, 0.75))
        #expect(bottomRight.2 > 0.5 && bottomRight.0 < 0.2,
                "the right display should carry the blue quarter, not \(bottomRight)")
    }

    /// A file has no wall to fit, so nothing here reaches one. The flag rides
    /// the two paths that present into a drawable, and an export re-renders the
    /// canvas through the plain pass whatever the run is fitted with.
    @Test(.enabled(if: hasMetal))
    func anExportIsNeverWarped() throws {
        let wall = try Wall(canvas: .white)
        let plain = try #require(wall.exported())
        wall.renderer.projection = wall.placement(Installation.Projection(
            corners: .init(topLeft: Vector2(0.2, 0.2), topRight: Vector2(0.8, 0.1),
                           bottomRight: Vector2(0.9, 0.9), bottomLeft: Vector2(0.1, 0.8))))
        let fitted = try #require(wall.exported())
        #expect(plain == fitted, "the warp reached an export")
    }

    // MARK: Presenting one frame off screen

    /// One canvas, one display-sized texture, and the same present the window
    /// runs. Nothing here is a test-only path: it is `encodePresent` with the
    /// flag the drawable paths pass it.
    @MainActor
    private struct Wall {

        /// What the canvas holds: four colored quarters, or plain white for
        /// measuring a fade.
        enum Canvas { case quarters, white }

        let device: MTLDevice
        let renderer: MetalRenderer
        let sketch = Sketch()
        let source: MTLTexture
        static let displaySize = 240

        init(canvas: Canvas = .quarters) throws {
            device = try #require(MTLCreateSystemDefaultDevice())
            renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device),
                                         encoding: .srgb8)
            source = try Wall.makeCanvas(canvas, device: device)
        }

        func placement(_ projection: Installation.Projection) -> ProjectionPlacement? {
            ProjectionPlacement(projection, canvas: Vector2(64, 64),
                                output: Vector2(Double(Wall.displaySize), Double(Wall.displaySize)))
        }

        /// Present the canvas once through the projected pass and read the
        /// display back.
        func present(_ projection: Installation.Projection) throws -> Pixels {
            renderer.projection = placement(projection)
            let display = try Wall.makeDisplay(device: device, format: renderer.pixelFormat)
            let buffer = try #require(renderer.commandQueue.makeCommandBuffer())
            let pass = renderer.presentPass(into: display)
            let encoder = try #require(buffer.makeRenderCommandEncoder(descriptor: pass))
            renderer.encodePresent(from: source, drawer: sketch.drawer,
                                   into: encoder, projected: true)
            encoder.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
            return Pixels(display)
        }

        /// Present the canvas onto one display of a wall: the part travels with
        /// the display, while the run's own fitting is another display's.
        ///
        /// That is exactly the arrangement a wall is in, and the one that tells
        /// the two apart: reading the run's own placement would put the same
        /// part of the canvas on every beam.
        func present(part: Installation.Projection,
                     whileFittedTo other: Installation.Projection) throws -> Pixels {
            renderer.projection = placement(other)
            let display = try Wall.makeDisplay(device: device, format: renderer.pixelFormat)
            let buffer = try #require(renderer.commandQueue.makeCommandBuffer())
            let pass = renderer.presentPass(into: display)
            let encoder = try #require(buffer.makeRenderCommandEncoder(descriptor: pass))
            renderer.encodePresent(from: source, drawer: sketch.drawer, into: encoder,
                                   projected: true, placement: placement(part))
            encoder.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
            return Pixels(display)
        }

        /// The same canvas through the path an export takes, as bytes.
        func exported() -> Data? {
            guard let image = renderer.image(of: sketch.drawer,
                                             viewport: SIMD2<Float>(64, 64),
                                             width: 64, height: 64),
                  let data = image.dataProvider?.data else { return nil }
            return data as Data
        }

        private static func makeCanvas(_ kind: Canvas, device: MTLDevice) throws -> MTLTexture {
            let side = 64
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: side, height: side, mipmapped: false)
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            let texture = try #require(device.makeTexture(descriptor: descriptor))
            var texels = [Float16](repeating: 1, count: side * side * 4)
            if kind == .quarters {
                for y in 0..<side {
                    for x in 0..<side {
                        // Red, green, blue, white, clockwise from the top left.
                        let color: (Float16, Float16, Float16)
                        switch (x < side / 2, y < side / 2) {
                        case (true, true):   color = (1, 0, 0)
                        case (false, true):  color = (0, 1, 0)
                        case (false, false): color = (0, 0, 1)
                        case (true, false):  color = (1, 1, 1)
                        }
                        let at = (y * side + x) * 4
                        texels[at] = color.0
                        texels[at + 1] = color.1
                        texels[at + 2] = color.2
                        texels[at + 3] = 1
                    }
                }
            }
            texels.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                                withBytes: bytes.baseAddress!, bytesPerRow: side * 8)
            }
            return texture
        }

        private static func makeDisplay(device: MTLDevice,
                                        format: MTLPixelFormat) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: displaySize, height: displaySize, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            return try #require(device.makeTexture(descriptor: descriptor))
        }
    }

    /// A presented display, read back as light. The bytes are sRGB, and the
    /// question every fade asks is about light, so they are converted once here
    /// rather than at each reading.
    private struct Pixels {
        let width: Int, height: Int
        private let light: [Double]      // three per pixel

        init(_ texture: MTLTexture) {
            let width = texture.width, height = texture.height
            self.width = width
            self.height = height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: width * 4,
                                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            let blueFirst = texture.pixelFormat == .bgra8Unorm_srgb
                || texture.pixelFormat == .bgra8Unorm
            var light = [Double](repeating: 0, count: width * height * 3)
            for pixel in 0..<(width * height) {
                let b0 = Double(bytes[pixel * 4]) / 255
                let b1 = Double(bytes[pixel * 4 + 1]) / 255
                let b2 = Double(bytes[pixel * 4 + 2]) / 255
                let rgb = blueFirst ? (b2, b1, b0) : (b0, b1, b2)
                light[pixel * 3] = Pixels.toLight(rgb.0)
                light[pixel * 3 + 1] = Pixels.toLight(rgb.1)
                light[pixel * 3 + 2] = Pixels.toLight(rgb.2)
            }
            self.light = light
        }

        /// The light at a point given in fractions of the display.
        func at(_ point: Vector2) -> (Double, Double, Double) {
            let x = min(max(Int(point.x * Double(width)), 0), width - 1)
            let y = min(max(Int(point.y * Double(height)), 0), height - 1)
            let at = (y * width + x) * 3
            return (light[at], light[at + 1], light[at + 2])
        }

        private static func toLight(_ encoded: Double) -> Double {
            encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
    }
}
