import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Ollin

/// The reproduction recipe embedded in exports: its JSON shape, the seed and
/// parameter capture, and the round trips through the formats. The SVG-comment
/// tests run everywhere (no GPU); the video one is Metal-gated like the other
/// video tests. Serialized because the video test shares the GPU.
@Suite(.serialized)
@MainActor
struct ExportMetadataTests {

    final class Seeded: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        @Param(0...300) var radius = 80.0
        override func setup() { seed(7) }
        override func draw() {
            background(.white); noStroke(); fill(.black)
            drawCircle(50, 50, radius)
        }
    }

    /// Extract and parse the recipe JSON from an exported SVG's comment.
    private func recipeJSON(in svg: String) throws -> [String: Any] {
        let comment = try #require(svg.components(separatedBy: "\n").first { $0.contains("<!-- {") })
        let json = comment
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .trimmingCharacters(in: .whitespaces)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }

    @Test func svgCarriesTheRecipe() throws {
        let recipe = try recipeJSON(in: OllinApp.svg(of: Seeded(), frame: 3))
        #expect(recipe["tool"] as? String == "Ollin")
        #expect(recipe["seed"] as? Int == 7)
        #expect(recipe["frame"] as? Int == 3)
        #expect(recipe["fps"] as? Int == 60)
        let params = try #require(recipe["params"] as? [String: Any])
        #expect(params["radius"] as? Int == 80)   // whole numbers print bare
    }

    @Test func separateSeedsRecordSeparately() throws {
        final class Split: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            override func setup() { randomSeed(1); noiseSeed(2) }
            override func draw() { background(.white) }
        }
        let recipe = try recipeJSON(in: OllinApp.svg(of: Split()))
        #expect(recipe["seed"] == nil)
        #expect(recipe["randomSeed"] as? Int == 1)
        #expect(recipe["noiseSeed"] as? Int == 2)
    }

    /// Even an unseeded sketch is recoverable: its rolled `variation` seeds both
    /// generators at init, so the recipe carries the one number that brings the
    /// run back.
    @Test func unseededSketchRecordsItsRolledVariation() throws {
        final class Plain: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            override func draw() { background(.white) }
        }
        let plain = Plain()
        let recipe = try recipeJSON(in: OllinApp.svg(of: plain))
        #expect(recipe["seed"] as? Int == plain.variation)
        #expect(recipe["randomSeed"] == nil)   // one shared seed prints as `seed`
        #expect(recipe["noiseSeed"] == nil)
        #expect(recipe["params"] == nil)
    }

    @Test func sheetRecipeCarriesTheSeedList() throws {
        let json = ExportMetadata.sheetRecipe(seeds: [4, 5, 6], frame: 2, fps: 30)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["tool"] as? String == "Ollin")
        #expect(object["seeds"] as? [Int] == [4, 5, 6])
        #expect(object["frame"] as? Int == 2)
        #expect(object["fps"] as? Int == 30)
    }

    @Test func recipeFormatsParamKinds() {
        let meta = ExportMetadata(
            randomSeed: 5, noiseSeed: 5,
            params: [("flag", .boolean(true)),
                     ("name", .text("a\"b")),
                     ("size", .vector(x: 1.5, y: 2))],
            gitHash: "abc1234-dirty", frame: nil, fps: nil)
        #expect(meta.recipe ==
            #"{"tool":"Ollin","seed":5,"params":{"flag":true,"name":"a\"b","size":[1.5,2]},"git":"abc1234-dirty"}"#)
    }

    /// A plate export is only reproducible if the recipe says which press and
    /// intent made it, so both ride the same line as the seed.
    @Test func recipeCarriesThePrintingCondition() {
        var meta = ExportMetadata(randomSeed: 5, noiseSeed: 5, params: [],
                                  gitHash: nil, frame: nil, fps: nil)
        meta.inks = ["Cyan", "Magenta", "Yellow", "Black"]
        meta.printingCondition = "Generic CMYK Profile / relative"
        #expect(meta.recipe ==
            #"{"tool":"Ollin","seed":5,"inks":["Cyan","Magenta","Yellow","Black"],"printingCondition":"Generic CMYK Profile / relative"}"#)
        // Everything else leaves the field out entirely.
        meta.inks = nil
        meta.printingCondition = nil
        #expect(meta.recipe == #"{"tool":"Ollin","seed":5}"#)
    }

    @Test func pdfCarriesTheRecipeAsSubject() {
        let pdf = OllinApp.pdf(of: Seeded(), frame: 3)
        #expect(pdf.contains(Data(#""tool":"Ollin""#.utf8)))
        #expect(pdf.contains(Data(#""seed":7"#.utf8)))
    }

    @Test func pngRoundTripsTheRecipe() throws {
        let ctx = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let path = NSTemporaryDirectory() + "ollin-metadata-test.png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let recipe = #"{"tool":"Ollin","seed":7}"#
        #expect(OllinApp.writePNG(image, to: path, recipe: recipe))
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let png = try #require(props[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        #expect(png[kCGImagePropertyPNGDescription] as? String == recipe)
        #expect(png[kCGImagePropertyPNGSoftware] as? String == "Ollin")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func videoCarriesTheRecipe() async throws {
        let path = NSTemporaryDirectory() + "ollin-metadata-test.mp4"
        defer { try? FileManager.default.removeItem(atPath: path) }
        OllinApp.exportVideo(Seeded(), to: path, frames: 4, fps: 30)
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        // The container stores the item under its native key space, so match by
        // common key rather than the identifier the writer was handed.
        let metadata = try await asset.load(.commonMetadata)
        let description = try #require(metadata.first { $0.commonKey == .commonKeyDescription })
        let value = try #require(try await description.load(.stringValue))
        #expect(value.contains(#""seed":7"#))
    }
}
