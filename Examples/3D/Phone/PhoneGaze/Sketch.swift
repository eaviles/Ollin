import Foundation
import Ollin
import OllinPhone

/// Where the eyes point, streamed live from the phone in **Face** mode. Each tracked
/// face stands in the room as its wireframe net, posed by the full head transform; a
/// pair of solid eyeballs sits at the streamed eye poses, each squinting shut with
/// its blink blendshape; and a beam runs from each eye to the look-at point the two
/// converge on, marked by a warm bead. Look around and the beams sweep the room.
///
/// Setup: run Ollin Capture (Apps/OllinPhoneApp) on the iPhone, connect the cable,
/// tap **Face**, and look at the phone's front camera, then past it. The bead is
/// where ARKit reads your gaze. The connection retries on its own.
@main
final class PhoneGaze: Sketch {

    let device = PhoneDevice()

    // Eased frame-to-frame so live head motion doesn't jitter the orbit.
    var orbitCenter: Vector3?

    let netColor = Color(hex: 0x9FB4D8)
    let beadColor = Color(hex: 0xFFB060)

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

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

        // Aim between the heads and their gaze targets so both stay in frame.
        var center = Vector3.zero
        for face in faces { center += face.headPosition.lerp(to: face.worldLookAtPoint, 0.4) }
        center = center / Double(faces.count)
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.1) } else { orbitCenter = center }
        let radius = 0.75 + Double(faces.count - 1) * 0.3
        cameraShowcase(.turntable(period: .tau / 0.35), target: orbitCenter ?? center,
                       radius: radius, elevation: 0.08, fieldOfView: .pi / 3)

        environment(.studio.intensity(0.85))

        for face in faces { drawFace(face) }

        let n = faces.count
        drawCaption("PhoneGaze, \(n) \(n == 1 ? "face" : "faces") · the bead is where the eyes converge")
    }

    /// One face: the net at its head pose, the eyeballs, the beams, and the bead.
    private func drawFace(_ face: PhoneFace) {
        // The net, stood at the full head pose so the eyes sit inside it.
        withState {
            transform(face.headTransform)
            wireframe()
            strokeWeight(1.0)
            stroke(netColor)
            drawMesh(face.mesh())
        }

        let target = face.worldLookAtPoint
        for eye in PhoneEye.allCases {
            let at = face.worldEyePosition(eye)
            let gaze = face.worldGazeDirection(eye)
            let blink = face.blendShape(eye == .left ? .eyeBlinkLeft : .eyeBlinkRight)

            // The eyeball, squashed shut as the lid closes, with a dark pupil
            // riding its own gaze direction.
            withState {
                material(.clay)
                fill(.white)
                translate(at)
                scale(1, 1 - blink * 0.8, 1)
                drawSphere(radius: 0.012)
            }
            withState {
                material(.matte)
                fill(Color(white: 0.08))
                translate(at + gaze * 0.0105)
                drawSphere(radius: 0.0045)
            }

            // The beam, eye to convergence point.
            withState {
                material(.matte)
                fill(beadColor)
                drawCapsule(from: at + gaze * 0.014, to: target, radius: 0.0018)
            }
        }

        // The bead where the two beams meet.
        withState {
            material(.clay)
            fill(beadColor)
            translate(target)
            drawSphere(radius: 0.009)
        }
    }
}
