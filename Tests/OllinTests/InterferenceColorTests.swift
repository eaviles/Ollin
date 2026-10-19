import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// The color a thin film shows, on the CPU: `Spectrum.interference` is the
/// two-beam reflectance of a symmetric film, never past the peak a film of
/// that index can reach and nothing at no thickness; `Color.interference` is
/// that curve at full brightness, walking a draining film's color order; and
/// the GPU `.thinFilm` filter, which evaluates the same optics over its
/// wavelength taps, shows the same color for the same thickness.
@Suite
struct InterferenceColorTests {

    @Test func noThicknessReflectsNothing() {
        let flat = Spectrum.interference(thickness: 0)
        #expect(flat.samples.allSatisfy { $0 == 0 })
        let c = Color.interference(thickness: 0)
        #expect(c.red == 0 && c.green == 0 && c.blue == 0)
        // No index step is no film: air over air reflects nothing at any thickness.
        let air = Color.interference(thickness: 400, ior: 1)
        #expect(air.red == 0 && air.green == 0 && air.blue == 0)
    }

    @Test func theCurveStaysUnderThePeakAndReachesIt() {
        let peak = Spectrum.interferencePeak(ior: 1.35)
        #expect(peak > 0.08 && peak < 0.09)     // 4r² / (1 + r²)² for r = 0.149
        var highest = 0.0
        for thickness in stride(from: 0.0, through: 1500, by: 7) {
            let s = Spectrum.interference(thickness: thickness, ior: 1.35)
            for v in s.samples {
                #expect(v >= 0 && v <= peak + 1e-12)
                highest = max(highest, v)
            }
        }
        #expect(highest > 0.999 * peak, "full constructive interference never reached: \(highest) of \(peak)")
    }

    /// The order a draining soap film shows: straw, then magenta, then blue,
    /// then green, then yellow. Each is pinned by its dominant channel.
    @Test func theColorWalksAFilmsOrder() {
        func dominant(_ nm: Double) -> Int {
            let c = Color.interference(thickness: nm)
            let v = [c.red, c.green, c.blue]
            return v.indices.max { v[$0] < v[$1] }!
        }
        #expect(dominant(150) == 0, "150 nm is straw")
        #expect(dominant(250) == 2, "250 nm is blue")
        #expect(dominant(300) == 1, "300 nm is green")
        #expect(dominant(350) == 0, "350 nm is yellow to red")
        // The near-clear film is pale: bright and barely saturated.
        let pale = Color.interference(thickness: 100)
        #expect(pale.brightness > 0.8)
        #expect(pale.saturation < 0.2, "100 nm should be nearly white: \(pale)")
        // Full brightness: the brightest channel over the series reaches 1.
        let brightest = stride(from: 100.0, through: 700, by: 10)
            .map { Color.interference(thickness: $0) }
            .map { max($0.red, max($0.green, $0.blue)) }
            .max() ?? 0
        #expect(brightest > 0.98)
    }

    @Test func aRampOfFilmColorsPaintsAStroke() {
        // The use the color is for: a stroke that walks the series along its
        // length through `.alongPath`, which only needs the ramp to build.
        let ramp = Ramp((0...12).map { Color.interference(thickness: 200 + Double($0) * 30) })
        #expect(ramp.stops.count == 13)
        let a = ramp.color(at: 0), b = ramp.color(at: 1)
        #expect(abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue) > 0.3)
    }
}

/// The GPU twin: a white layer under `.thinFilm` with no swirl shows, pixel for
/// pixel, the color `Color.interference` computes for that thickness.
@Suite
@MainActor
struct InterferenceColorRenderProbes {

    final class FilmPatch: Sketch {
        var filter: Filter?
        static func make(_ filter: Filter?) -> FilmPatch { let s = FilmPatch(); s.filter = filter; return s }
        override var canvasSize: CanvasSize { .square(48) }
        override func draw() {
            background(.black)
            let layer = makeRenderTarget()
            withTarget(layer) { background(.white) }
            drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFilterShowsTheCPUsColor() throws {
        var worst = 0.0, worstThick = 0.0
        var report: [String] = []
        for thickness in [150.0, 250, 300, 420, 560, 700, 900] {
            let filter = Filter.thinFilm(amount: 1, thickness: thickness, variation: 0, ior: 1.35,
                                         quality: .detail)
            let image = try OllinApp.image(of: FilmPatch.make(filter), frame: 1)
            let px = Pixels(image)
            let cpu = Color.interference(thickness: thickness, ior: 1.35)
            let expected = [cpu.red, cpu.green, cpu.blue].map { min(max($0, 0), 1) * 255 }
            // The middle of the patch, averaged over a few pixels to take the
            // dither out.
            var sum = SIMD3<Double>()
            var n = 0.0
            for y in 20..<28 {
                for x in 20..<28 {
                    sum += SIMD3(Double(px.channel(0, x, y)), Double(px.channel(1, x, y)),
                                 Double(px.channel(2, x, y)))
                    n += 1
                }
            }
            let read = sum / n
            for i in 0..<3 {
                let off = abs(read[i] - expected[i])
                // Through the strong colors the two agree within a level. Past
                // about 600 nm the bands crowd together and the filter's 31 taps
                // sample the curve more coarsely than the 81 behind the CPU color,
                // which is worth a few levels there and no more.
                if thickness <= 600 { worst = max(worst, off) } else { worstThick = max(worstThick, off) }
            }
            report.append("\(Int(thickness)) nm: gpu \(read) cpu \(expected.map { Int($0.rounded()) })")
        }
        print("interference color, GPU against CPU: worst \(String(format: "%.2f", worst)) levels through 600 nm, "
              + "\(String(format: "%.2f", worstThick)) past it\n" + report.joined(separator: "\n"))
        #expect(worst <= 1.0, "the filter and the CPU color disagree by \(worst) levels in the strong colors")
        #expect(worstThick <= 4.0, "the filter and the CPU color disagree by \(worstThick) levels in the thick films")
    }
}
