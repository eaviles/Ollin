// figure: frame=0 themed
//
// Guide figure (Chapter 16): one page under a light that falls across it, cut
// two ways. The same photograph, one number for the whole page against each
// pixel's own neighborhood. The picture is a bundled sample, a book held open
// with dappled shadow over half of it, which is the case the filter exists for.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class LocalAverages: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var labelInk: Color { theme.ink(0.62) }

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        // A detail rather than the whole page: at this tile size the type has
        // to stay readable, or the two cuts read as abstract shapes instead of
        // as text lost and text recovered.
        photograph = SamplePhoto.page.load().cropped(x: 380, y: 420, width: 620, height: 620)
    }

    override func draw() {
        background(paper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["a page with shadow falling over it", "one number for all of it",
                      "each pixel against its own patch"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            let page = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(page) {
                drawImage(photograph, in: Rectangle(x: 0, y: 0, width: tile, height: tile),
                          fit: .cover)
            }

            switch index {
            case 0:
                drawImage(page.image, in: frame)
            case 1:
                drawImage(page.filtered(.threshold(0.3)).image, in: frame)
            default:
                drawImage(page.filtered(.adaptiveThreshold(window: 90)).image, in: frame)
            }

            fill(labelInk)
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
