@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// The 2D pan-and-zoom view: `viewControl()` and the `View2D` it drives.
///
/// Two promises carry it. A drag moves the content exactly as far as the pointer
/// went, and a zoom leaves the content under the pointer where it was. Neither
/// is a matter of feel: both are equations, and both are checked here.
@Suite(.serialized)
@MainActor
struct ViewControlTests {

    /// A sketch that runs `viewControl()` and reports what the view did.
    final class Probe: Sketch {
        var openingCenter: Vector2?
        var openingZoom = 1.0
        var mouseSeen = Vector2.zero
        /// Where a marker at this content point landed on the glass.
        var markerAt = Vector2(200, 150)
        var markerOnScreen = Vector2.zero

        override var canvasSize: CanvasSize { .square(400) }

        override func draw() {
            viewControl(center: openingCenter, zoom: openingZoom)
            mouseSeen = Vector2(mouseX, mouseY)
            markerOnScreen = view2D.screenPoint(markerAt,
                                                canvasCenter: Vector2(width / 2, height / 2))
        }
    }

    private func probe() -> Probe {
        let p = Probe()
        p.setCanvasSize(width: 400, height: 400)
        return p
    }

    /// Run one frame with the pointer here, the button in this state, and this
    /// much scroll waiting.
    private func frame(_ sketch: Probe, at pointer: Vector2,
                       pressed: Bool = false, scroll: Double = 0) {
        sketch.setMouse(x: pointer.x, y: pointer.y)
        sketch.handleMouseButton(pressed: pressed)
        if scroll != 0 { sketch.handleScroll(deltaY: scroll) }
        sketch.advance(time: Double(sketch.frameCount) / 60, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
    }

    // MARK: Panning

    /// The promise: content sticks to the pointer. A drag of 60 by 25 moves what
    /// was under the pointer by exactly 60 by 25 on the glass, whatever the zoom.
    @Test(arguments: [1.0, 0.4, 3.0])
    func aDragMovesTheContentExactlyAsFarAsThePointer(_ zoom: Double) {
        let sketch = probe()
        sketch.openingZoom = zoom
        frame(sketch, at: Vector2(100, 100))
        let before = sketch.markerOnScreen

        frame(sketch, at: Vector2(100, 100), pressed: true)   // the press itself moves nothing
        #expect(sketch.markerOnScreen == before, "the press alone moved the view")

        frame(sketch, at: Vector2(160, 125), pressed: true)
        let moved = sketch.markerOnScreen - before
        #expect(abs(moved.x - 60) < 1e-9 && abs(moved.y - 25) < 1e-9,
                "at zoom \(zoom) the content moved \(moved)")
    }

    /// Letting go ends the drag, so the next press does not jump the view by
    /// however far the pointer travelled in between.
    @Test func lettingGoEndsTheDrag() {
        let sketch = probe()
        frame(sketch, at: Vector2(100, 100), pressed: true)
        frame(sketch, at: Vector2(140, 100), pressed: true)
        let parked = sketch.markerOnScreen
        frame(sketch, at: Vector2(300, 300))                  // moved with the button up
        #expect(sketch.markerOnScreen == parked, "the view moved with nothing pressed")
        frame(sketch, at: Vector2(300, 300), pressed: true)   // press again, no motion yet
        #expect(sketch.markerOnScreen == parked, "the second press jumped the view")
    }

    // MARK: Zooming

    /// The other promise: the thing you are pointing at stays under the pointer
    /// while the view grows around it.
    @Test(arguments: [Vector2(200, 200), Vector2(40, 330), Vector2(399, 0)])
    func aZoomLeavesTheContentUnderThePointerWhereItWas(_ pointer: Vector2) {
        let sketch = probe()
        frame(sketch, at: pointer)
        let under = sketch.mouseSeen        // the content the pointer is over

        frame(sketch, at: pointer, scroll: 4)
        #expect(abs(sketch.mouseSeen.x - under.x) < 1e-9, "x moved: \(sketch.mouseSeen) vs \(under)")
        #expect(abs(sketch.mouseSeen.y - under.y) < 1e-9, "y moved: \(sketch.mouseSeen) vs \(under)")
        #expect(sketch.viewZoom > 1, "scrolling up should zoom in: \(sketch.viewZoom)")
    }

    /// Scrolling the other way zooms out, and the two undo each other exactly.
    @Test func scrollingBackUndoesTheZoom() {
        let sketch = probe()
        frame(sketch, at: Vector2(120, 260))
        let opening = sketch.markerOnScreen
        frame(sketch, at: Vector2(120, 260), scroll: 5)
        frame(sketch, at: Vector2(120, 260), scroll: -5)
        #expect(abs(sketch.viewZoom - 1) < 1e-9, "zoom came back to \(sketch.viewZoom)")
        #expect(abs(sketch.markerOnScreen.x - opening.x) < 1e-6, "\(sketch.markerOnScreen)")
        #expect(abs(sketch.markerOnScreen.y - opening.y) < 1e-6)
    }

