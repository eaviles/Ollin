import Foundation
@testable import Ollin
import Testing

/// Print color management: ICC profiles, the soft proof, the gamut check, and
/// the process-color plates. All CPU work through the system color engine, no
/// Metal, so these run everywhere.
@Suite
struct PrintColorTests {

    private let cmyk = SoftProof(.genericCMYK)

    /// An image of one flat color, opaque.
    private func flat(_ color: Color, size: Int = 8) -> Image {
        Image(width: size, height: size, color: color)
    }

    /// The mean color of an image, read back through its pixels.
    private func mean(_ image: Image) -> Color {
        guard let bytes = image.premultipliedPixels() else { return .clear }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        let count = image.width * image.height
        for p in 0 ..< count {
            let i = p * 4
            r += Double(bytes[i]); g += Double(bytes[i + 1])
            b += Double(bytes[i + 2]); a += Double(bytes[i + 3])
        }
        let n = Double(count) * 255
        return Color(red: r / n, green: g / n, blue: b / n, alpha: a / n)
    }

    // MARK: Profiles

    @Test func builtInProfilesDescribeThemselves() {
        #expect(ICCProfile.sRGB.space == .rgb)
        #expect(ICCProfile.sRGB.channelCount == 3)
        #expect(ICCProfile.sRGB.isUsable)
        #expect(!ICCProfile.sRGB.name.isEmpty)

        #expect(ICCProfile.displayP3.space == .rgb)
        #expect(ICCProfile.genericGray.space == .gray)
        #expect(ICCProfile.genericGray.channelCount == 1)

        #expect(ICCProfile.genericCMYK.space == .cmyk)
        #expect(ICCProfile.genericCMYK.channelCount == 4)
        #expect(ICCProfile.genericCMYK.channelNames == ["Cyan", "Magenta", "Yellow", "Black"])
        // A press profile describes an output device; a working space does not.
        #expect(ICCProfile.genericCMYK.isOutputDevice)
        #expect(!ICCProfile.sRGB.isOutputDevice)
    }

    @Test func profilesLoadFromBytesAndRejectRubbish() {
        let reloaded = ICCProfile(data: ICCProfile.sRGB.data)
        #expect(reloaded == ICCProfile.sRGB)
        #expect(reloaded?.name == ICCProfile.sRGB.name)
        #expect(ICCProfile(data: Data(repeating: 7, count: 400)) == nil)
        #expect(ICCProfile(data: Data()) == nil)
        // Different profiles are different values, which is what keys the
        // transform cache.
        #expect(ICCProfile.sRGB != ICCProfile.displayP3)
    }

    @Test func theMachinesProfilesAreFound() {
        let installed = ICCProfile.installed()
        #expect(installed.count >= 5)
        #expect(installed.contains { $0.space == .cmyk })
        // The system set is always there, whatever else a studio has added.
        #expect(ICCProfile.installed(named: "Generic CMYK Profile") != nil)
        #expect(ICCProfile.installed(named: "no such profile anywhere") == nil)
    }

    @Test func canvasProfileFollowsColorOutput() {
        #expect(ICCProfile.canvas(.standard) == .sRGB)
        #expect(ICCProfile.canvas(.wide) == .displayP3)
        #expect(ICCProfile.canvas(.extended) == .displayP3)
    }

    // MARK: The proof itself

    /// Proofing a space against itself has to change nothing, which is the
    /// control every other reading here is measured against.
    @Test func proofingAgainstTheSameSpaceIsIdentity() {
        let identity = SoftProof(.sRGB)
        for color in [Color.red, .green, .blue, Color(white: 0.5), .white, .black] {
            let proofed = mean(flat(color).softProofed(identity))
            #expect(abs(proofed.red - color.red) < 0.01)
            #expect(abs(proofed.green - color.green) < 0.01)
            #expect(abs(proofed.blue - color.blue) < 0.01)
        }
    }

    @Test func inkCannotHoldTheScreensSaturation() {
        // A screen red is far outside a four-ink gamut, so the proof has to
        // come back less colorful. Chroma is the honest measure of "less
        // colorful", and it is measured perceptually.
        for color in [Color.red, .green, .blue] {
            let proofed = mean(flat(color).softProofed(cmyk))
            #expect(OKLCH(proofed).c < OKLCH(color).c - 0.02)
        }
        // A muted color the press can hold survives the trip.
        let tan = Color(red: 0.8, green: 0.6, blue: 0.35)
        let proofedTan = mean(flat(tan).softProofed(cmyk))
        #expect(abs(OKLCH(proofedTan).c - OKLCH(tan).c) < 0.03)
    }

