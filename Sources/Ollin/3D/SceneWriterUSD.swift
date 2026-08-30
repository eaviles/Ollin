import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import simd

// The writing half of USD, the mirror of the reading half in `SceneLoaderUSD`
// and its siblings. A `Scene` goes out as a `.usda` layer: meshes as UsdGeomMesh
// prims under the node tree that placed them, surfaces as UsdPreviewSurface
// materials, and the scene's cameras and lights as UsdGeomCamera and UsdLux
// prims.
//
// Every mapping here is stated as the inverse of the one the reader does, and
// the tests hold the two against each other, because a writer that drifts from
// its reader is wrong in a way nothing else notices:
//
//   colors        sRGB → linear            (the reader re-encodes linear → sRGB)
//   camera fov    focal = aperture / 2tan(fov/2)   (reader: fov = 2 atan(aperture / 2 focal))
//   ortho height  verticalAperture = height × 10   (reader: height = aperture / 10)
//   spot cone     half-angle in degrees            (reader doubles it into coneAngle)
//   texture v     1 - v                            (the reader flips it back)
//
// What the format cannot hold, the writer says out loud rather than dropping
// quietly: a finish USD has no slot for, an animation, a skin. `notes` collects
// those for the caller to print once.

/// Serializes a `Scene` as a `.usda` text layer, collecting the image files a
/// package would carry alongside it.
struct USDSceneWriter {

    /// How many meters one scene unit stands for, written into the layer.
    var metersPerUnit: Double = 1
    /// Whether images can travel with the layer. A `.usdz` package holds them;
    /// a bare `.usda` is one text file with nowhere to put them.
    var carriesTextures: Bool = false

    /// The image files the layer refers to, named relative to it. Filled while
    /// serializing; empty unless `carriesTextures`.
    private(set) var textures: [(name: String, data: Data)] = []

    /// What the scene held that the format could not, one line each.
    private(set) var notes: [String] = []

    // Name bookkeeping: prim names must be identifiers and unique among their
    // siblings, and every material is written once and referred to by path.
    private var materials: [(key: String, path: String)] = []
    private var materialsUSDA: [String] = []
    private var textureIDs: [ObjectIdentifier: String] = [:]
    // Distinct textures numbered in the order they are met. An identity hash
    // would do for telling them apart, but it is seeded per process and could
    // in principle collide, and neither belongs in something that decides
    // whether two surfaces are the same material.
    private var textureOrdinals: [ObjectIdentifier: Int] = [:]

    // MARK: - The layer

    /// `scene` as a complete `.usda` layer.
    mutating func layer(for scene: Scene) -> String {
        let root = Self.identifier(scene.name ?? "Scene", fallback: "Scene")

        if !scene.animations.isEmpty {
            note("\(scene.animations.count) animation\(scene.animations.count == 1 ? "" : "s") stayed behind: a spatial export writes one pose, not a timeline.")
        }
        if !scene.skins.isEmpty {
            note("a skinned figure exported in the pose it is holding, not with its skeleton.")
        }

        // The tree first, so every material a mesh needs exists by the time the
        // Materials scope is written out below it.
        var body = ""
        var used = Set<String>()
        for node in scene.nodes {
            body += primitiveTree(node, at: "/\(root)", depth: 1, used: &used)
        }
        for (i, camera) in scene.cameras.enumerated() {
            body += cameraPrim(camera, name: unique("camera\(i)", in: &used), depth: 1)
        }
        for (i, light) in scene.lights.enumerated() {
            body += lightPrim(light, name: unique("light\(i)", in: &used), depth: 1)
        }
        if !materialsUSDA.isEmpty {
            body += " def Scope \"Materials\"\n {\n"
            body += materialsUSDA.joined()
            body += " }\n"
        }

        return """
        #usda 1.0
        (
            defaultPrim = "\(root)"
            doc = "Exported by Ollin \(OllinVersion.current)"
            metersPerUnit = \(num(metersPerUnit))
            upAxis = "Y"
        )

        def Xform "\(root)"
        {
        \(body)}

        """
    }

    /// Deduped: several maps on one material hit the same "textures can't
    /// travel in a bare layer" note, and once says it.
    private mutating func note(_ text: String) {
        guard !notes.contains(text) else { return }
        notes.append(text)
    }

    // MARK: - Nodes and meshes

