import Testing
import Foundation
import OllinWebGate
@testable import OllinShaderText

/// A whole fragment entry point carried to the page: the framework's effect,
/// generator, combine, and simulation fragments, each cut out with what it
/// reaches and rewritten over the page's bindings. The text checks read the
/// shape of the result; the browser check compiles every fragment the door
/// names, in one run, and is skipped with the reason in the log where no
/// browser gives WebGL2.
struct WebFragmentTranslatorTests {

    /// The segments the effect graph's fragments live in, in the order the
    /// exporter joins them.
    static func segmentText() throws -> String {
        let root = try #require(WebShaderLibraryTests.repositoryRoot())
        return try ["OllinShaderLib", "ShaderCore", "ShaderShapes", "ShaderEffects",
                    "ShaderCombine", "ShaderSim", "ShaderPatterns"].map { name in
            try String(contentsOf: root.appendingPathComponent("Sources/Ollin/Renderer/\(name).metal"), encoding: .utf8)
        }.joined(separator: "\n")
    }

    /// The fragments the shader door carries: every single-pass filter,
    /// generator, and combine the effect tables describe as data, the user-shader
    /// wrapper's readers aside, and the step and inject fragments of the
    /// single-field simulations.
    static let doorFragments = [
        // Filters
        "ollin_fx_color_grade", "ollin_fx_invert", "ollin_fx_posterize", "ollin_fx_threshold",
        "ollin_fx_sepia", "ollin_fx_color_vision", "ollin_fx_duotone", "ollin_fx_gradient_map",
        "ollin_fx_antialias", "ollin_fx_edges", "ollin_fx_sharpen", "ollin_fx_vignette",
        "ollin_fx_chromatic", "ollin_fx_halftone", "ollin_fx_dither", "ollin_fx_dither_duo",
        "ollin_fx_grain", "ollin_fx_pixelate", "ollin_fx_linescreen", "ollin_fx_solarize",
        "ollin_fx_temperature", "ollin_fx_vibrance", "ollin_fx_exposure", "ollin_fx_levels",
        "ollin_fx_colorama", "ollin_fx_lumakey", "ollin_fx_motion_blur", "ollin_fx_radial_blur",
        "ollin_fx_bilateral", "ollin_fx_emboss", "ollin_fx_oilpaint", "ollin_fx_crosshatch",
        "ollin_fx_toon", "ollin_fx_median", "ollin_fx_contour", "ollin_fx_cmyk_halftone",
        "ollin_fx_normal_map", "ollin_fx_relight", "ollin_fx_iridescence", "ollin_fx_glitter",
        "ollin_fx_thin_film", "ollin_fx_diffraction", "ollin_fx_scanlines", "ollin_fx_glitch",
        "ollin_fx_crt", "ollin_fx_kaleidoscope", "ollin_fx_swirl", "ollin_fx_droste",
        "ollin_fx_bulge", "ollin_fx_wave", "ollin_fx_ripple", "ollin_fx_mirror", "ollin_fx_polar",
        "ollin_fx_tile", "ollin_fx_perturb", "ollin_fx_fluted_glass", "ollin_fx_water",
        "ollin_fx_paper_texture", "ollin_fx_melt", "ollin_fx_field_map",
        "ollin_fx_brightpass", "ollin_fx_bloom_combine",
        // Combines
        "ollin_fx_mask", "ollin_fx_displace", "ollin_fx_lic", "ollin_fx_mix", "ollin_fx_paint_mix",
        // Generators
        "ollin_gen_checkers", "ollin_gen_grid", "ollin_gen_bars", "ollin_gen_noise",
        "ollin_gen_cellular", "ollin_gen_mesh_gradient", "ollin_gen_filaments",
        "ollin_gen_smoke_ring", "ollin_gen_color_panels", "ollin_gen_spiral", "ollin_gen_waves",
        "ollin_gen_dot_orbit", "ollin_gen_grain_gradient", "ollin_gen_pulsing_border",
        "ollin_gen_god_rays", "ollin_gen_quasicrystal", "ollin_gen_moire", "ollin_gen_gyroid",
        "ollin_gen_phyllotaxis", "ollin_gen_hexpulse", "ollin_gen_chladni", "ollin_gen_escape",
        "ollin_gen_orbittrap", "ollin_gen_domain", "ollin_gen_gabor", "ollin_gen_newton",
        // Simulations: the injects and the steps of the single-field sims.
        "ollin_sim_inject", "ollin_sim_inject_height", "ollin_sim_inject_sand",
        "ollin_sim_inject_grains", "ollin_sim_inject_excite", "ollin_sim_inject_brain",
        "ollin_sim_reaction_diffusion", "ollin_sim_reaction_diffusion_modulated",
        "ollin_sim_life", "ollin_sim_lenia", "ollin_sim_ripples", "ollin_sim_sandpile",
        "ollin_sim_falling_sand", "ollin_sim_cyclic", "ollin_sim_excitable", "ollin_sim_brain",
        "ollin_sim_hodgepodge", "ollin_sim_state_seed",
    ]

