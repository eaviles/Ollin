import Ollin
import Foundation

/// The gesture marks' members in space. One drawn stroke, heavy at the start
/// and lifting toward the end, as a tube whose thickness is the mark's width
/// at every point (`GestureMark.tube`), and as a chain of solids strung along
/// it at the flat chain's stations (`GestureMark.solids`). Four looks on a
/// picker:
///
/// - **candy**: the tube under a diagonal stripe that tiles once a width, so
///   it runs round the tube as a candy stripe.
/// - **wobble**: the tube wound round the path instead of along it, a phone
///   cord's coil, in clay.
/// - **metal**: a polished tube that reflects the canvas, since the layer the
///   flat marks are drawn into is the scene's environment (`environment(.feed(layer))`).
/// - **solids**: a chain of flat-shaded cubes, each as big as the width there
///   and turned along the path, where the flat chain's squares stand.
///
/// The stroke grows over the loop and holds, and nothing behind the pen moves:
/// every ring and every solid stands by its distance from the start. The same
/// gesture's hull and strips, flat, lie on the sheet under the solid.
@main
final class GestureMarks3D: Sketch {
    enum Look: String, CaseIterable, ParamOption { case candy, wobble, metal, solids }

    @Param(style: .segmented, icon: "scribble.variable") var look = Look.candy
    @Param("Width", 30 ... 150, icon: "lineweight") var weight = 90.0
    @Param("Seed", 1 ... 99, icon: "dice") var seed = 7
    @Param("Wobble", 0 ... 1.2, icon: "waveform.path") var wobble = 0.6
    @Param("Pen draws it", icon: "pencil.and.outline") var penDraws = true

    override var loopDuration: Double? { 12 }

    let paper = Color(hex: 0xF3EEE3)
    let palette = [Color(hex: 0x1F2B5B), Color(hex: 0xC4473A), Color(hex: 0xE0A43A),
                   Color(hex: 0x2F7A78), Color(hex: 0xE07A8F)]
    /// The candy stripe: a diagonal band that tiles once a width along the tube.
    lazy var stripes: Image = Self.stripeImage(Color(hex: 0xC4473A), Color(hex: 0xF7F2E8))
    lazy var cube = Mesh.roundedBox(size: 1, radius: 0.16, segments: 3)

    override func draw() {
        background(paper)
        let progress = penDraws ? smoothstep(0, 0.7, loopProgress(over: 12)) : 1
        let (points, widths) = handStroke(seed: seed)
        let count = max(2, Int(progress * Double(points.count)))
        let gesture = GestureMark(points: Array(points.prefix(count)), widths: Array(widths.prefix(count)))

        // The flat marks of the same gesture, into a layer: the table's picture
        // and, for the metal, what the tube reflects.
        let flat = makeRenderTarget()
        withTarget(flat) {
            background(paper)
            noStroke()
            fill(Color(hex: 0xE0A43A))
            drawShape(gesture.hull(padding: weight * 0.5))
            for piece in gesture.strips(rows: 4, length: 2, seed: seed) {
                fill(palette[(piece.row + piece.index) % palette.count])
                drawShape(piece.shape)
            }
        }
        let turn = time / 12 * 2 * .pi
        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 8.6, azimuth: 0.9 + 0.35 * sin(turn), elevation: 0.95,
                         fieldOfView: .pi / 4.5, near: 0.1, far: 60))
        if look == .metal {
            environment(.feed(flat))
        } else {
            directionalLight(Color(hex: 0xFFF6E8), direction: Vector3(-0.4, -0.85, -0.3), intensity: 1.2,
                             softness: 0.3)
            ambientLight(Color(hex: 0xC6CDD8))
        }
        castShadows(look != .metal)

        // The gesture's plane, canvas units, laid on the table: a unit per 100
        // points, the canvas centered (its down is -y, as the tube stands), the
        // foot of the sheet toward the camera. The sheet is the layer stretched
        // over a quad in that plane, under the tube.
        withState {
            rotateX(-.pi / 2)
            scale(0.01, 0.01, 0.01)
            translate(-width / 2, height / 2, 0)
            withState {
                noLights()
                fill(.white)
                drawMesh(Self.sheet(width: width, height: height, below: weight / 2).textured(flat.image))
            }
            switch look {
            case .candy:
                material(.matte)
                fill(.white)
                drawMesh(gesture.tube(sides: 20).textured(stripes, wrap: .tile))
            case .wobble:
                material(.clay)
                fill(Color(hex: 0x2F7A78))
                drawMesh(gesture.tube(sides: 20, wobble: wobble, wavelength: 3))
            case .metal:
                material(.polishedMetal)
                fill(Color(hex: 0xE8E4DC))
                drawMesh(gesture.tube(sides: 24))
            case .solids:
                material(.matte)
                fill(Color(hex: 0xC4473A))
                drawMesh(cube, instances: gesture.solids(spacing: 0.9, seed: seed))
            }
        }

        noStroke()
        fill(Color(white: 0.4))
        textSize(20)
        textAlign(.center, .bottom)
        drawText("\(look.rawValue)  ·  the tube is as wide as the mark", width / 2, height - 28)
    }

    /// A long stroke across the sheet, heavy where it starts and lifting toward
    /// the end, from the seed.
    func handStroke(seed: Int) -> (points: [Vector2], widths: [Double]) {
        randomSeed(seed)
        let route: [Vector2] = [Vector2(150, 640), Vector2(360, 360), Vector2(590, 560), Vector2(780, 300),
                                Vector2(940, 520)]
        let knots: [Vector2] = route.map { (point: Vector2) -> Vector2 in
            point + Vector2(random(-50, 50), random(-70, 70))
        }
        let points = Contour(curveThrough: knots, closed: false).resampled(spacing: 4).points
        let widths: [Double] = points.indices.map { (i: Int) -> Double in
            let u = Double(i) / Double(max(points.count - 1, 1))
            let lift: Double = 1 - 0.7 * u
            let press: Double = 0.35 + 0.65 * smoothstep(0, 0.05, u)
            return weight * lift * press
        }
        return (points, widths)
    }

    /// A quad the size of the canvas in the gesture's plane (the canvas's down as
    /// -y), `below` units under it, with the picture's top-left at the canvas's.
    static func sheet(width: Double, height: Double, below: Double) -> Mesh {
        Mesh(positions: [Vector3(0, 0, -below), Vector3(width, 0, -below),
                         Vector3(width, -height, -below), Vector3(0, -height, -below)],
             normals: [Vector3](repeating: Vector3(0, 0, 1), count: 4),
             indices: [0, 1, 2, 0, 2, 3],
             uvs: [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
    }

    /// A diagonal two-color stripe, 64 texels square, drawn once.
    static func stripeImage(_ a: Color, _ b: Color) -> Image {
        let n = 64
        let image = Image(width: n, height: n)
        for y in 0 ..< n {
            for x in 0 ..< n {
                image[x, y] = ((x + y) / 16) % 2 == 0 ? a : b
            }
        }
        return image
    }
}