    /// One node and its children, as an Xform holding a Mesh when it has
    /// geometry. A node's per-material slices become one Mesh prim each, which
    /// is how `drawScene` draws them too.
    private mutating func primitiveTree(_ node: SceneNode, at parent: String, depth: Int,
                                        used: inout Set<String>) -> String {
        let pad = String(repeating: " ", count: depth)
        let name = unique(Self.identifier(node.name, fallback: "node"), in: &used)
        let path = "\(parent)/\(name)"
        var out = "\(pad)def Xform \"\(name)\"\n\(pad){\n"

        if node.localTransform != matrix_identity_float4x4 {
            out += "\(pad) matrix4d xformOp:transform = \(matrix(node.localTransform))\n"
            out += "\(pad) uniform token[] xformOpOrder = [\"xformOp:transform\"]\n"
        }

        if let mesh = node.mesh, !mesh.isEmpty {
            var inner = Set<String>()
            if node.meshParts.isEmpty || node.partsVertexCount != mesh.positions.count {
                out += meshPrim(mesh, indices: mesh.indices, material: mesh.material,
                                name: unique("mesh", in: &inner), at: path, depth: depth + 1)
            } else {
                for (i, part) in node.meshParts.enumerated() {
                    out += meshPrim(mesh, indices: part.indices, material: part.material,
                                    name: unique("mesh\(i)", in: &inner), at: path,
                                    depth: depth + 1)
                }
            }
        }

        var childNames = Set<String>()
        for child in node.children {
            out += primitiveTree(child, at: path, depth: depth + 1, used: &childNames)
        }
        return out + "\(pad)}\n"
    }

    /// A mesh prim: its points, its triangles, and whatever per-vertex data it
    /// carries.
    private mutating func meshPrim(_ mesh: Mesh, indices: [UInt32], material: MeshMaterial?,
                                   name: String, at parent: String, depth: Int) -> String {
        let pad = String(repeating: " ", count: depth)
        var out = "\(pad)def Mesh \"\(name)\"\n"
        if material != nil {
            // A prim that binds a material must say it has a binding, which the
            // spec's own validator is strict about.
            out += "\(pad)(\n\(pad) prepend apiSchemas = [\"MaterialBindingAPI\"]\n\(pad))\n"
        }
        out += "\(pad){\n"

        // Without this a Mesh is a subdivision cage by default, and the model
        // arrives smoothed and shrunken in every viewer that honors the schema.
        out += "\(pad) uniform token subdivisionScheme = \"none\"\n"
        out += "\(pad) point3f[] points = \(tuples(mesh.positions.map { [$0.x, $0.y, $0.z] }))\n"
        out += "\(pad) int[] faceVertexCounts = [\(Array(repeating: "3", count: indices.count / 3).joined(separator: ", "))]\n"
        out += "\(pad) int[] faceVertexIndices = [\(indices.map(String.init).joined(separator: ", "))]\n"

        if mesh.normals.count == mesh.positions.count {
            out += "\(pad) normal3f[] normals = \(tuples(mesh.normals.map { [$0.x, $0.y, $0.z] })) ("
            out += "\n\(pad)  interpolation = \"vertex\"\n\(pad) )\n"
        }
        if mesh.uvs.count == mesh.positions.count {
            // The reader flips v back on the way in; this is that flip.
            out += "\(pad) texCoord2f[] primvars:st = \(tuples(mesh.uvs.map { [$0.x, 1 - $0.y] })) ("
            out += "\n\(pad)  interpolation = \"vertex\"\n\(pad) )\n"
        }
        if mesh.colors.count == mesh.positions.count {
            let linear = mesh.colors.map { c -> [Double] in
                [Color.srgbToLinear(c.red), Color.srgbToLinear(c.green), Color.srgbToLinear(c.blue)]
            }
            out += "\(pad) color3f[] primvars:displayColor = \(tuples(linear)) ("
            out += "\n\(pad)  interpolation = \"vertex\"\n\(pad) )\n"
        }

        let bounds = extent(of: mesh.positions)
        out += "\(pad) float3[] extent = \(tuples(bounds))\n"

        if let material {
            let path = materialPath(material, hint: "\(parent)/\(name)",
                                    perVertexColor: mesh.colors.count == mesh.positions.count)
            out += "\(pad) rel material:binding = <\(path)>\n"
        }
        return out + "\(pad)}\n"
    }

