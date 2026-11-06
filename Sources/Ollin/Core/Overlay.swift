#if os(macOS)
#if canImport(AppKit)

import AppKit
import MetalKit

extension OllinApp {
    /// Run a sketch over the desktop: the piece floats above every other window,
    /// see-through wherever its canvas is, and a click lands on it only where it
    /// drew something. Everywhere else the click goes to whatever is underneath,
    /// so the machine stays in use with the piece on top of it.
    ///
    /// ```swift
    /// @main
    /// enum Fireflies {
    ///     @MainActor static func main() {
    ///         if OllinApp.handleCommandLine(makeSketch: { Swarm() }) { return }
    ///         OllinApp.runAsOverlay { Swarm() }
    ///     }
    /// }
    /// ```
    ///
    /// Any sketch runs this way with `--overlay` on its command line. The sketch
    /// clears its canvas with `background(.clear)`: what it leaves clear is the
    /// desktop showing through.
    ///
    /// A sketch whose canvas follows its view (`windowMode` `.resizable`) covers
    /// the main display; one that states a size floats at that size in the
    /// middle of it. The pointer is the sketch's wherever it is on the display
    /// (`mouseX`, `mouseY`), and its presses reach the sketch where the piece is
    /// under it. The keys stay with whatever is being typed in. A small mark in
    /// the menu bar carries Quit, since a piece with no window frame has nowhere
    /// else to be closed from. See `Docs/Output/Overlay.md`.
    ///
    /// - Parameters:
    ///   - hitTest: decides for itself whether a point of the canvas belongs to
    ///     the piece (true takes the click, false lets it through), given the
    ///     sketch and the point in canvas coordinates. Left out, the piece is
    ///     wherever the last frame it drew is not clear.
    ///   - makeSketch: makes the sketch to run.
    public static func runAsOverlay(hitTest: (@MainActor (Sketch, Vector2) -> Bool)? = nil,
                                    _ makeSketch: @escaping @MainActor () -> Sketch) {
        let app = NSApplication.shared
        // An accessory, as a wallpaper is: no Dock icon, no place in the app
        // switcher, and Quit in its menu-bar mark.
        app.setActivationPolicy(.accessory)
        let host = OverlayHost(makeSketch: makeSketch, hitTest: hitTest)
        OverlayHost.current = host
        app.delegate = host
        app.run()
    }
}

/// The program around an overlay run: one pane on the main display, and the
/// menu-bar mark that quits the piece.
@MainActor
final class OverlayHost: NSObject, NSApplicationDelegate {

    /// The host of the run, held so the application's delegate lives as long as
    /// the application does.
    static var current: OverlayHost?

    private let makeSketch: @MainActor () -> Sketch
    private let hitTest: (@MainActor (Sketch, Vector2) -> Bool)?
    private(set) var pane: OverlayPane?
    private var statusItem: NSStatusItem?

    init(makeSketch: @escaping @MainActor () -> Sketch,
         hitTest: (@MainActor (Sketch, Vector2) -> Bool)?) {
        self.makeSketch = makeSketch
        self.hitTest = hitTest
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let screen = NSScreen.main {
            pane = OverlayPane(screen: screen, sketch: makeSketch(), hitTest: hitTest)
            pane?.show()
        }
        let title = pane?.sketch.title ?? ProcessInfo.processInfo.processName
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: title)
        item.button?.toolTip = title
        item.menu = surfaceQuitMenu(for: title)
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        pane?.close()
        pane = nil
    }
}

/// The piece over the desktop: a borderless, see-through window at the floating
/// level with a running canvas for content, and the hit test that decides,
/// pointer move by pointer move, whether the window is there to be clicked.
@MainActor
final class OverlayPane {

    let sketch: Sketch
    let window: NSWindow
    let canvas: OllinMTKView
    let runner: SketchRunner
    let hits: OverlayHitTester
    private var monitors: [Any] = []

    init?(screen: NSScreen, sketch: Sketch, hitTest: (@MainActor (Sketch, Vector2) -> Bool)? = nil) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.sketch = sketch

