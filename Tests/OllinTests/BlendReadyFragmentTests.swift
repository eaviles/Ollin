import Foundation
@testable import Ollin
import Testing

/// Every fragment a sketch's blend mode reaches hands its color to the blend
/// through `ollin_blend_ready` (or its premultiplied twin). Under multiply,
/// screen, and the lighter and darker of two, the blend cannot weight a color
/// by its coverage itself, so a fragment that returns its color bare draws a
/// half-covered pixel at full effect under those modes and looks right under
/// the ordinary one, where nothing would say so.
///
/// This reads the shader sources, so it runs anywhere and draws nothing.
@Suite
struct BlendReadyFragmentTests {
    /// The segments the drawing paths' fragments live in.
    static let segments = ["ShaderCore", "ShaderShapes", "ShaderStrokes", "ShaderFills", "ShaderCombinator",
                           "ShaderRaymarch", "Shader3D", "ShaderOcean"]

    /// The fragments in those segments that no blend mode reaches, each with
    /// why. A new fragment joins this list with its reason or calls the helper.
    static let unblended: [String: String] = [
        "ollin_clip_fragment": "writes the stencil only; its color is masked off",
        "ollin_raymarch_upsample_fragment": "lays the reduced field back, always under the over blend",
        "ollin_raymarch_shadow_fragment": "a shadow pass: no color to blend",
        "ollin_particle_splat_fragment": "the light splat's own additive pass into a single-sample layer",
        "ollin_particle_splat_point_fragment": "the light splat's own additive pass into a single-sample layer",
        "ollin_mesh_velocity_fragment": "writes a motion vector with blending off",
        "ollin_mesh_fieldshadow_fragment": "writes a shadow factor into its own target",
        "ollin_mesh_point_shadow_fragment": "writes a distance into the shadow cube",
        "ollin_mesh_normal_fragment": "writes normals into its own target",
        "ollin_mesh_gbuffer_fragment": "writes the reflection pass's surface data with blending off",
        "ollin_mesh_scatter_fragment": "writes the subsurface mask with blending off",
        "ollin_ocean_spectrum": "an effect pass over the ocean's own textures",
        "ollin_ocean_resolve": "an effect pass over the ocean's own textures",
    ]

    /// Each fragment function in a segment and its body.
    static func fragments(in name: String) throws -> [(name: String, body: Substring)] {
        let url = try #require(OllinResources.bundle.url(forResource: name, withExtension: "metal"))
        let source = try String(contentsOf: url, encoding: .utf8)
        var found: [(String, Substring)] = []
        var rest = source[...]
        while let start = rest.range(of: "\nfragment ") {
            let signature = rest[start.upperBound...]
            guard let open = signature.firstIndex(of: "("),
                  let nameStart = signature[..<open].lastIndex(where: { $0 == " " || $0 == "\n" }) else { break }
            let function = String(signature[signature.index(after: nameStart)..<open])
            // Past the parameter list, then the braces of the body.
            var index = open, depth = 0
            repeat {
                if signature[index] == "(" { depth += 1 } else if signature[index] == ")" { depth -= 1 }
                index = signature.index(after: index)
            } while depth > 0
            guard let brace = signature[index...].firstIndex(of: "{") else { break }
            var end = brace
            depth = 0
            repeat {
                if signature[end] == "{" { depth += 1 } else if signature[end] == "}" { depth -= 1 }
                end = signature.index(after: end)
            } while depth > 0
            found.append((function, signature[brace..<end]))
            rest = signature[end...]
        }
        return found
    }

    @Test(arguments: segments)
    func everyBlendedFragmentHandsItsColorThroughTheHelper(segment: String) throws {
        let all = try Self.fragments(in: segment)
        #expect(!all.isEmpty, "\(segment) holds no fragment: the reader lost its place")
        for (name, body) in all {
            let ready = body.contains("ollin_blend_ready(") || body.contains("ollin_blend_ready_premultiplied(")
            if let reason = Self.unblended[name] {
                #expect(!ready, "\(name) is listed as unblended (\(reason)) and calls the helper: drop it from the list")
            } else {
                #expect(ready, "\(name) in \(segment).metal returns its color without ollin_blend_ready: under multiply, screen, lightest, and darkest it ignores its own coverage")
            }
        }
    }

    /// The list names only fragments that exist.
    @Test func theUnblendedListNamesRealFragments() throws {
        let names = try Set(Self.segments.flatMap { try Self.fragments(in: $0).map(\.name) })
        for listed in Self.unblended.keys {
            #expect(names.contains(listed), "\(listed) is on the unblended list and in no segment")
        }
    }
}
