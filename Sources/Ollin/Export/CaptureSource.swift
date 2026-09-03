import Foundation

// Where an exported file came from. `--capture-source` resolves the source a
// render ran on to one commit, names the written files after it, and records it
// in the reproduction recipe, so a picture found months later leads back to the
// code that drew it. A clean tree is already that commit; an uncommitted one is
// written into the repository as a commit that sits on no branch, which is the
// part a plain `-dirty` marker can never give back.

/// The commit that holds the source an export was rendered from.
struct CaptureSource {
    /// The short hash that names the exported files and rides in the recipe.
    let id: String
    /// The short hash `HEAD` stood at, `nil` in a repository with no commits.
    let base: String?
    /// True when the tree carried uncommitted work, so `id` names a commit
    /// written for this capture rather than `HEAD` itself.
    let isCapture: Bool
    /// The ref anchoring a capture commit. Without it the commit is unreachable
    /// and the next `git gc` collects it.
    let ref: String?

    /// The capture for this run, resolved once and reused by every frame of a
    /// sequence or a video (the tree is hashed once, not 600 times).
    @MainActor static var current: CaptureSource?
}

// MARK: - Resolving the capture

extension CaptureSource {
    /// Resolve the source in `directory` (the process's working directory by
    /// default) to one commit, writing the working tree into the repository
    /// when it carries uncommitted work. `note` names the run in the commit
    /// message. Returns `nil` outside a repository, without git, or when the
    /// tree cannot be written.
    ///
    /// Nothing the caller owns moves: the index, the working tree, `HEAD`, and
    /// every branch are left exactly as they were. The capture is built in a
    /// throwaway index file and lands as a commit reachable only through
    /// `refs/ollin/captures/`.
    static func resolve(in directory: String? = nil, note: String) -> CaptureSource? {
        guard let root = git(["rev-parse", "--show-toplevel"], in: directory), !root.isEmpty else {
            return nil
        }
        let head = git(["rev-parse", "--short", "HEAD"], in: root)
        let dirty = git(["status", "--porcelain"], in: root).map { !$0.isEmpty } ?? false
        guard dirty else {
            guard let head else { return nil }   // a repository with no commits and nothing to keep
            return CaptureSource(id: head, base: head, isCapture: false, ref: nil)
        }
        guard let tree = writeWorkingTree(in: root) else {
            return head.map { CaptureSource(id: $0, base: $0, isCapture: false, ref: nil) }
        }

        // The tree alone identifies the source, so a second export of the same
        // files reuses the first capture instead of writing a near-twin commit.
        // (Its parent is then the base of the earlier run, which only differs
        // when the same tree is exported from two different commits.)
        let ref = "refs/ollin/captures/\(tree)"
        if let existing = git(["rev-parse", "--short", "--verify", "--quiet", ref], in: root) {
            return CaptureSource(id: existing, base: head, isCapture: true, ref: ref)
        }

        let message = """
            Ollin capture from \(note)

            The working tree an export was rendered from.
            base: \(head ?? "none")
            """
        var arguments = ["commit-tree", tree]
        if head != nil { arguments += ["-p", "HEAD"] }
        arguments += ["-m", message]
        guard let commit = git(arguments, in: root, identity: true),
              git(["update-ref", ref, commit], in: root) != nil,
              let short = git(["rev-parse", "--short", commit], in: root) else {
            return head.map { CaptureSource(id: $0, base: $0, isCapture: false, ref: nil) }
        }
        return CaptureSource(id: short, base: head, isCapture: true, ref: ref)
    }

    /// Hash the whole working tree, tracked changes and new files alike, and
    /// return the tree object. The real index is copied rather than rebuilt from
    /// `HEAD` so the stat cache still holds and only changed files are read.
    private static func writeWorkingTree(in root: String) -> String? {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-capture-\(UUID().uuidString).index")
        let index = scratch.path
        defer { try? FileManager.default.removeItem(at: scratch) }
        try? FileManager.default.removeItem(at: scratch)

        if let gitDir = git(["rev-parse", "--absolute-git-dir"], in: root) {
            let live = URL(fileURLWithPath: gitDir).appendingPathComponent("index")
            try? FileManager.default.copyItem(at: live, to: scratch)
        }
        if !FileManager.default.fileExists(atPath: index) {
            guard git(["read-tree", "HEAD"], in: root, index: index) != nil else { return nil }
        }
        // `--all` stages new, changed, and deleted files, and honors .gitignore,
        // so build products and other ignored work stay out of the capture.
        guard git(["add", "--all"], in: root, index: index) != nil else { return nil }
        return git(["write-tree"], in: root, index: index)
    }

    /// Run git and return its trimmed standard output, or `nil` when git is
    /// missing or the command fails. `index` points the command at a throwaway
    /// index file; `identity` supplies an author, so a capture never depends on
    /// the machine having one configured and never signs a person's name to a
    /// commit a tool wrote.
    ///
    /// A phone or a tablet runs no other program, so there is no git to ask and
    /// every answer here is nil.
    @discardableResult
    private static func git(_ arguments: [String], in directory: String?,
                            index: String? = nil, identity: Bool = false) -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        var environment = ProcessInfo.processInfo.environment
        if let index { environment["GIT_INDEX_FILE"] = index }
        if identity {
            environment["GIT_AUTHOR_NAME"] = "Ollin"
            environment["GIT_AUTHOR_EMAIL"] = "capture@ollin.invalid"
            environment["GIT_COMMITTER_NAME"] = "Ollin"
            environment["GIT_COMMITTER_EMAIL"] = "capture@ollin.invalid"
        }
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()   // a directory outside a repository stays quiet
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        // An empty answer is still an answer: `status --porcelain` says "clean"
        // that way, so only a failure comes back as nil.
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }
}

// MARK: - Naming the files after the capture

extension CaptureSource {
    /// The output flags whose value is a path this run writes. An input path
    /// (a take to replay, an automation file) is never renamed.
    static let outputFlags = [
        "--export", "--export-sequence", "--export-video", "--export-gif",
        "--export-loop", "--export-spatial", "--export-svg", "--export-pdf",
        "--export-gcode", "--export-usdz", "--export-grid", "--export-sweep",
        "--export-separations", "--export-plates", "--export-web",
    ]

    /// `out.png` with capture `a1b2c3d` becomes `out-a1b2c3d.png`; a directory
    /// or a file-name stem takes the suffix on the end. A path already carrying
    /// the capture is returned untouched, so stamping twice is harmless.
    static func stamp(_ path: String, with id: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, trimmed != "/" else { return path }
        let ext = URL(fileURLWithPath: trimmed).pathExtension
        let stem = ext.isEmpty ? trimmed : String(trimmed.dropLast(ext.count + 1))
        guard !stem.isEmpty, !stem.hasSuffix("-\(id)") else { return trimmed }
        return ext.isEmpty ? "\(stem)-\(id)" : "\(stem)-\(id).\(ext)"
    }

    /// `args` with every output path renamed after the capture. A flag given
    /// with no value, or followed by another flag, is left alone.
    static func stamped(_ args: [String], with id: String) -> [String] {
        var stamped = args
        for flag in outputFlags {
            guard let i = stamped.firstIndex(of: flag), i + 1 < stamped.count else { continue }
            let value = stamped[i + 1]
            guard !value.hasPrefix("--") else { continue }
            stamped[i + 1] = stamp(value, with: id)
        }
        return stamped
    }
}
