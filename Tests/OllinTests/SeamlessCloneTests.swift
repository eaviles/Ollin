@testable import Ollin
import Testing
import CoreGraphics

/// Render checks on the `.seamlessClone` combine. These are theorems rather than
/// tastes, which is what makes them worth measuring: with the values around a
/// patch's rim all equal, the field that settles between them is that same value
/// everywhere, so the clone has to hand the layer underneath straight back. Two
/// things follow from it and are checked here too. The patch's own flat color must
/// leave no trace whatever it was, and the result must not depend on how far the
/// middle of the patch is from its rim.
///
/// Each is a case that broke while this was written. The rim-value test caught the
/// pyramid's intermediates overflowing half float; the distance test caught the
/// weight underflowing below the normalize's floor, which put a speckled blob of
/// raw patch color in the one place the answer should be smoothest.
@Suite
@MainActor
struct SeamlessCloneTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The largest per-channel difference between two renders, over the disc only.
    /// The present pass dithers, so one honest answer straddles two 8-bit levels and
    /// a difference of 1 is the floor rather than a discrepancy.
    private func worstInsideDisc(_ a: CGImage, _ b: CGImage, radius: Int) -> Int {
        let (da, db) = (pixels(of: a), pixels(of: b))
        let w = a.width, h = a.height
        var worst = 0
        for y in 0 ..< h {
            for x in 0 ..< w {
                let dx = x - w / 2, dy = y - h / 2
                guard dx * dx + dy * dy < radius * radius else { continue }
                let i = (y * w + x) * 4
                for c in 0 ..< 3 { worst = max(worst, abs(Int(da[i + c]) - Int(db[i + c]))) }
            }
        }
        return worst
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatBackdropComesBackUnchanged() throws {
        let cloned = try #require(OllinApp.image(of: ClonesProbe.make(patch: 0.95), frame: 0))
        let plain = try #require(OllinApp.image(of: ClonesProbe.make(patch: nil), frame: 0))
        let worst = worstInsideDisc(cloned, plain, radius: 140)
        #expect(worst <= 2, "the backdrop's own color came back \(worst)/255 off under the patch")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func thePatchesOwnColorLeavesNoTrace() throws {
        let dark = try #require(OllinApp.image(of: ClonesProbe.make(patch: 0.05), frame: 0))
        let light = try #require(OllinApp.image(of: ClonesProbe.make(patch: 0.95), frame: 0))
        let worst = worstInsideDisc(dark, light, radius: 140)
        #expect(worst <= 2, "two patches 0.9 apart in gray cloned \(worst)/255 differently")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theMiddleOfAWidePatchIsAsRightAsTheEdge() throws {
        // A wide patch puts its middle many levels of the pyramid away from the only
        // values it is held to. That distance is what the solver has to survive.
        let cloned = try #require(OllinApp.image(of: ClonesProbe.make(patch: 0.95, radius: 240),
                                                 frame: 0))
        let plain = try #require(OllinApp.image(of: ClonesProbe.make(patch: nil), frame: 0))
        let worst = worstInsideDisc(cloned, plain, radius: 230)
        #expect(worst <= 2, "deep inside a wide patch the answer was \(worst)/255 off")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anAmountOfZeroLeavesTheSeamIn() throws {
        // The before picture has to actually differ, or nothing above proves anything.
        let seamless = try #require(OllinApp.image(of: ClonesProbe.make(patch: 0.95), frame: 0))
        let pasted = try #require(OllinApp.image(of: ClonesProbe.make(patch: 0.95, amount: 0),
                                                 frame: 0))
        let worst = worstInsideDisc(seamless, pasted, radius: 140)
        #expect(worst > 60, "a plain paste differed from a seamless one by only \(worst)/255")
    }

    @Test func theParametersAreHeldToTheirRange() {
        guard case let .seamlessClone(amount, threshold) =
                Combine.seamlessClone(amount: 4, threshold: -1).kind else {
            Issue.record("expected a seamlessClone"); return
        }
        #expect(amount == 1)
        #expect(threshold == 0.01)
    }
}

/// A flat backdrop with a flat disc cloned onto it. Flat on purpose: a field held
/// to one value all around its rim settles to that value throughout, so the right
/// answer is known exactly and does not depend on the color space the solve runs in.
private final class ClonesProbe: Sketch {
    var patchGray: Double? = 0.95
    var discRadius: Double = 150
    var amount: Double = 1

    static func make(patch: Double?, radius: Double = 150, amount: Double = 1) -> ClonesProbe {
        let probe = ClonesProbe()
        probe.patchGray = patch
        probe.discRadius = radius
        probe.amount = amount
        return probe
    }

    override var canvasSize: CanvasSize { .square(512) }

    override func draw() {
        background(.black)
        let backdrop = makeRenderTarget()
        withTarget(backdrop) { background(Color(red: 0.25, green: 0.55, blue: 0.40)) }
        guard let gray = patchGray else { drawImage(backdrop.image, 0, 0); return }
        let patch = makeRenderTarget()
        withTarget(patch) {
            noStroke()
            fill(Color(red: gray, green: gray, blue: gray))
            drawCircle(256, 256, discRadius)
        }
        drawImage(backdrop.combined(with: patch, .seamlessClone(amount: amount)).image, 0, 0)
    }
}
