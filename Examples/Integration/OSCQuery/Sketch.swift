import Foundation
import Ollin
import OllinOSC

/// The sketch's parameters, published for a control app to find. An
/// `OSCQueryServer` on the extension seam serves every `@Param` below as an
/// OSCQuery namespace: the tree as JSON over HTTP on port 9000, and the values
/// over OSC on UDP at the same number, both advertised on the local network
/// under the sketch's name. Open a control app that speaks OSCQuery on the
/// same Wi-Fi, pick this sketch from its list, and the controls build
/// themselves with the right ranges; move one and the ring answers.
///
/// With nothing but a browser, `http://<this-mac>.local:9000/` shows the tree,
/// and `curl` reads one node: `curl 'http://localhost:9000/Shape/radius?VALUE'`.
/// Any OSC sender works for the other direction, `/Shape/radius 240.0`.
///
/// The left column draws the namespace as served, so the picture and the
/// listing are the same thing seen twice.
@main
final class OSCQuery: Sketch {

    enum Style: String, CaseIterable, ParamOption { case petals, rings, spokes }

    @Param(20...400, group: "Shape") var radius = 180.0
    @Param(3...24, group: "Shape") var count = 9
    @Param(group: "Shape") var style = Style.petals

    @Param(0...3, group: "Motion") var speed = 0.5
    @Param(group: "Motion") var spin = true
    @Param(x: 0...1, y: 0...1, style: .pad, group: "Motion") var pivot = Vector2(0.62, 0.5)

    @Param(group: "Color") var tint = Color(red: 1.0, green: 0.62, blue: 0.24)
    @Param(count: 2...6, group: "Color") var inks = Palette(
        Color(red: 0.98, green: 0.36, blue: 0.30),
        Color(red: 0.99, green: 0.80, blue: 0.30),
        Color(red: 0.35, green: 0.72, blue: 0.95))

    let query = OSCQueryServer()

    override func setup() {
        extend(query)
    }

    override func draw() {
        background(Color(white: 0.06))
        drawFigure()
        drawNamespace()

        fill(Color(white: 1).withAlpha(0.55))
        textSize(20)
        textAlign(.center)
        drawText(query.url ?? "opening the namespace", width / 2, height - 36)
    }

    // MARK: The picture

    private func drawFigure() {
        let cx = pivot.x * width
        let cy = pivot.y * height
        let turn = spin ? time * speed : 0
        let colors = inks.colors
        noStroke()
        withState {
            translate(cx, cy)
            rotate(turn)
            for i in 0..<count {
                let angle = Double(i) / Double(count) * .tau
                let ink = colors[i % max(1, colors.count)].mixed(with: tint, 0.35)
                withState {
                    rotate(angle)
                    switch style {
                    case .petals:
                        fill(ink.withAlpha(0.75))
                        drawEllipse(radius * 0.55, 0, radius * 0.9, radius * 0.32)
                    case .rings:
                        noFill()
                        stroke(ink.withAlpha(0.85))
                        strokeWeight(3)
                        drawCircle(radius * 0.6, 0, radius * 0.4)
                    case .spokes:
                        stroke(ink)
                        strokeWeight(6)
                        strokeCap(.round)
                        drawLine(radius * 0.15, 0, radius, 0)
                    }
                }
            }
        }
        noStroke()
        fill(tint)
        drawCircle(cx, cy, 14)
    }

    // MARK: The namespace, as served

    private func drawNamespace() {
        let root = query.namespace()
        var y = 64.0
        textAlign(.left)
        textSize(22)
        fill(Color(white: 0.92))
        drawText(root.description ?? "", 40, y)
        y += 40
        textSize(16)
        for node in root.methods {
            let value = (node.value ?? []).map(describe).joined(separator: "  ")
            fill(Color(white: 0.75))
            drawText(node.fullPath, 40, y)
            fill(tint.withAlpha(0.9))
            drawText(node.type ?? "", 300, y)
            fill(Color(white: 0.55))
            drawText(value, 340, y)
            y += 26
        }
    }

    private func describe(_ value: OSCQueryValue) -> String {
        switch value {
        case .number(let n): return n == n.rounded() ? "\(Int(n))" : String(format: "%.2f", n)
        case .text(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }
}