    @Test func printedBlackIsLighterThanScreenBlack() {
        // Ink on paper does not reach a black pixel's black, and the proof is
        // run without black point compensation so it says so.
        let proofedBlack = mean(flat(.black).softProofed(cmyk))
        #expect(proofedBlack.luminance > 0.001)
        #expect(proofedBlack.luminance < 0.05)
        // White stays white unless the paper is being simulated.
        let proofedWhite = mean(flat(.white).softProofed(cmyk))
        #expect(proofedWhite.luminance > 0.9)
    }

    @Test func paperSimulationTintsTheWhite() {
        var withPaper = cmyk
        withPaper.simulatePaper = true
        let plain = mean(flat(.white).softProofed(cmyk))
        let onPaper = mean(flat(.white).softProofed(withPaper))
        // Simulated stock is darker than paper-white and no longer neutral.
        #expect(onPaper.luminance < plain.luminance - 0.02)
        #expect(OKLCH(onPaper).c > OKLCH(plain).c)
    }

    @Test func intentIsCarriedIntoTheTransform() {
        // Absolute and relative disagree about white, which is the difference
        // that proves the intent reached the color engine rather than being
        // dropped on the way.
        let relative = SoftProof(.genericCMYK, intent: .relative)
        let absolute = SoftProof(.genericCMYK, intent: .absolute)
        let a = mean(flat(.white).softProofed(relative))
        let b = mean(flat(.white).softProofed(absolute))
        #expect(abs(a.luminance - b.luminance) > 0.01)
    }

    @Test func alphaSurvivesTheProof() {
        let translucent = flat(Color(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.5))
        let proofed = translucent.softProofed(cmyk)
        #expect(abs(mean(proofed).alpha - 0.5) < 0.01)
    }

    // MARK: The gamut check

    @Test func theGamutCheckFlagsWhatInkCannotReach() {
        #expect(flat(.red).outOfGamutFraction(cmyk) > 0.99)
        #expect(flat(.green).outOfGamutFraction(cmyk) > 0.99)
        #expect(flat(Color(white: 0.5)).outOfGamutFraction(cmyk) < 0.01)
        #expect(flat(.white).outOfGamutFraction(cmyk) < 0.01)

        // The mask is the same answer as an image: white where it will not print.
        let mask = flat(.red).gamutMask(cmyk)
        #expect(mean(mask).red > 0.99)
        #expect(mean(flat(Color(white: 0.4)).gamutMask(cmyk)).red < 0.01)
    }

    @Test func theWarningColorReplacesWhatWillNotPrint() {
        let flagged = flat(.red).softProofed(cmyk, warning: .green)
        let color = mean(flagged)
        #expect(color.green > 0.9)
        #expect(color.red < 0.1)
        // A color the press can hold is left as the proof made it.
        let safe = mean(flat(Color(white: 0.5)).softProofed(cmyk, warning: .green))
        #expect(safe.green < 0.7)
    }

    @Test func aProofAgainstAnUnreadableProfileChangesNothing() {
        let broken = SoftProof(ICCProfile(empty: "nothing"))
        let source = flat(.red)
        let proofed = source.softProofed(broken)
        #expect(mean(proofed).red > 0.99)
        #expect(source.separated(into: broken).plates.isEmpty)
    }

    // MARK: Process plates

    @Test func plateCountAndNamesFollowTheProfile() {
        let plates = flat(Color(red: 0.4, green: 0.5, blue: 0.7)).separated(into: .genericCMYK)
        #expect(plates.plates.count == 4)
        #expect(plates.plates.map(\.name) == ["Cyan", "Magenta", "Yellow", "Black"])
        #expect(plates.width == 8 && plates.height == 8)

        let gray = flat(Color(white: 0.5)).separated(into: .genericGray)
        #expect(gray.plates.count == 1)
        #expect(gray.plates[0].name == "Gray")
    }

