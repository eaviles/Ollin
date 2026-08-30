@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import COllinShaders

/// CPU checks on the thin-film finish: the clamps, the packing, and the one rule that
/// is not obvious, that a film of no thickness ships as no film at all.
@Suite
struct ThinFilmMaterialTests {

    @Test func clampsAndPacks() {
        let m = Material(shading: .physicallyBased, thinFilm: 4, thinFilmThickness: -20,
                         thinFilmIOR: 9)
        #expect(m.thinFilm == 1)               // 0...1
        #expect(m.thinFilmThickness == 0)      // >= 0
        #expect(m.thinFilmIOR == 3)            // 1...3
        let g = Material(shading: .physicallyBased, thinFilm: 0.5,
                         thinFilmThickness: 480, thinFilmIOR: 1.45).gpuMaterial()
        #expect(abs(g.thinFilm - 0.5) < 1e-6)
        #expect(abs(g.thinFilmThickness - 480) < 1e-3)
        #expect(abs(g.thinFilmIor - 1.45) < 1e-6)
    }

    @Test func aFilmOfNoThicknessShipsAsNoFilm() {
        // Nothing interferes across no distance, so the strength is zeroed on the way
        // to the GPU rather than asking the model for a color it has no basis for.
        // That zero is also the shader's gate, which is why it matters here.
        let g = Material(shading: .physicallyBased, thinFilm: 1, thinFilmThickness: 0).gpuMaterial()
        #expect(g.thinFilm == 0)
        #expect(Material().gpuMaterial().thinFilm == 0)     // and the default is inert
    }

    @Test func theCuratedFilmsAreAllPhysicallyBased() {
        // The film rides the physically-based lobe alone, so every ready-made one must
        // carry that shading model and a thickness to interfere across.
        for m in [Material.anodized, .oilOnWater, .nacre, .soapFilm()] {
            #expect(m.shading == .physicallyBased)
            #expect(m.thinFilm > 0 && m.thinFilmThickness > 0)
        }
        #expect(Material.anodized.metallic == 1)            // a film over a conductor
        #expect(Material.soapFilm().transmission == 1)      // a wall you see through
        #expect(Material.soapFilm(thickness: 700).thinFilmThickness == 700)
    }
}

/// An independent reading of the published thin-film model, written here in Swift so
/// the shader is checked against something other than itself. Interference between the
/// two faces of the film, summed over the trips light can make between them, with the
/// eye's response evaluated in the frequency domain (the technique credited in
/// ATTRIBUTION.md). Only the case the probes use is covered: a gray base, the film
/// denser than the air over it, and a thickness far above the vanishing guard.
private enum FilmReference {

    static func reflectanceStraightOn(baseF0: Double, filmIor: Double,
                                      thicknessNm: Double) -> SIMD3<Double> {
        reflectance(cosTheta: 1, baseF0: baseF0, filmIor: filmIor, thicknessNm: thicknessNm)
    }

    static func reflectance(cosTheta: Double, baseF0: Double, filmIor: Double,
                            thicknessNm: Double) -> SIMD3<Double> {
        let eta = filmIor
        let sinT2sq = (1 / (eta * eta)) * (1 - cosTheta * cosTheta)
        let cosT2 = (1 - sinT2sq).squareRoot()

        let r12 = schlick(r0(eta, 1), cosTheta)
        let t121 = 1 - r12
        let phi21 = Double.pi                       // the film is the denser side here

        let baseIor = (1 + baseF0.squareRoot()) / (1 - baseF0.squareRoot())
        let r23 = schlick(r0(baseIor, eta), cosT2)
        let phi23 = baseIor < eta ? Double.pi : 0

        let opd = 2 * eta * thicknessNm * cosT2
        let phi = phi21 + phi23

        let r123 = min(max(r12 * r23, 1e-5), 0.9999)
        let sqrtR123 = r123.squareRoot()
        let rs = t121 * t121 * r23 / (1 - r123)

        var total = SIMD3<Double>(repeating: r12 + rs)
        var cm = SIMD3<Double>(repeating: rs - t121)
        for m in 1...2 {
            cm *= sqrtR123
            let s = sensitivity(Double(m) * opd, SIMD3<Double>(repeating: Double(m) * phi))
            total += cm * (2 * s)
        }
        return SIMD3(max(total.x, 0), max(total.y, 0), max(total.z, 0))
    }

