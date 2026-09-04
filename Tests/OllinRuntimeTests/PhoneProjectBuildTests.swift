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
/// run. The time limit is the hang backstop for a wedged subprocess, and the
/// build is waited on asynchronously so that backstop can act: a blocking
/// wait cannot be cancelled, and on a three-core runner it parked one of the
/// three cooperative threads for the ten minutes the build took, with every
/// other suite queued behind that thread.
@Suite("The phone project builds", .serialized, .timeLimit(.minutes(15)))
struct PhoneProjectBuildTests {

    @Test("The host ollin phone writes compiles for iOS", .enabled(if: xcodegenInstalled, "xcodegen is not installed"))
    func theHostCompilesForIOS() async throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let sketch = repository.appendingPathComponent("Apps/OllinSketchApp/Sources/TouchRings.swift").path
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-phone-build-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let plan = try PhoneProject.plan(sketchPath: sketch, frameworkPath: repository.path, team: "ABCDE12345")
        try plan.write(to: folder)

        let generated = try await Self.run(["xcodegen", "generate", "--quiet"], in: folder)
        #expect(generated.status == 0, Comment(rawValue: generated.output))

        let derivedData = repository.appendingPathComponent(".build/PhoneProjectBuild/DerivedData")
        let build = try await Self.run([
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

    /// Runs `command` and returns its status and everything it printed. The
    /// process is waited on through its termination handler, so no thread is
    /// parked, and its output goes to a file rather than a pipe, so a child
    /// that outlives it holds nothing open. Cancelling the task (the suite's
    /// time limit) terminates the process, which is what resumes the wait.
    private static func run(_ command: [String], in directory: URL) async throws -> (status: Int32, output: String) {
        let output = directory.appendingPathComponent("\(command[0])-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            return (127, "could not create \(output.path)")
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        process.standardOutput = handle
        process.standardError = handle

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try? handle.close()
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        return (status, text)
    }
}
