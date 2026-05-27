import Foundation
import AppKit
import Ollin
import OllinRuntime

/// Owns the running sketch and reacts to file changes: it watches the sketch's
/// folder, and on a `.swift` save it recompiles the sketch off the main thread
/// (the window keeps drawing the old one) and swaps the result in on the main
/// thread. A compile error is reported and the running sketch is left untouched
/// — a typo never closes the window.
final class LiveSession {
    private let runner: SketchRunner
    private let loader: SketchLoader
    private let sketchPath: String
    private let displayName: String
    private let keepClock: Bool
    /// The framework's shader source, watched for live shader reload — set only
    /// when running from the Ollin repo (where `Sources/Ollin/Renderer` exists).
    private let shaderPath: String?
    private var watcher: FileWatcher?

    /// Asset extensions whose change re-runs `setup()` (where assets load).
    private static let assetExtensions = ["png", "jpg", "jpeg", "gif", "heic", "bmp", "tiff"]

    init(runner: SketchRunner, loader: SketchLoader, sketchPath: String,
         displayName: String, keepClock: Bool) {
        self.runner = runner
        self.loader = loader
        self.sketchPath = sketchPath
        self.displayName = displayName
        self.keepClock = keepClock

        let shader = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("Sources/Ollin/Renderer/Shaders.metal")
        self.shaderPath = FileManager.default.fileExists(atPath: shader) ? shader : nil
    }

    func start() {
        var dirs = [(sketchPath as NSString).deletingLastPathComponent]
        if let shaderPath {                   // also watch the shader's folder
            dirs.append((shaderPath as NSString).deletingLastPathComponent)
        }
        watcher = FileWatcher(paths: dirs) { [weak self] changed in
            self?.handle(changed)   // called on the watcher's background queue
        }
        watcher?.start()
        print("OllinLive: watching \(displayName) — edit and save to hot-reload.")
        if shaderPath != nil { print("OllinLive: also live-reloading Shaders.metal.") }
    }

    /// Dispatch a coalesced batch of changed paths by file type.
    private func handle(_ paths: [String]) {
        if paths.contains(where: { $0.hasSuffix(".swift") }) {
            reloadSketch()
        } else if shaderPath != nil, paths.contains(where: { $0.hasSuffix(".metal") }) {
            reloadShaders()
        } else if paths.contains(where: { Self.assetExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            DispatchQueue.main.async { [weak self] in
                self?.runner.rerunSetup()
                print("OllinLive: asset changed — re-running setup() ✓")
            }
        }
    }

    private func reloadShaders() {
        guard let shaderPath,
              let source = try? String(contentsOfFile: shaderPath, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            do {
                try self?.runner.reloadShaderLibrary(source: source)
                print("OllinLive: reloaded Shaders.metal ✓")
            } catch {
                FileHandle.standardError.write(
                    Data("OllinLive: shader reload skipped (kept running) — \(error)\n".utf8))
            }
        }
    }

    private func reloadSketch() {
        switch loader.load() {     // synchronous swiftc, on the background queue
        case .success(let sketch):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.runner.reload(to: sketch, keepClock: self.keepClock)
                print("OllinLive: reloaded \(type(of: sketch)) ✓")
            }
        case .failure(let error):
            FileHandle.standardError.write(
                Data("OllinLive: reload skipped (kept running) — \(error)\n".utf8))
        }
    }
}
