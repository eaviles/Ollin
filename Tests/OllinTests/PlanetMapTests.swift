import Foundation
import Ollin
import Testing

/// Probes over the maps the `3D/Geometry/Planet` example bakes on the GPU. The
/// kernels are read from the example's own `planet.metal`, so these test the file
/// that ships rather than a copy of it, and they run at a small map size because
/// every claim here is about the fields, not about how many texels they have.
///
/// A pixel snapshot pins the frame as a picture. These pin the things a whole-frame
/// mean difference averages away: that the map wraps, that the caps are ice, that
/// water is smoother than land, that a light stands on land, that the cover knob
/// moves the weather, and that the surface is opaque.
@Suite
@MainActor
struct PlanetMapTests {

    /// Sea level, as the kernels have it. A copy on purpose: if the file moves its
    /// waterline, these tests should say so rather than follow along.
    static let sea = 0.54

    // MARK: The map is a sphere, not a rectangle

    /// Longitude wraps, so the first column and the last are neighbors. A field
    /// worked out in map coordinates instead of on the sphere would show its seam
    /// here as a step; on the sphere there is nothing to step over.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theMapMeetsItselfAroundTheEquator() throws {
        let maps = try #require(PlanetMaps.baked())
        let height = try #require(maps.read(maps.heightMap))

