import Ollin

/// Projected decals: pictures stamped onto the scene.
///
/// A `Decal` wraps an image once; `drawDecal(_:at:...)` then places it each frame
/// as a projection box, and every mesh surface inside the box receives the
/// picture, composited over its base color before lighting, so it shades as
/// paint on the surface. One box can span several meshes at once: the sliding
/// roundel here conforms over the floor and up onto whichever crate it
/// crosses, while faces edge-on to the projection fade the stamp out instead
/// of smearing it.
///
/// The striped tag is stamped sideways onto a crate's front, spun by `roll`;
/// the half-transparent ring shows a later decal compositing over an earlier
/// one. Decals are per-frame state like lights, which is why moving one is
/// just placing it somewhere else next frame. The images are authored in
/// setup from pure math, no files.
@main
final class Decals: Sketch {

    let period = 12.0
    override var loopDuration: Double? { period }

    @Param(0.8...3, icon: "arrow.up.left.and.arrow.down.right") var size = 1.9
    @Param(0...1, icon: "circle.righthalf.filled") var ringOpacity = 0.55
    @Param(-1...1, icon: "rotate.right") var roll = 0.2

    var roundel = Decal(Image(width: 1, height: 1, color: .white))!
    var ring = Decal(Image(width: 1, height: 1, color: .white))!
    var tag = Decal(Image(width: 1, height: 1, color: .white))!

    override func setup() {
        let side = 128
        func authored(_ paint: (Double, Double) -> (UInt8, UInt8, UInt8, UInt8)) -> Decal {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    let u = (Double(x) + 0.5) / Double(side) - 0.5
                    let v = (Double(y) + 0.5) / Double(side) - 0.5
                    let (r, g, b, a) = paint(u, v)
                    let i = (y * side + x) * 4
                    let k = Double(a) / 255
                    bytes[i] = UInt8(Double(r) * k); bytes[i + 1] = UInt8(Double(g) * k)
                    bytes[i + 2] = UInt8(Double(b) * k); bytes[i + 3] = a
                }
            }
            return Decal(Image(width: side, height: side, premultipliedRGBA: bytes)!)!
        }
        roundel = authored { u, v in
            let r = (u * u + v * v).squareRoot()
            if r > 0.48 { return (0, 0, 0, 0) }
            return r > 0.34 ? (204, 42, 42, 255)
                : (r > 0.2 ? (238, 228, 205, 255) : (44, 64, 148, 255))
        }
        ring = authored { u, v in
            let r = (u * u + v * v).squareRoot()
            return (r > 0.3 && r < 0.46) ? (250, 200, 40, 255) : (0, 0, 0, 0)
        }
        tag = authored { u, v in
            guard abs(u) < 0.46, abs(v) < 0.3 else { return (0, 0, 0, 0) }
            let stripe = Int(((u + v * 0.6) * 7).rounded(.down) + 100) % 2 == 0
            return stripe ? (24, 24, 24, 255) : (240, 190, 40, 255)
        }
    }

    override func draw() {
        background(Color(hex: 0x10131A))
        cameraShowcase(.sway(amplitude: 0.14, period: 24), target: Vector3(0, 0.4, 0),
                       radius: 9.4, elevation: 0.5, fieldOfView: .pi / 4)
        environment(.studio.intensified(to: 0.8))
        directionalLight(Color(kelvin: 5600), direction: Vector3(-0.4, -0.8, -0.4),
                         intensity: 1.05)
        ambientLight(Color(white: 0.06))

        fill(Color(white: 0.72))
        drawMesh(Mesh.plane(width: 9, depth: 7))
        fill(Color(hex: 0x8A7B63))
        for (p, w) in [(Vector3(1.1, 0.55, -0.6), 1.6), (Vector3(-1.9, 0.4, 0.9), 1.2)] {
            withState {
                translate(p)
                drawMesh(Mesh.box(width: w, height: p.y * 2, depth: w * 0.85))
            }
        }

        // The roundel slides a slow figure across floor and crates, one lap
        // per loop; its box is deep enough to reach both.
        let t = loopProgress(over: period) * .tau
        let slide = Vector3(2.6 * sin(t), 0.5, 1.4 * sin(2 * t))
        drawDecal(roundel, at: slide, width: size, depth: 2.4)
        // A half-transparent ring parked where the roundel passes: when they
        // overlap, the later ring composites over the sliding stamp.
        drawDecal(ring, at: Vector3(0, 0.2, 1.2), width: 1.6, opacity: ringOpacity)
        // The tag, stamped sideways onto the front crate face.
        drawDecal(tag, at: Vector3(1.0, 0.6, 0.2), direction: Vector3(0, 0, -1),
              width: 1.3, depth: 1.8, roll: roll)
    }
}
