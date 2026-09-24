import Compression
import Foundation
@testable import Ollin
#if canImport(ModelIO)
import ModelIO
#endif

/// A small glTF that reaches every accessor reader: a quad with normals, uvs,
/// quantized vertex colors, tangents, and a skin, a second primitive with
/// 32-bit indices and no normals (so the smooth-normal pass runs), a sparse
/// morph target, a textured material whose picture sits in the buffer, an
/// animation of translation, rotation, and morph weight, a camera, and a
/// light. `text` carries the buffer as a data URI, `binary` is the same scene
/// as a `.glb`.
enum GLTFSeed {

    struct Seed {
        var text: String
        var binary: [UInt8]
    }

    static func make() -> Seed {
        var buffer = Data()
        var views: [String] = []
        func view(_ bytes: Data) -> Int {
            while buffer.count % 4 != 0 { buffer.append(0) }
            views.append(#"{"buffer": 0, "byteOffset": \#(buffer.count), "byteLength": \#(bytes.count)}"#)
            buffer.append(bytes)
            return views.count - 1
        }
        func floats(_ values: [Float]) -> Data {
            var d = Data()
            for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
            return d
        }
        func ints<T: FixedWidthInteger>(_ values: [T]) -> Data {
            var d = Data()
            for v in values { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            return d
        }
        let positions = view(floats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]))
        let normals = view(floats([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]))
        let uvs = view(floats([0, 0, 1, 0, 1, 1, 0, 1]))
        let colors = view(ints([UInt8](arrayLiteral: 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 128, 255, 255, 255, 255)))
        let tangents = view(floats([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, -1, 1, 0, 0, 1]))
        let joints = view(ints([UInt8](arrayLiteral: 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)))
        let weights = view(floats([1, 0, 0, 0, 0.5, 0.5, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]))
        let indices16 = view(ints([UInt16](arrayLiteral: 0, 1, 2, 0, 2, 3)))
        let indices32 = view(ints([UInt32](arrayLiteral: 0, 2, 3)))
        let sparseIndex = view(ints([UInt8](arrayLiteral: 2)))
        let sparseValue = view(floats([0, 0, 0.5]))
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let inverseBind = view(floats(identity + [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 1]))
        let times = view(floats([0, 0.5, 1]))
        let moves = view(floats([0, 0, 0, 0.5, 0, 0, 1, 0.5, 0]))
        let turns = view(floats([0, 0, 0, 1, 0, 0, 0.3826834, 0.9238795, 0, 0, 0.7071068, 0.7071068]))
        let blend = view(floats([0, 1, 0.25]))
        let picture = view(Data(ModelFileMutationTests.png()))

        let json = """
        {"asset": {"version": "2.0"}, "scene": 0,
         "scenes": [{"name": "seed", "nodes": [0, 3]}],
         "nodes": [
          {"name": "body", "mesh": 0, "skin": 0, "children": [1, 2], "translation": [0, 1, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1], "weights": [0.5]},
          {"name": "root", "translation": [0, 0, 0]},
          {"name": "tip", "matrix": [1,0,0,0, 0,1,0,0, 0,0,1,0, 1,0,0,1], "camera": 0},
          {"name": "lamp", "translation": [2, 3, 4], "extensions": {"KHR_lights_punctual": {"light": 0}}}],
         "meshes": [{"primitives": [
            {"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "COLOR_0": 3, "TANGENT": 4, "JOINTS_0": 5, "WEIGHTS_0": 6},
             "indices": 7, "material": 0, "mode": 4, "targets": [{"POSITION": 9}]},
            {"attributes": {"POSITION": 0, "TEXCOORD_0": 2, "JOINTS_0": 5, "WEIGHTS_0": 6}, "indices": 8, "material": 1,
             "targets": [{"POSITION": 9}]}],
           "weights": [0.25]}],
         "skins": [{"joints": [1, 2], "inverseBindMatrices": 10}],
         "accessors": [
          {"bufferView": \(positions), "componentType": 5126, "count": 4, "type": "VEC3", "min": [0,0,0], "max": [1,1,0]},
          {"bufferView": \(normals), "componentType": 5126, "count": 4, "type": "VEC3"},
          {"bufferView": \(uvs), "componentType": 5126, "count": 4, "type": "VEC2"},
          {"bufferView": \(colors), "componentType": 5121, "normalized": true, "count": 4, "type": "VEC4"},
          {"bufferView": \(tangents), "componentType": 5126, "count": 4, "type": "VEC4"},
          {"bufferView": \(joints), "componentType": 5121, "count": 4, "type": "VEC4"},
          {"bufferView": \(weights), "componentType": 5126, "count": 4, "type": "VEC4"},
          {"bufferView": \(indices16), "componentType": 5123, "count": 6, "type": "SCALAR"},
          {"bufferView": \(indices32), "componentType": 5125, "count": 3, "type": "SCALAR"},
          {"componentType": 5126, "count": 4, "type": "VEC3",
           "sparse": {"count": 1, "indices": {"bufferView": \(sparseIndex), "componentType": 5121},
                      "values": {"bufferView": \(sparseValue)}}},
          {"bufferView": \(inverseBind), "componentType": 5126, "count": 2, "type": "MAT4"},
          {"bufferView": \(times), "componentType": 5126, "count": 3, "type": "SCALAR"},
          {"bufferView": \(moves), "componentType": 5126, "count": 3, "type": "VEC3"},
          {"bufferView": \(turns), "componentType": 5126, "count": 3, "type": "VEC4"},
          {"bufferView": \(blend), "componentType": 5126, "count": 3, "type": "SCALAR"}],
         "bufferViews": [\(views.joined(separator: ", "))],
         "buffers": [BUFFER],
         "materials": [
          {"name": "painted", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.4, 0.2, 1], "baseColorTexture": {"index": 0},
             "metallicFactor": 0.2, "roughnessFactor": 0.6}, "normalTexture": {"index": 0, "scale": 1.5},
           "occlusionTexture": {"index": 0}, "emissiveFactor": [0.1, 0.1, 0], "emissiveTexture": {"index": 0}},
          {"name": "plain", "pbrMetallicRoughness": {"baseColorFactor": [0.2, 0.2, 0.9, 0.5]}}],
         "textures": [{"source": 0}],
         "images": [{"bufferView": \(picture), "mimeType": "image/png"}],
         "cameras": [{"type": "perspective", "perspective": {"yfov": 0.8, "znear": 0.1, "zfar": 100, "aspectRatio": 1.5}}],
         "extensions": {"KHR_lights_punctual": {"lights": [{"type": "spot", "color": [1, 0.9, 0.8], "intensity": 20, "range": 10,
            "spot": {"innerConeAngle": 0.2, "outerConeAngle": 0.6}}]}},
         "animations": [{"name": "sway", "samplers": [
            {"input": 11, "output": 12, "interpolation": "LINEAR"},
            {"input": 11, "output": 13, "interpolation": "STEP"},
            {"input": 11, "output": 14}],
          "channels": [{"sampler": 0, "target": {"node": 2, "path": "translation"}},
                       {"sampler": 1, "target": {"node": 1, "path": "rotation"}},
                       {"sampler": 2, "target": {"node": 0, "path": "weights"}}]}]}
        """
        let text = json.replacingOccurrences(
            of: "BUFFER",
            with: #"{"uri": "data:application/octet-stream;base64,\#(buffer.base64EncodedString())", "byteLength": \#(buffer.count)}"#)

        var chunk = Array(json.replacingOccurrences(of: "BUFFER", with: #"{"byteLength": \#(buffer.count)}"#).utf8)
        while chunk.count % 4 != 0 { chunk.append(0x20) }
        var bin = [UInt8](buffer)
        while bin.count % 4 != 0 { bin.append(0) }
        var glb: [UInt8] = []
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { glb.append(contentsOf: $0) } }
        glb += Array("glTF".utf8)
        u32(2)
        u32(12 + 8 + chunk.count + 8 + bin.count)
        u32(chunk.count); glb += Array("JSON".utf8); glb += chunk
        u32(bin.count); glb += Array("BIN".utf8) + [0]; glb += bin
        return Seed(text: text, binary: glb)
    }
}

/// The USD seeds: a text stage with a skinned, blend-shaped arm, an animated
/// transform, a camera, a light, and a textured mesh with a bound preview
/// material; a crate written by Model I/O; and a package holding a layer and
/// the picture its material names.
enum USDSeed {

    static let text = """
    #usda 1.0
    (
        defaultPrim = "World"
        metersPerUnit = 0.01
        upAxis = "Y"
        startTimeCode = 0
        endTimeCode = 24
        timeCodesPerSecond = 24
    )

    def Xform "World"
    {
        double3 xformOp:translate.timeSamples = {
            0: (0, 0, 0),
            24: (1, 2, 3),
        }
        float3 xformOp:rotateXYZ = (10, 20, 30)
        float3 xformOp:scale = (1, 2, 1)
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ", "xformOp:scale"]

        def Camera "Eye"
        {
            float focalLength = 35
            float horizontalAperture = 36
            float verticalAperture = 24
            float2 clippingRange = (0.1, 1000)
            matrix4d xformOp:transform = ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 1, 10, 1))
            uniform token[] xformOpOrder = ["xformOp:transform"]
        }

        def SphereLight "Lamp"
        {
            float inputs:intensity = 30
            float inputs:radius = 0.5
            color3f inputs:color = (1, 0.8, 0.6)
            double3 xformOp:translate = (0, 5, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]
        }

        def Mesh "Tile" (
            prepend apiSchemas = ["MaterialBindingAPI"]
        )
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (2, 1, 0)]
            int[] faceVertexCounts = [4, 3]
            int[] faceVertexIndices = [0, 1, 2, 3, 1, 4, 2]
            normal3f[] normals = [(0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1)] (
                interpolation = "vertex"
            )
            texCoord2f[] primvars:st = [(0, 0), (1, 0), (1, 1), (0, 1)] (
                interpolation = "faceVarying"
            )
            int[] primvars:st:indices = [0, 1, 2, 3, 1, 2, 3]
            rel material:binding = </World/Looks/Paint>
        }

        def Scope "Looks"
        {
            def Material "Paint"
            {
                token outputs:surface.connect = </World/Looks/Paint/Surface.outputs:surface>

                def Shader "Surface"
                {
                    uniform token info:id = "UsdPreviewSurface"
                    color3f inputs:diffuseColor.connect = </World/Looks/Paint/Picture.outputs:rgb>
                    float inputs:roughness = 0.4
                    float inputs:metallic = 0.1
                    token outputs:surface
                }

                def Shader "Picture"
                {
                    uniform token info:id = "UsdUVTexture"
                    asset inputs:file = @picture.png@
                    token inputs:wrapS = "repeat"
                    float3 outputs:rgb
                }
            }
        }

        def SkelRoot "Model" (
            prepend apiSchemas = ["SkelBindingAPI"]
        )
        {
            def Skeleton "Skel" (
                prepend apiSchemas = ["SkelBindingAPI"]
            )
            {
                uniform token[] joints = ["Base", "Base/Tip"]
                uniform matrix4d[] bindTransforms = [((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)), ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 1, 0, 1))]
                uniform matrix4d[] restTransforms = [((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)), ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 1, 0, 1))]
                rel skel:animationSource = </World/Model/Skel/Anim>

                def SkelAnimation "Anim"
                {
                    uniform token[] joints = ["Base/Tip"]
                    float3[] translations.timeSamples = {
                        0: [(0, 1, 0)],
                        24: [(0, 1, 0)],
                    }
                    quatf[] rotations.timeSamples = {
                        0: [(1, 0, 0, 0)],
                        24: [(0.7071068, 0, 0, 0.7071068)],
                    }
                    half3[] scales.timeSamples = {
                        0: [(1, 1, 1)],
                        24: [(1, 1, 1)],
                    }
                    uniform token[] blendShapes = ["bulge"]
                    float[] blendShapeWeights.timeSamples = {
                        0: [0],
                        24: [1],
                    }
                }
            }

            def Mesh "Arm" (
                prepend apiSchemas = ["SkelBindingAPI"]
            )
            {
                point3f[] points = [(-0.2, 0, 0.2), (0.2, 0, 0.2), (0.2, 0, -0.2), (-0.2, 0, -0.2), (-0.2, 2, 0.2), (0.2, 2, 0.2), (0.2, 2, -0.2), (-0.2, 2, -0.2)]
                int[] faceVertexCounts = [4, 4, 4, 4, 4, 4]
                int[] faceVertexIndices = [0, 1, 5, 4, 1, 2, 6, 5, 2, 3, 7, 6, 3, 0, 4, 7, 4, 5, 6, 7, 3, 2, 1, 0]
                rel skel:skeleton = </World/Model/Skel>
                int[] primvars:skel:jointIndices = [0, 0, 0, 0, 1, 1, 1, 1] (
                    elementSize = 1
                    interpolation = "vertex"
                )
                float[] primvars:skel:jointWeights = [1, 1, 1, 1, 1, 1, 1, 1] (
                    elementSize = 1
                    interpolation = "vertex"
                )
                uniform token[] skel:blendShapes = ["bulge"]
                rel skel:blendShapeTargets = [</World/Model/Arm/bulge>]

                def BlendShape "bulge"
                {
                    uniform vector3f[] offsets = [(0.3, 0, 0), (-0.3, 0, 0)]
                    uniform int[] pointIndices = [1, 3]
                }
            }
        }
    }
    """

    #if canImport(ModelIO)
    /// A crate Model I/O writes for a lit, textured box under a camera, or
    /// `nil` where this system cannot write one.
    static func crate(in folder: ScratchFolder) -> [UInt8]? {
        guard MDLAsset.canExportFileExtension("usdc") else { return nil }
        let allocator = MDLMeshBufferDataAllocator()
        let box = MDLMesh(boxWithExtent: SIMD3<Float>(2, 1, 1), segments: SIMD3<UInt32>(1, 1, 1),
                          inwardNormals: false, geometryType: .triangles, allocator: allocator)
        let material = MDLMaterial(name: "paint", scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
        material.setProperty(MDLMaterialProperty(name: "baseColor", semantic: .baseColor,
                                                 float3: SIMD3<Float>(0.8, 0.3, 0.1)))
        box.submeshes?.forEach { ($0 as? MDLSubmesh)?.material = material }
        box.transform = MDLTransform(matrix: simd_float4x4(diagonal: SIMD4(1, 1, 1, 1)))
        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(box)
        let camera = MDLCamera()
        camera.transform = MDLTransform(matrix: simd_float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 5, 1)))
        asset.add(camera)
        let url = folder.url.appendingPathComponent("seed.usdc")
        guard (try? asset.export(to: url)) != nil, let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }
    #else
    static func crate(in folder: ScratchFolder) -> [UInt8]? { nil }
    #endif

    /// A package: the layer first (the one a reader opens) and a picture
    /// beside it, stored without compression as the format asks.
    static func package(layer: [UInt8], named name: String, texture: [UInt8]) -> [UInt8] {
        ZipSeed.stored([(name, layer), ("picture.png", texture)])
    }
}

/// A zip written the plain way: local headers, the data (stored, or deflated
/// where asked), a central directory, and its end record.
enum ZipSeed {

