import CryptoKit
import Foundation
import OllinRuntime

// MARK: - Where things live

let repo = FileManager.default.currentDirectoryPath
let guideDir = repo + "/Guide"
let preambleDir = guideDir + "/Snippets"

func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

/// The names the surrounding prose established, per chapter. A fragment like
/// `fill(p[i])` is correct prose and cannot compile alone; the preamble is where
/// that context is written down, once, instead of being pasted into the page.
///
/// A preamble is spliced inside the probe type, so its own imports are lifted
/// out and returned separately to sit at the top of the file.
func preamble(for page: String) -> (body: String, imports: [String]) {
    let stem = (page as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    guard let text = read("\(preambleDir)/\(stem).swift") else { return ("", []) }
    var kept: [String] = []
    var imports: [String] = []
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("import ") { imports.append(trimmed); continue }
        if trimmed.hasPrefix("//") && kept.isEmpty { continue }
        kept.append(line)
    }
    return (kept.joined(separator: "\n"), imports)
}

// MARK: - Arguments

var only: String?
var record = false
var pages: [String] = []
var listSkips = false
var argv = Array(CommandLine.arguments.dropFirst())
while let arg = argv.first {
    argv.removeFirst()
    switch arg {
    case "--only": only = argv.isEmpty ? nil : argv.removeFirst()
    case "--skips": listSkips = true
    case "--record": record = true
    case let path where path.hasSuffix(".md"): pages.append(path)
    default:
        FileHandle.standardError.write(Data("guide-snippets: unknown argument \(arg)\n".utf8))
        exit(2)
    }
}
if pages.isEmpty {
    pages = ((try? FileManager.default.contentsOfDirectory(atPath: guideDir)) ?? [])
        .filter { $0.hasSuffix(".md") && $0 != "AUTHORING.md" && $0 != "PLAN.md" }
        .sorted()
        .map { "Guide/" + $0 }
}
if let only { pages = pages.filter { $0.localizedCaseInsensitiveContains(only) } }

// MARK: - Collect

struct Job { var block: Block; var source: String; var preambleLines: Range<Int> }
var jobs: [Job] = []
var sharedImports: Set<String> = []
var skipped: [(Block, String)] = []
var shellBlocks: [Block] = []
var nameProblems: [NameProblem] = []

for page in pages {
    guard let text = read(repo + "/" + page) else {
        FileHandle.standardError.write(Data("guide-snippets: cannot read \(page)\n".utf8)); exit(1)
    }
    let (pre, imports) = preamble(for: page)
    sharedImports.formUnion(imports)
    nameProblems += exampleNameProblems(page: page, text: text, repo: repo)
    for block in blocks(in: page, text: text) {
        if block.language == "sh" { shellBlocks.append(block); continue }
        guard block.language == "swift" else { continue }
        if let reason = block.skip { skipped.append((block, reason)); continue }
        if isElided(block.body) { skipped.append((block, "elided with ...")); continue }
        let source = wrapped(block, preamble: pre)
        jobs.append(Job(block: block, source: source,
                        preambleLines: preambleSpan(of: pre, in: source)))
    }
}

nameProblems += docsAnchorProblems(in: shellBlocks, repo: repo)

if listSkips {
    for (block, reason) in skipped {
        print("\(block.page):\(block.line)  skipped: \(reason)")
    }
    print("guide-snippets: \(skipped.count) skipped, \(jobs.count) checked")
    exit(0)
}

// MARK: - Typecheck

/// One loader per job, run across the cores. `typecheck` writes its own work
/// directory per call, so the runs do not collide.
let importPrelude = sharedImports.sorted().joined(separator: "\n")
let lock = NSLock()
var failures: [(Block, String)] = []
var done = 0
let total = jobs.count
let quiet = ProcessInfo.processInfo.environment["OLLIN_SNIPPETS_QUIET"] != nil

DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
    let job = jobs[index]
    let source = importPrelude.isEmpty ? job.source : importPrelude + "\n" + job.source
    let name = (job.block.page as NSString).lastPathComponent
        .replacingOccurrences(of: ".md", with: "") + "_\(job.block.line).swift"
    let loader = SketchLoader(sketchPath: repo + "/Guide/Snippets/" + name)
    let result = loader.typecheck(source, fileName: name)
    lock.lock()
    done += 1
    if case .failure(let error) = result {
        failures.append((job.block, firstError("\(error)", preambleLines: job.preambleLines)))
    }
    if !quiet && done % 25 == 0 {
        FileHandle.standardError.write(Data("  \(done)/\(total)\r".utf8))
    }
    lock.unlock()
}

// MARK: - Report

/// Where the chapter's preamble sits in the wrapped file, so an error inside it
/// is reported as the preamble's rather than blamed on the reader's block.
func preambleSpan(of preamble: String, in source: String) -> Range<Int> {
    guard !preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0..<0 }
    let lines = source.components(separatedBy: "\n")
    let first = preamble.components(separatedBy: "\n").first(where: {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }) ?? ""
    guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces)
                                                 == first.trimmingCharacters(in: .whitespaces) })
    else { return 0..<0 }
    let count = preamble.components(separatedBy: "\n").count
    return (start + 1)..<(start + 1 + count)   // 1-based, as the compiler counts
}

