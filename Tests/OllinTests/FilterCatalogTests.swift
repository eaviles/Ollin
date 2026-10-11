import Testing
import CoreGraphics
@testable import Ollin

/// The filters no other suite builds, held to two things a filter promises:
/// at its defaults it changes the picture, and at the setting that asks for
/// none of its effect (an amount of 0, a distance of 0, levels at 0, 1, 1)
/// it leaves the picture exactly as it was.
@Suite
@MainActor
struct FilterCatalogTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let filter: Filter
        var testDescription: String { name }
    }

    /// Each filter at its defaults.
    nonisolated static let moving: [Case] = [
        Case(name: "sepia", filter: .sepia()),
        Case(name: "duotone", filter: .duotone(dark: Color(red: 0.1, green: 0, blue: 0.3), light: .white)),
        Case(name: "soft proof", filter: .softProof(SoftProof(.genericCMYK))),
        Case(name: "sharpen", filter: .sharpen()),
        Case(name: "halftone", filter: .halftone()),
        Case(name: "dither", filter: .dither()),
        Case(name: "two-color dither", filter: .dither(dark: .black, light: .white)),
        Case(name: "pixelate", filter: .pixelate()),
        Case(name: "line screen", filter: .lineScreen()),
        Case(name: "solarize", filter: .solarize()),
        Case(name: "temperature", filter: .temperature(amount: 0.5)),
        Case(name: "levels", filter: .levels(blackPoint: 0.2, whitePoint: 0.8, gamma: 1.4)),
        Case(name: "colorama", filter: .colorama()),
        Case(name: "luma key", filter: .lumaKey()),
        Case(name: "motion blur", filter: .motionBlur()),
        Case(name: "radial blur", filter: .radialBlur()),
        Case(name: "bilateral", filter: .bilateral()),
        Case(name: "crosshatch", filter: .crosshatch()),
        Case(name: "toon", filter: .toon()),
        Case(name: "median", filter: .median()),
        Case(name: "contour", filter: .contour()),
        Case(name: "glitch", filter: .glitch()),
        Case(name: "crt", filter: .crt()),
        Case(name: "bulge", filter: .bulge()),
        Case(name: "wave", filter: .wave()),
        Case(name: "mirror", filter: .mirror()),
        Case(name: "polar", filter: .polar()),
        Case(name: "tile", filter: .tile()),
        Case(name: "perturb", filter: .perturb()),
    ]

    /// Each filter at the setting that asks for none of its effect.
    nonisolated static let still: [Case] = [
        Case(name: "sepia", filter: .sepia(amount: 0)),
        Case(name: "duotone", filter: .duotone(dark: Color(red: 0.1, green: 0, blue: 0.3), light: .white, amount: 0)),
        Case(name: "soft proof", filter: .softProof(SoftProof(.genericCMYK), amount: 0)),
        Case(name: "sharpen", filter: .sharpen(amount: 0)),
        Case(name: "temperature", filter: .temperature(amount: 0, tint: 0)),
        Case(name: "levels", filter: .levels(blackPoint: 0, whitePoint: 1, gamma: 1)),
        Case(name: "motion blur", filter: .motionBlur(distance: 0)),
        Case(name: "radial blur", filter: .radialBlur(amount: 0)),
        Case(name: "contour", filter: .contour(amount: 0)),
        Case(name: "glitch", filter: .glitch(amount: 0)),
        Case(name: "bulge", filter: .bulge(amount: 0)),
        Case(name: "wave", filter: .wave(amplitude: 0)),
        Case(name: "polar", filter: .polar(amount: 0)),
        Case(name: "perturb", filter: .perturb(amount: 0)),
    ]

    @Test(arguments: moving)
    func atItsDefaultsAFilterChangesThePicture(_ item: Case) throws {
        let plain = pixels(of: try OllinApp.image(of: FilteredPicture(nil), frame: 1))
        let filtered = pixels(of: try OllinApp.image(of: FilteredPicture(item.filter), frame: 1))
        let moved = zip(plain, filtered).filter { abs(Int($0) - Int($1)) > 2 }.count
        #expect(moved > plain.count / 100, "\(item.name) moved \(moved) of \(plain.count) bytes")
    }

    @Test(arguments: still)
    func atNoneOfItsEffectAFilterLeavesThePicture(_ item: Case) throws {
        let plain = pixels(of: try OllinApp.image(of: FilteredPicture(nil), frame: 1))
        let filtered = pixels(of: try OllinApp.image(of: FilteredPicture(item.filter), frame: 1))
        let worst = zip(plain, filtered).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst == 0, "\(item.name) moved a byte by \(worst)")
    }
}

/// A picture with edges, flats, a ramp, and every hue, drawn into a layer and
/// drawn back through one filter.
@MainActor
private final class FilteredPicture: Sketch {
    var filter: Filter?

    convenience init(_ filter: Filter?) {
        self.init()
        self.filter = filter
    }

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            background(Color(white: 0.15))
            noStroke()
            for i in 0 ..< 12 {
                fill(Color(hue: Double(i) / 12, saturation: 0.8, brightness: 0.4 + 0.05 * Double(i)))
                drawRect(Double(i) * 8, 0, 8, 30)
            }
            fill(.white)
            drawCircle(30, 60, 18)
            fill(Color(red: 0.9, green: 0.3, blue: 0.2))
            drawStar(70, 62, 22, 9, points: 5)
            stroke(.white)
            strokeWeight(1.5)
            for i in 0 ..< 6 { drawLine(0, 82 + Double(i) * 2.5, 96, 90 + Double(i) * 2.5) }
        }
        drawImage(filter.map { layer.filtered($0).image } ?? layer.image, 0, 0)
    }
}