        // Measured the same way on both sides, as a worst case rather than an
        // average: a mean would hide a seam that only shows where a coast crosses
        // it, and a max against a mean would fail on an honest map.
        var worstWrap = 0.0, worstNeighbor = 0.0
        for row in 0 ..< PlanetMaps.mapHeight {
            let left = height.value(0, row).r
            let right = height.value(PlanetMaps.mapWidth - 1, row).r
            worstWrap = max(worstWrap, abs(left - right))
            worstNeighbor = max(worstNeighbor, abs(height.value(1, row).r
                                                   - height.value(2, row).r))
        }
        #expect(worstWrap < worstNeighbor * 1.5 + 0.005,
                "seam \(worstWrap) against a neighboring step of \(worstNeighbor)")
    }

    /// Land and sea in a believable proportion. The point is the contrast spread in
    /// the kernel: fractal noise piles up around its middle, and read straight it
    /// puts almost everything on one side of the waterline.
    @Test(.enabled(if: Snapshot.hasMetal))
    func thereIsBothLandAndSea() throws {
        let maps = try #require(PlanetMaps.baked())
        let height = try #require(maps.read(maps.heightMap))
        let land = height.fraction { $0.r >= Self.sea }
        #expect(land > 0.12 && land < 0.62, "land fraction \(land)")
    }

    // MARK: The surface

    /// **The rule this file exists to hold.** A color map's alpha is opacity. A
    /// field parked in that channel draws a half-transparent planet, and nothing
    /// reports it: the picture simply lets the background through.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSurfaceIsOpaqueEverywhere() throws {
        let maps = try #require(PlanetMaps.baked())
        let surface = try #require(maps.read(maps.surfaceMap))
        let lowest = surface.reduce(1.0) { min($0, $1.a) }
        #expect(lowest > 0.99, "the dimmest alpha in the surface map is \(lowest)")
    }

    /// The caps are ice: bright and near colorless at the poles, and neither at the
    /// equator. Read off the top and bottom rows against the middle band.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCapsAreIceAndTheEquatorIsNot() throws {
        let maps = try #require(PlanetMaps.baked())
        let surface = try #require(maps.read(maps.surfaceMap))

        func brightness(row: Int) -> Double {
            (0 ..< PlanetMaps.mapWidth).reduce(0.0) { sum, x in
                let c = surface.value(x, row)
                return sum + (c.r + c.g + c.b) / 3
            } / Double(PlanetMaps.mapWidth)
        }
        let north = brightness(row: 0)
        let south = brightness(row: PlanetMaps.mapHeight - 1)
        let middle = brightness(row: PlanetMaps.mapHeight / 2)

        #expect(north > middle * 2, "north \(north) against the equator's \(middle)")
        #expect(south > middle * 2, "south \(south) against the equator's \(middle)")
    }

    /// A world is not one material. This is the pin for the failure that happened
    /// twice here, both times from a ramp that saturated rather than from a wrong
    /// color: the land came out as one flat expanse of bare stone with a few green
    /// patches left in it.
    ///
    /// The measure is the blue share of each land color. Everything that grows, and
    /// sand with it, keeps blue near an eighth of its total; stone and tundra sit
    /// near a quarter, because they are grey. So the share of land reading grey is
    /// one number, and it separates cleanly: 0.27 as the maps stand, against 0.46
    /// with the height ramp put back the way it saturated. A colorless world also
    /// costs the greenery, so that is checked too, though it is the weaker signal.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theLandIsNotOneMaterial() throws {
        let maps = try #require(PlanetMaps.baked())
        let height = try #require(maps.read(maps.heightMap))
        let surface = try #require(maps.read(maps.surfaceMap))

        var land = 0, green = 0, stony = 0
        for i in 0 ..< surface.texels.count {
            guard height.texels[i].r >= Self.sea else { continue }
            let c = surface.texels[i]
            let sum = c.r + c.g + c.b
            // Ice is not ground, and it is grey by nature, so it is left out.
            guard sum > 1e-4, max(c.r, max(c.g, c.b)) <= 0.55 else { continue }
            land += 1
            if c.g > c.r && c.g > c.b { green += 1 }
            if c.b / sum > 0.22 { stony += 1 }
        }
        #expect(land > 500, "only \(land) texels of ice-free land to measure")

        let greenShare = Double(green) / Double(land)
        let stonyShare = Double(stony) / Double(land)
        #expect(stonyShare < 0.38, "\(stonyShare) of the land is bare grey")
        #expect(greenShare > 0.30, "only \(greenShare) of the land grows anything")
    }

    // MARK: The finish

    /// Water is nearly a mirror and ground is not, which is the whole reason a sun
    /// appears on the sea and nowhere else.
    @Test(.enabled(if: Snapshot.hasMetal))
    func waterIsSmootherThanLand() throws {
        let maps = try #require(PlanetMaps.baked())
        let height = try #require(maps.read(maps.heightMap))
        let finish = try #require(maps.read(maps.finishMap))

        var water = (sum: 0.0, count: 0)
        var ground = (sum: 0.0, count: 0)
        // Away from the caps, where ice sits between the two on purpose.
        for row in (PlanetMaps.mapHeight / 4) ..< (PlanetMaps.mapHeight * 3 / 4) {
            for x in 0 ..< PlanetMaps.mapWidth {
                let rough = finish.value(x, row).g
                if height.value(x, row).r < Self.sea - 0.02 {
                    water.sum += rough; water.count += 1
                } else if height.value(x, row).r > Self.sea + 0.02 {
                    ground.sum += rough; ground.count += 1
                }
            }
        }
        #expect(water.count > 0 && ground.count > 0)
        let wet = water.sum / Double(water.count), dry = ground.sum / Double(ground.count)
        #expect(wet < 0.3 && dry > 0.7, "water \(wet), ground \(dry)")

        // And nothing is metal: a planet is a dielectric all over.
        #expect(finish.reduce(0.0) { max($0, $1.b) } < 0.01)
    }

    // MARK: The lights

    /// Every light stands on land, above the waterline. The kernels share one height
    /// map for exactly this: the coast the color draws and the coast the cities keep
    /// off are the same coast.
    @Test(.enabled(if: Snapshot.hasMetal))
    func everyLightStandsOnLand() throws {
        let maps = try #require(PlanetMaps.baked())
        let height = try #require(maps.read(maps.heightMap))
        let lights = try #require(maps.read(maps.lightMap))

        var lit = 0, wet = 0
        for row in 0 ..< PlanetMaps.mapHeight {
            for x in 0 ..< PlanetMaps.mapWidth {
                let c = lights.value(x, row)
                guard c.r + c.g + c.b > 0.02 else { continue }
                lit += 1
                if height.value(x, row).r < Self.sea { wet += 1 }
            }
        }
        #expect(lit > 20, "only \(lit) texels carry any light")
        #expect(wet == 0, "\(wet) of \(lit) lit texels sit on water")
    }

    /// And they are a scattering, not a wash: a lit world would read as a second
    /// daylight rather than as cities.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theLightsAreScattered() throws {
        let maps = try #require(PlanetMaps.baked())
        let lights = try #require(maps.read(maps.lightMap))
        let lit = lights.fraction { $0.r + $0.g + $0.b > 0.02 }
        #expect(lit < 0.10, "\(lit) of the world is lit")
    }

    // MARK: The weather

    /// The cover knob moves the weather, in the direction it says. Nothing else in
    /// the bake depends on it, so this is the one thing to hold.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCoverKnobRaisesTheCloud() throws {
        let clear = try #require(PlanetMaps.baked(cover: 0.1))
        let thick = try #require(PlanetMaps.baked(cover: 0.9))
        let a = try #require(clear.read(clear.cloudMap)).mean { $0.a }
        let b = try #require(thick.read(thick.cloudMap)).mean { $0.a }
        #expect(a < 0.05, "a clear sky covers \(a)")
        #expect(b > 0.25 && b > a + 0.2, "cover 0.1 gives \(a), cover 0.9 gives \(b)")
    }

    // MARK: The seed

    /// A world is a function of its number: the same one twice is the same world,
    /// and a different one is a different world.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aWorldIsItsNumber() throws {
        let a = try #require(PlanetMaps.baked(world: 2))
        let b = try #require(PlanetMaps.baked(world: 2))
        let c = try #require(PlanetMaps.baked(world: 7))
        let ha = try #require(a.read(a.heightMap))
        let hb = try #require(b.read(b.heightMap))
        let hc = try #require(c.read(c.heightMap))

        var sameWorst = 0.0, otherWorst = 0.0
        for i in 0 ..< ha.texels.count {
            sameWorst = max(sameWorst, abs(ha.texels[i].r - hb.texels[i].r))
            otherWorst = max(otherWorst, abs(ha.texels[i].r - hc.texels[i].r))
        }
        #expect(sameWorst == 0, "the same world differs by \(sameWorst)")
        #expect(otherWorst > 0.2, "two worlds differ by only \(otherWorst)")
    }
}

