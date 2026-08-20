@testable import Ollin
import Testing
import CoreGraphics

/// Behavioral probes for the lens flare: the invariants a mean-diff snapshot
/// cannot pin. The flare has to add light at all, it has to follow how much of
/// its source the camera can *see* rather than switching off, stopping the iris
/// down has to shrink the ghosts, and a frame that does not ask for one has to
/// come out untouched.
@Suite
@MainActor
struct LensFlareRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// How much light the flare adds, as the mean rise over the same frame drawn
    /// without one. Reading the *difference* is what makes the occluder cases
    /// comparable: whatever the occluder does to the scene cancels, and what is
    /// left is the flare alone.
    private func flareAdded(_ occluder: FlareProbe.Occluder,
                            fStop: Double = 4.5) throws -> Double {
        let on = try #require(OllinApp.image(of: FlareProbe.make(occluder: occluder,
                                                                flare: true, fStop: fStop),
                                             frame: 1))
        let off = try #require(OllinApp.image(of: FlareProbe.make(occluder: occluder,
                                                                 flare: false, fStop: fStop),
                                              frame: 1))
        let a = pixels(of: on), b = pixels(of: off)
        var sum = 0.0
        for i in stride(from: 0, to: a.count, by: 4) {
            for c in 0..<3 { sum += max(0, Double(a[i + c]) - Double(b[i + c])) }
        }
        return sum / Double(a.count / 4 * 3)
    }

    /// How much of the frame the flare covers brightly, which is what the iris
    /// changes: stopping down shrinks every ghost together.
    private func flareArea(fStop: Double) throws -> Int {
        let on = try #require(OllinApp.image(of: FlareProbe.make(occluder: .none,
                                                                flare: true, fStop: fStop),
                                             frame: 1))
        let off = try #require(OllinApp.image(of: FlareProbe.make(occluder: .none,
                                                                 flare: false, fStop: fStop),
                                              frame: 1))
        let a = pixels(of: on), b = pixels(of: off)
        var covered = 0
        for i in stride(from: 0, to: a.count, by: 4) where Double(a[i + 1]) - Double(b[i + 1]) > 6 {
            covered += 1
        }
        return covered
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFlareAddsLightToTheFrame() throws {
        let added = try flareAdded(.none)
        #expect(added > 4, "the flare should be plainly there: \(added)")
    }

    /// The design rule that separates a flare from a sticker: its strength
    /// follows the source's *visible* area, so an occluder fades it rather than
    /// switching it off. Half a source gives roughly half a flare.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anOccluderFadesTheFlareRatherThanEndingIt() throws {
        let clear = try flareAdded(.none)
        let half = try flareAdded(.half)
        let hidden = try flareAdded(.full)
        #expect(clear > 4, "nothing to fade: \(clear)")
        #expect(half < clear * 0.85, "a covered source should dim the flare: \(half) of \(clear)")
        #expect(half > clear * 0.15, "it should fade, not switch off: \(half) of \(clear)")
        #expect(hidden < clear * 0.1, "a hidden source should leave almost none: \(hidden)")
    }

    /// A ghost is a picture of the opening the light came through, so closing
    /// the iris makes every one of them smaller.
    @Test(.enabled(if: Snapshot.hasMetal))
    func stoppingDownShrinksTheGhosts() throws {
        let wide = try flareArea(fStop: 2.2)
        let tight = try flareArea(fStop: 16)
        #expect(wide > 0, "no ghosts to shrink")
        #expect(tight < wide * 3 / 4, "stopping down should shrink them: \(tight) of \(wide)")
    }

    /// A sketch that does not ask for a flare pays nothing and renders exactly
    /// as it did before there was one, and turning it back off is the same as
    /// never turning it on.
    @Test(.enabled(if: Snapshot.hasMetal))
    func askingForNoFlareLeavesTheFrameUntouched() throws {
        let never = try #require(OllinApp.image(of: FlareProbe.make(occluder: .none, flare: false),
                                                frame: 1))
        let cancelled = try #require(OllinApp.image(of: FlareProbe.make(occluder: .none,
                                                                       flare: true, cancel: true),
                                                    frame: 1))
        #expect(pixels(of: never) == pixels(of: cancelled))
    }
}

/// A fixed scene with one lamp, drawn with or without a flare and with the lamp
/// clear of, half behind, or fully behind a slab. No clock, so every frame is
/// the same picture.
private final class FlareProbe: Sketch {

    enum Occluder { case none, half, full }

    var occluder: Occluder = .none
    var wantsFlare = false
    var cancels = false
    var fStop = 4.5

    static func make(occluder: Occluder, flare: Bool,
                     cancel: Bool = false, fStop: Double = 4.5) -> FlareProbe {
        let probe = FlareProbe()
        probe.occluder = occluder
        probe.wantsFlare = flare
        probe.cancels = cancel
        probe.fStop = fStop
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    /// Where the lamp sits, and the eye it is seen from. The occluder's edge is
    /// placed on the line between them, so half of the lamp's disc is covered.
    private let lamp = Vector3(1.0, 2.1, -2)
    private let eye = Vector3(0, 1.5, 7)

    override func draw() {
        background(Color(white: 0.03))
        perspective(eye: eye, target: Vector3(0, 1.5, 0),
                    fieldOfView: .pi / 3.2, near: 0.2, far: 60)
        ambientLight(Color(white: 0.05))
        pointLight(Color(hex: 0xFFF2D6), at: lamp, intensity: 14)
        if wantsFlare {
            lensFlare(strength: 1, lens: Lens.heliar.multicoated().stopped(to: fStop))
        }
        if cancels { noLensFlare() }

        fill(.white)
        matcap(bulb)
        withState {
            translate(lamp)
            drawSphere(radius: 0.16)
        }
        matcap(nil)

        fill(Color(white: 0.28))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 24, height: 0.1, depth: 24)
        }
        // The slab sits halfway to the lamp, with its near edge on the eye-to-lamp
        // line for the half case and a little past it for the full one.
        if occluder != .none {
            let middle = eye + (lamp - eye) * 0.5
            let shift = occluder == .half ? 2.0 : 1.2
            fill(Color(white: 0.35))
            withState {
                translate(middle.x + shift, middle.y, middle.z)
                drawBox(width: 4, height: 3, depth: 0.4)
            }
        }
    }

    private let bulb = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))
}
