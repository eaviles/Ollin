import Foundation
import Metal

/// What a check of one shader file found.
package struct ShaderCheckReport: Sendable {

    /// What the shader is, which follows from how many layers it reads: none makes it a
    /// generator, one a filter, two a combine. The same rule the effect graph uses.
    package enum Shape: String, Sendable, CaseIterable {
        case generator, filter, combine

        /// How the shape reads in a sentence, for the line the command prints.
        package var reason: String {
            switch self {
            case .generator: return "it reads no layer"
            case .filter: return "it reads one layer"
            case .combine: return "it reads two layers"
            }
        }
    }

    /// The file that was checked, as an absolute path.
    package let path: String
    package let shape: Shape
    /// True when the caller named the shape rather than the checker working it out.
    package let shapeWasGiven: Bool
    /// The `param(info, i)` indices the shader reads, in order, without repeats.
    package let parameters: [Int]
    /// The files it pulled in, in the order they were read.
    package let included: [String]
    /// The compiler's complaint, tidied and pointing at the author's own line. Empty
    /// when the shader compiled.
    package let diagnostics: String

    package var ok: Bool { diagnostics.isEmpty }
}

/// Compiles a shader file on the real device and says what it found: the errors at the
/// author's own line, what the shader is, which parameters it reads, and which files it
/// pulled in. This is the loop a person editing a `.metal` outside a running sketch has
/// otherwise no way to close, since the only other way to learn whether a shader
/// compiles is to launch something that draws it.
/// Main-actor because the compose and diagnostic helpers it reuses belong to the
/// renderer, which is. A command line runs its top level there anyway.
@MainActor
package enum ShaderCheck {

    /// Check the shader in `path`. `shape` names what to compile it as; leave it off and
    /// the checker works it out from how many layers the shader reads.
    package static func check(path: String,
                              as shape: ShaderCheckReport.Shape? = nil) -> ShaderCheckReport {
        let full = URL(fileURLWithPath: path).standardizedFileURL.path
        func failed(_ message: String, shape: ShaderCheckReport.Shape = .generator)
            -> ShaderCheckReport {
            ShaderCheckReport(path: full, shape: shape, shapeWasGiven: false,
                              parameters: [], included: [], diagnostics: message)
        }
        guard let text = try? String(contentsOfFile: full, encoding: .utf8) else {
            return failed("\(full): cannot read the file.")
        }
        let resolved = ShaderIncludes.resolveFromFilesystem(text, name: full)
        guard resolved.ok else {
            return failed(resolved.problems.joined(separator: "\n"))
        }
        let found = shape ?? inferredShape(of: resolved.source)
        let parameters = parameterIndices(in: resolved.source)
        guard let device = MTLCreateSystemDefaultDevice() else {
            return failed("no Metal device on this machine, so nothing can be compiled.",
                          shape: found)
        }
        let variant: MetalRenderer.UserShaderVariant
        switch found {
        case .generator: variant = .generator
        case .filter: variant = .filter
        case .combine: variant = .combine
        }
        let (composed, offset) = MetalRenderer.composeUserShaderSource(
            userSource: resolved.source, modules: .all, variant: variant,
            sourceName: full, sourceStartLine: 1)
        func report(_ diagnostics: String) -> ShaderCheckReport {
            ShaderCheckReport(path: full, shape: found, shapeWasGiven: shape != nil,
                              parameters: parameters, included: resolved.included,
                              diagnostics: diagnostics)
        }
        do {
            let library = try device.makeLibrary(source: composed, options: nil)
            guard let vertex = library.makeFunction(name: "ollin_user_vertex"),
                  let fragment = library.makeFunction(name: "ollin_user_fragment") else {
                return report("\(full):1: the shader has no "
                              + "shade(float2 uv, ShaderInfo info) function.")
            }
            // Build the pipeline too, not only the library: a shader can compile and
            // still be refused here, and the running sketch would find that out, not us.
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.rasterSampleCount = 1
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            _ = try device.makeRenderPipelineState(descriptor: descriptor)
            return report("")
        } catch {
            return report(MetalRenderer.cleanShaderDiagnostics(
                (error as NSError).localizedDescription, userLineOffset: offset,
                sourceName: full, sourceStartLine: 1))
        }
    }

    /// What the shader is, from the layer readers it calls. `sampleAux` needs a second
    /// layer, `sample` a first, and a shader that calls neither takes none.
    package static func inferredShape(of source: String) -> ShaderCheckReport.Shape {
        if calls("sampleAux", in: source) || calls("sampleAuxRaw", in: source) { return .combine }
        if calls("sample", in: source) || calls("sampleRaw", in: source) { return .filter }
        return .generator
    }

    /// The `param(info, i)` indices the source reads, sorted and without repeats. An
    /// index worked out at run time cannot be seen from here, so this is what the shader
    /// asks for in plain sight, not a promise that it asks for nothing else.
    package static func parameterIndices(in source: String) -> [Int] {
        let pattern = #"(?<![A-Za-z0-9_])param\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*(\d+)\s*\)"#
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        var found = Set<Int>()
        rx.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, let value = Int(ns.substring(with: m.range(at: 1))) else { return }
            found.insert(value)
        }
        return found.sorted()
    }

    /// Whether `source` calls `name` as a function, rather than merely containing the
    /// word (`sampleCount` is not a call to `sample`, and `discSample(` is not one either).
    private static func calls(_ name: String, in source: String) -> Bool {
        guard let rx = try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_])\(NSRegularExpression.escapedPattern(for: name))\\s*\\(")
        else { return false }
        let ns = source as NSString
        return rx.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) != nil
    }
}
