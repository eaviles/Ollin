import Ollin
import Foundation

// Polar (radial) domain repetition for the raymarched 3D SDF fields: `repeatedRadially`
// folds one built wedge into an evenly spaced ring around an axis, so a whole rosette stays
// one sphere-traced surface with no per-copy draw cost. The value-type form rings a tier of
// spokes into a sunburst; the block form folds a melting petal into a flower turning above it.
@main
final class RaymarchedRadial: Sketch {
    override func draw() {
        background(Color(hex: 0x0b1020))
        let t = time

        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 8,
                         azimuth: t * 0.25, elevation: 0.5,
                         fieldOfView: .pi / 4, near: 0.1, far: 40))

        directionalLight(.white, direction: Vector3(-0.4, 0.9, 0.35),
                         intensity: 1.25, softness: 0.35)
        ambientLight(Color(white: 0.15))
        material(.glossy)

        // Value-type: one spoke (a capsule laid radial) folded into a 14-spoke sunburst around
        // the Y axis and melted onto a central hub — one built wedge, fourteen copies, one
        // surface. `.rotatedZ` lays the upright capsule flat, `.at` pushes it out to its radius.
        let spoke = SDF3D.capsule(radius: 0.12, height: 1.25).rotatedZ(.pi / 2)
            .at(x: 0.95, y: 0, z: 0)
            .colored(Color(hex: 0x38bdf8))
        let hub = SDF3D.sphere(radius: 0.55).colored(Color(hex: 0x22d3ee))
        drawSDF3D(spoke.repeatedRadially(count: 14).smoothUnion(hub, k: 0.25)
            .at(x: 0, y: -0.7, z: 0))

        // Block form: a leaning cone petal folded into a ring of 6 and melted with a central
        // bud, the whole flower slowly turning — the same fold written as a scoped block.
        withState {
            translate(0, 1.4, 0)
            rotateY(t * 0.5)
            repeatedRadially(count: 6) {
                smoothUnion(k: 0.22) {
                    fill(Color(hex: 0xfacc15))
                    drawSphere(radius: 0.4)
                    fill(Color(hex: 0xf472b6))
                    withState { translate(1.05, 0.1, 0); rotateZ(-0.7); drawCone(radius: 0.28, height: 1.05) }
                }
            }
        }
    }
}
