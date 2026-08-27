import Foundation
import Ollin

// `ollin check <file.metal> …`: compile a shader on this machine's GPU and say what it
// found. A shader edited outside a running sketch has otherwise no way to be tried: the
// only other way to learn whether it compiles is to launch something that draws it, and
// a mistake then arrives as a blank layer rather than as a line number.

let usage = """
usage: ollin check <file.metal> [more.metal ...] [--as generator|filter|combine]

Compiles each shader the way a sketch would and reports what it found: any errors at
your own line, what the shader is, the parameters it reads, and the files it includes.

  --as <shape>   compile it as a generator (no input layer), a filter (one), or a
                 combine (two). Left off, the shape follows from the layer readers
                 the shader calls, which is the same rule the effect graph uses.

Exits nonzero when any shader fails.
"""

var paths: [String] = []
var given: ShaderCheckReport.Shape?
var arguments = Array(CommandLine.arguments.dropFirst())

while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--help", "-h", "help":
        print(usage)
        exit(0)
    case "--as":
        guard let name = arguments.first, let shape = ShaderCheckReport.Shape(rawValue: name) else {
            let names = ShaderCheckReport.Shape.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data("ollin check: --as takes one of \(names)\n".utf8))
            exit(2)
        }
        arguments.removeFirst()
        given = shape
    default:
        if argument.hasPrefix("-") {
            FileHandle.standardError.write(Data("ollin check: unknown flag \(argument)\n".utf8))
            exit(2)
        }
        paths.append(argument)
    }
}

guard !paths.isEmpty else {
    print(usage)
    exit(2)
}

/// How the parameters a shader reads read in a sentence. Contiguous from zero is the
/// ordinary case and says exactly how many floats to pass; a gap is worth pointing at,
/// since an index nothing writes reads as zero and is usually a slip.
func parameterLine(_ indices: [Int]) -> String {
    guard let last = indices.last else { return "reads no parameters" }
    let list = indices.map(String.init).joined(separator: ", ")
    if indices == Array(0...last) {
        return "reads parameter\(indices.count == 1 ? "" : "s") \(list), so pass "
            + "\(indices.count) float\(indices.count == 1 ? "" : "s")"
    }
    let missing = Set(0...last).subtracting(indices).sorted().map(String.init).joined(separator: ", ")
    return "reads parameters \(list), and skips \(missing), which nothing would write"
}

var failures = 0
for path in paths {
    let report = ShaderCheck.check(path: path, as: given)
    guard report.ok else {
        failures += 1
        let count = report.diagnostics.split(separator: "\n").filter { $0.contains(": error:") }.count
        print("\(path): \(count == 0 ? "failed" : "\(count) error\(count == 1 ? "" : "s")")")
        print(report.diagnostics)
        continue
    }
    print("\(path): ok")
    let because = report.shapeWasGiven ? "as you asked" : "because \(report.shape.reason)"
    print("  a \(report.shape.rawValue), \(because)")
    print("  \(parameterLine(report.parameters))")
    for file in report.included {
        print("  includes \(file)")
    }
}

exit(failures == 0 ? 0 : 1)
