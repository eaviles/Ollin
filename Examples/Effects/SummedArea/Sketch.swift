import Ollin

/// **Summed-area tables**: one table that turns "the average of the square around this
/// pixel" into four lookups, however big the square is.
///
/// The table holds, at every texel, the sum of everything above and to the left of it.
/// Subtract the two edges, add the corner back, and you have the sum over any rectangle
/// at all for the same price. Two filters ride on that here:
///
/// - **`.boxBlur`** averages the square around each pixel, and a radius of 400 costs what
///   a radius of 4 costs. Drag `blur` to the top and notice that nothing slows down.
/// - **`.adaptiveThreshold`** cuts each pixel against the average of its *own*
///   neighborhood instead of against one number for the whole page.
///
/// The page below is lit by a lamp that keeps moving, which is what the second filter is
/// for. Watch the three readings as the light sweeps:
///
/// - **page**: the marks as they are, one corner always in shadow.
/// - **global**: a plain `.threshold`. There is no single number that works, so the cut
///   eats the shadowed end of the page and then the lit one as the lamp travels.
/// - **local**: `.adaptiveThreshold`. Every pixel is compared with its surroundings, so
///   the lamp stops mattering and the marks come back whole and stay still.
///
/// Try it: pull `window` down small and watch thick strokes hollow out, because the
/// middle of a stroke stops being able to see any paper.
@main
final class SummedArea_Example: Sketch {

    enum Reading: String, CaseIterable, ParamOption { case together, page, global, local, blur }

    @Param(style: .segmented, icon: "rectangle.split.3x1") var reading: Reading = .together
    @Param(24 ... 400, icon: "square.dashed") var window = 150.0
    @Param(0 ... 0.4, icon: "slider.horizontal.below.rectangle") var bias = 0.15
    @Param(0 ... 400, icon: "drop") var blur = 30.0
    @Param(0 ... 1, icon: "circle.lefthalf.filled") var cut = 0.5

    let paper = Color(hex: 0xF2ECE0)
    let ink = Color(hex: 0x1B2028)

    override func draw() {
        background(Color(hex: 0x0E1216))

        let page = makeRenderTarget()
        withTarget(page) { drawPage() }

        switch reading {
        case .page:
            drawImage(page.image, 0, 0)
        case .global:
            drawImage(page.filtered(.threshold(cut, softness: 0.01)).image, 0, 0)
        case .local:
            drawImage(page.filtered(.adaptiveThreshold(window: window, bias: bias)).image, 0, 0)
        case .blur:
            drawImage(page.filtered(.boxBlur(radius: blur)).image, 0, 0)
        case .together:
            // The three readings wiped into columns of the one page. The marks cover the
            // whole sheet on purpose: every column then holds ink, paper, and whatever
            // the lamp is doing to that part of it, so the columns really are comparable.
            let third = width / 3
            let readings = [page,
                            page.filtered(.threshold(cut, softness: 0.01)),
                            page.filtered(.adaptiveThreshold(window: window, bias: bias))]
            for (i, layer) in readings.enumerated() {
                let column = Rectangle(x: Double(i) * third, y: 0, width: third, height: height)
                withClip(column) { drawImage(layer.image, 0, 0) }
            }
            stroke(Color(hex: 0x0E1216)); strokeWeight(3)
            drawLine(third, 0, third, height)
            drawLine(third * 2, 0, third * 2, height)
            noStroke()
            labels(["page", "global", "local"], every: third)
        }
    }

    /// A page of marks under a lamp that keeps moving: the marks first, then the light
    /// multiplied over them. Multiplying is what makes this an illumination rather than a
    /// wash, and an illumination is exactly what the local cut is built to see through.
    private func drawPage() {
        background(paper)
        noStroke()
        fill(ink)
        textSize(38)
        // Lines that run the whole width, so no column of the comparison is left
        // holding nothing but paper.
        let lines = ["the average of a square costs four lookups",
                     "whatever the size of the square, and that",
                     "one fact is the whole of the idea. build a",
                     "table of running sums once, and every box",
                     "average after it is two subtractions and",
                     "an addition. a blur that reaches across the",
                     "canvas costs what a blur of four pixels does,",
                     "and a threshold can afford to ask each pixel",
                     "what its own neighborhood looks like."]
        for (i, line) in lines.enumerated() {
            drawText(line, width * 0.05, 130 + Double(i) * 66)
        }
        // Thick marks as well as thin: a stroke wide enough to hold its own middle is
        // what shows a window that has been set too small.
        stroke(ink)
        strokeWeight(20)
        noFill()
        drawLine(width * 0.05, height * 0.78, width * 0.95, height * 0.78)
        strokeWeight(9)
        for i in 0 ..< 5 {
            drawCircle(width * (0.12 + Double(i) * 0.19), height * 0.9, 52)
        }
        noStroke()
        fill(ink)
        for i in 0 ..< 6 {
            drawRect(width * (0.06 + Double(i) * 0.155), height * 0.06, 92, 26)
        }

        // The lamp. A bright pool that travels, falling away toward the far side, and
        // multiplied over everything already drawn, because that is what light does to a
        // page and it is exactly what the local cut is built to see through.
        blendMode(.multiply)
        let lamp = Vector2(width * (0.5 + cos(time * 0.4) * 0.44),
                           height * (0.5 + sin(time * 0.27) * 0.36))
        fill(Gradient.radial(center: lamp, radius: width * 1.15,
                             Ramp([Color(white: 1.0), Color(white: 0.72), Color(white: 0.3)])))
        drawRect(0, 0, width, height)
        blendMode(.normal)
    }

    /// One caption under each column, on its own dark plate. The plate is not decoration:
    /// the right-hand column is a sheet of white paper, and white lettering on it would
    /// not be there at all.
    private func labels(_ names: [String], every third: Double) {
        textSize(30)
        textAlign(.center)
        for (i, name) in names.enumerated() {
            let center = (Double(i) + 0.5) * third
            fill(Color(hex: 0x0E1216, alpha: 0.82))
            drawRect(center - 84, height - 62, 168, 44)
            fill(Color(white: 1))
            drawText(name, center, height - 30)
        }
        textAlign(.left)
    }
}
