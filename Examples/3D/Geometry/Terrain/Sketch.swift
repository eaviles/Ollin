import Ollin

/// Generated terrain, weathered. A `Heightfield` grows by diamond-square
/// subdivision, then erodes: tens of thousands of simulated raindrops carve
/// ravines and build sediment fans (`.hydraulic`), and a thermal pass settles
/// the slopes that stand too steep (`.thermal`). Both the raw and the eroded
/// fields become meshes in `setup()`, wearing a texture that colors each
/// sample by its height, so the `weathered` toggle flips between them and the
/// carving reads directly. Everything reproduces from the seed knob.
@main
final class Terrain3D: Sketch {
    private var rawMesh = Mesh(positions: [], indices: [])
    private var erodedMesh = Mesh(positions: [], indices: [])

    @Param(icon: "cloud.rain") var weathered = true
    @Param(1 ... 99, icon: "dice") var terrainSeed = 7.0

    private var builtSeed = 0.0

    override func setup() {
        rebuild()
    }

    override func draw() {
        if terrainSeed.rounded() != builtSeed { rebuild() }

        background(Color(hex: 0x0A0D12))
        lightingPreset(.goldenHour)
        cameraShowcase(.orbitAndRise(period: .tau / 0.12), radius: 14.5,
                       elevation: 0.6, fieldOfView: .pi / 4)
        drawMesh(weathered ? erodedMesh : rawMesh)
    }

    private func rebuild() {
        builtSeed = terrainSeed.rounded()
        let seed = UInt64(builtSeed)

        let land = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: seed)
        let eroded = land
            .eroded(.hydraulic(drops: 50_000), seed: seed)
            .eroded(.thermal(talus: 0.012, iterations: 30))

        rawMesh = terrainMesh(land)
        erodedMesh = terrainMesh(eroded)
    }

    /// The field as a mesh wearing a height-colored texture: each sample's
    /// height walks a ramp from valley green through rock to snow.
    private func terrainMesh(_ field: Heightfield) -> Mesh {
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
        let texture = Image(width: field.columns, height: field.rows,
                            premultipliedRGBA: pixels)
        let mesh = field.mesh(width: 10, depth: 10, height: 2.2)
        guard let texture else { return mesh }
        return mesh.textured(texture)
    }
}
