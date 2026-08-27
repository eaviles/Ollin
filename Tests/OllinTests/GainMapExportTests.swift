import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import Ollin

/// Probes for the gain map an `extended` still carries.
///
/// The claim is narrow and checkable: the picture in the file is the frame
/// clamped at white (what the PNG already writes), and a reader with headroom
/// gets the frame back. So every test here writes a file and reads it twice,
/// once plainly and once expanded, and compares both against the frame the
/// renderer produced.
///
/// The two failure modes worth guarding are not obvious ones. A gain map worked
/// out from image statistics throws a *small* highlight away, and a gain map
/// with one channel instead of three wrecks a *colored* one. Both look fine in
/// a thumbnail and both are measured below.
@Suite
@MainActor
struct GainMapExportTests {

    // MARK: Sketches under test

    /// A dim field with one small bright core, which is the ordinary shape of a
    /// sketch highlight and the case a statistics-driven gain map loses.
    private final class Core: Sketch {
        var output: ColorOutput = .extended
        var core: Color = Color(white: 4)
        var side = 64
        override var colorOutput: ColorOutput { output }
        override var canvasSize: CanvasSize { .square(side) }

        override func draw() {
            background(Color(white: 0.4))
            noStroke()
            fill(core)
            // About 1.5% of the frame, well under the quarter that a
            // statistics-driven map needs before it keeps the peak.
            drawRect(Double(side) / 2 - 4, Double(side) / 2 - 4, 8, 8)
        }
    }

    // MARK: Reading files back

    private func context() -> CIContext { GainMap.makeContext() }

    /// Every pixel of `url`, in the extended linear space the frame was in.
    /// `expanded` asks for the gain map to be applied.
    private func pixels(of url: URL, expanded: Bool, width: Int, height: Int) throws -> [Float] {
        let options: [CIImageOption: Any] = expanded ? [.expandToHDR: true] : [:]
        let image = try #require(CIImage(contentsOf: url, options: options))
        var out = [Float](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        out.withUnsafeMutableBytes { buffer in
            context().render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16,
                             bounds: image.extent, format: .RGBAf, colorSpace: space)
        }
        return out
    }

    /// The brightest component in a buffer, and the color of the pixel holding
    /// it.
    private func brightest(_ buffer: [Float]) -> (peak: Float, color: SIMD3<Float>) {
        var peak: Float = -1
        var color = SIMD3<Float>()
        for p in stride(from: 0, to: buffer.count, by: 4) {
            let c = SIMD3(buffer[p], buffer[p + 1], buffer[p + 2])
            if c.max() > peak { peak = c.max(); color = c }
        }
        return (peak, color)
    }

    private func temporary(_ name: String) -> URL {
        ollinTempURL("ollin-gainmap-\(name)")
    }

    /// The frame the renderer produced, as floats, so a file can be compared
    /// against its own source rather than against a guess. Only a wide or
    /// extended sketch has float samples; an eight-bit one has none, which is
    /// itself the reason it can carry no gain map.
    private func rendered(_ sketch: Sketch) throws -> (image: CGImage, samples: GainMap.Samples) {
        let image = try #require(OllinApp.image(of: sketch))
        let samples = try #require(GainMap.floatSamples(of: image, context: context()))
        return (image, samples)
    }

    // MARK: The frame comes back

