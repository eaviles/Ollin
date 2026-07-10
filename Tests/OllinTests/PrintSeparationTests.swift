import Foundation
@testable import Ollin
import Testing

/// A print separation makes two promises: the masters it writes mean what the
/// press thinks they mean (byte = ink fraction, black = full ink), and the
/// preview it shows is the overprint those masters actually make. The tests
/// pin the physical model (translucent inks multiply on paper), the search
/// (drawing with an ink color comes back as that ink, and a predicted
/// overprint separates back to its coverages), the screening passes (binary
/// output that conserves tone), and determinism end to end.
@Suite
struct PrintSeparationTests {

    // MARK: - The overprint model

    /// The community's overprint chart, as physics: blue over yellow reads
    /// green, pink over yellow reads orange-red, pink over blue reads violet.
    /// The model multiplies transmittances in linear light, so these fall out.
    @Test func overprintsMixTheWayInksDo() {
        func overprint(_ a: Ink, _ b: Ink) -> SIMD3<Double> {
            OverprintModel(paper: .white, inks: [a, b]).predict([1, 1])
        }

        let green = overprint(.blue, .yellow)
        #expect(green.y > green.x && green.y > green.z)

        let orange = overprint(.fluorescentPink, .yellow)
        #expect(orange.x > orange.y && orange.y >= orange.z)

        let violet = overprint(.fluorescentPink, .blue)
        #expect(violet.z > violet.y)
    }

    /// No coverage shows bare paper; ink only darkens what is under it.
    @Test func inkOnlyDarkens() {
        let model = OverprintModel(paper: .white, inks: [.blue, .yellow])
        let bare = model.predict([0, 0])
        #expect(bare == SIMD3(1, 1, 1))
        let some = model.predict([0.4, 0.7])
        #expect(some.x <= bare.x && some.y <= bare.y && some.z <= bare.z)
    }

    // MARK: - Separation

    /// Drawing with an ink's own color separates to solid ink on that layer
    /// and nothing on the others.
    @Test func inkColorSeparatesExactly() {
        let flat = Image(width: 4, height: 4, color: Ink.fluorescentPink.color)
        let sep = flat.separated(into: [.fluorescentPink, .blue])

        #expect(sep.layers.count == 2)
        #expect(masterByte(sep.layers[0]) <= 2)     // solid pink
        #expect(masterByte(sep.layers[1]) >= 253)   // no blue
    }

    /// Bare paper wants no ink at all.
    @Test func paperSeparatesToNothing() {
        let flat = Image(width: 4, height: 4, color: .white)
        let sep = flat.separated(into: [.black, .fluorescentPink, .yellow])
        for layer in sep.layers {
            #expect(masterByte(layer) >= 254)
        }
    }

    /// A color built by the model from known coverages separates back to an
    /// overprint that looks the same: the preview must land within a
    /// just-noticeable OKLab distance of the source color.
    @Test func predictedOverprintRoundTrips() {
        let model = OverprintModel(paper: .white, inks: [.blue, .yellow])
        let linear = model.predict([0.6, 0.3])
        let color = Color(red: Color.linearToSrgb(linear.x),
                          green: Color.linearToSrgb(linear.y),
                          blue: Color.linearToSrgb(linear.z))

        let sep = Image(width: 4, height: 4, color: color)
            .separated(into: [.blue, .yellow])
        let reproduced = sep.preview()[2, 2]
        #expect(labDistance(color, reproduced) < 0.02)
    }

    /// A gray on black-and-pink drums must not turn pink: the search weighs
    /// the whole ink set, and black alone reaches gray best.
    @Test func grayStaysNeutral() {
        let gray = Color(red: 0.5, green: 0.5, blue: 0.5)
        let sep = Image(width: 4, height: 4, color: gray)
            .separated(into: [.black, .fluorescentPink])
        let reproduced = sep.preview()[2, 2]
        #expect(labDistance(gray, reproduced) < 0.03)
        #expect(masterByte(sep.layers[1]) >= 240)   // pink stays out of it
    }

    /// A translucent pixel composites over the stock before separating: fully
    /// transparent is bare paper, half-black is roughly half ink.
    @Test func translucencyCompositesOverPaper() {
        var image = Image(width: 4, height: 4, color: .clear)
        for y in 0..<4 {
            for x in 0..<4 {
                image[x, y] = Color.black.withAlpha(x < 2 ? 0 : 0.5)
            }
        }
        let sep = image.separated(into: [.black])
        let bytes = sep.layers[0].master.premultipliedPixels()!
        #expect(bytes[0] == 255)                        // transparent: no ink
        let half = 1 - Double(bytes[2 * 4]) / 255       // half-black column
        // Half of black's *linear* light is mid-coverage ink, not byte 128.
        #expect(abs(half - 0.5) < 0.1)
    }

    /// The same image, inks, and paper give byte-identical masters twice over.
    @Test func separationIsDeterministic() {
        let source = gradient(width: 24, height: 16)
        let a = source.separated(into: [.blue, .fluorescentPink, .yellow])
        let b = source.separated(into: [.blue, .fluorescentPink, .yellow])
        for (la, lb) in zip(a.layers, b.layers) {
            #expect(la.master.premultipliedPixels() == lb.master.premultipliedPixels())
        }
    }

    /// An empty ink list separates to no layers, and the preview of an empty
    /// separation is just the paper.
    @Test func emptyInksSeparateToNothing() {
        let sep = gradient(width: 8, height: 8).separated(into: [])
        #expect(sep.layers.isEmpty)
        #expect(near(sep.preview()[4, 4], .white))
    }

    // MARK: - Masters and coverage