/// The compiler says a great deal; the first real error is what a person acts on.
func firstError(_ log: String, preambleLines: Range<Int> = 0..<0) -> String {
    for line in log.components(separatedBy: "\n") where line.contains(": error:") {
        if let range = line.range(of: ": error: ") {
            let message = String(line[range.upperBound...])
            let place = line[..<range.lowerBound]
            let parts = place.components(separatedBy: ":").dropFirst(1).prefix(2)
            let column = parts.joined(separator: ":")
            let row = Int(parts.first ?? "") ?? -1
            if preambleLines.contains(row) {
                return "\(message)   [in this chapter's Guide/Snippets preamble, "
                     + "not in the block]"
            }
            return "\(message)   [in the block, at \(column)]"
        }
    }
    return log.components(separatedBy: "\n").first ?? log
}

failures.sort { ($0.0.page, $0.0.line) < ($1.0.page, $1.0.line) }

// MARK: - The recorded gaps
//
// Most fragments in the Guide cannot compile alone, and correctly so: `fill(p[i])`
// is the right thing to print on the page and names two things the prose
// introduced. Rather than paste that context into every block, the blocks that
// cannot stand alone are recorded here with the error they give, and the gate
// fails on a *change*: a block that starts failing, a block whose error becomes
// a different one, or a recorded block that now compiles. That is what turns an
// API rename into a failure here instead of into a reader's problem.
//
// A chapter shrinks its share by adding Guide/Snippets/<chapter>.swift, which is
// spliced into every probe from that page. The listing is the backlog, and it is
// meant to go down.

/// Keyed on the block's own text, so editing the prose above it moves nothing.
func fingerprint(_ block: Block) -> String {
    let normalized = block.body.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    let digest = SHA256.hash(data: Data((block.page + "\u{1}" + normalized).utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(12).description
}

let gapsPath = preambleDir + "/known-gaps.txt"
let header = """
# Guide blocks that cannot compile on their own, and the error each one gives.
#
# Written by `swift run OllinGuideSnippets --record`; never edited by hand. Each
# line is <fingerprint> <page>:<line> <first error>, keyed on the block's own
# text so editing the prose around it changes nothing here.
#
# A line in this file is not a defect. Most are fragments naming something the
# surrounding prose introduced, which is the right way to write a page. What the
# file buys is that any *change* fails the gate: a block that starts failing, one
# whose error becomes a different one, or one that now compiles and should be
# dropped from here. That is how a public rename shows up as a broken snippet.
#
# To shrink a chapter's share, add Guide/Snippets/<chapter>.swift declaring the
# names its prose establishes; it is spliced into every probe from that page.

"""

var recorded: [String: (place: String, message: String)] = [:]
if let text = read(gapsPath) {
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        let parts = line.components(separatedBy: "  ")
        guard parts.count >= 3 else { continue }
        recorded[parts[0]] = (parts[1], parts[2...].joined(separator: "  "))
    }
}

let failedNow = Dictionary(uniqueKeysWithValues: failures.map {
    (fingerprint($0.0), (block: $0.0, message: $0.1))
})

if record {
    var lines = [header]
    for (print_, entry) in failedNow.sorted(by: {
        ($0.value.block.page, $0.value.block.line) < ($1.value.block.page, $1.value.block.line)
    }) {
        lines.append("\(print_)  \(entry.block.page):\(entry.block.line)  \(entry.message)")
    }
    try? (lines.joined(separator: "\n") + "\n").write(toFile: gapsPath, atomically: true, encoding: .utf8)
    print("guide-snippets: recorded \(failedNow.count) known gaps into \(gapsPath)")
    print("guide-snippets: \(jobs.count) checked, \(skipped.count) skipped, \(shellBlocks.count) shell blocks seen")
    exit(0)
}

var problems: [String] = []
for (key, entry) in failedNow.sorted(by: {
    ($0.value.block.page, $0.value.block.line) < ($1.value.block.page, $1.value.block.line)
}) {
    guard let known = recorded[key] else {
        problems.append("\(entry.block.page):\(entry.block.line): \(entry.message)")
        continue
    }
    if known.message != entry.message {
        problems.append("\(entry.block.page):\(entry.block.line): the error changed"
                        + "\n    was: \(known.message)\n    now: \(entry.message)")
    }
}
for (key, known) in recorded.sorted(by: { $0.value.place < $1.value.place })
where failedNow[key] == nil {
    let stillThere = jobs.contains { fingerprint($0.block) == key }
    if stillThere {
        problems.append("\(known.place): compiles now, so drop its line from known-gaps.txt")
    }
}

for problem in nameProblems.sorted(by: { ($0.page, $0.line) < ($1.page, $1.line) }) {
    problems.append("\(problem.page):\(problem.line): \(problem.message)")
}
problems.sort()
for problem in problems { print(problem) }
print("guide-snippets: \(jobs.count) Swift blocks checked, \(skipped.count) skipped, "
      + "\(shellBlocks.count) shell blocks read for commands, "
      + "\(failedNow.count) cannot stand alone, \(problems.count) problem(s)")
if !problems.isEmpty {
    print("guide-snippets: a new or changed failure means the snippet broke. Fix the block,")
    print("    or if the context is genuinely new, re-record with --record and say why.")
}
exit(problems.isEmpty ? 0 : 1)
