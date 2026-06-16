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

        // Every face the phone is tracking (TrueDepth handles up to 3), with a mesh
        // to draw.
        let faces = device.latestFaces.filter { !$0.meshPoints.isEmpty }
        guard !faces.isEmpty else {
            var text = device.waitingMessage + "\n\n" +
                "Run Ollin Capture on the iPhone, connect the cable,\n" +
                "tap Face, and look at the front camera."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        // Sort left-to-right by head position so each face keeps a steady color.
        let ordered = faces.sorted { $0.headPosition.x < $1.headPosition.x }
        drawMeshes(ordered)
        drawExpressionBars(ordered[0])    // bars track the leftmost face

        let n = ordered.count
        let tracking = ordered.filter { $0.isTracked }.count
        drawCaption("PhoneFace — \(n) \(n == 1 ? "face" : "faces"), \(tracking) tracking; drag to spin")
    }

    /// All tracked face meshes, each placed at its head position so several people
    /// sit apart in space, orbited as one and warmed as each jaw opens.
    private func drawMeshes(_ faces: [PhoneFace]) {
        // A base hue per face so people read apart; each warms toward orange as its
        // jaw opens — a visible read of one blendshape driving the look.
        let baseColors = [Color(hex: 0x9FB4D8), Color(hex: 0xFFB060), Color(hex: 0x8AE0A0)]
        let warm = Color(hex: 0xFFB060)

        var cloud = PointCloud()
        var center = Vector3.zero
        for (i, face) in faces.enumerated() {
            let tint = Color.mix(baseColors[i % baseColors.count], warm,
                                 t: face.blendShape(.jawOpen), in: .oklch)
            for p in face.meshPoints {
                // Place the face-local mesh at its head's world position, and fade the
                // back of the head out so the front reads clearly.
                var c = tint
                c.alpha = map(p.z, -0.08, 0.06, 0.25, 1.0, clamp: true)
                cloud.add(p + face.headPosition, color: c, size: 0.0045)
            }
            center += face.headPosition
        }
        center = center / Double(faces.count)

        // Widen the orbit as more faces spread out so they all stay in frame.
        let azimuth = mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : time * 0.4
        let radius = 0.42 + Double(faces.count - 1) * 0.3
        camera(.orbiting(target: center, radius: radius, azimuth: azimuth,
                         elevation: 0.04, fieldOfView: .pi / 3))
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
