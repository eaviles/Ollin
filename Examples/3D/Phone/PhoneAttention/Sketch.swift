import Foundation
import Ollin
import OllinPhone

/// Where the phone's picture draws the eye, live from a tethered iPhone: the
/// camera frame with the attention heat map over it as a warm glow, a frame
/// around each region the model picked out, and an eased bead riding the
/// strongest one, trailing where the attention has been.
///
/// Setup: install **Ollin Capture** on an iPhone, launch it, tap **Attention**
/// (rear camera), and connect the cable. The connection retries on its own, so
/// tapping the mode (or plugging in) after this sketch is already running just
/// begins the feed.
///
/// The heat map is coarse on purpose (the model's own resolution); stretched
/// over the frame it reads as a soft spotlight. `salience(at:in:)` can read the
/// value under any canvas point, so the same surface drives stippling or
/// particles. On a LiDAR phone each region's center also stands in ARKit world
/// space, which this overlay reports in its caption.
@main
final class PhoneAttention: Sketch {

    let device = PhoneDevice()

    let glowColor = Color(hex: 0xFFB84D)
    let frameColor = Color(hex: 0x7FE0D4)

    /// The bead riding the strongest region, eased so a jumpy model reads as a
    /// wandering gaze, and the places it has been.
    var eye: Vector2?
    var trail: [Vector2] = []

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(hex: 0x0D1017))

        guard let attention = device.latestSaliency,
              let frame = device.latestSaliencyFrame else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on an iPhone, tap Attention (rear\n" +
                              "camera), and connect the cable.", style: .info)
        }

        // Letterbox the camera frame into the canvas; the heat map and every
        // region box share the same rectangle, so everything lines up.
        let frameSize = Vector2(Double(frame.width), Double(frame.height))
        let rect = Rectangle(fitting: frameSize, in: canvasRectangle)
        drawImage(frame, in: rect)

        // The heat as a warm glow: the coarse map stretched over the picture.
        if let heat = device.latestSaliencyHeatMap {
            tint(glowColor.withAlpha(0.75))
            drawImage(heat, in: rect)
            noTint()
        }

        // A frame around each region, its weight following the model's trust.
        for region in attention.regions {
            withState {
                noFill()
                stroke(frameColor.withAlpha(0.4 + 0.6 * region.confidence))
                strokeWeight(2 + 3 * region.confidence)
                drawRect(region.bounds(in: rect), cornerRadius: 10)
            }
        }

        drawEye(toward: attention.strongestRegion?.center(in: rect))

        let lifted = attention.regions.contains(where: \.hasWorldPlacement)
        let counted = attention.regions.count
        drawCaption("PhoneAttention: \(counted) \(counted == 1 ? "region" : "regions")"
                    + (lifted ? ", centers placed in the room" : ""))
    }

    /// Ease the bead toward the strongest region and fade a trail behind it, so
    /// the picture keeps a memory of where the attention has been.
    private func drawEye(toward target: Vector2?) {
        if let target {
            let current = eye ?? target
            eye = current + (target - current) * 0.12
        }
        guard let eye else { return }
        trail.append(eye)
        if trail.count > 90 { trail.removeFirst() }

        noStroke()
        for (i, p) in trail.enumerated() {
            let age = Double(i) / Double(max(trail.count - 1, 1))
            fill(glowColor.withAlpha(0.25 * age))
            drawCircle(p.x, p.y, 4 + 6 * age)
        }
        fill(.white)
        drawCircle(eye.x, eye.y, 7)
        noFill()
        stroke(glowColor)
        strokeWeight(2)
        drawCircle(eye.x, eye.y, 14)
    }
}
