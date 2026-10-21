import Foundation
import Testing
@testable import OllinRuntime

/// A reload refused when the framework under the host changed. A live host
/// loads a sketch compiled against the module files beside its own binary, so
/// a build that rewrites those files while a window runs makes the next
/// reload a sketch compiled against a framework the host is not, which loads
/// and then crashes. The compiler names the modules it read (its loaded-module
/// trace); any of them written after the host started refuses the load with
/// one sentence, and the sketch on stage keeps playing (the stage half is the
/// OllinLiveCoding `--sessiontest`, which compiles for real).
@Suite
struct FrameworkRebuiltTests {
    /// A scratch folder laid out like a build, with module files dated `written`.
    private func build(_ modules: [String], written: Date) throws -> String {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("FrameworkRebuiltTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        for module in modules {
            let path = (root as NSString).appendingPathComponent(module)
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try Data("module".utf8).write(to: URL(fileURLWithPath: path))
            try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: path)
        }
        return root
    }

    @Test func theTraceNamesOnlyTheFrameworksModules() throws {
        let root = try build([], written: Date())
        defer { try? FileManager.default.removeItem(atPath: root) }
        let trace = (root as NSString).appendingPathComponent("modules.json")
        let products = (root as NSString).appendingPathComponent("Products")
        let json: [String: Any] = ["swiftmodules": [
            "/Applications/Xcode.app/SDKs/MacOSX.sdk/usr/lib/swift/Foundation.swiftmodule/arm64e.swiftinterface",
            "\(products)/Ollin.swiftmodule/arm64-apple-macos.swiftmodule",
            "\(products)/Modules/OllinAudio.swiftmodule",
            "\(root)/ProductsElsewhere/Other.swiftmodule",
        ]]
        try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: trace))
        let named = SketchLoader.frameworkModules(inTrace: trace, under: [products, products + "/Modules"])
        // Named as the files really are (the scratch folder is itself behind
        // a link, `/var` to `/private/var`).
        let real = SketchTarget.resolved(products)
        #expect(named == ["\(real)/Ollin.swiftmodule/arm64-apple-macos.swiftmodule",
                          "\(real)/Modules/OllinAudio.swiftmodule"])
        #expect(SketchLoader.frameworkModules(inTrace: root + "/missing.json", under: [products]).isEmpty)
        // A host that found its directories through a link (`.build/debug` is
        // one to the real products) still knows the files the compiler names.
        try FileManager.default.createDirectory(atPath: products, withIntermediateDirectories: true)
        let link = (root as NSString).appendingPathComponent("debug")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: products)
        let throughLink = SketchLoader.frameworkModules(inTrace: trace, under: [link, link + "/Modules"])
        #expect(throughLink.count == 2)
    }

    @Test func aModuleWrittenAfterTheLaunchRefusesTheLoad() throws {
        let launch = Date()
        let root = try build(["Ollin.swiftmodule/arm64-apple-macos.swiftmodule", "Modules/OllinAudio.swiftmodule"],
                             written: launch.addingTimeInterval(30))
        defer { try? FileManager.default.removeItem(atPath: root) }
        let modules = ["Ollin.swiftmodule/arm64-apple-macos.swiftmodule", "Modules/OllinAudio.swiftmodule"]
            .map { (root as NSString).appendingPathComponent($0) }
        guard case .frameworkRebuilt(let module, let at)? = SketchLoader.rebuiltModule(modules, since: launch) else {
            Issue.record("a module written after the launch did not refuse")
            return
        }
        #expect(module == "Ollin", "named after its module folder, not the file inside it")
        #expect(abs(at.timeIntervalSince(launch) - 30) < 1)
        let sentence = "\(SketchLoader.LoadError.frameworkRebuilt(module: module, at: at))"
        #expect(sentence.contains("The framework was rebuilt since this window opened (Ollin at "))
        #expect(sentence.hasSuffix("relaunch to run it."))
        // The other layout: the module is the file itself.
        guard case .frameworkRebuilt(let audio, _)? = SketchLoader.rebuiltModule([modules[1]], since: launch) else {
            Issue.record("the other layout's module did not refuse")
            return
        }
        #expect(audio == "OllinAudio")
    }

    @Test func modulesFromBeforeTheLaunchLoad() throws {
        let launch = Date()
        let root = try build(["Ollin.swiftmodule/arm64-apple-macos.swiftmodule"],
                             written: launch.addingTimeInterval(-30))
        defer { try? FileManager.default.removeItem(atPath: root) }
        let module = (root as NSString).appendingPathComponent("Ollin.swiftmodule/arm64-apple-macos.swiftmodule")
        #expect(SketchLoader.rebuiltModule([module], since: launch) == nil)
        // A module that is gone (a clean, mid-build) is not a refusal; the
        // compile that read it would have failed on its own.
        #expect(SketchLoader.rebuiltModule([root + "/Gone.swiftmodule"], since: launch) == nil)
        #expect(SketchLoader.rebuiltModule([], since: launch) == nil)
    }

    @Test func theLaunchIsThisProcesssOwnStart() {
        let launch = SketchLoader.processLaunch
        #expect(launch <= Date())
        #expect(launch > Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime - 1))
        #expect(SketchLoader(sketchPath: "/tmp/Sketch.swift").launchedAt == launch)
    }
}
