import Ollin
import OllinSamplePhotos

/// Eight tape and lens looks, one picker across them: a street on a worn
/// videotape, woven blankets saved as a JPEG at a quality that sweeps down to
/// tiles and back, a city panned through a datamosh until its blocks drag, the
/// same rooftops through a tilt-shift lens that turns them into a model, a
/// shoreline blurring in from the bottom, a portrait fogged by a light leak,
/// a page of tiles peeling off the stone under it, and a headland in sepia
/// under the hairline scratches of a worn print. Each is one filter, one
/// generator, or one simulation, and each moves.
@main
final class TapeAndLens: Sketch {
    enum Look: String, CaseIterable, ParamOption {
        case vhs, jpeg, datamosh, tiltShift, progressiveBlur, lightLeak, pagePeel, scratches
    }

    @Param(style: .segmented, icon: "film") var look = Look.vhs
    @Param("Amount", 0 ... 2, icon: "slider.horizontal.3") var amount = 1.0
    @Param("Seed", 0 ... 99, icon: "dice") var seed = 3

    override var loopDuration: Double? { 12 }

    private var street = Image(width: 1, height: 1)
    private var textiles = Image(width: 1, height: 1)
    private var city = Image(width: 1, height: 1)
    private var boats = Image(width: 1, height: 1)
    private var portrait = Image(width: 1, height: 1)
    private var talavera = Image(width: 1, height: 1)
    private var stone = Image(width: 1, height: 1)
    private var headland = Image(width: 1, height: 1)
    private var mosh: SimField?
    private var moshSeed = -1

    override func setup() {
        street = SamplePhoto.street.load()
        textiles = SamplePhoto.textiles.load()
        city = SamplePhoto.city.load()
        boats = SamplePhoto.boats.load()
        portrait = SamplePhoto.portrait.load()
        talavera = SamplePhoto.talavera.load()
        stone = SamplePhoto.stone.load()
        headland = SamplePhoto.headland.load()
    }

    override func draw() {
        let t = loopProgress(over: 12)
        switch look {
        case .vhs: drawTape(t)
        case .jpeg: drawCompression(t)
        case .datamosh: drawDatamosh(t)
        case .tiltShift: drawTiltShift(t)
        case .progressiveBlur: drawProgressive(t)
        case .lightLeak: drawLeak(t)
        case .pagePeel: drawPeel(t)
        case .scratches: drawScratches(t)
        }
    }

    /// `photo` filling the canvas, drifting by `pan` (a fraction of the
    /// canvas) and magnified by `zoom`, so a still picture has motion in it.
    private func drawPanned(_ photo: Image, pan: Vector2, zoom: Double) {
        let w = width * zoom, h = height * zoom
        let x = (width - w) / 2 + pan.x * width, y = (height - h) / 2 + pan.y * height
        drawImage(photo, in: Rectangle(x: x, y: y, width: w, height: h), fit: .cover)
    }

    // MARK: Tape

    /// A street on tape, the camera drifting along it.
    private func drawTape(_ t: Double) {
        let scene = makeRenderTarget()
        withTarget(scene) {
            drawPanned(street, pan: Vector2(0.05 * sin(t * .tau), 0), zoom: 1.12)
        }
        drawImage(scene.filtered(.vhs(amount: amount, phase: time)).image, 0, 0)
    }

    // MARK: Compression

    /// Woven blankets saved as a JPEG, the quality sweeping from 100 down to
    /// 4 and back over the loop, the number in the corner.
    private func drawCompression(_ t: Double) {
        let sweep = 0.5 + 0.5 * cos(t * .tau)
        let quality = max(1, Int((4 + 96 * pow(sweep, 3)) / max(amount, 0.05)))
        let scene = makeRenderTarget()
        withTarget(scene) { drawPanned(textiles, pan: .zero, zoom: 1) }
        drawImage(scene.filtered(.jpeg(quality: min(quality, 100))).image, 0, 0)
        drawLabel("quality \(min(quality, 100))")
    }

    // MARK: Datamosh

