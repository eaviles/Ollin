import Ollin
import OllinScreen

/// Takes the Mac's own screen as material. The whole display, one app, or a
/// single window arrives as a live image, so anything running on the machine can
/// be drawn, filtered, and composited: a browser, a map, a video call, a
/// terminal, another sketch.
///
/// The knob worth turning first is `tunnel`. By default the sketch's own window
/// is cut out of the capture, so pointing it at the screen it is drawn on shows
/// everything except itself. Turn `tunnel` on and the sketch is left in the
/// picture, so it draws a screen containing a window drawing a screen containing
/// a window, and the image recedes into itself. That is the oldest trick in
/// video art, and it costs one boolean here.
///
/// `look` proves the frames are ordinary images: they go through the same filter
/// catalog as anything else drawn. `detail` trades captured pixels for speed, and
/// is the knob to reach for on a large display.
///
/// Press `L` to list what this Mac can currently capture, with the line of code
/// that names each one. Capturing needs the screen-recording permission; if it is
/// off, the sketch says so on the canvas and tells you where to turn it on.
@main
final class ScreenCaptureExample: Sketch {

    enum Look: String, CaseIterable, ParamOption {
        case plain, bloom, posterize, edges
    }

    @Param(icon: "arrow.triangle.2.circlepath") var tunnel = false
    @Param(icon: "camera.filters") var look = Look.plain
    @Param(0.25 ... 1, icon: "square.resize") var detail = 1.0

    private let screen = ScreenCapture(.mainDisplay)
    private var listing: [String] = []
    private var showsListing = false

    override func setup() {
        screen.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        screen.excludesOwnWindows = !tunnel
        screen.scale = detail

        guard let frame = screen.frame,
              let rect = screen.fittedRectangle(in: bounds) else {
            drawStatus(screen.waitingMessage, style: ScreenCapture.isAvailable ? .info : .warning)
            return
        }

        if look == .plain {
            drawImage(frame, in: rect)
        } else {
            // The capture is an ordinary image, so it goes through the effect
            // graph like anything else the sketch draws.
            let layer = makeRenderTarget()
            withTarget(layer) {
                background(.black)
                drawImage(frame, in: bounds)
            }
            drawImage(layer.filtered(filter).image, in: bounds)
        }

        drawLabel()
        if showsListing { drawListing() }
    }

    private var filter: Filter {
        switch look {
        case .plain:     return .exposure(stops: 0)
        case .bloom:     return .bloom(threshold: 0.55, amount: 0.7, radius: 12)
        case .posterize: return .posterize(levels: 5)
        case .edges:     return .edges(amount: 2.2)
        }
    }

    override func keyPressed() {
        guard key == "l" || key == "L" else { return }
        showsListing.toggle()
        guard showsListing else { return }
        // Enumerating is asynchronous, so the listing lands a moment later and
        // the sketch keeps drawing in the meantime.
        Task { @MainActor in
            var lines: [String] = ["Displays"]
            for display in await ScreenCapture.displays() {
                lines.append("  .display(\(display.id))   \(display.label)")
            }
            lines.append("Apps")
            for app in await ScreenCapture.apps().prefix(12) {
                lines.append("  .app(\"\(app.name)\")")
            }
            lines.append("Windows")
            for window in await ScreenCapture.windows().prefix(12) {
                guard let title = window.title, !title.isEmpty else { continue }
                lines.append("  .window(title: \"\(title)\")")
            }
            listing = lines
        }
    }

    private func drawLabel() {
        let name = tunnel ? "the screen, this window included" : "the screen, this window left out"
        fill(Color(white: 0.85))
        textSize(20 * scale)
        drawText(name, 26 * scale, 40 * scale)
        fill(Color(white: 0.5))
        textSize(16 * scale)
        drawText("L lists what can be captured", 26 * scale, 66 * scale)
    }

    private func drawListing() {
        let lines = listing.isEmpty ? ["Looking…"] : listing
        let box = Rectangle(x: 26 * scale, y: 90 * scale,
                            width: width - 52 * scale,
                            height: Double(lines.count) * 20 * scale + 24 * scale)
        fill(Color(white: 0, alpha: 0.72))
        noStroke()
        drawRect(box)
        textSize(15 * scale)
        for (index, line) in lines.enumerated() {
            fill(line.hasPrefix("  ") ? Color(white: 0.72) : Color(hex: 0x7FD4FF))
            drawText(line, box.x + 14 * scale, box.y + (Double(index) + 1) * 20 * scale)
        }
    }
}
