import CryptoKit
import Foundation
import OllinRuntime

// MARK: - Where things live

let repo = FileManager.default.currentDirectoryPath

func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

/// One tree of prose whose Swift blocks are compiled: the Guide's chapters or
/// the reference pages under Docs/. Each keeps its own preambles and its own
/// list of known gaps, so a Docs page's error is never compared against the
/// Guide's baseline and the two files can be re-recorded apart.
struct Tree {
    let name: String            // "Guide" or "Docs", also the directory
    let pages: [String]         // repo-relative, sorted
    var snippetsDir: String { repo + "/" + name + "/Snippets" }
    var gapsPath: String { snippetsDir + "/known-gaps.txt" }

    /// The preamble file a page reads: the chapter's stem for the Guide
    /// (`03-MotionAndTime.swift`), and the path under Docs/ with its slashes
    /// turned to dashes for the reference (`Drawing-Color.swift`), since three
    /// Docs pages share a stem (`README.md`, `Light.md`, `Watercolor.md`).
    func preambleStem(for page: String) -> String {
        let relative = String(page.dropFirst(name.count + 1)).replacingOccurrences(of: ".md", with: "")
        return name == "Guide" ? (relative as NSString).lastPathComponent : relative.replacingOccurrences(of: "/", with: "-")
    }

    /// Every satellite any preamble in this tree imports, read from all of them
    /// rather than from the pages this run happens to be checking. A block's
    /// error must not depend on what else was checked beside it: with the union
    /// taken over the selection, `--only 22-Meshes` had no `OllinPhysics` in
    /// scope, one block there gave a different first error than in the whole
    /// run, and the recorded baseline then read as broken for a chapter nobody
    /// had touched. Per tree, so the Guide's union cannot move a Docs error.
    var sharedImports: Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: snippetsDir)) ?? []
        var found: Set<String> = []
        for file in files where file.hasSuffix(".swift") {
            found.formUnion(preamble(stem: file.replacingOccurrences(of: ".swift", with: "")).imports)
        }
        return found
    }

    /// The names the surrounding prose established, per page. A fragment like
    /// `fill(p[i])` is correct prose and cannot compile alone; the preamble is
    /// where that context is written down, once, instead of being pasted into
    /// the page.
    ///
    /// A preamble is spliced inside the probe type, so its own imports are
    /// lifted out and returned separately to sit at the top of the file.
    func preamble(stem: String) -> (body: String, imports: [String]) {
        guard let text = read("\(snippetsDir)/\(stem).swift") else { return ("", []) }
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

    var header: String {
        let what = name == "Guide" ? "Guide blocks" : "Docs blocks"
        let preambleName = name == "Guide" ? "Guide/Snippets/<chapter>.swift" : "Docs/Snippets/<Group>-<Page>.swift"
        return """
        # \(what) that cannot compile on their own, and the error each one gives.
        #
        # Written by `Scripts/check-snippets.sh --record`; never edited by hand. Each
        # line is <fingerprint> <page>:<line> <first error>, keyed on the block's own
        # text so editing the prose around it changes nothing here.
        #
        # A line in this file is not a defect. Most are fragments naming something the
        # surrounding prose introduced, which is the right way to write a page. What the
        # file buys is that any *change* fails the gate: a block that starts failing, one
        # whose error becomes a different one, or one that now compiles and should be
        # dropped from here. That is how a public rename shows up as a broken snippet.
        #
        # To shrink a page's share, add \(preambleName) declaring the
        # names its prose establishes; it is spliced into every probe from that page.

        """
    }
}

func guidePages() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: repo + "/Guide")) ?? [])
        .filter { $0.hasSuffix(".md") && $0 != "AUTHORING.md" && $0 != "PLAN.md" }
        .sorted()
        .map { "Guide/" + $0 }
}

func docsPages() -> [String] {
    ((FileManager.default.enumerator(atPath: repo + "/Docs")?.compactMap { $0 as? String }) ?? [])
        .filter { $0.hasSuffix(".md") && !$0.hasPrefix("Snippets/") }
        .sorted()
        .map { "Docs/" + $0 }
}

let trees = [Tree(name: "Guide", pages: guidePages()), Tree(name: "Docs", pages: docsPages())]

// MARK: - Arguments

