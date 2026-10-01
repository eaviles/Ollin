@testable import Ollin
import AppKit
import Foundation
import ImageIO
import Metal
import MetalKit
import QuartzCore
import Testing
import UniformTypeIdentifiers

/// The small things a sketch asks of its window, and the one question it asks
/// of an export. `redraw()` wakes a still sketch for exactly one frame and
/// hands the pause back; `isExporting` is true through every headless drive
/// that writes what it draws and false in a window and a benchmark; the
/// pointer's shape and hiding reach the canvas view, apart from each other,
/// and follow a reload; a pick from the open panel arrives the way a drop
/// does; `copyFrame()` puts the frame the window shows on a pasteboard as a
/// PNG; and `spherical` and a vector's angles undo each other and agree with
/// the camera's own orbit.
@Suite
@MainActor
struct SketchConvenienceTests {

    // MARK: A live runner on a view with no window

    /// A headless view of `side` pixels that the test turns by hand: each
    /// `runner.draw(in:)` is one refresh, and `isPaused` says whether the
    /// display timer would ask for another.
    private func makeView(_ device: MTLDevice, side: Int, for sketch: Sketch) -> OllinMTKView {
        let view = makeOllinMTKView(device: device, size: CGSize(width: side, height: side), sketch: sketch)
        view.drawableSize = CGSize(width: side, height: side)
        view.isPaused = true
        return view
    }

    /// Run the refreshes the display timer would run while the view is
    /// unpaused, and say how many there were (stopping at `limit`).
    @discardableResult
    private func runWhileAwake(_ runner: SketchRunner, _ view: MTKView, limit: Int = 12) -> Int {
        var refreshes = 0
        while !view.isPaused, refreshes < limit {
            runner.draw(in: view)
            refreshes += 1
        }
        return refreshes
    }

