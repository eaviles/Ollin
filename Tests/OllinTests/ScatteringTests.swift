@testable import Ollin
import Testing
import CoreGraphics
import simd

/// The CPU half of the subsurface scattering: the diffusion kernel is a pure,
/// deterministic function of a material's falloff color and strength, and its
/// invariants are exact, so they pin without a GPU.
@Suite
struct ScatterKernelTests {

    private let skinFalloff = SIMD3<Float>(1.0, 0.37, 0.3)

    @Test func theKernelConservesEnergyAtAnyStrength() {
        for strength: Float in [0, 0.3, 0.85, 1] {
            let k = MetalRenderer.scatterKernel(falloff: skinFalloff, strength: strength)
            #expect(k.count == MetalRenderer.scatterTapCount)
            var sum = SIMD3<Float>.zero
            for t in k { sum += SIMD3(t.x, t.y, t.z) }
            for c in 0..<3 {
                #expect(abs(sum[c] - 1) < 1e-5,
                        "channel \(c) sums \(sum[c]) at strength \(strength)")
            }
        }
    }

    @Test func strengthZeroIsExactlyTheIdentity() {
        let k = MetalRenderer.scatterKernel(falloff: skinFalloff, strength: 0)
        #expect(k[0].x == 1 && k[0].y == 1 && k[0].z == 1)
        for t in k.dropFirst() {
            #expect(t.x == 0 && t.y == 0 && t.z == 0)
        }
    }

    @Test func theCenterTapLeadsAndOffsetsStaySymmetric() {
        let k = MetalRenderer.scatterKernel(falloff: skinFalloff, strength: 0.85)
        #expect(k[0].w == 0)
        // The remaining taps pair off symmetrically about zero, spanning ±3.
        let offsets = k.dropFirst().map(\.w).sorted()
        #expect(abs(offsets.first! + 3) < 1e-5 && abs(offsets.last! - 3) < 1e-5)
        for (a, b) in zip(offsets, offsets.reversed()) {
            #expect(abs(a + b) < 1e-5)
        }
    }

    @Test func aWiderFalloffCarriesMoreWeightFarOut() {
        // The skin falloff runs red widest: at the far taps the red weight must
        // dominate blue, which is what makes the diffusion halo warm.
        let k = MetalRenderer.scatterKernel(falloff: skinFalloff, strength: 0.85)
        let far = k.filter { abs($0.w) > 1.5 }
        let red = far.reduce(Float(0)) { $0 + $1.x }
        let blue = far.reduce(Float(0)) { $0 + $1.z }
        #expect(red > blue * 3, "far-tap red \(red) vs blue \(blue)")
    }

    @Test func theKernelIsDeterministic() {
        let a = MetalRenderer.scatterKernel(falloff: skinFalloff, strength: 0.85)
        let b = MetalRenderer.scatterKernel(falloff: skinFalloff, strength: 0.85)
        #expect(a == b)
    }
}

