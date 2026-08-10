import CoreGraphics
import Foundation
import Testing
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

/// The probe room: a Cornell-style box whose only light is a spot pool on the floor,
/// with one wall red (or repainted white for the bleed counterfactual).
private final class GIRoomProbe: Sketch {
    var gi = true
    var redWall = true
    var intensity = 1.0
    var toggle = false

    static func make(gi: Bool, redWall: Bool = true, intensity: Double = 1,
                     toggle: Bool = false) -> GIRoomProbe {
        let probe = GIRoomProbe()
        probe.gi = gi
        probe.redWall = redWall
        probe.intensity = intensity
        probe.toggle = toggle
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 2, 0), radius: 9.5,
                         azimuth: 0, elevation: 0.02, fieldOfView: .pi / 3.2,
                         near: 1, far: 40))
        spotLight(.white, at: Vector3(0, 3.8, 0), direction: Vector3(0, -1, 0),
                  angle: .pi / 3, penumbra: 0.4, intensity: 3)
        castShadows()
        if gi { globalIllumination(intensity: intensity) }
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
