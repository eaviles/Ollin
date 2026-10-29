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
                              anisotropy: g, bounce: 0)
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

    // MARK: The bounce

    /// The share each further octave keeps of the last at a bounce of 1.
    static let contribution = 0.43
    /// What an even, white half-space lit and seen along its normal reads
    /// against a white matte surface under the same light, from the exact
    /// solution: Chandrasekhar's H function at 1 for conservative isotropic
    /// scattering is 2.9078, and the reflected radiance is H(1)^2 / 8 of it.
    static let halfSpaceReading = 2.9078 * 2.9078 / 8

    /// Henyey-Greenstein at cosine `c`, normalized so an even medium reads 1.
    static func phase(_ c: Double, _ g: Double) -> Double {
        let denominator = 1 + g * g - 2 * g * c
        return (1 - g * g) / (denominator * denominator.squareRoot())
    }

    /// The octave sum a uniform slab of thickness `depth` and extinction
    /// `density` returns toward a light on the camera's side (`frontLit`) or
    /// behind the slab, with the phase's cosine `cosine` and anisotropy `g`,
    /// at a bounce whose contribution factor is `b`: octave k adds b^k of the
    /// light through a shadow thinned to 2^-k of the depth, with the phase at
    /// g / 2^k, each integrated exactly against the view's own transmittance.
    static func octaveSum(density: Double, depth: Double, frontLit: Bool, cosine: Double,
                          g: Double, b: Double, octaves: Int = 8) -> Double {
        var sum = 0.0
        var share = 1.0, thinning = 1.0, spread = g
        for _ in 0 ..< octaves {
            let p = phase(cosine, spread)
            let term: Double
            if frontLit {
                // Light to depth s crosses s of the medium thinned, the view s whole.
                let k = density * (1 + thinning)
                term = (1 - exp(-k * depth)) / k
            } else {
                // Light to depth s crosses (depth - s) thinned, the view s whole.
                let k = density * (1 - thinning)
                term = k > 1e-9 ? exp(-thinning * density * depth) * (1 - exp(-k * depth)) / k
                                : depth * exp(-density * depth)
            }
            sum += share * p * density * term
            share *= b
            thinning *= 0.5
            spread *= 0.5
            if share < 1e-4 { break }
        }
        return sum
    }

    /// A white slab lit from the camera's side, with the bounce on: the slab
    /// returns the octave sum, each octave the single-scattering integral with
    /// the light's shadow thinned by half again, its share halved, and its
    /// phase spread toward even. Read in each channel's albedo.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.0, 0.5])
    func aLitSlabReturnsItsOctaveSum(anisotropy g: Double) throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 1.2, color: Color(linear: 1, green: 0.5, blue: 0.25),
                              anisotropy: g, bounce: 1)
        probe.slabDepth = 1
        probe.volume = Volume(width: 16, height: 16, depth: 32, repeating: 1)
        probe.lightToward = Vector3(0, 0, -1)
        let frame = try Self.render(probe)
        let sum = Self.octaveSum(density: 1.2, depth: 1, frontLit: true, cosine: -1, g: g,
                                 b: Self.contribution)
        for (channel, albedo) in [1.0, 0.5, 0.25].enumerated() {
            let expected = albedo * sum
            let measured = frame.row(frame.height / 2, columns: 8 ..< frame.width - 8, channel: channel)
            #expect(abs(measured - expected) < 0.0025,
                    "g \(g), channel \(channel): \(measured) against \(expected)")
        }
        // And the sum is more than one scattering, which is what the bounce adds.
        let single = Self.octaveSum(density: 1.2, depth: 1, frontLit: true, cosine: -1, g: g, b: 0)
        #expect(sum > single * 1.3, "octaves \(sum) against one \(single)")
    }

    /// A thick white cloud lit from the front: with the bounce it reads
    /// brighter than lit once, and what the exact solution for an even white
    /// half-space gives, 1.06 of a white matte surface under the same light
    /// (which reads the light's own color, 1 here), the reading the share is
    /// set by. Lit from behind with a forward phase, the bounce brightens the
    /// slab too, the light shining through: the silver lining.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aThickCloudBouncesMoreLightAndNeverPastTheLight() throws {
        func reading(bounce: Double, lightToward z: Double, g: Double) throws -> Double {
            let probe = VolumeProbe()
            probe.medium = Medium(density: 2, color: .white, anisotropy: g, bounce: bounce)
            probe.slabDepth = 4
            probe.volume = Volume(width: 8, height: 8, depth: 48, repeating: 1)
            probe.lightToward = Vector3(0, 0, z)
            let frame = try Self.render(probe)
            return frame.row(frame.height / 2, columns: 8 ..< frame.width - 8)
        }
        let once = try reading(bounce: 0, lightToward: -1, g: 0)
        let bounced = try reading(bounce: 1, lightToward: -1, g: 0)
        #expect(abs(once - 0.5) < 0.004, "lit once, a thick even slab returns half: \(once)")
        #expect(bounced > once + 0.25, "bounced \(bounced) against once \(once)")
        let expected = Self.octaveSum(density: 2, depth: 4, frontLit: true, cosine: -1, g: 0,
                                      b: Self.contribution)
        #expect(abs(expected - Self.halfSpaceReading) < 0.005,
                "the share lands the sum on the half-space reading: \(expected)")
        #expect(abs(bounced - expected) < 0.004, "\(bounced) against the sum \(expected)")
        // Half a bounce sits between the two.
        let half = try reading(bounce: 0.5, lightToward: -1, g: 0)
        #expect(half > once + 0.05 && half < bounced - 0.05, "half a bounce reads \(half)")
        // The silver lining: lit from behind through a forward phase.
        let edgeOnce = try reading(bounce: 0, lightToward: 1, g: 0.5)
        let edgeBounced = try reading(bounce: 1, lightToward: 1, g: 0.5)
        #expect(edgeBounced > edgeOnce * 3, "lit from behind: \(edgeBounced) against \(edgeOnce)")
    }

    /// A slab so thick that no light survives it as a half float: lit from
    /// behind, the camera's side would read nothing if the shadow grid held
    /// transmittance, and reads the deep octaves' share because it holds the
    /// optical depth. Against the closed form.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDeepOctaveFindsLightThroughAThickSlab() throws {
        let probe = VolumeProbe()
        probe.medium = Medium(density: 10, color: .white, bounce: 1)
        probe.slabDepth = 2.5
        probe.volume = Volume(width: 8, height: 8, depth: 64, repeating: 1)
        probe.lightToward = Vector3(0, 0, 1)
        let frame = try Self.render(probe)
        let measured = frame.row(frame.height / 2, columns: 8 ..< frame.width - 8)
        let expected = Self.octaveSum(density: 10, depth: 2.5, frontLit: false, cosine: 1, g: 0,
                                      b: Self.contribution)
        #expect(expected > 0.015, "the closed form has light to find: \(expected)")
        #expect(abs(measured - expected) < expected * 0.05, "\(measured) against \(expected)")
        // Lit once, the same slab is black from this side.
        let once = VolumeProbe()
        once.medium = Medium(density: 10, color: .white, bounce: 0)
        once.slabDepth = 2.5
        once.volume = probe.volume
        once.lightToward = Vector3(0, 0, 1)
        #expect(try Self.render(once).row(frame.height / 2, columns: 8 ..< frame.width - 8) < 0.001)
    }

    // MARK: Fog

    /// Under fog, a volume is veiled as a solid at its mean depth is: a dense
    /// glowing slab that saturates to white a short way in reads, through the
    /// fog, as a white solid standing one extinction length behind the slab's
    /// face, within a level. Under a gray fog, with the air's own light added;
    /// under a black one at twice the density and a thicker slab, where a veil
    /// read at the slab's face instead would be two levels off.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [(Color.gray, 0.12, 8.0), (Color.black, 0.2, 4.0)])
    func fogVeilsAVolumeAsItVeilsASolid(fog: Color, fogDensity: Double, density: Double) throws {
        // The solid is half a unit wide, a quarter of the view: read both at its middle.
        func center(_ sketch: Sketch) throws -> Double {
            let pixels = Pixels(try OllinApp.image(of: sketch, frame: 0))
            let y = pixels.height / 2
            let columns = pixels.width / 2 - 6 ..< pixels.width / 2 + 6
            return columns.reduce(0.0) { $0 + Double(pixels.gray($1, y)) } / Double(columns.count)
        }
        let cloud = VolumeProbe()
        cloud.medium = Medium(density: density, color: .black, glow: .white, glowIntensity: density,
                              bounce: 0)
        cloud.slabDepth = 2
        cloud.volume = Volume(width: 8, height: 8, depth: 64, repeating: 1)
        cloud.air = (fog, fogDensity)
        let solid = VolumeProbe()
        solid.volume = nil
        solid.solidFrontZ = 1 - 1 / density   // the slab's face is at z = 1
        solid.solidColor = .white
        solid.air = (fog, fogDensity)
        let veiledCloud = try center(cloud), veiledSolid = try center(solid)
        #expect(abs(veiledCloud - veiledSolid) <= 1, "cloud \(veiledCloud), solid \(veiledSolid)")
        // And the fog did something: the same solid with no fog reads white.
        let clear = VolumeProbe()
        clear.volume = nil
        clear.solidFrontZ = solid.solidFrontZ
        clear.solidColor = .white
        #expect(try center(clear) > veiledSolid + 40)
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

    /// Two volumes over the same box share their center, so the farthest-first
    /// sort has nothing to order them by, and they keep their call order with
    /// the later one on top. A medium that only glows adds 0.6 over black
    /// whatever its place; an absorbing one drawn after it dims that glow by its
    /// transmittance, and drawn before it dims only the black behind both.
    @Test(.enabled(if: Snapshot.hasMetal))
    func twoVolumesOnOneBoxCompositeInCallOrder() throws {
        let glow = Medium(density: 0, color: .black, glow: .white, glowIntensity: 0.4)
        let dust = Medium(density: 1, color: .black)
        for dustFirst in [false, true] {
            let probe = VolumeProbe()
            probe.medium = glow
            probe.secondMedium = dust
            probe.secondFirst = dustFirst
            probe.slabDepth = 1.5
            probe.volume = Volume(width: 8, height: 8, depth: 8, repeating: 1)
            let frame = try Self.render(probe)
            let measured = frame.row(frame.height / 2, columns: 8 ..< frame.width - 8)
            let expected = dustFirst ? 0.6 : 0.6 * exp(-1.5)
            #expect(abs(measured - expected) < 0.0015,
                    "dust \(dustFirst ? "first" : "last"): \(measured) against \(expected)")
        }
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

    /// A grid a kernel wrote draws as the `Volume` holding the same samples
    /// draws, to the byte: the same march, the same light grid, the same medium.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aKernelWrittenGridDrawsAsTheCPUGridToTheByte() throws {
        let medium = Medium(density: 1.2, color: Color(linear: 1, green: 0.5, blue: 0.25))
        let cpu = VolumeProbe()
        cpu.medium = medium
        cpu.slabDepth = 1
        cpu.volume = VolumeProbe.kernelSlab(side: 9)
        cpu.lightToward = Vector3(0, 0, -1)
        let gpu = VolumeProbe()
        gpu.medium = medium
        gpu.slabDepth = 1
        gpu.computeSource = ComputeTexture3D(width: 9, height: 9, depth: 9)
        gpu.lightToward = Vector3(0, 0, -1)
        let a = try Self.render(cpu), b = try Self.render(gpu)
        #expect(a.rgb == b.rgb)
        // And the picture is a lit slab, not two blanks agreeing.
        #expect(a.row(a.height / 2, columns: 8 ..< a.width - 8) > 0.05)
    }

    /// The march strides through the blocks of its grid that hold no medium
    /// and leaves the bytes it leaves stepping through every one: a puff that
    /// fills part of its box, with holes in it, lit by a spot through its own
    /// shadow and the solids', from a CPU grid and from one a kernel writes.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [false, true])
    func skippingTheEmptyBlocksLeavesTheSameBytes(kernelWritten: Bool) throws {
        func render(skipping: Bool) throws -> [UInt8] {
            MetalRenderer.skipsEmptyVolumeBlocks = skipping
            defer { MetalRenderer.skipsEmptyVolumeBlocks = true }
            let probe = PuffProbe()
            probe.kernelWritten = kernelWritten
            return Pixels(try OllinApp.image(of: probe, frame: 1)).bytes
        }
        let skipped = try render(skipping: true)
        let stepped = try render(skipping: false)
        #expect(skipped == stepped)
        // And there is a lit cloud to compare, over a scene that differs from it.
        let plain = PuffProbe()
        plain.drawsVolume = false
        let without = Pixels(try OllinApp.image(of: plain, frame: 1)).bytes
        #expect(zip(skipped, without).filter { $0 != $1 }.count > 2_000)
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
    /// A grid a kernel fills on the first frame, drawn in place of `volume`
    /// when set: `0.25 + 0.5 * v`, the slab `kernelSlab` describes.
    var computeSource: ComputeTexture3D?
    private var filled = false
    private let fillSlab = ComputeKernel(entry: "fillSlab", """
        kernel void fillSlab(texture3d<float, access::write> out [[texture(0)]],
                             uint3 gid [[thread_position_in_grid]]) {
            uint3 n = uint3(out.get_width(), out.get_height(), out.get_depth());
            if (any(gid >= n)) return;
            out.write(float4(0.25 + 0.5 * float(gid.y) / float(n.y - 1)), gid);
        }
    """)
    /// The same slab for the CPU: values `k / 16 + 1 / 4`, exact in every float.
    static func kernelSlab(side: Int) -> Volume {
        Volume(width: side, height: side, depth: side) { _, v, _ in 0.25 + 0.5 * v }
    }
    var medium = Medium()
    var slabDepth = 1.0
    var ground: Color = .black
    /// Where a solid's front face sits, if one is drawn: a box centered on the
    /// axis, its back well behind the slab, black unless `solidColor` says.
    var solidFrontZ: Double?
    var solidColor: Color = .black
    /// Fog over the scene, its color and density, if set.
    var air: (color: Color, density: Double)?
    /// The way a directional light travels, if one is set.
    var lightToward: Vector3?
    /// Draw the volume before the solid instead of after it.
    var volumeFirst = false
    /// A second medium drawn over the same box, after the first one (or before
    /// it, with `secondFirst`), so the two boxes share their center exactly.
    var secondMedium: Medium?
    var secondFirst = false
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
        if let computeSource, !filled {
            compute(fillSlab, writing: computeSource)
            filled = true
        }
        if temporal { temporalAntialiasing() }
        noLights()
        if let air { fog(air.color, density: air.density) }
        if let lightToward {
            // A black ambient beside the one light; `ambientLight` turns the
            // lighting on, so with no light the solids stay flat.
            ambientLight(.black)
            castShadows()
            directionalLight(.white, direction: lightToward, intensity: 1,
                             castsShadow: blocksUpperHalf)
        }
        noStroke()
        if volumeFirst { drawTheVolume() }
        if let solidFrontZ {
            fill(solidColor)
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
        if let computeSource {
            drawVolume(computeSource, width: 2, height: 2, depth: slabDepth, medium: medium)
            return
        }
        guard let volume else { return }
        if let secondMedium, secondFirst {
            drawVolume(volume, width: 2, height: 2, depth: slabDepth, medium: secondMedium)
        }
        drawVolume(volume, width: 2, height: 2, depth: slabDepth, medium: medium)
        if let secondMedium, !secondFirst {
            drawVolume(volume, width: 2, height: 2, depth: slabDepth, medium: secondMedium)
        }
    }
}

