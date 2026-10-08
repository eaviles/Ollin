@testable import Ollin
import Testing
import Foundation

/// The volume path (`drawVolume`) held to the optical model it implements:
/// Beer-Lambert transmittance, the emission integral with absorption, the
/// march ending at the first solid, and single scattering from a light, each
/// against its closed form, read back in linear light before the tone map.
@Suite
@MainActor
struct VolumeTests {

    // MARK: Linear read-back

    struct Linear {
        let width: Int
        let height: Int
        let rgb: [Float]
        func channel(_ x: Int, _ y: Int, _ c: Int) -> Double { Double(rgb[(y * width + x) * 3 + c]) }
        /// Channel `c` along row `y`, averaged over columns `columns`.
        func row(_ y: Int, columns: Range<Int>, channel c: Int = 0) -> Double {
            columns.reduce(0) { $0 + channel($1, y, c) } / Double(columns.count)
        }
    }

    static func render(_ sketch: Sketch, frame n: Int = 0) throws -> Linear {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.automaticQuality = .detail
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: n, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let count = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: count * 4)
        var rgb = [Float](repeating: 0, count: count * 3)
        for i in 0..<count {
            for c in 0..<3 { rgb[i * 3 + c] = Float(halfs[i * 4 + c]) }
        }
        return Linear(width: linear.width, height: linear.height, rgb: rgb)
    }

    /// The world height a row's pixel center sits at, under `VolumeProbe`'s
    /// orthographic camera (2 units top to bottom across `size` rows).
    static func worldY(row: Int, size: Int) -> Double {
        1 - (Double(row) + 0.5) * 2 / Double(size)
    }

    // MARK: Absorption

    /// A slab whose value rises linearly from 0 at its bottom to 1 at its top,
    /// seen square-on over white: every row keeps exp(-density * depth * value)
    /// of the white behind it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSlabLetsThroughBeersLawRowByRow() throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 1.5, color: .black)
        probe.slabDepth = 1.2
        probe.volume = Volume(width: 8, height: 64, depth: 8) { _, v, _ in v }
        probe.ground = .white
        let frame = try Self.render(probe)
        var worst = 0.0
        for row in stride(from: 2, to: frame.height - 2, by: 3) {
            let value = (Self.worldY(row: row, size: frame.height) + 1) / 2
            let expected = exp(-1.5 * 1.2 * value)
            let measured = frame.row(row, columns: 8 ..< frame.width - 8)
            worst = max(worst, abs(measured - expected))
        }
        #expect(worst < 0.0015, "worst row off Beer's law by \(worst)")
    }

    // MARK: Emission

    /// A uniform glowing slab over black: with nothing blocking, every row adds
    /// glow * depth; with a density, glow / density * (1 - exp(-density * depth)),
    /// whatever the step count.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aGlowingSlabAddsItsEmissionIntegral() throws {
        for density in [0.0, 0.8, 3.0] {
            let probe = VolumeProbe()
            probe.medium = Medium(density: density, color: .black, glow: .white, glowIntensity: 0.4)
            probe.slabDepth = 1.5
            probe.volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
            let frame = try Self.render(probe)
            let expected = density == 0 ? 0.4 * 1.5 : 0.4 / density * (1 - exp(-density * 1.5))
            let measured = frame.row(frame.height / 2, columns: 8 ..< frame.width - 8)
            #expect(abs(measured - expected) < 0.0015,
                    "density \(density): \(measured) against \(expected)")
        }
    }

    // MARK: Depth

    /// A black solid inside a glowing, absorbing slab: over the solid only the
    /// slab in front of it glows (the march stops at its face), and around it
    /// the whole depth does.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSolidInsideHidesTheVolumeBehindIt() throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 1, color: .black, glow: .white, glowIntensity: 1)
        probe.slabDepth = 2
        probe.volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
        probe.solidFrontZ = 0.5   // the slab's front is at z = 1, so 0.5 of it lies in front
        let frame = try Self.render(probe)
        let center = frame.height / 2
        let overSolid = frame.row(center, columns: center - 6 ..< center + 6)
        let besideSolid = frame.row(center, columns: 4 ..< 16)
        #expect(abs(overSolid - (1 - exp(-0.5))) < 0.0015, "over the solid: \(overSolid)")
        #expect(abs(besideSolid - (1 - exp(-2.0))) < 0.0015, "beside it: \(besideSolid)")
    }

    // MARK: Scattering

    /// A white, evenly scattering slab lit by a light shining in from the
    /// camera's side: light reaching depth s has crossed s of the medium, and
    /// the light scattered there crosses s again on the way back, so the slab
    /// returns c * p / 2 * (1 - exp(-2 * density * depth)), where p is the
    /// phase at backscatter (1 for an even medium, normalized so; a forward one
    /// sends less back). That reads the light's transmittance grid, the phase
    /// and its direction, and the scattering color.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.0, 0.5])
    func aLitSlabReturnsItsSingleScatteringIntegral(anisotropy g: Double) throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 1.2, color: Color(linear: 1, green: 0.5, blue: 0.25),
                              anisotropy: g)
        probe.slabDepth = 1
        probe.volume = Volume(width: 16, height: 16, depth: 32, repeating: 1)
        probe.lightToward = Vector3(0, 0, -1)
        let frame = try Self.render(probe)
        let backscatter = (1 - g * g) / pow(1 + g, 3)
        for (channel, albedo) in [1.0, 0.5, 0.25].enumerated() {
            let expected = albedo * backscatter * 0.5 * (1 - exp(-2 * 1.2 * 1))
            let measured = frame.row(frame.height / 2, columns: 8 ..< frame.width - 8, channel: channel)
            #expect(abs(measured - expected) < 0.0015,
                    "g \(g), channel \(channel): \(measured) against \(expected)")
        }
    }

    /// The volume composites over the frame's finished solids, so the order of
    /// the calls does not matter: drawn before the solid, it still glows only in
    /// front of it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aVolumeDrawnFirstStillEndsAtALaterSolid() throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 1, color: .black, glow: .white, glowIntensity: 1)
        probe.slabDepth = 2
        probe.volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
        probe.solidFrontZ = 0.5
        probe.volumeFirst = true
        let frame = try Self.render(probe)
        let center = frame.height / 2
        let overSolid = frame.row(center, columns: center - 6 ..< center + 6)
        #expect(abs(overSolid - (1 - exp(-0.5))) < 0.0015, "over the solid: \(overSolid)")
    }

    /// A light crossing the slab from the side, half of it blocked by a plate
    /// outside the view: the shadowed half takes no light from it, and the lit
    /// half does.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSolidsShadowFallsInsideTheCloud() throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 1, color: .white)
        probe.slabDepth = 1
        probe.volume = Volume(width: 16, height: 16, depth: 16, repeating: 1)
        probe.lightToward = Vector3(1, 0, 0)
        probe.blocksUpperHalf = true
        let frame = try Self.render(probe)
        let columns = 8 ..< frame.width - 8
        let shadowed = frame.row(frame.height / 4, columns: columns)
        let lit = frame.row(3 * frame.height / 4, columns: columns)
        #expect(lit > 0.05, "the lit half: \(lit)")
        #expect(shadowed < 0.002, "the shadowed half: \(shadowed)")
    }

    /// A volume drawn into a layer composites in that layer, over the layer's own
    /// solids and depth, and reads back as it does on the canvas.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aVolumeInALayerCompositesThere() throws {
        let direct = VolumeProbe()
        direct.medium = Medium(density: 1, color: .black, glow: .white, glowIntensity: 1)
        direct.slabDepth = 2
        direct.volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
        direct.solidFrontZ = 0.5
        let layered = VolumeProbe()
        layered.medium = direct.medium
        layered.slabDepth = 2
        layered.volume = direct.volume
        layered.solidFrontZ = 0.5
        layered.inLayer = true
        let a = try Self.render(direct), b = try Self.render(layered)
        let center = a.height / 2
        for columns in [center - 6 ..< center + 6, 4 ..< 16] {
            let inCanvas = a.row(center, columns: columns)
            let inLayer = b.row(center, columns: columns)
            #expect(abs(inCanvas - inLayer) < 0.002, "canvas \(inCanvas), layer \(inLayer)")
        }
    }

    /// Under temporal anti-aliasing an export draws several jittered samples
    /// and averages them; each shifts the march's start, and the average keeps
    /// the integral.
    @Test(.enabled(if: Snapshot.hasMetal))
    func temporalSamplesKeepTheIntegral() throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 0.8, color: .black, glow: .white, glowIntensity: 0.4)
        probe.slabDepth = 1.5
        probe.volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
        probe.temporal = true
        let frame = try Self.render(probe)
        let expected = 0.4 / 0.8 * (1 - exp(-0.8 * 1.5))
        let measured = frame.row(frame.height / 2, columns: 8 ..< frame.width - 8)
        #expect(abs(measured - expected) < 0.0015, "\(measured) against \(expected)")
    }

    /// A volume holding nothing changes nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anEmptyVolumeLeavesTheFrameAlone() throws {
        let with = VolumeProbe()
        with.volume = Volume(width: 4, height: 4, depth: 4)
        with.ground = Color(hex: 0x3366AA)
        with.solidFrontZ = 0.5
        let without = VolumeProbe()
        without.volume = nil
        without.ground = Color(hex: 0x3366AA)
        without.solidFrontZ = 0.5
        #expect(try Self.render(with).rgb == Self.render(without).rgb)
    }
}

