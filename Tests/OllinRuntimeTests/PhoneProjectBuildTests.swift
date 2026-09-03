import Foundation
@testable import OllinRuntime
import Testing

/// Whether xcodegen is on this machine. The generated project is an Xcode
/// project spec, so without it there is nothing to build; the test then
/// reports itself skipped and says why, rather than passing quietly.
private let xcodegenInstalled: Bool = {
    ["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen"].contains { FileManager.default.isExecutableFile(atPath: $0) }
}()

/// The check that matters most for `ollin phone`: the host it writes has to
/// compile for the phone against the framework as it stands. The pure tests
/// cannot catch a template that calls something the framework renamed, and
/// the preflight's iOS build compiles the framework, not this host.
///
/// It builds for the generic iOS destination with signing off, so it needs no
/// device and no team, and it keeps one derived-data folder under `.build` so
/// the framework compiles for the phone cold once ever rather than once per
/// run. The time limit is the hang backstop for a wedged subprocess.
@Suite("The phone project builds", .serialized, .timeLimit(.minutes(15)))
struct PhoneProjectBuildTests {

    @Test("The host ollin phone writes compiles for iOS", .enabled(if: xcodegenInstalled, "xcodegen is not installed"))
    func theHostCompilesForIOS() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let sketch = repository.appendingPathComponent("Apps/OllinSketchApp/Sources/TouchRings.swift").path
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-phone-build-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let plan = try PhoneProject.plan(sketchPath: sketch, frameworkPath: repository.path, team: "ABCDE12345")
        try plan.write(to: folder)

        let generated = Self.run(["xcodegen", "generate", "--quiet"], in: folder)
        #expect(generated.status == 0, Comment(rawValue: generated.output))

        let derivedData = repository.appendingPathComponent(".build/PhoneProjectBuild/DerivedData")
        let build = Self.run([
            "xcodebuild",
            "-project", folder.appendingPathComponent("OllinPhone.xcodeproj").path,
            "-scheme", "OllinPhone",
            "-destination", "generic/platform=iOS",
            "-derivedDataPath", derivedData.path,
            "CODE_SIGNING_ALLOWED=NO",
            "-quiet", "build",
        ], in: folder)
        let errors = build.output.split(separator: "\n").filter { $0.contains("error:") }.joined(separator: "\n")
        #expect(build.status == 0, Comment(rawValue: errors.isEmpty ? String(build.output.suffix(2000)) : errors))
    }

    private static func repositoryRoot() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("Sources/Ollin").path) {
                return url
            }
        }
        return nil
    }

    private static func run(_ command: [String], in directory: URL) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (127, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
