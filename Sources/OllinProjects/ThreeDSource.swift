import Foundation

/// Writing a 3D sketch out of a `ThreeDRecipe`.
///
/// The fragments are deliberately small and in a fixed order (camera, then the
/// surroundings, then the light, then the finish, then the thing itself), which
/// is both the order the reference recipe gives and the order that reads well
/// when someone opens the file to change it.
enum ThreeDSource {

    static func body(_ recipe: ThreeDRecipe, className: String, hints: String) -> String {
        let picked = recipe.chosen
        func has(_ option: ThreeDOption) -> Bool { picked.contains(option.id) }

        var setup = [hints]
        var draw: [String] = []

        draw.append("background(Color(hex: 0x0B0D12))")
        draw.append("")
        draw.append("// Drifts on its own, and you can drag it. It eases back when you stop.")
        draw.append("cameraShowcase(.autoOrbit(period: 24), target: Vector3(0, 1.1, 0), radius: 7,")
        draw.append("               elevation: 0.30, fieldOfView: .pi / 4)")
        draw.append("")

        if has(.environment) {
            draw.append("// Lights every surface and brings its own backdrop.")
            draw.append("environment(.studio)")
        }
        if has(.fog) {
            draw.append("fog(Color(hex: 0x0B0D12), density: 0.02)")
        }
        if has(.toneMap) {
            draw.append("toneMap(.aces)")
        }

        if has(.lit) || has(.physicallyBased) {
            draw.append("ambientLight(Color(white: 0.14))")
            draw.append("directionalLight(.white, direction: Vector3(-0.4, -0.85, -0.45), intensity: 0.9)")
        }
        if has(.shadows) {
            draw.append("castShadows()")
        }
        if has(.rayTraced) {
            draw.append("// A safe no-op on a machine without ray tracing.")
            draw.append("rayTracedReflections()")
        }
        if !draw.last!.isEmpty { draw.append("") }

        // The finish, then the thing it finishes.
        switch recipe.finish.id {
        case ThreeDOption.physicallyBased.id:
            draw.append("material(.metal(roughness: 0.25))")
            draw.append("fill(Color(hex: 0xF2F3F7))")
        case ThreeDOption.lit.id:
            draw.append("material(.physicallyBased(metallic: 0.1, roughness: 0.45))")
            draw.append("fill(Color(hue: 0.57, saturation: 0.45, brightness: 0.95))")
        case ThreeDOption.matcap.id:
            draw.append("// One image is the entire look: no lights, no material.")
            draw.append("matcap(.chrome)")
        default:
            break
        }

        switch recipe.geometry.id {
        case ThreeDOption.mesh.id:
            draw.append("withState {")
            draw.append("    translate(0, 1.2, 0)")
            draw.append("    rotateY(time * 0.3)")
            draw.append("    drawIcosphere(radius: 1.2, subdivisions: 3)")
            draw.append("}")
        case ThreeDOption.wireframe.id:
            draw.append("stroke(Color(hue: 0.55, saturation: 0.4, brightness: 1))")
            draw.append("wireframe()")
            draw.append("withState {")
            draw.append("    translate(0, 1.2, 0)")
            draw.append("    rotateY(time * 0.3)")
            draw.append("    drawIcosphere(radius: 1.2, subdivisions: 2)")
            draw.append("}")
            draw.append("wireframe(false)")
        case ThreeDOption.pointCloud.id:
            setup.append("")
            setup.append("// Built once: the cloud is data, not something to rebuild each frame.")
            setup.append("var points = PointCloud()")
            setup.append("for _ in 0 ..< 4000 {")
            setup.append("    // An even scatter through a ball: a direction off the")
            setup.append("    // sphere, then a radius that accounts for the room further out.")
            setup.append("    let angle = random(0, .tau)")
            setup.append("    let z = random(-1, 1)")
            setup.append("    let ring = (1 - z * z).squareRoot()")
            setup.append("    let direction = Vector3(cos(angle) * ring, sin(angle) * ring, z)")
            setup.append("    let radius = 1.2 * pow(random(0, 1), 1.0 / 3.0)")
            setup.append("    points.add(direction * radius + Vector3(0, 1.2, 0),")
            setup.append("               color: Color(hue: 0.55 + radius * 0.2, saturation: 0.45, brightness: 1),")
            setup.append("               size: 3)")
            setup.append("}")
            setup.append("cloud = points")
            draw.append("drawPointCloud(cloud)")
        case ThreeDOption.field.id:
            draw.append("// Two spheres melting into one another, traced per pixel.")
            draw.append("let blob = SDF3D.sphere(radius: 0.9).at(x: -0.5, y: 1.2, z: 0)")
            draw.append("    .smoothUnion(.sphere(radius: 0.7)")
            draw.append("        .at(x: 0.6, y: 1.2 + sin(time) * 0.4, z: 0), k: 0.55)")
            draw.append("drawSDF3D(blob)")
        default:
            break
        }

        // A floor, for the geometry that can sit on one and shadow it.
        if has(.shadows) || has(.environment) {
            draw.append("")
            draw.append("material(.dielectric(roughness: 0.85))")
            draw.append("fill(Color(white: 0.42))")
            draw.append("drawPlane(width: 12, depth: 12)")
        }

        let properties = recipe.geometry.id == ThreeDOption.pointCloud.id
            ? "    private var cloud = PointCloud()\n\n" : ""

        return """
        /// \(headline(recipe))
        final class \(className): Sketch {
        \(properties)    override func setup() {
                \(setup.joined(separator: "\n        "))
            }

            override func draw() {
                \(draw.joined(separator: "\n        "))
            }
        }
        """
    }

    /// One line saying what this particular combination is, so the file explains
    /// itself to whoever opens it next.
    static func headline(_ recipe: ThreeDRecipe) -> String {
        var line = "\(recipe.geometry.title) with \(recipe.finish.title.lowercased())"
        let extras = recipe.extras.sorted().compactMap { ThreeDOption.named($0)?.title.lowercased() }
        if !extras.isEmpty {
            line += ", plus \(extras.joined(separator: ", "))"
        }
        return line + "."
    }
}