        // The whole display for a canvas that follows its view; the canvas's own
        // size, fitted and centered, for one that states it.
        var frame = screen.frame
        if sketchKeepsItsShape(sketch) {
            let size = OllinApp.windowSize(fitting: sketch.canvasSize.cgSize)
            let visible = screen.visibleFrame
            // On whole points, or the window is grown to the next one to cover a half.
            frame = CGRect(x: (visible.midX - size.width / 2).rounded(),
                           y: (visible.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .floating
        window.isReleasedWhenClosed = false
        // See-through: the window has no ground of its own, and no shadow to
        // draw the edge of one.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Nothing to click until a frame says where the piece is.
        window.ignoresMouseEvents = true
        // On every space and over a full-screen program, and out of the window
        // cycle: the piece is not one of the windows being worked in.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let canvas = makeOllinMTKView(device: device, size: sketch.canvasSize.cgSize, sketch: sketch)
        // The pointer and its presses are the sketch's; the keyboard is not.
        canvas.claimsKeyboardOnAttach = false
        canvas.frame = CGRect(origin: .zero, size: frame.size)
        canvas.autoresizingMask = [.width, .height]
        canvas.layer?.isOpaque = false
        (canvas.layer as? CAMetalLayer)?.isOpaque = false
        canvas.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let runner = SketchRunner(sketch: sketch, view: canvas, device: device)
        canvas.delegate = runner
        // The window's own frames carry the canvas's coverage, so what the
        // sketch left clear is the desktop.
        runner.renderer.windowKeepsAlpha = true

        let hits = OverlayHitTester(hitTest: hitTest)
        sketch.extend(hits)

        window.contentView?.addSubview(canvas)
        self.window = window
        self.canvas = canvas
        self.runner = runner
        self.hits = hits
        runner.displayChanged(to: screen)

        hits.onChange = { [weak self] in self?.updatePointer() }
    }

    func show() {
        window.orderFrontRegardless()
        // The pointer moves whether or not the window is taking its events, so
        // both monitors are needed: the global one for moves that pass through
        // to another program, the local one for moves this program was given.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) { monitors.append(local) }
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        canvas.isPaused = true
        canvas.delegate = nil
        canvas.removeFromSuperview()
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Where the pointer is on the canvas, and whether the piece is under it:
    /// the sketch is told the first, and the window is there to be clicked or
    /// not by the second.
    func updatePointer() {
        apply(pointerAt: NSEvent.mouseLocation, buttonsDown: NSEvent.pressedMouseButtons != 0)
    }

    /// The same, for a pointer at `location` in screen coordinates (points up
    /// from the bottom left, as the system reports it).
    func apply(pointerAt location: CGPoint, buttonsDown: Bool) {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return }
        let across = Double((location.x - frame.minX) / frame.width)
        let down = 1 - Double((location.y - frame.minY) / frame.height)
        let inside = across >= 0 && across <= 1 && down >= 0 && down <= 1
        if inside {
            sketch.mouseX = across * sketch.width
            sketch.mouseY = down * sketch.height
        }
        // A press that began on the piece stays the piece's until it is let go,
        // however the picture moves under it.
        if buttonsDown, !window.ignoresMouseEvents { return }
        let takes = inside && hits.takes(sketch: sketch, acrossFraction: across, downFraction: down)
        if window.ignoresMouseEvents == takes { window.ignoresMouseEvents = !takes }
    }
}

/// Whether the piece is under a point of its canvas, from the last frame it
/// drew or from the sketch's own answer.
///
/// With no answer of the sketch's, every other frame is read back at the canvas
/// size and kept, and a point belongs to the piece where that frame is not
/// clear. A frame that was drawn opaque is the piece everywhere.
@MainActor
final class OverlayHitTester: SketchExtension {

    /// Coverage above this is the piece. A hair above nothing, so the last
    /// faint pixel of a soft edge does not take a click.
    static let threshold = 0.05

    private let hitTest: (@MainActor (Sketch, Vector2) -> Bool)?
    /// The last frame read back, with its bytes.
    private var frame: (image: CGImage, bytes: CFData)?
    private var frameNumber = 0
    /// Told when a new frame is in, so the answer under a still pointer follows
    /// the picture.
    var onChange: (() -> Void)?

    init(hitTest: (@MainActor (Sketch, Vector2) -> Bool)?) {
        self.hitTest = hitTest
    }

    // Every other frame: the shape of the piece twenty or thirty times a second
    // is as fast as a hand can tell, at half the read-back.
    nonisolated var wantsRenderedFrame: Bool {
        MainActor.assumeIsolated {
            guard hitTest == nil else { return false }
            frameNumber += 1
            return frameNumber % 2 == 1
        }
    }

    nonisolated func frameRendered(_ sketch: Sketch, image: CGImage) {
        MainActor.assumeIsolated {
            take(image)
            onChange?()
        }
    }

    /// Keep `image` as the frame the answers are read from.
    func take(_ image: CGImage) {
        guard let bytes = image.dataProvider?.data else { return }
        frame = (image, bytes)
    }

    /// The coverage of the kept frame at a point given as fractions of the
    /// canvas (0 to 1 across, 0 to 1 down): 0 clear, 1 covered. An opaque frame
    /// is covered everywhere; with no frame yet, nothing is.
    func coverage(acrossFraction x: Double, downFraction y: Double) -> Double {
        guard let frame else { return 0 }
        let image = frame.image
        let alphaInfo = image.alphaInfo
        guard alphaInfo != .none, alphaInfo != .noneSkipFirst, alphaInfo != .noneSkipLast else { return 1 }
        let px = min(max(Int(x * Double(image.width)), 0), image.width - 1)
        let py = min(max(Int(y * Double(image.height)), 0), image.height - 1)
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = py * image.bytesPerRow + px * bytesPerPixel
        guard offset + bytesPerPixel <= CFDataGetLength(frame.bytes),
              let base = CFDataGetBytePtr(frame.bytes) else { return 0 }
        if image.bitsPerComponent == 16 {
            // Half-float components, the alpha last.
            let bits = UInt16(base[offset + 6]) | (UInt16(base[offset + 7]) << 8)
            return Double(Float(Float16(bitPattern: bits)))
        }
        // Eight bits a component. The alpha is first in the pixel's own order,
        // which little-endian 32-bit storage puts in the last byte, or last in
        // it, which that storage puts first.
        let little = image.bitmapInfo.contains(.byteOrder32Little)
        let alphaFirst = alphaInfo == .first || alphaInfo == .premultipliedFirst
        let index = (alphaFirst == little) ? 3 : 0
        return Double(base[offset + index]) / 255
    }

    /// Whether a click at that point of the canvas is the piece's.
    func takes(sketch: Sketch, acrossFraction x: Double, downFraction y: Double) -> Bool {
        if let hitTest {
            return hitTest(sketch, Vector2(x * sketch.width, y * sketch.height))
        }
        return coverage(acrossFraction: x, downFraction: y) > Self.threshold
    }
}

#endif
#endif