/// A cloud's shadow on the solids under it (`drawVolume` under `castShadows()`):
/// the floor under a slab reads darker by the slab's transmittance toward the
/// light, read off the same light grid the cloud shades itself by, and nothing
/// changes until the frame casts shadows.
@Suite
@MainActor
struct CloudShadowTests {
    /// The floor under a slab whose thickness grows across it, lit straight
    /// down: each column keeps exp(-density * depth * value) of the floor
    /// beside the slab, for a grid the CPU filled and one a kernel wrote alike.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [false, true])
    func theFloorUnderACloudKeepsItsTransmittance(kernelWritten: Bool) throws {
        let probe = CloudShadowProbe()
        probe.kernelWritten = kernelWritten
        let frame = try VolumeTests.render(probe)
        let beside = CloudShadowProbe.floor(frame, x: -0.85)
        #expect(beside > 0.3, "the floor beside the slab reads \(beside)")
        var worst = 0.0
        for x in [-0.4, -0.2, 0.0, 0.2, 0.4] {
            let expected = exp(-probe.density * 0.5 * (x + 0.5))
            let ratio = CloudShadowProbe.floor(frame, x: x) / beside
            worst = max(worst, abs(ratio - expected))
            #expect(abs(ratio - expected) < 0.03, "x \(x): \(ratio) against \(expected)")
        }
        #expect(worst < 0.03, "worst column off its transmittance by \(worst)")
    }

