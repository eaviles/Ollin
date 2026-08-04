import Foundation
import simd

// The lights leg of USD scene import: the authored UsdLux lights resolve into
// ordinary `Light` values on `Scene.lights`, from the same raw-tree read that
// builds the node tree (`loadUSDScene` collects the light prims with their
// world transforms during its walk, so visibility and purpose gate them the
// way they gate meshes).
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
// the prim's world transform at load. Attribute names carry the `inputs:`
// prefix, with the bare pre-2021 spellings accepted as fallbacks. The glTF
// treatment applies throughout: colors arrive linear and re-encode to sRGB,
// and physical intensities (scaled by 2^exposure) mean nothing without the
// falloff model USD assumes, so each kind normalizes to its brightest;
// relative balance survives, absolute units don't.

extension Scene {

    /// The prim type names of the mapped UsdLux kinds, shared with the scene
    /// walk that collects them.
    static let usdLightTypeNames: Set<String> = ["SphereLight", "DistantLight", "RectLight",
                                                "DiskLight", "CylinderLight"]

    /// The authored UsdLux lights of `stage`, resolved through their prims'
    /// world transforms. (The scene walk passes its own collected refs
    /// instead, so hidden prims stay dark; this whole-stage form reads every
    /// light prim.)
    static func resolveUSDLights(_ stage: USDStage) -> [Light] {
        var refs: [(prim: USDPrim, world: simd_double4x4)] = []
        stage.visitPrims { prim, world in
            if usdLightTypeNames.contains(prim.typeName) { refs.append((prim, world)) }
        }
        return resolveUSDLights(refs: refs)
    }

    /// The collected light prims resolved into `Light` values, with the
    /// per-kind brightest-is-1 intensity normalization.
    static func resolveUSDLights(refs: [(prim: USDPrim, world: simd_double4x4)]) -> [Light] {
        guard !refs.isEmpty else { return [] }

        var lights: [Light] = []
        var brightness: [Double] = []
        for (prim, world) in refs {
            guard let light = resolveUSDLight(prim, world: world) else { continue }
            lights.append(light.0)
            brightness.append(light.brightness)
        }

        // Per-kind normalization: the brightest of each kind becomes 1.
        var kindMax: [Light.Kind: Double] = [:]
        for (light, b) in zip(lights, brightness) {
            kindMax[light.kind] = Swift.max(kindMax[light.kind] ?? 0, b)
        }
        for i in lights.indices {
            let peak = kindMax[lights[i].kind] ?? 0
            lights[i].intensity = peak > 0 ? brightness[i] / peak : 1
        }
        return lights
    }

    /// One light prim as a `Light` (intensity still the raw physical
    /// brightness; the caller normalizes) or nil for a kind this doesn't map.
    private static func resolveUSDLight(_ prim: USDPrim, world: simd_double4x4)
        -> (Light, brightness: Double)? {
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

        func vec(_ c: SIMD4<Double>) -> Vector3 { Vector3(c.x, c.y, c.z) }
        let position = vec(world.columns.3)
        var direction = -vec(world.columns.2)
        direction = direction.lengthSquared > 1e-12 ? direction.normalized : Vector3(0, -1, 0)
        let xAxis = vec(world.columns.0)
        let yAxis = vec(world.columns.1)

        let light: Light
        switch prim.typeName {
        case "DistantLight":
            light = .directional(color, direction: direction)
        case "SphereLight":
            if let halfAngle = lightScalar(prim, "shaping:cone:angle") {
                // The cone restricts emission to `halfAngle` degrees off the
                // -z axis; softness fades the cone's interior edge.
                let softness = min(max(lightScalar(prim, "shaping:cone:softness") ?? 0, 0), 1)
                light = .spot(color, at: position, direction: direction,
                              angle: 2 * halfAngle * .pi / 180, penumbra: softness)
            } else {
                light = .point(color, at: position)
            }
        case "RectLight":
            // Width spans local x, height local y; a scaling transform scales
            // the panel with it.
            let width = (lightScalar(prim, "width") ?? 1) * xAxis.length
            let height = (lightScalar(prim, "height") ?? 1) * yAxis.length
            let up = yAxis.lengthSquared > 1e-12 ? yAxis.normalized : .unitY
            light = .rect(color, at: position, direction: direction,
                          width: width, height: height, up: up)
        case "DiskLight":
            let radius = (lightScalar(prim, "radius") ?? 0.5)
                * (xAxis.length + yAxis.length) / 2
            light = .disk(color, at: position, direction: direction, radius: radius)
        case "CylinderLight":
            // The tube runs along local x; transforming its endpoints carries
            // position, aim, and any scale in one move.
            let half = (lightScalar(prim, "length") ?? 1) / 2
            let from = world * SIMD4<Double>(-half, 0, 0, 1)
            let to = world * SIMD4<Double>(half, 0, 0, 1)
            let radius = (lightScalar(prim, "radius") ?? 0.5)
                * (yAxis.length + vec(world.columns.2).length) / 2
            light = .tube(color, from: vec(from), to: vec(to), radius: radius)
        default:
            return nil
        }
        return (light, brightness)
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
