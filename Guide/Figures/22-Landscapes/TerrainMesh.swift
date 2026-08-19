// figure: frame=0
//
// Guide diagram (Chapter 22): the eroded heightfield read out as a solid
// mesh and lit, wearing a texture that colors each sample by its own height.
// This is the same data as the third panel of the erosion figure, standing up.
import Ollin

final class TerrainMesh: Sketch {
    override var canvasSize: CanvasSize { .square(720) }

    var land = Mesh(positions: [], indices: [])

    override func setup() {
        let field = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
            .eroded(.hydraulic(drops: 50_000), seed: 7)
            .eroded(.thermal(talus: 0.012, iterations: 30))

        let ramp = Ramp([Color(hex: 0x2E4A33), Color(hex: 0x5C6B48),
                         Color(hex: 0x8A7E66), Color(hex: 0x9C948C),
                         Color(hex: 0xEDEFF2)])
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.values.count * 4)
        for value in field.values {
            let c = ramp.color(at: min(max(value, 0), 1))
            pixels.append(UInt8((c.red * 255).rounded()))
            pixels.append(UInt8((c.green * 255).rounded()))
            pixels.append(UInt8((c.blue * 255).rounded()))
            pixels.append(255)
        }
        let mesh = field.mesh(width: 10, depth: 10, height: 2.2)
        if let texture = Image(width: field.columns, height: field.rows,
                               premultipliedRGBA: pixels) {
            land = mesh.textured(texture)
        } else {
            land = mesh
        }
    }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        lightingPreset(.goldenHour)
        camera(.orbiting(radius: 14.5, azimuth: 0.9, elevation: 0.55,
                         fieldOfView: .pi / 4))
        drawMesh(land)
    }
}
