import Foundation
import Ollin
import OllinPhone

/// A live face mesh and its expression, streamed from a tethered iPhone running the
/// **Ollin** capture app in **Face** mode — the front-camera sibling of
/// `PhoneBodyPose`. The phone runs ARKit face tracking on its Neural Engine and
/// streams the deforming mesh (with its triangle topology) plus the 52 expression
/// blendshapes; the Mac orbits the mesh as a wireframe net (the recognizable AR face
/// mesh) and reads the expression off the blendshapes.
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

    /// All tracked face meshes, each drawn as a wireframe net at its head position so
    /// several people sit apart in space, orbited as one and warmed as each jaw opens.
    private func drawMeshes(_ faces: [PhoneFace]) {
        // A base hue per face so people read apart; each warms toward orange as its
        // jaw opens — a visible read of one blendshape driving the look.
        let baseColors = [Color(hex: 0x9FB4D8), Color(hex: 0xFFB060), Color(hex: 0x8AE0A0)]
        let warm = Color(hex: 0xFFB060)

        var center = Vector3.zero
        for face in faces { center += face.headPosition }
        center = center / Double(faces.count)

        // Widen the orbit as more faces spread out so they all stay in frame.
        let radius = 0.42 + Double(faces.count - 1) * 0.3
        cameraShowcase(.turntable(period: .tau / 0.4), target: center, radius: radius,
                    elevation: 0.04, fieldOfView: .pi / 3)

        // Each face as its triangle net — the recognizable AR face mesh — placed at its
        // head's world position.
        wireframe()
        strokeWeight(1.2)
        for (i, face) in faces.enumerated() {
            let tint = Color.mix(baseColors[i % baseColors.count], warm,
                                 t: face.blendShape(.jawOpen), in: .oklch)
            withState {
                translate(face.headPosition)
                stroke(tint)
                drawMesh(face.mesh())
            }
        }
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
