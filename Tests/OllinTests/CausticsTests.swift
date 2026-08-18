@testable import Ollin
import Testing
import CoreGraphics

/// Behavioral probes for the caustics chain (`caustics()`): the invariants a mean-diff
/// snapshot can't pin. The opt-in must be *inert without a casting material* (byte-equal
/// to the same frame without the call), a glass lens must land real light inside its own
/// shadow, and a tinted lens must land light of its own color. All ray-tracing-gated:
/// on a non-tracing device `caustics()` is a documented no-op and there is nothing to
/// probe. The comparisons are on/off pairs of one fixed frame, so the per-pixel
/// difference isolates exactly what the photons added.
@Suite
@MainActor
struct CausticRenderProbes {

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

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func inertWithoutACastingMaterial() throws {
        // caustics() with only matte surfaces in the frame must not encode anything:
        // the frame renders byte-identical to the same frame without the call (the
        // whole chain is gated on a transmitting or mirror-polished material existing).
        let with = try #require(OllinApp.image(of: CausticProbe.make(kind: .matteOn), frame: 1))
        let without = try #require(OllinApp.image(of: CausticProbe.make(kind: .matteOff), frame: 1))
        #expect(pixels(of: with) == pixels(of: without))
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aLensLandsLightInsideItsOwnShadow() throws {
        // A hovering glass sphere with castShadows() on: direct light cannot reach
        // the floor under it, so with caustics off the patch is plain shadow. The
        // photons refracted through the lens must brighten that patch, and must not
        // touch a far corner the lens never focuses onto.
        let on = try #require(OllinApp.image(of: CausticProbe.make(kind: .lensOn), frame: 1))
        let off = try #require(OllinApp.image(of: CausticProbe.make(kind: .lensOff), frame: 1))
        let dOn = pixels(of: on), dOff = pixels(of: off)
        func luma(_ d: [UInt8], x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
            mean(d, width: on.width, height: on.height, channel: 1, x: x, y: y)
        }
        let spotOn = luma(dOn, x: 0.40...0.60, y: 0.55...0.75)
        let spotOff = luma(dOff, x: 0.40...0.60, y: 0.55...0.75)
        #expect(spotOn - spotOff > 10,
                "expected the focus patch brighter with caustics: on \(spotOn), off \(spotOff)")
        let cornerOn = luma(dOn, x: 0.02...0.12, y: 0.02...0.12)
        let cornerOff = luma(dOff, x: 0.02...0.12, y: 0.02...0.12)
        #expect(abs(cornerOn - cornerOff) < 3,
                "expected the far corner untouched: on \(cornerOn), off \(cornerOff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aTintedLensLandsLightOfItsOwnColor() throws {
        // The same lens in absorbing green glass: what the photons add to the focus
        // patch must lean green (the Beer-Lambert tint rides the photon), where the
        // clear lens's addition is neutral.
        let green = try #require(OllinApp.image(of: CausticProbe.make(kind: .greenLensOn), frame: 1))
        let off = try #require(OllinApp.image(of: CausticProbe.make(kind: .greenLensOff), frame: 1))
        let dG = pixels(of: green), dOff = pixels(of: off)
        func channelMean(_ d: [UInt8], _ c: Int) -> Double {
            mean(d, width: green.width, height: green.height, channel: c,
                 x: 0.40...0.60, y: 0.55...0.75)
        }
        let addedGreen = channelMean(dG, 1) - mean(dOff, width: off.width, height: off.height,
                                                   channel: 1, x: 0.40...0.60, y: 0.55...0.75)
        let addedRed = channelMean(dG, 0) - mean(dOff, width: off.width, height: off.height,
                                                 channel: 0, x: 0.40...0.60, y: 0.55...0.75)
        #expect(addedGreen > 6, "expected a green caustic: added green \(addedGreen)")
        #expect(addedGreen - addedRed > 3,
                "expected the addition to lean green: green \(addedGreen), red \(addedRed)")
    }
}

/// The probe scene, one variant per case: a fixed steep camera over a matte floor,
/// a sun almost straight down, and a hovering ball lens whose focal point lands on
/// the floor near the frame's lower center.
private final class CausticProbe: Sketch {
    enum Kind {
        case matteOn, matteOff            // no casting material: must match exactly
        case lensOn, lensOff
        case greenLensOn, greenLensOff
    }
    var kind: Kind = .lensOn

    static func make(kind: Kind) -> CausticProbe {
        let probe = CausticProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.05))
        perspective(eye: Vector3(0, 5.2, 3.4), target: Vector3(0, 0, 0.3),
                    fieldOfView: .pi / 3.4, near: 1, far: 30)
        directionalLight(.white, direction: Vector3(-0.05, -1, -0.02), intensity: 2)
        castShadows()
        switch kind {
        case .matteOn, .matteOff:
            if kind == .matteOn { caustics() }
            withState {
                material(.dielectric(roughness: 0.7))
                fill(Color(white: 0.6))
                translate(0, 1.4, 0.3)
                drawSphere(radius: 1.0)
            }
        case .lensOn, .lensOff:
            if kind == .lensOn { caustics() }
            lens(clear: true)
        case .greenLensOn, .greenLensOff:
            if kind == .greenLensOn { caustics() }
            lens(clear: false)
        }
        withState {
            material(.dielectric(roughness: 0.85))
            fill(Color(white: 0.55))
            translate(0, -0.5, 0)
            drawBox(width: 18, height: 1.0, depth: 14)
        }
    }

    private func lens(clear: Bool) {
        withState {
            if clear {
                material(.glass(thickness: 2.0))
            } else {
                material(.glass(thickness: 2.0,
                                attenuationColor: Color(hex: 0x2e8f5b),
                                attenuationDistance: 1.2))
            }
            fill(.white)
            translate(0, 1.45, 0.3)
            drawSphere(radius: 1.0)
        }
    }
}
