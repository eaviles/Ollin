import AppKit
import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Ollin

/// A sketch floating over the desktop (`OllinApp.runAsOverlay`, `--overlay`).
///
/// The claims are the ones that decide whether the machine stays usable under
/// the piece: the window is see-through and above the others, it never takes
/// the keyboard, and it is there to be clicked only where the piece is, which
/// is read off the alpha of a frame the sketch really drew.
@MainActor
@Suite(.serialized)
struct OverlayHostTests {

    /// A disk in the middle of a clear canvas.
    final class Disk: Sketch {
        override var canvasSize: CanvasSize { .size(200, 120) }
        override func draw() {
            background(.clear)
            noStroke()
            fill(.white)
            drawCircle(width / 2, height / 2, 40)
        }
    }

    /// The same disk on a black ground: nothing of the canvas is clear.
    final class DiskOnBlack: Sketch {
        override var canvasSize: CanvasSize { .size(200, 120) }
        override func draw() {
            background(.black)
            fill(.white)
            drawCircle(width / 2, height / 2, 40)
        }
    }

    /// The shape a piece over the whole display has: the canvas follows its view.
    final class Filling: Sketch {
        override var windowMode: WindowMode { .resizable }
        override func draw() { background(.clear) }
    }

    private func makePane(_ sketch: Sketch,
                          hitTest: (@MainActor (Sketch, Vector2) -> Bool)? = nil) throws -> OverlayPane {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let screen = try #require(NSScreen.main, "no display on this machine")
        return try #require(OverlayPane(screen: screen, sketch: sketch, hitTest: hitTest))
    }

    @Test func thePaneIsSeeThroughAndFloatsOverTheOtherWindows() throws {
        let pane = try makePane(Disk())
        defer { pane.close() }
        #expect(pane.window.level == .floating)
        #expect(!pane.window.isOpaque && pane.window.backgroundColor == .clear && !pane.window.hasShadow)
        #expect((pane.canvas.layer as? CAMetalLayer)?.isOpaque == false, "the canvas's own layer is opaque")
        #expect(pane.runner.renderer.windowKeepsAlpha, "the window's frames would be presented opaque")
        #expect(pane.window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(pane.window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(pane.window.collectionBehavior.contains(.ignoresCycle))
    }

    @Test func thePaneNeverTakesTheKeyboardAndStartsOutOfTheWayOfClicks() throws {
        let pane = try makePane(Disk())
        defer { pane.close() }
        #expect(!pane.window.canBecomeKey, "an overlay taking the keys would leave typing dead")
        #expect(!pane.canvas.claimsKeyboardOnAttach)
        // Until a frame says where the piece is, every click goes through.
        #expect(pane.window.ignoresMouseEvents)
        // The pointer and its presses are the sketch's where the piece is.
        #expect(!pane.canvas.ignoresInput)
    }

    @Test func aStatedCanvasFloatsAtItsSizeAndAFollowingOneCoversTheDisplay() throws {
        let screen = try #require(NSScreen.main, "no display on this machine")
        let stated = try makePane(Disk())
        defer { stated.close() }
        let fitted = OllinApp.windowSize(fitting: CGSize(width: 200, height: 120))
        #expect(stated.window.frame.size == fitted)
        #expect(abs(stated.window.frame.midX - screen.visibleFrame.midX) < 1)
        let filling = try makePane(Filling())
        defer { filling.close() }
        #expect(filling.window.frame == screen.frame)
    }

    // MARK: Where the piece is