    @Test func aFilterFragmentBecomesAPageShader() throws {
        let text = try Self.segmentText()
        let swirl = WebFragmentTranslator.translate(entry: "ollin_fx_swirl", in: text, paramRows: 4)
        #expect(swirl.isClean, "\(swirl.unsupported)")
        #expect(swirl.textures == ["src"])
        #expect(swirl.paramsName == "params")
        let glsl = swirl.glsl
        #expect(glsl.hasPrefix("#version 300 es\n"))
        #expect(glsl.contains("uniform sampler2D src;"))
        #expect(glsl.contains("uniform vec4 params[OLLIN_PARAM_ROWS];"))
        #expect(glsl.contains("#define OLLIN_PARAM_ROWS 4"))
        #expect(glsl.contains("vec4 ollin_fx_swirl("))
        #expect(glsl.contains("ollin_tex(src,"))
        #expect(glsl.contains("void main() { fragColor = ollin_fx_swirl(); }"))
        #expect(!glsl.contains("[["))
        #expect(!glsl.contains("PresentOut"))
        #expect(!glsl.contains("fragment "))
        #expect(!glsl.contains(".sample("))
        #expect(!glsl.contains("float2"))
    }

    @Test func aLookupTableRidesAsASecondSampler() throws {
        let text = try Self.segmentText()
        let map = WebFragmentTranslator.translate(entry: "ollin_fx_gradient_map", in: text, paramRows: 1)
        #expect(map.isClean, "\(map.unsupported)")
        #expect(map.textures == ["src", "lut"])
        #expect(map.glsl.contains("uniform sampler2D src;\nuniform sampler2D lut;"))
    }

    @Test func aGeneratorReadsNoTexture() throws {
        let text = try Self.segmentText()
        let noise = WebFragmentTranslator.translate(entry: "ollin_gen_noise", in: text, paramRows: 3)
        #expect(noise.isClean, "\(noise.unsupported)")
        #expect(noise.textures.isEmpty)
        #expect(!noise.glsl.contains("uniform sampler2D"))
        // The noise it reaches came along: the library's fbm and its hash.
        #expect(noise.glsl.contains("float ollin_fbm("))
        #expect(noise.glsl.contains("float hash12("))
    }

    @Test func aSimulationStepCarriesItsMacros() throws {
        let text = try Self.segmentText()
        let step = WebFragmentTranslator.translate(entry: "ollin_sim_reaction_diffusion", in: text, paramRows: 2)
        #expect(step.isClean, "\(step.unsupported)")
        #expect(step.textures == ["src"])
        // The neighbor taps were written as a macro over a texture read; the
        // read crossed inside the macro.
        #expect(step.glsl.contains("#define TAP("))
        #expect(step.glsl.contains("ollin_texLod(src,"))
        #expect(!step.glsl.contains(".sample("))
    }

    @Test func anEntryTheDoorNamesExists() throws {
        let text = try Self.segmentText()
        let defined = Set(WebFragmentTranslator.entryPoints(in: text))
        let missing = Self.doorFragments.filter { !defined.contains($0) }
        #expect(missing.isEmpty, "not defined: \(missing)")
    }

    @Test func everyDoorFragmentTranslatesClean() throws {
        let text = try Self.segmentText()
        var unclean: [String] = []
        for name in Self.doorFragments {
            let t = WebFragmentTranslator.translate(entry: name, in: text, paramRows: 80)
            if !t.isClean { unclean.append("\(name): \(t.unsupported.map(\.message).joined(separator: " / "))") }
        }
        #expect(unclean.isEmpty, Comment(rawValue: unclean.joined(separator: "\n")))
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func everyDoorFragmentCompilesInTheBrowser() async throws {
        let text = try Self.segmentText()
        let shaders = Self.doorFragments.map {
            WebFragmentTranslator.translate(entry: $0, in: text, paramRows: 80).glsl
        }
        let dom = try await HeadlessBrowser.dom(of: WebGLPage.compile(shaders), timeout: 180)
        var failures: [String] = []
        for (i, name) in Self.doorFragments.enumerated() {
            let report = HeadlessBrowser.text(of: "r\(i)", in: dom) ?? "no report"
            if report != "OK" { failures.append("\(name): \(report.prefix(400))") }
        }
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n\n")))
    }
}
