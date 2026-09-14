import AVFoundation
import CoreGraphics
import Foundation
import Metal
import MetalFX

// The desk only. What this reports on is a Mac that runs the `ollin` command:
// the toolchain that compiles a sketch, the command itself on a PATH, a shell's
// completions, and the screen-recording grant. Two of its questions cannot even
// be asked elsewhere, since `Process` and the screen-capture preflight are
// macOS-only, and a phone running a sketch has none of it to answer for.
#if os(macOS)

/// What this machine can run, asked once and said in plain lines.
///
/// Everything Ollin needs is either present or it is not, and when it is not
/// the failure arrives somewhere else entirely: a shader that will not compile
/// reads as a blank layer, a camera nobody granted reads as a black frame, a
/// missing command reads as `command not found`. This asks each question
/// directly, before any of that, and puts the one line that fixes it beside the
/// answer.
///
/// Nothing here asks for anything. The permission reads are the preflight forms
/// that report what was already decided, so running the report can never raise
/// a dialog on somebody's screen.
package struct Doctor: Sendable {

    /// How much a finding matters. A `problem` stops a sketch from running at
    /// all; a `note` is something worth knowing that nothing is waiting on.
    package enum Level: String, Sendable {
        case ok, note, problem
    }

    /// One answer: what was asked, what came back, anything worth adding, and
    /// the single line that changes the answer.
    package struct Finding: Sendable {
        package let level: Level
        /// What was asked about, two or three words ("The Metal device").
        package let title: String
        /// The answer itself, on one line.
        package let detail: String
        /// Extra lines under the answer, each worth reading on its own.
        package let notes: [String]
        /// The one thing to do about it, or nil when there is nothing to do.
        package let fix: String?

        package init(_ level: Level, _ title: String, _ detail: String,
                     notes: [String] = [], fix: String? = nil) {
            self.level = level
            self.title = title
            self.detail = detail
            self.notes = notes
            self.fix = fix
        }
    }

    /// The whole report, in the order a person reads it: the system first, then
    /// the two compilers a sketch passes through, then the command itself, then
    /// what the machine has already been asked to allow.
    ///
    /// `repository` is the checkout the command was run out of, which only the
    /// command knows; without it the `ollin` on the path is reported but not
    /// matched against this clone.
    package static func report(repository: String? = nil) -> [Finding] {
        var findings: [Finding] = [system(), swiftCompiler()]
        findings.append(contentsOf: metal())
        findings.append(command(repository: repository))
        findings.append(completions())
        findings.append(contentsOf: permissions())
        return findings
    }

    /// Whether any finding is something a sketch would trip over.
    package static func hasProblem(_ findings: [Finding]) -> Bool {
        findings.contains { $0.level == .problem }
    }

    // MARK: The system

    /// The lowest macOS Ollin builds against, which is the package's own floor.
    package static let lowestSystem = (major: 26, minor: 0)

    private static func system() -> Finding {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let said = "macOS \(version.majorVersion).\(version.minorVersion)"
        let low = version.majorVersion < lowestSystem.major
            || (version.majorVersion == lowestSystem.major && version.minorVersion < lowestSystem.minor)
        guard low else { return Finding(.ok, "The system", said) }
        return Finding(.problem, "The system",
                       said + ", below the \(lowestSystem.major) this needs",
                       fix: "update macOS to \(lowestSystem.major) or later")
    }

    // MARK: The two compilers

    /// The Swift compiler, which turns a sketch file into the thing that runs.
    private static func swiftCompiler() -> Finding {
        guard let found = run("/usr/bin/xcrun", ["--find", "swiftc"]), found.status == 0,
              !found.output.isEmpty else {
            return Finding(.problem, "The Swift compiler", "not found",
                           notes: ["a sketch is compiled on every run and on every save"],
                           fix: "install Xcode, then: sudo xcode-select -s /Applications/Xcode.app")
        }
        let path = found.output
        let version = run(path, ["--version"])?.output
            .split(separator: "\n").first.map(String.init) ?? ""
        // The banner reads "Apple Swift version 6.4 (swiftlang-…)"; the number
        // alone is what a person wants, and the rest is build provenance.
        let number = version.split(separator: " ").first { Double($0) != nil || $0.contains(".") }
        return Finding(.ok, "The Swift compiler",
                       number.map { "Swift \($0)" } ?? "found",
                       notes: [path])
    }

    /// The shader compiler, asked the only way that settles it: by compiling.
    ///
    /// Ollin builds its shader library from source at runtime, so the component
    /// that does it has to be installed on the machine rather than merely
    /// findable in a toolchain. Asking `xcrun` would say whether a *file* is
    /// there; compiling says whether the thing works.
    private static func shaderCompiler(on device: MTLDevice) -> Finding {
        do {
            _ = try device.makeLibrary(source: "#include <metal_stdlib>\nkernel void ollin_doctor() {}\n",
                                       options: ollinShaderCompileOptions())
            return Finding(.ok, "The shader compiler", "compiles on this device")
        } catch {
            return Finding(.problem, "The shader compiler", "\(error.localizedDescription)",
                           notes: ["every sketch compiles Ollin's shader library when it starts"],
                           fix: "xcodebuild -downloadComponent MetalToolchain")
        }
    }

    // MARK: The GPU

    private static func metal() -> [Finding] {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return [Finding(.problem, "The Metal device", "none",
                            notes: ["everything Ollin draws is drawn on the GPU"],
                            fix: "run this on a Mac with a Metal-capable GPU")]
        }
        var notes: [String] = []
        let tracing = device.supportsRaytracing && device.supportsRaytracingFromRender
        if tracing {
            notes.append(device.supportsFamily(.apple9)
                ? "ray tracing, on dedicated hardware"
                : "ray tracing, in software on this generation, so a traced frame costs more")
        } else {
            notes.append("no ray tracing, so traced reflections and shadows fall back to their rasterized forms")
        }
        notes.append(device.supportsFamily(.metal3)
            ? "mesh shaders, which the strand fields are drawn with"
            : "no mesh shaders, so a strand field draws nothing")
        notes.append(MTLFXTemporalScalerDescriptor.supportsDevice(device)
            ? "temporal scaling, so a sketch can render small and present large"
            : "no temporal scaling, so an upscaling sketch renders at full size")
        return [Finding(.ok, "The Metal device", device.name, notes: notes),
                shaderCompiler(on: device)]
    }

    // MARK: The command

    /// The `ollin` a shell would run, and whether it is this clone's.
    private static func command(repository: String?) -> Finding {
        guard let found = onPath("ollin") else {
            return Finding(.note, "The ollin command", "not on your PATH",
                           notes: ["without it a sketch is run as: swift run OllinLive <file>"],
                           fix: "Scripts/ollin install")
        }
        let resolved = URL(fileURLWithPath: found).resolvingSymlinksInPath().path
        guard let repository else { return Finding(.ok, "The ollin command", found, notes: [resolved]) }
        let mine = URL(fileURLWithPath: repository).appendingPathComponent("Scripts/ollin")
            .resolvingSymlinksInPath().path
        if resolved == mine { return Finding(.ok, "The ollin command", found) }
        return Finding(.note, "The ollin command", found,
                       notes: ["it runs \(resolved), which is not this checkout"],
                       fix: "Scripts/ollin install")
    }

    /// Where zsh looks for completion functions. `FPATH` is not exported by a
    /// login shell, so the usual homes are read instead: finding the file in
    /// one of them is what a person means by "completions are installed".
    package static var completionDirectories: [String] {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/share/zsh/site-functions",
                "/usr/local/share/zsh/site-functions",
                "/usr/share/zsh/site-functions",
                home + "/.zsh/completions",
                home + "/.oh-my-zsh/completions",
                home + "/.local/share/zsh/site-functions"]
    }

    private static func completions() -> Finding {
        let manager = FileManager.default
        for directory in completionDirectories {
            let path = directory + "/_ollin"
            if manager.fileExists(atPath: path) {
                return Finding(.ok, "Shell completions", path)
            }
        }
        return Finding(.note, "Shell completions", "not installed",
                       notes: ["zsh completes the flags of every ollin command once they are"],
                       fix: "Scripts/ollin install")
    }

    // MARK: What the machine allows

    /// The three grants the framework itself can read without asking for them.
    /// Each is only a problem for a sketch that wants it, so a refusal is a
    /// note carrying the pane that undoes it.
    private static func permissions() -> [Finding] {
        [grant(name: "The camera",
               status: AVCaptureDevice.authorizationStatus(for: .video),
               wants: "a sketch that reads a camera or runs the vision tier",
               pane: "Privacy & Security > Camera"),
         grant(name: "The microphone",
               status: AVCaptureDevice.authorizationStatus(for: .audio),
               wants: "a sketch that listens, and a recording that keeps its sound",
               pane: "Privacy & Security > Microphone"),
         screenRecording()]
    }

    private static func grant(name: String, status: AVAuthorizationStatus,
                              wants: String, pane: String) -> Finding {
        switch status {
        case .authorized:
            return Finding(.ok, name, "allowed")
        case .notDetermined:
            return Finding(.ok, name, "not asked for yet",
                           notes: ["\(wants) asks the first time it opens one"])
        case .denied:
            return Finding(.note, name, "refused", notes: [wants],
                           fix: "System Settings > \(pane)")
        case .restricted:
            return Finding(.note, name, "restricted by this machine's policy", notes: [wants])
        @unknown default:
            return Finding(.note, name, "unknown")
        }
    }

    private static func screenRecording() -> Finding {
        let wants = "a sketch that reads the screen or another window"
        guard CGPreflightScreenCaptureAccess() else {
            return Finding(.note, "The screen", "not allowed", notes: [wants],
                           fix: "System Settings > Privacy & Security > Screen & System Audio Recording")
        }
        return Finding(.ok, "The screen", "allowed")
    }

    // MARK: Asking the machine

    /// The first executable named `name` on `PATH`, or nil.
    private static func onPath(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = String(directory) + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Run a command and take its first output, trimmed. The pipe is drained
    /// before the wait, which is the order that cannot deadlock.
    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String)? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, text)
    }
}

// MARK: - Saying it

package extension Doctor {

    /// The report as the lines the command prints. Written for a person: the
    /// answer first, anything worth adding under it, and the fix last so the
    /// thing to do is the thing left on screen.
    static func lines(_ findings: [Finding]) -> [String] {
        var out: [String] = []
        for finding in findings {
            let mark: String
            switch finding.level {
            case .ok: mark = "  ok  "
            case .note: mark = "  --  "
            case .problem: mark = "  no  "
            }
            out.append(mark + finding.title + ": " + finding.detail)
            for note in finding.notes { out.append("        " + note) }
            if let fix = finding.fix { out.append("        fix: " + fix) }
        }
        return out
    }
}

#endif