    static func stored(_ entries: [(String, [UInt8])]) -> [UInt8] {
        make(entries.map { ($0.0, $0.1, false) })
    }

    static func make(_ entries: [(name: String, bytes: [UInt8], deflate: Bool)]) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        func u16(_ v: Int, _ into: inout [UInt8]) { into += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int, _ into: inout [UInt8]) {
            into += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        for entry in entries {
            let name = Array(entry.name.utf8)
            let body = entry.deflate ? deflate(entry.bytes) : entry.bytes
            let method = entry.deflate ? 8 : 0
            let crc = crc32(entry.bytes)
            let offset = out.count
            u32(0x0403_4B50, &out); u16(20, &out); u16(0, &out); u16(method, &out); u16(0, &out); u16(0, &out)
            u32(crc, &out); u32(body.count, &out); u32(entry.bytes.count, &out)
            u16(name.count, &out); u16(0, &out)
            out += name + body
            u32(0x0201_4B50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(method, &central)
            u16(0, &central); u16(0, &central); u32(crc, &central); u32(body.count, &central)
            u32(entry.bytes.count, &central); u16(name.count, &central); u16(0, &central); u16(0, &central)
            u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central)
            central += name
        }
        let directory = out.count
        out += central
        u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(entries.count, &out); u16(entries.count, &out)
        u32(central.count, &out); u32(directory, &out); u16(0, &out)
        return out
    }

    static func deflate(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytes.count + 1024)
        let written = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        return Array(out.prefix(written))
    }

    static func crc32(_ bytes: [UInt8]) -> Int {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return Int(crc ^ 0xFFFF_FFFF)
    }
}

/// A binary PLY, little-endian, written by hand: four colored vertices and
/// two triangles.
enum PLYSeed {
    static func binary() -> [UInt8] {
        let header = """
        ply
        format binary_little_endian 1.0
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

        """
        var out = Array(header.utf8)
        let vertices: [(Float, Float, Float, UInt8)] = [(0, 0, 0, 255), (1, 0, 0, 0), (0, 1, 0, 128), (1, 1, 0, 9)]
        for (x, y, z, c) in vertices {
            for f in [x, y, z] { withUnsafeBytes(of: f.bitPattern.littleEndian) { out += $0 } }
            out += [c, 255 - c, 7]
        }
        for face in [[0, 1, 2], [1, 3, 2]] {
            out.append(3)
            for i in face { withUnsafeBytes(of: Int32(i).littleEndian) { out += $0 } }
        }
        return out
    }
}
