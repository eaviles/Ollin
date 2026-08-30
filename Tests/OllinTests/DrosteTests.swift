import Foundation
import Ollin
import Testing

/// Laws for `Filter.droste`, read off real renders. The construction promises one
/// thing above all: the picture is unchanged by a particular scale-and-turn, which
/// is what "inside itself, without end" means. That is a theorem about the map, so
/// it is what the tests measure, together with the hole never being read and the
/// zoom closing on itself after exactly one copy.
@Suite
@MainActor
struct DrosteTests {
    /// The factor that leaves a droste picture unchanged: a scale, and a turn once
    /// the copies are wound into a spiral. Derived from the map, not from the code:
    /// the log-plane rotation is `1 - ik`, so the step that moves one copy along the
    /// strip is `log(gamma) = period / (1 - ik)`.
    private func repeatFactor(inner: Double, twist: Double) -> (scale: Double, turn: Double) {
        let period = -log(inner)
        let k = twist * period / (2 * .pi)
        return (exp(period / (1 + k * k)), period * k / (1 + k * k))
    }

    /// A point turned and scaled about the middle of the canvas.
    private func stepped(_ point: Vector2, about center: Vector2,
                         by factor: (scale: Double, turn: Double)) -> Vector2 {
        let d = point - center
        let c = cos(factor.turn), s = sin(factor.turn)
        return center + Vector2(d.x * c - d.y * s, d.x * s + d.y * c) * factor.scale
    }

    // MARK: - The picture is inside itself

    /// The whole claim, measured: a point and the same point one copy out carry the
    /// same color. Plain concentric copies first, where the step is a pure scale.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCopyOutIsTheSamePicture() throws {
        let render = try #require(OllinApp.image(of: DrosteProbe.make(twist: 0), frame: 1))
        let pixels = try #require(Probe(render))
        let center = Vector2(120, 120)
        let step = repeatFactor(inner: 0.4, twist: 0)

        var checked = 0
        for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 5) {
            let here = center + Vector2(cos(angle), sin(angle)) * 26
            let out = stepped(here, about: center, by: step)
            guard pixels.holds(out) else { continue }
            checked += 1
            #expect(pixels.difference(here, out) < 14,
                    "a copy out should carry the same color at angle \(angle)")
        }
        #expect(checked >= 8, "expected the probe points to land on the canvas")
    }

    /// The same law once the copies are wound into a spiral, where the step is a
    /// scale *and* a turn. Nothing but the right log-plane rotation satisfies it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCopyOutIsTheSamePictureThroughTheTwist() throws {
        let render = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1), frame: 1))
        let pixels = try #require(Probe(render))
        let center = Vector2(120, 120)
        let step = repeatFactor(inner: 0.4, twist: 1)
        #expect(step.turn > 0.1, "the spiral should really turn, or the law is vacuous")

        var checked = 0
        for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 5) {
            let here = center + Vector2(cos(angle), sin(angle)) * 26
            let out = stepped(here, about: center, by: step)
            guard pixels.holds(out) else { continue }
            checked += 1
            #expect(pixels.difference(here, out) < 14,
                    "a copy out should carry the same color at angle \(angle)")
        }
        #expect(checked >= 8, "expected the probe points to land on the canvas")
    }

    /// The turn has to be part of it. Stepping out by the scale alone, with the
    /// spiral on, lands somewhere else, so the law above is not passing by accident.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theTurnIsWhatMakesTheSpiralMatch() throws {
        let render = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1), frame: 1))
        let pixels = try #require(Probe(render))
        let center = Vector2(120, 120)
        let step = repeatFactor(inner: 0.4, twist: 1)

        var worse = 0, compared = 0
        for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 5) {
            let here = center + Vector2(cos(angle), sin(angle)) * 26
            let right = stepped(here, about: center, by: step)
            let flat = stepped(here, about: center, by: (step.scale, 0))
            guard pixels.holds(right), pixels.holds(flat) else { continue }
            compared += 1
            if pixels.difference(here, flat) > pixels.difference(here, right) + 6 { worse += 1 }
        }
        #expect(compared >= 8)
        #expect(worse >= compared / 2,
                "dropping the turn should miss the matching copy at most angles")
    }

    // MARK: - The hole

    /// The middle of the source is never read: the map lands in the ring between
    /// `inner` and the edge, always. The probe paints the middle a color that
    /// appears nowhere else, so a single such pixel in the output is a wrap that
    /// walked out of its ring.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theHoleInTheMiddleIsNeverRead() throws {
        let source = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1, showSource: true), frame: 1))
        let plain = try #require(Probe(source))
        #expect(plain.countsMarker() > 200, "the marker should really be in the source")

        let render = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1), frame: 1))
        let pixels = try #require(Probe(render))
        #expect(pixels.countsMarker() == 0, "the hole must never be sampled")
    }

    // MARK: - The zoom

    /// One whole copy of zoom is the picture back where it started, which is what
    /// makes an endless fall loop.
    @Test(.enabled(if: Snapshot.hasMetal))
    func oneWholeCopyOfZoomComesBackToWhereItStarted() throws {
        let still = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1, zoom: 0), frame: 1))
        let round = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1, zoom: 1), frame: 1))
        let half = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1, zoom: 0.5), frame: 1))

        #expect(try meanDifference(still, round) < 1.5, "a whole copy of zoom should return")
        #expect(try meanDifference(still, half) > 8, "half a copy should not")
    }

    /// A quarter turn of `rotation` moves the picture, so the knob is wired.
    @Test(.enabled(if: Snapshot.hasMetal))
    func rotationTurnsIt() throws {
        let flat = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1), frame: 1))
        let turned = try #require(OllinApp.image(of: DrosteProbe.make(twist: 1, rotation: 0.7), frame: 1))
        #expect(try meanDifference(flat, turned) > 8)
    }

    // MARK: - Reading pixels

    private func meanDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let pa = try #require(Probe(a)), pb = try #require(Probe(b))
        return pa.meanDifference(from: pb)
    }
}