    /// The same slab, the same light, no `castShadows()`: the floor under it
    /// reads as the floor beside it, and the frame is the frame with no slab.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCloudShadowsNothingUntilTheFrameCastsShadows() throws {
        let probe = CloudShadowProbe()
        probe.castsShadows = false
        let frame = try VolumeTests.render(probe)
        let beside = CloudShadowProbe.floor(frame, x: -0.85)
        let under = CloudShadowProbe.floor(frame, x: 0.4)
        #expect(abs(under / beside - 1) < 0.002, "under \(under), beside \(beside)")
        let bare = CloudShadowProbe()
        bare.castsShadows = false
        bare.drawsSlab = false
        #expect(frame.rgb == (try VolumeTests.render(bare)).rgb)
    }

    /// A grid a kernel wrote shadows the floor as the CPU grid holding the same
    /// samples does, to the byte.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aKernelWrittenCloudShadowsAsTheCPUGridDoes() throws {
        let cpu = CloudShadowProbe()
        let gpu = CloudShadowProbe()
        gpu.kernelWritten = true
        #expect(try VolumeTests.render(cpu).rgb == VolumeTests.render(gpu).rgb)
    }
}

/// A white floor under a slab of absorbing medium whose value grows from 0 at
/// its left face to 1 at its right (`u`), 1 wide, 0.5 thick, 2 deep, floating
/// 1.5 above the floor; a white directional light straight down. The
/// orthographic camera sits low over the floor looking along -z and down, so
/// the floor under the slab is in view below it and the slab itself lies above
/// the frame: a floor pixel at `x` is lit through the slab's column there and
/// seen through clear air.
private final class CloudShadowProbe: Sketch {
    var castsShadows = true
    var drawsSlab = true
    var kernelWritten = false
    let density = 2.0
    private let side = 9
    private lazy var grid = ComputeTexture3D(width: side, height: side, depth: side)
    private var filled = false
    private let fillRamp = ComputeKernel(entry: "fillRamp", """
        kernel void fillRamp(texture3d<float, access::write> out [[texture(0)]],
                             uint3 gid [[thread_position_in_grid]]) {
            uint3 n = uint3(out.get_width(), out.get_height(), out.get_depth());
            if (any(gid >= n)) return;
            out.write(float4(float(gid.x) / float(n.x - 1)), gid);
        }
    """)

