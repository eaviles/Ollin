// figure: frame=0
//
// Guide figure (Chapter 22): projected decals. A roundel stamped down across
// the floor and up over a crate at once (one projection box conforming over
// two meshes, the crate's vertical faces fading edge-on), a striped tag
// stamped sideways onto the crate's front face, and a half-transparent ring
// compositing over the roundel where they overlap.
import Ollin

final class Stamped: Sketch {

    override var canvasSize: CanvasSize { .size(880, 380) }

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
        background(Color(hex: 0x0B0D12))
        camera(.orbiting(target: Vector3(0, 0.3, 0), radius: 6.6, azimuth: 0.5,
                         elevation: 0.42, fieldOfView: .pi / 4.4))
        environment(.studio.intensified(to: 0.8).lightingOnly())
        directionalLight(Color(kelvin: 5600), direction: Vector3(-0.4, -0.8, -0.4))
        ambientLight(Color(white: 0.1))
        fill(Color(white: 0.72))
        drawMesh(Mesh.plane(width: 9, depth: 6))
        fill(Color(hex: 0x8A7B63))
        for (p, w) in [(Vector3(1.1, 0.55, -0.5), 1.6), (Vector3(-2.2, 0.4, 0.8), 1.2)] {
            withState {
                translate(p)
                drawMesh(Mesh.box(width: w, height: p.y * 2, depth: w * 0.85))
            }
        }
        drawDecal(roundel, at: Vector3(0.1, 0.4, 0.5), width: 2.4, depth: 2)
        drawDecal(ring, at: Vector3(-0.8, 0.2, 1.0), width: 1.7, opacity: 0.55)
        drawDecal(tag, at: Vector3(1.0, 0.6, 0.3), direction: Vector3(0, 0, -1),
              width: 1.3, depth: 1.8, roll: 0.18)
    }
}
