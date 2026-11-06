import AppKit
import CoreGraphics
import Foundation
import Metal
import MetalKit
import Testing
@testable import Ollin

/// A window of its own for one of a sketch's layers (`makeWindow(showing:title:)`).
///
/// What the window shows is the layer and not the canvas, at the layer's own
/// size and through the layer's own camera; the pointer it reports is in the
/// layer's coordinates whatever size the window has been dragged to; and the
/// run that draws the sketch opens each window once, closes it when the sketch
/// closes it or is replaced, and opens none where there is no window to stand
/// beside.
@MainActor
@Suite(.serialized)
struct LayerWindowTests {

    /// A lit block on the canvas, and beside it a layer of another shape holding
    /// a flat readout: the piece and a view of controls.
    final class TwoViews: Sketch {
        var monitor: RenderTarget!
        var controls: SketchWindow!
        var drawsTheLayer = true
        /// Draw the layer through a camera of its own, from above: what a
        /// second view of one world wants, and what a frame's one camera
        /// does not yet give.
        var layerLooksFromAbove = false
        override var canvasSize: CanvasSize { .size(200, 140) }
        let block = Mesh.box(width: 1.2, height: 0.6, depth: 2)

        override func setup() {
            monitor = makeRenderTarget(width: 160, height: 90)
            controls = makeWindow(showing: monitor, title: "Controls")
        }

        func scene() {
            fill(Color(red: 0.9, green: 0.5, blue: 0.2))
            material(.matte)
            drawMesh(block)
        }

        override func draw() {
            background(Color(white: 0.1))
            // The lights are the frame's: set once, they light every view.
            directionalLight(.white, direction: Vector3(0.4, -0.8, -0.45), intensity: 1)
            ambientLight(Color(white: 0.25))
            camera(.perspective(eye: Vector3(0, 1.2, 5), target: .zero, fieldOfView: .pi / 4))
            scene()
            guard drawsTheLayer else { return }
            withTarget(monitor) {
                background(Color(white: 0.1))
                if layerLooksFromAbove {
                    camera(.perspective(eye: Vector3(0, 6, 0.01), target: .zero, fieldOfView: .pi / 4))
                    scene()
                } else {
                    Readout.drawReadout(on: self)
                }
            }
        }
    }

    /// The layer's readout alone, as a canvas of the layer's size.
    final class Readout: Sketch {
        override var canvasSize: CanvasSize { .size(160, 90) }
        static func drawReadout(on sketch: Sketch) {
            sketch.noStroke()
            sketch.fill(Color(red: 0.2, green: 0.7, blue: 0.9))
            sketch.drawRect(12, 14, 90, 20)
            sketch.fill(.white)
            sketch.drawCircle(120, 60, 18)
        }
        override func draw() {
            background(Color(white: 0.1))
            Readout.drawReadout(on: self)
        }
    }

    /// The canvas's view alone: the block through the stage's camera, no layer.
    final class StageAlone: Sketch {
        override var canvasSize: CanvasSize { .size(200, 140) }
        let block = Mesh.box(width: 1.2, height: 0.6, depth: 2)
        override func draw() {
            background(Color(white: 0.1))
            directionalLight(.white, direction: Vector3(0.4, -0.8, -0.45), intensity: 1)
            ambientLight(Color(white: 0.25))
            camera(.perspective(eye: Vector3(0, 1.2, 5), target: .zero, fieldOfView: .pi / 4))
            fill(Color(red: 0.9, green: 0.5, blue: 0.2))
            material(.matte)
            drawMesh(block)
        }
    }

    /// One headless frame of `sketch`, and what its window shows of it.
    private func frame(of sketch: TwoViews) throws -> (canvas: CGImage, window: CGImage?) {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let canvas = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
        return (canvas, renderer.layerImage(of: sketch.monitor, drawer: sketch.drawer))
    }

