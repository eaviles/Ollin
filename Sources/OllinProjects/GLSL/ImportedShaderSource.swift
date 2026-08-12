import Foundation

/// A shader that has been brought over from GLSL, ready to become a project.
/// It carries the translated Metal and how many inputs the shader reads, which
/// is what decides the shape of the sketch written around it.
public struct ImportedShader: Sendable {
    public var metalSource: String
    public var routing: ShaderImport.Routing
    /// Whether anything in it still needs a person.
    public var needsAttention: Bool
    /// A one-line description of where it came from, for the sketch's own comment.
    public var origin: String?

    /// The name of the `.metal` file, without its extension.
    public static let resourceName = "imported"

    public init(metalSource: String, routing: ShaderImport.Routing,
                needsAttention: Bool = false, origin: String? = nil) {
        self.metalSource = metalSource
        self.routing = routing
        self.needsAttention = needsAttention
        self.origin = origin
    }

    public init(_ result: ShaderImport.Result, origin: String? = nil) {
        self.init(metalSource: result.metalSource, routing: result.routing,
                  needsAttention: result.needsAttention, origin: origin)
    }
}

/// Writes the sketch that runs an imported shader.
///
/// How many inputs the shader reads decides the shape: none draws it straight,
/// one runs it over a layer, two run it over a pair. The layers a filter or a
/// combine reads are drawn here in plain calls, so the first thing to edit is
/// obvious and needs no knowledge of the shader.
enum ImportedShaderSource {

    static func body(_ shader: ImportedShader, className: String, inlineShader: Bool) -> String {
        var lines: [String] = []

        lines.append("/// A fragment shader brought over from GLSL.")
        if let origin = shader.origin, !origin.isEmpty {
            lines.append("/// \(origin)")
        }
        lines.append("///")
        if inlineShader {
            lines.append("/// The shader sits in the string below. Editing it under OllinLive reloads")
            lines.append("/// the sketch with it.")
        } else {
            lines.append("/// The shader sits in `\(ImportedShader.resourceName).metal` beside this file.")
            lines.append("/// Editing that file under OllinLive reloads it without restarting the sketch.")
        }
        if shader.needsAttention {
            lines.append("///")
            lines.append("/// It did not come over whole. The shader file lists what needs a hand,")
            lines.append("/// in comments marked TODO(ollin), and it will not compile until they are dealt with.")
        }

        lines.append("@main")
        lines.append("final class \(className): Sketch {")
        lines.append("")
        lines.append(shaderDeclaration(shader, inline: inlineShader))
        lines.append("")
        lines.append("    override func draw() {")
        lines.append(drawBody(shader.routing))
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func shaderDeclaration(_ shader: ImportedShader, inline: Bool) -> String {
        guard inline else {
            return "    private let imported = Shader(resource: \"\(ImportedShader.resourceName)\", in: .module)"
        }
        // A raw literal, so a backslash in the shader stays a backslash and
        // nothing in it is read as Swift.
        let indented = shader.metalSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    " + $0 }
            .joined(separator: "\n")
        return "    private let imported = Shader(#\"\"\"\n\(indented)\n    \"\"\"#)"
    }

    private static func drawBody(_ routing: ShaderImport.Routing) -> String {
        switch routing {
        case .generator:
            return "        drawImage(generate(imported).image, 0, 0)"

        case .filter:
            return """
                    // What the shader reads with sample(info, uv). Draw anything here.
                    let layer = renderTarget()
                    withTarget(layer) {
                        background(Color(hex: 0x0E1116))
                        noStroke()
                        fill(Color(hex: 0xFFC857))
                        drawCircle(mouseX, mouseY, width * 0.18)
                    }
                    drawImage(layer.filtered(.shader(imported)).image, 0, 0)
            """

        case .combine:
            return """
                    // The first input, read with sample(info, uv).
                    let base = renderTarget()
                    withTarget(base) {
                        background(Color(hex: 0x2B1B12))
                        noStroke()
                        fill(Color(hex: 0xFF8C42))
                        drawCircle(width / 2, height / 2, width * 0.3)
                    }
                    // The second, read with sampleAux(info, uv).
                    let aux = renderTarget()
                    withTarget(aux) {
                        background(Color(hex: 0x0E1B2A))
                        stroke(Color(hex: 0x4CC9F0))
                        strokeWeight(6)
                        let step = width / 12
                        for i in 0...12 {
                            drawLine(Double(i) * step, 0, Double(i) * step, height)
                            drawLine(0, Double(i) * step, width, Double(i) * step)
                        }
                    }
                    drawImage(base.combined(with: aux, .shader(imported)).image, 0, 0)
            """
        }
    }
}
