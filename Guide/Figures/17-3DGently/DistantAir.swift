// figure: frame=0 width=680
//
// Guide figure (Chapter 17): aerial perspective. A file of dark ridgelines
// steps away beneath a procedural sky: each silhouette is a measured step
// paler and bluer than the one before, the farthest melting into the horizon,
// the air brightening toward the sky's own sun. Fixed camera and sun, seeded
// heightfields, no time, so the still reproduces.
import Ollin

final class DistantAir: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    private var ridges: [Mesh] = []

    override func setup() {
        for i in 0 ..< 9 {
            let land = Heightfield.diamondSquare(size: 129, roughness: 0.74,
                                                 seed: UInt64(20 + i))
            let height = 4.0 + Double(i) * 2.6
            ridges.append(land.mesh(width: 380, depth: 22, height: height)
                .colored(by: { p, _ in
                    let h = min(max(p.y / height, 0), 1)
                    return Color.mix(Color(hex: 0x2A2F28), Color(hex: 0x6E6B5E), t: h)
                }))
        }
    }

    override func draw() {
        background(.black)
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 5, -70), radius: 85,
                         azimuth: 0, elevation: 0.018, fieldOfView: .pi / 3.6))
        let sunHeight = 0.34
        let sunAround = 4.4
        environment(.sky(turbidity: 2.4, sunElevation: sunHeight).rotated(sunAround))
        // A warm key on the same sun direction, so lit faces catch it while
        // shadow faces keep the sky's cool.
        let ce = cos(sunHeight)
        directionalLight(Color(hue: 0.09, saturation: 0.35, brightness: 1.0),
                         direction: Vector3(sin(sunAround) * ce, -sin(sunHeight),
                                            -cos(sunAround) * ce),
                         intensity: 1.15)
        aerialPerspective(density: 0.005, haziness: 0.3)
        fill(.white)
        for (i, ridge) in ridges.enumerated() {
            withState {
                translate(0, 0, 6 - Double(i) * 24)
                drawMesh(ridge)
            }
        }
    }
}