/// Behavioral probes for the diffusion blur itself: each compares a pair of renders
/// differing only in the scattering, because the effect lives in a band around the
/// terminator that a whole-frame mean would average away.
@Suite
@MainActor
struct ScatteringRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean of one channel over a fractional region (top-left origin).
    private func mean(_ data: [UInt8], width: Int, height: Int, channel: Int,
                      x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        var sum = 0, count = 0
        for py in Int(Double(height) * y.lowerBound)..<Int(Double(height) * y.upperBound) {
            for px in Int(Double(width) * x.lowerBound)..<Int(Double(width) * x.upperBound) {
                sum += Int(data[(py * width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    /// The shadow band just past the terminator (the light comes from +x, so the
    /// sphere's left third is its shadow side).
    private func shadowBand(_ image: CGImage, channel: Int) -> Double {
        mean(pixels(of: image), width: image.width, height: image.height,
             channel: channel, x: 0.30...0.42, y: 0.42...0.58)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func scatteringCarriesLightPastTheTerminator() throws {
        // The diffusion's signature: energy from the lit side re-emerging in the
        // shadow just past the terminator, where the bare twin stays near black.
        let skin = try #require(OllinApp.image(of: ScatterProbe.make(kind: .skin), frame: 1))
        let bare = try #require(OllinApp.image(of: ScatterProbe.make(kind: .bare), frame: 1))
        let a = shadowBand(skin, channel: 0), b = shadowBand(bare, channel: 0)
        #expect(a - b > 4, "expected shadow-side glow: scattering \(a), bare \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func redOutrunsBlueAcrossTheTerminator() throws {
        // The default falloff runs red widest, so the shadow band's gain must be
        // red-dominant relative to the bare twin: the warm halo, not a gray blur.
        let skin = try #require(OllinApp.image(of: ScatterProbe.make(kind: .skin), frame: 1))
        let bare = try #require(OllinApp.image(of: ScatterProbe.make(kind: .bare), frame: 1))
        let redGain = shadowBand(skin, channel: 0) - shadowBand(bare, channel: 0)
        let blueGain = shadowBand(skin, channel: 2) - shadowBand(bare, channel: 2)
        #expect(redGain > blueGain * 1.5,
                "expected a warm halo: red gain \(redGain), blue gain \(blueGain)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLargerRadiusSpreadsFarther() throws {
        // Doubling the radius must push more light deeper into the shadow side.
        let near = try #require(OllinApp.image(of: ScatterProbe.make(kind: .skin), frame: 1))
        let wide = try #require(OllinApp.image(of: ScatterProbe.make(kind: .wideRadius), frame: 1))
        let a = shadowBand(wide, channel: 0), b = shadowBand(near, channel: 0)
        #expect(a - b > 2, "expected a wider spread: radius x2 \(a), x1 \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOccludedSurfaceScattersNothing() throws {
        // A scattering sphere hidden behind a wall must leave the frame exactly as
        // the same scene with its scattering off: the mask pass is depth-tested, so
        // hidden surfaces mark no pixels, and unmarked pixels pass through the blur
        // bit-exact.
        let hidden = try #require(OllinApp.image(of: ScatterProbe.make(kind: .hiddenSkin), frame: 1))
        let plain = try #require(OllinApp.image(of: ScatterProbe.make(kind: .hiddenBare), frame: 1))
        #expect(pixels(of: hidden) == pixels(of: plain))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func pixelsOffTheSurfaceAreUntouched() throws {
        // Within a scattering frame, everything that is not a marked surface (the
        // background and the bare twin) must be byte-identical to the render with
        // the scattering off: the per-pixel early-out, not a tolerance.
        let skin = try #require(OllinApp.image(of: ScatterProbe.make(kind: .skin), frame: 1))
        let bare = try #require(OllinApp.image(of: ScatterProbe.make(kind: .bare), frame: 1))
        let a = pixels(of: skin), b = pixels(of: bare)
        let w = skin.width, h = skin.height
        // The sphere sits in the middle; the left and right eighths are background.
        var mismatches = 0
        for py in stride(from: 0, to: h, by: 4) {
            for px in 0..<(w / 8) {
                for c in 0..<3 {
                    if a[(py * w + px) * 4 + c] != b[(py * w + px) * 4 + c] { mismatches += 1 }
                    let rx = w - 1 - px
                    if a[(py * w + rx) * 4 + c] != b[(py * w + rx) * 4 + c] { mismatches += 1 }
                }
            }
        }
        #expect(mismatches == 0, "\(mismatches) background channel values moved")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aScatteringRenderReproduces() throws {
        // The kernel, the mask, and the blur are pure functions of the frame, so
        // two renders of the same sketch are byte-identical (the export promise).
        let a = try #require(OllinApp.image(of: ScatterProbe.make(kind: .skin), frame: 1))
        let b = try #require(OllinApp.image(of: ScatterProbe.make(kind: .skin), frame: 1))
        #expect(pixels(of: a) == pixels(of: b))
    }
}

/// The probe scene: one sphere under a directional light from +x (so the left side
/// is shadow), the scattering varied by `kind`; the hidden variants put a wall in
/// front of it.
private final class ScatterProbe: Sketch {
    enum Kind {
        case skin, bare               // the diffusion vs its twin
        case wideRadius               // twice the radius
        case hiddenSkin, hiddenBare   // occluded behind a wall
    }
    var kind: Kind = .skin

    static func make(kind: Kind) -> ScatterProbe {
        let probe = ScatterProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: .zero, radius: 6, azimuth: 0, elevation: 0,
                         fieldOfView: .pi / 4, near: 1, far: 30))
        directionalLight(.white, direction: Vector3(-1, -0.15, -0.3), intensity: 1.3)
        noStroke()
        fill(Color(red: 0.92, green: 0.72, blue: 0.62))
        let base = Material.dielectric(roughness: 0.45)
        let skin = Material.skin(radius: 0.5)
        let wide = Material.skin(radius: 1.0)
        switch kind {
        case .skin: material(skin)
        case .bare: material(base)
        case .wideRadius: material(wide)
        case .hiddenSkin, .hiddenBare:
            // The wall fills the view; the sphere is fully behind it.
            withState {
                translate(0, 0, 2)
                fill(Color(white: 0.4)); material(base)
                drawBox(width: 8, height: 8, depth: 0.4)
            }
            material(kind == .hiddenSkin ? skin : base)
        }
        drawSphere(radius: 1.5)
    }
}
