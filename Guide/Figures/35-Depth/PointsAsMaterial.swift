// figure: frame=0
//
// Guide figure (Chapter 35): points as their own material. The same cloud of
// points twice: on the left as dots, on the right skinned by
// `particleSurface(of:radius:)` into one blended form. The points are a
// splash crown thrown up around a ring, seeded so the figure renders the same
// everywhere.
import Ollin

final class PointsAsMaterial: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    var points: [Vector3] = []
    var skin = Mesh(positions: [], indices: [])

    override func setup() {
        seed(35)
        points = []
        for _ in 0 ..< 2400 {
            let a = random(0, .tau)
            let c = max(0, cos(a * 9))
            let spike = c * c * c * c * c * c                    // nine tall points around the rim
            let lift = random(0, 1) * (0.12 + 0.4 * spike)
            let r = 0.5 + random(-0.04, 0.04) + lift * 0.3     // the wall leans out as it rises
            points.append(Vector3(cos(a) * r, lift, sin(a) * r))
        }
        skin = particleSurface(of: points, radius: 0.05)
    }

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: Vector3(0, 0.15, 0), radius: 3.6,
                         azimuth: 0.3, elevation: 0.45, fieldOfView: .pi / 4))
        lightingPreset(.studio)

        // Left: the points as dots.
        withState {
            translate(-0.8, 0, 0)
            var cloud = PointCloud()
            for p in points { cloud.add(p, color: Color(hex: 0xEDE7DA), size: 0.02) }
            drawPointCloud(cloud)
        }
        // Right: the same points, skinned into one surface.
        withState {
            translate(0.8, 0, 0)
            material(.glossy)
            fill(Color(hex: 0x6FB3D2))
            drawMesh(skin)
        }

        noStroke()
        fill(Color(white: 0.82))
        textFont(OutlineFont.system)
        textSize(19)
        textAlign(.center)
        drawText("the points", at: Vector2(width * 0.27, 470))
        drawText("particleSurface(of:radius:)", at: Vector2(width * 0.73, 470))
    }
}
