import Testing
@testable import Ollin

/// A blur or glow radius is in pixels, and one under a pixel spreads nothing.
/// Four examples once wrote a share of the canvas there (`radius: 0.012`) and
/// shipped without the glow they asked for, since the bloom only brightened the
/// marks in place. The drawer now says so once, where the sketch's call is, on
/// both roads a filter takes: the whole frame and a layer.
@Suite
struct FilterSpreadNoteTests {

    private func freshDrawer() -> Drawer {
        let drawer = Drawer()
        drawer.beginFrame()
        return drawer
    }

    @Test func aSubPixelBloomOverTheFrameIsNoted() {
        let drawer = freshDrawer()
        drawer.postProcess(.bloom(threshold: 0.7, amount: 0.5, radius: 0.012))
        #expect(drawer.drawerNotes.contains { $0.hasPrefix("bloom(radius: 0.012) spreads less than a pixel") })
    }

    @Test func aSubPixelSpreadOnALayerIsNoted() {
        let drawer = freshDrawer()
        let layer = RenderTarget(width: 64, height: 64, scale: 1, drawer: drawer)
        _ = drawer.recordFilter(.halation(radius: 0.5), of: layer)
        _ = drawer.recordFilter(.gaussianBlur(radius: 0.25), of: layer)
        #expect(drawer.drawerNotes.contains { $0.hasPrefix("halation(radius: 0.5)") })
        #expect(drawer.drawerNotes.contains { $0.hasPrefix("gaussianBlur(radius: 0.25)") })
    }

    /// A radius of a pixel or more says nothing, and neither does zero, which is
    /// how a sketch asks for no spread at all.
    @Test func aRadiusInPixelsOrZeroIsLeftAlone() {
        let drawer = freshDrawer()
        drawer.postProcess(.bloom(radius: 12))
        drawer.postProcess(.gaussianBlur(radius: 1))
        drawer.postProcess(.bloom(radius: 0))
        drawer.postProcess(.invert())
        #expect(drawer.drawerNotes.isEmpty)
    }
}