    /// The min and max corners of a point set, the bounds a viewer frames the
    /// model by.
    private func extent(of positions: [Vector3]) -> [[Double]] {
        guard var lo = positions.first, var hi = positions.first else { return [[0, 0, 0], [0, 0, 0]] }
        for p in positions {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        return [[lo.x, lo.y, lo.z], [hi.x, hi.y, hi.z]]
    }

    // MARK: - Materials

    /// The path of the material prim for `material`, written once and shared by
    /// every mesh wearing the same one.
    private mutating func materialPath(_ material: MeshMaterial, hint: String,
                                       perVertexColor: Bool) -> String {
        let texture = material.texture.map { ordinal(of: $0) }
        let normal = material.normalTexture.map { ordinal(of: $0) }
        let mr = material.metallicRoughnessTexture.map { ordinal(of: $0) }
        let occlusion = material.occlusionTexture.map { ordinal(of: $0) }
        let emissive = material.emissiveTexture.map { ordinal(of: $0) }
        let heightMap = material.heightTexture.map { ordinal(of: $0) }
        let key = [num(material.baseColor.red), num(material.baseColor.green),
                   num(material.baseColor.blue), num(material.baseColor.alpha),
                   num(material.metallic), num(material.roughness), num(material.opacity),
                   num(material.ior), num(material.clearcoat), num(material.clearcoatRoughness),
                   perVertexColor ? "vc" : "-",
                   texture.map(String.init) ?? "-",
                   normal.map(String.init) ?? "-", num(material.normalScale),
                   mr.map(String.init) ?? "-",
                   occlusion.map(String.init) ?? "-", num(material.occlusionStrength),
                   emissive.map(String.init) ?? "-",
                   num(material.emissiveColor.red), num(material.emissiveColor.green),
                   num(material.emissiveColor.blue),
                   heightMap.map(String.init) ?? "-", num(material.heightScale)]
            .joined(separator: "/")
        if let found = materials.first(where: { $0.key == key }) { return found.path }

        let name = "material\(materials.count)"
        let path = "/\(rootName(of: hint))/Materials/\(name)"
        materials.append((key, path))
        materialsUSDA.append(materialUSDA(material, name: name, path: path,
                                          perVertexColor: perVertexColor))
        return path
    }

    /// One material: a UsdPreviewSurface, plus the reader shaders a texture, a
    /// surface map, or per-vertex color needs to feed it. Every map's encoding
    /// is the stated inverse of the reader's: the normal map's strength rides
    /// its decode as scale (2s, 2s, 2, 1) / bias (−s, −s, −1, 0) (an exact
    /// spelling of `s · (2c − 1)` on x/y), the metallic/roughness factors ride
    /// the packed map's per-channel scale (b and g, the standard packing), the
    /// occlusion strength rides its channel as scale s / bias 1 − s (exactly
    /// `1 + s·(ao − 1)`), and the emissive factor rides its map's scale.
    private mutating func materialUSDA(_ material: MeshMaterial, name: String, path: String,
                                       perVertexColor: Bool) -> String {
        var shaders = ""
        var needsST = false
        var diffuse = "  color3f inputs:diffuseColor = \(linearTuple(material.baseColor))\n"
        var mapInputs = ""

        /// A `UsdUVTexture` shader block reading `file` through the shared st
        /// reader, with an optional raw color space and scale/bias decode.
        func textureShader(_ shaderName: String, file: String, raw: Bool,
                           scale: String? = nil, bias: String? = nil,
                           outputs: [String]) -> String {
            needsST = true
            var s = "   def Shader \"\(shaderName)\"\n   {\n"
            s += "    uniform token info:id = \"UsdUVTexture\"\n"
            s += "    asset inputs:file = @\(file)@\n"
            s += "    float2 inputs:st.connect = <\(path)/st.outputs:result>\n"
            // The material's own answer for uvs outside the square, so a tiling
            // floor is still tiling when the file is read back.
            let wrapToken = switch material.wrap {
            case .clamp: "clamp"
            case .tile: "repeat"
            case .mirror: "mirror"
            }
            s += "    token inputs:wrapS = \"\(wrapToken)\"\n"
            s += "    token inputs:wrapT = \"\(wrapToken)\"\n"
            if raw { s += "    token inputs:sourceColorSpace = \"raw\"\n" }
            if let scale { s += "    float4 inputs:scale = \(scale)\n" }
            if let bias { s += "    float4 inputs:bias = \(bias)\n" }
            for output in outputs { s += "    \(output)\n" }
            s += "   }\n\n"
            return s
        }

        if let texture = material.texture, let file = textureFile(texture) {
            shaders += textureShader("texture", file: file, raw: false,
                                     scale: linearScale(material.baseColor),
                                     outputs: ["float3 outputs:rgb"])
            // Both a value and a connection: a renderer follows the connection,
            // and a reader that only looks at values still gets the tint rather
            // than nothing. The tint itself rides the texture's own scale, which
            // is where a preview surface keeps a multiplier on a sample.
            diffuse += "  color3f inputs:diffuseColor.connect = <\(path)/texture.outputs:rgb>\n"
        } else if perVertexColor {
            // A preview surface has no per-vertex color input, so the mesh's
            // own displayColor is read into the diffuse slot by a primvar
            // reader, which is the way the spec provides.
            shaders += """
               def Shader "vertexColor"
               {
                uniform token info:id = "UsdPrimvarReader_float3"
                string inputs:varname = "displayColor"
                float3 outputs:result
               }


            """
            diffuse += "  color3f inputs:diffuseColor.connect = <\(path)/vertexColor.outputs:result>\n"
        }

        if let normal = material.normalTexture, let file = textureFile(normal) {
            let s = material.normalScale
            shaders += textureShader("normalMap", file: file, raw: true,
                                     scale: "(\(num(2 * s)), \(num(2 * s)), 2, 1)",
                                     bias: "(\(num(-s)), \(num(-s)), -1, 0)",
                                     outputs: ["float3 outputs:rgb"])
            mapInputs += "  normal3f inputs:normal.connect = <\(path)/normalMap.outputs:rgb>\n"
        }

        // The metallic-roughness map and the occlusion map: one shader when
        // occlusion shares the packed image (the r channel is its slot), two
        // otherwise. Data either way, never color.
        let sharedORM = material.occlusionTexture != nil
            && material.occlusionTexture === material.metallicRoughnessTexture
        if let mr = material.metallicRoughnessTexture, let file = textureFile(mr) {
            let s = material.occlusionStrength
            let scale = sharedORM
                ? "(\(num(s)), \(num(material.roughness)), \(num(material.metallic)), 1)"
                : "(1, \(num(material.roughness)), \(num(material.metallic)), 1)"
            let bias = sharedORM ? "(\(num(1 - s)), 0, 0, 0)" : nil
            var outputs = ["float outputs:g", "float outputs:b"]
            if sharedORM { outputs.insert("float outputs:r", at: 0) }
            shaders += textureShader("mrTexture", file: file, raw: true,
                                     scale: scale, bias: bias, outputs: outputs)
            mapInputs += "  float inputs:metallic.connect = <\(path)/mrTexture.outputs:b>\n"
            mapInputs += "  float inputs:roughness.connect = <\(path)/mrTexture.outputs:g>\n"
            if sharedORM {
                mapInputs += "  float inputs:occlusion.connect = <\(path)/mrTexture.outputs:r>\n"
            }
        }
        if !sharedORM, let occlusion = material.occlusionTexture,
           let file = textureFile(occlusion) {
            let s = material.occlusionStrength
            shaders += textureShader("occlusionTexture", file: file, raw: true,
                                     scale: "(\(num(s)), \(num(s)), \(num(s)), 1)",
                                     bias: "(\(num(1 - s)), \(num(1 - s)), \(num(1 - s)), 0)",
                                     outputs: ["float outputs:r"])
            mapInputs += "  float inputs:occlusion.connect = <\(path)/occlusionTexture.outputs:r>\n"
        }

        // The height map feeds the preview surface's `displacement` input as
        // scale s / bias −s, the exact spelling of s·(h − 1): white sits at
        // the authored surface and darker carves in below it (the parallax
        // datum), so a renderer that really displaces carves the same relief
        // and the reader recovers `heightScale` from the channel scale.
        if material.heightScale > 0, let heightMap = material.heightTexture,
           let file = textureFile(heightMap) {
            let s = material.heightScale
            shaders += textureShader("heightMap", file: file, raw: true,
                                     scale: "(\(num(s)), \(num(s)), \(num(s)), 1)",
                                     bias: "(\(num(-s)), \(num(-s)), \(num(-s)), 0)",
                                     outputs: ["float outputs:r"])
            mapInputs += "  float inputs:displacement.connect = <\(path)/heightMap.outputs:r>\n"
        }

        let emissiveOn = material.emissiveColor.red > 0 || material.emissiveColor.green > 0
            || material.emissiveColor.blue > 0
        if emissiveOn, let emissive = material.emissiveTexture, let file = textureFile(emissive) {
            shaders += textureShader("emissiveTexture", file: file, raw: false,
                                     scale: linearScale(material.emissiveColor),
                                     outputs: ["float3 outputs:rgb"])
            mapInputs += "  color3f inputs:emissiveColor = \(linearTuple(material.emissiveColor))\n"
            mapInputs += "  color3f inputs:emissiveColor.connect = <\(path)/emissiveTexture.outputs:rgb>\n"
        } else if emissiveOn {
            mapInputs += "  color3f inputs:emissiveColor = \(linearTuple(material.emissiveColor))\n"
        }

        if needsST {
            shaders = """
                   def Shader "st"
                   {
                    uniform token info:id = "UsdPrimvarReader_float2"
                    string inputs:varname = "st"
                    float2 outputs:result
                   }


                """ + shaders
        }

        let inputs = (diffuse + mapInputs).trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: "\n", with: "\n  ")
        return """
          def Material "\(name)"
          {
           token outputs:surface.connect = <\(path)/surface.outputs:surface>

        \(shaders)   def Shader "surface"
           {
            uniform token info:id = "UsdPreviewSurface"
            int inputs:useSpecularWorkflow = 0
          \(inputs)
            float inputs:metallic = \(num(material.metallic))
            float inputs:roughness = \(num(material.roughness))
            float inputs:opacity = \(num(material.opacity))
            float inputs:ior = \(num(material.ior))
            float inputs:clearcoat = \(num(material.clearcoat))
            float inputs:clearcoatRoughness = \(num(material.clearcoatRoughness))
            token outputs:surface
           }
          }

        """
    }

