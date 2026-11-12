#if os(macOS)
import AppKit
import SwiftUI

/// Where the system's Colors panel goes when a color row opens it. The panel
/// is one shared window that comes back wherever it was last left, which can
/// be on top of the inspector whose row opened it, covering the swatch being
/// edited and the rows around it. This is the rule that moves it aside.
package enum ColorPanelPlacement {
    /// The space left between the panel and what it stands beside.
    package static let gap: CGFloat = 12

    /// The origin to move `panel` to so it leaves `column` in view, or `nil`
    /// where it already does (a place the user chose stands). All four
    /// rectangles are in screen coordinates: the panel's frame, the
    /// inspector's column, the window that holds the column, and the
    /// screen's usable area.
    ///
    /// The places tried, first fit wins: outside the window on the column's
    /// side, where the panel covers nothing and sits next to the row;
    /// outside the window on the far side, where it still covers nothing;
    /// then inside the window against the column's inner edge, over the
    /// canvas. When the screen has room for none of them whole, the last is
    /// used and pushed back onto the screen. The panel keeps its height on
    /// the screen, moved only as far as it takes to be wholly visible.
    package static func origin(panel: CGRect, column: CGRect, window: CGRect, screen: CGRect) -> CGPoint? {
        guard panel.intersects(column) else { return nil }
        let width = panel.width
        let columnIsRight = column.midX >= window.midX
        let outsideRight = window.maxX + gap
        let outsideLeft = window.minX - gap - width
        let beside = columnIsRight ? column.minX - gap - width : column.maxX + gap
        let candidates = columnIsRight ? [outsideRight, outsideLeft, beside] : [outsideLeft, outsideRight, beside]
        let fits = candidates.first { $0 >= screen.minX && $0 + width <= screen.maxX }
        let x = fits ?? min(max(beside, screen.minX), max(screen.minX, screen.maxX - width))
        let y = min(max(panel.minY, screen.minY), max(screen.minY, screen.maxY - panel.height))
        return CGPoint(x: x, y: y)
    }
}

/// Watches for the Colors panel coming up and moves it off any parameters
/// list it lands on. One per process, since the panel is.
@MainActor
package final class ColorPanelPlacer {
    package static let shared = ColorPanelPlacer()

    private final class Anchor {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var anchors: [Anchor] = []
    private var observer: NSObjectProtocol?
    private var wasVisible = false

    /// How many times the panel has been moved aside, for a test to read.
    package private(set) var placements = 0

    /// Keep the panel off the column `view` stands in, for as long as the
    /// view lives.
    package func watch(_ view: NSView) {
        anchors.removeAll { $0.view == nil }
        guard !anchors.contains(where: { $0.view === view }) else { return }
        anchors.append(Anchor(view))
        guard observer == nil else { return }
        // Posted after every event the application handles, so the panel is
        // moved in the same pass as the click that opened it, before it is
        // drawn where it was. The check is two property reads.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
    }

    /// Move the panel if it has just come up over a watched column. Nothing
    /// is done while it stays up: once it is showing, where it stands is the
    /// user's to choose.
    package func check() {
        let isVisible = NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
        defer { wasVisible = isVisible }
        guard isVisible, !wasVisible else { return }
        let panel = NSColorPanel.shared
        for anchor in anchors {
            guard let view = anchor.view, let window = view.window, window !== panel, window.isVisible,
                  let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { continue }
            let column = Self.column(of: view, in: window)
            guard let origin = ColorPanelPlacement.origin(panel: panel.frame, column: column,
                                                          window: window.frame, screen: screen) else { continue }
            panel.setFrameOrigin(origin)
            placements += 1
            return
        }
    }

    /// The column a list stands in, on the screen: as wide as the list and
    /// as tall as its window, since a list scrolls and the column is what
    /// the eye reads as the inspector.
    package static func column(of view: NSView, in window: NSWindow) -> CGRect {
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        return CGRect(x: frame.minX, y: window.frame.minY, width: frame.width, height: window.frame.height)
    }
}

/// A view with nothing in it, set behind the parameters list so the placer
/// knows where the list's column is.
struct ColorPanelAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        ColorPanelPlacer.shared.watch(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
