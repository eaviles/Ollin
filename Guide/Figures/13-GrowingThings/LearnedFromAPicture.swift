// figure: frame=0 themed
//
// Guide figure (Chapter 13): Wave Function Collapse's overlapping model.
// Left, the sample: a small picture drawn by hand. Right, a much larger
// texture built out of the square patches that picture contains, so that
// every overlap agrees. Nothing in the result is new up close; everything
// about it is new at a distance.
import Ollin
import OllinDiagram

final class LearnedFromAPicture: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    // The sample and its output are depicted content, identical in both themes.
    let wall = Color(hex: 0x2B2B2B)
    let room = Color(hex: 0xF7F5F0)

    static let rows = [
        "................",
        "..######..####..",
        "..#....#..#..#..",
        "..#....####..#..",
        "..#..........#..",
        "..#..####....#..",
        "..####..#..###..",
        "........#..#....",
        "..#######..#....",
        "..#.....#..#....",
        "..#.....####....",
        "..#######.......",
        "................",
        "..####..######..",
        "..#..#..#....#..",
        "..#..####....#..",
    ]

    override func draw() {
        background(paper)
        seed(4)

        let sample = Image(width: 16, height: 16)
        for (y, row) in Self.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                sample[x, y] = ch == "#" ? wall : room
            }
        }

        let sampleBox = Rectangle(x: 40, y: 78, width: 240, height: 240)
        drawPixels(sample, in: sampleBox)

        if let texture = wfc(from: sample, width: 48, height: 30, patternSize: 3) {
            drawPixels(texture, in: Rectangle(x: 336, y: 78, width: 504, height: 240))
        }

        noStroke()
        fill(ink)
        textSize(15)
        drawText("the sample, 16 by 16", at: Vector2(40, 60))
        drawText("48 by 30, built from its squares", at: Vector2(336, 60))
        fill(theme.ink(0.55))
        textSize(13)
        drawText("every 3 by 3 square here is one the sample already contained",
                 at: Vector2(336, 348))
    }

    /// A rectangle per pixel, so the marks stay hard-edged when enlarged.
    func drawPixels(_ image: Image, in box: Rectangle) {
        let cell = min(box.width / Double(image.width), box.height / Double(image.height))
        let x0 = box.x + (box.width - cell * Double(image.width)) / 2
        let y0 = box.y + (box.height - cell * Double(image.height)) / 2
        noStroke()
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                fill(image[x, y])
                drawRect(corner: Vector2(x0 + Double(x) * cell, y0 + Double(y) * cell),
                         width: cell, height: cell)
            }
        }
    }
}