    /// Turn the run loop until `done`, or ten seconds pass. A frame grab is
    /// delivered on the run loop, so it has to turn; the probe comes before
    /// the clock, so a late wakeup still finds what it waited for.
    private func spin(until done: () -> Bool) {
        let deadline = CACurrentMediaTime() + 10
        while !done() {
            if CACurrentMediaTime() > deadline { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    /// A still sketch that counts its frames, and can ask for one more from
    /// inside `draw()`.
    final class Still: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        var draws = 0
        var redrawsInsideDraw = false
        override func setup() { noLoop() }
        override func draw() {
            draws += 1
            background(.black)
            noStroke()
            fill(Color(red: 0.9, green: 0.4, blue: 0.2))
            drawCircle(32, 32, 20)
            if redrawsInsideDraw { redraw() }
        }
    }

    // MARK: redraw()

    @Test(.enabled(if: Snapshot.hasMetal))
    func redrawDrawsExactlyOneFrameOfAStillSketch() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Still()
        let view = makeView(device, side: 64, for: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        view.isPaused = false
        #expect(runWhileAwake(runner, view) == 1, "a still sketch draws its first frame and holds")
        #expect(sketch.draws == 1)

        sketch.redraw()
        #expect(!view.isPaused, "redraw wakes the display timer")
        #expect(runWhileAwake(runner, view) == 1, "and it sleeps again after one frame")
        #expect(sketch.draws == 2)

        // Several asks before the frame is drawn are one frame.
        sketch.redraw()
        sketch.redraw()
        sketch.redraw()
        #expect(runWhileAwake(runner, view) == 1)
        #expect(sketch.draws == 3)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRedrawInsideDrawAsksForNothingMore() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Still()
        sketch.redrawsInsideDraw = true
        let view = makeView(device, side: 64, for: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        view.isPaused = false
        #expect(runWhileAwake(runner, view) == 1, "the frame being drawn is the one asked for")
        sketch.redraw()
        #expect(runWhileAwake(runner, view) == 1)
        #expect(sketch.draws == 2)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func redrawPassesTheTimelineHoldWithTheClockStill() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Still()
        let view = makeView(device, side: 64, for: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.isPaused = false
        runWhileAwake(runner, view)
        runner.setClockPaused(true)
        let held = sketch.time

        sketch.redraw()
        #expect(runWhileAwake(runner, view) == 1)
        #expect(sketch.draws == 2, "a held clock still lets the asked-for frame through")
        #expect(sketch.time == held, "under a hold the frame is drawn at the held time")
    }

    @Test func redrawDoesNothingWhileLoopingOrWithNothingShowingTheSketch() throws {
        let loose = Still()
        loose.redraw()   // no runner: an export, a test with no window

        let device = try #require(MTLCreateSystemDefaultDevice())
        let looping = Sketch()
        let view = makeView(device, side: 32, for: looping)
        let runner = SketchRunner(sketch: looping, view: view, device: device)
        _ = runner
        looping.redraw()
        #expect(view.isPaused, "a looping sketch's next frame is coming anyway")
    }

    // MARK: isExporting

    /// Writes down what `isExporting` said in `setup()` and in every `draw()`.
    final class ExportProbe: Sketch {
        override var canvasSize: CanvasSize { .square(32) }
        var seen: [Bool] = []
        override func setup() { seen.append(isExporting) }
        override func draw() {
            seen.append(isExporting)
            background(.black)
            noStroke()
            fill(.white)
            drawCircle(16, 16, 8)
        }
    }

    private func temporaryPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-isExporting-\(UUID().uuidString)-\(name)").path
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func isExportingIsTrueThroughEveryDriveThatWritesItsFrames() throws {
        var drives: [(String, [Bool])] = []

        let still = ExportProbe()
        _ = try OllinApp.image(of: still, frame: 3)
        drives.append(("a still", still.seen))

        let frames = ExportProbe()
        _ = try OllinApp.renderFrames(frames, frames: 3, fps: 30, skipSeconds: 0) { _, _ in }
        drives.append(("a sequence, a video, a GIF", frames.seen))

        let vector = ExportProbe()
        _ = OllinApp.recordVectorFrame(of: vector, frame: 2, fps: 30, hatching: nil)
        drives.append(("a vector file", vector.seen))

        let spatial = ExportProbe()
        _ = OllinApp.recordSpatialFrame(of: spatial, frame: 2, fps: 30)
        drives.append(("a 3D file", spatial.seen))

        let web = ExportProbe()
        _ = try OllinApp.recordWebFrames(of: web, frames: 2, fps: 30)
        drives.append(("a web page", web.seen))

        let exr = ExportProbe()
        let exrPath = temporaryPath("frame.exr")
        defer { try? FileManager.default.removeItem(atPath: exrPath) }
        try OllinApp.exportEXR(exr, to: exrPath, frame: 2)
        drives.append(("an EXR", exr.seen))

        var tiles: [ExportProbe] = []
        _ = try OllinApp.contactSheet(of: { let s = ExportProbe(); tiles.append(s); return s },
                                      seeds: [1, 2], tileWidth: 32)
        drives.append(("a contact sheet", tiles.flatMap(\.seen)))

        var widgets: [ExportProbe] = []
        _ = OllinApp.widgetFrames(count: 1) { let s = ExportProbe(); widgets.append(s); return s }
        drives.append(("a widget", widgets.flatMap(\.seen)))

        for (drive, seen) in drives {
            #expect(!seen.isEmpty, "\(drive) ran no sketch code")
            #expect(seen.allSatisfy { $0 }, "\(drive): isExporting read \(seen)")
        }
        #expect(!ExportProbe().isExporting, "and false once the drive is over")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func isExportingIsFalseInAWindowAndInABenchmark() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let live = ExportProbe()
        let view = makeView(device, side: 32, for: live)
        let runner = SketchRunner(sketch: live, view: view, device: device)
        runner.draw(in: view)
        runner.draw(in: view)
        #expect(live.seen == [false, false, false])

        let bench = ExportProbe()
        OllinApp.benchmark(bench, frames: 3)
        #expect(!bench.seen.isEmpty && bench.seen.allSatisfy { !$0 },
                "a benchmark's frames stand in for a window's (\(bench.seen))")
    }

    // MARK: The pointer

    @Test func pointerShapeAndHidingReachTheCanvasApartFromEachOther() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Sketch()
        let view = makeView(device, side: 32, for: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        _ = runner
        #expect(view.canvasCursor == nil, "the ordinary arrow adds no cursor rect")

        sketch.pointerShape(.crosshair)
        #expect(view.canvasCursor === PointerShape.crosshair.systemCursor)

        sketch.hidePointer()
        #expect(view.canvasCursor === OllinMTKView.invisibleCursor)
        sketch.pointerShape(.openHand)
        #expect(view.canvasCursor === OllinMTKView.invisibleCursor,
                "a shape set while hidden does not show the pointer")
        sketch.showPointer()
        #expect(view.canvasCursor === PointerShape.openHand.systemCursor,
                "shown again, in the shape set while it was hidden")

        sketch.pointerShape(.arrow)
        #expect(view.canvasCursor == nil)
    }

    @Test func everyShapeIsASystemCursor() {
        for shape in PointerShape.allCases {
            #expect(shape.systemCursor.image.size.width > 0, "\(shape)")
        }
        let shown = PointerShape.allCases.filter { $0 != .arrow }.map { ObjectIdentifier($0.systemCursor) }
        #expect(Set(shown).count == shown.count, "no two shapes are the same cursor")
    }

    @Test func aSketchShowingNothingKeepsItsPointerForTheViewThatMountsIt() throws {
        let sketch = Sketch()
        sketch.pointerShape(.pointingHand)
        sketch.hidePointer()
        sketch.showPointer()   // nothing showing the sketch: the asks are kept, not lost

        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = makeView(device, side: 32, for: sketch)
        _ = SketchRunner(sketch: sketch, view: view, device: device)
        #expect(view.canvasCursor === PointerShape.pointingHand.systemCursor)
    }

    /// A sketch that asks for its pointer and remembers its presses.
    final class Presser: Sketch {
        var presses = 0
        let shape: PointerShape
        init(shape: PointerShape) {
            self.shape = shape
            super.init()
        }
        required init() {
            shape = .arrow
            super.init()
        }
        override func setup() { pointerShape(shape) }
        override func mousePressed() { presses += 1 }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aReloadHandsTheCanvasItsInputAndItsPointerToTheNewInstance() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let first = Presser(shape: .crosshair)
        let view = makeView(device, side: 64, for: first)
        let runner = SketchRunner(sketch: first, view: view, device: device)
        runner.draw(in: view)
        #expect(view.canvasCursor === PointerShape.crosshair.systemCursor)

        let second = Presser(shape: .closedHand)
        runner.reload(to: second)
        #expect(view.canvasCursor == nil, "the fresh instance has asked for nothing yet")
        runner.draw(in: view)
        #expect(view.canvasCursor === PointerShape.closedHand.systemCursor)

        let press = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: press)
        #expect(second.presses == 1, "a click after a reload reaches the instance drawing")
        #expect(first.presses == 0)
    }