    /// Which distinct texture this is, counting from the first one met.
    private mutating func ordinal(of texture: Image) -> Int {
        let id = ObjectIdentifier(texture)
        if let found = textureOrdinals[id] { return found }
        let next = textureOrdinals.count
        textureOrdinals[id] = next
        return next
    }

    /// The package-relative file name for `texture`, encoding it as a PNG the
    /// first time it is seen. Nil when images can't travel with this layer, or
    /// when the encode fails.
    private mutating func textureFile(_ texture: Image) -> String? {
        guard carriesTextures else {
            note("a texture was left out: a .usda layer is one text file, so images only travel inside a .usdz package.")
            return nil
        }
        let id = ObjectIdentifier(texture)
        if let found = textureIDs[id] { return found }
        guard let png = texture.pngData() else {
            note("a texture couldn't be encoded and was left out of the material.")
            return nil
        }
        let entry = "textures/texture\(textureIDs.count).png"
        // The path the layer refers to it by is anchored relative, the form the
        // spec asks for so it can't depend on where a reader is looking; the
        // package entry itself is the plain name.
        let assetPath = "./" + entry
        textureIDs[id] = assetPath
        textures.append((entry, png))
        return assetPath
    }

    // MARK: - Cameras

    /// A camera prim posed by its own transform: USD aims a camera down its
    /// local -z, which is the convention the reader resolves back through.
    private func cameraPrim(_ camera: Camera3D, name: String, depth: Int) -> String {
        let pad = String(repeating: " ", count: depth)
        let forward = camera.target - camera.eye
        let world = Self.pose(at: camera.eye, forward: forward, up: camera.up)
        var out = "\(pad)def Camera \"\(name)\"\n\(pad){\n"
        out += "\(pad) matrix4d xformOp:transform = \(matrix(world))\n"
        out += "\(pad) uniform token[] xformOpOrder = [\"xformOp:transform\"]\n"

        // A film back of this size is USD's own default, and holding it fixed
        // is what lets the focal length carry the angle by itself.
        let vertical = 15.2908
        switch camera.projection {
        case .perspective(let fieldOfView):
            // The inverse of the reader's fov.
            let half = max(min(fieldOfView, .pi - 0.01), 0.01) / 2
            let focal = vertical / (2 * tan(half))
            out += "\(pad) token projection = \"perspective\"\n"
            out += "\(pad) float focalLength = \(num(focal))\n"
            out += "\(pad) float horizontalAperture = \(num(vertical * 20.955 / 15.2908))\n"
            out += "\(pad) float verticalAperture = \(num(vertical))\n"
        case .intrinsic(let k):
            // A real lens measured in pixels: both apertures follow from the
            // focal lengths, and an off-center principal point becomes the
            // aperture offsets USD keeps for exactly this.
            let height = Double(max(k.height, 1)), width = Double(max(k.width, 1))
            let focal = k.fy * vertical / height
            let horizontal = k.fx > 0 ? focal * width / k.fx : vertical
            out += "\(pad) token projection = \"perspective\"\n"
            out += "\(pad) float focalLength = \(num(focal))\n"
            out += "\(pad) float horizontalAperture = \(num(horizontal))\n"
            out += "\(pad) float verticalAperture = \(num(vertical))\n"
            out += "\(pad) float horizontalApertureOffset = \(num((k.cx - width / 2) * horizontal / width))\n"
            out += "\(pad) float verticalApertureOffset = \(num((height / 2 - k.cy) * vertical / height))\n"
        case .orthographic(let height):
            // USD measures an orthographic aperture in tenths of a scene unit.
            out += "\(pad) token projection = \"orthographic\"\n"
            out += "\(pad) float horizontalAperture = \(num(height * 10))\n"
            out += "\(pad) float verticalAperture = \(num(height * 10))\n"
        }
        out += "\(pad) float2 clippingRange = (\(num(camera.near)), \(num(camera.far)))\n"
        return out + "\(pad)}\n"
    }

