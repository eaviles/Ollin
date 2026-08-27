import Foundation
import Testing
@testable import Ollin

/// `--capture-source`: resolving an export to the commit that holds its source,
/// naming the written files after it, and leaving the repository exactly as it
/// was found. Pure Foundation and git, no GPU, so it runs anywhere.
@MainActor
struct CaptureSourceTests {

    // MARK: - A repository to work in

    /// Run git in `directory` and return its trimmed output, failing the test
    /// when the command does. The identity is passed per command so the run
    /// never depends on the machine having one configured.
    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-c", "user.name=Test", "-c", "user.email=test@ollin.invalid",
                             "-c", "commit.gpgsign=false"] + arguments
        process.currentDirectoryURL = directory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed")
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A fresh repository in its own directory, holding one committed file.
    /// Each test gets its own, so parallel runs never share one.
    private func makeRepository() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-capture-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: root)
        try "first\n".write(to: root.appendingPathComponent("sketch.swift"), atomically: true,
                            encoding: .utf8)
        try git(["add", "."], in: root)
        try git(["commit", "-q", "-m", "first"], in: root)
        return root
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Resolving

    @Test func aCleanTreeIsItsOwnCapture() throws {
        let root = try makeRepository()
        defer { remove(root) }

        let source = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        #expect(source.id == (try git(["rev-parse", "--short", "HEAD"], in: root)))
        #expect(source.isCapture == false)
        #expect(source.ref == nil)
        // Nothing was written: a clean tree needs no commit of its own.
        #expect(try git(["for-each-ref", "refs/ollin/captures"], in: root).isEmpty)
    }

    @Test func anUncommittedTreeBecomesACommit() throws {
        let root = try makeRepository()
        defer { remove(root) }
        try "second\n".write(to: root.appendingPathComponent("sketch.swift"), atomically: true,
                             encoding: .utf8)
        try "new\n".write(to: root.appendingPathComponent("added.swift"), atomically: true,
                          encoding: .utf8)

        let source = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        #expect(source.isCapture)
        #expect(source.id != (try git(["rev-parse", "--short", "HEAD"], in: root)))
        #expect(try git(["cat-file", "-t", source.id], in: root) == "commit")
        // The edit and the brand-new file are both in the captured tree, which
        // is the whole point: a `-dirty` marker gives back neither.
        #expect(try git(["show", "\(source.id):sketch.swift"], in: root) == "second")
        #expect(try git(["show", "\(source.id):added.swift"], in: root) == "new")
        // And it grows from the commit the work started on.
        #expect(try git(["rev-parse", "--short", "\(source.id)^"], in: root)
                == (try git(["rev-parse", "--short", "HEAD"], in: root)))
    }

    @Test func aCaptureIsAnchoredSoCollectionKeepsIt() throws {
        let root = try makeRepository()
        defer { remove(root) }
        try "second\n".write(to: root.appendingPathComponent("sketch.swift"), atomically: true,
                             encoding: .utf8)

        let source = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        let ref = try #require(source.ref)
        #expect(ref.hasPrefix("refs/ollin/captures/"))
        #expect(try git(["rev-parse", "--short", ref], in: root) == source.id)
        // An aggressive collection is the real test of the anchor.
        try git(["reflog", "expire", "--expire=now", "--all"], in: root)
        try git(["gc", "--prune=now", "-q"], in: root)
        #expect(try git(["cat-file", "-t", source.id], in: root) == "commit")
    }

    @Test func theCaptureLeavesTheRepositoryAlone() throws {
        let root = try makeRepository()
        defer { remove(root) }
        try "second\n".write(to: root.appendingPathComponent("sketch.swift"), atomically: true,
                             encoding: .utf8)
        try "staged\n".write(to: root.appendingPathComponent("staged.swift"), atomically: true,
                             encoding: .utf8)
        try git(["add", "staged.swift"], in: root)

        let before = (status: try git(["status", "--porcelain"], in: root),
                      head: try git(["rev-parse", "HEAD"], in: root),
                      branch: try git(["rev-parse", "--abbrev-ref", "HEAD"], in: root),
                      staged: try git(["diff", "--cached", "--name-only"], in: root))
        _ = CaptureSource.resolve(in: root.path, note: "test")
        #expect(try git(["status", "--porcelain"], in: root) == before.status)
        #expect(try git(["rev-parse", "HEAD"], in: root) == before.head)
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: root) == before.branch)
        #expect(try git(["diff", "--cached", "--name-only"], in: root) == before.staged)
        // The branch it sits on gained nothing either.
        #expect(try git(["rev-list", "--count", "HEAD"], in: root) == "1")
    }

    @Test func ignoredWorkStaysOutOfTheCapture() throws {
        let root = try makeRepository()
        defer { remove(root) }
        try ".build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true,
                              encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".build"),
                                                withIntermediateDirectories: true)
        try "binary\n".write(to: root.appendingPathComponent(".build/product"), atomically: true,
                             encoding: .utf8)

        let source = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        let listed = try git(["ls-tree", "-r", "--name-only", source.id], in: root)
        #expect(listed.contains(".gitignore"))
        #expect(!listed.contains(".build"))
    }

    @Test func theSameTreeCapturesOnlyOnce() throws {
        let root = try makeRepository()
        defer { remove(root) }
        try "second\n".write(to: root.appendingPathComponent("sketch.swift"), atomically: true,
                             encoding: .utf8)

        let first = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        let again = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        #expect(first.id == again.id)
        #expect(try git(["for-each-ref", "--count=9", "refs/ollin/captures"], in: root)
                .split(separator: "\n").count == 1)

        // A further edit is a different source, so it is a different capture.
        try "third\n".write(to: root.appendingPathComponent("sketch.swift"), atomically: true,
                            encoding: .utf8)
        let third = try #require(CaptureSource.resolve(in: root.path, note: "test"))
        #expect(third.id != first.id)
    }

    @Test func outsideARepositoryThereIsNoCapture() throws {
        let plain = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-capture-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { remove(plain) }
        #expect(CaptureSource.resolve(in: plain.path, note: "test") == nil)
    }

    // MARK: - Naming the files

    @Test func stampNamesAFileAfterTheCapture() {
        #expect(CaptureSource.stamp("out.png", with: "a1b2c3d") == "out-a1b2c3d.png")
        #expect(CaptureSource.stamp("/tmp/a b/out.mp4", with: "a1b2c3d") == "/tmp/a b/out-a1b2c3d.mp4")
        #expect(CaptureSource.stamp("frames", with: "a1b2c3d") == "frames-a1b2c3d")
        #expect(CaptureSource.stamp("/tmp/frames/", with: "a1b2c3d") == "/tmp/frames-a1b2c3d")
        #expect(CaptureSource.stamp("plate", with: "a1b2c3d") == "plate-a1b2c3d")
    }

    @Test func stampingTwiceChangesNothing() {
        let once = CaptureSource.stamp("out.png", with: "a1b2c3d")
        #expect(CaptureSource.stamp(once, with: "a1b2c3d") == once)
    }

    @Test func onlyTheWrittenPathsAreRenamed() {
        let args = ["Example", "--export", "out.png", "--replay", "take.json",
                    "--automation", "slow.json", "--seed", "10"]
        let stamped = CaptureSource.stamped(args, with: "a1b2c3d")
        #expect(stamped[2] == "out-a1b2c3d.png")
        #expect(stamped[4] == "take.json")        // an input, read not written
        #expect(stamped[6] == "slow.json")
        #expect(stamped[8] == "10")
    }

    @Test func aFlagWithNoPathIsLeftAlone() {
        let args = ["Example", "--export-usdz", "--frame", "3"]
        #expect(CaptureSource.stamped(args, with: "a1b2c3d") == args)
    }

    @Test func everyWrittenPathIsRenamed() {
        for flag in CaptureSource.outputFlags {
            let stamped = CaptureSource.stamped(["Example", flag, "out.png"], with: "a1b2c3d")
            #expect(stamped[2] == "out-a1b2c3d.png", "\(flag) kept its given name")
        }
    }

    // MARK: - The recipe

    @Test func theRecipeCarriesTheCapture() {
        let metadata = ExportMetadata(randomSeed: 7, noiseSeed: 7, params: [],
                                      gitHash: "8167de3-dirty", frame: 0, fps: 60,
                                      captureCommit: "a1b2c3d")
        #expect(metadata.recipe ==
                #"{"tool":"Ollin","seed":7,"git":"8167de3-dirty","capture":"a1b2c3d","frame":0,"fps":60}"#)
    }

    @Test func withoutACaptureTheRecipeIsUnchanged() {
        let metadata = ExportMetadata(randomSeed: 7, noiseSeed: 7, params: [],
                                      gitHash: "8167de3", frame: 0, fps: 60)
        #expect(metadata.recipe == #"{"tool":"Ollin","seed":7,"git":"8167de3","frame":0,"fps":60}"#)
    }
}
