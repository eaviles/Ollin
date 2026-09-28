import Foundation
import simd

// The lights leg of USD scene import: the authored UsdLux lights become
// node-riding `SceneLightSpec`s on the scene walk's nodes (`loadUSDScene`
// attaches them where it builds each light prim's node, so visibility and
// purpose gate them the way they gate meshes), and `Scene.lights` resolves
// them into ordinary `Light` values through the tree's current transforms.
//
// The mapping, each USD light kind onto the Ollin light it is:
//
//   SphereLight                     → point
//   SphereLight with a shaping cone → spot (the cone half-angle, in degrees,
//                                     doubles into Ollin's full `coneAngle`;
//                                     the cone softness is the penumbra)
//   DistantLight                    → directional
//   RectLight (width × height)      → rect area light
//   DiskLight (radius)              → disk area light
//   CylinderLight (length, radius)  → tube area light (its length runs along
//                                     the prim's local x axis)
//
// Every kind emits along its node's -z axis (the camera convention, shared
// with glTF), so direction, position, and the area extents resolve through
// the prim's world transform whenever the lights are read. Attribute names
// carry the `inputs:` prefix, with the bare pre-2021 spellings accepted as
// fallbacks. The glTF treatment applies throughout: colors arrive linear and
// re-encode to sRGB, and physical intensities (scaled by 2^exposure) mean
// nothing without the falloff model USD assumes, so each kind normalizes to
// its brightest; relative balance survives, absolute units don't.

extension Scene {

    /// The prim type names of the mapped UsdLux kinds, shared with the scene
    /// walk that collects them.
    static let usdLightTypeNames: Set<String> = ["SphereLight", "DistantLight", "RectLight",
                                                "DiskLight", "CylinderLight"]

    /// One light prim as a node-local spec, intensity still the raw physical
    /// brightness (`normalizeLightSpecs` rescales once the tree is built), or
    /// nil for a kind this doesn't map.
    static func usdLightSpec(_ prim: USDPrim) -> SceneLightSpec? {
        // Schema defaults: intensity 1 (except DistantLight, whose fallback
        // approximates sunlight), exposure 0, white; brightness scales by
        // 2^exposure.
        let defaultIntensity = prim.typeName == "DistantLight" ? 50000.0 : 1.0
        let intensity = max(lightScalar(prim, "intensity") ?? defaultIntensity, 0)
        let brightness = intensity * pow(2, lightScalar(prim, "exposure") ?? 0)

        var color = Color.white
        if case .tuple(let c)? = lightInput(prim, "color"), c.count == 3 {
            func enc(_ x: Double) -> Double { Color.linearToSrgb(min(max(x, 0), 1)) }
            color = Color(red: enc(c[0]), green: enc(c[1]), blue: enc(c[2]))
        }

        switch prim.typeName {
        case "DistantLight":
            return SceneLightSpec(kind: .directional, color: color, intensity: brightness)
        case "SphereLight":
            if let halfAngle = lightScalar(prim, "shaping:cone:angle") {
                // The cone restricts emission to `halfAngle` degrees off the
                // -z axis; softness fades the cone's interior edge.
                let softness = min(max(lightScalar(prim, "shaping:cone:softness") ?? 0, 0), 1)
                return SceneLightSpec(kind: .spot, color: color, intensity: brightness,
                                      coneAngle: 2 * halfAngle * .pi / 180, penumbra: softness)
            }
            return SceneLightSpec(kind: .point, color: color, intensity: brightness)
        case "RectLight":
            // Width spans local x, height local y; a scaling transform scales
            // the panel with it at resolution.
            return SceneLightSpec(kind: .rectangle, color: color, intensity: brightness,
                                  width: lightScalar(prim, "width") ?? 1,
                                  height: lightScalar(prim, "height") ?? 1)
        case "DiskLight":
            return SceneLightSpec(kind: .disk, color: color, intensity: brightness,
                                  radius: lightScalar(prim, "radius") ?? 0.5)
        case "CylinderLight":
            // The tube runs along local x; resolution transforms its endpoints,
            // carrying position, aim, and any scale in one move.
            return SceneLightSpec(kind: .tube, color: color, intensity: brightness,
                                  radius: lightScalar(prim, "radius") ?? 0.5,
                                  length: lightScalar(prim, "length") ?? 1)
        default:
            return nil
        }
    }

    /// A light input by its base name: the `inputs:`-prefixed spelling, else
    /// the bare pre-2021 one.
    private static func lightInput(_ prim: USDPrim, _ name: String) -> USDValue? {
        (prim.attribute("inputs:" + name) ?? prim.attribute(name))?.authoredValue
    }

    private static func lightScalar(_ prim: USDPrim, _ name: String) -> Double? {
        switch lightInput(prim, name) {
        case .double(let d): d
        case .int(let i): Double(i)
        case .uint(let u): Double(u)
        default: nil
        }
    }
}
