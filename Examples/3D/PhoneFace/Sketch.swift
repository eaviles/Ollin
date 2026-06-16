import Foundation
import Ollin
import OllinPhone

/// A live face mesh and its expression, streamed from a tethered iPhone running the
/// **Ollin** capture app in **Face** mode — the front-camera sibling of
/// `PhoneBodyPose`. The phone runs ARKit face tracking on its Neural Engine and
/// streams the deforming mesh plus the 52 expression blendshapes; the Mac orbits the
/// mesh as a point cloud and reads the expression off the blendshapes.
///
/// Setup: run Ollin Capture (Apps/OllinPhoneApp) on the iPhone, connect the cable,
/// tap **Face**, and look at the phone's front camera. Smile, blink, open your mouth
/// — the cloud deforms and the bars move. The connection retries on its own.
@main
final class PhoneFace3D: Sketch {

    let device = PhoneDevice()

    // The few expressions to chart, with friendly labels.
    let charted: [(PhoneBlendShape, String)] = [
        (.jawOpen, "jaw open"),
        (.mouthSmileLeft, "smile L"), (.mouthSmileRight, "smile R"),
        (.mouthPucker, "pucker"),
        (.eyeBlinkLeft, "blink L"), (.eyeBlinkRight, "blink R"),
        (.browInnerUp, "brow up"), (.cheekPuff, "cheeks"),
    ]

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

        guard let face = device.latestFace, !face.meshPoints.isEmpty else {
            var text = device.waitingMessage + "\n\n" +
                "Run Ollin Capture on the iPhone, connect the cable,\n" +
                "tap Face, and look at the front camera."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        drawMesh(face)
        drawExpressionBars(face)

        let state = face.isTracked ? "tracking" : "extrapolating"
        drawCaption("PhoneFace — \(state), \(face.meshPoints.count) verts; drag to spin")
    }

    /// The face mesh, orbited and colored by depth, warmed as the mouth opens.
    private func drawMesh(_ face: PhoneFace) {
        let azimuth = mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : time * 0.4
        camera(.orbiting(target: .zero, radius: 0.42, azimuth: azimuth,
                         elevation: 0.04, fieldOfView: .pi / 3))

        // Warm the whole face toward orange as the jaw opens — a visible read of one
        // blendshape driving the look.
        let warmth = face.blendShape(.jawOpen)
        let cool = Color(hex: 0x9FB4D8), warm = Color(hex: 0xFFB060)
        let tint = Color.mix(cool, warm, t: warmth, in: .oklch)

        var cloud = PointCloud()
        for p in face.meshPoints {
            // Fade the back of the head out so the front face reads clearly.
            var c = tint
            c.alpha = map(p.z, -0.08, 0.06, 0.25, 1.0, clamp: true)
            cloud.add(p, color: c, size: 0.0045)
        }
        drawPointCloud(cloud)
    }

    /// A column of expression bars (a 2D HUD over the 3D scene). Sizes are fractions
    /// of the canvas width, so the layout holds at any `canvasSize`.
    private func drawExpressionBars(_ face: PhoneFace) {
        let barW = width * 0.2, barH = width * 0.013, gap = width * 0.009
        let x = width * 0.037, top = width * 0.045

        textFont(OutlineFont.system)
        textSize(width * 0.014)
        textAlign(.left, .middle)
        noStroke()

        for (i, entry) in charted.enumerated() {
            let y = top + Double(i) * (barH + gap)
            let v = face.blendShape(entry.0)

            fill(Color(white: 1, alpha: 0.12))
            drawRect(x, y, barW, barH)
            fill(Color.mix(Color(hex: 0x4A88FF), Color(hex: 0xFF5C7A), t: v, in: .oklch))
            drawRect(x, y, barW * v, barH)

            fill(Color(white: 0.9))
            drawText(entry.1, x + barW + width * 0.01, y + barH * 0.5)
        }
    }
}
