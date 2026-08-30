import Foundation
import Ollin
import OllinPhone

/// A solid mannequin posed live by the phone's body stream, standing where the
/// person stands. Where PhoneBodyPose draws the joints as dots in the skeleton's
/// own space, this one reads the richer half of the stream: the world anchor
/// stands the figure in the room, each joint's orientation turns a solid part,
/// the estimated scale sizes the parts to the person, and the per-joint tracked
/// flag tints what the camera saw apart from what the rig filled in.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// choose **Body**, connect the cable, and stand in front of the rear camera.
/// Walk around: the figure crosses the sketch's world the way you cross the room.
@main
final class PhoneBodyFigure: Sketch {

    let device = PhoneDevice()

    // Framing and ground, eased frame-to-frame so live sensor noise doesn't
    // jitter the view or bounce the floor with each step.
    var orbitCenter: Vector3?
    var floorY: Double?

    // What the camera saw vs. what the rig filled in.
    let seenColor = Color(hex: 0xEDE7DA)
    let filledColor = Color(hex: 0x5C6B8A)

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

        guard let body = device.latestBody, !body.positions.isEmpty else {
            var text = device.waitingMessage + "\n\n" +
                "Run the Ollin capture app on the iPhone in Body mode,\n" +
                "connect the cable, and stand in front of its rear camera."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        // Aim at where the person really stands (world space, meters from where
        // the phone's session began).
        let center = body.worldCenter
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.1) } else { orbitCenter = center }
        cameraShowcase(.turntable(period: .tau / 0.35), target: orbitCenter ?? center, radius: 3.2,
                       elevation: 0.18, fieldOfView: .pi / 3)

        environment(.studio.intensified(to: 0.9))

        drawFloor(under: body)
        drawFigure(body)

        let state = body.isTracked ? "tracking" : "extrapolating"
        let at = body.worldTransform.columns.3
        drawCaption(String(format: "PhoneBodyFigure, %@ · scale %.2f · standing at (% .1f, % .1f) m",
                           state, body.scaleFactor, Double(at.x), Double(at.z)))
    }

    /// Capsule limbs strung between the joints' world positions, plus oriented
    /// parts wherever a rotation shows: the torso leans and twists with the
    /// spine, the head turns, the hands ride their wrists.
    private func drawFigure(_ body: PhoneBody) {
        let s = body.scaleFactor
        for (a, b) in PhoneBody.skeleton {
            guard let pa = body.worldPosition(a), let pb = body.worldPosition(b) else { continue }
            let seen = body.isJointTracked(a) && body.isJointTracked(b)
            withState {
                material(.clay)
                fill(seen ? seenColor : filledColor)
                drawCapsule(from: pa, to: pb, radius: 0.032 * s)
            }
        }
        part(body, at: .spine) {
            drawRoundedBox(width: 0.30 * s, height: 0.34 * s, depth: 0.16 * s, radius: 0.05 * s)
        }
        // The nose cone shows which way the head faces. Which local axis points
        // forward is a device check: if the nose sits backward, negate the z here.
        part(body, at: .head) {
            drawSphere(radius: 0.11 * s)
            translate(0, 0.02 * s, 0.10 * s)
            drawSphere(radius: 0.035 * s)
        }
        for hand: PhoneJoint in [.leftHand, .rightHand] {
            part(body, at: hand) {
                drawRoundedBox(width: 0.05 * s, height: 0.11 * s, depth: 0.03 * s, radius: 0.012 * s)
            }
        }
    }

    /// Stand one solid part at a joint: the joint's full world pose (orientation
    /// and position composed) goes onto the transform stack in one `transform` call.
    private func part(_ body: PhoneBody, at joint: PhoneJoint, _ piece: () -> Void) {
        guard let pose = body.worldTransform(ofJoint: joint) else { return }
        withState {
            material(.clay)
            fill(body.isJointTracked(joint) ? seenColor : filledColor)
            transform(pose)
            piece()
        }
    }

    /// A slab under the lowest foot, eased so a step doesn't bounce the ground.
    private func drawFloor(under body: PhoneBody) {
        let feet = [PhoneJoint.leftFoot, .rightFoot, .leftAnkle, .rightAnkle]
            .compactMap { body.worldPosition($0)?.y }
        guard let lowest = feet.min() else { return }
        let y = floorY.map { $0 + (lowest - $0) * 0.1 } ?? lowest
        floorY = y
        let c = body.worldCenter
        withState {
            material(.matte)
            fill(Color(white: 0.14))
            translate(c.x, y - 0.02, c.z)
            drawBox(width: 4, height: 0.02, depth: 4)
        }
    }
}
