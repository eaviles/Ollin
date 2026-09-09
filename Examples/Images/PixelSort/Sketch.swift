import Ollin
import OllinSamplePhotos

/// A Guanajuato alley, melted by pixel sorting.
///
/// `pixelSorted` rearranges runs of an image's own pixels: nothing is
/// recolored, the pixels just change places, which is what gives the streaks
/// their molten reading. Runs are bounded by a brightness window, so the
/// deep doorways and the brightest cloud hold their ground while the walls
/// pour. Here the window's top edge breathes over the loop, so the melt
/// advances and recedes; hold the mouse to add the second, horizontal pass
/// (the classic treatment sorts both axes).
///
/// Sorting is CPU work at the image's own resolution, so the photograph is
/// scaled down once in `setup()` and the result drawn back up.
@main
final class PixelSort: Sketch {
    override var loopDuration: Double? { 12 }

    private var source = Image(width: 1, height: 1)

    override func setup() {
        seed(9)
        // Small on purpose: sorting runs on the picture's own pixels, and the
        // streaks read better drawn up from a small source than computed over a
        // large one.
        source = SamplePhoto.alley.load().resized(width: 320, height: 320)
    }

    override func draw() {
        background(.black)

        // The window's ceiling breathes: low, only faint streaks; high, the
        // whole sky and the sunlit walls pour. The floor sits above the darkest
        // doorways, so those hold and break the runs, which is where the jagged
        // teeth come from.
        let ceiling = 0.7 + 0.2 * sin(loopProgress(over: 12) * .tau)
        var sorted = source.pixelSorted(.vertical, threshold: 0.24 ... ceiling,
                                        reversed: true)
        if mouseIsPressed {
            sorted = sorted.pixelSorted(.horizontal, threshold: 0.24 ... ceiling)
        }
        drawImage(sorted, in: canvasRectangle)

        drawCaption("brightness-bounded runs, sorted; hold the mouse for the horizontal pass")
    }
}
