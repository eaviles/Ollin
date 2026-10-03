@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// The persistent layers as the base of a combine: `Feedback`, `Accumulator`, and
/// `SimField` each forward `combined(with:_:)` to the layer they show, beside
/// `filtered(_:)`. Before the forwarders a sketch reached a combine through a filter
/// that changed nothing (`.exposure(stops: 0)`), so each check draws both ways and
/// asks for the same pixels, and the planted case asks that the base actually
/// matters (a combine that ignored it would match its twin trivially).
@Suite
@MainActor
struct PersistentLayerCombineTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachCombineEqualsTheHopItReplaces() throws {
        for kind in CombineProbe.Kind.allCases {
            let direct = try OllinApp.image(of: CombineProbe(kind, hop: false), frame: 4)
            let hopped = try OllinApp.image(of: CombineProbe(kind, hop: true), frame: 4)
            let (differing, worst) = ImageSourceTests.compare(direct, hopped)
            #expect(differing == 0, "\(kind): \(differing) pixels differ, by up to \(worst) levels")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theBaseIsWhatTheCombineMasks() throws {
        for kind in CombineProbe.Kind.allCases {
            let shown = try OllinApp.image(of: CombineProbe(kind, hop: false), frame: 4)
            let blank = try OllinApp.image(of: CombineProbe(kind, hop: false, blankBase: true), frame: 4)
            let (differing, _) = ImageSourceTests.compare(shown, blank)
            #expect(differing > 1000, "\(kind): the masked base changed only \(differing) pixels")
        }
    }
}

/// A persistent layer of moving marks, masked by a disc in a second layer, through
/// the forwarder or through the do-nothing filter that stood in for it.
private final class CombineProbe: Sketch {
    enum Kind: CaseIterable { case feedback, accumulator, simField }
    var kind: Kind = .feedback
    var hop = false
    var blankBase = false
    var trails: Feedback!
    var light: Accumulator!
    var field: SimField!

    convenience init(_ kind: Kind, hop: Bool, blankBase: Bool = false) {
        self.init()
        self.kind = kind
        self.hop = hop
        self.blankBase = blankBase
    }

    override var canvasSize: CanvasSize { .square(160) }

    override func setup() {
        trails = makeFeedback()
        light = makeAccumulator()
        field = makeSimField(.selfWarp())
    }

    override func draw() {
        background(.black)
        let mask = makeRenderTarget()
        withTarget(mask) {
            background(.clear)
            noStroke()
            fill(.white)
            drawCircle(80, 80, 50)
        }
        let combine = Combine.mask(channel: .alpha)
        let result: RenderTarget
        switch kind {
        case .feedback:
            withFeedback(trails) { previous in
                drawImage(previous, 0, 0)
                marks()
            }
            result = hop ? trails.filtered(.exposure(stops: 0)).combined(with: mask, combine)
                         : trails.combined(with: mask, combine)
        case .accumulator:
            withAccumulator(light) { marks() }
            result = hop ? light.filtered(.exposure(stops: 0)).combined(with: mask, combine)
                         : light.combined(with: mask, combine)
        case .simField:
            withField(field) { marks() }
            result = hop ? field.filtered(.exposure(stops: 0)).combined(with: mask, combine)
                         : field.combined(with: mask, combine)
        }
        drawImage(result.image, 0, 0)
    }

    /// A ground and a mark that moves a little each frame, or nothing at all for
    /// the blank base.
    private func marks() {
        guard !blankBase else { return }
        background(Color(red: 0.2, green: 0.3, blue: 0.6))
        noStroke()
        fill(.orange)
        drawRect(20 + Double(frameCount) * 6, 30, 50, 90)
    }
}