/// A rendered frame, read as bytes.
private struct Probe {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = buffer.withUnsafeMutableBytes({ raw in
                  CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
              }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bytes = buffer
    }

    func holds(_ point: Vector2) -> Bool {
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        return x >= 2 && y >= 2 && x < width - 2 && y < height - 2
    }

    func color(_ point: Vector2) -> (Int, Int, Int) {
        let x = min(max(Int(point.x.rounded()), 0), width - 1)
        let y = min(max(Int(point.y.rounded()), 0), height - 1)
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// The largest per-channel gap between two places in the same picture.
    func difference(_ a: Vector2, _ b: Vector2) -> Int {
        let ca = color(a), cb = color(b)
        return max(abs(ca.0 - cb.0), max(abs(ca.1 - cb.1), abs(ca.2 - cb.2)))
    }

    func meanDifference(from other: Probe) -> Double {
        guard other.bytes.count == bytes.count else { return .infinity }
        var total = 0
        for i in bytes.indices { total += abs(Int(bytes[i]) - Int(other.bytes[i])) }
        return Double(total) / Double(bytes.count)
    }

    /// How many pixels carry the marker painted into the source's hole. The marker is
    /// a mid gray, and the field around it is never less than a third saturated, so a
    /// pixel whose three channels agree at that level can only have come from the hole.
    func countsMarker() -> Int {
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
            guard r >= 100, r <= 170 else { continue }
            if abs(r - g) < 12 && abs(g - b) < 12 { count += 1 }
        }
        return count
    }
}

/// A smooth two-way field (hue around, lightness across) with a marker disc in the
/// middle that the map must never reach. Smooth on purpose: both probe points read
/// the *same* place in the source, so the only error left is the half pixel between
/// a probe point and its pixel center.
private final class DrosteProbe: Sketch {
    override var canvasSize: CanvasSize { .square(240) }

    private var twist = 0.0
    private var zoom = 0.0
    private var spin = 0.0
    private var showSource = false
    private var source = Image(width: 240, height: 240, color: .black)

    static func make(twist: Double, zoom: Double = 0, rotation: Double = 0,
                     showSource: Bool = false) -> DrosteProbe {
        let probe = DrosteProbe()
        probe.twist = twist
        probe.zoom = zoom
        probe.spin = rotation
        probe.showSource = showSource
        return probe
    }

    override func setup() {
        for y in 0 ..< 240 {
            for x in 0 ..< 240 {
                let p = Vector2(Double(x) - 119.5, Double(y) - 119.5) / 120
                let r = p.length
                if r < 0.34 {
                    // The marker: inside `inner`, so no wrap of the map should reach it.
                    // Gray, which the saturated field around it can never produce.
                    source[x, y] = Color(white: 0.52)
                    continue
                }
                let angle = atan2(p.y, p.x) / (2 * .pi) + 0.5
                source[x, y] = Color(hue: angle, saturation: 0.35 + 0.4 * r,
                                     brightness: 0.35 + 0.5 * min(r, 1))
            }
        }
    }

    override func draw() {
        background(.black)
        if showSource {
            drawImage(source, in: canvasRectangle)
            return
        }
        let layer = makeRenderTarget()
        withTarget(layer) { drawImage(source, in: canvasRectangle) }
        drawImage(layer.filtered(.droste(inner: 0.4, twist: twist, zoom: zoom,
                                         angle: spin)).image,
                  in: canvasRectangle)
    }
}
