import CoreGraphics
import Foundation
import ScreenCaptureKit

/// What a ``ScreenCapture`` should point at: a display, one app's windows, or a
/// single window. A plain value you write in the sketch, so the same line always
/// picks the same thing and the sketch stays the record of what was captured.
///
/// ```swift
/// ScreenCapture(.mainDisplay)                 // the whole screen
/// ScreenCapture(.app("Safari"))               // every window Safari has open
/// ScreenCapture(.window(title: "Untitled"))   // one window, by its title
/// ```
///
/// Names are matched leniently, because that is what makes them worth writing:
/// ``app(_:)`` accepts an application's name *or* its bundle identifier, and
/// ``window(title:app:)`` matches any window whose title contains the text, both
/// ignoring case. Where several windows match, the lowest window id wins, so a
/// run is repeatable rather than depending on stacking order. The exact forms,
/// ``display(_:)`` and ``windowID(_:)``, take the ids that
/// ``ScreenCapture/displays()`` and ``ScreenCapture/windows()`` report, for when
/// a sketch resolves its own target and wants no ambiguity at all.
///
/// A source that names something not on screen yet is not an error: the capture
/// keeps looking, and starts the moment it appears (see ``ScreenCapture/start()``).
public enum ScreenSource: Sendable, Equatable {

    /// The display the menu bar is on.
    case mainDisplay

    /// A display by its system id, as reported by ``ScreenCapture/displays()``.
    case display(CGDirectDisplayID)

    /// Every on-screen window belonging to one application, matched by its name
    /// or its bundle identifier (case-insensitive). The windows are captured
    /// against their display, so they keep their positions and overlap.
    case app(String)

    /// One window, matched by a case-insensitive substring of its title, and
    /// optionally narrowed to an application (again by name or bundle
    /// identifier). A window is captured on its own: it arrives at its own size
    /// with nothing in front of it, even when another window covers it on screen.
    case window(title: String, app: String?)

    /// One window by its id, as reported by ``ScreenCapture/windows()``.
    case windowID(CGWindowID)

    /// A window matched by title alone, in whichever application owns it.
    public static func window(title: String) -> ScreenSource {
        .window(title: title, app: nil)
    }

    /// A short description of what this names, used in the on-canvas waiting
    /// notice ("Waiting for Safari…").
    public var label: String {
        switch self {
        case .mainDisplay:              return "the main display"
        case .display(let id):          return "display \(id)"
        case .app(let name):            return name
        case .window(let title, _):     return title
        case .windowID(let id):         return "window \(id)"
        }
    }
}

// MARK: What is on screen

/// A display that can be captured, one entry from ``ScreenCapture/displays()``.
public struct ScreenDisplay: Sendable, Identifiable, Equatable {
    /// The system display id. Pass it to ``ScreenSource/display(_:)``.
    public let id: CGDirectDisplayID
    /// The display's size in points.
    public let size: CGSize
    /// Whether this is the display the menu bar is on.
    public let isMain: Bool

    /// A one-line label, e.g. `"Display 1 (1680×1050, main)"`.
    public var label: String {
        let dims = "\(Int(size.width))×\(Int(size.height))"
        return isMain ? "Display \(id) (\(dims), main)" : "Display \(id) (\(dims))"
    }
}

/// A window that can be captured, one entry from ``ScreenCapture/windows()``.
public struct ScreenWindow: Sendable, Identifiable, Equatable {
    /// The window id. Pass it to ``ScreenSource/windowID(_:)``.
    public let id: CGWindowID
    /// The window's title, if it has one.
    public let title: String?
    /// The name of the application that owns it.
    public let appName: String?
    /// The bundle identifier of the application that owns it (empty for a
    /// process launched without a bundle, which is what a sketch run from the
    /// terminal is).
    public let bundleIdentifier: String?
    /// The window's frame in screen points.
    public let frame: CGRect

    /// A one-line label, e.g. `"Untitled (TextEdit)"`.
    public var label: String {
        switch (title?.isEmpty == false ? title : nil, appName) {
        case let (t?, a?):  return "\(t) (\(a))"
        case let (t?, nil): return t
        case let (nil, a?): return a
        default:            return "Window \(id)"
        }
    }
}

/// An application whose windows can be captured, one entry from
/// ``ScreenCapture/apps()``.
public struct ScreenApp: Sendable, Identifiable, Equatable {
    /// The process id.
    public let id: pid_t
    /// The application's name.
    public let name: String
    /// The application's bundle identifier (empty for a process launched
    /// without a bundle).
    public let bundleIdentifier: String

    /// A one-line label, e.g. `"Safari (com.apple.Safari)"`.
    public var label: String {
        bundleIdentifier.isEmpty ? name : "\(name) (\(bundleIdentifier))"
    }
}

