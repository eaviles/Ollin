import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the `.defocus` depth-of-field combine, rendered headless and
/// read back. The pixel snapshots pin the *look* of a whole defocused scene but average
/// away the defects that show up while a focal plane racks, so these pin the gather's
/// rules directly: a near spread invents no color, a sharp subject rejects the blurred
/// backdrop behind it, a lightly defocused midground keeps its silhouette against a
/// heavily defocused backdrop, and a layer with transparency blurs its coverage along
/// with its color. Metal-gated.
@Suite
@MainActor
struct DefocusTests {

    /// Blurring white with white must give white. The near (foreground) field is a
    /// running average, and seeding it with black rather than the center texel left it
    /// converging *from* black, so a partly covered foreground composited a dark ring
    /// over the background: this scene came back with a ~12% dip at the edge of the
    /// near spread.
    @Test(.enabled(if: Snapshot.hasMetal))
    func nearSpreadInventsNoColour() throws {
        let image = try #require(OllinApp.image(of: NearSpreadProbe(), frame: 1))
        let px = pixels(of: image)
        var darkest = 255
        for i in stride(from: 0, to: px.bytes.count, by: 4) {
            darkest = min(darkest, Int(px.bytes[i]))
        }
        // Only the present pass's output dither may move it off pure white.
        #expect(darkest >= 250)
    }

    /// A subject sitting on the focal plane stays exactly itself, however blurred the
    /// backdrop behind it is: a farther tap is hidden by this pixel and may not spill
    /// onto it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func sharpSubjectRejectsTheBackdrop() throws {
        let image = try #require(OllinApp.image(of: MidgroundProbe.make(depth: 0.30), frame: 1))
        // 20px inside the silhouette, the square is its own color and nothing else.
        #expect(redRun(of: image, y: 300, from: 170, to: 280).min ?? 0 >= 250)
    }

    /// A barely defocused midground must not lose its edge to a heavily defocused
    /// backdrop. Without the occlusion clamp (a tap behind this pixel reaches no further
    /// than twice this pixel's own blur) the backdrop poured in for the full `maxBlur`
    /// however sharp the midground was, which is what made a rack read as a pop rather
    /// than a rack.
    @Test(.enabled(if: Snapshot.hasMetal))
    func midgroundKeepsItsEdgeAgainstAFarBackdrop() throws {
        let image = try #require(OllinApp.image(of: MidgroundProbe.make(depth: 0.52), frame: 1))
        // Depth 0.52 gives the square a 4.8px circle of confusion against the backdrop's
        // 48px, so it must be back to its own color within a few px of its edge.
        // (Measured: 5px with the clamp, 30px without.)
        let recovery = try #require(firstX(inImage: image, y: 300, from: 150, to: 260,
                                           reaching: 250))
        #expect(recovery - 150 <= 12)
    }

    /// A defocused foreground has to soften on *both* sides of its silhouette. Its
    /// outward spread is the easy half; the inward half needs the background field to be
    /// allowed to gather from under the near blur, and the foreground's coverage to be
    /// an area fraction of that blur rather than of the whole gather disc. Without both,
    /// a near object blurred by 60px kept a razor edge on the inside and stepped 40% of
    /// the way to the background in a single pixel.
    @Test(.enabled(if: Snapshot.hasMetal))
    func nearEdgeSoftensOnBothSides() throws {
        let image = try #require(OllinApp.image(of: NearEdgeProbe(), frame: 1))
        // The disc's silhouette is at x = 390 and its blur is 60px, so the walk covers
        // the whole ramp it should occupy.
        let run = redRun(of: image, y: 300, from: 318, to: 462).values
        let steps = stride(from: 6, to: run.count, by: 6).map { abs(run[$0] - run[$0 - 6]) }
        // No 6px stretch may carry more than a fifth of the whole transition.
        #expect((steps.max() ?? 255) < 50)
        // And 30px inside the silhouette it is genuinely mid-ramp, not still solid.
        #expect(run[360 - 318] > 40)
    }

    /// The layers are premultiplied, so the gather has to carry alpha with the color.
    /// Blurring only rgb left a hard alpha edge around a soft color edge: the shape
    /// stopped being premultiplied, and its silhouette stayed razor sharp no matter how
    /// much blur was asked for.
    @Test(.enabled(if: Snapshot.hasMetal))
    func transparentLayerBlursItsCoverageToo() throws {
        let image = try #require(OllinApp.image(of: TransparentEdgeProbe(), frame: 1))
        // Walk across the disc's edge over white, reading green (the red channel is 255
        // for both the red disc and the white page). A blurred coverage gives a wide,
        // graded ramp; a hard alpha edge gives a jump inside a pixel or two.
        let run = channelRun(of: image, channel: 1, y: 300, from: 150, to: 260)
        let graded = run.values.filter { $0 > 80 && $0 < 235 }.count
        #expect(graded >= 20)
    }

    /// `maxBlur` 0 is a pass-through, so the op is free to leave in a sketch.
    @Test(.enabled(if: Snapshot.hasMetal))
    func zeroBlurPassesThrough() throws {
        let blurred = try #require(OllinApp.image(of: MidgroundProbe.make(depth: 0.55, maxBlur: 0), frame: 1))
        let run = redRun(of: blurred, y: 300, from: 140, to: 160)
        // The silhouette is where the sketch drew it, with no ramp either side.
        #expect(run.values.filter { $0 > 20 && $0 < 235 }.count <= 2)
    }

    // MARK: Readback helpers

    private func pixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    /// One channel along one scanline, plus its minimum.
    private func channelRun(of image: CGImage, channel: Int, y: Int, from x0: Int, to x1: Int)
        -> (values: [Int], min: Int?) {
        let px = pixels(of: image)
        var out: [Int] = []
        for x in x0 ... min(x1, px.width - 1) {
            out.append(Int(px.bytes[(y * px.width + x) * 4 + channel]))
        }
        return (out, out.min())
    }

    private func redRun(of image: CGImage, y: Int, from x0: Int, to x1: Int)
        -> (values: [Int], min: Int?) {
        channelRun(of: image, channel: 0, y: y, from: x0, to: x1)
    }

    /// The first x at or past which the red channel stays at least `level`.
    private func firstX(inImage image: CGImage, y: Int, from x0: Int, to x1: Int,
                        reaching level: Int) -> Int? {
        let run = redRun(of: image, y: y, from: x0, to: x1).values
        for (i, v) in run.enumerated() where v >= level {
            if run[i...].allSatisfy({ $0 >= level }) { return x0 + i }
        }
        return nil
    }
}

