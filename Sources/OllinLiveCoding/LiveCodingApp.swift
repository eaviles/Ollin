import SwiftUI
import Ollin
import OllinRuntime

// OllinLiveCoding: the live-coding performance host.
//
//   swift run OllinLiveCoding [path/to/Sketch.swift]
//
// One window: the running sketch fills the stage and the code rides over it
// as translucent text. ⌘↩ recompiles the editor buffer and hot-swaps the
// sketch while the old one keeps drawing; the clock carries across the swap
// so motion never jumps mid-set (⌘⇧↩ evaluates fresh). Evaluation never
// saves; the .swift file stays the artifact, written only by ⌘S.
@main
struct LiveCodingApp: App {
    @NSApplicationDelegateAdaptor(LiveCodingAppDelegate.self) private var delegate
    @State private var session: PerformanceSession

    init() {
        // Stop AppKit from reading a sketch-path argument as a file-open
        // request, which suppresses the automatic initial window for a
        // bundleless host launched with an argument. Registered in `init` so
        // it lands before AppKit parses the arguments.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])

        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: status lines show immediately

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--selftest") { SelfTest.run() }        // headless; exits
        if arguments.contains("--sessiontest") { SessionTest.run() }  // headless; exits

        // A path argument opens that sketch; none starts an untitled buffer
        // from the template.
        var fileURL: URL?
        if let pathArg = arguments.first(where: { !$0.hasPrefix("-") }) {
            let path = (pathArg as NSString).isAbsolutePath
                ? pathArg
                : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(pathArg)
            guard FileManager.default.fileExists(atPath: path) else {
                FileHandle.standardError.write(
                    Data("OllinLiveCoding: file not found: \(path)\n".utf8))
                exit(2)
            }
            fileURL = URL(fileURLWithPath: path)
        }

        let session = PerformanceSession(fileURL: fileURL)
        _session = State(initialValue: session)
        ActivePerformance.session = session
    }

    var body: some SwiftUI.Scene {
        // A `Window` (not `WindowGroup`): one performance, one window. Unlike
        // the sibling hosts there is no `.windowResizability(.contentSize)`;
        // the stage flexes with the window (and fullscreen), and the letterbox
        // keeps the canvas true.
        Window("OllinLiveCoding", id: "main") {
            LiveCodingRootView(session: session)
        }
        .defaultSize(width: OllinApp.defaultWindowSize.width,
                     height: OllinApp.defaultWindowSize.height)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            PerformanceFileCommands()
            SketchCommands()
            PerformanceViewCommands()
            OllinCameraCommands()
        }
    }
}

/// The one running session, reachable from menu `Commands` structs (which
/// can't be handed instance state). Weak: the `App`'s `@State` owns it.
@MainActor
enum ActivePerformance {
    static weak var session: PerformanceSession?
}

/// Activation + lifecycle for the bundleless `swift run` executable.
final class LiveCodingAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Sketch ▸ Evaluate (⌘↩) / Evaluate Fresh (⌘⇧↩), the instrument's action.
private struct SketchCommands: Commands {
    var body: some Commands {
        CommandMenu("Sketch") {
            Button("Evaluate") {
                ActivePerformance.session?.evaluate()
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Evaluate Fresh") {
                ActivePerformance.session?.evaluate(fresh: true)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
        }
    }
}

/// File ▸ New / Open… / Save / Save As…, replacing the defaults (there is no
/// document architecture behind this window; the session is it).
private struct PerformanceFileCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                ActivePerformance.session?.newBuffer()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open…") {
                ActivePerformance.session?.openDocument()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                ActivePerformance.session?.saveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save As…") {
                ActivePerformance.session?.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}

/// View ▸ inspector / code visibility / code size / backdrop strength. ⌘0–⌘8
/// stay clear: they belong to the Camera menu.
private struct PerformanceViewCommands: Commands {
    @AppStorage(LiveCodingRootView.sidebarShownKey) private var sidebarShown = false
    @AppStorage(LiveCodingRootView.codeHiddenKey) private var codeHidden = false
    @AppStorage(LiveCodingRootView.fontSizeKey) private var fontSize = 15.0
    @AppStorage(LiveCodingRootView.backdropKey) private var backdrop = 0.55

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Show Inspector", isOn: $sidebarShown)
                .keyboardShortcut("/", modifiers: .command)
            Toggle("Hide Code", isOn: $codeHidden)
                .keyboardShortcut("h", modifiers: [.control, .shift])
            Divider()
            Button("Bigger Code") { fontSize = min(fontSize + 1, 32) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Code") { fontSize = max(fontSize - 1, 9) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Picker("Code Backdrop", selection: $backdrop) {
                Text("Subtle").tag(0.3)
                Text("Medium").tag(0.55)
                Text("Strong").tag(0.8)
            }
        }
    }
}
