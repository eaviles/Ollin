import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import OllinMutation
@testable import Ollin
#if canImport(ModelIO)
import ModelIO
#endif

/// The 3D files a sketch is handed: glTF as text and as a binary container,
/// Wavefront OBJ, PLY and STL, and the USD family in its three containers.
/// Each is read as a merged mesh and as a scene, then read the way `drawScene`
/// reads it: every node's mesh posed by its morph targets and its skin, every
/// animation applied across its length, the bounds taken and the mesh fitted.
///
/// One promise is checked beside the no-trap invariant: a mesh a loader hands out never
/// names a vertex it does not have, since every pass that reads a triangle
/// indexes the positions with those numbers.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct ModelFileMutationTests {

    // MARK: glTF

    @Test func gltfFiles() {
        let seed = GLTFSeed.make()
        var inconsistent = 0
        let text = MutationRun.run("gltf-text", seeds: [seed.text.bytes], count: 300, sweeps: false,
                                   numberSweep: true, allocations: fileBound) { bytes in
            guard let doc = GLTFDocument(data: Data(bytes), isBinary: false,
                                         baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())) else { return false }
            return Self.read(doc, inconsistent: &inconsistent)
        }
        #expect(text.seedsRefused.isEmpty, "\(text)")
        #expect(text.oversizedCount == 0, "\(text)")

        let binary = MutationRun.run("gltf-binary", seeds: [seed.binary], count: 600,
                                     allocations: fileBound) { bytes in
            guard let doc = GLTFDocument(data: Data(bytes), isBinary: true,
                                         baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())) else { return false }
            return Self.read(doc, inconsistent: &inconsistent)
        }
        #expect(binary.seedsRefused.isEmpty, "\(binary)")
        #expect(binary.oversizedCount == 0, "\(binary)")
        #expect(inconsistent == 0, "a loaded mesh named a vertex it does not have")
    }

    static func read(_ doc: GLTFDocument, inconsistent: inout Int) -> Bool {
        let mesh = Mesh.loadGLTF(doc)
        if let mesh { read(mesh, inconsistent: &inconsistent) }
        let scene = Scene.loadGLTFScene(doc)
        if let scene { read(scene, inconsistent: &inconsistent) }
        return mesh != nil && scene != nil
    }

    /// A mesh read the way a sketch reads one: its bounds, fitted, its
    /// tangents made where it has uvs, and every triangle's corners looked up.
    static func read(_ mesh: Mesh, inconsistent: inout Int) {
        guard mesh.indices.allSatisfy({ Int($0) < mesh.positions.count }) else {
            inconsistent += 1
            return
        }
        _ = mesh.bounds
        _ = mesh.normalized(scale: 1)
        if !mesh.uvs.isEmpty { _ = mesh.generatingTangents() }
    }

    /// A scene read the way `drawScene` reads one.
    static func read(_ scene: Scene, inconsistent: inout Int) {
        var scene = scene
        _ = scene.bounds
        _ = scene.cameras
        _ = scene.lights
        let worlds = scene.nodeWorldTransforms()
        func visit(_ node: SceneNode) {
            if let mesh = node.mesh {
                read(mesh, inconsistent: &inconsistent)
                if mesh.indices.allSatisfy({ Int($0) < mesh.positions.count }) {
                    let shaped = node.morphedMesh() ?? mesh
                    if let skin = node.skinIndex, scene.skins.indices.contains(skin) {
                        _ = node.skinnedMesh(shaped, skin: scene.skins[skin], worlds: worlds)
                    }
                    for part in node.meshParts where !part.indices.allSatisfy({ Int($0) < mesh.positions.count }) {
                        inconsistent += 1
                    }
                }
            }
            for child in node.children { visit(child) }
        }
        for node in scene.nodes { visit(node) }
        for animation in scene.animations {
            for time in [-1, 0, animation.duration / 2, animation.duration, animation.duration * 2 + 1] {
                scene.apply(animation, at: time)
            }
        }
    }

    // MARK: OBJ, PLY, STL

    @Test func objFiles() throws {
        let cube = """
        mtllib look.mtl
        o cube
        v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nv 0 0 1\nv 1 0 1\nv 1 1 1\nv 0 1 1
        vt 0 0\nvt 1 0\nvt 1 1\nvt 0 1
        vn 0 0 -1\nvn 0 0 1\nvn 1 0 0
        usemtl paint
        f 1/1/1 2/2/1 3/3/1 4/4/1
        f 5/1/2 6/2/2 7/3/2
        f -4//3 -3//3 -2//3 -1//3
        f 2 3 7 6
        s off
        """
        let material = "newmtl paint\nKd 0.8 0.2 0.1\nmap_Kd -clamp on swatch.png\n"
        let folder = ScratchFolder("obj")
        folder.write(Self.png(), named: "swatch.png")
        var inconsistent = 0
        let text = MutationRun.run("obj-text", seeds: [cube.bytes], count: 600, numberSweep: true,
                                   allocations: fileBound) { bytes in
            guard let mesh = try? Mesh(objSource: String(decoding: bytes, as: UTF8.self)) else { return false }
            Self.read(mesh, inconsistent: &inconsistent)
            return true
        }
        #expect(text.seedsRefused.isEmpty, "\(text)")
        #expect(text.oversizedCount == 0, "\(text)")

        let objURL = folder.write(cube.bytes, named: "model.obj")
        let mtl = MutationRun.run("obj-material", seeds: [material.bytes], count: 200, numberSweep: true,
                                  allocations: fileBound) { bytes in
            folder.write(bytes, named: "look.mtl")
            guard let mesh = try? Mesh(contentsOf: objURL) else { return false }
            Self.read(mesh, inconsistent: &inconsistent)
            return mesh.material != nil
        }
        #expect(mtl.seedsRefused.isEmpty, "\(mtl)")
        #expect(mtl.oversizedCount == 0, "\(mtl)")
        #expect(inconsistent == 0, "a loaded mesh named a vertex it does not have")
    }

    #if canImport(ModelIO)
    /// PLY as text and as binary, and binary STL, the formats read through
    /// Model I/O. Each case is a file on disk, since that is all Model I/O
    /// opens, so a run is one format.
    @Test(arguments: ["ply-text", "ply-binary", "stl-binary"])
    func plyAndStlFiles(_ name: String) throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 4
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face 2
        property list uchar int vertex_indices
        end_header
        0 0 0 255 0 0
        1 0 0 0 255 0
        0 1 0 0 0 255
        1 1 0 9 9 9
        3 0 1 2
        3 1 3 2

        """
        let triangle = Mesh(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 1)],
                            indices: [0, 1, 2, 1, 3, 2])
        let folder = ScratchFolder(name)
        let stl = try #require(triangle.data(as: .stl))
        let (ext, seed, numbers): (String, [UInt8], Bool) = switch name {
        case "ply-text": ("ply", ply.bytes, true)
        case "ply-binary": ("ply", PLYSeed.binary(), true)
        default: ("stl", [UInt8](stl), false)
        }
        var inconsistent = 0
        let report = MutationRun.run(name, seeds: [seed], count: 120, sweeps: !numbers, numberSweep: numbers,
                                     allocations: fileBound) { bytes in
            let url = folder.write(bytes, named: "case.\(ext)")
            guard let mesh = try? Mesh(contentsOf: url) else { return false }
            Self.read(mesh, inconsistent: &inconsistent)
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
        #expect(inconsistent == 0, "a loaded mesh named a vertex it does not have")
    }
    #endif

    // MARK: USD

    @Test func usdText() throws {
        // The seed's prims carry every shape of statement the loader reads: a
        // skinned and blend-shaped arm, an animated transform, a camera, a
        // light, and a textured mesh with a bound preview material.
        let folder = ScratchFolder("usd-text")
        var inconsistent = 0
        let report = MutationRun.run("usd-text", seeds: [USDSeed.text.bytes], count: 400, sweeps: false,
                                     numberSweep: true, allocations: fileBound) { bytes in
            Self.readUSD(bytes, at: folder.url.appendingPathComponent("case.usda"), inconsistent: &inconsistent)
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
        #expect(inconsistent == 0, "a loaded mesh named a vertex it does not have")
    }

    /// A crate reaches far past its size by design (LZ4 and the integer coding
    /// together pack a thousand values into a byte), so its bound is wider.
    static let crateBound = AllocationBound(perInputByte: 4096)

    @Test func usdCrate() throws {
        let folder = ScratchFolder("usd-crate")
        let crate = try #require(USDSeed.crate(in: folder), "Model I/O would not write a crate here")
        var inconsistent = 0
        let report = MutationRun.run("usd-crate", seeds: [crate], count: 300, allocations: Self.crateBound) { bytes in
            Self.readUSD(bytes, at: folder.url.appendingPathComponent("case.usdc"), inconsistent: &inconsistent)
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
        #expect(inconsistent == 0, "a loaded mesh named a vertex it does not have")
    }

    @Test func usdPackage() throws {
        let folder = ScratchFolder("usd-package")
        let crate = try #require(USDSeed.crate(in: folder), "Model I/O would not write a crate here")
        let package = USDSeed.package(layer: crate, named: "scene.usdc", texture: Self.png())
        var inconsistent = 0
        let report = MutationRun.run("usd-package", seeds: [package], count: 300, allocations: Self.crateBound) { bytes in
            Self.readUSD(bytes, at: folder.url.appendingPathComponent("case.usdz"), inconsistent: &inconsistent)
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
        #expect(inconsistent == 0, "a loaded mesh named a vertex it does not have")
    }

    static func readUSD(_ bytes: [UInt8], at url: URL, inconsistent: inout Int) -> Bool {
        guard let stage = try? USDStage.load(data: Data(bytes)) else { return false }
        stage.visitPrims { prim, _ in _ = prim.localXform() }
        guard let scene = Scene.loadUSDScene(data: Data(bytes), fileURL: url) else { return false }
        read(scene, inconsistent: &inconsistent)
        if let mesh = Mesh.merged(scene) { read(mesh, inconsistent: &inconsistent) }
        return true
    }

    // MARK: Seeds

    /// A one-pixel PNG, the smallest picture ImageIO writes.
    static func png() -> [UInt8] {
        let data = NSMutableData()
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = { context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
                            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
                            return context.makeImage() }(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return [] }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return [UInt8](data as Data)
    }
}
