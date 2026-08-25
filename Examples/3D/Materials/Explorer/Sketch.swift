import AppKit
import Ollin

/// The material explorer: every finish in the hand.
///
/// The whole curated `Material` library on one Preset menu, every finish scalar on
/// its own knob, and the stage around the surface (lighting preset, environment,
/// fog, shadows, the solid it's judged on) switchable while you look. Picking a
/// preset snaps the knobs to its values; drag any knob to tweak from there, and the
/// caption notes when the finish has left its preset. Press a key to step through
/// the presets; the mouse stays free for the camera (drag to orbit, scroll to
/// dolly). Press C to copy the knobs as the `Material(...)` expression that
/// rebuilds them (`swiftSource`), ready to paste into a sketch.
///
/// Things worth trying: `polishedMetal` under the `city` backdrop (a mirror needs
/// something to reflect), `frostedGlass` over `sunset` (transmission needs an
/// environment to transmit), `sequin` while the camera orbits (the flakes flash
/// with the view), and `felt` with a `sheenColor` far from the surface color (the
/// two-tone velvet look).
@main
final class MaterialExplorer: Sketch {

    enum PreviewShape: CaseIterable, ParamOption {
        case sphere, torus, knot, box, cylinder
    }

    enum Backdrop: CaseIterable, ParamOption {
        case none, studio, city, courtyard, forest, interior, night, sunrise, sunset, sky

        var environment: Environment? {
            switch self {
            case .none: nil
            case .studio: .studio
            case .city: .city
            case .courtyard: .courtyard
            case .forest: .forest
            case .interior: .interior
            case .night: .night
            case .sunrise: .sunrise
            case .sunset: .sunset
            case .sky: .sky()
            }
        }
    }

    enum ShadingChoice: CaseIterable, ParamOption {
        case standard, toon, gooch, physicallyBased

        var model: Material.Shading {
            switch self {
            case .standard: .standard
            case .toon: .toon
            case .gooch: .gooch
            case .physicallyBased: .physicallyBased
            }
        }

        init(_ shading: Material.Shading) {
            switch shading {
            case .standard: self = .standard
            case .toon: self = .toon
            case .gooch: self = .gooch
            case .physicallyBased: self = .physicallyBased
            }
        }
    }

    // The starting point, and what it's judged on.
    @Param(group: "Preset") var preset: Material = .glossy
    @Param(group: "Preset") var shape: PreviewShape = .sphere
    @Param(group: "Preset") var surfaceColor = Color(hue: 0.05, saturation: 0.55, brightness: 0.85)

    // The stage around it.
    @Param(group: "Stage") var mood: LightingPreset = .studio
    @Param(group: "Stage") var backdrop: Backdrop = .studio
    @Param(group: "Stage") var shadows = true
    @Param(group: "Stage") var haze = false

    // The finish, knob by knob. Defaults spell out `.glossy`, the opening preset.
    @Param(group: "Finish") var shading: ShadingChoice = .standard
    @Param(1...12, group: "Finish") var toonBands = 4.0
    @Param("Specular", 0...1, group: "Finish") var specularLevel = 0.9
    @Param("Shininess", 1...256, group: "Finish") var shininessLevel = 160.0

    @Param(0...1, group: "Physically based") var metallic = 0.0
    @Param(0...1, group: "Physically based") var roughness = 0.5
    @Param(-1...1, group: "Physically based") var anisotropy = 0.0

    @Param(0...1, group: "Glass") var transmission = 0.0
    @Param("IOR", 1...2.5, group: "Glass") var ior = 1.5
    @Param(0...3, group: "Glass") var thickness = 0.0

    @Param(0...1, group: "Coat and cloth") var clearcoat = 0.0
    @Param("Coat roughness", 0...1, group: "Coat and cloth") var clearcoatRoughness = 0.0
    @Param(0...1, group: "Coat and cloth") var sheen = 0.0
    @Param(0...1, group: "Coat and cloth") var sheenRoughness = 0.5
    @Param(group: "Coat and cloth") var sheenColor: Color = .white

    @Param(0...1, group: "Shimmer") var iridescence = 0.0
    @Param(0...3, group: "Shimmer") var iridescenceScale = 1.0
    @Param(0...1, group: "Shimmer") var sparkle = 0.0
    @Param(0.05...12, group: "Shimmer") var sparkleSize = 1.0
    @Param(1...100, group: "Shimmer") var sparkleSharpness = 48.0

    @Param(0...1, group: "Glow") var rim = 0.0
    @Param(0.1...6, group: "Glow") var rimPower = 2.0
    @Param(0...1, group: "Glow") var subsurface = 0.0
    @Param(group: "Glow") var subsurfaceColor: Color = .white

    private var lastPreset: Material?
    private var copiedUntil = -1.0