    @Test("a small highlight keeps its true brightness")
    func smallHighlightSurvives() throws {
        let sketch = Core()
        let (image, frame) = try rendered(sketch)
        #expect(frame.peak > 3.5, "the sketch should draw well above white")

        let url = temporary("small.heic")
        let written = try #require(OllinApp.writeHEIC(image, to: url.path))
        #expect(written.keepsHighlights)
        #expect(abs(written.peak - Double(frame.peak)) < 0.01)

        let expanded = try pixels(of: url, expanded: true, width: image.width, height: image.height)
        let peak = brightest(expanded).peak
        // The base is eight bits, so a fraction of a percent is the floor here.
        #expect(abs(peak / frame.peak - 1) < 0.02,
                "read \(peak) back from a frame whose peak was \(frame.peak)")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("a colored highlight keeps its color")
    func colouredHighlightKeepsItsHue() throws {
        let sketch = Core()
        // Clamping this per channel gives (1, 1, 0.72), so the three channels
        // need three different gains. One gain for all three cannot do it.
        sketch.core = Color(red: 4, green: 2.2, blue: 0.72)
        let (image, frame) = try rendered(sketch)

        let url = temporary("color.heic")
        _ = try #require(OllinApp.writeHEIC(image, to: url.path))
        let expanded = try pixels(of: url, expanded: true, width: image.width, height: image.height)
        let got = brightest(expanded).color
        let want = brightest(frame.pixels).color
        for channel in 0..<3 {
            let error = abs(got[channel] / max(want[channel], 1e-4) - 1)
            #expect(error < 0.03,
                    "channel \(channel) came back \(got[channel]), wanted \(want[channel])")
        }
        try? FileManager.default.removeItem(at: url)
    }

    @Test("an odd canvas width still lines up")
    func unalignedWidthSurvives() throws {
        // The gain map's rows are padded to a boundary, so a width that is not a
        // multiple of it is the case that would shear the map against the
        // picture.
        let sketch = Core()
        sketch.side = 61
        let (image, frame) = try rendered(sketch)
        let url = temporary("odd.heic")
        _ = try #require(OllinApp.writeHEIC(image, to: url.path))
        let expanded = try pixels(of: url, expanded: true, width: image.width, height: image.height)
        #expect(abs(brightest(expanded).peak / frame.peak - 1) < 0.02)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: What a reader without headroom sees

    @Test("the picture in the file stops at white")
    func baseStopsAtWhite() throws {
        let sketch = Core()
        let (image, _) = try rendered(sketch)
        let url = temporary("base.heic")
        _ = try #require(OllinApp.writeHEIC(image, to: url.path))
        let plain = try pixels(of: url, expanded: false, width: image.width, height: image.height)
        #expect(brightest(plain).peak <= 1.01,
                "a reader without headroom must never be handed a value above white")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("the picture in the file is the frame clamped at white")
    func baseMatchesTheClampedFrame() throws {
        let sketch = Core()
        let (image, frame) = try rendered(sketch)
        let url = temporary("clamped.heic")
        _ = try #require(OllinApp.writeHEIC(image, to: url.path))
        let plain = try pixels(of: url, expanded: false, width: image.width, height: image.height)
        var worst: Float = 0
        for i in stride(from: 0, to: plain.count, by: 4) {
            for channel in 0..<3 {
                let want = min(max(frame.pixels[i + channel], 0), 1)
                worst = max(worst, abs(plain[i + channel] - want))
            }
        }
        #expect(worst < 0.01, "the picture drifted from the clamped frame by \(worst)")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: When there is nothing to keep

    @Test("a frame that never leaves 0...1 carries no gain map")
    func noHighlightsNoMap() throws {
        let sketch = Core()
        sketch.core = Color(white: 0.9)
        let (image, _) = try rendered(sketch)
        let url = temporary("flat.heic")
        let written = try #require(OllinApp.writeHEIC(image, to: url.path))
        #expect(!written.keepsHighlights)
        #expect(written.peak <= 1.01)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let map = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap)
        #expect(map == nil, "an ordinary frame should not pay for a gain map")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("a wide sketch writes a wide still with no map")
    func wideOutputKeepsItsColours() throws {
        // A wide-gamut frame has floats but nothing above white, so it takes the
        // same picture-building path as an extended one and simply gets no map.
        let sketch = Core()
        sketch.output = .wide
        sketch.core = Color(displayP3: 1, green: 0, blue: 0)
        let (image, frame) = try rendered(sketch)
        let url = temporary("wide.heic")
        let written = try #require(OllinApp.writeHEIC(image, to: url.path))
        #expect(!written.keepsHighlights)

        let plain = try pixels(of: url, expanded: false, width: image.width, height: image.height)
        var worst: Float = 0
        for i in stride(from: 0, to: plain.count, by: 4) {
            for channel in 0..<3 {
                let want = min(max(frame.pixels[i + channel], 0), 1)
                worst = max(worst, abs(plain[i + channel] - want))
            }
        }
        #expect(worst < 0.01, "the wide-gamut picture drifted by \(worst)")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("a standard sketch writes an ordinary still")
    func standardOutputWritesNoMap() throws {
        let sketch = Core()
        sketch.output = .standard
        let image = try #require(OllinApp.image(of: sketch))
        #expect(GainMap.floatSamples(of: image, context: context()) == nil,
                "an eight-bit frame has no values above white to read")
        let url = temporary("standard.heic")
        let written = try #require(OllinApp.writeHEIC(image, to: url.path))
        #expect(!written.keepsHighlights, "eight bits cannot hold anything above white")

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.heic")
        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeISOGainMap) == nil)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: The file says what it is

    @Test("the gain map is the ISO one, not a private form")
    func theMapIsTheStandardOne() throws {
        let sketch = Core()
        let (image, _) = try rendered(sketch)
        let url = temporary("iso.heic")
        _ = try #require(OllinApp.writeHEIC(image, to: url.path))

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let iso = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeISOGainMap) as? [CFString: Any]
        #expect(iso != nil, "the map should be readable as the standard one")

        let description = try #require(iso?[kCGImageAuxiliaryDataInfoDataDescription] as? [CFString: Any])
        #expect(description["Width" as CFString] as? Int == image.width)
        #expect(description["Height" as CFString] as? Int == image.height)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("the ceiling written is the frame's own peak")
    func theCeilingIsTheFramesPeak() throws {
        let sketch = Core()
        let (image, frame) = try rendered(sketch)
        let url = temporary("ceiling.heic")
        _ = try #require(OllinApp.writeHEIC(image, to: url.path))

        // Applying the map at a headroom far past anything real is limited to
        // the map's own declared ceiling, so what comes back *is* that ceiling.
        // A separate claim from the reconstruction tests, which read the file
        // the way a display would.
        let base = try #require(CIImage(contentsOf: url))
        let map = try #require(CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true]))
        let full = base.applyingGainMap(map, headroom: 100)

        var out = [Float](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        out.withUnsafeMutableBytes { buffer in
            context().render(full, toBitmap: buffer.baseAddress!, rowBytes: image.width * 16,
                             bounds: full.extent, format: .RGBAf, colorSpace: space)
        }
        let ceiling = brightest(out).peak
        #expect(abs(ceiling / frame.peak - 1) < 0.02,
                "the file declares \(ceiling)x for a frame peaking at \(frame.peak)x")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("the reproduction recipe travels with the still")
    func theRecipeSurvives() throws {
        let sketch = Core()
        let (image, _) = try rendered(sketch)
        let url = temporary("recipe.heic")
        let recipe = "{\"tool\":\"Ollin\",\"seed\":42}"
        _ = try #require(OllinApp.writeHEIC(image, to: url.path, recipe: recipe))

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFSoftware] as? String == "Ollin")
        #expect(exif?[kCGImagePropertyExifUserComment] as? String == recipe)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: The flag surface

    @Test("the file name picks the format")
    func exportPicksTheFormatFromThePath() throws {
        let heic = temporary("flag.heic")
        OllinApp.export(Core(), to: heic.path)
        let source = try #require(CGImageSourceCreateWithURL(heic as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.heic")
        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil)

        let png = temporary("flag.png")
        OllinApp.export(Core(), to: png.path)
        let pngSource = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
        #expect(CGImageSourceGetType(pngSource) as String? == "public.png")

        try? FileManager.default.removeItem(at: heic)
        try? FileManager.default.removeItem(at: png)
    }
}
