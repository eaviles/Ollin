@testable import Ollin
import Testing
import CoreGraphics

/// Behavioral probes for the layered physically-based lobes: a clear coat must add its
/// own highlight over a base too rough (or too dark) to make one, under every lighting
/// route the lobe rides (a punctual light, an area panel's LTC integral, the environment
/// gather), and sheen must brighten the silhouette rim. A mean-diff snapshot can't pin
/// these (the lobes live in small regions), so each probe compares a pair of renders
/// differing only in the lobe.
@Suite
@MainActor
struct CoatSheenRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean of one channel over a fractional region (top-left origin).
    private func mean(_ data: [UInt8], width: Int, height: Int, channel: Int,
                      x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        var sum = 0, count = 0
        for py in Int(Double(height) * y.lowerBound)..<Int(Double(height) * y.upperBound) {
            for px in Int(Double(width) * x.lowerBound)..<Int(Double(width) * x.upperBound) {
                sum += Int(data[(py * width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    /// Peak green over the sphere's projected disc. The coat swaps the base's *broad*
    /// dim specular for a *sharp* bright one (its base F0 also re-derives toward 0
    /// under the film), so a region mean legitimately goes *down* with a coat; the
    /// lobe's signature is the peak.
    private func peak(_ image: CGImage) -> Double {
        let d = pixels(of: image)
        var top = 0
        for py in Int(Double(image.height) * 0.3)..<Int(Double(image.height) * 0.7) {
            for px in Int(Double(image.width) * 0.3)..<Int(Double(image.width) * 0.7) {
                top = max(top, Int(d[(py * image.width + px) * 4 + 1]))
            }
        }
        return Double(top)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCoatAddsItsHighlightUnderAPointLight() throws {
        // A fully rough near-black dielectric shows only a broad dim sheen; the same
        // sphere under a polished coat must gain a sharp highlight (the film's second
        // lobe), far brighter at its peak than anything the bare surface makes.
        let coated = try #require(OllinApp.image(of: CoatProbe.make(kind: .coatPoint), frame: 1))
        let bare = try #require(OllinApp.image(of: CoatProbe.make(kind: .barePoint), frame: 1))
        let a = peak(coated), b = peak(bare)
        #expect(a - b > 40, "expected the coat's sharp highlight: coated \(a), bare \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCoatReflectsAPanelLight() throws {
        // Under a rect area light alone the coat runs its own LTC fetch at the coat
        // roughness, so the panel's sharp reflection must appear on a coated rough
        // black sphere where the bare one shows only a broad wash.
        let coated = try #require(OllinApp.image(of: CoatProbe.make(kind: .coatPanel), frame: 1))
        let bare = try #require(OllinApp.image(of: CoatProbe.make(kind: .barePanel), frame: 1))
        let a = peak(coated), b = peak(bare)
        #expect(a - b > 40, "expected the panel in the coat: coated \(a), bare \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCoatGathersTheEnvironment() throws {
        // Under an environment alone, a fully rough black dielectric gathers only the
        // flat broad average; the coat's smooth gather must bring the environment's
        // bright features back as a distinct peak.
        let coated = try #require(OllinApp.image(of: CoatProbe.make(kind: .coatEnv), frame: 1))
        let bare = try #require(OllinApp.image(of: CoatProbe.make(kind: .bareEnv), frame: 1))
        let a = peak(coated), b = peak(bare)
        #expect(a - b > 40, "expected the environment in the coat: coated \(a), bare \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func sheenRimsTheSilhouette() throws {
        // Sheen is fabric fuzz at grazing angles: a white-sheen cloth sphere must
        // brighten in a band just inside its silhouette relative to the same sphere
        // without sheen (the lobe peaks where the view grazes the surface).
        let sheen = try #require(OllinApp.image(of: CoatProbe.make(kind: .sheen), frame: 1))
        let plain = try #require(OllinApp.image(of: CoatProbe.make(kind: .plainCloth), frame: 1))
        let dS = pixels(of: sheen), dP = pixels(of: plain)
        func rim(_ d: [UInt8], _ img: CGImage) -> Double {
            // A vertical band crossing the sphere's left rim at mid-height.
            mean(d, width: img.width, height: img.height, channel: 1,
                 x: 0.24...0.34, y: 0.42...0.58)
        }
        let a = rim(dS, sheen), b = rim(dP, plain)
        #expect(a - b > 6, "expected a brighter sheen rim: sheen \(a), plain \(b)")
    }
}

/// The probe scene, one variant per case: a single sphere under a fixed camera, the
/// material's lobe and the lighting route varied by `kind`.
private final class CoatProbe: Sketch {
    enum Kind {
        case coatPoint, barePoint       // punctual: the coat's Cook-Torrance lobe
        case coatPanel, barePanel       // area: the coat's second LTC fetch
        case coatEnv, bareEnv           // IBL: the coat's smooth prefiltered gather
        case sheen, plainCloth          // the sheen rim
    }
    var kind: Kind = .coatPoint

    static func make(kind: Kind) -> CoatProbe {
        let probe = CoatProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0.0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        let roughBlack = Material(shading: .physicallyBased, metallic: 0, roughness: 1)
        var coated = roughBlack
        coated.clearcoat = 1
        coated.clearcoatRoughness = 0.05
        switch kind {
        case .coatPoint, .barePoint:
            pointLight(.white, at: Vector3(2.5, 2, 4), intensity: 1.4)
            fill(Color(white: 0.03))
            material(kind == .coatPoint ? coated : roughBlack)
            drawSphere(radius: 1.2)
        case .coatPanel, .barePanel:
            rectangleLight(.white, at: Vector3(2.2, 1.5, 3.5), direction: Vector3(-0.5, -0.3, -0.8),
                      width: 2.5, height: 2.5, intensity: 3)
            fill(Color(white: 0.03))
            material(kind == .coatPanel ? coated : roughBlack)
            drawSphere(radius: 1.2)
        case .coatEnv, .bareEnv:
            environment(.studio)
            fill(Color(white: 0.03))
            material(kind == .coatEnv ? coated : roughBlack)
            drawSphere(radius: 1.2)
        case .sheen, .plainCloth:
            directionalLight(.white, direction: Vector3(-0.3, -0.4, -1), intensity: 1.2)
            fill(Color(hue: 0.62, saturation: 0.6, brightness: 0.35))
            var cloth = Material(shading: .physicallyBased, metallic: 0, roughness: 0.9)
            if kind == .sheen {
                cloth.sheen = 1
                cloth.sheenRoughness = 0.6
            }
            material(cloth)
            drawSphere(radius: 1.2)
        }
    }
}