    // MARK: - Lights

    /// A UsdLux light prim, each kind the inverse of the one the reader maps in.
    private func lightPrim(_ light: Light, name: String, depth: Int) -> String {
        let pad = String(repeating: " ", count: depth)
        let type: String
        var extra = ""

        switch light.kind {
        case .directional:
            type = "DistantLight"
        case .point:
            type = "SphereLight"
            // A punctual light is a sphere with no size; saying so keeps its
            // shadows sharp in a renderer that would otherwise soften them.
            extra += "\(pad) float inputs:radius = 0\n"
            extra += "\(pad) bool treatAsPoint = 1\n"
        case .spot:
            type = "SphereLight"
            extra += "\(pad) float inputs:radius = 0\n"
            extra += "\(pad) bool treatAsPoint = 1\n"
            extra += "\(pad) float inputs:shaping:cone:angle = \(num(light.coneAngle / 2 * 180 / .pi))\n"
            extra += "\(pad) float inputs:shaping:cone:softness = \(num(light.penumbra))\n"
        case .rectangle:
            type = "RectLight"
            extra += "\(pad) float inputs:width = \(num(light.width))\n"
            extra += "\(pad) float inputs:height = \(num(light.height))\n"
        case .disk:
            type = "DiskLight"
            extra += "\(pad) float inputs:radius = \(num(light.radius))\n"
        case .tube:
            type = "CylinderLight"
            extra += "\(pad) float inputs:length = \(num(light.length))\n"
            extra += "\(pad) float inputs:radius = \(num(light.radius))\n"
        }

        let world = Self.lightPose(light)
        var out = "\(pad)def \(type) \"\(name)\"\n\(pad){\n"
        out += "\(pad) matrix4d xformOp:transform = \(matrix(world))\n"
        out += "\(pad) uniform token[] xformOpOrder = [\"xformOp:transform\"]\n"
        out += "\(pad) color3f inputs:color = \(linearTuple(light.color))\n"
        out += "\(pad) float inputs:intensity = \(num(light.intensity))\n"
        out += extra
        return out + "\(pad)}\n"
    }