    /// One headless frame of a sketch with nothing but its canvas.
    private func still(_ sketch: Sketch) throws -> CGImage {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        return try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60,
                                                     renderer: try OllinApp.headlessRenderer(for: sketch)))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theWindowShowsItsLayerAtItsOwnSizeAndTheCanvasKeepsItsOwnPicture() throws {
        let shown = try frame(of: TwoViews())
        let window = try #require(shown.window, "the window was given no picture")
        #expect(shown.canvas.width == 200 && shown.canvas.height == 140)
        #expect(window.width == 160 && window.height == 90, "the window's picture is \(window.width) by \(window.height)")

        // The window shows the layer: the picture the same drawing makes on a
        // canvas of the layer's size.
        let readout = try #require(imageDifference(window, try still(Readout())))
        #expect(readout.max <= 2, "the window's picture is off the layer's own drawing by up to \(readout.max) levels")
        // And the canvas is the piece, as it is with no layer beside it.
        let stage = try #require(imageDifference(shown.canvas, try still(StageAlone())))
        #expect(stage.max <= 2, "drawing a layer changed the canvas by up to \(stage.max) levels")
        // Two different pictures, each with something in it.
        let flat = try #require(flatImage(like: window))
        let ink = try #require(imageDifference(window, flat))
        #expect(ink.max > 60, "the window's picture is blank")
    }

    /// A frame has one 3D camera, so a camera set inside a layer's block is the
    /// canvas's too, and a second window cannot yet show the same world from
    /// somewhere else. Pinned as a known issue: the day a layer keeps a camera
    /// of its own this stops failing, and the pin has to come off.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayersCameraIsStillTheFramesCamera() throws {
        let sketch = TwoViews()
        sketch.layerLooksFromAbove = true
        let shown = try frame(of: sketch)
        let alone = try still(StageAlone())
        withKnownIssue("a frame has one camera: the layer's replaces the canvas's") {
            let stage = try #require(imageDifference(shown.canvas, alone))
            #expect(stage.max <= 2, "the layer's camera moved the canvas by up to \(stage.max) levels")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerTheFrameDidNotDrawIsNotShown() throws {
        // Drawn in the first frame and left out of the second, in one run: the
        // layer still holds the first frame's texture, which by now could be
        // another layer's, and the window is given nothing rather than that.
        let sketch = TwoViews()
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        func draw(frame: Int) throws {
            sketch.advance(time: Double(frame) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
            _ = try #require(renderer.image(of: sketch.drawer, viewport: SIMD2<Float>(200, 140),
                                            width: 200, height: 140))
        }
        try draw(frame: 0)
        #expect(renderer.layerImage(of: sketch.monitor, drawer: sketch.drawer) != nil)
        let canvas = try #require(sketch.monitor.texture, "the layer kept no texture")
        #expect(renderer.presentSource(layer: sketch.monitor, canvas: canvas, drawer: sketch.drawer) === sketch.monitor.texture)
        // A display of a wall has no layer, and is given the canvas.
        #expect(renderer.presentSource(layer: nil, canvas: canvas, drawer: sketch.drawer) === canvas)

        sketch.drawsTheLayer = false
        try draw(frame: 1)
        #expect(sketch.monitor.texture != nil, "the layer's old texture is gone, so this proves nothing")
        #expect(renderer.layerImage(of: sketch.monitor, drawer: sketch.drawer) == nil,
                "a layer the frame did not draw was presented")
        #expect(renderer.presentSource(layer: sketch.monitor, canvas: canvas, drawer: sketch.drawer) == nil)
    }

    @Test func inAnExportNoWindowOpensAndTheLayerStillDraws() throws {
        let sketch = TwoViews()
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(sketch.layerWindows.count == 1)
        #expect(!sketch.controls.isOpen)
        #expect(sketch.controls.mouseX == 0 && sketch.controls.mouseY == 0 && !sketch.controls.mouseIsPressed)
        #expect(sketch.drawer.renderTargets.contains { $0 === sketch.monitor })
    }

    // MARK: The window itself

    private func makePane(_ sketch: TwoViews) throws -> LayerWindowPane {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device on this machine")
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        return LayerWindowPane(showing: sketch.controls, device: device, output: sketch.colorOutput, beside: nil)
    }

    @Test func thePaneIsTheLayersShapeAndNamesItsLayer() throws {
        let sketch = TwoViews()
        let pane = try makePane(sketch)
        defer { pane.close() }
        #expect(pane.window.title == "Ollin - Controls")
        let content = pane.window.contentRect(forFrameRect: pane.window.frame).size
        #expect(abs(content.width / content.height - 160.0 / 90.0) < 0.01)
        #expect(pane.window.contentAspectRatio == CGSize(width: 160, height: 90))
        #expect(!pane.window.canBecomeKey, "the keys stay with the sketch's own window")
        #expect(pane.window.styleMask.contains(.resizable) && pane.window.styleMask.contains(.closable))
        #expect(pane.window.collectionBehavior.contains(.fullScreenPrimary))
        // Made, not shown: nothing is on this machine's screen, and the value says so.
        #expect(!sketch.controls.isOpen && !pane.window.isVisible)

        // With a size to draw at, the run is handed a drawable that names the layer.
        pane.view.layoutSubtreeIfNeeded()
        if let display = pane.nextDisplay() {
            #expect(display.layer === sketch.monitor)
            #expect(display.placement == nil)
        }
    }

    @Test func thePointerIsReportedInTheLayersCoordinates() throws {
        let sketch = TwoViews()
        let pane = try makePane(sketch)
        defer { pane.close() }
        let bounds = pane.view.bounds
        // A quarter across and a quarter down from the top, whatever the
        // window's size: events arrive in points up from the bottom left.
        pane.view.report(CGPoint(x: bounds.width * 0.25, y: bounds.height * 0.75), pressed: true)
        #expect(abs(sketch.controls.mouseX - 40) < 1e-9 && abs(sketch.controls.mouseY - 22.5) < 1e-9)
        #expect(sketch.controls.mouseIsPressed)
        #expect(sketch.controls.mouse == Vector2(sketch.controls.mouseX, sketch.controls.mouseY))
        // The same place after the window is dragged to twice the size.
        pane.window.setContentSize(CGSize(width: bounds.width * 2, height: bounds.height * 2))
        pane.view.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width * 2, height: bounds.height * 2))
        let grown = pane.view.bounds
        pane.view.report(CGPoint(x: grown.width * 0.25, y: grown.height * 0.75), pressed: false)
        #expect(abs(sketch.controls.mouseX - 40) < 1e-9 && abs(sketch.controls.mouseY - 22.5) < 1e-9)
        #expect(!sketch.controls.mouseIsPressed)
        // Past the edge the pointer stays on the layer.
        pane.view.report(CGPoint(x: grown.width * 3, y: -40))
        #expect(sketch.controls.mouseX == 160 && sketch.controls.mouseY == 90)
    }

    @Test func eitherWayOfClosingEndsTheWindow() throws {
        let sketch = TwoViews()
        let pane = try makePane(sketch)
        sketch.controls.isOpen = true
        sketch.controls.close()
        #expect(!sketch.controls.isOpen && sketch.controls.isDismissed)
        #expect(pane.window.contentView == nil, "the sketch's close left the window standing")

        // The person closing it: the window says it will close, and the value follows.
        let other = TwoViews()
        let second = try makePane(other)
        other.controls.isOpen = true
        other.controls.mouseIsPressed = true
        second.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(!other.controls.isOpen && other.controls.isDismissed && !other.controls.mouseIsPressed)
        second.close()
    }

    // MARK: The run that opens them

    private func makeRunner(_ sketch: Sketch) throws -> (runner: SketchRunner, canvas: OllinMTKView) {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device on this machine")
        let canvas = makeOllinMTKView(device: device, size: sketch.canvasSize.cgSize, sketch: sketch)
        canvas.isPaused = true
        let runner = SketchRunner(sketch: sketch, view: canvas, device: device)
        canvas.delegate = runner
        return (runner, canvas)
    }

    @Test func theRunOpensEachWindowOnceAndClosesWhatTheSketchCloses() throws {
        let sketch = TwoViews()
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        let (runner, _) = try makeRunner(sketch)
        defer { runner.closeLayerWindows() }

        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 1)
        #expect(runner.layerPanes.first?.sketchWindow === sketch.controls)
        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 1, "a second frame opened the window again")

        // A second window joins; the first closes; only the second is left.
        let second = sketch.makeWindow(showing: sketch.monitor, title: "Second")
        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 2)
        sketch.controls.close()
        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 1 && runner.layerPanes.first?.sketchWindow === second)
        // A closed window is not opened again.
        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 1)
    }

    @Test func aReplacedSketchTakesItsWindowsWithIt() throws {
        let sketch = TwoViews()
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        let (runner, _) = try makeRunner(sketch)
        defer { runner.closeLayerWindows() }
        runner.syncLayerWindows(opening: true, showing: false)
        let old = try #require(runner.layerPanes.first)
        sketch.controls.isOpen = true

        let next = TwoViews()
        runner.reload(to: next)
        next.controls = next.makeWindow(showing: next.makeRenderTarget(width: 64, height: 64), title: "Next")
        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 1 && runner.layerPanes.first?.sketchWindow === next.controls)
        #expect(!sketch.controls.isOpen, "the old sketch's window still reads open")
        #expect(old.window.contentView == nil, "the old sketch's window was left standing")
    }

    @Test func aRunWithNoWindowToStandBesideOpensNone() throws {
        let sketch = TwoViews()
        sketch.setCanvasSize(width: 200, height: 140)
        try sketch.runSetup()
        let (runner, canvas) = try makeRunner(sketch)
        // A canvas in no window (an export's, a test's), and a surface that
        // takes no input (a wallpaper, a menu-bar strip).
        #expect(!runner.opensLayerWindows(for: canvas))
        canvas.ignoresInput = true
        #expect(!runner.opensLayerWindows(for: canvas))
        // The rule, case by case: a window somebody can see, input taken, and no export.
        #expect(SketchRunner.opensLayerWindows(headless: false, inVisibleWindow: true, takesInput: true))
        #expect(!SketchRunner.opensLayerWindows(headless: true, inVisibleWindow: true, takesInput: true))
        #expect(!SketchRunner.opensLayerWindows(headless: false, inVisibleWindow: false, takesInput: true))
        #expect(!SketchRunner.opensLayerWindows(headless: false, inVisibleWindow: true, takesInput: false))
        runner.syncLayerWindows(opening: runner.opensLayerWindows(for: canvas), showing: false)
        #expect(runner.layerPanes.isEmpty)
        // The canvas leaving its window takes every layer window down.
        canvas.ignoresInput = false
        runner.syncLayerWindows(opening: true, showing: false)
        #expect(runner.layerPanes.count == 1)
        runner.closeLayerWindows()
        #expect(runner.layerPanes.isEmpty && !sketch.controls.isOpen)
    }

    /// A flat image of the background's gray, the size of `image`.
    private func flatImage(like image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(gray: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
