import Ollin
import OllinSamplePhotos

/// A small picture drawn big, cell by cell.
///
/// A photograph is dithered to black and white at a quarter of the canvas's size,
/// then drawn at four canvas pixels a cell. Drawn the ordinary way the GPU
/// blends each cell into its neighbors, and the hard black-and-white grain
/// turns into a gray blur. `imageSampling(.nearest)` reads every pixel as a
/// hard square instead, so the cells read as cells, and no enlarged copy is
/// ever made: the 270 by 270 picture is the one texture, read differently.
///
/// The split follows the pointer: left of it the default `.linear`, right of
/// it `.nearest`. The same picture, one state call apart. The choice is
/// drawing state beside `tint`, so `withState { }` puts it back, which is how
/// the two halves share one `draw()`.
@main
final class PixelArt: Sketch {
    private var cells: Image?
    private let cellSize = 4.0

    override func setup() {
        // A quarter of the canvas, dithered to black and white once: per-pixel
        // CPU work belongs in setup(), and the drawing afterwards costs one quad.
        let small = Int((shortSide / cellSize).rounded())
        let source = SamplePhoto.portrait.load().resized(width: small, height: small)
        cells = source.dithered(.atkinson, to: Palette([.black, .white]))
    }

    override func draw() {
        background(Color(hex: 0x14161C))
        guard let cells else { return }
        let side = Double(cells.width) * cellSize
        let x = (width - side) / 2, y = (height - side) / 2
        let frame = Rectangle(x: x, y: y, width: side, height: side)

        // The pointer places the split; at rest it sits a little right of center.
        let split = mouseIsPressed || mouseX > 0 ? min(max(mouseX, x), x + side) : x + side * 0.55

        // Left of the split: the default, each cell blended into the next.
        withClip(Rectangle(x: x, y: y, width: split - x, height: side)) {
            drawImage(cells, in: frame)
        }
        // Right of it: the same picture read as hard cells.
        withClip(Rectangle(x: split, y: y, width: x + side - split, height: side)) {
            withState {
                imageSampling(.nearest)
                drawImage(cells, in: frame)
            }
        }

        stroke(Color(hex: 0xE8B04B))
        strokeWeight(2)
        drawLine(split, y - 12, split, y + side + 12)
        drawCaption("left: .linear (blended)  ·  right: imageSampling(.nearest)  ·  move the pointer")
    }
}