var only: String?
var record = false
var named: [String] = []
var listSkips = false
var argv = Array(CommandLine.arguments.dropFirst())
while let arg = argv.first {
    argv.removeFirst()
    switch arg {
    case "--only": only = argv.isEmpty ? nil : argv.removeFirst()
    case "--skips": listSkips = true
    case "--record": record = true
    case let path where path.hasSuffix(".md"): named.append(path)
    default:
        FileHandle.standardError.write(Data("check-snippets: unknown argument \(arg)\n".utf8))
        exit(2)
    }
}

/// The pages this run checks, per tree: everything, the named ones, or the
/// ones a `--only` substring picks out (`--only Docs/` is the reference alone).
@MainActor func selected(_ tree: Tree) -> [String] {
    var pages = named.isEmpty ? tree.pages : named.filter { $0.hasPrefix(tree.name + "/") }
    if let only { pages = pages.filter { $0.localizedCaseInsensitiveContains(only) } }
    return pages
}

// MARK: - Collect

struct Job { var tree: Int; var block: Block; var source: String; var preambleLines: Range<Int> }
var jobs: [Job] = []
var skipped: [(Block, String)] = []
var shellBlocks: [Block] = []
var nameProblems: [NameProblem] = []
var checkedPages: [Set<String>] = trees.map { _ in [] }

for (index, tree) in trees.enumerated() {
    for page in selected(tree) {
        guard let text = read(repo + "/" + page) else {
            FileHandle.standardError.write(Data("check-snippets: cannot read \(page)\n".utf8)); exit(1)
        }
        checkedPages[index].insert(page)
        let (pre, _) = tree.preamble(stem: tree.preambleStem(for: page))
        nameProblems += exampleNameProblems(page: page, text: text, repo: repo)
        for block in blocks(in: page, text: text) {
            if block.language == "sh" { shellBlocks.append(block); continue }
            guard block.language == "swift" else { continue }
            if let reason = block.skip { skipped.append((block, reason)); continue }
            if isElided(block.body) { skipped.append((block, "elided with ...")); continue }
            let source = wrapped(block, preamble: pre)
            jobs.append(Job(tree: index, block: block, source: source,
                            preambleLines: preambleSpan(of: pre, in: source)))
        }
    }
}

nameProblems += docsAnchorProblems(in: shellBlocks, repo: repo)

if listSkips {
    for (block, reason) in skipped {
        print("\(block.page):\(block.line)  skipped: \(reason)")
    }
    print("check-snippets: \(skipped.count) skipped, \(jobs.count) checked")
    exit(0)
}

// MARK: - Typecheck

/// One loader per job, run across the cores. `typecheck` writes its own work
/// directory per call, so the runs do not collide.
let importPreludes = trees.map { $0.sharedImports.sorted().joined(separator: "\n") }
let lock = NSLock()
var failures: [(Block, String)] = []
var done = 0
let total = jobs.count
let quiet = ProcessInfo.processInfo.environment["OLLIN_SNIPPETS_QUIET"] != nil

DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
    let job = jobs[index]
    let tree = trees[job.tree]
    let prelude = importPreludes[job.tree]
    let source = prelude.isEmpty ? job.source : prelude + "\n" + job.source
    let name = tree.preambleStem(for: job.block.page) + "_\(job.block.line).swift"
    let loader = SketchLoader(sketchPath: tree.snippetsDir + "/" + name)
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

/// Where the page's preamble sits in the wrapped file, so an error inside it
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
                return "\(message)   [in this page's Snippets preamble, not in the block]"
            }
            return "\(message)   [in the block, at \(column)]"
        }
    }
    return log.components(separatedBy: "\n").first ?? log
}

failures.sort { ($0.0.page, $0.0.line) < ($1.0.page, $1.0.line) }

// MARK: - The recorded gaps
//
// Most fragments in the prose cannot compile alone, and correctly so: `fill(p[i])`
// is the right thing to print on the page and names two things the prose
// introduced. Rather than paste that context into every block, the blocks that
// cannot stand alone are recorded here with the error they give, and the gate
// fails on a *change*: a block that starts failing, a block whose error becomes
// a different one, or a recorded block that now compiles. That is what turns an
// API rename into a failure here instead of into a reader's problem.
//
// A page shrinks its share by adding a preamble under its tree's Snippets/,
// which is spliced into every probe from that page. The listing is the backlog,
// and it is meant to go down.

