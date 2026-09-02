import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Ollin

/// Behavioral probes for the global-illumination probe field. Each claim is measured
/// against its counterfactual twin (GI off, the wall repainted, the box unsealed by a
/// light moved inside), because a whole-frame snapshot diff would average the bounce
/// into its tolerance. RT-gated: without ray tracing there are no probes to trace.
@Suite
@MainActor
struct GlobalIlluminationTests {

    // MARK: Pixel support

    private func pixels(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    /// Mean (r, g, b) over a fractional band of the frame.
    private func bandMean(_ image: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>)
        -> (r: Double, g: Double, b: Double) {
        let (data, w, h) = pixels(image)
        var r = 0, g = 0, b = 0, count = 0
        for py in Int(Double(h) * y.lowerBound)..<Int(Double(h) * y.upperBound) {
            for px in Int(Double(w) * x.lowerBound)..<Int(Double(w) * x.upperBound) {
                let i = (py * w + px) * 4
                r += Int(data[i]); g += Int(data[i + 1]); b += Int(data[i + 2]); count += 1
            }
        }
        let n = Double(max(count, 1))
        return (Double(r) / n, Double(g) / n, Double(b) / n)
    }

    // MARK: The claims

    /// The headline: a room whose only light is a pool on the floor. Direct light
    /// cannot reach the ceiling at all, so any ceiling brightness is the probes'
    /// bounce and the counterfactual (GI off) pins it near black.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func bounceLightFillsWhatDirectCannotReach() throws {
        func ceiling(gi: Bool) throws -> Double {
            let image = try #require(OllinApp.image(of: GIRoomProbe.make(gi: gi), frame: 1))
            let m = bandMean(image, x: 0.35...0.65, y: 0.16...0.26)
            return (m.r + m.g + m.b) / 3
        }
        let lit = try ceiling(gi: true)
        let dark = try ceiling(gi: false)
        #expect(dark < 8, "the ceiling must be unlit without bounce: \(dark)")
        #expect(lit - dark > 40, "expected bounce light on the ceiling: on \(lit), off \(dark)")
    }

