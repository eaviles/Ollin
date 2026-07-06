import Testing
import Metal
@testable import Ollin

/// The user-shader error path must report compile diagnostics at the real source
/// location (the sketch's own `.swift` file and line for an inline string, the
/// `.metal` file for a resource), so an error is IDE-clickable instead of reading
/// `Shader:8` with nothing to jump to.
@MainActor
struct ShaderErrorTests {

    // MARK: Call-site capture

    @Test func inlineShaderCapturesCallSite() {
        let line = #line; let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(uv, 0.0, 1.0);
        }
        """)
        #expect(shader.diagnosticSourceName == #filePath)
        // A multiline literal's content starts the line after the opening `"""`.
        #expect(shader.diagnosticStartLine == line + 1)
    }

    @Test func singleLineShaderStartsOnTheCallLine() {
        let line = #line; let shader = Shader("float4 shade(float2 uv, ShaderInfo info) { return 1.0; }")
        #expect(shader.diagnosticStartLine == line)
    }

    // MARK: Composed-source directive

    @Test func composedSourceEmitsFileLineDirective() {
        let (source, _) = MetalRenderer.composeUserShaderSource(
            userSource: "float4 shade(float2 uv, ShaderInfo info) { return 1.0; }",
            modules: .all, variant: .generator,
            sourceName: "/Users/someone/Sketch.swift", sourceStartLine: 42)
        #expect(source.contains("#line 42 \"/Users/someone/Sketch.swift\""))
    }

    @Test func directiveEscapesQuotesInPaths() {
        let (source, _) = MetalRenderer.composeUserShaderSource(
            userSource: "x", modules: .all, variant: .generator,
            sourceName: #"/odd/"quoted".swift"#, sourceStartLine: 1)
        #expect(source.contains(#"#line 1 "/odd/\"quoted\".swift""#))
    }

    // MARK: Fallback rebase (a toolchain that ignores `#line`)

    @Test func fallbackRebaseMapsToFileAndLine() {
        // A diagnostic at composed line offset+3 is user-source line 3, which sits
        // at file line start+2.
        let raw = "program_source:103:5: error: expected ';'\n"
        let cleaned = MetalRenderer.cleanShaderDiagnostics(
            raw, userLineOffset: 100, sourceName: "/Users/someone/Sketch.swift",
            sourceStartLine: 40)
        #expect(cleaned.hasPrefix("/Users/someone/Sketch.swift:42:5: error:"))
    }

    @Test func cleanupDropsASuppressedNotesContinuationLines() {
        // A dropped stdlib note must take its code excerpt and caret with it, so
        // no orphaned snippet leaks into the message (the shape a real
        // "did you mean 'vec'" diagnostic produces).
        let raw = "/Users/a/Sketch.swift:7:5: error: use of undeclared identifier 'vec4'\n"
            + "    vec4 v = 1.0;\n"
            + "    ^~~~\n"
            + "/System/Library/.../metal_types:83:1: note: 'vec' declared here\n"
            + "using vec = T __attribute__((__ext_vector_type__(N)));\n"
            + "^\n"
        let cleaned = MetalRenderer.cleanShaderDiagnostics(
            raw, userLineOffset: 0, sourceName: "/Users/a/Sketch.swift", sourceStartLine: 7)
        #expect(cleaned.contains("vec4 v = 1.0;"))
        #expect(cleaned.contains("^~~~"))
        #expect(!cleaned.contains("metal_types"))
        #expect(!cleaned.contains("ext_vector_type"))
    }

    @Test func cleanupKeepsLinesNamingTheUserFile() {
        // The system-path filter must never drop a diagnostic that names the
        // user's own file, wherever that file lives.
        let raw = "/usr/local/sketches/Sketch.swift:9:1: error: boom\n"
            + "note: candidate in /System/Library/GPUCompiler.framework/x.h\n"
        let cleaned = MetalRenderer.cleanShaderDiagnostics(
            raw, userLineOffset: 0, sourceName: "/usr/local/sketches/Sketch.swift",
            sourceStartLine: 9)
        #expect(cleaned.contains("Sketch.swift:9:1: error: boom"))
        #expect(!cleaned.contains("GPUCompiler.framework"))
    }

    // MARK: End to end: the Metal compiler honors the directive

    @Test func compilerReportsErrorsAtTheTaggedLocation() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        // A broken shader whose error sits on its second line: pretend it starts
        // at Sketch.swift:20, so the diagnostic must land on line 21.
        let broken = """
        float4 shade(float2 uv, ShaderInfo info) {
            vec4 v = 1.0;
            return v;
        }
        """
        let (composed, _) = MetalRenderer.composeUserShaderSource(
            userSource: broken, modules: .all, variant: .generator,
            sourceName: "/tmp/Sketch.swift", sourceStartLine: 20)
        var message = ""
        do {
            _ = try device.makeLibrary(source: composed, options: nil)
            Issue.record("the broken shader compiled")
        } catch {
            message = (error as NSError).localizedDescription
        }
        #expect(message.contains("/tmp/Sketch.swift:21:"))
    }
}