    private static func r0(_ inner: Double, _ outer: Double) -> Double {
        let r = (inner - outer) / (inner + outer)
        return r * r
    }

    private static func schlick(_ f0: Double, _ cosTheta: Double) -> Double {
        let m = min(max(1 - cosTheta, 0), 1)
        let m2 = m * m
        return f0 + (1 - f0) * (m2 * m2 * m)
    }

    private static func sensitivity(_ opd: Double, _ shift: SIMD3<Double>) -> SIMD3<Double> {
        let phase = 2 * Double.pi * opd * 1.0e-9
        let amp = SIMD3<Double>(5.4856e-13, 4.4201e-13, 5.2481e-13)
        let center = SIMD3<Double>(1.6810e+06, 1.7953e+06, 2.2084e+06)
        let width = SIMD3<Double>(4.3278e+09, 9.3046e+09, 6.6121e+09)
        var xyz = SIMD3<Double>()
        for i in 0..<3 {
            xyz[i] = amp[i] * (2 * Double.pi * width[i]).squareRoot()
                   * cos(center[i] * phase + shift[i]) * exp(-phase * phase * width[i])
        }
        xyz.x += 9.7470e-14 * (2 * Double.pi * 4.5282e+09).squareRoot()
               * cos(2.2399e+06 * phase + shift.x) * exp(-4.5282e+09 * phase * phase)
        xyz /= 1.0685e-7
        let r = 3.2404542 * xyz.x - 1.5371385 * xyz.y - 0.4985314 * xyz.z
        let g = -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z
        let b = 0.0556434 * xyz.x - 0.2040259 * xyz.y + 1.0572252 * xyz.z
        return SIMD3(r, g, b)
    }
}

