import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// The chrome filter against its own rules: amount 0 changes no byte; with a
/// flat horizon the sky's top, the wire, the break, the core band, and the
/// floor's bottom sit on the stated rows in the stated colors; the warp bends
/// the break by the formula at every column; the phase moves the bend; the
/// shape keeps its edge; and the layer's own color tints the chrome.
@Suite
@MainActor
struct ChromeFilterTests {

    static let side = 240

    /// A layer of `paint` (white by default) filling the canvas or a disc,
    /// over black, filtered or not.
    final class ChromeProbe: Sketch {
        var filter: Filter?
        var paint: Color = .white
        var disc = false
        static func make(_ filter: Filter?, paint: Color = .white, disc: Bool = false) -> ChromeProbe {
            let s = ChromeProbe(); s.filter = filter; s.paint = paint; s.disc = disc; return s
        }
        override var canvasSize: CanvasSize { .square(ChromeFilterTests.side) }
        override func draw() {
            background(.black)
            let layer = makeRenderTarget()
            withTarget(layer) {
                if disc {
                    noStroke(); fill(paint); drawCircle(120, 120, 80)
                } else {
                    background(paint)
                }
            }
            drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
        }
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        guard pa.count == pb.count else { return 255 }
        return zip(pa, pb).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    private func rgb(_ px: Pixels, _ x: Int, _ y: Int) -> SIMD3<Int> {
        SIMD3(px.channel(0, x, y), px.channel(1, x, y), px.channel(2, x, y))
    }

    private func bytes(_ c: Color) -> SIMD3<Int> {
        SIMD3(Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
    }

    private func within(_ a: SIMD3<Int>, _ b: SIMD3<Int>, _ tolerance: Int) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.z - b.z) <= tolerance
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func amountZeroChangesNoByte() throws {
        let plain = try OllinApp.image(of: ChromeProbe.make(nil, disc: true), frame: 1)
        let held = try OllinApp.image(of: ChromeProbe.make(.chrome(amount: 0), disc: true), frame: 1)
        #expect(maxDifference(plain, held) == 0)
        let chromed = try OllinApp.image(of: ChromeProbe.make(.chrome(), disc: true), frame: 1)
        #expect(maxDifference(plain, chromed) > 100)
    }

    /// With no warp the horizon is a straight row, and every band sits where
    /// the parameters say, in the color the parameters say.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBandsSitOnTheStatedRows() throws {
        let sky = Ramp([Color(hex: 0x0A1F5C), Color(hex: 0xEAF7FF)])
        let floor = Ramp([Color(hex: 0x3A1A06), Color(hex: 0xFFF0B8)])
        let core = Color(hex: 0x24110A), wire = Color(hex: 0xFFFFFF)
        let filter = Filter.chrome(horizon: 0.5, warp: 0, waves: 1, sky: sky, floor: floor,
                                   core: core, coreWidth: 20, breakWidth: 6, wire: wire)
        let px = Pixels(try OllinApp.image(of: ChromeProbe.make(filter), frame: 1))
        let x = 97
        // The horizon at row 120: the break fills rows 117 to 122 (|d| < 3), the
        // wire the six rows above it, the sky's first stop at the top, the
        // floor's last stop at the bottom, and the core just under the break.
        // Each band's outermost row is a blend over the pixel of anti-aliasing,
        // so the rows read are the ones fully inside.
        for y in 118...121 {
            let v = rgb(px, x, y)
            #expect(v.x < 12 && v.y < 12 && v.z < 12, "row \(y) is not the black break: \(v)")
        }
        for y in 112...115 {
            let v = rgb(px, x, y)
            #expect(v.x > 240 && v.y > 240 && v.z > 240, "row \(y) is not the wire: \(v)")
        }
        #expect(within(rgb(px, x, 0), bytes(sky.stops[0].color), 6), "the top row is not the sky's first stop")
        #expect(within(rgb(px, x, 239), bytes(floor.stops[1].color), 6), "the bottom row is not the floor's last stop")
        #expect(within(rgb(px, x, 124), bytes(core), 10), "row 124 is not the core band: \(rgb(px, x, 124))")
        // Halfway down the sky the ramp is halfway between its stops, in its
        // own mixing space.
        let mid = sky.color(at: 60.5 / 120)
        #expect(within(rgb(px, x, 60), bytes(mid), 8), "row 60 is not the sky ramp's midpoint")
        // The floor fades from the core: 60 rows under the break it is well past the band.
        let deep = floor.color(at: (182.5 - 120) / 120)   // d - 3 = 59.5, past the 20-row band
        #expect(within(rgb(px, x, 182), bytes(deep), 8), "row 182 is not the floor ramp")
    }

    /// The break's row at a column is the horizon plus the warp times the
    /// bend the fragment computes: a sine of x and a cosine at a second
    /// frequency, drifting with the phase.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theWarpBendsTheHorizonByItsFormula() throws {
        // The break is the run of black rows in a column: wide enough here that a
        // sloped horizon's anti-aliasing leaves black inside it, read as the mean
        // of the rows at black.
        func breakRow(_ px: Pixels, _ x: Int) -> Double {
            var sum = 0.0, n = 0.0
            for y in 60..<180 {
                let v = rgb(px, x, y)
                if v.x + v.y + v.z <= 6 { sum += Double(y) + 0.5; n += 1 }
            }
            return n > 0 ? sum / n : -1
        }
        func predicted(_ x: Int, phase: Double, warp: Double, waves: Double) -> Double {
            let k = 2 * Double.pi * waves / Double(Self.side)
            let px = Double(x) + 0.5
            let bend = sin(px * k + phase) + 0.55 * cos(px * k * 2.37 - 0.61 * phase)
            return 0.5 * Double(Self.side) + warp * bend
        }
        for (phase, warp, waves) in [(0.0, 12.0, 1.0), (1.7, 9.0, 2.0)] {
            let filter = Filter.chrome(horizon: 0.5, warp: warp, waves: waves, breakWidth: 8, phase: phase)
            let px = Pixels(try OllinApp.image(of: ChromeProbe.make(filter), frame: 1))
            for x in stride(from: 7, to: Self.side, by: 29) {
                let row = breakRow(px, x)
                let want = predicted(x, phase: phase, warp: warp, waves: waves)
                #expect(abs(row - want) <= 1.0, "column \(x) at phase \(phase): break at \(row), formula says \(want)")
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theShapeKeepsItsEdgeAndTheLayerTintsIt() throws {
        let white = Pixels(try OllinApp.image(of: ChromeProbe.make(.chrome(warp: 0), disc: true), frame: 1))
        // Outside the disc the background shows through untouched.
        let corner = rgb(white, 10, 10)
        #expect(corner.x == 0 && corner.y == 0 && corner.z == 0)
        let edge = rgb(white, 120, 120 - 90)
        #expect(edge.x == 0 && edge.y == 0 && edge.z == 0, "ten pixels past the rim is not background: \(edge)")
        // Inside, a red layer is the chrome multiplied by red: the floor's pale
        // yellow bottom keeps its red and loses its green and blue.
        let red = Pixels(try OllinApp.image(of: ChromeProbe.make(.chrome(warp: 0), paint: Color(red: 1, green: 0, blue: 0), disc: true), frame: 1))
        let w = rgb(white, 120, 190), r = rgb(red, 120, 190)
        #expect(w.y > 120 && w.z > 40, "the white disc's floor has no green or blue to lose: \(w)")
        #expect(abs(r.x - w.x) <= 2 && r.y == 0 && r.z == 0, "the red disc is not the chrome times red: \(r) against \(w)")
    }
}
