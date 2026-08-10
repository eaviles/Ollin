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

/// Behavioral probes for the transmittance term (the translucency half): each
/// compares a thin backlit slab against a thick twin, because the term lives on
/// the dark side of a body and everything else in the frame must not move.
@Suite
@MainActor
struct TransmittanceRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean of one channel over the middle of the slab's camera-facing (dark) side.
    private func face(_ image: CGImage, channel: Int = 0) -> Double {
        let data = pixels(of: image)
        let w = image.width, h = image.height
        var sum = 0, count = 0
        for py in Int(Double(h) * 0.35)..<Int(Double(h) * 0.60) {
            for px in Int(Double(w) * 0.40)..<Int(Double(w) * 0.60) {
                sum += Int(data[(py * w + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBacklitThinSlabGlowsWhereAThickOneStaysDark() throws {
        // The term's signature: the caster's depth says how far the light traveled
        // inside the body, so a slab thinner than a couple of scattering radii
        // glows on its dark side while a deep one blocks.
        let thin = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thin), frame: 1))
        let thick = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thick), frame: 1))
        let a = face(thin), b = face(thick)
        #expect(a - b > 15, "expected a transmitted glow: thin \(a), thick \(b)")
        #expect(b < 10, "the thick body's face must stay dark, got \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func transmittedLightIsRedDominant() throws {
        // The default falloff runs red widest, so at a body a radius-and-a-half
        // thick only red survives the crossing: the blood-red of a backlit hand,
        // not a gray glow.
        let thin = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thin), frame: 1))
        let red = face(thin, channel: 0), blue = face(thin, channel: 2)
        #expect(red > blue * 2 + 8, "expected red through the body: red \(red), blue \(blue)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutACasterThereIsNoTransmittance() throws {
        // The term needs the caster's depth to measure thickness, so the same
        // backlit slab with shadows off keeps a black face (the scene carries no
        // ambient): the documented envelope, and the gate that keeps a
        // shadow-less scattering frame byte-identical to before the term existed.
        let off = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thinNoCaster), frame: 1))
        let a = face(off)
        #expect(a < 3, "expected a dark face with no caster, got \(a)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSpotCasterTransmitsThroughItsPerspectiveMap() throws {
        // The spot map's depth is non-linear, so this pins the perspective
        // linearization: a wrong constant reads a wild thickness and the thin
        // slab's glow either dies or floods the thick twin too.
        let thin = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thinSpot), frame: 1))
        let thick = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thickSpot), frame: 1))
        let a = face(thin), b = face(thick)
        #expect(a - b > 15, "expected a spot-lit glow: thin \(a), thick \(b)")
        #expect(b < 10, "the thick body under a spot must stay dark, got \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPointCasterTransmitsOnEitherPath() throws {
        // A point caster measures thickness by closest-hit ray on a ray-tracing
        // device and from the cube's stored linear distance elsewhere; the probe is
        // path-agnostic, so it covers whichever this machine runs.
        let thin = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thinPoint), frame: 1))
        let thick = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thickPoint), frame: 1))
        let a = face(thin), b = face(thick)
        #expect(a - b > 15, "expected a point-lit glow: thin \(a), thick \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func strengthZeroIsByteIdenticalToAPlainMaterial() throws {
        // At scattering 0 the branch is never taken, so a material that differs
        // only in its (inert) scatter fields renders the identical frame: the gate
        // that keeps existing scenes untouched.
        let zero = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thinZeroStrength), frame: 1))
        let plain = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thinPlain), frame: 1))
        #expect(pixels(of: zero) == pixels(of: plain))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aTransmittingRenderReproduces() throws {
        // Thickness comes from the same deterministic maps and rays the shadows
        // use, so two renders are byte-identical (the export promise).
        let a = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thin), frame: 1))
        let b = try #require(OllinApp.image(of: TransmitProbe.make(kind: .thin), frame: 1))
        #expect(pixels(of: a) == pixels(of: b))
    }
}

/// The transmittance probe scene: one upright slab facing the camera, the light
/// behind it, so the visible face is the body's dark side; `kind` varies the
/// slab's depth, the caster, and the material gates.
private final class TransmitProbe: Sketch {
    enum Kind {
        case thin, thick              // directional caster, 0.18 vs 2.0 deep
        case thinNoCaster             // same thin slab, shadows off
        case thinSpot, thickSpot      // spot caster (the perspective map)
        case thinPoint, thickPoint    // point caster (RT ray or cube distance)
        case thinZeroStrength         // scatter fields set, strength 0
        case thinPlain                // no scatter fields at all
    }
    var kind: Kind = .thin

    static func make(kind: Kind) -> TransmitProbe {
        let probe = TransmitProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 6, azimuth: 0,
                         elevation: 0, fieldOfView: .pi / 4, near: 1, far: 30))
        switch kind {
        case .thinSpot, .thickSpot:
            spotLight(.white, at: Vector3(0.3, 1.2, -6.5), direction: Vector3(-0.05, -0.05, 1),
                      angle: 0.9, intensity: 1.5)
        case .thinPoint, .thickPoint:
            pointLight(.white, at: Vector3(0.3, 1.2, -5.5), intensity: 1.5)
        default:
            directionalLight(.white, direction: Vector3(0.15, -0.25, 1), intensity: 1.4)
        }
        if kind != .thinNoCaster { castShadows() }
        noStroke()
        fill(Color(red: 0.92, green: 0.72, blue: 0.62))
        var m = Material.dielectric(roughness: 0.45)
        switch kind {
        case .thinPlain:
            break
        case .thinZeroStrength:
            m.scatteringRadius = 0.12
            m.scattering = 0
        default:
            m = .skin(radius: 0.12)
        }
        material(m)
        let deep: Double
        switch kind {
        case .thick, .thickSpot, .thickPoint: deep = 2.0
        default: deep = 0.18
        }
        withState {
            translate(0, 0.9, 0)
            drawBox(width: 2.2, height: 2.6, depth: deep)
        }
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