/// Rendered probes for the thin film: that it is inert until asked for, that it colors
/// what the surface reflects, that the color walks with the thickness and with the
/// angle, that the surface under it is part of the answer, and that the color the
/// shader picks is the color the published model asks for.
@Suite
@MainActor
struct ThinFilmRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The mean color over a disc of the canvas, as three 0…255 channels.
    private func mean(_ image: CGImage, radius: Double, at center: (Double, Double) = (0.5, 0.5))
        -> SIMD3<Double> {
        let d = pixels(of: image)
        let w = image.width, h = image.height
        let cx = center.0 * Double(w), cy = center.1 * Double(h)
        let r = radius * Double(w)
        var sum = SIMD3<Double>(), count = 0.0
        for py in 0..<h {
            for px in 0..<w {
                let dx = Double(px) - cx, dy = Double(py) - cy
                guard dx * dx + dy * dy <= r * r else { continue }
                let i = (py * w + px) * 4
                sum += SIMD3(Double(d[i]), Double(d[i + 1]), Double(d[i + 2]))
                count += 1
            }
        }
        return sum / max(count, 1)
    }

    /// Which channel is brightest and which is dimmest. Ordering survives any tone
    /// curve that treats the channels alike, which is what lets a rendered pixel be
    /// compared against a reflectance.
    private func order(_ c: SIMD3<Double>) -> (Int, Int) {
        var high = 0, low = 0
        for i in 1...2 {
            if c[i] > c[high] { high = i }
            if c[i] < c[low] { low = i }
        }
        return (high, low)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutAFilmTheSurfaceIsUntouched() throws {
        // Two ways of asking for nothing: no film, and a film of no thickness. Both
        // must land on the exact pixels the material had before the finish existed.
        let plain = try #require(OllinApp.image(of: FilmProbe.make(.plainMetal), frame: 1))
        let none = try #require(OllinApp.image(of: FilmProbe.make(.filmStrengthZero), frame: 1))
        let flat = try #require(OllinApp.image(of: FilmProbe.make(.filmThicknessZero), frame: 1))
        #expect(pixels(of: none) == pixels(of: plain))
        #expect(pixels(of: flat) == pixels(of: plain))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFilmColorsWhatTheSurfaceReflects() throws {
        // The same gray metal under a white light: with a film it must come back
        // colored, and colored means the channels separate, not that it dimmed.
        let plain = try #require(OllinApp.image(of: FilmProbe.make(.plainMetal), frame: 1))
        let filmed = try #require(OllinApp.image(of: FilmProbe.make(.film(550)), frame: 1))
        let a = mean(plain, radius: 0.12), b = mean(filmed, radius: 0.12)
        let spreadPlain = a.max() - a.min(), spreadFilmed = b.max() - b.min()
        #expect(spreadPlain < 6, "the gray reference is not gray: \(a)")
        #expect(spreadFilmed > 18,
                "the film left the surface gray: \(b), spread \(spreadFilmed)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func thicknessWalksTheColor() throws {
        // Thickness is the whole instrument: three films over one surface must come
        // back as three different colors, each pair apart by more than any noise. The
        // three are picked where the model's own series is far apart (it comes back
        // around, so two thicknesses can honestly share a color).
        var seen: [SIMD3<Double>] = []
        for t in [280.0, 360, 600] {
            let image = try #require(OllinApp.image(of: FilmProbe.make(.film(t)), frame: 1))
            seen.append(mean(image, radius: 0.12))
        }
        for i in 0..<seen.count {
            for j in (i + 1)..<seen.count {
                let d = (seen[i] - seen[j])
                let worst = max(abs(d.x), max(abs(d.y), abs(d.z)))
                #expect(worst > 10, "thicknesses \(i) and \(j) render alike: \(seen[i]) \(seen[j])")
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theColorWalksAcrossOneBody() throws {
        // A film of one thickness still makes many colors on a curved body, because
        // the light's path through it lengthens as the surface turns away. Straight-on
        // and three-quarters-out must not read as the same color.
        let image = try #require(OllinApp.image(of: FilmProbe.make(.filmOnASphere(480)),
                                                frame: 1))
        let middle = mean(image, radius: 0.05)
        let outer = mean(image, radius: 0.035, at: (0.5, 0.5 - 0.155))
        let d = middle - outer
        let worst = max(abs(d.x), max(abs(d.y), abs(d.z)))
        #expect(worst > 10, "the film does not turn with the surface: \(middle) vs \(outer)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSurfaceUnderTheFilmIsPartOfTheColor() throws {
        // The second face of the film is where it meets the surface under it, so a
        // film over a conductor and the same film over a dielectric must not agree.
        let onMetal = try #require(OllinApp.image(of: FilmProbe.make(.film(480)), frame: 1))
        let onGlass = try #require(OllinApp.image(of: FilmProbe.make(.filmOnDielectric(480)),
                                                 frame: 1))
        #expect(order(mean(onMetal, radius: 0.12)) != order(mean(onGlass, radius: 0.12))
                || pixels(of: onMetal) != pixels(of: onGlass))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theShaderPicksTheColorTheModelAsks() throws {
        // The fidelity check. Straight on, with the light along the eye, what the plate
        // sends back is the film's reflectance times a factor that treats the three
        // channels alike. So every difference between two channels comes straight from
        // the model, and an independent reading of it (`FilmReference`) must agree on
        // the direction of each one, at every thickness across the useful range.
        //
        // Only differences the model itself calls real are checked: past about 700 nm
        // the bands crowd together and the film genuinely washes toward neutral, where
        // a channel order is noise rather than a claim.
        let baseF0 = Color.srgbToLinear(FilmProbe.metalWhite)
        var checked = 0
        for thickness in stride(from: 220.0, through: 820, by: 60) {
            let image = try #require(OllinApp.image(of: FilmProbe.make(.film(thickness)),
                                                   frame: 1))
            let rendered = mean(image, radius: 0.06)
            #expect(rendered.max() < 250,
                    "thickness \(thickness) clipped, so a channel order says nothing: \(rendered)")
            #expect(rendered.max() > 8, "thickness \(thickness) rendered black: \(rendered)")
            let expected = FilmReference.reflectanceStraightOn(baseF0: baseF0, filmIor: 1.3,
                                                               thicknessNm: thickness)
            let scale = (expected.x + expected.y + expected.z) / 3
            for (i, j) in [(0, 1), (1, 2), (0, 2)] {
                let modelGap = (expected[i] - expected[j]) / max(scale, 1e-6)
                guard abs(modelGap) > 0.05 else { continue }
                let renderedGap = rendered[i] - rendered[j]
                #expect(modelGap * renderedGap > 0,
                        "at \(thickness) nm channels \(i)/\(j) disagree: rendered \(rendered), model \(expected)")
                checked += 1
            }
        }
        #expect(checked > 15, "too few real color differences to check (\(checked))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFilmSurvivesIntoAPathTracedFrame() throws {
        // An offline frame shades through its own path, so the film has to be there
        // too, or an export would quietly drop the color the window shows.
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 24, denoise: false)
        defer { OllinApp.pathTracedExport = nil }
        let plain = try #require(OllinApp.image(of: FilmProbe.make(.plainMetal), frame: 1))
        let filmed = try #require(OllinApp.image(of: FilmProbe.make(.film(550)), frame: 1))
        let a = mean(plain, radius: 0.12), b = mean(filmed, radius: 0.12)
        #expect(a.max() - a.min() < 8, "the traced reference is not gray: \(a)")
        #expect(b.max() - b.min() > 12, "the traced film left the surface gray: \(b)")
    }
}