    override var canvasSize: CanvasSize { .square(96) }

    /// The floor's red channel at world `x` on the row through the target,
    /// averaged over a few rows (the ratio depends on `x` alone).
    static func floor(_ frame: VolumeTests.Linear, x: Double) -> Double {
        let column = Int((x + 1) * Double(frame.width) / 2)
        let center = frame.height / 2
        return (center - 4 ... center + 4).reduce(0.0) { $0 + frame.channel(column, $1, 0) } / 9
    }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 3, 8), target: .zero, height: 2, near: 1, far: 40)
        noLights()
        ambientLight(.black)
        directionalLight(.white, direction: Vector3(0, -1, 0), intensity: 1)
        if castsShadows { castShadows() }
        noStroke()
        fill(.white)
        withState { translate(0, -0.05, 0); drawBox(width: 12, height: 0.1, depth: 12) }
        guard drawsSlab else { return }
        let medium = Medium(density: density, color: .black)
        withState {
            translate(0, 1.75, 0)
            if kernelWritten {
                if !filled { compute(fillRamp, writing: grid); filled = true }
                drawVolume(grid, width: 1, height: 0.5, depth: 2, medium: medium)
            } else {
                let ramp = Volume(width: side, height: side, depth: side) { u, _, _ in u }
                drawVolume(ramp, width: 1, height: 0.5, depth: 2, medium: medium)
            }
        }
    }
}

