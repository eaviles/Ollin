@testable import Ollin
import Testing
import CoreGraphics

/// Behavioral probes for the lens flare: the invariants a mean-diff snapshot
/// cannot pin. The flare has to add light at all, it has to follow how much of
/// its source the camera can *see* rather than switching off, stopping the iris
/// down has to shrink the ghosts, and a frame that does not ask for one has to
/// come out untouched.
@Suite
@MainActor
struct LensFlareRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// How much light the flare adds, as the mean rise over the same frame drawn
    /// without one. Reading the *difference* is what makes the occluder cases
    /// comparable: whatever the occluder does to the scene cancels, and what is
    /// left is the flare alone.
    private func flareAdded(_ occluder: FlareProbe.Occluder,
                            fStop: Double = 4.5, star: Double = 0,
                            near: Bool = false) throws -> Double {
        let on = try #require(OllinApp.image(of: FlareProbe.make(occluder: occluder, flare: true,
                                                                fStop: fStop, star: star),
                                             frame: 1))
        let off = try #require(OllinApp.image(of: FlareProbe.make(occluder: occluder, flare: false,
                                                                 fStop: fStop, star: star),
                                              frame: 1))
        return rise(pixels(of: on), over: pixels(of: off),
                    width: on.width, height: on.height, near: near)
    }

    /// The mean rise of one frame over another, either over the whole picture or
    /// only over the patch the source sits in.
    private func rise(_ a: [UInt8], over b: [UInt8], width: Int, height: Int,
                      near: Bool) -> Double {
        // The lamp projects a little right of and above the middle in the probe
        // scene; this patch holds its star and almost none of the ghost chain.
        let xs = near ? Int(Double(width) * 0.55)..<Int(Double(width) * 0.67) : 0..<width
        let ys = near ? Int(Double(height) * 0.38)..<Int(Double(height) * 0.50) : 0..<height
        var sum = 0.0, count = 0
        for y in ys {
            for x in xs {
                let i = (y * width + x) * 4
                for c in 0..<3 { sum += max(0, Double(a[i + c]) - Double(b[i + c])) }
                count += 3
            }
        }
        return sum / Double(max(count, 1))
    }

    /// What the ghosts alone add, measured in linear light: all of it, the
    /// brightest pixel of it, and how many pixels are clearly lit.
    ///
    /// The flare is drawn at a fraction of its usual level. At the usual one the
    /// brightest ghost sits at the top of what eight bits hold, and a peak that
    /// cannot rise says nothing about light that was gathered. The rise is taken
    /// in linear light because that is where light adds: the same ghost over a
    /// lit floor and over a black wall rises by different amounts once encoded.
    private func ghostLight(_ lens: Lens, fStop: Double? = nil, sourceSize: Double = 0.015)
        throws -> (total: Double, peak: Double, covered: Int, steepest: Double,
                   steepestAcross: Double, steepestUp: Double) {
        let stopped = fStop.map { lens.stopped(to: $0) } ?? lens
        let on = try #require(OllinApp.image(of: FlareProbe.make(
            occluder: .none, flare: true, sourceSize: sourceSize, amount: 0.12,
            lens: stopped), frame: 1))
        let off = try #require(OllinApp.image(of: FlareProbe.make(
            occluder: .none, flare: false, sourceSize: sourceSize, lens: stopped), frame: 1))
        let a = pixels(of: on), b = pixels(of: off)
        func linear(_ byte: UInt8) -> Double {
            let v = Double(byte) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        var total = 0.0, peak = 0.0, covered = 0, across = 0.0, up = 0.0
        let width = on.width
        var rises = [Double](repeating: 0, count: a.count / 4)
        for i in stride(from: 0, to: a.count, by: 4) {
            let rise = (0..<3).map { max(0, linear(a[i + $0]) - linear(b[i + $0])) }.max() ?? 0
            rises[i / 4] = rise
            total += rise
            peak = max(peak, rise)
            if rise > 0.003 { covered += 1 }
        }
        // The sharpest step between two neighboring pixels, which is an edge. Only
        // where the scene itself is flat and dark underneath: a ghost crossing the
        // lit bulb rises by nothing on it and by its whole level beside it, and
        // that step is the bulb's edge, which no source size softens.
        func plain(_ i: Int, _ j: Int) -> Bool {
            for channel in 0..<3 {
                let here = Int(b[i * 4 + channel]), there = Int(b[j * 4 + channel])
                if here >= 48 || abs(here - there) > 1 { return false }
            }
            return true
        }
        for index in rises.indices where index % width != width - 1 && index + width < rises.count {
            if plain(index, index + 1) { across = max(across, abs(rises[index + 1] - rises[index])) }
            if plain(index, index + width) { up = max(up, abs(rises[index + width] - rises[index])) }
        }
        return (total, peak, covered, max(across, up), across, up)
    }

    /// A ghost is a picture taken with the source, so its edge is as soft as the
    /// source is wide: a wider source spreads each ghost over more of the frame
    /// and takes the step at its edge down. The middle of a wide flat ghost does
    /// not dim, which is why the edge is what is measured and not the peak.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aWiderSourceSoftensTheGhosts() throws {
        let lens = Lens.doubleGauss.multicoated()
        let point = try ghostLight(lens, fStop: 8, sourceSize: 0.003)
        let lamp = try ghostLight(lens, fStop: 8, sourceSize: 0.04)
        #expect(lamp.covered > point.covered,
                "a wide source covers \(lamp.covered) pixels against \(point.covered)")
        #expect(point.steepest > lamp.steepest * 1.5,
                "a point source's sharpest edge steps by \(point.steepest) against \(lamp.steepest)")
    }

    /// The iris moves the flare's light and adds none. Closing it shrinks the
    /// ghosts it shapes, and the same light in a smaller shape is a brighter one.
    /// The double Gauss is the lens to ask, since its ghosts are the iris's to
    /// shape; most of the Heliar's are bounded by the barrel, which does not move.
    @Test(.enabled(if: Snapshot.hasMetal))
    func stoppingDownGathersTheLightAndAddsNone() throws {
        let lens = Lens.doubleGauss.multicoated()
        let open = try ghostLight(lens, fStop: 4, sourceSize: 0.004)
        let closed = try ghostLight(lens, fStop: 11, sourceSize: 0.004)
        #expect(closed.covered < open.covered * 3 / 4,
                "stopped down the ghosts cover \(closed.covered) pixels against \(open.covered)")
        #expect(closed.peak > open.peak * 1.3,
                "stopped down they peak at \(closed.peak) against \(open.peak)")
        #expect(closed.total < open.total * 2 && closed.total > open.total / 4,
                "and carry \(closed.total) against \(open.total): gathered, not multiplied")
    }

    /// Following the rays is what stops a ghost at the barrel. First order has no
    /// barrel in it: a ghost is the whole front opening's worth of light, scaled.
    /// A real ray that strays past the rim of any element on the way is lost, and
    /// on a lens of wide ghosts that is most of what first order draws.
    @Test(.enabled(if: Snapshot.hasMetal))
    func followingTheRaysStopsAGhostAtTheBarrel() throws {
        let lens = Lens.heliar.multicoated()
        let followed = try ghostLight(lens, sourceSize: 0.004)
        MetalRenderer.flareFollowsRays = false
        defer { MetalRenderer.flareFollowsRays = true }
        let firstOrder = try ghostLight(lens, sourceSize: 0.004)
        #expect(followed.covered > 0 && firstOrder.covered > 0)
        // Measured: 48% of first order's pixels, and 73% with the barrel's clip
        // taken out of the shader (lost rays and the losses at each refraction
        // account for the rest), so 60% is the line only the barrel puts it under.
        #expect(Double(followed.covered) < Double(firstOrder.covered) * 0.6,
                "followed, the ghosts cover \(followed.covered) pixels against first order's \(firstOrder.covered)")
    }

    /// What one of the extras adds, in linear light, as a picture: the frame with
    /// it over the same frame with a flare that leaves it out, so the ghosts
    /// cancel and only the extra is left.
    private func extraLight(streak: Double = 0, halo: Double = 0, dirt: Double = 0,
                            occluder: FlareProbe.Occluder = .none, haloSize: Double = 0.38,
                            lens: Lens? = nil)
        throws -> (rise: [Double], width: Int, height: Int) {
        let with = try #require(OllinApp.image(of: FlareProbe.make(
            occluder: occluder, flare: true, lens: lens, streak: streak, halo: halo, dirt: dirt,
            haloSize: haloSize), frame: 1))
        let without = try #require(OllinApp.image(of: FlareProbe.make(
            occluder: occluder, flare: true, lens: lens), frame: 1))
        let a = pixels(of: with), b = pixels(of: without)
        func linear(_ byte: UInt8) -> Double {
            let v = Double(byte) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        var rise = [Double](repeating: 0, count: a.count / 4)
        for i in stride(from: 0, to: a.count, by: 4) {
            rise[i / 4] = (0..<3).map { max(0, linear(a[i + $0]) - linear(b[i + $0])) }.max() ?? 0
        }
        return (rise, with.width, with.height)
    }

    /// How far the ghosts' light is spread each way about its own middle, as the
    /// variance of where it falls, weighted by how much falls there.
    private func ghostSpread(_ lens: Lens) throws -> (across: Double, up: Double) {
        let on = try #require(OllinApp.image(of: FlareProbe.make(
            occluder: .none, flare: true, sourceSize: 0.004, amount: 0.12, lens: lens), frame: 1))
        let off = try #require(OllinApp.image(of: FlareProbe.make(
            occluder: .none, flare: false, sourceSize: 0.004, lens: lens), frame: 1))
        let a = pixels(of: on), b = pixels(of: off)
        var total = 0.0, sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumYY = 0.0
        for y in 0..<on.height {
            for x in 0..<on.width {
                let i = (y * on.width + x) * 4
                let rise = max(0, Double(a[i + 1]) - Double(b[i + 1]))
                total += rise
                sumX += rise * Double(x); sumY += rise * Double(y)
                sumXX += rise * Double(x * x); sumYY += rise * Double(y * y)
            }
        }
        guard total > 0 else { return (0, 0) }
        let meanX = sumX / total, meanY = sumY / total
        return (sumXX / total - meanX * meanX, sumYY / total - meanY * meanY)
    }

    /// An anamorphic front group stretches what forms behind it sideways, and
    /// only sideways: the ghosts spread further across the frame and no further
    /// up it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anAnamorphicLensStretchesTheGhostsSideways() throws {
        let lens = Lens.doubleGauss.multicoated().stopped(to: 8)
        let plain = try ghostSpread(lens)
        let squeezed = try ghostSpread(lens.anamorphic(squeeze: 2))
        #expect(plain.across > 0 && plain.up > 0)
        #expect(squeezed.across > plain.across * 1.6,
                "across: \(squeezed.across) squeezed against \(plain.across)")
        #expect(squeezed.up < plain.up * 1.3,
                "up: \(squeezed.up) squeezed against \(plain.up)")
    }

    /// Behind an anamorphic front group a round source is still round on the
    /// frame, so it softens a ghost's edge by as much across as up. Left as a disc
    /// on the sensor it would come out twice as wide as tall once the picture is
    /// stretched back, and the edges facing sideways would be twice as soft: half
    /// the step from one pixel to the next.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anAnamorphicGhostIsAsSoftAcrossAsUp() throws {
        let lens = Lens.doubleGauss.multicoated().stopped(to: 8)
        let plain = try ghostLight(lens, sourceSize: 0.03)
        let squeezed = try ghostLight(lens.anamorphic(squeeze: 2), sourceSize: 0.03)
        let before = plain.steepestAcross / plain.steepestUp
        let after = squeezed.steepestAcross / squeezed.steepestUp
        #expect(plain.steepestUp > 0 && squeezed.steepestUp > 0)
        // Measured: 0.89 of the plain lens's own ratio, and 0.53 of it with every
        // edge left as soft as the sensor has it, so the line sits between them.
        #expect(after > before * 0.72,
                "across over up: \(after) squeezed against \(before) plain")
    }

    /// Where the probe's lamp sits on the frame, as fractions of it.
    private let lampAt = (x: 0.61, y: 0.44)

    /// A streak filter throws one line through the light and nothing anywhere
    /// else: light far along the line, on the lamp's own row, and none a little
    /// way above or below it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStreakIsOneLineThroughTheLight() throws {
        let (rise, width, height) = try extraLight(streak: 1)
        let row = Int(lampAt.y * Double(height))
        let farLeft = Int(0.08 * Double(width))
        func at(_ x: Int, _ y: Int) -> Double { rise[y * width + x] }
        let onLine = (row - 1...row + 1).map { at(farLeft, $0) }.max() ?? 0
        let offLine = max(at(farLeft, row - height / 8), at(farLeft, row + height / 8))
        #expect(onLine > 0.004, "the streak reaches far along its line: \(onLine)")
        #expect(offLine < onLine / 8, "and stays on it: \(offLine) off the line against \(onLine) on it")
    }

    /// The halo is a ring: brightest at its own radius from the light, with
    /// little inside it and little beyond.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theHaloIsARingAtItsRadius() throws {
        let (rise, width, height) = try extraLight(halo: 1)
        // Straight up from the lamp, over the dark wall. The default radius is
        // 0.38 frame heights.
        let x = Int(lampAt.x * Double(width))
        func above(_ fraction: Double) -> Double {
            let y = Int((lampAt.y - fraction) * Double(height))
            return y >= 0 ? rise[y * width + x] : 0
        }
        let onRing = [0.37, 0.38, 0.39].map(above).max() ?? 0
        #expect(onRing > 0.004, "there is a ring: \(onRing)")
        #expect(above(0.2) < onRing / 6, "and the inside of it is dark: \(above(0.2))")
    }

    /// The halo is drawn as something formed inside the lens, so an anamorphic
    /// front group stretches it sideways with the ghosts: it crosses the lamp's
    /// own row twice as far out as it stands above the lamp, and where a round
    /// ring would cross that row there is nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anAnamorphicLensStretchesTheHalo() throws {
        let lens = Lens.heliar.multicoated().stopped(to: 4.5).anamorphic(squeeze: 2)
        let (rise, width, height) = try extraLight(halo: 1, haloSize: 0.2, lens: lens)
        let row = Int(lampAt.y * Double(height)), column = Int(lampAt.x * Double(width))
        func beside(_ fraction: Double) -> Double {
            let x = Int((lampAt.x - fraction) * Double(width))
            guard x >= 0 else { return 0 }
            var most = 0.0
            for y in (row - 1)...(row + 1) { most = max(most, rise[y * width + x]) }
            return most
        }
        func above(_ fraction: Double) -> Double {
            let y = Int((lampAt.y - fraction) * Double(height))
            guard y >= 0 else { return 0 }
            var most = 0.0
            for x in (column - 1)...(column + 1) { most = max(most, rise[y * width + x]) }
            return most
        }
        let up = [0.19, 0.2, 0.21].map(above).max() ?? 0
        let out = [0.39, 0.4, 0.41].map(beside).max() ?? 0
        #expect(up > 0.004, "the ring stands its radius above the lamp: \(up)")
        #expect(out > 0.004, "and twice that beside it: \(out)")
        #expect(beside(0.2) < out / 4, "with nothing where a round ring would cross: \(beside(0.2))")
    }

    /// Dirt is lit by the light it sits in front of, so it follows how much of
    /// that light the camera can see, like the rest of the flare: there with the
    /// lamp clear, gone with the lamp hidden.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDirtIsLitByTheLightItSitsBefore() throws {
        let clear = try extraLight(dirt: 1).rise.reduce(0, +)
        let hidden = try extraLight(dirt: 1, occluder: .full).rise.reduce(0, +)
        #expect(clear > 1, "a dirty lens shows its dirt toward a light: \(clear)")
        #expect(hidden < clear * 0.1, "and not once the light is hidden: \(hidden) against \(clear)")
    }

    /// A flare is light arriving, so it can only add: no pixel of the frame is
    /// darker with it than without. What broke this once was a sliver of a ghost's
    /// mesh read past its own edge, which came back as less than no light and put
    /// single black pixels in a veil.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFlareNeverTakesLightAway() throws {
        var darkened = 0, worst = 0
        for lens in [Lens.doubleGauss.multicoated().stopped(to: 11),
                     Lens.doubleGauss.multicoated().stopped(to: 11).anamorphic(squeeze: 2),
                     Lens.heliar.multicoated()] {
            let on = try #require(OllinApp.image(of: FlareProbe.make(
                occluder: .none, flare: true, sourceSize: 0.02, amount: 2, lens: lens), frame: 1))
            let off = try #require(OllinApp.image(of: FlareProbe.make(
                occluder: .none, flare: false, sourceSize: 0.02, lens: lens), frame: 1))
            let a = pixels(of: on), b = pixels(of: off)
            for i in stride(from: 0, to: a.count, by: 4) {
                // Two levels of room for the present pass's dither.
                var drop = 0
                for channel in 0..<3 {
                    let without = Int(b[i + channel]), with = Int(a[i + channel])
                    drop = max(drop, without - with)
                }
                if drop > 2 { darkened += 1; worst = max(worst, drop) }
            }
        }
        #expect(darkened == 0, "\(darkened) pixels are darker with the flare on, by up to \(worst) levels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFlareAddsLightToTheFrame() throws {
        let added = try flareAdded(.none)
        #expect(added > 4, "the flare should be plainly there: \(added)")
    }

    /// The design rule that separates a flare from a sticker: its strength
    /// follows the source's *visible* area, so an occluder fades it rather than
    /// switching it off. Half a source gives roughly half a flare.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anOccluderFadesTheFlareRatherThanEndingIt() throws {
        let clear = try flareAdded(.none)
        let half = try flareAdded(.half)
        let hidden = try flareAdded(.full)
        #expect(clear > 4, "nothing to fade: \(clear)")
        #expect(half < clear * 0.85, "a covered source should dim the flare: \(half) of \(clear)")
        #expect(half > clear * 0.15, "it should fade, not switch off: \(half) of \(clear)")
        #expect(hidden < clear * 0.1, "a hidden source should leave almost none: \(hidden)")
    }

    /// A sketch that does not ask for a flare pays nothing and renders exactly
    /// as it did before there was one, and turning it back off is the same as
    /// never turning it on.
    /// The star is the flare's other half: it sits on the source itself, where
    /// the ghosts deliberately do not.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStarLandsOnTheSourceItself() throws {
        let without = try flareAdded(.none, star: 0, near: true)
        let with = try flareAdded(.none, star: 1, near: true)
        #expect(with > without + 3,
                "the star should light the source's own patch: \(without) without, \(with) with")
        // And it is separable: turning it off leaves the chain across the frame.
        let chain = try flareAdded(.none, star: 0)
        #expect(chain > 4, "the ghosts should still be there without a star: \(chain)")
    }

    /// The star is light bending at the blades, so a round iris has no arms to
    /// throw and a bladed one does. Comparing the same pair with the star turned
    /// off is what makes this about the star rather than about the ghosts, which
    /// the blade count also shapes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBladesShapeTheStar() throws {
        func spread(star: Double) throws -> Int {
            let round = try #require(OllinApp.image(of: FlareProbe.make(
                occluder: .none, flare: true, star: star, blades: 0), frame: 1))
            let bladed = try #require(OllinApp.image(of: FlareProbe.make(
                occluder: .none, flare: true, star: star, blades: 6), frame: 1))
            let a = pixels(of: round), b = pixels(of: bladed)
            let width = round.width, height = round.height
            var differing = 0
            for y in Int(Double(height) * 0.30)..<Int(Double(height) * 0.58) {
                for x in Int(Double(width) * 0.47)..<Int(Double(width) * 0.75) {
                    let i = (y * width + x) * 4
                    if abs(Double(a[i + 1]) - Double(b[i + 1])) > 8 { differing += 1 }
                }
            }
            return differing
        }
        let withStar = try spread(star: 1)
        let withoutStar = try spread(star: 0)
        #expect(withStar > withoutStar * 2 + 40,
                "the blades should reshape the star: \(withoutStar) without, \(withStar) with")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func askingForNoFlareLeavesTheFrameUntouched() throws {
        let never = try #require(OllinApp.image(of: FlareProbe.make(occluder: .none, flare: false),
                                                frame: 1))
        let cancelled = try #require(OllinApp.image(of: FlareProbe.make(occluder: .none,
                                                                       flare: true, cancel: true),
                                                    frame: 1))
        #expect(pixels(of: never) == pixels(of: cancelled))
    }
}