    /// Color bleeding: the white floor beside the red wall picks up red it cannot get
    /// from the white spot. The counterfactual repaints that wall white, so the pair
    /// isolates the wall's own reflected color from every other term.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aColoredWallDyesItsNeighborhood() throws {
        func floorRedness(redWall: Bool) throws -> Double {
            let image = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true, redWall: redWall),
                                                    frame: 1))
            let m = bandMean(image, x: 0.10...0.24, y: 0.62...0.74)
            return m.r - m.g
        }
        let dyed = try floorRedness(redWall: true)
        let plain = try floorRedness(redWall: false)
        #expect(dyed - plain > 8,
                "expected the red wall's bounce on the floor beside it: red \(dyed), white \(plain)")
    }

    /// The leak test: a sealed box with a bright point light outside stays dark inside.
    /// The probes outside the box are bright, and only the visibility weights stand
    /// between them and the interior; the counterfactual moves the light inside, which
    /// proves the camera really is watching the interior surfaces.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func lightDoesNotLeakIntoASealedBox() throws {
        func interior(lightInside: Bool) throws -> Double {
            let image = try #require(OllinApp.image(of: GISealedBoxProbe.make(lightInside: lightInside),
                                                    frame: 1))
            let m = bandMean(image, x: 0.3...0.7, y: 0.3...0.7)
            return (m.r + m.g + m.b) / 3
        }
        let sealed = try interior(lightInside: false)
        let control = try interior(lightInside: true)
        #expect(control > 60, "the interior must be visible when lit from inside: \(control)")
        #expect(sealed < 8, "bounce light must not leak through the sealed walls: \(sealed)")
    }

    /// The artistic dial: doubling the intensity brightens the bounce (measured on the
    /// ceiling, which is bounce-only), and intensity 0 is the off picture.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func intensityScalesTheBounce() throws {
        func ceiling(intensity: Double) throws -> Double {
            let image = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true, intensity: intensity),
                                                    frame: 1))
            let m = bandMean(image, x: 0.35...0.65, y: 0.16...0.26)
            return (m.r + m.g + m.b) / 3
        }
        let one = try ceiling(intensity: 1)
        let two = try ceiling(intensity: 2)
        let zero = try ceiling(intensity: 0)
        #expect(two > one + 15, "intensity 2 must out-bounce intensity 1: \(two) vs \(one)")
        #expect(zero < 8, "intensity 0 must contribute nothing: \(zero)")
    }

    /// `noGlobalIllumination()` after `globalIllumination()` is pixel-identical to
    /// never asking: the per-frame state reset, the renderer gate, and the untouched
    /// carriers all in one equality.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func turningItOffIsTheDefaultAgain() throws {
        let off = try #require(OllinApp.image(of: GIRoomProbe.make(gi: false), frame: 1))
        let toggled = try #require(OllinApp.image(of: GIRoomProbe.make(gi: false, toggle: true),
                                                  frame: 1))
        #expect(pixels(off).data == pixels(toggled).data,
                "an on-then-off frame must be byte-identical to never-on")
    }

    /// A mirror interior carries the bounce: the polished strip reflects the upper back
    /// wall, whose ambient the GI toggle swaps between the honest occluded bounce and
    /// the unoccluded environment cube. The strip is pure metal (no diffuse of its
    /// own), so before the hit shade sampled the field its image was untouched by the
    /// toggle; a substantial on/off difference *inside the reflection* is exactly the
    /// mirror-interior term.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aMirrorInteriorCarriesTheBounce() throws {
        func strip(gi: Bool) throws -> Double {
            let image = try #require(OllinApp.image(of: GIMirrorProbe.make(gi: gi), frame: 1))
            let m = bandMean(image, x: 0.35...0.65, y: 0.90...0.98)
            return (m.r + m.g + m.b) / 3
        }
        let on = try strip(gi: true)
        let off = try strip(gi: false)
        #expect(abs(on - off) > 25,
                "the mirrored wall's ambient must follow the GI toggle: on \(on), off \(off)")
    }

    /// A render target's meshes gather the field: the bounce-only-ceiling claim, with
    /// the whole scene drawn inside `withTarget` and composited back (the
    /// depth-of-field shape, geometry existing only in the layer).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aRenderTargetGathersTheField() throws {
        func ceiling(gi: Bool) throws -> Double {
            let image = try #require(OllinApp.image(of: GITargetProbe.make(gi: gi), frame: 1))
            let m = bandMean(image, x: 0.35...0.65, y: 0.16...0.26)
            return (m.r + m.g + m.b) / 3
        }
        let lit = try ceiling(gi: true)
        let dark = try ceiling(gi: false)
        #expect(dark < 8, "a target's ceiling must be unlit without bounce: \(dark)")
        #expect(lit - dark > 40,
                "expected bounce light on the target's ceiling: on \(lit), off \(dark)")
    }

    /// The quality parameter is plumbed end to end: on the export path `.default` resolves
    /// to `.detail` (the automatic lift), so the two are byte-identical, while
    /// `.performance` traces fewer rays and iterations and lands on different bytes.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theQualityParameterResolvesTheExportTiers() throws {
        func render(_ quality: RenderQuality?) throws -> [UInt8] {
            let image = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true, quality: quality),
                                                    frame: 1))
            return pixels(image).data
        }
        let automatic = try render(nil)
        let detail = try render(.detail)
        let performance = try render(.performance)
        #expect(automatic == detail,
                "an export's automatic tier must be .detail, byte-identically")
        #expect(automatic != performance,
                "`.performance` must actually trace a lighter update than `.detail`")
    }

    /// Camera cascades change the near field on a vast scene: the red wall's face,
    /// standing on a brilliantly lit floor, reads the floor's bounce through the fine
    /// cascades where the single 512-probe volume spreads ~50-unit probes and smears
    /// it. The counterfactual is the same scene and camera with only the ladder
    /// removed (the test seam), so the pair isolates exactly the cascades' term.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func cascadesResolveTheNearFieldOnAVastScene() throws {
        func wallFace(cascades: Bool) throws -> Double {
            MetalRenderer.giCascadesEnabledForTesting = cascades
            defer { MetalRenderer.giCascadesEnabledForTesting = true }
            let image = try #require(OllinApp.image(of: GIVastProbe.make(), frame: 1))
            let m = bandMean(image, x: 0.20...0.27, y: 0.36...0.44)
            return (m.r + m.g + m.b) / 3
        }
        let cascaded = try wallFace(cascades: true)
        let single = try wallFace(cascades: false)
        #expect(single > 40, "the wall must be lit in both renders: \(single)")
        #expect(abs(cascaded - single) > 8,
                "the fine cascades must change the wall's floor bounce: cascaded \(cascaded), single \(single)")
    }

    /// The coarseness threshold: a room-scale scene never derives camera cascades, so
    /// disabling them changes nothing, byte-identically. This is the guard that the
    /// shipped single-volume path (gi-3d and every room GI scene) is untouched by the
    /// whole cascade mechanism.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aRoomScaleSceneStaysSingleVolume() throws {
        let normal = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true), frame: 1))
        MetalRenderer.giCascadesEnabledForTesting = false
        defer { MetalRenderer.giCascadesEnabledForTesting = true }
        let forced = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true), frame: 1))
        #expect(pixels(normal).data == pixels(forced).data,
                "a room under the coarseness threshold must not derive cascades")
    }

    /// A cascaded export stays a pure function of the frame: the headless path refits
    /// the ladder from the frame's own camera and bounds every frame, so two renders
    /// of the vast scene are byte-identical (the promise every export stands on).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aCascadedExportIsAPureFunctionOfTheFrame() throws {
        let first = try #require(OllinApp.image(of: GIVastProbe.make(), frame: 1))
        let second = try #require(OllinApp.image(of: GIVastProbe.make(), frame: 1))
        #expect(pixels(first).data == pixels(second).data,
                "two renders of one cascaded GI frame must be byte-identical")
    }

    /// The ladder derivation is the design in numbers: nothing at room scale, halving
    /// cascades once the fitted spacing crosses half the working distance, the finest
    /// near a quarter of it, at most three, axis counts clamped to the scene's slab
    /// with covered axes pinned. Pure CPU.
    @Test
    func theCascadeLadderFollowsTheWorkingScale() {
        // Room scale: spacing well under half the working distance, no ladder.
        let room = MetalRenderer.giCascadeLadder(volumeOrigin: SIMD3(-5, 0, -5),
                                                 volumeSpan: SIMD3(10, 6, 10),
                                                 spacing: SIMD3(repeating: 1.5),
                                                 eye: SIMD3(0, 2, 4), workingScale: 9.5)
        #expect(room.isEmpty, "a room-scale scene must stay single-volume: \(room)")
        // Terrain scale: the vast probe's own numbers (52-unit spacing, W 13.7).
        let vast = MetalRenderer.giCascadeLadder(volumeOrigin: SIMD3(-390, -20, -390),
                                                 volumeSpan: SIMD3(780, 39, 780),
                                                 spacing: SIMD3(52, 39, 52),
                                                 eye: SIMD3(6, 4, 12), workingScale: 13.75)
        #expect(vast.count == 3, "a vast scene must ladder to three cascades: \(vast.count)")
        #expect(vast.map(\.spacing) == [26, 13, 6.5],
                "cascades must halve from the scene spacing: \(vast.map(\.spacing))")
        for cas in vast {
            let product = Int(cas.counts.x) * Int(cas.counts.y) * Int(cas.counts.z)
            #expect(product <= 512 && cas.counts.min() >= 2 && cas.counts.max() <= 8,
                    "a cascade must fit its atlas slot: \(cas.counts)")
        }
        // The vertical axis: covered by the slab at every rung, so pinned (never
        // scrolls) and centered on it, while the vast axes anchor on the eye.
        #expect(vast.allSatisfy { $0.scrolls.y == 0 && $0.scrolls.x == 1 && $0.scrolls.z == 1 },
                "slab-covered axes pin, vast axes scroll: \(vast.map(\.scrolls))")
        let finest = vast[2]
        #expect(abs((finest.origin.x + Float(finest.counts.x - 1) * finest.spacing * 0.5) - 6) < 1e-3,
                "a scrolling axis centers its window on the eye")
        // Determinism: the derivation is a pure function.
        let again = MetalRenderer.giCascadeLadder(volumeOrigin: SIMD3(-390, -20, -390),
                                                  volumeSpan: SIMD3(780, 39, 780),
                                                  spacing: SIMD3(52, 39, 52),
                                                  eye: SIMD3(6, 4, 12), workingScale: 13.75)
        #expect(again == vast, "the ladder must derive identically twice")
    }

    /// The scroll math is the reference's: a dead zone of one whole plane (truncation
    /// toward zero), the phase wrap that keeps a stationary lattice point on its
    /// texel, and entered slabs at the edge the window moved toward. Pure CPU.
    @Test
    func theScrollMathKeepsStationaryProbesPut() {
        let counts = SIMD3<Int32>(8, 3, 8)
        let scrolls = SIMD3<Int32>(1, 0, 1)
        // Dead zone: anchor within one spacing of the center scrolls nothing.
        let still = MetalRenderer.giScrollDelta(origin: SIMD3(-14, 0, -14), spacing: 4,
                                                counts: counts, scrolls: scrolls,
                                                anchor: SIMD3(3.9, 0, -3.9))
        #expect(still == .zero, "under one plane of drift must not scroll: \(still)")
        // A move of 2.5 spacings scrolls 2 whole planes, pinned axes never.
        let delta = MetalRenderer.giScrollDelta(origin: SIMD3(-14, 0, -14), spacing: 4,
                                                counts: counts, scrolls: scrolls,
                                                anchor: SIMD3(10, 50, -4.1))
        #expect(delta == SIMD3(2, 0, -1), "whole planes toward the anchor: \(delta)")
        // The wrap: phase accumulates modulo counts, negatives included.
        var phase = SIMD3<Int32>.zero
        phase = MetalRenderer.giWrappedPhase(phase, delta: SIMD3(2, 0, -1), counts: counts)
        #expect(phase == SIMD3(2, 0, 7), "the phase wraps per axis: \(phase)")
        phase = MetalRenderer.giWrappedPhase(phase, delta: SIMD3(-3, 0, 2), counts: counts)
        #expect(phase == SIMD3(7, 0, 1), "the wrap survives sign changes: \(phase)")
        // The stationary-probe identity: a lattice point's physical texel is the same
        // before and after a scroll (the tank-tread rule the atlases stand on).
        let n: Int32 = 8, d: Int32 = 3, oldPhase: Int32 = 5
        let newPhase = ((oldPhase + d) % n + n) % n
        for g in 0..<(n - d) {   // points covered by both windows
            let physOld = ((g + d) + oldPhase) % n   // old window grid coord is g + d
            let physNew = (g + newPhase) % n
            #expect(physOld == physNew, "a stationary probe must keep its texel")
        }
        // Entered slabs: the planes at the edge the window moved toward.
        #expect(MetalRenderer.giEnteredRange(delta: 3, count: 8) == (5, 3))
        #expect(MetalRenderer.giEnteredRange(delta: -2, count: 8) == (0, 2))
        #expect(MetalRenderer.giEnteredRange(delta: 0, count: 8) == (0, 0))
        #expect(MetalRenderer.giEnteredRange(delta: 12, count: 8) == (0, 8),
                "a teleport clears the whole cascade")
    }

    /// The per-axis probe counts follow the fitted volume's aspect under the fixed
    /// 512 budget: a cube keeps the shipped 8x8x8, a pancake spends its rows
    /// horizontally, and no extent can exceed the budget or drop an axis below a
    /// trilinear cage. Pure CPU (the derivation is a pure function of the extent).
    @Test
    func probeCountsFollowTheVolumesAspect() {
        #expect(MetalRenderer.giAxisCounts(for: SIMD3(10, 10, 10)) == SIMD3(8, 8, 8),
                "a cubic volume must keep the shipped 8x8x8")
        let pancake = MetalRenderer.giAxisCounts(for: SIMD3(100, 5, 100))
        #expect(pancake == SIMD3(16, 2, 16),
                "a flat scene must spend its probes horizontally: \(pancake)")
        let beam = MetalRenderer.giAxisCounts(for: SIMD3(100, 5, 10))
        #expect(beam.x == 16 && beam.y < beam.z,
                "counts must order by extent: \(beam)")
        // Budget + floor + cap over a deterministic sweep of aspect ratios.
        for i in 0..<64 {
            let ext = SIMD3<Float>(Float(1 + i % 8) * 3.7,
                                   Float(1 + (i / 8) % 8) * 1.3,
                                   Float(1 + i / 16) * 9.1)
            let c = MetalRenderer.giAxisCounts(for: ext)
            #expect(Int(c.x) * Int(c.y) * Int(c.z) <= 512, "budget exceeded at \(ext): \(c)")
            #expect(c.min() >= 2 && c.max() <= 16, "axis out of range at \(ext): \(c)")
        }
    }

    /// The new gathering paths are as deterministic as the main one: two renders of
    /// the mirror frame (GI + deferred supersampled reflections) and of the target
    /// frame (GI + an effect layer) are byte-identical.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theNewPathsExportDeterministically() throws {
        let mirrorA = try #require(OllinApp.image(of: GIMirrorProbe.make(gi: true), frame: 1))
        let mirrorB = try #require(OllinApp.image(of: GIMirrorProbe.make(gi: true), frame: 1))
        #expect(pixels(mirrorA).data == pixels(mirrorB).data,
                "two renders of the mirror frame must be byte-identical")
        let targetA = try #require(OllinApp.image(of: GITargetProbe.make(gi: true), frame: 1))
        let targetB = try #require(OllinApp.image(of: GITargetProbe.make(gi: true), frame: 1))
        #expect(pixels(targetA).data == pixels(targetB).data,
                "two renders of the target frame must be byte-identical")
    }

    /// Headless determinism: the export path converges the field within the frame from
    /// iteration-indexed seeds, so two renders of the same frame are byte-identical
    /// (the promise every snapshot and video export stands on).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anExportIsAPureFunctionOfTheFrame() throws {
        let first = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true), frame: 1))
        let second = try #require(OllinApp.image(of: GIRoomProbe.make(gi: true), frame: 1))
        #expect(pixels(first).data == pixels(second).data,
                "two renders of one GI frame must be byte-identical")
    }
}