    /// The wheel cannot take the view past the range it was given, however long
    /// somebody keeps scrolling.
    @Test func theWheelStaysInsideTheRange() {
        let sketch = probe()
        for _ in 0..<40 { frame(sketch, at: Vector2(200, 200), scroll: 20) }
        #expect(sketch.viewZoom <= 50 + 1e-9, "zoomed to \(sketch.viewZoom)")
        for _ in 0..<80 { frame(sketch, at: Vector2(200, 200), scroll: -20) }
        #expect(sketch.viewZoom >= 0.05 - 1e-9, "zoomed to \(sketch.viewZoom)")
    }

    // MARK: The opening view

    /// The framing is the *opening* one: it is applied once, and after that the
    /// viewer owns the view. Passing it every frame must not undo their dragging.
    @Test func theOpeningFramingIsAppliedOnceOnly() {
        let sketch = probe()
        sketch.openingCenter = Vector2(200, 200)
        frame(sketch, at: Vector2(100, 100), pressed: true)
        frame(sketch, at: Vector2(180, 100), pressed: true)
        let dragged = sketch.viewCenter
        #expect(abs(dragged.x - 120) < 1e-9, "an 80px drag at zoom 1: \(dragged)")

        sketch.openingCenter = Vector2(20, 20)          // a different framing, every frame
        frame(sketch, at: Vector2(180, 100))
        #expect(sketch.viewCenter == dragged, "the opening framing snapped the view back")
    }

    /// And `resetView()` is the way back, since nothing else is.
    @Test func resetPutsTheOpeningFramingBack() {
        let sketch = probe()
        frame(sketch, at: Vector2(100, 100), pressed: true)
        frame(sketch, at: Vector2(300, 220), pressed: true, scroll: 6)
        #expect(sketch.viewCenter != Vector2(200, 200))
        sketch.resetView()
        frame(sketch, at: Vector2(300, 220))
        #expect(sketch.viewCenter == Vector2(200, 200), "\(sketch.viewCenter)")
        #expect(sketch.viewZoom == 1)
    }

    // MARK: The pointer

    /// Inside the frame the mouse reads the content it is pointing at, so
    /// hit-testing and drawing at the pointer keep working at any zoom.
    @Test func theMouseReadsTheContentItIsPointingAt() {
        let sketch = probe()
        sketch.openingZoom = 2
        frame(sketch, at: Vector2(300, 200))
        // At zoom 2 about (200, 200), the glass point 300 is 50 content units right.
        #expect(abs(sketch.mouseSeen.x - 250) < 1e-9, "\(sketch.mouseSeen)")
        #expect(abs(sketch.mouseSeen.y - 200) < 1e-9)
    }

    /// The remap lasts one frame. The runner only writes the mouse when it
    /// moves, so a remap left standing would be applied to itself again on every
    /// still frame after it, and the view would crawl away on its own.
    @Test func aStillPointerDoesNotDriftTheView() {
        let sketch = probe()
        sketch.openingZoom = 2
        frame(sketch, at: Vector2(300, 200))
        let first = sketch.mouseSeen
        // Four more frames with nothing touched at all: no setMouse, no scroll.
        for _ in 0..<4 {
            sketch.advance(time: Double(sketch.frameCount) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
        }
        #expect(sketch.mouseSeen == first, "the pointer drifted to \(sketch.mouseSeen)")
        #expect(sketch.mouseX == 300 && sketch.mouseY == 200,
                "the real pointer was left at \(sketch.mouseX), \(sketch.mouseY)")
    }

    // MARK: What actually draws

    /// A render probe, so the transform the arithmetic describes is the one the
    /// renderer applies. A marker drawn at a content point lands where
    /// `screenPoint` says it will after a pan and a zoom.
    final class Marked: Sketch {
        var pan = Vector2.zero
        var scroll = 0.0
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.black)
            if scroll != 0 { view2D.seed(center: Vector2(120, 120), zoom: 1) }
            viewControl()
            noStroke()
            fill(.white)
            drawCircle(60, 60, 14)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The middle of the lit pixels, in canvas coordinates. A centroid rather
    /// than the brightest pixel: a filled disc has hundreds of equally bright
    /// ones, and the first found is its top edge, a whole radius off.
    private func center(ofLit image: CGImage) -> Vector2 {
        let d = pixels(of: image)
        var sum = Vector2.zero, count = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width where d[(y * image.width + x) * 4 + 1] > 128 {
                sum += Vector2(Double(x), Double(y)); count += 1
            }
        }
        return count > 0 ? sum / count : Vector2(-1, -1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theMarkerLandsWhereTheViewSaysItWill() throws {
        let sketch = Marked()
        sketch.setCanvasSize(width: 240, height: 240)
        // Drag the view 40 right and 20 down, over two frames.
        sketch.setMouse(x: 100, y: 100)
        sketch.handleMouseButton(pressed: true)
        sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        sketch.setMouse(x: 140, y: 120)
        sketch.advance(time: 1.0 / 60, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()

        let frame = try #require(OllinApp.image(of: sketch, frame: 1))
        let found = center(ofLit: frame)
        let due = sketch.view2D.screenPoint(Vector2(60, 60), canvasCenter: Vector2(120, 120))
        #expect(abs(found.x - due.x) < 3 && abs(found.y - due.y) < 3,
                "the marker landed at \(found), the view says \(due)")
    }
}
