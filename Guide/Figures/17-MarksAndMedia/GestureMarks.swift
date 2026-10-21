// figure: frame=0 probe themed
//
// Guide diagram (Chapter 17): one gesture, tapering from heavy to light, made
// into sixteen families of marks by GestureMark. The outlines, the rows across
// the width, the sprouts, the ribbon resampled, and the lines around the path,
// each panel the same path and the same seed.
import Ollin
import OllinDiagram

final class GestureMarks: Sketch {
    override var canvasSize: CanvasSize { .size(880, 820) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    let red = Color(red: 0.77, green: 0.28, blue: 0.23)
    let gold = Color(red: 0.88, green: 0.64, blue: 0.23)
    let teal = Color(red: 0.18, green: 0.48, blue: 0.47)
    let rose = Color(red: 0.88, green: 0.48, blue: 0.56)

    override func draw() {
        background(paper)
        textSize(16)
        let palette = [ink, red, gold, teal, rose]

        let titles = [".cloud", ".chain", ".spikes", ".dashes", ".dots", ".strips", ".feather", ".leaves",
                      ".fringe", ".pixels", ".facets", ".lanes", ".spiral", ".strands", ".fragments", ".wiggle"]

        for i in 0 ..< 16 {
            let r = Rectangle(x: 36 + Double(i % 4) * 206, y: 30 + Double(i / 4) * 198,
                              width: 188, height: 150)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            let gesture = self.gesture(in: r)
            withState {
                strokeCap(.round)
                strokeJoin(.round)
                switch i {
                case 0: fillOne(gesture.cloud(seed: 4).shape, ink)
                case 1: fill(gesture.chain(seed: 4), palette) { 3 * ($0.index % 2) }
                case 2: fillOne(gesture.spikes(seed: 4).shape, red)
                case 3: fill(gesture.dashes(rows: 3, seed: 4), palette) { $0.row }
                case 4: fill(gesture.dots(rows: 3, seed: 4), palette) { $0.row + $0.index }
                case 5: fill(gesture.strips(rows: 3, seed: 4), palette) { $0.row + 2 * $0.index }
                case 6: stroke(gesture.feather(seed: 4), palette, weight: 1) { $0.index / 5 }
                case 7: fill(gesture.leaves(seed: 4), palette) { 3 - 2 * $0.row }
                case 8: stroke(gesture.fringe(seed: 4), palette, weight: 0.8) { 1 + $0.row }
                case 9: fill(gesture.pixels(cell: 5, seed: 4), palette) { 2 * $0.row }
                case 10:
                    noStroke()
                    for piece in gesture.facets(seed: 4) {
                        let fade: Double = 0.14 * Double(piece.row) + 0.06 * Double(piece.index % 3)
                        fill(teal.mixed(with: paper, fade))
                        drawShape(piece.shape)
                    }
                case 11: fill(gesture.lanes(count: 4, seed: 4), palette) { $0.row }
                case 12: stroke(gesture.spiral(cycle: 0.4), palette, weight: 1.2) { _ in 0 }
                case 13: stroke(gesture.strands(count: 5, seed: 4), palette, weight: 1.2) { $0.row }
                case 14: stroke(gesture.fragments(density: 1.4, seed: 4), palette, weight: 1.4) { $0.index }
                default: stroke(gesture.wiggle(wavelength: 0.8, amplitude: 0.8), palette, weight: 2) { _ in 1 }
                }
            }

            noStroke()
            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.y + r.height + 10)
        }
    }

    /// One gesture inside a panel: an S-curve that starts heavy and lifts.
    private func gesture(in r: Rectangle) -> GestureMark {
        let count = 90
        let points = (0 ... count).map { k -> Vector2 in
            let t = Double(k) / Double(count)
            return Vector2(r.x + 26 + t * (r.width - 52), r.center.y + sin(t * .pi * 2) * (r.height * 0.22))
        }
        let widths = (0 ... count).map { k in 34 * (1 - 0.6 * Double(k) / Double(count)) }
        return GestureMark(points: points, widths: widths)
    }

    private func fillOne(_ shape: Shape, _ color: Color) {
        noStroke()
        fill(color)
        drawShape(shape)
    }

    private func fill(_ pieces: [GestureMark.Piece], _ palette: [Color], _ pick: (GestureMark.Piece) -> Int) {
        noStroke()
        for piece in pieces {
            fill(palette[pick(piece) % palette.count])
            drawShape(piece.shape)
        }
    }

    private func stroke(_ pieces: [GestureMark.Piece], _ palette: [Color], weight: Double,
                        _ pick: (GestureMark.Piece) -> Int) {
        noFill()
        strokeWeight(weight)
        for piece in pieces {
            stroke(palette[pick(piece) % palette.count])
            drawPolyline(piece.contour.points)
        }
    }
}