/// The grid as a value: where its samples sit, how it is read between them,
/// and the fast noise fill against the closure form it stands in for.
@Suite
struct VolumeValueTests {
    /// The closure form calls the field once per lattice point, corner to
    /// corner, `x` fastest.
    @Test func theClosureSamplesTheLatticeCornerToCorner() {
        let volume = Volume(width: 3, height: 4, depth: 5) { u, v, w in u + 10 * v + 100 * w }
        #expect(volume[0, 0, 0] == 0)
        #expect(volume[2, 0, 0] == 1)
        #expect(volume[0, 3, 0] == 10)
        #expect(volume[0, 0, 4] == 100)
        #expect(abs(volume[1, 2, 3] - (0.5 + 10 * 2.0 / 3 + 100 * 0.75)) < 1e-4)
        let explicit = Volume(width: 2, height: 2, depth: 2, values: [0, 1, 2, 3, 4, 5, 6, 7])
        #expect(explicit[1, 0, 0] == 1 && explicit[0, 1, 0] == 2 && explicit[0, 0, 1] == 4)
    }

    /// Reading between samples interpolates trilinearly, so a field linear in
    /// each axis reads back exactly anywhere, clamped outside the box.
    @Test func readingBetweenSamplesIsTrilinear() {
        let volume = Volume(width: 5, height: 3, depth: 4) { u, v, w in 2 * u - v + 0.5 * w }
        for (u, v, w) in [(0.13, 0.71, 0.4), (0.5, 0.5, 0.5), (0.99, 0.01, 0.66)] {
            #expect(abs(volume.value(u: u, v: v, w: w) - (2 * u - v + 0.5 * w)) < 1e-5)
        }
        #expect(abs(volume.value(u: -1, v: 2, w: 0) - (0 - 1 + 0)) < 1e-6)
    }