// MARK: Probe sketches

/// A uniformly white layer defocused by a depth map whose only feature is a *near* disc:
/// the near field spreads, but there is no second color anywhere for it to spread.
private final class NearSpreadProbe: Sketch {
    override var canvasSize: CanvasSize { .square(600) }
    override func draw() {
        noLoop()
        compose {
            layer { background(.white) }
                .defocused(by: aside {
                    background(Color(white: 0.5))          // the backdrop sits at focus
                    noStroke(); fill(Color(white: 0.0))    // a near disc
                    drawCircle(300, 300, 90)
                }, focus: 0.5, range: 0.05, maxBlur: 60)
        }
    }
}

/// A red square at `depth` over a far backdrop, with the depth map's square drawn 10px
/// proud of the color square so its anti-aliased rim sits away from the color edge
/// (that rim is its own, separate artifact and would muddy the reading here).
/// focus 0.30, range 0.20, maxBlur 48, so depth 0.30 is sharp and 0.55 blurs by 12px
/// while the backdrop blurs by the full 48.
private final class MidgroundProbe: Sketch {
    var depth = 0.55
    var maxBlur = 48.0

    /// `Sketch` requires `init()`, so the knobs are set on the instance.
    static func make(depth: Double, maxBlur: Double = 48) -> MidgroundProbe {
        let probe = MidgroundProbe()
        probe.depth = depth; probe.maxBlur = maxBlur
        return probe
    }

    override var canvasSize: CanvasSize { .square(600) }
    override func draw() {
        noLoop()
        compose {
            layer {
                background(Color(white: 0.02))
                noStroke(); fill(Color(hex: 0xFF3B30))
                drawRect(150, 150, 300, 300)
            }
            .defocused(by: aside {
                background(Color(white: 1.0))
                noStroke(); fill(Color(white: depth))
                drawRect(140, 140, 320, 320)
            }, focus: 0.30, range: 0.20, maxBlur: maxBlur)
        }
    }
}

/// A near, heavily defocused disc in front of a sharp background that sits just *behind*
/// the focal plane (0.55 against focus 0.5, range 0.05: still inside the sharp band, but
/// unambiguously on the far side of it, so the near/far sort has no tie to break).
private final class NearEdgeProbe: Sketch {
    override var canvasSize: CanvasSize { .square(600) }
    override func draw() {
        noLoop()
        compose {
            layer {
                background(.white)
                noStroke(); fill(Color(hex: 0x00A8E8))
                drawCircle(300, 300, 90)
            }
            .defocused(by: aside {
                background(Color(white: 0.55))
                noStroke(); fill(Color(white: 0.0))       // near
                drawCircle(300, 300, 90)
            }, focus: 0.5, range: 0.05, maxBlur: 60)
        }
    }
}

/// A red disc on an otherwise *transparent* layer, defocused, composited over white:
/// the coverage has to blur with the color or the silhouette stays hard.
private final class TransparentEdgeProbe: Sketch {
    override var canvasSize: CanvasSize { .square(600) }
    override func draw() {
        noLoop()
        background(.white)
        compose {
            layer {                                        // no background: transparent
                noStroke(); fill(Color(hex: 0xFF3B30))
                drawCircle(300, 300, 100)
            }
            .defocused(by: aside {
                background(Color(white: 1.0))              // far, so the disc blurs
                noStroke(); fill(Color(white: 1.0))
                drawCircle(300, 300, 100)
            }, focus: 0.0, range: 0.05, maxBlur: 40)
        }
    }
}
