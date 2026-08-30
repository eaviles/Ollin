// figure: frame=0
//
// Guide figure (Chapter 22): triplanar projection dressing surfaces that have
// no uvs. A grown, folded ball (the previous section's output, which no one
// unwrapped) wears an authored vein texture and its normal map through the
// three-axis projection, and a cairn of three separate boxes continues one
// standing pattern across their abutting faces.
import Ollin

final class TriplanarSkin: Sketch {

    override var canvasSize: CanvasSize { .size(880, 380) }

    /// The vein field both maps derive from: thin seams over open stone,
    /// tiling both ways. Pure math, no rng.
    func veinField(_ u: Double, _ v: Double) -> Double {
        let warp = 0.09 * sin(v * 2 * .tau) + 0.05 * sin(u * 3 * .tau + 1.7)
        let a = 0.5 + 0.5 * sin((u * 3 + warp) * .tau)
        let b = 0.5 + 0.5 * sin((v * 4 + 0.14 * sin(u * 2 * .tau) + 0.31) * .tau)
        return min(pow(a, 0.16), pow(b, 0.22))
    }

    var stone = Image(width: 1, height: 1, color: .white)
    var veins = Image(width: 1, height: 1, color: .white)
    var grown = Mesh(positions: [], normals: [], indices: [])

    override func setup() {
        let size = 256
        var color = [UInt8](repeating: 255, count: size * size * 4)
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let t = 0.45 + 0.55 * veinField(u, v)
                let i = (y * size + x) * 4
                color[i] = UInt8(214 * t); color[i + 1] = UInt8(196 * t); color[i + 2] = UInt8(168 * t)
                let dx = (veinField(u + d, v) - veinField(u - d, v)) / (2 * d) * 0.3
                let dy = (veinField(u, v + d) - veinField(u, v - d)) / (2 * d) * 0.3
                let len = (dx * dx + dy * dy + 1).squareRoot()
                normal[i] = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        stone = Image(width: size, height: size, premultipliedRGBA: color)!
        veins = Image(width: size, height: size, premultipliedRGBA: normal)!

        // The previous section's surface: a ball grown until it folds. No
        // uvs anywhere in it, which is the point.
        let growth = MeshGrowth(mesh: .icosphere(radius: 0.8, subdivisions: 3),
                                driver: .uniform, seed: 7)
        growth.maxVertices = 3600
        growth.step(110)
        grown = growth.mesh
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(-1.6, 1.1, 7.4), target: .zero, fieldOfView: .pi / 4))
        environment(.studio.intensified(to: 1.0).lightingOnly())
        directionalLight(Color(white: 0.9), direction: Vector3(-0.5, -0.6, -0.55))

        fill(.white)
        material(.dielectric(roughness: 0.65))
        withState {
            translate(-2.3, 0.35, 0)
            drawMesh(grown.triplanarTextured(stone, normal: veins, scale: 1.3))
        }
        withState {
            translate(2.5, -0.55, 0)
            for (w, y) in [(2.2, 0.0), (1.5, 0.9), (0.9, 1.65)] {
                withState {
                    translate(0, y, 0)
                    drawMesh(Mesh.box(width: w, height: 0.95, depth: 1.5)
                        .triplanarTextured(stone, normal: veins, scale: 1.3))
                }
            }
        }
        material(Material())
        for (name, x) in [("a surface nobody unwrapped", -2.3), ("one pattern, three boxes", 2.5)] {
            withBillboard(at: Vector3(x, -2.05, 0)) {
                fill(Color(white: 0.6))
                textSize(19)
                textAlign(.center, .middle)
                drawText(name, 0, 0)
            }
        }
    }
}
