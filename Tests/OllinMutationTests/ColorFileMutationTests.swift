import CoreGraphics
import Foundation
import Testing
import OllinMutation
@testable import Ollin

/// The color files a sketch is handed: a `.cube` look, a palette in any of the
/// four shapes it arrives in, and an ICC profile. Each is read, then read back
/// the way a sketch reads it: a look asked for colors, a palette's colors
/// turned into hue and back, a profile's channels named.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct ColorFileMutationTests {

    static let probes: [Color] = [.black, .white, Color(red: 0.3, green: 0.6, blue: 0.9),
                                  Color(red: 1, green: 0, blue: 0.5, alpha: 0.5)]

    @Test func cubeFiles() {
        let cube = ColorLUT(size: 3, title: "Cooler") { c in
            Color(red: c.red * 0.9, green: c.green, blue: min(1, c.blue * 1.1))
        }.cubeText
        let curves = "TITLE \"curves\"\nLUT_1D_SIZE 3\nLUT_1D_INPUT_RANGE 0 1\n0 0 0\n0.5 0.4 0.6\n1 1 1\n"
        let report = MutationRun.run("cube-file", seeds: [cube.bytes, curves.bytes], count: 600,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let look = try ColorLUT(data: Data(bytes))
            for probe in Self.probes { _ = look.color(for: probe) }
            _ = look.cubeText
            _ = look.domainScale
            _ = look.domainOffset
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func paletteFiles() {
        let hexLines = "#1b2a41\n#324a5f\n#ccc9dc\n0xFF6600\n'ab12cd'\n"
        let csv = "name,a,b,c\nsunset,#ff7e5f,#feb47b,#ffcf71\nsea,#2e8bc0,#b1d4e0,#0c2d48\n"
        let tsv = "#101010\t#202020\t#303030\n#ff0000\t#00ff00\t#0000ff\n"
        let json = ##"[{"colors": ["#ff0000", "#00ff00"]}, ["#123", "#4567", "#89abcd", "#ef012345"]]"##
        let report = MutationRun.run("palette-file",
                                     seeds: [hexLines.bytes, csv.bytes, tsv.bytes, json.bytes, Self.aseFile()],
                                     count: 600, numberSweep: true, allocations: fileBound) { bytes in
            let palettes = Palette.palettes(data: Data(bytes))
            for palette in palettes { Self.read(palette) }
            for format in [PaletteFormat.hexLines, .csv, .tsv, .json, .ase] {
                for palette in Palette.palettes(data: Data(bytes), format: format) { Self.read(palette) }
            }
            return !palettes.isEmpty
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    /// A palette read as a sketch reads one: every color by its components
    /// and turned around through hue, and the palette sampled along its length.
    static func read(_ palette: Palette) {
        for color in palette.colors {
            _ = Color(hue: color.hue, saturation: color.saturation, brightness: color.brightness)
            _ = color.withAlpha(0.5)
        }
        for t in stride(from: 0.0, through: 1.0, by: 0.25) { _ = palette.color(at: t) }
    }

    @Test func iccProfiles() throws {
        let seeds = [CGColorSpace.sRGB, CGColorSpace.genericGrayGamma2_2]
            .compactMap { CGColorSpace(name: $0)?.copyICCData() as Data? }
            .map { [UInt8]($0) }
        try #require(seeds.count == 2)
        let report = MutationRun.run("icc-profile", seeds: seeds, count: 150, allocations: fileBound) { bytes in
            guard let profile = ICCProfile(data: Data(bytes)) else { return false }
            _ = profile.name
            _ = profile.channelNames
            _ = SoftProof(profile)
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    // MARK: Adobe Swatch Exchange

    /// A small swatch file written from the published layout: two groups and a
    /// loose swatch, in each of the four color models the reader knows.
    static func aseFile() -> [UInt8] {
        var out: [UInt8] = Array("ASEF".utf8) + [0, 1, 0, 0]
        var blocks: [[UInt8]] = []
        func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
        func u32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func f32(_ v: Float) -> [UInt8] { u32(v.bitPattern) }
        func name(_ text: String) -> [UInt8] {
            let units = Array(text.utf16) + [0]
            return u16(UInt16(units.count)) + units.flatMap(u16)
        }
        func block(_ type: UInt16, _ body: [UInt8]) -> [UInt8] { u16(type) + u32(UInt32(body.count)) + body }
        blocks.append(block(0xC001, name("warm")))
        blocks.append(block(0x0001, name("red") + Array("RGB ".utf8) + f32(1) + f32(0) + f32(0) + u16(2)))
        blocks.append(block(0x0001, name("ink") + Array("CMYK".utf8) + f32(0.1) + f32(0.2) + f32(0.3) + f32(0.4) + u16(0)))
        blocks.append(block(0xC002, []))
        blocks.append(block(0xC001, name("cool")))
        blocks.append(block(0x0001, name("mist") + Array("Gray".utf8) + f32(0.5) + u16(2)))
        blocks.append(block(0x0001, name("sea") + Array("LAB ".utf8) + f32(0.5) + f32(-20) + f32(-30) + u16(2)))
        blocks.append(block(0xC002, []))
        blocks.append(block(0x0001, name("loose") + Array("RGB ".utf8) + f32(0.2) + f32(0.4) + f32(0.6) + u16(2)))
        out += u32(UInt32(blocks.count))
        for b in blocks { out += b }
        return out
    }
}