/// The mirror room: sealed, spot-pooled like `GIRoomProbe`, with a polished-metal
/// strip on the floor reflecting the bounce-only ceiling, an environment (traced
/// reflections require one) and `rayTracedReflections()` on. A pure metal carries no
/// diffuse of its own, so the strip's image changes under the GI toggle only through
/// the *hit shade's* ambient: exactly the term the mirror-interior wiring adds.
private final class GIMirrorProbe: Sketch {
    var gi = true

    static func make(gi: Bool) -> GIMirrorProbe {
        let probe = GIMirrorProbe()
        probe.gi = gi
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 2.3, 4.0), target: Vector3(0, 1.4, -1),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 40)
        environment(.sky().lightingOnly())
        spotLight(.white, at: Vector3(0, 3.8, -2.0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 3, penumbra: 0.4, intensity: 3)
        castShadows()
        rayTracedReflections()
        if gi { globalIllumination() }
        // A sealed room, interior 8 x 4.2 x 8, camera inside its front half.
        withState { fill(Color(white: 0.9)); translate(0, -0.1, 0); drawBox(width: 8.4, height: 0.2, depth: 9.4) }
        withState { fill(Color(white: 0.9)); translate(0, 4.3, 0); drawBox(width: 8.4, height: 0.2, depth: 9.4) }
        withState { fill(Color(white: 0.9)); translate(0, 2.1, -4.1); drawBox(width: 8.4, height: 4.6, depth: 0.2) }
        withState { fill(Color(white: 0.9)); translate(0, 2.1, 4.8); drawBox(width: 8.4, height: 4.6, depth: 0.2) }
        withState { fill(Color(white: 0.9)); translate(-4.1, 2.1, 0); drawBox(width: 0.2, height: 4.6, depth: 9.4) }
        withState { fill(Color(white: 0.9)); translate(4.1, 2.1, 0); drawBox(width: 0.2, height: 4.6, depth: 9.4) }
        // The mirror strip, flat on the floor between the camera and the pool: the
        // camera sees the upper back wall (bounce-only) in it.
        withState {
            fill(Color(white: 0.95))
            material(.metal(roughness: 0.05))
            translate(0, 0.08, 1.0)
            drawBox(width: 3.4, height: 0.16, depth: 2.4)
        }
    }
}

