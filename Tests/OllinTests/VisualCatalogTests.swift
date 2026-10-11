import Testing
import CoreGraphics
@testable import Ollin

/// The visual chain's sources and operators: each source draws its own
/// picture, each operator
/// changes the chain it is applied to, each one set to do nothing leaves the
/// chain exactly as it was, and a modulated operator at amount 0 is exactly
/// its plain twin (the driver's share is all `amount` adds).
@Suite
@MainActor
struct VisualCatalogTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable () -> Visual
        var testDescription: String { name }
    }

    struct Twin: Sendable, CustomTestStringConvertible {
        let name: String
        let modulated: @Sendable () -> Visual
        let plain: @Sendable () -> Visual
        var testDescription: String { name }
    }

    nonisolated static func base() -> Visual {
        .oscillator(frequency: 6, speed: 0.3, colorShift: 0.4).rotated(0.4)
    }

    nonisolated static func driver() -> Visual { .noise(scale: 4) }

    nonisolated static let sources: [Case] = [
        Case(name: "voronoi", make: { .voronoi() }),
        Case(name: "shape", make: { .shape() }),
        Case(name: "gradient", make: { .gradient() }),
        Case(name: "noise", make: { .noise() }),
    ]

    nonisolated static let operators: [Case] = [
        Case(name: "scaled", make: { base().scaled(1.5) }),
        Case(name: "pixelated", make: { base().pixelated(8) }),
        // The two-axis operators one axis at a time, so an axis dropped on
        // the way to the shader shows.
        Case(name: "repeated across", make: { base().repeated(x: 2, y: 1) }),
        Case(name: "repeated down", make: { base().repeated(x: 1, y: 3) }),
        Case(name: "scrolled across", make: { base().scrolled(x: 0.2, y: 0) }),
        Case(name: "scrolled down", make: { base().scrolled(x: 0, y: 0.15) }),
        Case(name: "pixelated across", make: { base().pixelated(x: 6, y: 96) }),
        Case(name: "pixelated down", make: { base().pixelated(x: 96, y: 6) }),
        Case(name: "contrast", make: { base().contrast(1.8) }),
        Case(name: "posterized", make: { base().posterized(levels: 3) }),
        Case(name: "thresholded", make: { base().thresholded(0.5) }),
        Case(name: "luma", make: { base().luma(threshold: 0.5) }),
        Case(name: "hue shifted", make: { base().hueShifted(0.3) }),
        Case(name: "color cycled", make: { base().colorCycled(0.5) }),
        Case(name: "channel", make: { base().channel(.red) }),
        Case(name: "mixed", make: { base().mixed(with: driver(), amount: 0.5) }),
        Case(name: "differenced", make: { base().differenced(with: driver()) }),
        Case(name: "rotated by", make: { base().rotated(by: driver(), amount: 0.5) }),
        Case(name: "scaled by", make: { base().scaled(by: driver(), amount: 0.5) }),
        Case(name: "pixelated by", make: { base().pixelated(by: driver(), amount: 0.5) }),
        Case(name: "kaleidoscope by", make: { base().kaleidoscope(by: driver(), segments: 6, amount: 0.5) }),
    ]

    nonisolated static let neutral: [Case] = [
        Case(name: "scaled", make: { base().scaled(1) }),
        Case(name: "repeated", make: { base().repeated(x: 1, y: 1) }),
        Case(name: "scrolled", make: { base().scrolled(x: 0, y: 0) }),
        Case(name: "contrast", make: { base().contrast(1) }),
        Case(name: "hue shifted", make: { base().hueShifted(0) }),
        Case(name: "color cycled", make: { base().colorCycled(0) }),
        Case(name: "brightness", make: { base().brightness(0) }),
        Case(name: "saturation", make: { base().saturation(1) }),
        Case(name: "inverted", make: { base().inverted(0) }),
        Case(name: "mixed", make: { base().mixed(with: driver(), amount: 0) }),
        Case(name: "blended", make: { base().blended(with: driver(), amount: 0) }),
        Case(name: "displaced", make: { base().displaced(by: driver(), amount: 0) }),
        Case(name: "rotated by", make: { base().rotated(by: driver(), amount: 0) }),
        Case(name: "scaled by", make: { base().scaled(by: driver(), amount: 0) }),
    ]

    nonisolated static let twins: [Twin] = [
        Twin(name: "pixelated", modulated: { base().pixelated(by: driver(), amount: 0, offset: 8) },
             plain: { base().pixelated(8) }),
        Twin(name: "kaleidoscope", modulated: { base().kaleidoscope(by: driver(), segments: 6, amount: 0) },
             plain: { base().kaleidoscope(segments: 6) }),
        Twin(name: "rotated", modulated: { base().rotated(by: driver(), amount: 0, offset: 0.5) },
             plain: { base().rotated(0.5) }),
        Twin(name: "scaled", modulated: { base().scaled(by: driver(), amount: 0, offset: 1.5) },
             plain: { base().scaled(1.5) }),
    ]

    private func render(_ visual: Visual) throws -> [UInt8] {
        pixels(of: try OllinApp.image(of: VisualProbe(visual), frame: 1))
    }

    private func moved(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).filter { abs(Int($0) - Int($1)) > 2 }.count
    }

    @Test(arguments: sources)
    func aSourceDrawsItsOwnPicture(_ item: Case) throws {
        let picture = try render(item.make())
        let other = try render(Self.base())
        #expect(moved(picture, other) > picture.count / 4, "\(item.name) drew what the oscillator draws")
        #expect(Set(picture).count > 8, "\(item.name) drew a flat picture")
    }

    @Test func aSolidIsThatColorEverywhere() throws {
        let picture = Pixels(try OllinApp.image(of: VisualProbe(.solid(Color(red: 1, green: 0, blue: 0))), frame: 1))
        for (x, y) in [(0, 0), (48, 48), (95, 95), (10, 80)] {
            #expect(picture.channel(0, x, y) == 255 && picture.channel(1, x, y) == 0 && picture.channel(2, x, y) == 0)
        }
    }

    @Test func aLayerSourceDrawsTheLayer() throws {
        let probe = VisualProbe(nil)
        probe.drawsLayer = true
        let viaVisual = Pixels(try OllinApp.image(of: probe, frame: 1))
        #expect(viaVisual.channel(0, 30, 30) > 200, "the layer's disc reads \(viaVisual.channel(0, 30, 30))")
        #expect(viaVisual.channel(0, 80, 80) < 30, "outside the disc reads \(viaVisual.channel(0, 80, 80))")
    }

    @Test(arguments: operators)
    func anOperatorChangesTheChain(_ item: Case) throws {
        let plain = try render(Self.base())
        let changed = try render(item.make())
        #expect(moved(plain, changed) > plain.count / 100, "\(item.name) moved \(moved(plain, changed)) bytes")
    }

    @Test(arguments: neutral)
    func anOperatorSetToNothingLeavesTheChain(_ item: Case) throws {
        let plain = try render(Self.base())
        let same = try render(item.make())
        let worst = zip(plain, same).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst == 0, "\(item.name) moved a byte by \(worst)")
    }

    @Test(arguments: twins)
    func aModulationAtZeroIsItsPlainTwin(_ twin: Twin) throws {
        #expect(try render(twin.modulated()) == render(twin.plain()))
    }
}

@MainActor
private final class VisualProbe: Sketch {
    var visual: Visual?
    var drawsLayer = false

    convenience init(_ visual: Visual?) {
        self.init()
        self.visual = visual
    }

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(.black)
        if drawsLayer {
            let layer = makeRenderTarget()
            withTarget(layer) {
                noStroke()
                fill(Color(red: 1, green: 0, blue: 0))
                drawCircle(30, 30, 16)
            }
            drawVisual(.layer(layer))
        } else if let visual {
            drawVisual(visual)
        }
    }
}