    /// Writing a sample changes that copy only.
    @Test func aWriteCopiesFirst() {
        let original = Volume(width: 2, height: 2, depth: 2, repeating: 1)
        var edited = original
        edited[1, 1, 1] = 5
        #expect(original[1, 1, 1] == 1)
        #expect(edited[1, 1, 1] == 5)
        #expect(original != edited)
        #expect(original.contentID != edited.contentID)
    }

    /// The fast noise fill gives the samples the closure form gives over the
    /// same seeded noise, looping or not.
    @Test func theNoiseFillMatchesTheClosureForm() {
        let fields = NoiseFields(seed: 7)
        let fast = Volume.noise(width: 9, height: 7, depth: 6, frequency: 3, octaves: 3, seed: 7)
        let slow = Volume(width: 9, height: 7, depth: 6) { u, v, w in
            fields.fbm(u * 3, v * 3, w * 3, octaves: 3)
        }
        #expect(fast == slow)
        let looping = Volume.noise(width: 6, height: 5, depth: 4, loop: 0.3, seed: 2)
        let loopingFields = NoiseFields(seed: 2)
        let byHand = Volume(width: 6, height: 5, depth: 4) { u, v, w in
            loopingFields.fbm(u * 4, v * 4, w * 4, loop: 0.3)
        }
        #expect(looping == byHand)
        #expect(Volume.noise(width: 4, height: 4, depth: 4, loop: 0, seed: 2)
                == Volume.noise(width: 4, height: 4, depth: 4, loop: 1, seed: 2))
    }
}

/// A slab filling the view square-on under an orthographic camera looking down
/// -z: 2 units wide and high, `slabDepth` deep, centered at the origin.
private final class VolumeProbe: Sketch {
    var volume: Volume? = Volume(width: 2, height: 2, depth: 2, repeating: 1)
    var medium = Medium()
    var slabDepth = 1.0
    var ground: Color = .black
    /// Where a black solid's front face sits, if one is drawn: a box centered
    /// on the axis, its back well behind the slab.
    var solidFrontZ: Double?
    /// The way a directional light travels, if one is set.
    var lightToward: Vector3?
    /// Draw the volume before the solid instead of after it.
    var volumeFirst = false
    /// A plate outside the view, on the light's side, shading the slab's upper half.
    var blocksUpperHalf = false
    /// Draw the scene into a layer and the layer onto the canvas.
    var inLayer = false
    var temporal = false

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(ground)
        if inLayer {
            let layer = makeRenderTarget()
            withTarget(layer) { scene() }
            drawImage(layer.image, 0, 0)
        } else {
            scene()
        }
    }

    func scene() {
        background(ground)
        ortho(eye: Vector3(0, 0, 10), target: .zero, height: 2, near: 1, far: 30)
        if temporal { temporalAntialiasing() }
        noLights()
        ambientLight(.black)
        if let lightToward {
            castShadows()
            directionalLight(.white, direction: lightToward, intensity: 1,
                             castsShadow: blocksUpperHalf)
        }
        noStroke()
        if volumeFirst { drawTheVolume() }
        if let solidFrontZ {
            fill(.black)
            withState {
                translate(0, 0, solidFrontZ - 2)
                drawBox(width: 0.5, height: 0.5, depth: 4)
            }
        }
        if blocksUpperHalf {
            fill(.black)
            withState {
                translate(-1.6, 0.8, 0)
                drawBox(width: 0.2, height: 1.6, depth: 3)
            }
        }
        if !volumeFirst { drawTheVolume() }
    }

    func drawTheVolume() {
        if let volume {
            drawVolume(volume, width: 2, height: 2, depth: slabDepth, medium: medium)
        }
    }
}
