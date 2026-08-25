import Ollin

/// Detail maps: texture that survives a close look.
///
/// A base texture sized for the whole object dissolves into blur as the
/// camera closes in; there are only so many texels. `detailMapped` tiles a
/// second, much finer pair across it: a color map (128 gray is neutral, so
/// darker speckles darken and lighter ones lighten) and a normal map whose
/// fine bumps are reoriented onto the base relief, so the grain rides the
/// large forms instead of overwriting them.
///
/// The two spheres wear the same base maps; only the right one carries the
/// detail pair. From afar they read alike. As the camera sways close, the
/// left one goes soft while the right keeps its grain. `tiles` is how many
/// times the detail tiles across the base; `strength` fades the pair (0 is
/// the off switch, byte-identical to no detail at all). All maps are
/// authored in setup from pure math, no image files.
@main
final class Detail: Sketch {

    @Param(2...24, icon: "squareshape.split.3x3") var tiles = 7.0
    @Param(0...1, icon: "dial.medium") var strength = 0.9

    var base = Image(width: 1, height: 1, color: .white)
    var baseBumps = Image(width: 1, height: 1, color: .white)
    var grain = Image(width: 1, height: 1, color: .white)
    var grainBumps = Image(width: 1, height: 1, color: .white)

    /// Broad blotches for the base; a fine deterministic speckle for the
    /// detail. Pure math, so every run is identical.
    func blotch(_ u: Double, _ v: Double) -> Double {
        0.5 + 0.25 * sin(u * 2 * .tau + 1.3) * sin(v * 2 * .tau)
            + 0.25 * sin((u + v) * 3 * .tau)
    }

    func speckle(_ u: Double, _ v: Double) -> Double {
        let a = sin(u * 9 * .tau) * sin(v * 7 * .tau)
        let b = sin((u * 5 + v * 6) * .tau + 2.1)
        return 0.5 + 0.28 * a + 0.22 * b
    }

    func makeMap(_ size: Int, field: (Double, Double) -> Double,
                 tint: (Double) -> (UInt8, UInt8, UInt8)) -> (Image, Image) {
        var color = [UInt8](repeating: 255, count: size * size * 4)
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let h = clamp(field(u, v), 0, 1)
                let i = (y * size + x) * 4
                let (r, g, b) = tint(h)
                color[i] = r; color[i + 1] = g; color[i + 2] = b
                let dx = (field(u + d, v) - field(u - d, v)) / (2 * d) * 0.2
                let dy = (field(u, v + d) - field(u, v - d)) / (2 * d) * 0.2
                let len = (dx * dx + dy * dy + 1).squareRoot()
                normal[i] = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        return (Image(width: size, height: size, premultipliedRGBA: color)!,
                Image(width: size, height: size, premultipliedRGBA: normal)!)
    }

    override func setup() {
        (base, baseBumps) = makeMap(256, field: blotch) { h in
            (UInt8(120 + 100 * h), UInt8(96 + 80 * h), UInt8(70 + 60 * h))
        }
        // The detail color map is *data* with 128 the neutral: a speckle
        // swinging around it, so the mean brightness holds.
        (grain, grainBumps) = makeMap(96, field: speckle) { h in
            let v = UInt8(clamp(88 + 80 * h, 0, 255))
            return (v, v, v)
        }
    }

    override func draw() {
        background(Color(hex: 0x10131A))
        cameraShowcase(.sway(amplitude: 0.12, period: 22), target: .zero, radius: 4.4,
                       elevation: 0.1, fieldOfView: .pi / 4)
        environment(.studio.intensity(0.8))
        directionalLight(Color(kelvin: 5400), direction: Vector3(-0.6, -0.5, -0.6))
        ambientLight(Color(white: 0.06))
        fill(.white)
        material(.dielectric(roughness: 0.7))

        let dressed = Mesh.sphere(radius: 1.05, segments: 64, rings: 32)
            .textured(base).normalMapped(baseBumps, scale: 0.8)
        withState {
            translate(-1.25, 0, 0)
            drawMesh(dressed)
        }
        withState {
            translate(1.25, 0, 0)
            drawMesh(dressed.detailMapped(grain, normal: grainBumps,
                                          scale: tiles, strength: strength))
        }
        material(Material())
        drawLabels()
    }

    private func drawLabels() {
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.55))
            for (name, x) in [("base maps only", -1.25), ("with the detail pair", 1.25)] {
                if let p = project(Vector3(x, -1.5, 0)) {
                    drawText(name, at: p)
                }
            }
        }
    }
}