/// A 3D compute texture as storage: what a kernel writes is what a read gives
/// back, a fresh one is zero, and the ping-pong pair swaps.
@Suite
@MainActor
struct ComputeTexture3DTests {
    /// Each sample written by `gid` reads back at its place, `x` fastest.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aKernelWritesEverySampleOfAGrid() throws {
        let probe = GridProbe()
        _ = try VolumeTests.render(probe)
        let samples = try #require(probe.grid.snapshot())
        #expect(samples.count == 5 * 6 * 7)
        for z in 0 ..< 7 {
            for y in 0 ..< 6 {
                for x in 0 ..< 5 {
                    #expect(samples[(z * 6 + y) * 5 + x] == Float(x + 10 * y + 100 * z))
                }
            }
        }
    }

    /// A grid no kernel has touched holds zeros once something binds it (a
    /// volume drawn before its first kernel is empty), and each side is at
    /// least 2.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFreshGridIsZero() throws {
        let probe = GridProbe()
        probe.fills = false
        _ = try VolumeTests.render(probe)
        let samples = try #require(probe.grid.snapshot())
        #expect(samples.count == 5 * 6 * 7)
        #expect(samples.allSatisfy { $0 == 0 })
        let tiny = ComputeTexture3D(width: 0, height: 1, depth: 300)
        #expect(tiny.width == 2 && tiny.height == 2 && tiny.depth == 300)
    }

    /// The pair's `read` and `write` trade places on every swap.
    @Test func thePingPongPairSwaps() {
        let pair = PingPongTexture3D(width: 4, height: 4, depth: 4)
        let first = pair.read
        #expect(pair.write !== first)
        pair.swap()
        #expect(pair.write === first)
        #expect(pair.read !== first)
    }
}

