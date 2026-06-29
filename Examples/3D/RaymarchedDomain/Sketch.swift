import Ollin
import Foundation

// Domain operators for the raymarched 3D SDF fields: `repeated(spacing:count:)` tiles a unit
// cell into a finite lattice, and `mirrored(x:y:z:)` folds one built lobe into a symmetric
// set, both as point-rewriting scopes, so the whole tiled/mirrored field is still one
// sphere-traced surface (no per-copy draw cost). Here the block form nests a smooth-union
// cell inside a `repeated` block to grow a melting lattice, and a mirrored cone caps it.
@main
final class RaymarchedDomain: Sketch {
    override func draw() {
        raymarchResolution(0.35)   // a heavier melting lattice, so traced below the default half-res
        background(Color(hex: 0x0d1117))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.3), target: .zero, radius: 8.5,
                    elevation: 0.5, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.5, 0.85, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.16))
        material(.glossy)

        // A unit cell (a sphere melted with a box on top), tiled into a 5×5 lattice on the
        // ground plane by the `repeated` block. The smooth-union nests inside the repeat.
        repeated(spacing: Vector3(1.7, 0, 1.7), count: 2) {
            smoothUnion(k: 0.28) {
                fill(Color(hex: 0x38bdf8))
                drawSphere(radius: 0.42)
                fill(Color(hex: 0xf472b6))
                withState { translate(0, 0.5, 0); rotateY(t * 0.6); drawBox(size: 0.42) }
            }
        }

        // The value-type form of the same idea: one wedge mirrored across x and z into a
        // four-fold cluster floating above the lattice (four cones from one built leaf).
        let wedge = SDF3D.cone(radius: 0.45, height: 1.0).colored(Color(hex: 0xfacc15))
            .at(x: 0.85, y: 0, z: 0.85)
        drawSDF3D(wedge.mirrored(x: true, y: false, z: true).at(x: 0, y: 2.3, z: 0))
    }
}