/// The probe scene: a flat plate square to the camera, lit by a single white light
/// along the eye, with no environment, so every pixel across it is the surface's own
/// answer to one known ray and nothing else. One case draws a sphere instead, for the
/// question that is about the surface turning away.
private final class FilmProbe: Sketch {
    enum Kind: Equatable {
        case plainMetal
        case filmStrengthZero
        case filmThicknessZero
        case film(Double)
        case filmOnDielectric(Double)
        case filmOnASphere(Double)
    }

    /// The gray the probe's metal is painted, kept here so the fidelity check can
    /// linearize the same number the sketch draws with.
    static let metalWhite = 0.75

    var kind: Kind = .plainMetal

    static func make(_ kind: Kind) -> FilmProbe {
        let probe = FilmProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.02))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        // Along the eye, so the middle of the sphere is seen and lit straight on. The
        // intensity keeps the brightest film under the ceiling, where a clipped channel
        // would stop saying which one leads.
        directionalLight(.white, direction: Vector3(0, 0, -1), intensity: 0.45)
        fill(Color(white: FilmProbe.metalWhite))
        material(finish())
        if case .filmOnASphere = kind {
            drawSphere(radius: 1.6)
        } else {
            // Square to the camera, so the whole face is seen and lit straight on and
            // reads as one color: the film's own, times a factor common to all three
            // channels.
            rotateX(.pi / 2)
            drawPlane(width: 3.2, depth: 3.2)
        }
    }

    private func finish() -> Material {
        let metal = Material(shading: .physicallyBased, metallic: 1, roughness: 0.42)
        switch kind {
        case .plainMetal:
            return metal
        case .filmStrengthZero:
            var m = metal; m.thinFilmThickness = 550; return m
        case .filmThicknessZero:
            var m = metal; m.thinFilm = 1; m.thinFilmThickness = 0; return m
        case .film(let t), .filmOnASphere(let t):
            var m = metal; m.thinFilm = 1; m.thinFilmThickness = t; return m
        case .filmOnDielectric(let t):
            var m = Material(shading: .physicallyBased, metallic: 0, roughness: 0.42)
            m.thinFilm = 1; m.thinFilmThickness = t; return m
        }
    }
}
