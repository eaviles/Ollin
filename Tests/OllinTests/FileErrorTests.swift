@testable import Ollin
import Foundation
import Testing

/// Every loader that takes a file, a resource, or bytes fails one way: it
/// throws a `FileError`, `missing` for a file or resource that is not there and
/// `unreadable` for bytes that are not what it reads, where it used to answer
/// `nil` for both. The writers throw `unwritable`. One law per loader family.
@Suite
@MainActor
struct FileErrorTests {

    private let nowhere = "/nonexistent-\(UUID().uuidString)/file"

    private func missing(_ ext: String, _ load: (String) throws -> Void) {
        let path = nowhere + "." + ext
        let error = #expect(throws: FileError.self) { try load(path) }
        #expect(error?.kind == .missing, "\(ext): \(String(describing: error))")
        #expect(error?.path == path)
    }

    private func unreadable(_ ext: String, _ load: (String) throws -> Void) throws {
        let path = NSTemporaryDirectory() + "ollin-garbage-\(UUID().uuidString).\(ext)"
        try Data("this is not a \(ext) file \u{1}\u{2}".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let error = #expect(throws: FileError.self) { try load(path) }
        #expect(error?.kind == .unreadable, "\(ext): \(String(describing: error))")
        #expect(error?.path == path)
    }

    private final class Plain: Sketch {
        override func draw() {}
    }

    @Test func aMissingFileIsMissingAndNamesItsPath() {
        let sketch = Plain()
        missing("png") { _ = try sketch.loadImage($0) }
        missing("obj") { _ = try sketch.loadMesh($0) }
        missing("gltf") { _ = try sketch.loadScene($0) }
        missing("svg") { _ = try sketch.loadSVG($0) }
        missing("hex") { _ = try sketch.loadPalette($0) }
        missing("hex") { _ = try sketch.loadPalettes($0) }
        missing("csv") { _ = try sketch.loadTable($0) }
        missing("json") { _ = try sketch.loadJSON($0) }
        missing("ies") { _ = try IESProfile(contentsOf: URL(fileURLWithPath: $0)) }
        missing("icc") { _ = try ICCProfile(contentsOf: URL(fileURLWithPath: $0)) }
        missing("ttf") { _ = try OutlineFont(path: $0) }
        missing("bdf") { _ = try BitmapFont(bdfContentsOf: URL(fileURLWithPath: $0)) }
        missing("fnt") { _ = try BitmapFont(fntContentsOf: URL(fileURLWithPath: $0)) }
        missing("jhf") { _ = try StrokeFont(jhfContentsOf: URL(fileURLWithPath: $0)) }
        missing("metal") { _ = try ComputeKernel(entry: "k", contentsOf: URL(fileURLWithPath: $0)) }
    }

    @Test func bytesThatAreNotTheFormatAreUnreadable() throws {
        let sketch = Plain()
        try unreadable("png") { _ = try sketch.loadImage($0) }
        try unreadable("obj") { _ = try sketch.loadMesh($0) }
        try unreadable("usda") { _ = try sketch.loadScene($0) }
        try unreadable("svg") { _ = try sketch.loadSVG($0) }
        try unreadable("json") { _ = try sketch.loadJSON($0) }
        try unreadable("ies") { _ = try IESProfile(contentsOf: URL(fileURLWithPath: $0)) }
        try unreadable("icc") { _ = try ICCProfile(contentsOf: URL(fileURLWithPath: $0)) }
        try unreadable("ttf") { _ = try OutlineFont(path: $0) }
        try unreadable("bdf") { _ = try BitmapFont(bdfContentsOf: URL(fileURLWithPath: $0)) }
        try unreadable("jhf") { _ = try StrokeFont(jhfContentsOf: URL(fileURLWithPath: $0)) }
        // A file whose extension no mesh reader takes is unreadable, and says which it takes.
        try unreadable("xyz") { _ = try Mesh(path: $0) }
    }

    @Test func aResourceTheBundleLacksIsMissingAndNamesIt() {
        for load in [
            { _ = try Image(resource: "no-such-picture", withExtension: "png", in: .main) },
            { _ = try Mesh(resource: "no-such-model", withExtension: "obj", in: .main) },
            { _ = try Scene(resource: "no-such-scene", withExtension: "gltf", in: .main) },
            { _ = try SVG(resource: "no-such-drawing", in: .main) },
            { _ = try Table(resource: "no-such-table", in: .main) },
            { _ = try JSON(resource: "no-such-document", in: .main) },
        ] as [() throws -> Void] {
            let error = #expect(throws: FileError.self) { try load() }
            #expect(error?.kind == .missing)
            #expect(error?.path?.hasPrefix("no-such-") == true)
        }
    }

    @Test func bytesInHandThatAreNotTheFormatAreUnreadableWithNoPath() {
        let garbage = Data("garbage \u{1}".utf8)
        for load in [
            { _ = try Image(data: garbage) },
            { _ = try SVG(data: garbage) },
            { _ = try JSON(data: garbage) },
            { _ = try Palette(data: Data()) },
            { _ = try Table(text: "") },
            { _ = try IESProfile(data: garbage) },
            { _ = try ICCProfile(data: garbage) },
            { _ = try OutlineFont(data: garbage) },
            { _ = try Mesh(objSource: "# no faces") },
        ] as [() throws -> Void] {
            let error = #expect(throws: FileError.self) { try load() }
            #expect(error?.kind == .unreadable)
            #expect(error?.path == nil)
        }
    }

    @Test func theWritersThrowUnwritable() {
        let mesh = Mesh.icosphere(radius: 1, subdivisions: 1)
        let unknown = NSTemporaryDirectory() + "ollin-\(UUID().uuidString).gcode"
        let format = #expect(throws: FileError.self) { try mesh.write(to: unknown) }
        #expect(format?.kind == .unwritable)
        #expect(!FileManager.default.fileExists(atPath: unknown))
        let folderless = nowhere + ".stl"
        let place = #expect(throws: FileError.self) { try mesh.write(to: folderless) }
        #expect(place?.kind == .unwritable)
        let scene = #expect(throws: FileError.self) {
            try Scene(nodes: [SceneNode(name: "a", mesh: mesh)]).write(to: nowhere + ".usdz")
        }
        #expect(scene?.kind == .unwritable)
    }

    @Test func theSentenceNamesTheFileAndTheProblem() {
        let error = FileError(.missing, path: "/a/b.png", problem: "no such file")
        #expect(error.description == "/a/b.png: no such file")
        #expect(error.localizedDescription == "/a/b.png: no such file")
        #expect(FileError(.unreadable, path: nil, problem: "not JSON").description == "not JSON")
    }
}
