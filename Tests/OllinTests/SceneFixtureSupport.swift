import Foundation
@testable import Ollin

/// A USD text fixture read as a `Scene` without touching the disk: the same
/// walk `Scene(contentsOf:)` runs on a `.usda` file (the node tree, the lights
/// and cameras, the animation, the skinning), fed the text's bytes. `nil` where
/// the text does not parse or holds no prims, which is what `Scene(contentsOf:)`
/// throws on.
///
/// The fixtures here name no outside asset, so the file URL the reader would
/// resolve them beside is a stand-in.
func loadUSDScene(_ usda: String) -> Ollin.Scene? {
    Scene.loadUSDScene(data: Data(usda.utf8), fileURL: sceneFixtureURL(extension: "usda"))
}

/// A glTF text fixture read as a `Scene` without touching the disk, the way
/// `Scene(contentsOf:)` reads a `.gltf` file. Buffers are the fixture's own
/// data URIs; an external buffer would be looked for beside the stand-in URL
/// and refused.
func loadGLTFScene(_ json: String) -> Ollin.Scene? {
    guard let document = GLTFDocument(data: Data(json.utf8), isBinary: false,
                                      baseDirectory: sceneFixtureURL(extension: "gltf").deletingLastPathComponent())
    else { return nil }
    return Scene.loadGLTFScene(document)
}

/// Where a fixture would live if it were a file: nowhere, under a folder that
/// does not exist, so a reader that reaches for a sibling asset finds nothing.
private func sceneFixtureURL(extension ext: String) -> URL {
    URL(fileURLWithPath: "/nonexistent/ollin-scene-fixtures/fixture.\(ext)")
}
