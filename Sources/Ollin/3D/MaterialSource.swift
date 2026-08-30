// A tuned finish written back as the source that rebuilds it. The explorer's
// "copy as Swift" rides this, and any sketch can print any material the same
// way. Pure text: nothing here touches the renderer.

import Foundation

extension Material {

    /// This material written as the Swift expression that rebuilds it.
    ///
    /// A curated preset prints as its short name (`.glossy`); anything else prints
    /// as a `Material(...)` call listing only the fields that differ from
    /// `Material()`'s defaults, in the initializer's own order, so the expression
    /// stays as short as the built-in presets' definitions. Values print rounded
    /// to four decimals, and a field whose rounded text matches the default's is
    /// left out, so a knob's float dust never reaches the source. The expression
    /// passes back through the initializer, which clamps every field to its legal
    /// range. Paste it wherever a `Material` goes:
    ///
    /// ```swift
    /// material(Material(specular: 0.9, shininess: 160))
    /// let finish: Material = .glossy
    /// ```
    public var swiftSource: String {
        if let match = Material.paramChoices.first(where: { $0.value == self }) {
            return ".\(match.name)"
        }
        return swiftSourceExpression
    }

    /// The full `Material(...)` call, never a preset name. The public property
    /// prefers the short form; the label compile gate needs this one.
    var swiftSourceExpression: String {
        let defaults = Material()
        var args: [String] = []
        func scalar(_ label: String, _ path: KeyPath<Material, Double>) {
            let text = Material.sourceNumber(self[keyPath: path])
            if text != Material.sourceNumber(defaults[keyPath: path]) {
                args.append("\(label): \(text)")
            }
        }
        func color(_ label: String, _ path: KeyPath<Material, Color>) {
            let text = Material.sourceColor(self[keyPath: path])
            if text != Material.sourceColor(defaults[keyPath: path]) {
                args.append("\(label): \(text)")
            }
        }
        if shading != defaults.shading {
            args.append("shading: \(Material.sourceShading(shading))")
        }
        scalar("toonBands", \.toonBands)
        scalar("metallic", \.metallic)
        scalar("roughness", \.roughness)
        scalar("anisotropy", \.anisotropy)
        scalar("anisotropyRotation", \.anisotropyRotation)
        scalar("transmission", \.transmission)
        scalar("ior", \.ior)
        scalar("thickness", \.thickness)
        color("attenuationColor", \.attenuationColor)
        scalar("attenuationDistance", \.attenuationDistance)
        scalar("clearcoat", \.clearcoat)
        scalar("clearcoatRoughness", \.clearcoatRoughness)
        scalar("sheen", \.sheen)
        color("sheenColor", \.sheenColor)
        scalar("sheenRoughness", \.sheenRoughness)
        scalar("thinFilm", \.thinFilm)
        scalar("thinFilmThickness", \.thinFilmThickness)
        scalar("thinFilmIOR", \.thinFilmIOR)
        scalar("specular", \.specular)
        scalar("shininess", \.shininess)
        scalar("iridescence", \.iridescence)
        scalar("iridescenceScale", \.iridescenceScale)
        scalar("iridescenceFlow", \.iridescenceFlow)
        scalar("iridescencePhase", \.iridescencePhase)
        scalar("iridescenceFlowSize", \.iridescenceFlowSize)
        scalar("sparkle", \.sparkle)
        scalar("sparkleSize", \.sparkleSize)
        scalar("sparkleSharpness", \.sparkleSharpness)
        color("sparkleColor", \.sparkleColor)
        scalar("rim", \.rim)
        scalar("rimPower", \.rimPower)
        color("rimColor", \.rimColor)
        scalar("subsurface", \.subsurface)
        color("subsurfaceColor", \.subsurfaceColor)
        scalar("scattering", \.scattering)
        scalar("scatteringRadius", \.scatteringRadius)
        color("scatteringColor", \.scatteringColor)
        color("goochWarm", \.goochWarm)
        color("goochCool", \.goochCool)
        if args.isEmpty { return "Material()" }
        return "Material(\(args.joined(separator: ", ")))"
    }

    private static func sourceShading(_ shading: Shading) -> String {
        switch shading {
        case .standard: ".standard"
        case .toon: ".toon"
        case .gooch: ".gooch"
        case .physicallyBased: ".physicallyBased"
        }
    }

    /// Four decimals, trailing zeros trimmed, whole numbers bare.
    private static func sourceNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10_000).rounded() / 10_000
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded() && abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        var text = String(format: "%.4f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The shortest `Color` form: a named standard, a gray, or the full channels.
    private static func sourceColor(_ color: Color) -> String {
        let r = sourceNumber(color.red)
        let g = sourceNumber(color.green)
        let b = sourceNumber(color.blue)
        let a = sourceNumber(color.alpha)
        if a == "1" {
            if r == "1" && g == "1" && b == "1" { return ".white" }
            if r == "0" && g == "0" && b == "0" { return ".black" }
            if r == g && g == b { return "Color(white: \(r))" }
            return "Color(red: \(r), green: \(g), blue: \(b))"
        }
        if r == g && g == b { return "Color(white: \(r), alpha: \(a))" }
        return "Color(red: \(r), green: \(g), blue: \(b), alpha: \(a))"
    }
}
