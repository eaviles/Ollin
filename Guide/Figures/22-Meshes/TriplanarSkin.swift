// figure: frame=0
//
// Guide figure (Chapter 22): triplanar projection dressing surfaces that have
// no uvs. A grown, folded ball (the previous section's output, which no one
// unwrapped) wears a photograph of glazed tilework and a normal map taken off
// the picture's own light and shade, both through the three-axis projection,
// and a cairn of three separate boxes continues one standing pattern across
// their abutting faces. The picture is the one bundled surface that repeats
// seamlessly, which a triplanar projection needs: it tiles whatever it is
// given whatever the wrap setting says.
import Ollin
import OllinSamplePhotos

final class TriplanarSkin: Sketch {

    override var canvasSize: CanvasSize { .size(880, 380) }

    var tiles = Image(width: 1, height: 1, color: .white)
    var relief = Image(width: 1, height: 1, color: .white)
    var grown = Mesh(positions: [], normals: [], indices: [])

    /// The normal map, taken off the picture's own light and shade: the slope
    /// of its brightness at each texel, green-up. A small working copy carries
    /// the slopes well enough, and the reads wrap, so the normal map tiles
    /// exactly as the color map does. Built here on the CPU rather than on the
    /// GPU, because a render target filled at the top of `draw` would land on
    /// the canvas rather than on the meshes.
    func makeRelief() {
        let size = 256
        let small = tiles.resized(width: size, height: size)
        var field = [Double](repeating: 0, count: size * size)
        for y in 0 ..< size {
            for x in 0 ..< size { field[y * size + x] = small[x, y].luminance }
        }
        func height(_ x: Int, _ y: Int) -> Double {
            field[(((y % size) + size) % size) * size + (((x % size) + size) % size)]
        }
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        let gain = 3.0
        for y in 0 ..< size {
            for x in 0 ..< size {
                let dx = (height(x + 1, y) - height(x - 1, y)) * gain
                let dy = (height(x, y + 1) - height(x, y - 1)) * gain
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * size + x) * 4
                normal[i]     = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        relief = Image(width: size, height: size, premultipliedRGBA: normal)!
    }

    override func setup() {
        tiles = SamplePhoto.talavera.load()
        makeRelief()

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
            drawMesh(grown.triplanarTextured(tiles, normal: relief, scale: 2.2))
        }
        withState {
            translate(2.5, -0.55, 0)
            for (w, y) in [(2.2, 0.0), (1.5, 0.9), (0.9, 1.65)] {
                withState {
                    translate(0, y, 0)
                    drawMesh(Mesh.box(width: w, height: 0.95, depth: 1.5)
                        .triplanarTextured(tiles, normal: relief, scale: 2.2))
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
