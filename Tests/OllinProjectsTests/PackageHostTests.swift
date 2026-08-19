import Foundation
import Testing
@testable import OllinProjects

/// Joining a package that is already there.
///
/// This is the one path that changes a file somebody else wrote, so the rules
/// are about restraint: read only what is needed, refuse what cannot work, and
/// when the manifest cannot be understood confidently, leave it alone.
@Suite("Joining a package")
struct PackageHostTests {

    // MARK: - Finding it

    @Test("The nearest manifest above the folder is the one a sketch would join")
    func findsTheNearest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("2026/08")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try manifest(name: "Sketchbook").write(to: root.appendingPathComponent("Package.swift"),
                                               atomically: true, encoding: .utf8)

        let host = try #require(PackageHost.nearest(from: nested))
        #expect(host.name == "Sketchbook")
        #expect(host.linksOllin)
        #expect(host.relativePath(of: nested) == "2026/08")
        // The folder about to be made does not exist yet, which is exactly the
        // case a path comparison gets wrong.
        #expect(host.relativePath(of: nested.appendingPathComponent("Sketch2026001"))
                == "2026/08/Sketch2026001")
    }

    @Test("A folder with no package above it has nothing to join")
    func findsNothing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PackageHost.nearest(from: root, limit: 1) == nil)
    }

    @Test("A package that cannot reach Ollin is recognized as such")
    func noticesAMissingDependency() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try manifest(name: "Elsewhere", linksOllin: false)
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let host = try #require(PackageHost.nearest(from: root))
        #expect(!host.linksOllin)
    }

    // MARK: - Changing it

    @Test("A target lands in the target list, not in a list inside one")
    func insertsInTheRightArray() throws {
        let text = manifest(name: "Sketchbook")
        let updated = try #require(PackageHost.inserting("        .marker,", intoTargetsOf: text))

        // After the existing target, and before the array's own closing line,
        // which keeps its indentation.
        let targets = try #require(updated.range(of: "targets: ["))
        let marker = try #require(updated.range(of: ".marker,"))
        let existing = try #require(updated.range(of: "name: \"Existing\""))
        #expect(targets.upperBound < existing.lowerBound)
        #expect(existing.upperBound < marker.lowerBound)
        #expect(updated.contains("\n    ],"))
        // A target's own `dependencies: [ ... ]` must not be mistaken for the end.
        #expect(!updated.contains(".product(name: \"Ollin\", package: \"Ollin\")]        .marker,"))
    }

    @Test("A manifest it cannot read is left alone")
    func refusesWhatItCannotRead() {
        #expect(PackageHost.inserting("x", intoTargetsOf: "let package = Package(name: \"A\")") == nil)
        #expect(PackageHost.inserting("x", intoTargetsOf: "targets: no bracket here") == nil)
    }

    // MARK: - Generating into it

    @Test("The sketch is new files plus exactly one edit")
    func plansAFolderAndAnEdit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("2026/08")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try manifest(name: "Sketchbook").write(to: root.appendingPathComponent("Package.swift"),
                                               atomically: true, encoding: .utf8)

        var request = self.request(name: "Sketch2026001", in: nested)
        request.kind = .inPackage
        let project = try ProjectGenerator.plan(request)

        #expect(project.files.map(\.path) == ["Sketch2026001/Sketch.swift"])
        #expect(project.edits.count == 1)
        let edit = try #require(project.edits.first)
        #expect(edit.file == root.appendingPathComponent("Package.swift"))
        #expect(edit.updated.contains("name: \"Sketch2026001\""))
        // The target's path is where the folders actually put it.
        #expect(edit.updated.contains("path: \"2026/08/Sketch2026001\""))
    }

    @Test("A package that cannot reach Ollin is refused, with the reason")
    func refusesAPackageWithoutOllin() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try manifest(name: "Elsewhere", linksOllin: false)
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        var request = self.request(name: "Thing", in: root)
        request.kind = .inPackage
        #expect(throws: ProjectGeneratorError.self) { _ = try ProjectGenerator.plan(request) }

        let host = try #require(PackageHost.nearest(from: root))
        #expect(ProjectGeneratorError.packageDoesNotLinkOllin(host).description.contains("does not depend on Ollin"))
    }

    @Test("Writing applies the edit as well as the new files")
    func writingChangesTheManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifestURL = root.appendingPathComponent("Package.swift")
        try manifest(name: "Sketchbook").write(to: manifestURL, atomically: true, encoding: .utf8)

        var request = self.request(name: "Nightfall", in: root)
        request.kind = .inPackage
        try ProjectGenerator.write(try ProjectGenerator.plan(request))

        let after = try String(contentsOf: manifestURL, encoding: .utf8)
        #expect(after.contains("name: \"Nightfall\""))
        #expect(after.contains("name: \"Existing\""))     // nothing was replaced
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Nightfall/Sketch.swift").path))
    }

    // MARK: - Support

    private func manifest(name: String, linksOllin: Bool = true) -> String {
        let dependency = linksOllin
            ? "        .package(path: \"/somewhere/Ollin\"),"
            : "        .package(url: \"https://example.com/Other.git\", branch: \"main\"),"
        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(name)",
            platforms: [.macOS("26.0")],
            dependencies: [
        \(dependency)
            ],
            targets: [
                .executableTarget(
                    name: "Existing",
                    dependencies: [.product(name: "Ollin", package: "Ollin")],
                    path: "sketches/Existing"
                ),
            ],
            swiftLanguageModes: [.v6]
        )
        """
    }

    private func request(name: String, in folder: URL) -> ProjectRequest {
        ProjectRequest(name: name, destination: folder,
                       framework: .localPath(URL(fileURLWithPath: "/somewhere/Ollin")))
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