    /// Knobs hide while the shader ignores them, so the panel only offers what
    /// can change the picture: the physically-based set acts under that shading
    /// model alone, the specular pair only outside it, and each dependent scalar
    /// waits for the knob that turns its term on. IOR stays with the
    /// physically-based set (not behind transmission) because it also shapes the
    /// normal-incidence reflectance of an opaque surface.
    override func setup() {
        $toonBands.show(when: $shading) { $0 == .toon }
        $specularLevel.show(when: $shading) { $0 != .physicallyBased }
        $shininessLevel.show(when: $shading) { $0 != .physicallyBased }
        $metallic.show(when: $shading) { $0 == .physicallyBased }
        $roughness.show(when: $shading) { $0 == .physicallyBased }
        $anisotropy.show(when: $shading) { $0 == .physicallyBased }
        $transmission.show(when: $shading) { $0 == .physicallyBased }
        $ior.show(when: $shading) { $0 == .physicallyBased }
        $thickness.show(when: $transmission) { $0 > 0 }
        $clearcoat.show(when: $shading) { $0 == .physicallyBased }
        $clearcoatRoughness.show(when: $clearcoat) { $0 > 0 }
        $sheen.show(when: $shading) { $0 == .physicallyBased }
        $sheenRoughness.show(when: $sheen) { $0 > 0 }
        $sheenColor.show(when: $sheen) { $0 > 0 }
        $iridescenceScale.show(when: $iridescence) { $0 > 0 }
        $sparkleSize.show(when: $sparkle) { $0 > 0 }
        $sparkleSharpness.show(when: $sparkle) { $0 > 0 }
        $rimPower.show(when: $rim) { $0 > 0 }
        $subsurfaceColor.show(when: $subsurface) { $0 > 0 }
    }

    override func keyPressed() {
        if key == "c" || key == "C" {
            copyFinish()
            return
        }
        let roster = Material.paramChoices
        let index = roster.firstIndex { $0.value == preset } ?? 0
        preset = roster[(index + 1) % roster.count].value
    }

    /// Put the knobs on the clipboard as the expression that rebuilds them,
    /// and print it, so a terminal run shows what was copied.
    private func copyFinish() {
        let source = knobMaterial.swiftSource
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        print(source)
        copiedUntil = time + 2.5
    }

    /// Copy a preset's values onto the knobs, so tweaking starts from it.
    private func snap(to m: Material) {
        shading = ShadingChoice(m.shading)
        toonBands = m.toonBands
        specularLevel = m.specular
        shininessLevel = m.shininess
        metallic = m.metallic
        roughness = m.roughness
        anisotropy = m.anisotropy
        transmission = m.transmission
        ior = m.ior
        thickness = m.thickness
        clearcoat = m.clearcoat
        clearcoatRoughness = m.clearcoatRoughness
        sheen = m.sheen
        sheenRoughness = m.sheenRoughness
        sheenColor = m.sheenColor
        iridescence = m.iridescence
        iridescenceScale = m.iridescenceScale
        sparkle = m.sparkle
        sparkleSize = m.sparkleSize
        sparkleSharpness = m.sparkleSharpness
        rim = m.rim
        rimPower = m.rimPower
        subsurface = m.subsurface
        subsurfaceColor = m.subsurfaceColor
    }

    /// The material the knobs currently spell.
    private var knobMaterial: Material {
        var m = Material()
        m.shading = shading.model
        m.toonBands = toonBands
        m.specular = specularLevel
        m.shininess = shininessLevel
        m.metallic = metallic
        m.roughness = roughness
        m.anisotropy = anisotropy
        m.transmission = transmission
        m.ior = ior
        m.thickness = thickness
        m.clearcoat = clearcoat
        m.clearcoatRoughness = clearcoatRoughness
        m.sheen = sheen
        m.sheenRoughness = sheenRoughness
        m.sheenColor = sheenColor
        m.iridescence = iridescence
        m.iridescenceScale = iridescenceScale
        m.sparkle = sparkle
        m.sparkleSize = sparkleSize
        m.sparkleSharpness = sparkleSharpness
        m.rim = rim
        m.rimPower = rimPower
        m.subsurface = subsurface
        m.subsurfaceColor = subsurfaceColor
        return m
    }

    override func draw() {
        // Snap the knobs when the Preset menu changes while running. The first
        // frame only records the selection, so values restored across a reload
        // (or tuned before a save) aren't clobbered.
        if lastPreset == nil {
            lastPreset = preset
        } else if preset != lastPreset {
            snap(to: preset)
            lastPreset = preset
        }

        background(Color(white: 0.05))
        cameraShowcase(.autoOrbit(), target: Vector3(0, -0.15, 0), radius: 4.8,
                       elevation: 0.26, fieldOfView: .pi / 4)

        lightingPreset(mood)
        if let environment = backdrop.environment { self.environment(environment) }
        castShadows(shadows)
        if haze { fog(Color(white: 0.55), density: 0.1) }

        // The ground that catches the shadow: matte, neutral.
        withState {
            translate(0, -1.4, 0)
            fill(Color(white: 0.5))
            material(.matte)
            drawPlane(width: 18, depth: 18)
        }

        // The surface under judgment.
        let m = knobMaterial
        withState {
            fill(surfaceColor)
            material(m)
            switch shape {
            case .sphere: drawSphere(radius: 1.15, segments: 96, rings: 48)
            case .torus: drawTorus(radius: 0.9, tube: 0.42, segments: 96, sides: 48)
            case .knot: drawTorusKnot(p: 2, q: 3, radius: 0.8, tube: 0.28)
            case .box:
                rotateY(0.5)
                drawBox(size: 1.7)
            case .cylinder: drawCylinder(radius: 0.8, height: 1.9, segments: 96)
            }
        }

        if time < copiedUntil {
            drawCaption("Copied as Swift to the clipboard")
        } else {
            let name = Material.paramChoices.first { $0.value == preset }?.name ?? "custom"
            let tweaked = m != preset ? " (tweaked)" : ""
            drawCaption("Material: \(name)\(tweaked)   ·   press a key for the next preset, C to copy as Swift")
        }
    }
}
