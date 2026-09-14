import Foundation
import Ollin

// `ollin doctor`: ask this machine every question a sketch would otherwise
// answer by failing, and put the one line that fixes each answer beside it.
//
// The report itself lives in the framework (`Core/Doctor.swift`), so what this
// prints is what the tests read. All this target does is find the checkout the
// command was run out of, print the lines, and decide the exit code.

let usage = """
usage: ollin doctor

Says what this machine can run: the system, the two compilers a sketch passes
through, the GPU and what it supports, the ollin command itself, and the grants
the framework can read. Nothing here asks for a permission; it only reports what
was decided already.

Exits nonzero when something would stop a sketch from running.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    print(usage)
    exit(0)
}
if let unknown = arguments.first {
    FileHandle.standardError.write(Data("ollin doctor takes no arguments (got \(unknown))\n\n\(usage)\n".utf8))
    exit(2)
}

/// The checkout this binary was built in: the executable sits at
/// `<repo>/.build/<config>/OllinDoctor`, but the build layouts differ, so walk
/// up from it until a directory holds both the manifest and the command.
func repository() -> String? {
    var directory = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
    for _ in 0 ..< 8 {
        let manifest = directory.appendingPathComponent("Package.swift")
        let command = directory.appendingPathComponent("Scripts/ollin")
        if FileManager.default.fileExists(atPath: manifest.path),
           FileManager.default.fileExists(atPath: command.path) {
            return directory.path
        }
        let parent = directory.deletingLastPathComponent()
        if parent.path == directory.path { break }
        directory = parent
    }
    return nil
}

let findings = Doctor.report(repository: repository())
print("")
for line in Doctor.lines(findings) { print(line) }
print("")
if Doctor.hasProblem(findings) {
    print("  Something above would stop a sketch from running.")
    exit(1)
}