    /// One frame of `sketch` as the export draws it, alpha and all.
    private func rendered(_ sketch: Sketch) throws -> CGImage {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        return try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func thePieceIsWhereTheRenderedFrameIsNotClear() throws {
        let hits = OverlayHitTester(hitTest: nil)
        let sketch = Disk()
        // No frame yet: nothing to click.
        #expect(!hits.takes(sketch: sketch, acrossFraction: 0.5, downFraction: 0.5))
        hits.take(try rendered(sketch))
        // The disk's middle, its inside near the rim, and three places it is not.
        #expect(hits.coverage(acrossFraction: 0.5, downFraction: 0.5) > 0.99)
        #expect(hits.takes(sketch: sketch, acrossFraction: 0.5, downFraction: 0.5))
        #expect(hits.takes(sketch: sketch, acrossFraction: 0.5 + 35.0 / 200, downFraction: 0.5))
        #expect(!hits.takes(sketch: sketch, acrossFraction: 0.5 + 45.0 / 200, downFraction: 0.5))
        #expect(!hits.takes(sketch: sketch, acrossFraction: 0.02, downFraction: 0.02))
        #expect(hits.coverage(acrossFraction: 0.98, downFraction: 0.98) == 0)
        // The rim is where the answer changes, within a pixel or so of the radius.
        var edge = 0.0
        for step in 0 ... 200 {
            let x = 0.5 + Double(step) / 200 * 0.3
            if !hits.takes(sketch: sketch, acrossFraction: x, downFraction: 0.5) { edge = (x - 0.5) * 200; break }
        }
        #expect(abs(edge - 40) <= 1.5, "the piece ends \(edge) points from its middle, and its radius is 40")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOpaqueFrameIsThePieceEverywhere() throws {
        let hits = OverlayHitTester(hitTest: nil)
        let sketch = DiskOnBlack()
        hits.take(try rendered(sketch))
        #expect(hits.takes(sketch: sketch, acrossFraction: 0.02, downFraction: 0.02))
        #expect(hits.coverage(acrossFraction: 0.98, downFraction: 0.5) == 1)
    }

    /// A 4 by 2 image whose left half is covered at `alpha` and whose right half
    /// is clear, in the byte layout `info` names.
    private func halves(alpha: CGFloat, info: UInt32) throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info))
        ctx.clear(CGRect(x: 0, y: 0, width: 4, height: 2))
        ctx.setFillColor(red: 1, green: 0.5, blue: 0.25, alpha: alpha)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try #require(ctx.makeImage())
    }

    @Test func theAlphaIsReadWhereverThePixelKeepsIt() throws {
        // The two layouts a read-back frame arrives in, and the two they are not.
        let layouts: [UInt32] = [
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,   // B G R A
            CGImageAlphaInfo.premultipliedLast.rawValue,                                             // R G B A
            CGImageAlphaInfo.premultipliedFirst.rawValue,                                            // A R G B
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,    // A B G R
        ]
        for info in layouts {
            let hits = OverlayHitTester(hitTest: nil)
            hits.take(try halves(alpha: 0.5, info: info))
            let covered = hits.coverage(acrossFraction: 0.2, downFraction: 0.5)
            #expect(abs(covered - 0.5) < 0.01, "layout \(info): read \(covered) where the alpha is a half")
            #expect(hits.coverage(acrossFraction: 0.8, downFraction: 0.5) == 0, "layout \(info)")
        }
        // A faint edge is not the piece: under the threshold a click goes through.
        let faint = OverlayHitTester(hitTest: nil)
        faint.take(try halves(alpha: 0.03, info: layouts[0]))
        #expect(!faint.takes(sketch: Disk(), acrossFraction: 0.2, downFraction: 0.5))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theWindowIsThereToBeClickedOnlyOverThePiece() throws {
        let sketch = Disk()
        let pane = try makePane(sketch)
        defer { pane.close() }
        sketch.setCanvasSize(width: 200, height: 120)
        pane.hits.take(try rendered(Disk()))
        let frame = pane.window.frame
        func point(_ across: Double, _ down: Double) -> CGPoint {
            CGPoint(x: frame.minX + frame.width * across, y: frame.minY + frame.height * (1 - down))
        }
        // Over the disk: the window takes the click, and the sketch has the pointer.
        pane.apply(pointerAt: point(0.5, 0.5), buttonsDown: false)
        #expect(!pane.window.ignoresMouseEvents)
        #expect(abs(sketch.mouseX - 100) < 0.5 && abs(sketch.mouseY - 60) < 0.5)
        // Over the clear canvas: the click goes through, and the pointer is still the sketch's.
        pane.apply(pointerAt: point(0.05, 0.1), buttonsDown: false)
        #expect(pane.window.ignoresMouseEvents)
        #expect(abs(sketch.mouseX - 10) < 0.5 && abs(sketch.mouseY - 12) < 0.5)
        // A press that began on the piece stays the piece's while it is held.
        pane.apply(pointerAt: point(0.5, 0.5), buttonsDown: false)
        pane.apply(pointerAt: point(0.05, 0.1), buttonsDown: true)
        #expect(!pane.window.ignoresMouseEvents, "a drag off the piece dropped the press")
        pane.apply(pointerAt: point(0.05, 0.1), buttonsDown: false)
        #expect(pane.window.ignoresMouseEvents)
        // Off the window altogether: not the piece, and the sketch keeps its last place.
        pane.apply(pointerAt: CGPoint(x: frame.maxX + 300, y: frame.midY), buttonsDown: false)
        #expect(pane.window.ignoresMouseEvents)
        #expect(abs(sketch.mouseX - 10) < 0.5)
    }

    @Test func theSketchsOwnAnswerReplacesTheAlpha() throws {
        // The left half of the canvas is the piece, whatever was drawn.
        let hits = OverlayHitTester { sketch, point in point.x < sketch.width / 2 }
        let sketch = Disk()
        sketch.setCanvasSize(width: 200, height: 120)
        #expect(hits.takes(sketch: sketch, acrossFraction: 0.1, downFraction: 0.9))
        #expect(!hits.takes(sketch: sketch, acrossFraction: 0.9, downFraction: 0.5))
        // And no frame is read back for it.
        #expect(!hits.wantsRenderedFrame && !hits.wantsRenderedFrame)
    }

    @Test func everyOtherFrameIsReadBack() {
        let hits = OverlayHitTester(hitTest: nil)
        let asked = (0 ..< 6).map { _ in hits.wantsRenderedFrame }
        #expect(asked == [true, false, true, false, true, false])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func onlyASeeThroughWindowOverAClearCanvasKeepsItsAlpha() throws {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        func alpha(_ sketch: Sketch, seeThrough: Bool) throws -> PresentAlpha {
            let renderer = try OllinApp.headlessRenderer(for: sketch)
            renderer.windowKeepsAlpha = seeThrough
            _ = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
            return renderer.windowAlpha(for: sketch.drawer)
        }
        #expect(try alpha(Disk(), seeThrough: true) == .premultiplied)
        #expect(try alpha(Disk(), seeThrough: false) == .opaque, "an ordinary window lost its opaque present")
        #expect(try alpha(DiskOnBlack(), seeThrough: true) == .opaque)
    }
}
