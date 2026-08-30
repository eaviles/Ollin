import Ollin
import Foundation

// Machined joints and hardware primitives in the raymarched 3D combinators. The centerpiece
// is one form assembled with the joint ops: a hex-prism head chamfer-unioned onto a shaft,
// standing on a stepped stairs-union base with a chamfer-subtracted scoop. Beside it, the
// hardware leaves: a chain of links hanging from a capped-torus hook, and a line-armature
// tripod (capsule strokes between free points) holding a pyramid. Joint seams stay crisp
// (a machined pick per side), unlike the melted smooth-union look.
@main
final class RaymarchedJoinery: Sketch {
    override func draw() {
        background(Color(hex: 0x101418))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.35), target: Vector3(0, 0.4, 0), radius: 8.4,
                    elevation: 0.35, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.glossy)

        // The machined centerpiece: hex head + shaft + stepped base, joint sizes breathing.
        let r = 0.12 + sin(t * 1.6) * 0.07
        let head = SDF3D.hexPrism(radius: 0.55, height: 0.5).at(0, 1.5, 0)
            .colored(Color(hex: 0xffb454))
        let shaft = SDF3D.cylinder(radius: 0.28, height: 1.9).at(0, 0.55, 0)
            .colored(Color(hex: 0x9adcf0))
        let base = SDF3D.box(width: 2.2, height: 0.7, depth: 2.2).at(0, -0.75, 0)
            .colored(Color(hex: 0x5f6f86))
        let scoop = SDF3D.sphere(radius: 0.55).at(0.9, -0.35, 0.9)
        let piece = head.chamferUnion(shaft, radius: r)
            .stairsUnion(base, radius: 0.35, steps: 4)
            .chamferSubtract(scoop, radius: 0.1)
        drawSDF3D(piece)

        // A chain: alternating links under a capped-torus hook, swaying gently.
        let sway = sin(t * 1.2) * 0.15
        var chain = SDF3D.cappedTorus(radius: 0.42, tube: 0.11, angle: 2.1)
            .rotatedZ(.pi).at(-2.4, 2.1, 0).colored(Color(hex: 0xd8dee6))
        for i in 0..<3 {
            let link = SDF3D.link(height: 0.34, radius: 0.3, tube: 0.09)
                .rotatedY(i.isMultiple(of: 2) ? 0 : .pi / 2)
                .rotatedZ(sway * Double(i + 1) * 0.4)
                .at(-2.4 + sway * Double(i) * 0.2, 1.35 - Double(i) * 0.78, 0)
                .colored(Color(hex: 0xd8dee6))
            chain = chain.union(link)
        }
        drawSDF3D(chain)

        // A line-armature tripod (free-point capsule strokes) balancing a pyramid.
        let foot = 0.9
        let apex = Vector3(2.4, 0.4, 0)
        var tripod = SDF3D.line(from: apex, to: Vector3(2.4 - foot, -1.1, -foot), radius: 0.07)
        tripod = tripod.union(.line(from: apex, to: Vector3(2.4 - foot, -1.1, foot), radius: 0.07))
        tripod = tripod.union(.line(from: apex, to: Vector3(2.4 + foot, -1.1, 0), radius: 0.07))
        let cap = SDF3D.pyramid(base: 0.85, height: 0.8)
            .rotatedY(t * 0.7).at(2.4, 0.92, 0).colored(Color(hex: 0xff6f61))
        drawSDF3D(tripod.colored(Color(hex: 0x8fa3bd)).chamferUnion(cap, radius: 0.08))
    }
}