/// What is recorded and compared, with everything volatile taken out.
///
/// The compiler names the throwaway module it built (`OllinRuntimeCheck_` and a
/// fresh UUID) and the line inside the wrapped file, and both change without the
/// block changing: the module name every single run, the line whenever the
/// page's preamble grows. Comparing the raw text made the gate report a
/// change on every run and after every unrelated edit.
func stableMessage(_ message: String) -> String {
    var out = message.replacingOccurrences(of: #"OllinRuntimeCheck_[A-Fa-f0-9]+"#,
                                           with: "the probe", options: .regularExpression)
    if let bracket = out.range(of: "   [in ") { out = String(out[..<bracket.lowerBound]) }
    return out.trimmingCharacters(in: .whitespaces)
}

/// Keyed on the block's own text, so editing the prose above it moves nothing.
func fingerprint(_ block: Block) -> String {
    let normalized = block.body.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    let digest = SHA256.hash(data: Data((block.page + "\u{1}" + normalized).utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(12).description
}

struct Recorded { var place: String; var message: String }

func readRecorded(_ path: String) -> [String: Recorded] {
    var out: [String: Recorded] = [:]
    guard let text = read(path) else { return out }
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        let parts = line.components(separatedBy: "  ")
        guard parts.count >= 3 else { continue }
        out[parts[0]] = Recorded(place: parts[1], message: parts[2...].joined(separator: "  "))
    }
    return out
}

func page(of place: String) -> String {
    String(place[..<(place.lastIndex(of: ":") ?? place.endIndex)])
}

let failedNow = Dictionary(uniqueKeysWithValues: failures.map {
    (fingerprint($0.0), (block: $0.0, message: $0.1))
})

if record {
    for (index, tree) in trees.enumerated() where !checkedPages[index].isEmpty {
        // A scoped run re-records only the pages it checked and keeps every
        // other page's lines, so `--only Docs/Color --record` cannot empty the
        // file of everything it did not look at.
        var kept = readRecorded(tree.gapsPath).filter { !checkedPages[index].contains(page(of: $0.value.place)) }
        for (print_, entry) in failedNow where entry.block.page.hasPrefix(tree.name + "/") {
            kept[print_] = Recorded(place: "\(entry.block.page):\(entry.block.line)",
                                    message: stableMessage(entry.message))
        }
        var lines = [tree.header]
        for (print_, entry) in kept.sorted(by: { ($0.value.place, $0.key) < ($1.value.place, $1.key) }) {
            lines.append("\(print_)  \(entry.place)  \(entry.message)")
        }
        try? FileManager.default.createDirectory(atPath: tree.snippetsDir, withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(toFile: tree.gapsPath, atomically: true, encoding: .utf8)
        print("check-snippets: recorded \(kept.count) known gaps into \(tree.name)/Snippets/known-gaps.txt")
    }
    print("check-snippets: \(jobs.count) checked, \(skipped.count) skipped, \(shellBlocks.count) shell blocks seen")
    exit(0)
}

var problems: [String] = []
for (index, tree) in trees.enumerated() {
    let recorded = readRecorded(tree.gapsPath)
    for (key, entry) in failedNow.sorted(by: {
        ($0.value.block.page, $0.value.block.line) < ($1.value.block.page, $1.value.block.line)
    }) where entry.block.page.hasPrefix(tree.name + "/") {
        guard let known = recorded[key] else {
            problems.append("\(entry.block.page):\(entry.block.line): \(entry.message)")
            continue
        }
        if known.message != stableMessage(entry.message) {
            problems.append("\(entry.block.page):\(entry.block.line): the error changed"
                            + "\n    was: \(known.message)\n    now: \(entry.message)")
        }
    }
    for (key, known) in recorded.sorted(by: { $0.value.place < $1.value.place })
    where failedNow[key] == nil && checkedPages[index].contains(page(of: known.place)) {
        let stillThere = jobs.contains { fingerprint($0.block) == key }
        if stillThere {
            problems.append("\(known.place): compiles now, so drop its line from \(tree.name)/Snippets/known-gaps.txt")
        }
    }
}

for problem in nameProblems.sorted(by: { ($0.page, $0.line) < ($1.page, $1.line) }) {
    problems.append("\(problem.page):\(problem.line): \(problem.message)")
}
problems.sort()
for problem in problems { print(problem) }
print("check-snippets: \(jobs.count) Swift blocks checked, \(skipped.count) skipped, "
      + "\(shellBlocks.count) shell blocks read for commands, "
      + "\(failedNow.count) cannot stand alone, \(problems.count) problem(s)")
if !problems.isEmpty {
    print("check-snippets: a new or changed failure means the snippet broke. Fix the block,")
    print("    or if the context is genuinely new, re-record with --record and say why.")
}
exit(problems.isEmpty ? 0 : 1)