    /// A city panned and zoomed, through a datamosh: held blocks drag the old
    /// picture along the pan until they refresh.
    private func drawDatamosh(_ t: Double) {
        if mosh == nil || moshSeed != seed {
            mosh = makeSimField(.datamosh(amount: min(0.85, 0.55 * amount), seed: seed))
            moshSeed = seed
        }
        guard let mosh else { return }
        let a = t * .tau
        withField(mosh) {
            drawPanned(city, pan: Vector2(0.08 * sin(a), 0.04 * sin(2 * a)), zoom: 1.25 + 0.1 * cos(a))
        }
        drawImage(mosh.image, 0, 0)
    }

    // MARK: Lenses

    /// The rooftops through a tilt-shift lens, the focus line drifting up
    /// and down the town.
    private func drawTiltShift(_ t: Double) {
        let scene = makeRenderTarget()
        withTarget(scene) { drawPanned(city, pan: .zero, zoom: 1) }
        let focus = 0.55 + 0.12 * sin(t * .tau)
        let lens = Filter.tiltShift(focus: focus, angle: 0.08 * sin(t * .tau * 2),
                                    radius: 14 * amount)
        drawImage(scene.filtered(lens).filtered(.vibrance(amount: 0.4)).image, 0, 0)
    }

    /// The boats with a blur fading in from the middle down, its start
    /// sliding with the loop.
    private func drawProgressive(_ t: Double) {
        let scene = makeRenderTarget()
        withTarget(scene) { drawPanned(boats, pan: .zero, zoom: 1) }
        let start = 0.3 + 0.25 * (0.5 + 0.5 * sin(t * .tau))
        drawImage(scene.filtered(.progressiveBlur(start: start, end: 1, radius: 24 * amount)).image, 0, 0)
    }

    // MARK: Light leak

    /// A portrait with light leaking in from the right edge, breathing.
    private func drawLeak(_ t: Double) {
        let scene = makeRenderTarget()
        withTarget(scene) { drawPanned(portrait, pan: .zero, zoom: 1) }
        let anchor = Vector2(0.97, 0.35 + 0.1 * sin(t * .tau))
        drawImage(scene.filtered(.lightLeak(anchor: anchor, intensity: 0.4 * amount,
                                            phase: time, seed: seed)).image, 0, 0)
    }

    // MARK: Page peel

    /// A sheet of tiles peeling off the stone under it and laying back down.
    private func drawPeel(_ t: Double) {
        drawPanned(stone, pan: .zero, zoom: 1)
        let page = makeRenderTarget()
        withTarget(page) {
            background(.clear)
            drawPanned(talavera, pan: .zero, zoom: 1)
        }
        let progress = 0.5 - 0.5 * cos(t * .tau)
        drawImage(page.filtered(.pagePeel(amount: 0.4 * progress * min(amount, 2))).image, 0, 0)
    }

    // MARK: Scratches

    /// A headland in sepia under the scratches and grain of a worn print.
    private func drawScratches(_ t: Double) {
        let scene = makeRenderTarget()
        withTarget(scene) { drawPanned(headland, pan: Vector2(0, 0.004 * sin(time * 9)), zoom: 1.02) }
        drawImage(scene.filtered(.sepia(amount: 0.85)).filtered(.filmGrain(amount: 0.06)).image, 0, 0)
        let lines = generate(.scratches(count: 16, flicker: 0.6, phase: time, seed: seed))
        withState {
            blendMode(.screen)
            withState { tint(Color(white: 1, alpha: min(amount, 1))); drawImage(lines.image, 0, 0) }
        }
        let dirt = generate(.scratches(count: 6, thickness: 2, length: 0.25, wobble: 1,
                                       color: Color(white: 0, alpha: 0.6), phase: time, seed: seed + 50))
        drawImage(dirt.image, 0, 0)
    }

    // MARK: Label

    private func drawLabel(_ text: String) {
        withState {
            noStroke()
            fill(Color(white: 0, alpha: 0.55))
            drawRect(24, height - 76, 260, 52)
            fill(.white)
            textSize(26)
            textAlign(.left, .center)
            drawText(text, 40, height - 50)
        }
    }
}
