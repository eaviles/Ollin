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

    @Test func sparkleClampsAndPacks() {
        let m = Material(sparkle: 2, sparkleSize: 0, sparkleSharpness: 0,
                         sparkleColor: Color(white: 0.5))
        #expect(m.sparkle == 1)              // 0...1
        #expect(m.sparkleSize == 0.05)       // >= 0.05
        #expect(m.sparkleSharpness == 1)     // >= 1
        let g = m.gpuMaterial()
        #expect(close(g.sparkleColor.w, 1))  // sparkle strength in the alpha slot
        #expect(g.sparkleColor.x < 0.5 && g.sparkleColor.x > 0)  // linearized tint
        #expect(close(g.sparkleSize, 0.05) && close(g.sparkleSharpness, 1))
        // A default material stays inert (no flakes).
        #expect(close(Material().gpuMaterial().sparkleColor.w, 0))
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

    @Test func glassClampsAndDefaultsInert() {
        // The default material transmits nothing and carries the canonical glass IOR,
        // so every pre-glass material packs the same bytes it always did.
        let d = Material()
        #expect(d.transmission == 0 && d.ior == 1.5 && d.thickness == 0)
        #expect(d.attenuationDistance == 0)
        let m = Material(transmission: 3, ior: 0.5, thickness: -2, attenuationDistance: -1)
        #expect(m.transmission == 1)         // 0...1
        #expect(m.ior == 1)                  // >= 1
        #expect(m.thickness == 0)            // >= 0
        #expect(m.attenuationDistance == 0)  // >= 0
    }

    @Test func f0PacksExactlyAtTheDefaultIor() {
        // The shader used to hard-code 0.04; the packed f0 must be that exact float at
        // ior 1.5 (the computed ((0.5)/(2.5))^2 rounds to a *different* float), so
        // existing physically-based frames stay bit-identical.
        #expect(Material().gpuMaterial().f0 == Float(0.04))
        #expect(Material.glass().gpuMaterial().f0 == Float(0.04))
        // Off the default it's the real Fresnel form: ior 3 -> ((2)/(4))^2 = 0.25.
        #expect(close(Material(ior: 3).gpuMaterial().f0, 0.25))
    }

    @Test func glassPacksTransmissionAndAttenuation() {
        let m = Material.glass(roughness: 0.2, ior: 1.33, thickness: 1.8,
                               attenuationColor: Color(white: 0.5),
                               attenuationDistance: 0.7)
        #expect(m.shading == .physicallyBased && m.transmission == 1)
        let g = m.gpuMaterial()
        #expect(close(g.transmission, 1) && close(g.ior, 1.33) && close(g.thickness, 1.8))
        #expect(close(g.attenuation.w, 0.7))
        // Attenuation color is linearized (sRGB 0.5 -> ~0.214), and a black channel is
        // floored just above zero so the shader's pow() can't hit pow(0, 0) NaNs.
        #expect(g.attenuation.x < 0.5 && g.attenuation.x > 0)
        let black = Material.glass(attenuationColor: .black, attenuationDistance: 1).gpuMaterial()
        #expect(black.attenuation.x > 0 && close(black.attenuation.x, 1e-4))
        // The default is inert: no transmission, no attenuation.
        let d = Material().gpuMaterial()
        #expect(close(d.transmission, 0) && close(d.attenuation.w, 0))
        #expect(Material.frostedGlass.transmission == 1)
    }

    @Test func coatAndSheenClampAndPack() {
        // Both layered lobes are inert by default (no coat, a zero sheen tint), so
        // every pre-coat material packs the same shading it always did.
        let d = Material()
        #expect(d.clearcoat == 0 && d.clearcoatRoughness == 0)
        #expect(d.sheen == 0 && d.sheenRoughness == 0.5)
        let dg = d.gpuMaterial()
        #expect(close(dg.clearcoat, 0) && close(dg.clearcoatRoughness, 0))
        #expect(close(dg.sheenColor.x, 0) && close(dg.sheenColor.y, 0) && close(dg.sheenColor.z, 0))
        // Everything clamps to 0...1.
        let m = Material(clearcoat: 2, clearcoatRoughness: -1, sheen: 3, sheenRoughness: 9)
        #expect(m.clearcoat == 1 && m.clearcoatRoughness == 0)
        #expect(m.sheen == 1 && m.sheenRoughness == 1)
        // The sheen strength premultiplies the linearized tint (so strength 0 packs a
        // zero tint whatever the color); w carries the sheen roughness.
        let g = Material(sheen: 0.5, sheenColor: .white, sheenRoughness: 0.75).gpuMaterial()
        #expect(close(g.sheenColor.x, 0.5) && close(g.sheenColor.w, 0.75))
        #expect(close(Material(sheen: 0, sheenColor: .white).gpuMaterial().sheenColor.x, 0))
        // The presets read as their names.
        let paint = Material.carPaint()
        #expect(paint.shading == .physicallyBased && paint.metallic == 1 && paint.clearcoat == 1)
        #expect(Material.lacquer.clearcoat == 1 && Material.lacquer.metallic == 0)
        #expect(Material.satin.sheen > 0 && Material.felt.sheen > 0)
        #expect(Material.felt.sheenRoughness > Material.satin.sheenRoughness)
    }

    @Test func soapFilmClampsAndPacks() {
        // The film swirl is inert by default (0 flow: the plain rim sheen), the flow
        // clamps non-negative, and the phase clock passes through signed (it's a
        // clock, not a strength).
        let d = Material()
        #expect(d.iridescenceFlow == 0 && d.iridescencePhase == 0)
        #expect(d.iridescenceFlowSize == 1)
        let m = Material(iridescence: 0.8, iridescenceFlow: -2, iridescencePhase: -3.5,
                         iridescenceFlowSize: 0)
        #expect(m.iridescenceFlow == 0)
        #expect(m.iridescencePhase == -3.5)
        #expect(m.iridescenceFlowSize == 0.05)   // floored, like sparkleSize
        let g = Material(iridescence: 0.8, iridescenceFlow: 1.5,
                         iridescencePhase: 7.25, iridescenceFlowSize: 0.4).gpuMaterial()
        #expect(close(g.iridescenceFlow, 1.5) && close(g.iridescencePhase, 7.25))
        #expect(close(g.iridescenceFlowSize, 0.4))
        #expect(close(Material().gpuMaterial().iridescenceFlow, 0))
    }
}
