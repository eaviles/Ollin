@testable import Ollin
import Foundation
import Testing

/// The `Material(...)` expression a finish writes itself back as: the roster
/// short names, the diff against the defaults, the value formatting, and a
/// compile gate proving every printed label is one the initializer takes.
/// No GPU, so most of it runs in CI; the gate needs the built module beside
/// the test bundle and fails loudly when it cannot find it.
@Suite
struct MaterialSourceTests {

    @Test func theDefaultPrintsBare() {
        #expect(Material().swiftSourceExpression == "Material()")
    }

    @Test func everyPresetPrintsItsName() {
        for entry in Material.paramChoices {
            #expect(entry.value.swiftSource == ".\(entry.name)", "\(entry.name)")
        }
    }

    @Test func onlyTheChangedFieldsPrint() {
        let m = Material(shading: .physicallyBased, metallic: 1, roughness: 0.32)
        #expect(m.swiftSource
            == "Material(shading: .physicallyBased, metallic: 1, roughness: 0.32)")
    }

    @Test func fieldsFollowTheInitializersOrder() {
        // Built out of order on purpose; the printed order is the initializer's.
        var m = Material()
        m.specular = 0.4
        m.toonBands = 6
        m.shading = .toon
        #expect(m.swiftSource == "Material(shading: .toon, toonBands: 6, specular: 0.4)")
    }

    @Test func floatDustDoesNotPrint() {
        // A parameter's value a hair off the default rounds back onto it, so the
        // field stays out of the expression.
        var m = Material()
        m.roughness = 0.5 + 1e-9
        m.specularSharpness = 32.00002
        #expect(m.swiftSourceExpression == "Material()")
    }

    @Test func colorsPrintTheirShortestForm() {
        var m = Material()
        m.sheenColor = Color(red: 0.2, green: 0.4, blue: 0.6)
        #expect(m.swiftSource
            == "Material(sheenColor: Color(red: 0.2, green: 0.4, blue: 0.6))")
        m.sheenColor = Color(white: 0.3)
        #expect(m.swiftSource == "Material(sheenColor: Color(white: 0.3))")
        m.sheenColor = .black
        #expect(m.swiftSource == "Material(sheenColor: .black)")
        m.sheenColor = .white          // back on the default: nothing prints
        #expect(m.swiftSourceExpression == "Material()")
        m.scatteringColor = .white     // this default is not white, so it prints
        #expect(m.swiftSource == "Material(scatteringColor: .white)")
    }

    /// Every field changed at once: the one expression carrying all the labels.
    static let kitchenSink = Material(
        shading: .physicallyBased, toonBands: 7, metallic: 0.8, roughness: 0.21,
        anisotropy: -0.6, anisotropyRotation: 0.7, transmission: 0.9, ior: 1.31,
        thickness: 1.5, attenuationColor: Color(red: 0.9, green: 0.5, blue: 0.2),
        attenuationDistance: 2.5, clearcoat: 0.6, clearcoatRoughness: 0.15,
        sheen: 0.7, sheenColor: Color(red: 0.1, green: 0.2, blue: 0.9),
        sheenRoughness: 0.35, specular: 1.2, specularSharpness: 96,
        iridescence: 0.5, iridescenceScale: 1.8, iridescenceFlow: 0.4,
        iridescencePhase: 0.9, iridescenceFlowSize: 2.5,
        sparkle: 0.65, sparkleSize: 3, sparkleSharpness: 24,
        sparkleColor: Color(white: 0.85),
        rim: 0.45, rimSharpness: 3.5, rimColor: Color(red: 0.3, green: 0.8, blue: 0.5),
        subsurface: 0.55, subsurfaceColor: Color(red: 1, green: 0.8, blue: 0.7),
        scattering: 0.75, scatteringRadius: 1.2, scatteringColor: Color(white: 0.4),
        goochWarm: Color(red: 0.8, green: 0.6, blue: 0.2),
        goochCool: Color(red: 0.1, green: 0.15, blue: 0.4))

    @Test func theKitchenSinkPrintsEveryField() {
        #expect(Self.kitchenSink.swiftSourceExpression == "Material("
            + "shading: .physicallyBased, toonBands: 7, metallic: 0.8, "
            + "roughness: 0.21, anisotropy: -0.6, anisotropyRotation: 0.7, "
            + "transmission: 0.9, ior: 1.31, thickness: 1.5, "
            + "attenuationColor: Color(red: 0.9, green: 0.5, blue: 0.2), "
            + "attenuationDistance: 2.5, clearcoat: 0.6, clearcoatRoughness: 0.15, "
            + "sheen: 0.7, sheenColor: Color(red: 0.1, green: 0.2, blue: 0.9), "
            + "sheenRoughness: 0.35, specular: 1.2, specularSharpness: 96, "
            + "iridescence: 0.5, iridescenceScale: 1.8, iridescenceFlow: 0.4, "
            + "iridescencePhase: 0.9, iridescenceFlowSize: 2.5, "
            + "sparkle: 0.65, sparkleSize: 3, sparkleSharpness: 24, "
            + "sparkleColor: Color(white: 0.85), "
            + "rim: 0.45, rimSharpness: 3.5, rimColor: Color(red: 0.3, green: 0.8, blue: 0.5), "
            + "subsurface: 0.55, subsurfaceColor: Color(red: 1, green: 0.8, blue: 0.7), "
            + "scattering: 0.75, scatteringRadius: 1.2, scatteringColor: Color(white: 0.4), "
            + "goochWarm: Color(red: 0.8, green: 0.6, blue: 0.2), "
            + "goochCool: Color(red: 0.1, green: 0.15, blue: 0.4))")
    }

    /// The compile gate: typecheck the kitchen sink plus every preset's full
    /// form against the built module. A wrong argument label in the emitter
    /// fails here with the compiler's own diagnostic.
    @Test func everyPrintedLabelCompiles() throws {
        var lines = ["import Ollin", "", "let swatches: [Material] = ["]
        lines.append("    \(Self.kitchenSink.swiftSourceExpression),")
        for entry in Material.paramChoices {
            lines.append("    \(entry.value.swiftSourceExpression),")
        }
        lines.append("]")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaterialSourceGate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Swatches.swift")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let arguments = try #require(Self.typecheckArguments(for: file),
                                     "no Ollin.swiftmodule beside the test bundle")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc"] + arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let noise = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                           encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "the emitted source does not typecheck:\n\(noise)")
    }

    /// The `-I` and module-map flags the typecheck needs, found the way the
    /// sketch loader documents. The products dir is an ancestor of the test
    /// resource bundle (its direct parent in the classic layout, a few levels
    /// up when the Xcode build system nests the bundle inside the xctest); the
    /// swiftmodule sits in its `Modules/` subdir (classic) or directly in it
    /// (Xcode build system). C module maps: a `module.modulemap` that is a
    /// direct child of a `*.build` dir (classic), or every named map in the
    /// intermediates' `GeneratedModuleMaps` collection (Xcode build system).
    /// Only one of the two shapes exists per products dir, so the flags never
    /// declare a module twice.
    private static func typecheckArguments(for file: URL) -> [String]? {
        let fm = FileManager.default
        var bin = Bundle.module.bundleURL.deletingLastPathComponent()
        var args = ["-typecheck", file.path]
        var found = false
        for _ in 0..<6 {
            let modules = bin.appendingPathComponent("Modules")
            if fm.fileExists(atPath: modules.appendingPathComponent("Ollin.swiftmodule").path) {
                args += ["-I", modules.path]
                found = true
                break
            }
            if fm.fileExists(atPath: bin.appendingPathComponent("Ollin.swiftmodule").path) {
                args += ["-I", bin.path]
                found = true
                break
            }
            bin = bin.deletingLastPathComponent()
        }
        guard found else { return nil }
        for name in (try? fm.contentsOfDirectory(atPath: bin.path)) ?? []
        where name.hasSuffix(".build") {
            let map = bin.appendingPathComponent(name).appendingPathComponent("module.modulemap")
            if fm.fileExists(atPath: map.path) {
                args += ["-Xcc", "-fmodule-map-file=\(map.path)"]
            }
        }
        let generated = bin.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Intermediates.noindex")
            .appendingPathComponent("GeneratedModuleMaps")
        for name in ((try? fm.contentsOfDirectory(atPath: generated.path)) ?? []).sorted()
        where name.hasSuffix(".modulemap") {
            args += ["-Xcc", "-fmodule-map-file=\(generated.appendingPathComponent(name).path)"]
        }
        return args
    }
}
