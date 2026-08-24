import Ollin

/// A picture rebuilt out of a hundred smaller pictures.
///
/// Each cell of the target is averaged, and the picture from the library whose
/// own average is nearest goes there. Stand back and the cells add up to the
/// target; step forward and every cell is a picture of its own.
///
/// Both the target and the library are painted here rather than loaded, so the
/// sketch carries no assets: the target is three blobs of light drifting under a
/// sweeping band, and the library is a hundred small patterns spread over the
/// colors the target uses.
///
/// The averaging happens in linear light, which is the only way it can be right.
/// A cell of half black and half white is middle gray at 0.5 in linear light, and
/// averaging the sRGB numbers instead reads a quarter too dark, which a mosaic
/// shows as a picture that has lost its lights.
///
/// The tint travels over the loop, mixing each cell toward the color it stands
/// for. At zero the pictures are themselves and the mosaic is loose; further up
/// the target comes through. Hold the mouse to see the target on its own.
@main
final class PhotoMosaic_Example: Sketch {
    override var loopDuration: Double? { 14 }

    private let target = Image(width: 192, height: 192, color: .black)
    private var library: [Image] = []
    private var mosaic: PhotoMosaic?

    override func setup() {
        library = (0 ..< 100).map { tile(index: $0) }
        paint(phase: 0)
        mosaic = target.mosaic(of: library, columns: 32, rows: 32)
    }

    override func draw() {
        background(Color(hex: 0x07090E))
        let phase = loopProgress(over: 14) * .tau
        paint(phase: phase)
        // The target drifts, so the match is worked out again each frame. It is a
        // pass over a small picture, which is what keeps that affordable.
        mosaic = target.mosaic(of: library, columns: 32, rows: 32)

        let frame = Rectangle(fitting: Vector2(1, 1), in: bounds.inset(by: 70))
        if mouseIsPressed {
            drawImage(target, in: frame, fit: .cover)
            drawCaption("the target on its own, painted small and read cell by cell")
            return
        }

        guard let mosaic else { return }
        let tint = 0.5 - 0.5 * cos(phase)
        drawMosaic(mosaic, of: library, in: frame, tint: tint * 0.55)

        let used = mosaic.uses(of: library.count).filter { $0 > 0 }.count
        drawCaption("\(mosaic.tiles.count) cells from \(used) of \(library.count) pictures, "
            + "tinted \(Int((tint * 55).rounded()))% toward what they stand for")
    }

    /// One picture for the library: a colored ground with a mark on it, so a cell
    /// reads as a picture rather than as a swatch.
    private func tile(index: Int) -> Image {
        let side = 12
        let picture = Image(width: side, height: side, color: .black)
        let hue = Double(index % 10) / 10
        let level = 0.12 + Double(index / 10) / 9 * 1.0
        let ground = CosinePalette.rainbow.color(at: hue)
        let kind = index % 4
        for y in 0 ..< side {
            for x in 0 ..< side {
                let u = Double(x) / Double(side - 1), v = Double(y) / Double(side - 1)
                var lift = 0.0
                switch kind {
                case 0: lift = (u + v) < 0.7 ? 0.35 : 0            // a corner
                case 1: lift = abs(u - 0.5) < 0.18 ? 0.3 : 0       // a bar
                case 2: lift = (u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5) < 0.06 ? 0.4 : 0
                default: lift = ((x + y) % 4 < 2) ? 0.18 : 0       // a weave
                }
                picture[x, y] = Color(red: clamp(ground.red * level + lift, 0, 1),
                                      green: clamp(ground.green * level + lift, 0, 1),
                                      blue: clamp(ground.blue * level + lift, 0, 1))
            }
        }
        return picture
    }

    /// The target: three drifting blobs of light under a sweeping band, painted
    /// straight into the picture's pixels.
    private func paint(phase: Double) {
        let n = target.width
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1

                var field = glow(u, v, 0.5 * cos(phase), 0.5 * sin(phase), 7)
                field += 0.9 * glow(u, v, 0.36 * cos(-2 * phase + 1.3), 0.36 * sin(-2 * phase + 1.3), 11)
                field += 0.7 * glow(u, v, 0.62 * cos(3 * phase + 4), 0.62 * sin(3 * phase + 4), 16)

                let band = 0.5 + 0.5 * sin(2.4 * (u * cos(phase) + v * sin(phase)) - phase)
                let tone = clamp(1 - exp(-1.4 * field * (0.3 + 0.7 * band)), 0, 1)
                // A ground that shifts across the picture, so no two cells are the
                // same color. A target that is mostly one flat dark takes one
                // picture from the library and repeats it everywhere.
                let ground = 0.22 + 0.20 * (u * 0.5 + 0.5) + 0.14 * (v * 0.5 + 0.5)
                let hue = clamp(0.08 + (u * 0.5 + 0.5) * 0.35 + (v * 0.5 + 0.5) * 0.2
                    + tone * 0.3, 0, 1)
                let paint = CosinePalette.rainbow.color(at: hue)
                target[x, y] = Color(red: clamp(paint.red * (ground + tone * 0.85), 0, 1),
                                     green: clamp(paint.green * (ground + tone * 0.85), 0, 1),
                                     blue: clamp(paint.blue * (ground + tone * 0.85), 0, 1))
            }
        }
    }

    private func glow(_ u: Double, _ v: Double, _ cx: Double, _ cy: Double, _ sharp: Double) -> Double {
        let dx = u - cx, dy = v - cy
        return exp(-(dx * dx + dy * dy) * sharp)
    }
}