    // MARK: The open panel

    final class Chooser: Sketch {
        var picks = 0
        override func filesChosen() { picks += 1 }
    }

    @Test func aPickArrivesAsPathsAndFiresTheHookOnce() {
        let sketch = Chooser()
        sketch.handleChosenFiles(["/pictures/a.png", "/pictures/b.heic"])
        #expect(sketch.picks == 1)
        #expect(sketch.chosenFiles() == ["/pictures/a.png", "/pictures/b.heic"])
        #expect(sketch.chosenFiles().isEmpty, "reading empties the list")

        sketch.handleChosenFiles([])
        #expect(sketch.picks == 1, "a panel closed without a pick is not a pick")
        #expect(sketch.droppedFiles().isEmpty, "a pick is not a drop")

        sketch.chooseFiles(withExtensions: ["png"])   // nothing showing it: no panel
    }

    @Test func theExtensionsBecomeThePanelsTypes() {
        let types = SketchRunner.contentTypes(forExtensions: ["png", ".JPG", "jpeg", "", "csv"])
        #expect(types == [.png, .jpeg, .commaSeparatedText],
                "dots and case do not matter, and two names for one type offer it once")
        #expect(SketchRunner.contentTypes(forExtensions: []).isEmpty, "no extensions offers every file")
        let made = SketchRunner.contentTypes(forExtensions: ["ollinpatch"])
        #expect(made.count == 1 && made.first?.preferredFilenameExtension == "ollinpatch",
                "an extension the system does not know still matches by name")
    }

    // MARK: Copying the frame

    private func pixels(_ png: Data) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height, WebExportTests.rgba(of: image))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func copyFramePutsTheFrameOnThePasteboardAsAPNG() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Still()
        // A window larger than the canvas: the copy is the canvas's size.
        let view = makeView(device, side: 160, for: sketch)
        sketch.setCanvasSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.isPaused = false
        runWhileAwake(runner, view)

        let board = NSPasteboard(name: NSPasteboard.Name("ollin-copy-frame-test"))
        board.clearContents()
        board.setString("what was there", forType: .string)

        sketch.copyFrame(to: board)
        #expect(runWhileAwake(runner, view) == 1, "a still sketch draws one frame for the copy")
        spin { board.data(forType: .png) != nil }
        let png = try #require(board.data(forType: .png))
        #expect(board.string(forType: .string) == nil, "the copy takes the clipboard's place")

        let copied = try pixels(png)
        #expect(copied.width == 64 && copied.height == 64)
        let center = (32 * 64 + 32) * 4
        #expect(copied.bytes[center] > 200 && copied.bytes[center + 2] < 90,
                "the disc is in the copy (\(copied.bytes[center ..< center + 3]))")
        #expect(copied.bytes[0] < 10, "and the black ground around it")
        #expect(sketch.frameCopier?.wantsRenderedFrame == false, "one copy per call")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLoopingSketchCopiesTheNextFrameItShows() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = ExportProbe()
        let view = makeView(device, side: 32, for: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.draw(in: view)

        let board = NSPasteboard(name: NSPasteboard.Name("ollin-copy-frame-looping-test"))
        board.clearContents()
        sketch.copyFrame(to: board)
        #expect(view.isPaused, "a looping sketch is not woken: its next frame is coming")
        runner.draw(in: view)
        spin { board.data(forType: .png) != nil }
        let copied = try pixels(try #require(board.data(forType: .png)))
        #expect(copied.width == 32 && copied.height == 32)
    }

    @Test func copyFrameWithNothingShowingTheSketchArmsNothing() {
        let sketch = ExportProbe()
        sketch.copyFrame()
        #expect(sketch.frameCopier == nil, "an export has no window to copy from")
    }

    // MARK: Spherical coordinates

    private func close(_ a: Vector3, _ b: Vector3, _ tolerance: Double = 1e-9) -> Bool {
        (a - b).length < tolerance
    }

    @Test func sphericalPointsWhereItsAnglesSay() {
        #expect(close(spherical(0, 0, 1), Vector3(0, 0, 1)), "azimuth 0 looks down +z")
        #expect(close(spherical(.pi / 2, 0, 2), Vector3(2, 0, 0)), "a quarter turn is +x")
        #expect(close(spherical(1.3, .pi / 2, 3), Vector3(0, 3, 0)), "elevation pi/2 is straight up")
        #expect(close(spherical(0, -.pi / 2, 3), Vector3(0, -3, 0)))
        #expect(close(spherical(0.7, 0.2, 5, around: Vector3(1, 2, 3)),
                      Vector3(1, 2, 3) + spherical(0.7, 0.2, 5)))
    }

    @Test func sphericalAndAVectorsAnglesUndoEachOther() {
        var rng = SystemRandomNumberGenerator()
        let center = Vector3(-2, 0.5, 4)
        for _ in 0..<500 {
            let a = Double.random(in: -.pi ..< .pi, using: &rng)
            let e = Double.random(in: -1.5 ... 1.5, using: &rng)
            let r = Double.random(in: 0.01 ... 100, using: &rng)
            let offset = spherical(a, e, r, around: center) - center
            #expect(abs(offset.azimuth - a) < 1e-9)
            #expect(abs(offset.elevation - e) < 1e-9)
            #expect(abs(offset.length - r) < 1e-9 * max(1, r))
            #expect(close(spherical(offset.azimuth, offset.elevation, offset.length, around: center),
                          center + offset, 1e-9 * max(1, r)))
        }
        #expect(Vector3.zero.azimuth == 0 && Vector3.zero.elevation == 0)
    }

    @Test func sphericalStandsWhereTheOrbitingCameraStands() {
        for (a, e, r) in [(0.0, 0.3, 6.0), (2.1, -0.4, 3.5), (-1.2, 1.1, 10.0)] {
            let target = Vector3(1, -1, 2)
            let camera = Camera3D.orbiting(target: target, radius: r, azimuth: a, elevation: e)
            #expect(close(camera.eye, spherical(a, e, r, around: target)))
        }
    }
}
