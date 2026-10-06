// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the regions a drawing encloses. Left, three
// circles and a line, every patch they wall off found and tinted on its own.
// Middle, a ring of circles around bare page: the patch they ring is a region
// too, and a circle drawn inside another is a region and a hole. Right, two
// strokes over a circle: the one that crosses it cuts it in two, and the one
// whose end hangs loose inside walls nothing off. Nothing here uses
// randomness.
import Ollin
import OllinDiagram

final class EnclosedRegions: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }
    var tints: [Color] { [theme.accent(0.22), theme.ink(0.1), theme.accent(0.5), theme.ink(0.22), theme.accent(0.1)] }

    override func draw() {
        background(paper)
        patches(at: Vector2(30, 70))
        ringed(at: Vector2(390, 70))
        looseEnds(at: Vector2(750, 70))
    }

    func caption(_ title: String, _ note: String) {
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.left, .middle)
        drawText(title, 0, -34)
        fill(ink.withAlpha(0.7))
        textSize(15)
        textAlign(.left, .top)
        drawText(note, 0, 392)
    }

    /// Every outline inked over the fills.
    func inkOutlines(_ outlines: [Contour]) {
        noFill()
        stroke(ink)
        strokeWeight(2.2)
        strokeJoin(.round)
        for outline in outlines { drawPolyline(outline.points, closed: outline.isClosed) }
    }

    /// Three circles and a line: every patch its own shape.
    func patches(at origin: Vector2) {
        withState {
            translate(origin)
            caption("every patch its own shape", "regions(enclosedBy:), one fill each")
            let outlines = [Circle(center: Vector2(120, 150), radius: 95).contour(),
                            Circle(center: Vector2(205, 165), radius: 85).contour(),
                            Circle(center: Vector2(160, 245), radius: 90).contour(),
                            Contour([Vector2(10, 300), Vector2(300, 60)], closed: false)]
            let found = regions(enclosedBy: outlines)
            noStroke()
            for (i, region) in found.enumerated() {
                fill(tints[i % tints.count])
                drawShape(region)
            }
            inkOutlines(outlines)
            fill(ink.withAlpha(0.8))
            noStroke()
            textSize(14)
            textAlign(.left, .top)
            drawText("\(found.count) regions from 4 outlines", 0, 350)
        }
    }

    /// A ring of circles: the page they ring is a patch, a circle inside
    /// another is a hole.
    func ringed(at origin: Vector2) {
        withState {
            translate(origin)
            caption("the page it rings is a patch too", "a hole is a region of its own")
            let center = Vector2(160, 180)
            var outlines = (0 ..< 5).map { i in
                Circle(center: center + Vector2(angle: Double(i) / 5 * .tau - .tau / 4, length: 96),
                       radius: 62).contour()
            }
            outlines.append(Circle(center: center + Vector2(angle: -.tau / 4, length: 96) + Vector2(14, 8),
                                   radius: 20).contour())
            let found = regions(enclosedBy: outlines)
            noStroke()
            for region in found {
                let isGap = region.contains(center)
                let isHole = region.contours.count > 1
                fill(isGap ? accent : isHole ? theme.accent(0.22) : theme.ink(0.08))
                drawShape(region)
            }
            inkOutlines(outlines)
            fill(ink.withAlpha(0.8))
            noStroke()
            textSize(14)
            textAlign(.left, .top)
            drawText("\(found.count) regions; the middle is bare page, ringed", 0, 350)
        }
    }

    /// A stroke through a circle cuts it; a stroke ending inside does not.
    func looseEnds(at origin: Vector2) {
        withState {
            translate(origin)
            caption("a loose end walls nothing off", "one stroke cuts, the other is dropped")
            let disc = Circle(center: Vector2(160, 190), radius: 110).contour()
            let through = Contour([Vector2(20, 120), Vector2(300, 260)], closed: false)
            let hanging = Contour([Vector2(300, 90), Vector2(170, 180)], closed: false)
            let found = regions(enclosedBy: [disc, through, hanging])
            noStroke()
            for (i, region) in found.enumerated() {
                fill(tints[i % tints.count])
                drawShape(region)
            }
            inkOutlines([disc, through])
            noFill()
            stroke(accent)
            strokeWeight(2.2)
            strokeCap(.round)
            drawPolyline(hanging.points)
            fill(accent)
            noStroke()
            drawCircle(center: hanging.points[1], radius: 4.5)
            fill(ink.withAlpha(0.8))
            textSize(14)
            textAlign(.left, .top)
            drawText("\(found.count) regions: the loose stroke is left out", 0, 350)
        }
    }
}
