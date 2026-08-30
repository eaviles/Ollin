//  A recreation and homage after Nick Cave's "Soundsuits" (1992-present): wearable
//  sculptures that fully conceal the wearer, so race, gender, and class disappear,
//  and that sound as the body moves (the first, of twigs, was made in response to
//  the police beating of Rodney King). This sketch is an original interpretation
//  of the dyed-raffia suits, with no code lineage, and is not affiliated with or
//  endorsed by the artist. Reference: https://www.cerclemagazine.com/en/magazine/articles-magazine/nick-cave-2/
import Foundation
import simd
import Ollin
import OllinAudio
import OllinPhone

/// A raffia Soundsuit worn by a dancing figure. Every strand is drawn from the
/// body's joints, so the person underneath is completely hidden; the suit
/// rustles through the speakers when the body moves, and falls silent when it
/// stands still. Keys **1 / 2 / 3** change the dye.
///
/// It dances on its own. Tether an iPhone running the Ollin capture app in
/// **Body** mode and the suit is yours instead: the stream's world anchor,
/// joint rotations, and scale dress whoever is in front of the camera.
@main
final class Soundsuit: Sketch {

    let device = PhoneDevice()
    let synth = Synth(.breath)

    /// Dyed-raffia solids: one loud color head to toe is the look.
    let colorways: [(name: String, color: Color)] = [
        ("magenta", Color(hex: 0xD62E8C)),
        ("grass", Color(hex: 0x76B41F)),
        ("tangerine", Color(hex: 0xF08A1D)),
    ]
    var colorway = 0

    // Per-joint velocity, measured between fresh samples: it swings the strands
    // and sets the loudness of the rustle.
    var previous: [PhoneJoint: Vector3] = [:]
    var velocities: [PhoneJoint: Vector3] = [:]
    var lastTimestamp: Double?
    var rustle = 0.0
    var noteHeld = false

    var orbitCenter: Vector3?
    var floorY: Double?

    override func setup() {
        device.start()
    }