/// A fixed scene with one lamp, drawn with or without a flare and with the lamp
/// clear of, half behind, or fully behind a slab. No clock, so every frame is
/// the same picture.
private final class FlareProbe: Sketch {

    enum Occluder { case none, half, full }

    var occluder: Occluder = .none
    var wantsFlare = false
    var cancels = false
    var fStop = 4.5
    var star = 0.0
    var blades = 6
    var sourceSize = 0.015
    var amount = 1.0
    var lens: Lens?
    var streak = 0.0, halo = 0.0, dirt = 0.0, haloSize = 0.38

    static func make(occluder: Occluder, flare: Bool, cancel: Bool = false,
                     fStop: Double = 4.5, star: Double = 0, blades: Int = 6,
                     sourceSize: Double = 0.015, amount: Double = 1,
                     lens: Lens? = nil, streak: Double = 0, halo: Double = 0,
                     dirt: Double = 0, haloSize: Double = 0.38) -> FlareProbe {
        let probe = FlareProbe()
        probe.haloSize = haloSize
        probe.lens = lens
        probe.streak = streak
        probe.halo = halo
        probe.dirt = dirt
        probe.sourceSize = sourceSize
        probe.amount = amount
        probe.occluder = occluder
        probe.wantsFlare = flare
        probe.cancels = cancel
        probe.fStop = fStop
        probe.star = star
        probe.blades = blades
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    /// Where the lamp sits, and the eye it is seen from. The occluder's edge is
    /// placed on the line between them, so half of the lamp's disc is covered.
    private let lamp = Vector3(1.0, 2.1, -2)
    private let eye = Vector3(0, 1.5, 7)

    override func draw() {
        background(Color(white: 0.03))
        var view = Camera3D(eye: eye, target: Vector3(0, 1.5, 0), near: 0.2, far: 60,
                            projection: .perspective(fieldOfView: .pi / 3.2))
        view.apertureBlades = blades
        camera(view)
        ambientLight(Color(white: 0.05))
        pointLight(Color(hex: 0xFFF2D6), at: lamp, intensity: 14)
        if wantsFlare {
            lensFlare(LensFlare(lens: lens ?? Lens.heliar.multicoated().stopped(to: fStop),
                                amount: amount, star: star, streak: streak, halo: halo,
                                haloSize: haloSize, dirt: dirt, sourceSize: sourceSize))
        }
        if cancels { noLensFlare() }

        fill(.white)
        matcap(bulb)
        withState {
            translate(lamp)
            drawSphere(radius: 0.16)
        }
        matcap(nil)

        fill(Color(white: 0.28))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 24, height: 0.1, depth: 24)
        }
        // The slab sits halfway to the lamp, with its near edge on the eye-to-lamp
        // line for the half case and a little past it for the full one.
        if occluder != .none {
            let middle = eye + (lamp - eye) * 0.5
            let shift = occluder == .half ? 2.0 : 1.2
            fill(Color(white: 0.35))
            withState {
                translate(middle.x + shift, middle.y, middle.z)
                drawBox(width: 4, height: 3, depth: 0.4)
            }
        }
    }

    private let bulb = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))
}