    @Test func paperTakesNoInkAndBlackTakesPlenty() {
        let white = flat(.white).separated(into: .genericCMYK)
        #expect(white.peakTotalInk < 0.02)
        for plate in white.plates { #expect(plate.averageInk < 0.01) }

        let black = flat(.black).separated(into: .genericCMYK)
        // The black plate carries the most of it, which is what black
        // generation in a press profile is for.
        #expect(black.plates[3].averageInk > 0.5)
        #expect(black.peakTotalInk > 1.5)
        // Nothing asks for more ink than four solid inks can lay down.
        #expect(black.peakTotalInk <= 4.0)
    }

    @Test func totalInkIsTheSumOfThePlates() {
        let art = flat(Color(red: 0.15, green: 0.2, blue: 0.35))
        let plates = art.separated(into: .genericCMYK)
        let summed = plates.plates.map(\.averageInk).reduce(0, +)
        #expect(abs(plates.averageTotalInk - summed) < 0.01)
        #expect(plates.peakTotalInk >= plates.averageTotalInk)
    }

    /// The two halves have to agree: plates carried back through the profile
    /// must land where proofing the image directly lands.
    @Test func thePlatePreviewMatchesTheDirectProof() {
        for color in [Color.red, Color(red: 0.2, green: 0.5, blue: 0.8),
                      Color(white: 0.35), .white] {
            let art = flat(color)
            let viaPlates = mean(art.separated(into: cmyk).preview())
            let direct = mean(art.softProofed(cmyk))
            #expect(abs(viaPlates.red - direct.red) < 0.02)
            #expect(abs(viaPlates.green - direct.green) < 0.02)
            #expect(abs(viaPlates.blue - direct.blue) < 0.02)
        }
    }

    @Test func screeningLeavesOnlySolidInkOrBarePaper() {
        let art = flat(Color(white: 0.6))
        let screened = art.separated(into: .genericCMYK).halftoned(pitch: 4)
        for plate in screened.plates {
            guard let bytes = plate.master.premultipliedPixels() else {
                Issue.record("a screened plate lost its pixels")
                continue
            }
            for p in 0 ..< (plate.master.width * plate.master.height) {
                let value = bytes[p * 4]
                #expect(value == 0 || value == 255)
            }
        }
    }

    @Test func screeningKeepsTheTone() {
        // A dither conserves area, so a screened plate has to carry about the
        // same average ink as the continuous one it came from.
        let art = Image(width: 64, height: 64, color: Color(white: 0.55))
        let plates = art.separated(into: .genericCMYK)
        let screened = plates.dithered()
        for (before, after) in zip(plates.plates, screened.plates) {
            #expect(abs(before.averageInk - after.averageInk) < 0.06)
        }
    }

    @Test func processScreenAnglesAreTheConventionalRosette() {
        let angles = ProcessSeparation.screenAngles(count: 4)
        let degrees = angles.map { ($0 * 180 / .pi).rounded() }
        #expect(degrees == [15, 75, 0, 45])
        #expect(ProcessSeparation.screenAngles(count: 1) == [45 * .pi / 180])
    }

    @MainActor @Test func aPlateFileIsNamedAfterItsChannel() {
        #expect(OllinApp.platePath(stem: "art", index: 0, name: "Cyan") == "art-1-cyan.png")
        #expect(OllinApp.platePath(stem: "out/poster", index: 3, name: "Black")
                == "out/poster-4-black.png")
        // A profile with room in its channel names still files cleanly.
        #expect(OllinApp.platePath(stem: "art", index: 4, name: "Light Cyan")
                == "art-5-light-cyan.png")
    }

    // MARK: The baked lattice the live filter reads

    @Test func theBakedLatticeAgreesWithTheTransform() {
        guard let lut = ProofLUTCache.lut(for: cmyk) else {
            Issue.record("the proofing lattice failed to bake")
            return
        }
        #expect(lut.size == 33)
        #expect(lut.samples.count == 33 * 33 * 33)

        // Sample colors that do not sit on a lattice node, so the check is of
        // the interpolation and not of the nodes themselves. The lattice
        // stores linear light; the direct proof comes back encoded.
        let probes: [Color] = [.red, Color(red: 0.31, green: 0.62, blue: 0.17),
                               Color(white: 0.43), Color(red: 0.05, green: 0.11, blue: 0.29)]
        for color in probes {
            let expected = mean(flat(color).softProofed(cmyk))
            let sampled = lut.lookup(color.red, color.green, color.blue)
            #expect(abs(Color.linearToSrgb(Double(sampled.x)) - expected.red) < 0.02)
            #expect(abs(Color.linearToSrgb(Double(sampled.y)) - expected.green) < 0.02)
            #expect(abs(Color.linearToSrgb(Double(sampled.z)) - expected.blue) < 0.02)
        }
        // The gamut flag rides in alpha: solid red is out, mid gray is in.
        #expect(lut.lookup(1, 0, 0).w > 0.5)
        #expect(lut.lookup(0.5, 0.5, 0.5).w < 0.5)
    }

    // MARK: The live filter, rendered

    /// Four flat bands, proofed by the GPU filter, so the whole live path is
    /// under test: the baked lattice, its upload as a 3D texture, the encode
    /// on the way in and the linear values on the way out.
    private final class ProofProbeSketch: Sketch {
        var proof = SoftProof(.genericCMYK)
        var warning: Color?
        var amount = 1.0
        static let bands: [Color] = [.red, Color(red: 0.2, green: 0.55, blue: 0.8),
                                     Color(white: 0.5), .white]

        override var canvasSize: CanvasSize { .square(64) }

        override func draw() {
            noStroke()
            background(.white)
            let band = Double(height) / Double(Self.bands.count)
            for (index, color) in Self.bands.enumerated() {
                fill(color)
                drawRect(0, Double(index) * band, Double(width), band)
            }
            postProcess(.softProof(proof, warning: warning, amount: amount))
        }
    }

    /// The color at the middle of band `index`.
    @MainActor
    private func bandColors(_ sketch: ProofProbeSketch) throws -> [Color] {
        let rendered = Image(cgImage: try #require(OllinApp.image(of: sketch, frame: 0)))
        let band = rendered.height / ProofProbeSketch.bands.count
        return (0 ..< ProofProbeSketch.bands.count).map {
            rendered[rendered.width / 2, $0 * band + band / 2]
        }
    }

    @MainActor @Test(.enabled(if: Snapshot.hasMetal))
    func theLiveProofMatchesTheImageProof() throws {
        let sketch = ProofProbeSketch()
        let rendered = try bandColors(sketch)
        for (index, source) in ProofProbeSketch.bands.enumerated() {
            let expected = mean(flat(source).softProofed(cmyk))
            #expect(abs(rendered[index].red - expected.red) < 0.03)
            #expect(abs(rendered[index].green - expected.green) < 0.03)
            #expect(abs(rendered[index].blue - expected.blue) < 0.03)
        }
    }

    @MainActor @Test(.enabled(if: Snapshot.hasMetal))
    func proofingAgainstTheCanvasOwnSpaceChangesNothing() throws {
        // The control: a proof from sRGB to sRGB is a round trip through the
        // same profile, so the frame has to come back as it was drawn.
        let sketch = ProofProbeSketch()
        sketch.proof = SoftProof(.sRGB)
        let rendered = try bandColors(sketch)
        for (index, source) in ProofProbeSketch.bands.enumerated() {
            #expect(abs(rendered[index].red - source.red) < 0.02)
            #expect(abs(rendered[index].green - source.green) < 0.02)
            #expect(abs(rendered[index].blue - source.blue) < 0.02)
        }
    }

    @MainActor @Test(.enabled(if: Snapshot.hasMetal))
    func theLiveWarningFlagsWhatWillNotPrint() throws {
        // At amount 0 the colors are left alone and only the flag shows, which
        // is the mode for checking a palette without living inside the proof.
        let sketch = ProofProbeSketch()
        sketch.warning = .green
        sketch.amount = 0
        let rendered = try bandColors(sketch)
        // Saturated red cannot print, so it is replaced.
        #expect(rendered[0].green > 0.85)
        #expect(rendered[0].red < 0.15)
        // Mid gray and paper white can, so they are untouched.
        #expect(abs(rendered[2].red - 0.5) < 0.02)
        #expect(rendered[3].red > 0.98)
    }

    @Test func theLatticeIsSharedRatherThanRebuilt() {
        // The renderer keys its texture on the object, so the same printing
        // condition has to hand back the same lattice every frame.
        let first = ProofLUTCache.lut(for: cmyk)
        let second = ProofLUTCache.lut(for: SoftProof(.genericCMYK))
        #expect(first === second)
        var other = cmyk
        other.simulatePaper = true
        #expect(ProofLUTCache.lut(for: other) !== first)
    }
}
