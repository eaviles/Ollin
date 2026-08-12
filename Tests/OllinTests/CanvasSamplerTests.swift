import Foundation
import Metal
import Testing
@testable import Ollin

/// The canvas sample pass: the small compute kernel that reads N points back
/// from the rendered (sRGB display) texture. All Metal-gated; each GPU result
/// is checked against a CPU reference that applies the same rules, so the
/// pins are: exact byte round-trip (and RGBA channel order), averaging in
/// linear light (with the sRGB-space average as the counterfactual), edge
/// clamping, per-point radii, and the point-list re-upload.
@Suite
@MainActor
struct CanvasSamplerTests {

    // MARK: CPU reference (the kernel's rules, in Doubles)

    static func decode(_ byte: UInt8) -> Double {
        let c = Double(byte) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func encode(_ linear: Double) -> UInt8 {
        let c = min(max(linear, 0), 1)
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8((s * 255).rounded())
    }

    /// The kernel's box average over a byte grid: clamped taps, linear mean,
    /// sRGB re-encode.
    static func reference(_ pixels: [[SIMD4<UInt8>]], at x: Int, _ y: Int, radius: Int) -> SIMD4<UInt8> {
        let h = pixels.count, w = pixels[0].count
        var sum = SIMD4<Double>()
        for dy in -radius...radius {
            for dx in -radius...radius {
                let px = pixels[min(max(y + dy, 0), h - 1)][min(max(x + dx, 0), w - 1)]
                sum += SIMD4(decode(px.x), decode(px.y), decode(px.z), Double(px.w) / 255)
            }
        }
        let n = Double((2 * radius + 1) * (2 * radius + 1))
        let mean = sum / n
        return SIMD4(encode(mean.x), encode(mean.y), encode(mean.z),
                     UInt8((min(max(mean.w, 0), 1) * 255).rounded()))
    }

    /// A BGRA8-sRGB texture filled from an RGBA byte grid (rows of columns).
    static func makeTexture(_ pixels: [[SIMD4<UInt8>]]) -> MTLTexture? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let h = pixels.count, w = pixels[0].count
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = pixels[y][x]
                let i = (y * w + x) * 4
                bytes[i] = p.z; bytes[i + 1] = p.y; bytes[i + 2] = p.x; bytes[i + 3] = p.w
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: w * 4)
        return texture
    }

    static func flat(_ color: SIMD4<UInt8>, width: Int, height: Int) -> [[SIMD4<UInt8>]] {
        [[SIMD4<UInt8>]](repeating: [SIMD4<UInt8>](repeating: color, count: width), count: height)
    }

    // MARK: Pins

    @Test(.enabled(if: Snapshot.hasMetal))
    func bytesRoundTripExactlyAndChannelsStayInOrder() throws {
        // An asymmetric color: a BGRA/RGBA swap or a lost sRGB decode both fail.
        let color = SIMD4<UInt8>(200, 50, 10, 255)
        var grid = Self.flat(color, width: 32, height: 32)
        grid[5][20] = SIMD4(3, 250, 90, 128)
        let texture = try #require(Self.makeTexture(grid))
        let sampler = CanvasSampler(points: [
            .init(position: Vector2(8, 8)),
            .init(position: Vector2(20, 5)),
        ])
        let samples = try #require(sampler.sample(texture))
        #expect(samples[0] == color)
        #expect(samples[1] == SIMD4(3, 250, 90, 128))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func averagingRunsInLinearLightNotInSRGB() throws {
        // Left half black, right half white; a box astride the boundary. The
        // linear mean re-encoded is far brighter than the sRGB-space mean
        // (the counterfactual a naive byte average would produce).
        let w = 64, h = 16
        var grid = Self.flat(SIMD4(0, 0, 0, 255), width: w, height: h)
        for y in 0..<h { for x in 32..<w { grid[y][x] = SIMD4(255, 255, 255, 255) } }
        let radius = 4
        let sampler = CanvasSampler(points: [.init(position: Vector2(32, 8), radius: Double(radius))])
        let texture = try #require(Self.makeTexture(grid))
        let samples = try #require(sampler.sample(texture))

        let expected = Self.reference(grid, at: 32, 8, radius: radius)
        #expect(abs(Int(samples[0].x) - Int(expected.x)) <= 1)

        // The counterfactual: the same box averaged on the stored bytes.
        let sRGBMean = UInt8((Double(5 * 255) / 9).rounded())   // 5 of 9 columns white
        #expect(abs(Int(samples[0].x) - Int(sRGBMean)) > 20)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func offCanvasPointsClampToTheEdgeTexel() throws {
        var grid = Self.flat(SIMD4(10, 10, 10, 255), width: 24, height: 24)
        grid[0][0] = SIMD4(255, 0, 0, 255)
        grid[23][23] = SIMD4(0, 0, 255, 255)
        let texture = try #require(Self.makeTexture(grid))
        let sampler = CanvasSampler(points: [
            .init(position: Vector2(-50, -50)),
            .init(position: Vector2(500, 500)),
        ])
        let samples = try #require(sampler.sample(texture))
        #expect(samples[0] == SIMD4(255, 0, 0, 255))
        #expect(samples[1] == SIMD4(0, 0, 255, 255))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachPointCarriesItsOwnRadius() throws {
        // Two points at one position over a split field: the tight one reads
        // its texel, the wide one the mixed patch; each matches the reference.
        let w = 48, h = 48
        var grid = Self.flat(SIMD4(0, 0, 0, 255), width: w, height: h)
        for y in 0..<h { for x in 0..<w where (x + y).isMultiple(of: 2) {
            grid[y][x] = SIMD4(255, 255, 255, 255)
        } }
        let texture = try #require(Self.makeTexture(grid))
        let sampler = CanvasSampler(points: [
            .init(position: Vector2(24, 24), radius: 0),
            .init(position: Vector2(24, 24), radius: 6),
        ])
        let samples = try #require(sampler.sample(texture))
        #expect(samples[0] == Self.reference(grid, at: 24, 24, radius: 0))
        let wide = Self.reference(grid, at: 24, 24, radius: 6)
        #expect(abs(Int(samples[1].x) - Int(wide.x)) <= 1)
        #expect(samples[0] != samples[1])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func reassignedPointsResampleAtTheNewPositions() throws {
        var grid = Self.flat(SIMD4(0, 0, 0, 255), width: 32, height: 32)
        for y in 0..<32 { for x in 16..<32 { grid[y][x] = SIMD4(0, 255, 0, 255) } }
        let texture = try #require(Self.makeTexture(grid))
        let sampler = CanvasSampler(points: [.init(position: Vector2(4, 4))])
        let first = try #require(sampler.sample(texture))
        #expect(first[0] == SIMD4(0, 0, 0, 255))
        sampler.points = [.init(position: Vector2(24, 4))]
        let second = try #require(sampler.sample(texture))
        #expect(second[0] == SIMD4(0, 255, 0, 255))
    }
}
