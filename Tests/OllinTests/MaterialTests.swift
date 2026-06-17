@testable import Ollin
import Testing
import COllinShaders

/// CPU checks on the `Material` finish: its defaults, clamping, the `gpuMaterial()`
/// packing into the `OllinMaterial` uniform (colors linearized, shading model, strengths
/// in the color alpha slots), and the curated library. No Metal device, so these run in CI.
@Suite
struct MaterialTests {

    private func close(_ a: Float, _ b: Float, _ eps: Float = 1e-5) -> Bool { abs(a - b) <= eps }

    @Test func defaultIsInert() {
        // A default material shades like the original Lambert path: no highlight, no
        // finishes, standard shading.
        let m = Material()
        #expect(m.specular == 0)
        #expect(m.shininess == 32)
        #expect(m.iridescence == 0 && m.rim == 0 && m.subsurface == 0)
        #expect(m.shading == .standard)
        let g = m.gpuMaterial()
        #expect(g.shadingModel == 0)
        #expect(close(g.specular, 0) && close(g.rimColor.w, 0) && close(g.subsurfaceColor.w, 0))
    }

    @Test func clampsOutOfRange() {
        let m = Material(toonBands: 0, specular: -1, shininess: 0,
                         iridescence: 2, iridescenceScale: -1,
                         rim: 5, rimPower: 0, subsurface: -0.5)
        #expect(m.toonBands == 1)            // >= 1
        #expect(m.specular == 0)             // >= 0
        #expect(m.shininess == 1)            // >= 1
        #expect(m.iridescence == 1)          // 0...1
        #expect(m.iridescenceScale == 0)     // >= 0
        #expect(m.rim == 1)                  // 0...1
        #expect(m.rimPower >= 0.1)           // >= 0.1
        #expect(m.subsurface == 0)           // 0...1
    }

    @Test func gpuPackingLinearizesColorsAndCarriesStrengths() {
        // Rim/subsurface strengths ride the alpha of their color slots; the model and
        // scalar knobs map across; colors come out linearized (an sRGB 0.5 grey is < 0.5).
        let m = Material(shading: .toon, toonBands: 5,
                         specular: 0.4, shininess: 64,
                         iridescence: 0.7, iridescenceScale: 2.0,
                         rim: 0.8, rimPower: 3, rimColor: Color(white: 0.5),
                         subsurface: 0.6, subsurfaceColor: Color(white: 1.0))
        let g = m.gpuMaterial()
        #expect(g.shadingModel == 1)
        #expect(close(g.toonBands, 5))
        #expect(close(g.specular, 0.4) && close(g.shininess, 64))
        #expect(close(g.iridescence, 0.7) && close(g.iridescenceScale, 2))
        #expect(close(g.rimPower, 3))
        #expect(close(g.rimColor.w, 0.8))         // rim strength in the alpha slot
        #expect(close(g.subsurfaceColor.w, 0.6))  // subsurface strength in the alpha slot
        // sRGB 0.5 linearizes to ~0.214 — strictly less than 0.5, never the raw value.
        #expect(g.rimColor.x < 0.5 && g.rimColor.x > 0)
    }

    @Test func iridescentScalesStrength() {
        let m = Material.glossy.iridescent(by: 0.5)
        #expect(m.iridescence == Material.glossy.iridescence * 0.5)
        // glossy starts at 0, so scaling stays 0; soapBubble (1.0) halves and clamps.
        #expect(Material.soapBubble.iridescent(by: 0.5).iridescence == 0.5)
        #expect(Material.soapBubble.iridescent(by: 4).iridescence == 1)   // clamps to 1
    }

    @Test func libraryReadsAsItsName() {
        #expect(Material.matte.specular == 0)
        #expect(Material.polished.specular == 1)
        #expect(Material.soapBubble.iridescence > 0)
        #expect(Material.velvet.rim > 0)
        #expect(Material.jade.subsurface > 0)
        #expect(Material.toon.shading == .toon)
        #expect(Material.gooch.shading == .gooch)
    }

    @Test func equatable() {
        #expect(Material.clay == Material.clay)
        #expect(Material.clay != Material.glossy)
        var m = Material.glossy
        m.iridescence = 0.3
        #expect(m != Material.glossy)
    }
}