/// The target room: the same bounce-only-ceiling claim as `GIRoomProbe`, but with the
/// whole 3D scene drawn *inside* a render target and composited back, so it pins the
/// field reaching a `withTarget` layer's meshes (and the volume fitting geometry that
/// exists only in a target, the depth-of-field shape).
private final class GITargetProbe: Sketch {
    var gi = true

    static func make(gi: Bool) -> GITargetProbe {
        let probe = GITargetProbe()
        probe.gi = gi
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 2, 0), radius: 9.5,
                         azimuth: 0, elevation: 0.02, fieldOfView: .pi / 3.2,
                         near: 1, far: 40))
        spotLight(.white, at: Vector3(0, 3.8, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 3, penumbra: 0.4, intensity: 3)
        castShadows()
        if gi { globalIllumination() }
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            withState { fill(Color(white: 0.9)); translate(0, -0.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
            withState { fill(Color(white: 0.9)); translate(0, 4.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
            withState { fill(Color(white: 0.9)); translate(0, 2, -4.1); drawBox(width: 8, height: 4.4, depth: 0.2) }
            withState { fill(Color(white: 0.9)); translate(-4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
            withState { fill(Color(white: 0.9)); translate(4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
            withState { fill(Color(white: 0.85)); translate(1.6, 0.7, -1.0); drawSphere(radius: 0.7) }
        }
        drawImage(scene.image, 0, 0)
    }
}

/// The vast scene: a terrain-scale ground plane (the fitted volume's spacing lands an
/// order of magnitude past the coarseness threshold) with a small lit structure near
/// the camera, so the camera cascades have near-field bounce to resolve that the
/// single 512-probe volume cannot.
private final class GIVastProbe: Sketch {
    static func make() -> GIVastProbe { GIVastProbe() }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(6, 4, 12), target: Vector3(0, 1, 0),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 2000)
        pointLight(.white, at: Vector3(2, 6, 2), intensity: 8)
        castShadows()
        globalIllumination()
        withState { fill(Color(white: 0.85)); translate(0, -0.2, 0); drawBox(width: 600, height: 0.4, depth: 600) }
        withState { fill(Color(hex: 0xd03030)); translate(-2.5, 1.5, 0); drawBox(width: 0.3, height: 3, depth: 6) }
        withState { fill(Color(white: 0.9)); translate(0, 1, 0); drawBox(width: 2, height: 2, depth: 2) }
    }
}

/// The probe room: a Cornell-style box whose only light is a spot pool on the floor,
/// with one wall red (or repainted white for the bleed counterfactual).
private final class GIRoomProbe: Sketch {
    var gi = true
    var redWall = true
    var intensity = 1.0
    var toggle = false
    var quality: RenderQuality? = nil

    static func make(gi: Bool, redWall: Bool = true, intensity: Double = 1,
                     toggle: Bool = false, quality: RenderQuality? = nil) -> GIRoomProbe {
        let probe = GIRoomProbe()
        probe.gi = gi
        probe.redWall = redWall
        probe.intensity = intensity
        probe.toggle = toggle
        probe.quality = quality
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 2, 0), radius: 9.5,
                         azimuth: 0, elevation: 0.02, fieldOfView: .pi / 3.2,
                         near: 1, far: 40))
        spotLight(.white, at: Vector3(0, 3.8, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 3, penumbra: 0.4, intensity: 3)
        castShadows()
        if gi { globalIllumination(intensity: intensity) }
        if let quality { globalIlluminationQuality(quality) }
        if toggle { globalIllumination(); noGlobalIllumination() }
        withState { fill(Color(white: 0.9)); translate(0, -0.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(Color(white: 0.9)); translate(0, 4.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(Color(white: 0.9)); translate(0, 2, -4.1); drawBox(width: 8, height: 4.4, depth: 0.2) }
        withState {
            fill(redWall ? Color(hex: 0xd03030) : Color(white: 0.9))
            translate(-4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8)
        }
        withState { fill(Color(white: 0.9)); translate(4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
        withState { fill(Color(white: 0.85)); translate(1.6, 0.7, -1.0); drawSphere(radius: 0.7) }
    }
}

/// The sealed box: the camera inside, a bright point light outside (or inside for the
/// control). RT point shadows make the direct term exact, so anything the interior
/// shows with the light outside would be the probes leaking.
private final class GISealedBoxProbe: Sketch {
    var lightInside = false

    static func make(lightInside: Bool) -> GISealedBoxProbe {
        let probe = GISealedBoxProbe()
        probe.lightInside = lightInside
        return probe
    }

    override var canvasSize: CanvasSize { .square(160) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 1.2, 0), radius: 1.3,
                         azimuth: 0.4, elevation: 0.12, near: 0.05, far: 30))
        pointLight(.white, at: lightInside ? Vector3(0, 2.0, 0) : Vector3(6, 5, 4),
                   intensity: 6)
        castShadows()
        globalIllumination()
        // A sealed room, interior 3.6 x 2.6 x 3.6 around the camera.
        withState { fill(Color(white: 0.9)); translate(0, -0.1, 0); drawBox(width: 4.0, height: 0.2, depth: 4.0) }
        withState { fill(Color(white: 0.9)); translate(0, 2.7, 0); drawBox(width: 4.0, height: 0.2, depth: 4.0) }
        withState { fill(Color(white: 0.9)); translate(0, 1.3, -1.9); drawBox(width: 4.0, height: 2.8, depth: 0.2) }
        withState { fill(Color(white: 0.9)); translate(0, 1.3, 1.9); drawBox(width: 4.0, height: 2.8, depth: 0.2) }
        withState { fill(Color(white: 0.9)); translate(-1.9, 1.3, 0); drawBox(width: 0.2, height: 2.8, depth: 4.0) }
        withState { fill(Color(white: 0.9)); translate(1.9, 1.3, 0); drawBox(width: 0.2, height: 2.8, depth: 4.0) }
    }
}
