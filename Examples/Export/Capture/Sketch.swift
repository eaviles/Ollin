import AppKit
import Ollin

/// The frame-grab seam: an extension that receives the *rendered* frame and
/// saves it to a PNG, without `draw()` knowing about it.
///
/// `FrameSaver` is a `SketchExtension`. It only asks for the rendered frame
/// while a capture is armed (`wantsRenderedFrame` returns `armed`), so the
/// sketch pays the grab's readback cost only on the frame it saves — the rest
/// of the time it runs full speed. Press **S** to save the current frame; the
/// path is printed and a ring flashes to confirm.
@main
final class Capture: Sketch {
    private let saver = FrameSaver()

    override func setup() {
        extend(saver)
    }

    override func draw() {
        background(Color(white: 0.07))
        // A slow rosette of orbiting dots — just something worth capturing.
        let c = Vector2(width / 2, height / 2)
        noStroke()
        let count = 12
        for i in 0..<count {
            let a = Double(i) / Double(count) * .tau + time * 0.3
            let r = min(width, height) * 0.32 * (0.6 + 0.4 * sin(time + Double(i)))
            let p = c + Vector2(cos(a), sin(a)) * r
            fill(CosinePalette.rainbow.color(at: Double(i) / Double(count)))
            drawCircle(center: p, radius: 46 * scale)
        }
    }

    override func keyPressed() {
        if key == "s" || key == "S" { saver.capture() }
    }
}

/// Saves the rendered frame to a PNG when armed, and flashes a ring for a moment
/// afterward to confirm. `wantsRenderedFrame` is `true` only while armed, so the
/// loop grabs the frame just for the save and nothing more.
final class FrameSaver: SketchExtension {
    private var armed = false
    private var flash = 0          // frames left to show the "saved" ring

    /// Arm a one-frame capture: the next rendered frame is saved, then disarms.
    func capture() { armed = true }

    var wantsRenderedFrame: Bool { armed }

    func afterDraw(_ sketch: Sketch) {
        guard flash > 0 else { return }
        flash -= 1
        sketch.withState {
            sketch.noFill()
            sketch.stroke(Color(red: 0.95, green: 0.3, blue: 0.3, alpha: Double(flash) / 30))
            sketch.strokeWeight(10 * sketch.scale)
            sketch.drawCircle(sketch.width / 2, sketch.height / 2, min(sketch.width, sketch.height) * 0.46)
        }
    }

    func frameRendered(_ sketch: Sketch, _ image: CGImage) {
        armed = false                // one frame only
        flash = 30                   // confirm on the frames after (kept out of the saved PNG)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(format: "ollin-frame-%05d.png", sketch.frameCount))
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            print("Saved \(image.width)×\(image.height) frame → \(url.path)")
        } catch {
            print("Capture: failed to write \(url.path): \(error)")
        }
    }
}
