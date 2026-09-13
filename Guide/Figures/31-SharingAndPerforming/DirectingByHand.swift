// figure: frame=0 themed
//
// Guide diagram (Chapter 31): the timeline panel, annotated. A stylized
// OllinLive inspector on the left, with the diamond every parameter row
// carries: hollow where nothing drives the parameter yet, filled where a track
// does, and the function mark where a rule typed in the row drives it. The
// panel on the right: the transport and its readout, the ruler with a loop
// region and the playhead, one lane per track drawing what the parameter will
// do (a number as its curve, a color as the blend, a switch as steps), the
// selected key with its two Bezier handles, and the footer naming that key's
// moment and curve beside the file the lanes are saved to. Drawn with Ollin
// rather than captured, so it renders in both themes from one source.
import Ollin
import OllinDiagram

final class DirectingByHand: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let handleColor = Color(hex: 0xE8C64A)
    let span = 4.0                       // seconds across the ruler
    let playhead = 1.6

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let panel = Rectangle(x: 268, y: 100, width: 584, height: 340)
        let insp = Rectangle(x: 28, y: 100, width: 214, height: 294)
        let laneLeft = panel.x + 112, laneRight = panel.x + panel.width - 14
        func tx(_ t: Double) -> Double { laneLeft + t / span * (laneRight - laneLeft) }

        // ---- The inspector, four rows and their diamonds.
        card(insp)
        drawText("Parameters", insp.x + 14, insp.y + 16, size: 12, color: theme.muted,
                 align: .left, .middle)
        let rowTop = insp.y + 34
        sliderRow("Radius", y: rowTop, value: 0.45, in: insp, mark: .filled)
        sliderRow("Hue", y: rowTop + 58, value: 0.6, in: insp, mark: .hollow)
        colorRow("Ground", y: rowTop + 116, color: Color(hex: 0xF3EFE6), in: insp, mark: .filled)
        switchRow("Lit", y: rowTop + 174, rule: "time % 6 < 3", in: insp)

        // ---- The panel.
        card(panel)

        // The transport row and its readout.
        let transportY = panel.y + 22
        transport(at: panel.x + 18, y: transportY)
        drawText("frame 96", panel.x + panel.width - 118, transportY, size: 10.5,
                 color: theme.muted, align: .right, .middle)
        drawText("00:01.60", panel.x + panel.width - 14, transportY, size: 21,
                 color: theme.ink, align: .right, .middle)
        hairline(panel, at: panel.y + 42)

        // The ruler: a loop region, the ticks, the playhead.
        let ruler = Rectangle(x: laneLeft, y: panel.y + 44, width: laneRight - laneLeft, height: 26)
        noStroke()
        fill(theme.accent(0.14))
        drawRect(tx(1), ruler.y, tx(3) - tx(1), ruler.height)
        stroke(theme.accent)
        strokeWeight(1)
        for edge in [1.0, 3.0] { drawLine(tx(edge), ruler.y, tx(edge), ruler.y + ruler.height) }
        for s in 0...4 {
            let t = Double(s)
            stroke(theme.muted)
            drawLine(tx(t), ruler.y + ruler.height - 9, tx(t), ruler.y + ruler.height)
            if t + 0.5 < span {
                stroke(theme.border)
                drawLine(tx(t + 0.5), ruler.y + ruler.height - 5, tx(t + 0.5), ruler.y + ruler.height)
            }
            noStroke()
            let last = s == 4
            drawText("\(s)s", last ? tx(t) - 3 : tx(t) + 3, ruler.y + ruler.height - 11,
                     size: 9, color: theme.muted, align: last ? .right : .left, .bottom)
        }
        hairline(panel, at: ruler.y + ruler.height + 2)

        // The lanes, one per track.
        let laneH = 64.0
        let laneTop = ruler.y + ruler.height + 4
        let lanes = ["Radius", "Ground", "Lit"]
        for (i, name) in lanes.enumerated() {
            let y = laneTop + Double(i) * (laneH + 2)
            laneLabel(name, at: Vector2(panel.x + 16, y + laneH / 2))
            if i > 0 { hairline(panel, at: y - 1) }
        }
        let radiusLane = Rectangle(x: laneLeft, y: laneTop, width: laneRight - laneLeft, height: laneH)
        let groundLane = Rectangle(x: laneLeft, y: laneTop + laneH + 2, width: laneRight - laneLeft, height: laneH)
        let litLane = Rectangle(x: laneLeft, y: laneTop + 2 * (laneH + 2), width: laneRight - laneLeft, height: laneH)
        numberLane(radiusLane, tx: tx)
        colorLane(groundLane, tx: tx)
        switchLane(litLane, tx: tx)

        // The playhead, through the ruler and every lane, capped on the ruler.
        let ph = tx(playhead)
        stroke(theme.accent)
        strokeWeight(1)
        drawLine(ph, ruler.y, ph, litLane.y + litLane.height)
        noStroke()
        fill(theme.accent)
        drawRect(ph - 4.5, ruler.y, 9, 9, cornerRadius: 2)

        // The footer: a track to add, the selected key, the file.
        let footerY = panel.y + panel.height - 22
        hairline(panel, at: panel.y + panel.height - 44)
        chipButton("+ Track ▾", at: Vector2(panel.x + 14, footerY))
        drawText("2.00s", panel.x + 214, footerY, size: 11, color: theme.muted, align: .left, .middle)
        chipButton("Bezier ▾", at: Vector2(panel.x + 254, footerY))
        chipButton("Delete", at: Vector2(panel.x + 326, footerY))
        drawText("Sketch.automation.json · saved", panel.x + panel.width - 14, footerY,
                 size: 11, color: theme.muted, align: .right, .middle)

        // ---- Callouts.
        textSize(14)
        // The leaders land beside a mark rather than on it, so the diamond and
        // the function mark stay visible under their own callouts.
        callout("click the diamond, and a key lands", "at the playhead with the row's value",
                at: Vector2(28, 22), to: Vector2(insp.x + insp.width - 12, rowTop + 6), alignRight: false)
        callout("a rule wears the function mark,", "and its switch takes no hand",
                at: Vector2(28, 470), to: Vector2(insp.x + insp.width - 12, rowTop + 200), alignRight: false)
        callout("click a key: the footer names its moment", "and its curve; Bezier grows two handles",
                at: Vector2(852, 470), to: Vector2(panel.x + 300, footerY + 12), alignRight: true)

        // The ruler callout stands over the playhead, so its leader is short
        // and crosses nothing but the empty middle of the transport row.
        noStroke()
        drawText("scrub the ruler; the picture", ph, 24, size: 14, color: theme.ink, align: .center, .middle)
        drawText("follows the playhead", ph, 46, size: 14, color: theme.ink, align: .center, .middle)
        stroke(theme.accent)
        strokeWeight(2)
        drawLine(ph, 62, ph, ruler.y - 2)
        noStroke()
        fill(theme.accent)
        drawCircle(ph, ruler.y - 2, 4)

        diagramCaption("the lanes are the sketch's own automation, and every export plays them",
                       at: 548, theme: theme)
    }

    // MARK: - Lanes

    private func ease(_ u: Double) -> Double { u * u * (3 - 2 * u) }

    /// A number lane: the curve the keys make, the keys as diamonds, and the
    /// selected key's Bezier handles.
    private func numberLane(_ lane: Rectangle, tx: (Double) -> Double) {
        let pad = 9.0
        func y(_ v: Double) -> Double {
            lane.y + lane.height - pad - (v - 40) / (320 - 40) * (lane.height - 2 * pad)
        }
        func value(_ t: Double) -> Double {
            t <= 2 ? 40 + (320 - 40) * ease(t / 2) : 320 - (320 - 40) * ease((t - 2) / 2)
        }
        stroke(theme.accent(0.45))
        strokeWeight(1.5)
        var last = Vector2(tx(0), y(value(0)))
        for i in 1...160 {
            let t = Double(i) / 160 * span
            let p = Vector2(tx(t), y(value(t)))
            drawLine(last, p)
            last = p
        }
        // The selected key's handles: a stem out of it, and one into the next.
        let selected = Vector2(tx(2), y(320)), next = Vector2(tx(4), y(40))
        let out = Vector2(tx(2.55), y(320)), into = Vector2(tx(3.45), y(40))
        stroke(handleColor.withAlpha(0.9))
        strokeWeight(1)
        drawLine(selected, out)
        drawLine(next, into)
        noStroke()
        fill(handleColor)
        drawCircle(out.x, out.y, 2.5)
        drawCircle(into.x, into.y, 2.5)
        key(at: Vector2(tx(0), y(40)), selected: false)
        key(at: selected, selected: true)
        key(at: next, selected: false)
    }

    /// A color lane: the blend itself, as the band the panel draws, sampled
    /// along the lane, and a key where each color was placed.
    private func colorLane(_ lane: Rectangle, tx: (Double) -> Double) {
        let cream = Color(hex: 0xF3EFE6), navy = Color(hex: 0x1C2A5A)
        let bandH = 10.0, y = lane.y + (lane.height - bandH) / 2
        func color(_ t: Double) -> Color {
            t <= 2.5 ? cream.mixed(with: navy, ease(t / 2.5)) : navy.mixed(with: cream, ease((t - 2.5) / 1.5))
        }
        noStroke()
        var x = lane.x
        while x < lane.x + lane.width {
            let t = (x + 2 - lane.x) / lane.width * span
            fill(color(t))
            drawRect(x, y, 4.5, bandH)
            x += 4
        }
        for t in [0.0, 2.5, 4.0] { key(at: Vector2(tx(t), y + bandH / 2), selected: false) }
    }

    /// A switch lane: two levels and a step between them.
    private func switchLane(_ lane: Rectangle, tx: (Double) -> Double) {
        let low = lane.y + lane.height - 9, high = lane.y + 9
        stroke(theme.accent(0.45))
        strokeWeight(1.5)
        drawLine(tx(0), low, tx(3), low)
        drawLine(tx(3), low, tx(3), high)
        drawLine(tx(3), high, tx(4), high)
        key(at: Vector2(tx(0), low), selected: false)
        key(at: Vector2(tx(3), high), selected: false)
    }

    private func key(at p: Vector2, selected: Bool) {
        if selected { diamond(at: p, radius: 6.5, fill: theme.paper, stroke: nil) }
        diamond(at: p, radius: 4.5, fill: theme.accent, stroke: theme.accent)
    }

    private func diamond(at p: Vector2, radius: Double, fill color: Color, stroke edge: Color?) {
        withState {
            translate(p)
            rotate(.pi / 4)
            fill(color)
            if let edge {
                stroke(edge)
                strokeWeight(1)
            } else {
                noStroke()
            }
            let r = radius / 1.414
            drawRect(-r, -r, 2 * r, 2 * r)
        }
    }

    private func laneLabel(_ name: String, at p: Vector2) {
        diamond(at: Vector2(p.x + 4, p.y), radius: 4, fill: theme.accent, stroke: nil)
        noStroke()
        drawText(name, p.x + 16, p.y, size: 12, color: theme.ink, align: .left, .middle)
    }

    // MARK: - The inspector rows

    private enum Mark { case hollow, filled }

    private func rowMark(_ mark: Mark, at p: Vector2) {
        switch mark {
        case .hollow: diamond(at: p, radius: 5, fill: theme.paper, stroke: theme.muted)
        case .filled: diamond(at: p, radius: 5, fill: theme.accent, stroke: theme.accent)
        }
    }

    private func rowName(_ name: String, y: Double, in insp: Rectangle) {
        noStroke()
        drawText(name, insp.x + 14, y + 16, size: 13, color: theme.ink, align: .left, .middle)
    }

    private func sliderRow(_ name: String, y: Double, value: Double, in insp: Rectangle, mark: Mark) {
        rowName(name, y: y, in: insp)
        rowMark(mark, at: Vector2(insp.x + insp.width - 24, y + 16))
        let x0 = insp.x + 14, x1 = insp.x + insp.width - 44
        stroke(theme.border)
        strokeWeight(3)
        drawLine(x0, y + 40, x1, y + 40)
        stroke(theme.accent)
        drawLine(x0, y + 40, x0 + (x1 - x0) * value, y + 40)
        fill(theme.paper)
        stroke(theme.border)
        strokeWeight(1)
        drawCircle(x0 + (x1 - x0) * value, y + 40, 6)
    }

    private func colorRow(_ name: String, y: Double, color: Color, in insp: Rectangle, mark: Mark) {
        rowName(name, y: y, in: insp)
        rowMark(mark, at: Vector2(insp.x + insp.width - 24, y + 16))
        fill(color)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(insp.x + 14, y + 32, 64, 16, cornerRadius: 4)
    }

    private func switchRow(_ name: String, y: Double, rule: String, in insp: Rectangle) {
        rowName(name, y: y, in: insp)
        noStroke()
        drawText("ƒ", insp.x + insp.width - 24, y + 16, size: 14, color: theme.accent,
                 align: .center, .middle)
        // The switch, dimmed: the rule drives it, so it takes no hand.
        fill(theme.ink(0.18))
        drawRect(insp.x + 14, y + 31, 34, 18, cornerRadius: 9)
        fill(theme.paper)
        drawCircle(insp.x + 14 + 9, y + 40, 7)
        // The field under the row, holding the rule as typed.
        fill(theme.paper)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(insp.x + 14, y + 56, insp.width - 28, 22, cornerRadius: 5)
        noStroke()
        drawText(rule, insp.x + 22, y + 67, size: 11.5, color: theme.ink, align: .left, .middle)
    }

    // MARK: - Chrome

    private func card(_ rect: Rectangle) {
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(rect, cornerRadius: 10)
    }

    private func hairline(_ panel: Rectangle, at y: Double) {
        stroke(theme.border)
        strokeWeight(1)
        drawLine(panel.x, y, panel.x + panel.width, y)
    }

    private func chipButton(_ text: String, at p: Vector2) {
        textSize(11)
        let w = textWidth(text) + 16
        fill(theme.paper)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(p.x, p.y - 11, w, 22, cornerRadius: 5)
        noStroke()
        drawText(text, p.x + 8, p.y, size: 11, color: theme.ink, align: .left, .middle)
    }

    /// The transport: to the start, back a frame, play, forward a frame, to
    /// the end, and the loop button lit because a region is set.
    private func transport(at x: Double, y: Double) {
        noStroke()
        fill(theme.ink)
        drawRect(x, y - 6, 2, 12)
        drawTriangle(x + 12, y - 6, x + 12, y + 6, x + 3, y)
        let x1 = x + 28
        drawTriangle(x1 + 9, y - 6, x1 + 9, y + 6, x1, y)
        drawRect(x1 + 10, y - 6, 2, 12)
        let x2 = x + 56
        fill(theme.accent(0.18))
        drawRect(x2 - 3, y - 11, 24, 22, cornerRadius: 5)
        fill(theme.accent)
        drawTriangle(x2 + 4, y - 6, x2 + 4, y + 6, x2 + 15, y)
        let x3 = x + 92
        fill(theme.ink)
        drawRect(x3, y - 6, 2, 12)
        drawTriangle(x3 + 3, y - 6, x3 + 3, y + 6, x3 + 12, y)
        let x4 = x + 120
        drawTriangle(x4, y - 6, x4, y + 6, x4 + 9, y)
        drawRect(x4 + 10, y - 6, 2, 12)
        let x5 = x + 150
        noFill()
        stroke(theme.accent)
        strokeWeight(1.5)
        drawRect(x5, y - 5, 16, 10, cornerRadius: 3)
        noStroke()
        fill(theme.accent)
        drawTriangle(x5 + 12, y - 9, x5 + 12, y - 1, x5 + 18, y - 5)
        drawTriangle(x5 + 4, y + 1, x5 + 4, y + 9, x5 - 2, y + 5)
    }

    private func callout(_ line1: String, _ line2: String, at p: Vector2, to target: Vector2,
                         alignRight: Bool) {
        noStroke()
        fill(theme.ink)
        textAlign(alignRight ? .right : .left, .top)
        drawText(line1, p.x, p.y)
        drawText(line2, p.x, p.y + 22)
        // Start the leader at the text edge facing the target, so it never
        // crosses its own words.
        let widest = max(textWidth(line1), textWidth(line2))
        let anchor = Vector2(alignRight ? p.x - widest - 10 : p.x + widest + 10, p.y + 22)
        stroke(theme.accent)
        strokeWeight(2)
        drawLine(anchor, target)
        noStroke()
        fill(theme.accent)
        drawCircle(target.x, target.y, 4)
    }
}
