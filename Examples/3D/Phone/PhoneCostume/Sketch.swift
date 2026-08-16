//  Inspired by "Super You" by Universal Everything (universaleverything.com/projects/super-you),
//  the 2020 AR app that dresses a tracked body in animated costumes. Original
//  Ollin interpretation with no code lineage; not affiliated with or endorsed by
//  Universal Everything.
import Foundation
import Ollin
import OllinPhone

/// A costume worn by the phone's live body stream. The person is a dark
/// silhouette; the costume is the color. **1** dresses them in ribbons, trails
/// the joints leave behind as they move, so the costume only exists in motion.
/// **2** dresses them in plumage, feathers fanned around each bone whose twist
/// follows the joint's own rotation, so turning a wrist turns its feathers.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// choose **Body**, connect the cable, and move. The costume sizes itself to the
/// person, and a joint the camera loses fades its part of the costume.
@main
final class PhoneCostume: Sketch {

    let device = PhoneDevice()

    enum Costume { case ribbons, plumage }
    var costume = Costume.ribbons

    // Ribbon trails: a short world-position history per joint, appended only when
    // a fresh sample arrives (draw() outruns the stream, and repeating a stale
    // position would collapse the trail into a knot).
    var trails: [PhoneJoint: [Vector3]] = [:]
    var lastTimestamp: Double?

    var orbitCenter: Vector3?
    var floorY: Double?

    let palette = [Color(hex: 0xFF5A5F), Color(hex: 0xFFB400), Color(hex: 0x00C2A8),
                   Color(hex: 0x7A5CFF), Color(hex: 0xF2F2F2)]
    let trailJoints: [PhoneJoint] = [.head, .leftWrist, .leftHand, .rightWrist, .rightHand,
                                     .leftElbow, .rightElbow, .leftAnkle, .rightAnkle,
                                     .leftFoot, .rightFoot, .chest]

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(hex: 0x101015))

        guard let body = device.latestBody, !body.positions.isEmpty else {
            var text = device.waitingMessage + "\n\n" +
                "Run the Ollin capture app on the iPhone in Body mode,\n" +
                "connect the cable, and move in front of its rear camera."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        if body.timestamp != lastTimestamp {
            lastTimestamp = body.timestamp
            extendTrails(with: body)
        }

        let center = body.worldCenter
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.1) } else { orbitCenter = center }
        cameraShowcase(.turntable(period: .tau / 0.3), target: orbitCenter ?? center, radius: 3.0,
                       elevation: 0.15, fieldOfView: .pi / 3)
        environment(.studio.intensity(0.85))

        drawFloor(under: body)
        drawSilhouette(body)
        switch costume {
        case .ribbons: drawRibbons(body)
        case .plumage: drawPlumage(body)
        }

        let name = costume == .ribbons ? "ribbons" : "plumage"
        drawCaption("PhoneCostume, wearing \(name); press 1 or 2 to change, move to wear it")
    }

    override func keyPressed() {
        switch key {
        case "1": costume = .ribbons
        case "2": costume = .plumage
        default: break
        }
    }

    // MARK: The person underneath

    /// The body as a near-black figure, so the costume carries all the color.
    private func drawSilhouette(_ body: PhoneBody) {
        let s = body.scaleFactor
        withState {
            material(.matte)
            fill(Color(white: 0.08))
            for (a, b) in PhoneBody.skeleton {
                guard let pa = body.worldPosition(a), let pb = body.worldPosition(b) else { continue }
                drawCapsule(from: pa, to: pb, radius: 0.03 * s, segments: 10, rings: 3)
            }
            if let head = body.worldPosition(.head) {
                translate(head)
                drawSphere(radius: 0.1 * s, segments: 16, rings: 10)
            }
        }
    }

    // MARK: Costume 1, ribbons

    private func extendTrails(with body: PhoneBody) {
        for joint in trailJoints {
            guard let p = body.worldPosition(joint) else { continue }
            var trail = trails[joint] ?? []
            trail.append(p)
            if trail.count > 34 { trail.removeFirst(trail.count - 34) }
            trails[joint] = trail
        }
    }

    /// Each joint's recent path as a slim tube: a costume that only exists while
    /// the person moves, and dissolves when they stand still.
    private func drawRibbons(_ body: PhoneBody) {
        let s = body.scaleFactor
        withState {
            material(.plastic)
            for (i, joint) in trailJoints.enumerated() {
                guard let trail = trails[joint], trail.count > 2 else { continue }
                let dim = body.isJointTracked(joint) ? 1.0 : 0.35
                fill(palette[i % palette.count].withAlpha(dim))
                drawTube(trail, radius: 0.013 * s, sides: 6)
            }
        }
    }

    // MARK: Costume 2, plumage

    /// Feathers fanned around each bone. The fan's reference direction comes from
    /// the joint's own rotation (its local x axis), so the plumage twists with the
    /// limb instead of hanging in a fixed plane; noise sways it as time passes.
    private func drawPlumage(_ body: PhoneBody) {
        let s = body.scaleFactor
        withState {
            material(.plastic)
            for (boneIndex, bone) in PhoneBody.skeleton.enumerated() {
                guard let a = body.worldPosition(bone.0), let b = body.worldPosition(bone.1),
                      let pose = body.worldTransform(of: bone.0) else { continue }
                let axis = (b - a).normalized
                guard axis.lengthSquared > 0 else { continue }
                // The joint's local x axis, made perpendicular to the bone: the
                // twist reference only a rotation-carrying stream can provide.
                let localX = Vector3(Double(pose.columns.0.x), Double(pose.columns.0.y),
                                     Double(pose.columns.0.z))
                var reference = localX - axis * localX.dot(axis)
                if reference.lengthSquared < 1e-6 { reference = axis.cross(Vector3(0, 1, 0)) }
                reference = reference.normalized
                let side = axis.cross(reference)

                let dim = body.isJointTracked(bone.0) ? 1.0 : 0.35
                let feathers = 8
                for k in 0..<feathers {
                    let t = (Double(k) + 0.5) / Double(feathers)
                    let sway = noise(Double(boneIndex) * 3.1, Double(k) * 1.7, time * 0.6) * 0.7
                    let angle = t * .tau * 2.4 + sway
                    let radial = reference * cos(angle) + side * sin(angle)
                    // Lie the feather back down the bone, the way fur follows a limb.
                    let dir = (radial * 0.75 - axis * 0.5).normalized
                    let base = a.lerp(to: b, t)
                    let length = 0.13 * s * (0.8 + 0.35 * noise(Double(k) * 5.3, Double(boneIndex) * 1.9))
                    // One warm family, not the whole palette: a costume is one material.
                    let hue = (boneIndex + k) % 3 == 0 ? palette[0] : palette[1]
                    fill(hue.withAlpha(dim))
                    drawCapsule(from: base, to: base + dir * length,
                                radius: 0.009 * s, segments: 8, rings: 3)
                }
            }
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
            fill(Color(white: 0.12))
            translate(c.x, y - 0.02, c.z)
            drawBox(width: 4, height: 0.02, depth: 4)
        }
    }
}