/// A 5 x 6 x 7 grid at full precision, each sample its own coordinates.
private final class GridProbe: Sketch {
    let grid = ComputeTexture3D(width: 5, height: 6, depth: 7, format: .r32Float)
    var fills = true
    private let fill = ComputeKernel(entry: "fillCoordinates", """
        kernel void fillCoordinates(texture3d<float, access::write> out [[texture(0)]],
                                    uint3 gid [[thread_position_in_grid]]) {
            uint3 n = uint3(out.get_width(), out.get_height(), out.get_depth());
            if (any(gid >= n)) return;
            out.write(float4(float(gid.x + 10 * gid.y + 100 * gid.z)), gid);
        }
    """)

    override var canvasSize: CanvasSize { .square(8) }

    override func draw() {
        background(.black)
        if fills {
            compute(fill, writing: grid)
        } else {
            // Drawn untouched, so the renderer realizes the texture (a texture
            // nothing has bound has no contents to read back yet).
            ortho(eye: Vector3(0, 0, 10), target: .zero, height: 2, near: 1, far: 30)
            drawVolume(grid, size: 1, medium: Medium(density: 1, color: .black))
        }
    }
}

/// A lumpy puff in the lower part of a tall box, with a hollow through it,
/// lit by a spot from above that also lights a ball and the floor, seen in
/// perspective: most of the box is empty, in blocks the march can stride past.
private final class PuffProbe: Sketch {
    var kernelWritten = false
    var drawsVolume = true
    private let grid = ComputeTexture3D(width: 40, height: 56, depth: 40)
    private let fill = ComputeKernel(entry: "fillPuff", """
        kernel void fillPuff(texture3d<float, access::write> out [[texture(0)]],
                             uint3 gid [[thread_position_in_grid]]) {
            uint3 n = uint3(out.get_width(), out.get_height(), out.get_depth());
            if (any(gid >= n)) return;
            float3 u = float3(gid) / float3(n - 1);
            float3 c = u - float3(0.5, 0.32, 0.5);
            float r = length(c * float3(1.0, 1.4, 1.0));
            float lumps = 0.08 * sin(u.x * 23.0) * sin(u.y * 17.0 + 1.0) * sin(u.z * 19.0 + 2.0);
            float hole = length(float2(c.x, c.z)) < 0.06 ? 0.0 : 1.0;
            out.write(float4(max(0.0, 0.3 + lumps - r) * 6.0 * hole), gid);
        }
    """)
    /// The same puff for the CPU.
    nonisolated static func density(_ u: Double, _ v: Double, _ w: Double) -> Double {
        let c = (u - 0.5, v - 0.32, w - 0.5)
        let r = (c.0 * c.0 + c.1 * 1.4 * c.1 * 1.4 + c.2 * c.2).squareRoot()
        let lumps = 0.08 * sin(u * 23) * sin(v * 17 + 1) * sin(w * 19 + 2)
        let hole = (c.0 * c.0 + c.2 * c.2).squareRoot() < 0.06 ? 0.0 : 1.0
        return max(0, 0.3 + lumps - r) * 6 * hole
    }
    private lazy var volume = Volume(width: 40, height: 56, depth: 40, PuffProbe.density)

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        background(Color(white: 0.1))
        perspective(eye: Vector3(2.2, 1.6, 4.4), target: Vector3(0, 0.9, 0))
        ambientLight(Color(white: 0.15))
        castShadows()
        spotLight(.white, at: Vector3(0.3, 4, 0.2), direction: Vector3(-0.3, -4, -0.2),
                  coneAngle: 0.6, penumbra: 0.3, intensity: 2)
        noStroke()
        fill(Color(white: 0.5))
        drawGround(size: 8)
        withState {
            translate(0.15, 1.1, 0.1)
            fill(Color(white: 0.8))
            drawSphere(radius: 0.18)
        }
        guard drawsVolume else { return }
        withState {
            translate(0, 1.4, 0)
            if kernelWritten {
                compute(fill, writing: grid)
                drawVolume(grid, width: 2, height: 2.8, depth: 2, medium: .smoke)
            } else {
                drawVolume(volume, width: 2, height: 2.8, depth: 2, medium: .smoke)
            }
        }
    }
}
