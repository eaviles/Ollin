import Foundation
import Ollin
import OllinPhone

/// The hands the phone sees, standing in the room as solid little skeletons. The
/// capture app finds up to four 21-joint hands on-device and lifts each joint to
/// metric 3D through the LiDAR depth, so a hand here floats where the real hand
/// is, in meters, in the same world the depth sweep and the room mesh use. Left
/// and right wear their own color, a pinch closes into a bright bead at the
/// fingertips, and on a phone with no LiDAR the same stream arrives flat and
/// draws as a 2D overlay instead.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// choose **Hands**, connect the cable, and hold a hand in front of the rear
/// camera. Pinch: thumb to index closes the bead.
@main
final class PhoneHands: Sketch {

    let device = PhoneDevice()

    /// Where the orbit looks, eased frame-to-frame so live noise doesn't jitter it.
    var orbitCenter: Vector3?

    let rightColor = Color(hex: 0xE8A34F)      // warm for right hands
    let leftColor = Color(hex: 0x6FA8E8)       // cool for left
    let unknownColor = Color(white: 0.75)

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

        let hands = device.latestHands
        guard !hands.isEmpty else {
            var text = device.waitingMessage + "\n\n" +
                "Run the Ollin capture app on the iPhone in Hands mode,\n" +
                "connect the cable, and hold a hand in front of its rear camera."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        let lifted = hands.filter(\.hasWorldPositions)
        if lifted.isEmpty {
            drawFlatHands(hands)
        } else {
            drawLiftedHands(lifted)
        }
        drawCaption(caption(for: hands, lifted: !lifted.isEmpty))
    }

    // MARK: The 3D room (a LiDAR phone)

    private func drawLiftedHands(_ hands: [PhoneHand]) {
        // Aim at the middle of everything lifted; a hand is small, so orbit close.
        var center = Vector3.zero
        for hand in hands { center += hand.center }
        center /= Double(hands.count)
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.1) } else { orbitCenter = center }
        cameraShowcase(.turntable(period: .tau / 0.35), target: orbitCenter ?? center,
                       radius: 0.9, elevation: 0.15, fieldOfView: .pi / 3)
        environment(.studio.intensity(0.9))

        for hand in hands {
            let tone = color(of: hand)
            withState {
                material(.clay)
                fill(tone)
                for (a, b) in hand.bones() {
                    drawCapsule(from: a, to: b, radius: 0.006)
                }
                for joint in PhoneHandJoint.allCases {
                    guard let p = hand.position(joint) else { continue }
                    let tip = PhoneHand.tips.contains(joint)
                    withState {
                        translate(p.x, p.y, p.z)
                        drawSphere(radius: tip ? 0.011 : 0.008)
                    }
                }
            }
            // A closed pinch turns into one bright bead between the fingertips.
            if let d = hand.pinchDistance, d < 0.025,
               let thumb = hand.position(.thumbTip), let index = hand.position(.indexTip) {
                let mid = thumb.lerp(to: index, 0.5)
                withState {
                    material(.glossy)
                    fill(.white)
                    translate(mid.x, mid.y, mid.z)
                    drawSphere(radius: 0.014)
                }
            }
        }
    }

    // MARK: The flat overlay (no LiDAR to lift through)

    private func drawFlatHands(_ hands: [PhoneHand]) {
        for hand in hands {
            let tone = color(of: hand)
            withState {
                stroke(tone)
                strokeWeight(6)
                for (a, b) in hand.bones(in: bounds) { drawLine(a, b) }
                noStroke()
                fill(tone)
                for (_, p) in hand.points(in: bounds) {
                    drawCircle(center: p, radius: 9)
                }
            }
        }
    }

    // MARK: Shared

    private func color(of hand: PhoneHand) -> Color {
        switch hand.chirality {
        case .right: return rightColor
        case .left: return leftColor
        case .unknown: return unknownColor
        }
    }

    private func caption(for hands: [PhoneHand], lifted: Bool) -> String {
        var parts = ["PhoneHands, \(hands.count) in view · \(lifted ? "3D" : "2D, no LiDAR")"]
        for hand in hands {
            guard let d = hand.pinchDistance else { continue }
            let side = hand.chirality == .left ? "left" : "right"
            parts.append(String(format: "%@ pinch %.0f mm", side, d * 1000))
        }
        return parts.joined(separator: " · ")
    }
}
