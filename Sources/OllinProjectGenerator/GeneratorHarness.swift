import AppKit
import Foundation
import OllinProjects
import OllinRuntime

/// Windowed smoke tests for the generator, in the house `--selftest` idiom.
///
///   swift run OllinProjectGenerator --stagetest
///
/// runs every extension seam's starter through the check the source stage
/// runs (a type-check against the framework on this machine, the loader's own
/// module discovery) and requires each to pass, then breaks one on purpose and
/// requires the check to fail *and* to name the line. A seam that stopped
/// compiling is the defect this stage exists to show, so a check that cannot
/// go red would be worth nothing.
///
///   swift run OllinProjectGenerator --self-shot <path.png>
///
/// writes a capture of the window into `path.png` a few seconds after launch,
/// drawn by the window itself (`cacheDisplay`), so it needs no screen-recording
/// permission. A running sketch on the stage comes out black (Metal draws
/// outside AppKit); the source stage is text, so it comes out whole.
enum GeneratorHarness {
    static let stageTest = CommandLine.arguments.contains("--stagetest")

    /// Where `--self-shot` writes the window capture, when requested.
    static let shotPath: String? = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--self-shot"),
              arguments.indices.contains(flag + 1) else { return nil }
        return arguments[flag + 1]
    }()

    /// The check the stage runs, shared with `--stagetest` so the gate and the
    /// window cannot disagree about what "compiles" means.
    nonisolated static func check(_ file: GeneratedFile) -> Result<Void, SketchLoader.LoadError> {
        let stand = (NSTemporaryDirectory() as NSString).appendingPathComponent(file.path)
        return SketchLoader(sketchPath: stand)
            .typecheck(file.contents, fileName: (file.path as NSString).lastPathComponent)
    }

    /// The starter file of a plan: the one under `Sources/`.
    static func starter(of project: GeneratedProject) -> GeneratedFile? {
        project.files.first { $0.path.hasPrefix("Sources/") }
    }

    @MainActor
    static func runStageTest(frameworkRoot: URL) async -> Never {
        var failures: [String] = []
        func report(_ line: String) { print("OllinProjectGenerator stagetest: \(line)") }

        for seam in ExtensionSeam.all {
            let request = ProjectRequest(
                name: "Check" + seam.id.split(separator: "-").map(\.capitalized).joined(),
                kind: .extensionPackage, seam: seam,
                destination: URL(fileURLWithPath: NSTemporaryDirectory()),
                framework: .localPath(frameworkRoot))
            guard let plan = try? ProjectGenerator.plan(request), let file = starter(of: plan) else {
                failures.append("\(seam.id): no starter file in the plan")
                continue
            }
            let started = Date()
            let result = await Task.detached(priority: .userInitiated) { check(file) }.value
            let seconds = String(format: "%.1fs", Date().timeIntervalSince(started))
            switch result {
            case .success:
                report("\(seam.id): \(file.path) compiles (\(seconds))")
            case .failure(let error):
                failures.append("\(seam.id): \(file.path) does not compile:\n\(error)")
            }
        }

        // The counterfactual: the same starter with one call misspelled must
        // fail, and the failure must name the line it is on.
        let sabotaged = ExtensionSeam.drawCall.source(named: "Broken", module: "OllinxBroken")
            .replacingOccurrences(of: "drawPolyline(", with: "drawPolylineX(")
        let brokenLine = sabotaged.components(separatedBy: "\n")
            .firstIndex { $0.contains("drawPolylineX(") }.map { $0 + 1 }
        let broken = GeneratedFile(path: "Sources/OllinxBroken/Broken.swift", contents: sabotaged)
        let result = await Task.detached(priority: .userInitiated) { check(broken) }.value
        switch result {
        case .success:
            failures.append("a misspelled call passed the check")
        case .failure(let error):
            let diagnostics = CompileDiagnostic.parse(String(describing: error))
            if let first = diagnostics.first(where: { $0.severity == .error }),
               first.fileName == "Broken.swift", first.line == brokenLine {
                report("a misspelled call fails at Broken.swift:\(first.line), as it should")
            } else {
                failures.append("the broken starter failed without naming Broken.swift:\(brokenLine ?? 0):\n\(error)")
            }
        }

        if failures.isEmpty {
            report("PASS (\(ExtensionSeam.all.count) seams compile, and a broken one is named)")
            exit(0)
        }
        for failure in failures { report("FAIL \(failure)") }
        exit(1)
    }

    /// Draw the (frontmost) window into a PNG. Returns whether both the capture
    /// and the write succeeded.
    @MainActor
    static func writeWindowShot(to path: String) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}
