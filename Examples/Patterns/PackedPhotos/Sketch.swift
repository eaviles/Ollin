import Ollin
import OllinSamplePhotos

/// A contact sheet of twenty photographs at their own proportions, packed
/// onto a page that keeps changing shape. Each photograph is a rectangle of
/// its own width and height, a few of them given more room than the rest,
/// and `packRectangles(_:in:padding:)` fits them all onto the page without
/// overlapping, a gap apart. The packer keeps every size as given, so the
/// sheet is first scaled: the largest scale at which every photograph still
/// fits is found by halving the gap between a scale that fits and one that
/// does not, twenty times over.
///
/// The page turns square, wide, tall, and back every few seconds, and the
/// photographs glide from where one page put them to where the next does. Hold the mouse down to drag the page's corner: the sheet is packed
/// again every frame as you go, which is what the packer's speed buys.
///
/// ```sh
/// swift run Example-Patterns-PackedPhotos --export-loop /tmp/packed-photos.mp4
/// ```
///
/// The photographs are the framework's bundled samples (`OllinSamplePhotos`),
/// each credited by its photographer in that library.
@main
final class PackedPhotos: Sketch {
    @Param(0 ... 40, icon: "square.split.2x2") var gap = 14.0

    private var photos: [Image] = []
    /// Each photograph's width and height, in units the scale multiplies.
    private var sizes: [Vector2] = []
    /// The shapes the page takes in turn, as width over height.
    private let shapes = [1.0, 1.55, 0.7, 1.2]
    private var pages: [Rectangle] = []
    private var layouts: [RectanglePacking] = []
    private var laidOutGap = -1.0
    private let period = 16.0
    override var loopDuration: Double? { period }

    /// The photographs given more room than the rest.
    private let featured: Set<String> = ["portrait", "marigolds", "boats", "dancer"]

    override func setup() {
        textFont(OutlineFont.system)
        for sample in SamplePhoto.all {
            let picture = sample.load()
            let long = Double(max(picture.width, picture.height))
            // A smaller copy is plenty for a sheet, and quicker to draw.
            photos.append(picture.resized(width: Int(Double(picture.width) / long * 480),
                                          height: Int(Double(picture.height) / long * 480)))
            let weight = featured.contains(sample.name) ? 1.5 : 1.0
            sizes.append(Vector2(Double(picture.width), Double(picture.height)) / long * weight)
        }
        let room = canvasRectangle.inset(by: .all(70 * scale))
        pages = shapes.map { Rectangle(fitting: Vector2($0, 1), in: room) }
    }

    /// The sheet at the largest scale at which every photograph fits `page`.
    private func sheet(on page: Rectangle) -> (packing: RectanglePacking, scale: Double) {
        let padding = gap * scale
        let area = sizes.reduce(0) { $0 + $1.x * $1.y }
        // No scale fits more photograph than the page has room for.
        var fits = 0.0, tooBig = (page.area / area).squareRoot()
        for _ in 0 ..< 20 {
            let trial = (fits + tooBig) / 2
            if packRectangles(sizes.map { $0 * trial }, in: page, padding: padding).unplaced.isEmpty {
                fits = trial
            } else {
                tooBig = trial
            }
        }
        return (packRectangles(sizes.map { $0 * fits }, in: page, padding: padding), fits)
    }

    private func mixed(_ a: Rectangle, _ b: Rectangle, _ t: Double) -> Rectangle {
        Rectangle(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t),
                  width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    override func draw() {
        background(Color(hex: 0x17181C))
        if gap != laidOutGap {
            layouts = pages.map { sheet(on: $0).packing }
            laidOutGap = gap
        }

        // Which page, held for most of its turn and then gliding to the next.
        let steps = Double(shapes.count)
        let t = loopProgress(over: period) * steps
        let k = Int(t) % shapes.count, next = (k + 1) % shapes.count
        let glide = smoothstep(0.65, 1, t - Double(Int(t)))

        let page: Rectangle
        var places: [Rectangle]
        let caption: RectanglePacking
        if mouseIsPressed {
            // The page's far corner follows the mouse, packed afresh.
            let corner = canvasRectangle.inset(by: .all(30 * scale)).topLeft
            page = Rectangle(x: corner.x, y: corner.y,
                             width: max(mouse.x - corner.x, 80 * scale), height: max(mouse.y - corner.y, 80 * scale))
            caption = sheet(on: page).packing
            places = caption.placed.map(\.rectangle)
        } else {
            page = mixed(pages[k], pages[next], glide)
            caption = glide < 0.5 ? layouts[k] : layouts[next]
            places = zip(layouts[k].placed, layouts[next].placed).map { mixed($0.rectangle, $1.rectangle, glide) }
        }

        noFill()
        stroke(Color(hex: 0xF4EAD6).withAlpha(0.18))
        strokeWeight(1.5 * scale)
        drawRect(page.inset(by: .all(-12 * scale)))
        noStroke()
        for (i, place) in places.enumerated() where i < photos.count {
            drawImage(photos[caption.placed[i].index], in: place)
        }

        fill(Color(hex: 0xF4EAD6).withAlpha(0.6))
        textAlign(.center, .bottom)
        textSize(20 * scale)
        drawText("\(caption.placed.count) photographs on \(Int((caption.occupancy * 100).rounded()))% of the page",
             width / 2, height - 14 * scale)
    }
}
