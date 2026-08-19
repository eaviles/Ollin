// figure: frame=0
//
// Guide figure (Chapter 21): two hands from the phone's hand stream, drawn as
// small solid skeletons. The orange one is a right hand held open; the blue one
// is a left hand closing a pinch, and the white bead sits where thumb tip and
// index tip meet. Chirality picks the color, the 21 joints make the bones, and
// pinchDistance is the one number the bead hangs off.
//
// The hands are staged rather than tracked, the way this chapter's other figures
// stage a depth camera: the same PhoneHand a phone fills in, built by hand from a
// PhoneHandSample so the figure renders anywhere.
import Foundation
import simd
import Ollin
import OllinPhone

final class HandsAsSkeletons: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let rightColor = Color(hex: 0xE8A34F)
    let leftColor = Color(hex: 0x6FA8E8)

    /// A believable 21-joint hand out of plain numbers: four fingers fan up out
    /// of the palm, the thumb leans sideways, and a pinching hand curls thumb
    /// and index until the tips nearly meet.
    static func stagedHand(at base: Vector3, chirality: PhoneHandChirality,
                           pinch: Bool) -> PhoneHand {
        let side: Double = chirality == .right ? 1 : -1
        var joints: [PhoneHandJoint: PhoneHandJointSample] = [:]

        func put(_ joint: PhoneHandJoint, _ p: Vector3) {
            joints[joint] = PhoneHandJointSample(
                point: SIMD2<Float>(0.5, 0.5), confidence: 0.9,
                hasWorldPosition: true,
                worldPosition: SIMD3<Float>(Float(base.x + side * p.x), Float(base.y + p.y),
                                            Float(base.z + p.z)))
        }

        put(.wrist, .zero)

        let chains: [(PhoneHandJoint, PhoneHandJoint, PhoneHandJoint, PhoneHandJoint, Double)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.018),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, -0.002),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.014),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.030),
        ]
        for (mcp, pip, dip, tip, spread) in chains {
            let curled = pinch && mcp == .indexMCP
            let x = spread
            put(mcp, Vector3(x, 0.085, 0))
            if curled {
                put(pip, Vector3(x - 0.006, 0.115, 0.016))
                put(dip, Vector3(x - 0.016, 0.122, 0.030))
                put(tip, Vector3(x - 0.028, 0.118, 0.038))
            } else {
                put(pip, Vector3(x, 0.122, 0.004))
                put(dip, Vector3(x, 0.150, 0.008))
                put(tip, Vector3(x, 0.173, 0.012))
            }
        }

        if pinch {
            put(.thumbCMC, Vector3(-0.030, 0.020, 0.010))
            put(.thumbMP, Vector3(-0.042, 0.052, 0.024))
            put(.thumbIP, Vector3(-0.040, 0.086, 0.034))
            put(.thumbTip, Vector3(-0.033, 0.112, 0.040))
        } else {
            put(.thumbCMC, Vector3(-0.032, 0.018, 0.006))
            put(.thumbMP, Vector3(-0.052, 0.048, 0.012))
            put(.thumbIP, Vector3(-0.064, 0.074, 0.016))
            put(.thumbTip, Vector3(-0.073, 0.096, 0.018))
        }

        return PhoneHand(PhoneHandSample(tracked: true, timestamp: 0, chirality: chirality,
                                         confidence: 0.95, joints: joints))
    }

    lazy var open = Self.stagedHand(at: Vector3(-0.115, 0, 0), chirality: .right, pinch: false)
    lazy var pinch = Self.stagedHand(at: Vector3(0.115, 0.01, -0.02), chirality: .left, pinch: true)

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: Vector3(0, 0.09, 0), radius: 0.55,
                         azimuth: 0.32, elevation: 0.16, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.0).lightingOnly())

        for hand in [open, pinch] {
            let tone = hand.chirality == .right ? rightColor : leftColor
            withState {
                material(.clay)
                fill(tone)
                for (a, b) in hand.bones() { drawCapsule(from: a, to: b, radius: 0.006) }
                for joint in PhoneHandJoint.allCases {
                    guard let p = hand.position(joint) else { continue }
                    let tip = PhoneHand.tips.contains(joint)
                    withState {
                        translate(p.x, p.y, p.z)
                        drawSphere(radius: tip ? 0.011 : 0.008)
                    }
                }
            }
            // The pinch, worn as one bright bead between the fingertips.
            if let d = hand.pinchDistance, d < 0.025,
               let thumb = hand.position(.thumbTip), let index = hand.position(.indexTip) {
                let mid = thumb.lerp(to: index, 0.5)
                withState {
                    material(.glossy)
                    fill(.white)
                    translate(mid.x, mid.y, mid.z)
                    drawSphere(radius: 0.017)
                }
            }
        }
    }
}
