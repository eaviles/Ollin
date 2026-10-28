// figure: frame=0
//
// Guide figure (Chapter 28): a gesture in space. One tapering stroke four ways on a
// table: its flat dots on the sheet, a candy-striped tube as wide as the mark, the
// tube wound round the path, and a chain of cubes at the flat chain's stations.
import Ollin

final class GestureInSpace: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 480) }

    let palette = [Color(hex: 0x1F2B5B), Color(hex: 0xC4473A), Color(hex: 0xE0A43A),
                   Color(hex: 0x2F7A78), Color(hex: 0xE07A8F)]

    override func draw() {
        background(Color(hex: 0xF3EEE3))
        let gesture = stroke()

        camera(.perspective(eye: Vector3(0, 7.2, 5.2), target: Vector3(0, 0, 0), fieldOfView: .pi / 4.2))
        directionalLight(Color(hex: 0xFFF6E8), direction: Vector3(-0.4, -0.85, -0.3), intensity: 1.2)
        ambientLight(Color(hex: 0xC6CDD8))
        material(.matte)

        // The sheet, with the flat dots of the same gesture drawn on a layer.
        let sheet = makeRenderTarget(width: 1000, height: 300)
        withTarget(sheet) {
            background(Color(hex: 0xFBF8F1))
            noStroke()
            for (i, piece) in gesture.dots(rows: 3, size: 0.8, gap: 0.5, seed: 3).enumerated() {
                fill(palette[i % palette.count])
                drawShape(piece.shape)
            }
        }

        let stripes = Self.stripeImage(Color(hex: 0xC4473A), Color(hex: 0xF7F2E8))
        let cube = Mesh.roundedBox(size: 1, radius: 0.16, segments: 3)
        let rows: [(z: Double, draw: () -> Void)] = [
            (-2.7, { self.fill(.white); self.drawMesh(gesture.tube(sides: 20).textured(stripes, wrap: .tile)) }),
            (-0.9, { self.fill(Color(hex: 0x2F7A78)); self.drawMesh(gesture.tube(sides: 20, wobble: 0.6, wavelength: 3)) }),
            (0.9, { self.fill(Color(hex: 0xC4473A)); self.drawMesh(cube, instances: gesture.solids(spacing: 0.9, seed: 3)) }),
        ]
        for row in rows {
            withState {
                translate(0, 0, row.z)
                rotateX(-.pi / 2)
                scale(0.01, 0.01, 0.01)
                translate(-500, 150, 0)
                row.draw()
            }
        }
        withState {
            translate(0, 0.01, 2.7)
            fill(.white)
            drawMesh(Mesh.plane(width: 10, depth: 3).textured(sheet.image))
        }
    }

    /// One stroke across the sheet, heavy at the start and lifting toward the end.
    private func stroke() -> GestureMark {
        let knots = [Vector2(60, 150), Vector2(300, 60), Vector2(520, 230), Vector2(760, 80), Vector2(950, 190)]
        let points = Contour(curveThrough: knots, closed: false).resampled(spacing: 4).points
        let widths: [Double] = points.indices.map { i in
            let u = Double(i) / Double(max(points.count - 1, 1))
            return 60 * (1 - 0.7 * u) * (0.35 + 0.65 * smoothstep(0, 0.05, u))
        }
        return GestureMark(points: points, widths: widths)
    }

    static func stripeImage(_ a: Color, _ b: Color) -> Image {
        let n = 64
        let image = Image(width: n, height: n)
        for y in 0 ..< n { for x in 0 ..< n { image[x, y] = ((x + y) / 16) % 2 == 0 ? a : b } }
        return image
    }
}