// MARK: The matching rules

/// The rules a written name is matched by, as pure functions over plain values.
///
/// They are separated from the filter building below because that part cannot be
/// tested: `SCShareableContent` is only ever handed over by the system, so there
/// is no way to stand up a fake screen holding the windows a test wants. Keeping
/// the decisions here (which name matches, which window wins, which display a
/// window is on) means the part a sketch actually depends on is testable with no
/// screen, no stream, and no permission, and the code below is plumbing with no
/// judgement left in it.
enum ScreenMatch {

    /// An application matches a written name if it equals either the name shown
    /// to people or the bundle identifier, ignoring case. Both are offered
    /// because a bundle identifier is the stable handle for a shipping app,
    /// while a process launched from the terminal (a sketch, most of all) has
    /// none at all, so an empty identifier must never match an empty search.
    static func app(name: String, bundleIdentifier: String, matches written: String) -> Bool {
        let needle = written.lowercased()
        guard !needle.isEmpty else { return false }
        return name.lowercased() == needle || bundleIdentifier.lowercased() == needle
    }

    /// A window matches by a case-insensitive substring of its title, so the
    /// text a person can see in the title bar is enough to name it. An empty
    /// search matches nothing, rather than the first window on the screen.
    static func window(title: String?, matches written: String) -> Bool {
        let needle = written.lowercased()
        guard !needle.isEmpty, let title else { return false }
        return title.lowercased().contains(needle)
    }

    /// Which of several matching windows to take: the lowest id, so a repeated
    /// run picks the same window instead of following whatever is frontmost.
    static func preferred<Window>(_ windows: [Window],
                                  id: (Window) -> CGWindowID) -> Window? {
        windows.min { id($0) < id($1) }
    }

    /// Which display a window is on, by the largest overlap of their frames.
    /// Returns `nil` when the window touches none of them.
    static func displayHolding(_ window: CGRect, among displays: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let overlap = area(display.intersection(window))
            guard overlap > 0 else { continue }
            if best == nil || overlap > best!.area { best = (index, overlap) }
        }
        return best?.index
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isInfinite ? 0 : rect.width * rect.height
    }
}

// MARK: Building the filter

/// Turns a ``ScreenSource`` into the filter a stream captures through, against a
/// snapshot of what is currently on screen. Returns `nil` when the source names
/// something that is not there (a window not open yet, a display unplugged),
/// which is a state to wait through rather than an error.
func resolveFilter(_ source: ScreenSource,
                   in content: SCShareableContent,
                   excludingPID excluded: pid_t?) -> SCContentFilter? {
    switch source {
    case .mainDisplay:
        let main = CGMainDisplayID()
        let display = content.displays.first { $0.displayID == main } ?? content.displays.first
        return display.map { displayFilter($0, in: content, excludingPID: excluded) }

    case .display(let id):
        guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        return displayFilter(display, in: content, excludingPID: excluded)

    case .app(let name):
        let apps = content.applications.filter { matches($0, name) }
        guard !apps.isEmpty else { return nil }
        // An app's windows are captured against the display they are on, so take
        // the display holding its first window and fall back to the main one.
        let windows = content.windows
            .filter { window in apps.contains { $0.processID == window.owningApplication?.processID } }
        guard let first = ScreenMatch.preferred(windows, id: \.windowID) else { return nil }
        let displays = content.displays
        let index = ScreenMatch.displayHolding(first.frame, among: displays.map(\.frame))
        guard let display = index.map({ displays[$0] }) ?? displays.first else { return nil }
        return SCContentFilter(display: display, including: apps, exceptingWindows: [])

    case .window(let title, let app):
        let matching = content.windows
            .filter { ScreenMatch.window(title: $0.title, matches: title) }
            .filter { window in
                guard let app else { return true }
                guard let owner = window.owningApplication else { return false }
                return matches(owner, app)
            }
        guard let window = ScreenMatch.preferred(matching, id: \.windowID) else { return nil }
        return SCContentFilter(desktopIndependentWindow: window)

    case .windowID(let id):
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        return SCContentFilter(desktopIndependentWindow: window)
    }
}

/// A whole display, optionally with one process's windows left out of it.
private func displayFilter(_ display: SCDisplay,
                           in content: SCShareableContent,
                           excludingPID excluded: pid_t?) -> SCContentFilter {
    guard let excluded,
          let app = content.applications.first(where: { $0.processID == excluded }) else {
        return SCContentFilter(display: display, excludingWindows: [])
    }
    return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
}

/// `ScreenMatch.app` against the system's own application type.
private func matches(_ app: SCRunningApplication, _ written: String) -> Bool {
    ScreenMatch.app(name: app.applicationName,
                    bundleIdentifier: app.bundleIdentifier,
                    matches: written)
}
