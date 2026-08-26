import Foundation

/// What the generator makes: a loose sketch file, a folder that builds and runs
/// on its own, and later the platform bundles a sketch can be wrapped in.
///
/// A kind is *data*, not a code path. A kind that is not ready yet still lives
/// in this catalog carrying the reason it is waiting, so both faces of the
/// generator can name it and say what it needs, and so opening one later is a
/// new emitter plus a changed `availability` rather than a redesign.
public struct ProjectKind: Sendable, Hashable, Identifiable {
    /// Stable slug used on the command line (`--kind mac-sketch`).
    public let id: String
    /// Short name for a menu or a list row.
    public let title: String
    /// One sentence on what this kind produces.
    public let summary: String
    /// Whether the generator can emit it today, and if not, what it waits on.
    public let availability: Availability
    /// Whether a sketch of this kind runs itself.
    ///
    /// A windowed program does. A plug-in does not, because the program that
    /// loads it has an entry point already and a second one is at best dead
    /// weight; and neither does a piece whose program is a wrapper file beside
    /// the sketch (the wallpaper and menu-bar kinds), where a second `@main`
    /// would refuse to build. It is the one thing that changes the sketch file
    /// rather than the files around it, which is why it rides the kind instead
    /// of being asked about later.
    public let carriesEntryPoint: Bool
    /// Whether a sketch of this kind is drawn onto whatever it is put on, rather
    /// than into a window sized to the canvas.
    ///
    /// A screen saver and the wallpaper take a whole display, and the menu-bar
    /// strip is the same fact at a smaller size. The sketch is written to suit:
    /// it declares its window mode as `.resizable`, so `width` and `height` are
    /// the surface's. Data rather than a code path, because it is the same fact
    /// for every kind that has no window of its own.
    public let fillsTheDisplay: Bool

    public enum Availability: Sendable, Hashable {
        case available
        /// Named so a caller can print exactly what is missing rather than a
        /// bare "not supported".
        case waiting(on: String)
    }

    public var isAvailable: Bool { availability == .available }

    /// The reason this kind cannot be generated yet, or nil when it can.
    public var waitingOn: String? {
        if case .waiting(let reason) = availability { return reason }
        return nil
    }

    public init(id: String, title: String, summary: String, availability: Availability,
                carriesEntryPoint: Bool = true, fillsTheDisplay: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.availability = availability
        self.carriesEntryPoint = carriesEntryPoint
        self.fillsTheDisplay = fillsTheDisplay
    }
}

extension ProjectKind {
    /// One `.swift` file, run by the `ollin` command or directly when it carries
    /// the interpreter line. The smallest thing that is a whole sketch.
    public static let singleFile = ProjectKind(
        id: "single-file",
        title: "Single file",
        summary: "One .swift file, no package and no project. Run it with `ollin`, edit and save to hot-reload.",
        availability: .available
    )

    /// A folder with its own manifest, sources, and assets that `swift run`
    /// builds and runs. The form a piece grows into once it has assets or more
    /// than one file.
    public static let macSketch = ProjectKind(
        id: "mac-sketch",
        title: "Mac sketch",
        summary: "A folder that builds and runs on its own, with room for assets, shaders, and more than one file.",
        availability: .available
    )

    /// A finished piece, wrapped as a double-clickable app.
    ///
    /// The package is the mac sketch's; what this kind adds is the wrapper: a
    /// script that puts the `.app` folder around the built binary, renders the
    /// sketch's own frame into the icon, and signs the result so a machine
    /// that has never seen the toolchain can run it.
    public static let macApp = ProjectKind(
        id: "mac-app",
        title: "Mac app",
        summary: "A double-clickable .app built around the sketch, signed so it can be handed to a Mac without the toolchain.",
        availability: .available
    )

    /// A sketch added to the Swift package the chosen folder already sits in,
    /// rather than a package of its own. A folder of sketches is usually one
    /// package with a target each, so this is the right answer whenever there
    /// is a manifest above the destination.
    public static let inPackage = ProjectKind(
        id: "in-package",
        title: "Add to this package",
        summary: "A sketch folder plus one target in the Package.swift already above it, so the framework builds once for all of them.",
        availability: .available
    )

    /// A library other people's sketches import, rather than a sketch of your
    /// own: a package that depends on Ollin and adds to it.
    ///
    /// The mechanics are free, since any package that depends on the framework
    /// is already a working extension. What this kind supplies is the
    /// convention: the `ollinx-` name, the layout, and a worked starter on one
    /// of the seams the framework actually opens.
    public static let extensionPackage = ProjectKind(
        id: "extension",
        title: "Extension package",
        summary: "A library that adds to Ollin for other people's sketches to import, named and laid out by the shared convention.",
        availability: .available
    )

    public static let iOSApp = ProjectKind(
        id: "ios-app",
        title: "iPhone and iPad app",
        summary: "A sketch wrapped as an app for the phone and the tablet, with touch and the device sensors as input.",
        availability: .waiting(on: "the iOS platform leg: the framework declares macOS only, and the view layer's AppKit seam has no UIKit twin yet")
    )

    public static let visionOSApp = ProjectKind(
        id: "visionos-app",
        title: "Vision app",
        summary: "An immersive sketch, rendered through the headset's own per-frame loop rather than a window.",
        availability: .waiting(on: "the visionOS leg: immersive rendering drives a different render loop, which needs the per-frame seam and the iOS target first")
    )

    public static let screenSaver = ProjectKind(
        id: "screen-saver",
        title: "Screen saver",
        summary: "A sketch that runs as the machine's screen saver, so the piece lives in the system rather than a window.",
        availability: .available,
        carriesEntryPoint: false,
        fillsTheDisplay: true
    )

    /// A sketch running as the desktop wallpaper: one window per display, at
    /// desktop level, behind the icons.
    public static let wallpaper = ProjectKind(
        id: "wallpaper",
        title: "Wallpaper",
        summary: "A sketch that runs as the desktop wallpaper, drawn across every display behind the icons.",
        availability: .available,
        carriesEntryPoint: false,
        fillsTheDisplay: true
    )

    /// A sketch running as a small live strip among the menu bar's status
    /// items, on screen for the whole working day.
    public static let menuBar = ProjectKind(
        id: "menu-bar",
        title: "Menu bar piece",
        summary: "A sketch that runs as a small live strip in the menu bar, beside the clock all day.",
        availability: .available,
        carriesEntryPoint: false,
        fillsTheDisplay: true
    )

    public static let arEffect = ProjectKind(
        id: "ar-effect",
        title: "AR effect",
        summary: "A camera effect anchored to a face, a surface, or a tracked image, with the tracking handed to the sketch.",
        availability: .waiting(on: "AR mode: it layers on the iOS target and the 3D camera path, and needs a device to verify")
    )

    /// Every kind the generator knows about, ready or not, in the order a menu
    /// should show them.
    public static let all: [ProjectKind] = [
        .singleFile, .macSketch, .macApp, .inPackage, .extensionPackage,
        .iOSApp, .visionOSApp, .screenSaver, .wallpaper, .menuBar, .arEffect,
    ]

    /// The kinds that can be generated today.
    public static var available: [ProjectKind] { all.filter(\.isAvailable) }

    /// Look a kind up by its slug.
    public static func named(_ id: String) -> ProjectKind? {
        all.first { $0.id == id }
    }
}