    /// The master byte is the ink fraction directly: a mid-gray on a black
    /// drum wants mid coverage, written as a mid byte.
    @Test func averageInkReadsCoverage() {
        let model = OverprintModel(paper: .white, inks: [.black])
        let linear = model.predict([0.5])
        let color = Color(red: Color.linearToSrgb(linear.x),
                          green: Color.linearToSrgb(linear.y),
                          blue: Color.linearToSrgb(linear.z))
        let sep = Image(width: 8, height: 8, color: color).separated(into: [.black])
        #expect(abs(sep.layers[0].averageInk - 0.5) < 0.02)
    }

    // MARK: - Screening

    /// Every screening pass emits pure black-and-white masters.
    @Test func screeningIsBinary() {
        let sep = gradient(width: 32, height: 32)
            .separated(into: [.blue, .fluorescentPink])
        for screened in [sep.dithered(.blueNoise), sep.dithered(.floydSteinberg),
                         sep.dithered(.ordered(size: 8)), sep.halftoned(pitch: 6)] {
            for layer in screened.layers {
                let bytes = layer.master.premultipliedPixels()!
                var p = 0
                while p < bytes.count {
                    #expect(bytes[p] == 0 || bytes[p] == 255)
                    p += 4
                }
            }
        }
    }

    /// Screening conserves tone: a flat 30% layer keeps ~30% of its pixels
    /// inked, because coverage is the linear quantity the dots average to.
    @Test func screeningConservesCoverage() {
        let model = OverprintModel(paper: .white, inks: [.black])
        let linear = model.predict([0.3])
        let color = Color(red: Color.linearToSrgb(linear.x),
                          green: Color.linearToSrgb(linear.y),
                          blue: Color.linearToSrgb(linear.z))
        let sep = Image(width: 64, height: 64, color: color).separated(into: [.black])

        #expect(abs(sep.dithered(.blueNoise).layers[0].averageInk - 0.3) < 0.03)
        #expect(abs(sep.dithered(.floydSteinberg).layers[0].averageInk - 0.3) < 0.03)
        #expect(abs(sep.halftoned(pitch: 8).layers[0].averageInk - 0.3) < 0.05)
    }

    /// Coverage a press cannot hold is dropped before screening: a barely
    /// off-white (the residue 8-bit rounding leaves) screens to bare paper
    /// instead of stray specks, and a barely off-solid to full ink.
    @Test func screeningDropsUnprintableDots() {
        let nearWhite = Color(red: 1, green: 1, blue: 254.0 / 255)
        let faint = Image(width: 32, height: 32, color: nearWhite)
            .separated(into: [.yellow])
        #expect(faint.layers[0].averageInk > 0)   // the residue is in the master
        #expect(faint.dithered(.blueNoise).layers[0].averageInk == 0)
        #expect(faint.halftoned(pitch: 6).layers[0].averageInk == 0)

        let nearBlack = Color(red: 3.0 / 255, green: 3.0 / 255, blue: 3.0 / 255)
        let dense = Image(width: 32, height: 32, color: nearBlack)
            .separated(into: [.black])
        #expect(dense.dithered(.blueNoise).layers[0].averageInk == 1)
        #expect(dense.halftoned(pitch: 6).layers[0].averageInk == 1)
    }

    /// The default halftone screens rotate per layer, darkest ink at 45
    /// degrees, so the drums do not moire against each other.
    @Test func halftoneAnglesFollowConvention() {
        let angles = PrintSeparation.screenAngles(for: [.yellow, .black, .blue])
        #expect(abs(angles[1] - .pi / 4) < 1e-9)        // black takes 45
        #expect(Set(angles.map { Int(($0 * 180 / .pi).rounded()) }).count == 3)
    }

    /// Screening twice gives the same dots: the passes carry no hidden state.
    @Test func screeningIsDeterministic() {
        let sep = gradient(width: 24, height: 24).separated(into: [.blue, .yellow])
        let a = sep.halftoned(pitch: 5)
        let b = sep.halftoned(pitch: 5)
        for (la, lb) in zip(a.layers, b.layers) {
            #expect(la.master.premultipliedPixels() == lb.master.premultipliedPixels())
        }
    }

    // MARK: - The ink catalog

    /// Catalog lookup ignores case, spaces, and hyphens, and stays honest
    /// about unknowns.
    @Test func inkLookupIsForgiving() {
        #expect(Ink.named("fluorescent pink") == .fluorescentPink)
        #expect(Ink.named("Flat-Gold") == .flatGold)
        #expect(Ink.named("BLACK") == .black)
        #expect(Ink.named("cadmium slime") == nil)
    }

    /// The catalog carries the full standard set, distinctly named.
    @Test func catalogIsWellFormed() {
        #expect(Ink.catalog.count == 78)
        #expect(Set(Ink.catalog.map(\.name)).count == Ink.catalog.count)
    }

    // MARK: - Helpers

    private func masterByte(_ layer: PrintSeparation.Layer) -> Int {
        Int(layer.master.premultipliedPixels()![0])
    }

    private func labDistance(_ a: Color, _ b: Color) -> Double {
        let la = OKLab(a), lb = OKLab(b)
        let dl = la.l - lb.l, da = la.a - lb.a, db = la.b - lb.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    private func near(_ a: Color, _ b: Color) -> Bool {
        abs(a.red - b.red) < 0.02 && abs(a.green - b.green) < 0.02
            && abs(a.blue - b.blue) < 0.02
    }

    /// A horizontal white-to-color-to-black sweep with enough distinct colors
    /// to exercise the memoized search.
    private func gradient(width: Int, height: Int) -> Image {
        var image = Image(width: width, height: height, color: .white)
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(x) / Double(width - 1)
                let v = Double(y) / Double(max(1, height - 1))
                image[x, y] = Color(red: t, green: (1 - t) * v, blue: 1 - v)
            }
        }
        return image
    }
}