    /// Where a light sits and which way it faces. Every kind but the tube emits
    /// down its local -z; a tube runs along its local x, which is the axis the
    /// reader transforms its endpoints along.
    private static func lightPose(_ light: Light) -> simd_float4x4 {
        if light.kind == .tube {
            let axis = light.direction.lengthSquared > 1e-12 ? light.direction.normalized : .unitX
            let helper = abs(axis.dot(.unitY)) > 0.99 ? Vector3.unitZ : .unitY
            let y = helper.cross(axis).normalized
            return basis(x: axis, y: y, z: axis.cross(y), at: light.position)
        }
        return pose(at: light.position, forward: light.direction, up: light.up)
    }

    /// A right-handed frame at `origin` looking along `forward`, with `up` as
    /// the roll hint. The frame's -z is the view direction, matching how both
    /// cameras and lights are read.
    private static func pose(at origin: Vector3, forward: Vector3, up: Vector3) -> simd_float4x4 {
        let f = forward.lengthSquared > 1e-12 ? forward.normalized : Vector3(0, 0, -1)
        let z = Vector3(-f.x, -f.y, -f.z)
        var hint = up.lengthSquared > 1e-12 ? up.normalized : .unitY
        if abs(hint.dot(z)) > 0.999 { hint = abs(z.y) > 0.9 ? .unitZ : .unitY }
        let x = hint.cross(z).normalized
        return basis(x: x, y: z.cross(x), z: z, at: origin)
    }

