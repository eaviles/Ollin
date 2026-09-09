import Ollin
import OllinSamplePhotos

/// A picture rebuilt out of a hundred smaller pictures.
///
/// Each cell of the target is averaged, and the picture from the library whose
/// own average is nearest goes there. Stand back and the cells add up to the
/// target; step forward and every cell is a picture of its own.
///
/// The target is one of the bundled sample photographs, a young woman in a lace
/// headdress, read at 192 pixels. The library is cut from all four sample
/// photographs: each one at 60 pixels, sliced five by five into twenty-five
/// tiles, so every cell of the mosaic is a real piece of a real picture.
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

    private var target = Image(width: 1, height: 1)
    private var library: [Image] = []
    private var mosaic: PhotoMosaic?

    override func setup() {
        target = SamplePhoto.portrait.load().resized(width: 192, height: 192)
        library = SamplePhoto.all.flatMap { tiles(of: $0.load(), across: 5, side: 12) }
        // The target holds still, so the match is worked out once.
        mosaic = target.mosaic(of: library, columns: 32, rows: 32)
    }

    override func draw() {
        background(Color(hex: 0x07090E))
        let phase = loopProgress(over: 14) * .tau

        let frame = Rectangle(fitting: Vector2(1, 1), in: bounds.inset(by: 70))
        if mouseIsPressed {
            drawImage(target, in: frame, fit: .cover)
            drawCaption("the target on its own, read cell by cell")
            return
        }

        guard let mosaic else { return }
        let tint = 0.5 - 0.5 * cos(phase)
        drawMosaic(mosaic, of: library, in: frame, tint: tint * 0.55)

        let used = mosaic.uses(of: library.count).filter { $0 > 0 }.count
        drawCaption("\(mosaic.tiles.count) cells from \(used) of \(library.count) pictures, "
            + "tinted \(Int((tint * 55).rounded()))% toward what they stand for")
    }

    /// The library: `picture` shrunk to `across` tiles a side, then sliced into
    /// `across` by `across` pieces of `side` pixels each. Every piece is a
    /// real part of a real photograph, which is what makes a cell read as a
    /// picture rather than as a swatch.
    private func tiles(of picture: Image, across: Int, side: Int) -> [Image] {
        let small = picture.resized(width: across * side, height: across * side)
        var pieces: [Image] = []
        for row in 0 ..< across {
            for column in 0 ..< across {
                let piece = Image(width: side, height: side, color: .black)
                for y in 0 ..< side {
                    for x in 0 ..< side {
                        piece[x, y] = small[column * side + x, row * side + y]
                    }
                }
                pieces.append(piece)
            }
        }
        return pieces
    }
}