// MARK: - The fixture

/// A texel, in the order the snapshot hands them over.
private struct Texel { var r = 0.0, g = 0.0, b = 0.0, a = 0.0 }

/// One map read back from the GPU.
private struct MapReadback {
    var texels: [Texel]
    var width: Int

    func value(_ x: Int, _ y: Int) -> Texel { texels[y * width + x] }
    func fraction(_ holds: (Texel) -> Bool) -> Double {
        Double(texels.filter(holds).count) / Double(texels.count)
    }
    func mean(_ of: (Texel) -> Double) -> Double {
        texels.reduce(0.0) { $0 + of($1) } / Double(texels.count)
    }
    func reduce(_ start: Double, _ step: (Double, Texel) -> Double) -> Double {
        texels.reduce(start, step)
    }
}

/// Bakes the example's maps at a small size and hands them back. The kernels come
/// from the example's own file, so a change there reaches these tests.
@MainActor
private final class PlanetMaps: Sketch {
    static let mapWidth = 256, mapHeight = 128

    override var canvasSize: CanvasSize { .square(64) }

    let heightMap = ComputeTexture(width: PlanetMaps.mapWidth, height: PlanetMaps.mapHeight)
    let surfaceMap = ComputeTexture(width: PlanetMaps.mapWidth, height: PlanetMaps.mapHeight)
    let reliefMap = ComputeTexture(width: PlanetMaps.mapWidth, height: PlanetMaps.mapHeight)
    let finishMap = ComputeTexture(width: PlanetMaps.mapWidth, height: PlanetMaps.mapHeight)
    let lightMap = ComputeTexture(width: PlanetMaps.mapWidth, height: PlanetMaps.mapHeight)
    let cloudMap = ComputeTexture(width: PlanetMaps.mapWidth, height: PlanetMaps.mapHeight)

    var world = 3.0
    var cover = 0.55

    /// The example's own kernel file, read from the repository rather than copied.
    private static func kernel(_ entry: String) -> ComputeKernel? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // OllinTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // the repository
            .appendingPathComponent("Examples/3D/Geometry/Planet/planet.metal")
        return ComputeKernel(entry: entry, contentsOf: url)
    }

    override func draw() {
        background(.black)
        guard let bakeHeight = Self.kernel("planet_height"),
              let bakeSurface = Self.kernel("planet_surface"),
              let bakeRelief = Self.kernel("planet_relief"),
              let bakeFinish = Self.kernel("planet_finish"),
              let bakeLights = Self.kernel("planet_lights"),
              let bakeClouds = Self.kernel("planet_clouds") else { return }

        var seed = ComputeParams()
        seed.append(Float(world))
        compute(bakeHeight, writing: heightMap, params: seed)
        compute(bakeSurface, reading: heightMap, writing: surfaceMap, params: seed)

        var relief = ComputeParams()
        relief.append(Float(4.5))
        compute(bakeRelief, reading: heightMap, writing: reliefMap, params: relief)
        compute(bakeFinish, reading: heightMap, writing: finishMap)
        compute(bakeLights, reading: heightMap, writing: lightMap, params: seed)

        var sky = ComputeParams()
        sky.append(Float(world))
        sky.append(Float(cover))
        compute(bakeClouds, writing: cloudMap, params: sky)
    }

    func read(_ texture: ComputeTexture) -> MapReadback? {
        guard let floats = texture.snapshot() else { return nil }
        var texels = [Texel]()
        texels.reserveCapacity(texture.width * texture.height)
        for i in stride(from: 0, to: floats.count, by: 4) {
            texels.append(Texel(r: Double(floats[i]), g: Double(floats[i + 1]),
                                b: Double(floats[i + 2]), a: Double(floats[i + 3])))
        }
        return MapReadback(texels: texels, width: texture.width)
    }

    /// Run one frame, which is the whole bake, and hand the sketch back with its
    /// textures filled.
    static func baked(world: Double = 3, cover: Double = 0.55) -> PlanetMaps? {
        let sketch = PlanetMaps()
        sketch.world = world
        sketch.cover = cover
        guard OllinApp.image(of: sketch, frame: 0) != nil else { return nil }
        return sketch
    }
}