    private static func basis(x: Vector3, y: Vector3, z: Vector3,
                              at origin: Vector3) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(Float(x.x), Float(x.y), Float(x.z), 0),
                                SIMD4<Float>(Float(y.x), Float(y.y), Float(y.z), 0),
                                SIMD4<Float>(Float(z.x), Float(z.y), Float(z.z), 0),
                                SIMD4<Float>(Float(origin.x), Float(origin.y),
                                             Float(origin.z), 1)))
    }

    // MARK: - Formatting

    /// A matrix written the way USD authors one: four rows, translation last,
    /// which is this matrix's four columns (the reader reads them straight back
    /// as columns).
    private func matrix(_ m: simd_float4x4) -> String {
        let rows = [m.columns.0, m.columns.1, m.columns.2, m.columns.3].map { c in
            "(\(num(Double(c.x))), \(num(Double(c.y))), \(num(Double(c.z))), \(num(Double(c.w))))"
        }
        return "( \(rows.joined(separator: ", ")) )"
    }

    /// A color as the linear triple USD authors, the inverse of the reader's
    /// re-encoding on the way in.
    private func linearTuple(_ c: Color) -> String {
        "(\(num(Color.srgbToLinear(c.red))), \(num(Color.srgbToLinear(c.green))), \(num(Color.srgbToLinear(c.blue))))"
    }

    /// The same triple with alpha, for a texture's multiplier.
    private func linearScale(_ c: Color) -> String {
        "(\(num(Color.srgbToLinear(c.red))), \(num(Color.srgbToLinear(c.green))), \(num(Color.srgbToLinear(c.blue))), \(num(c.alpha)))"
    }

    private func tuples(_ values: [[Double]]) -> String {
        "[" + values.map { "(" + $0.map(num).joined(separator: ", ") + ")" }.joined(separator: ", ") + "]"
    }

    /// A number in the shortest form that reads back as the same 32-bit float,
    /// which is the precision every one of these attributes holds. Deterministic,
    /// so the same scene writes the same bytes.
    private func num(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e9 { return String(Int(value)) }
        return String(Float(value))
    }

    // MARK: - Names

    /// `path`'s first component, the root prim every material path hangs under.
    private func rootName(of path: String) -> String {
        path.split(separator: "/").first.map(String.init) ?? "Scene"
    }

    private func unique(_ name: String, in used: inout Set<String>) -> String {
        var candidate = name
        var n = 1
        while used.contains(candidate) {
            candidate = "\(name)_\(n)"
            n += 1
        }
        used.insert(candidate)
        return candidate
    }

    /// `name` as a USD prim name: letters, digits, and underscores, never
    /// leading with a digit.
    static func identifier(_ name: String, fallback: String) -> String {
        var out = ""
        for ch in name.unicodeScalars {
            out.unicodeScalars.append(CharacterSet.alphanumerics.contains(ch) && ch.isASCII
                                      ? ch : "_")
        }
        while out.hasPrefix("_") { out.removeFirst() }
        if let first = out.first, first.isNumber { out = "_" + out }
        return out.isEmpty ? fallback : out
    }
}

// MARK: - PNG encoding

extension Image {
    /// This image encoded as a PNG, for packaging beside a model. Nil if the
    /// system declines to encode it.
    func pngData() -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, currentCGImage(), nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