    override func draw() {
        let dye = colorways[colorway].color
        background(Color(hex: 0x141216))

        let live = device.latestBody
        let body = live ?? stagedDancer(time)
        updateVelocities(with: body)

        let center = body.worldCenter
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.1) } else { orbitCenter = center }
        cameraShowcase(.turntable(period: .tau / 0.25), target: orbitCenter ?? center, radius: 3.0,
                       elevation: 0.12, fieldOfView: .pi / 3)
        environment(.studio.intensified(to: 1.0).lightingOnly())

        drawFloor(under: body)
        drawUnderSuit(body, dye: dye)
        drawPointCloud(suit(for: body, dye: dye))
        playRustle()

        let source = live == nil ? "dancing on its own" : "worn live"
        drawCaption("Soundsuit, after Nick Cave: \(colorways[colorway].name), \(source); 1/2/3 to re-dye, move to sound it")
    }

    override func keyPressed() {
        switch key {
        case "1": colorway = 0
        case "2": colorway = 1
        case "3": colorway = 2
        default: break
        }
    }

    // MARK: Motion into sound

    /// Joint velocities in meters per second, measured between fresh samples only
    /// (draw() outruns the stream, and a repeated sample would read as stillness).
    private func updateVelocities(with body: PhoneBody) {
        guard body.timestamp != lastTimestamp else { return }
        let dt = lastTimestamp.map { body.timestamp - $0 } ?? 0
        lastTimestamp = body.timestamp
        for joint in body.positions.keys {
            guard let p = body.worldPosition(joint) else { continue }
            if dt > 0, dt < 0.5, let was = previous[joint] {
                velocities[joint] = (p - was) / dt
            }
            previous[joint] = p
        }
    }

    /// The rustle: breath-voice noise whose level follows how fast the limbs
    /// move, smoothed so it swells and settles rather than clicking.
    private func playRustle() {
        let listened: [PhoneJoint] = [.head, .leftWrist, .rightWrist, .leftHand, .rightHand,
                                      .leftAnkle, .rightAnkle, .leftElbow, .rightElbow]
        let motion = listened.compactMap { velocities[$0]?.length }.reduce(0, +)
            / Double(listened.count)
        rustle += (min(1, motion * 0.9) - rustle) * 0.15
        if !noteHeld {
            noteHeld = true
            synth.gain = 0
            synth.noteOn("D6")
        }
        synth.gain = rustle * 0.7
    }

    // MARK: The suit

    /// A solid figure under the strands, dyed dark, so no skin and no gap ever
    /// shows: the concealment is the point.
    private func drawUnderSuit(_ body: PhoneBody, dye: Color) {
        let s = body.scaleFactor
        withState {
            material(.matte)
            fill(Color.mix(dye, .black, 0.6))
            for (a, b) in PhoneBody.skeleton {
                guard let pa = body.worldPosition(a), let pb = body.worldPosition(b) else { continue }
                drawCapsule(from: pa, to: pb, radius: 0.05 * s, segments: 10, rings: 3)
            }
            if let head = body.worldPosition(.head) {
                translate(head)
                drawSphere(radius: 0.11 * s, segments: 16, rings: 10)
            }
        }
    }

    /// The raffia: strands hung from every bone and massed over the head, each a
    /// short chain of splats that droops with gravity and swings with its
    /// joint's own motion. Instanced splats keep thousands of strands cheap.
    private func suit(for body: PhoneBody, dye: Color) -> PointCloud {
        var cloud = PointCloud()
        let s = body.scaleFactor
        for (boneIndex, bone) in PhoneBody.skeleton.enumerated() {
            guard let a = body.worldPosition(bone.0), let b = body.worldPosition(bone.1),
                  let pose = body.worldTransform(ofJoint: bone.0) else { continue }
            let axis = (b - a).normalized
            guard axis.lengthSquared > 0 else { continue }
            let localX = Vector3(Double(pose.columns.0.x), Double(pose.columns.0.y),
                                 Double(pose.columns.0.z))
            var reference = localX - axis * localX.dot(axis)
            if reference.lengthSquared < 1e-6 { reference = axis.cross(Vector3(0, 1, 0)) }
            reference = reference.normalized
            let side = axis.cross(reference)
            let swing = swingOffset(of: bone.0)

            for anchor in 0..<7 {
                for strand in 0..<8 {
                    let seedA = Double(boneIndex) * 7.3 + Double(anchor) * 1.9
                    let seedB = Double(strand) * 3.7
                    // Each strand roots at its own spot along the bone, so the
                    // coverage has no rows in it.
                    let t = (Double(anchor) + noise(seedB * 4.1, seedA)) / 7
                    let base = a.lerp(to: b, min(1, t))
                    let angle = Double(strand) / 8 * .tau + noise(seedA, seedB) * 2
                    let radial = reference * cos(angle) + side * sin(angle)
                    let length = 0.13 * s * (0.7 + 0.4 * noise(seedB, seedA))
                    addStrand(to: &cloud, from: base + radial * 0.05 * s, radial: radial,
                              swing: swing, length: length, dye: dye,
                              jitter: noise(seedA * 1.7, seedB * 2.3), scale: s)
                }
            }
        }
        // The head becomes a taller mass of strands, the extended silhouette many
        // of the suits carry, and the face disappears under it.
        if let head = body.worldPosition(.head) {
            let swing = swingOffset(of: .head)
            for k in 0..<130 {
                let u = Double(k) / 130
                let ring = noise(Double(k) * 2.9, 4.1)
                let angle = u * .tau * 11
                // The fan covers the whole head, face included: lift runs from
                // below the chin to straight up.
                let lift = -0.35 + 1.35 * ring
                let radial = Vector3(cos(angle) * (1 - abs(lift) * 0.55), lift,
                                     sin(angle) * (1 - abs(lift) * 0.55)).normalized
                let length = 0.18 * s * (0.8 + 0.6 * ring)
                addStrand(to: &cloud, from: head + radial * 0.03 * s, radial: radial,
                          swing: swing, length: length, dye: dye,
                          jitter: noise(Double(k) * 1.3, 8.5), scale: s)
            }
        }
        return cloud
    }

    /// One strand: six splats stepped from the base, bending from its outward
    /// direction toward hanging straight down, plus the swing of its joint.
    private func addStrand(to cloud: inout PointCloud, from base: Vector3, radial: Vector3,
                           swing: Vector3, length: Double, dye: Color, jitter: Double,
                           scale: Double) {
        let tone = Color.mix(dye, jitter > 0.55 ? .white : .black, abs(jitter - 0.5) * 0.5)
        var p = base
        var dir = radial
        let segments = 6
        let step = length / Double(segments)
        for i in 0..<segments {
            let droop = Double(i) / Double(segments - 1)
            dir = (dir * (1 - droop * 0.35) + Vector3(0, -0.9, 0) * droop * 0.45 + swing).normalized
            p = p + dir * step
            let size = (0.021 - 0.0016 * Double(i)) * scale
            cloud.add(p, color: tone, size: size)
        }
    }

    /// How far a joint's motion throws its strands: opposite the velocity, so
    /// raising an arm trails its raffia downward, capped so a tracking jump
    /// cannot turn the suit inside out.
    private func swingOffset(of joint: PhoneJoint) -> Vector3 {
        guard let v = velocities[joint] else { return .zero }
        let thrown = v * -0.18
        let limit = 0.6
        let l = thrown.length
        return l > limit ? thrown * (limit / l) : thrown
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
            fill(Color(white: 0.1))
            translate(c.x, y - 0.02, c.z)
            drawBox(width: 4, height: 0.02, depth: 4)
        }
    }

    // MARK: The dancer (when no phone is streaming)

    /// A staged figure dancing in place: a bounce, swinging arms, swaying hips,
    /// and a slow turn, built from the same samples the phone would send.
    private func stagedDancer(_ t: Double) -> PhoneBody {
        func j(_ x: Float, _ y: Float, _ z: Float) -> PhoneJointSample {
            PhoneJointSample(position: SIMD3<Float>(x, y, z))
        }
        let beat = t * 2.4
        let swingL = Float(sin(beat))
        let swingR = Float(sin(beat + .pi))
        let bounce = Float(abs(sin(beat)) * 0.06)
        let sway = Float(sin(beat * 0.5) * 0.05)
        var anchor = simd_float4x4(simd_quatf(angle: Float(t * 0.5), axis: SIMD3<Float>(0, 1, 0)))
        anchor.columns.3 = SIMD4<Float>(sway, 0.95 + bounce, 0, 1)
        return PhoneBody(PhonePoseSample(
            isTracked: true, timestamp: t, anchor: anchor, scaleFactor: 1,
            joints: [
                .root: j(0, 0, 0), .hips: j(0, 0.02, 0),
                .spine: j(sway * 0.5, 0.25, 0), .chest: j(sway, 0.42, 0),
                .neck: j(sway, 0.52, 0), .head: j(sway, 0.64, 0),
                .leftShoulder: j(-0.17, 0.46, 0),
                .leftElbow: j(-0.32, 0.28 + 0.12 * swingL, 0.06 * swingL),
                .leftWrist: j(-0.36, 0.06 + 0.3 * max(0, swingL), 0.14 * swingL),
                .leftHand: j(-0.37, -0.02 + 0.34 * max(0, swingL), 0.16 * swingL),
                .rightShoulder: j(0.17, 0.46, 0),
                .rightElbow: j(0.32, 0.28 + 0.12 * swingR, 0.06 * swingR),
                .rightWrist: j(0.36, 0.06 + 0.3 * max(0, swingR), 0.14 * swingR),
                .rightHand: j(0.37, -0.02 + 0.34 * max(0, swingR), 0.16 * swingR),
                .leftHip: j(-0.09, -0.04, 0),
                .leftKnee: j(-0.11, -0.46, 0.05 * swingR),
                .leftAnkle: j(-0.12, -0.86 + bounce * 0.5, 0.02),
                .leftFoot: j(-0.12, -0.92 + bounce * 0.5, 0.13),
                .rightHip: j(0.09, -0.04, 0),
                .rightKnee: j(0.1, -0.46, 0.05 * swingL),
                .rightAnkle: j(0.11, -0.86, -0.02),
                .rightFoot: j(0.11, -0.92, 0.09),
            ]))
    }
}
