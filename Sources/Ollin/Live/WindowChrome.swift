#if os(macOS)
import SwiftUI
import AppKit

// Window chrome shared by the host apps (the live host, the examples gallery):
// the translucent sidebar backing, a hook for window-level configuration, and
// title-bar accessories that dodge the toolbar item's button capsule. All of it
// is macOS host chrome; none of it renders into a sketch or its exports.

/// A translucent vibrancy panel: the native sidebar look (sampling what's behind
/// the window), used as a host sidebar's background.
public struct SidebarVibrancy: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    public func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Runs window-level configuration when the hosting window appears. The
/// explicit home for window side effects, so nothing window-wide hides inside a
/// generic component. Attach with `.background(...)`.
public struct WindowCustomizer: NSViewRepresentable {
    private let configure: @MainActor (NSWindow) -> Void

    public init(configure: @escaping @MainActor (NSWindow) -> Void) {
        self.configure = configure
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView(frame: .zero)
        view.onAttach = configure
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Mounts a SwiftUI view as a leading or trailing title-bar accessory: a real
/// spot in the title bar with no toolbar-item button chrome. The host is
/// invisible (zero-size); attach with `.background(...)`. Idempotent at the
/// window level: one accessory per edge, updated in place. Installation happens
/// on the view's own `viewDidMoveToWindow` (and on every content update once the
/// window exists), so there is no window lookup and nothing to poll.
public struct TitleBarAccessory<Content: View>: NSViewRepresentable {
    private let attribute: NSLayoutConstraint.Attribute
    private let content: Content

    public init(attribute: NSLayoutConstraint.Attribute = .trailing,
                @ViewBuilder content: () -> Content) {
        self.attribute = attribute
        self.content = content()
    }

    private var tag: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(attribute == .leading ? "ollin.titlebar.leading" : "ollin.titlebar.trailing")
    }

    public final class Coordinator {
        var latest = AnyView(EmptyView())
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView(frame: .zero)
        let coordinator = context.coordinator
        let attribute = self.attribute
        let tag = self.tag
        view.onAttach = { window in
            Self.install(coordinator.latest, in: window, attribute: attribute, tag: tag)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.latest = AnyView(content)
        if let window = nsView.window {
            Self.install(context.coordinator.latest, in: window, attribute: attribute, tag: tag)
        }
    }

    @MainActor
    private static func install(_ content: AnyView, in window: NSWindow,
                                attribute: NSLayoutConstraint.Attribute,
                                tag: NSUserInterfaceItemIdentifier) {
        let titleBarHeight = max(28, window.frame.height - window.contentLayoutRect.height)
        if let existing = window.titlebarAccessoryViewControllers
            .compactMap({ $0 as? TitleBarAccessoryVC }).first(where: { $0.tag == tag }) {
            existing.titleBarHeight = titleBarHeight
            existing.update(content)
        } else {
            let accessory = TitleBarAccessoryVC(attribute: attribute, tag: tag)
            accessory.titleBarHeight = titleBarHeight
            accessory.update(content)
            window.addTitlebarAccessoryViewController(accessory)
        }
    }
}

/// Hosts a SwiftUI view as a leading or trailing title-bar accessory. It owns its
/// `NSHostingView` so any view holding the window can update the content in
/// place, keeping it a single instance per edge even if SwiftUI re-creates the
/// representable.
private final class TitleBarAccessoryVC: NSTitlebarAccessoryViewController {
    let tag: NSUserInterfaceItemIdentifier
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    /// Title-bar height, so the content's `maxHeight: .infinity` centers vertically.
    var titleBarHeight: CGFloat = 28 { didSet { resize() } }

    init(attribute: NSLayoutConstraint.Attribute, tag: NSUserInterfaceItemIdentifier) {
        self.tag = tag
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = attribute
        host.identifier = tag
        view = host
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ content: AnyView) {
        host.rootView = content
        resize()
    }

    private func resize() {
        host.setFrameSize(NSSize(width: host.fittingSize.width, height: titleBarHeight))
    }
}

/// A zero-size view that reports when it lands in (or moves between) windows:
/// AppKit's own signal for "the window exists now", replacing any need to poll
/// for it. Shared by the accessory mount and the window customizer above.
private final class WindowAttachmentView: NSView {
    var onAttach: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onAttach?(window) }
    }
}

#endif
