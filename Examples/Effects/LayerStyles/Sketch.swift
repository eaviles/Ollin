import Ollin

/// **Layer styles**: an ordinary layer given an edge of its own. A word and two shapes
/// are drawn into one layer the ordinary way, and every style here reads that layer's
/// alpha, so it follows the letters as closely as the shapes:
///
/// - **outline**: a band of color along the edge, outside it, inside it, or centered.
/// - **shadows**: the layer's alpha blurred and moved, laid under it as a drop shadow
///   or held inside it as an inner shadow.
/// - **glows**: color fading with the distance from the edge, outward under the layer
///   or inward over it.
/// - **bevel**: the band in from the edge raised into a slope and lit.
///
/// The outline, the glows, and the bevel measure the layer's distance field; the
/// shadows blur it. Each is one filter, and they stack in the order they are chained:
/// `stacked` runs the bevel, the inner glow, the outline, and the drop shadow, so the
/// outline is beveled with nothing and the shadow falls from the outlined shape.
///
/// The light swings slowly around the upper left. The bevel's highlights travel with
/// it, and the shadows fall away from it, so the two agree about where the light is.
///
/// Try it: pick `outline` and push `outlineWidth` up until the letters merge, or pick `bevel`
/// and watch a narrow stroke of the `n` rise to a ridge where the band meets itself.
@main
final class LayerStyles_Example: Sketch {

    enum Look: String, CaseIterable, ParamOption { case stacked, outline, shadows, glows, bevel }

    @Param(style: .segmented, icon: "square.stack.3d.up") var look: Look = .stacked
    @Param(0 ... 24, icon: "circle.circle") var outlineWidth = 7.0
    @Param(0 ... 40, icon: "aqi.medium") var blur = 16.0
    @Param(2 ... 40, icon: "square.on.square.dashed") var bevelWidth = 18.0

    let paper = Color(hex: 0xD9D4CA)
    let font = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold

    /// One lap: the light swings once and the shapes drift once, so the motion comes home.
    override var loopDuration: Double? { 18 }

    override func draw() {
        background(paper)
        let turn = time / 18 * 2 * .pi
        let light = -.pi * 0.75 + sin(turn) * 0.8
        let away = Vector2(-cos(light), -sin(light))

        let layer = makeRenderTarget()
        withTarget(layer) {
            noStroke()
            fill(Color(hex: 0x2F6FD0))
            drawCircle(width * 0.3 + sin(turn) * 18, height * 0.33, 150)
            fill(Color(hex: 0xE9A23B))
            drawStar(center: Vector2(width * 0.72, height * 0.31 + cos(turn) * 16),
                     outerRadius: 150, innerRadius: 68, points: 6)
            fill(Color(hex: 0xC8452F))
            textFont(font)
            textSize(330)
            textAlign(.center, .center)
            drawText("Ollin", width * 0.5, height * 0.72)
        }

        let shadow = Filter.dropShadow(offset: away * (blur * 0.8 + 6), radius: blur,
                                       color: Color(white: 0, alpha: 0.45))
        let styled: RenderTarget
        switch look {
        case .stacked:
            styled = layer
                .filtered(.bevel(width: bevelWidth, angle: light))
                .filtered(.innerGlow(radius: bevelWidth * 0.8, color: Color(white: 1, alpha: 0.35)))
                .filtered(.outline(width: outlineWidth, color: Color(hex: 0x1C1A24)))
                .filtered(shadow)
        case .outline:
            styled = layer
                .filtered(.outline(width: outlineWidth * 0.5, color: Color(hex: 0x9C2F3C), align: .inside))
                .filtered(.outline(width: outlineWidth, color: Color(hex: 0x1C1A24)))
        case .shadows:
            styled = layer
                .filtered(.innerShadow(offset: away * (blur * 0.4 + 3), radius: blur * 0.5,
                                       color: Color(white: 0, alpha: 0.6)))
                .filtered(shadow)
        case .glows:
            styled = layer
                .filtered(.innerGlow(radius: blur, color: Color(hex: 0xFFF4C8)))
                .filtered(.outerGlow(radius: blur * 2.5, color: Color(hex: 0xFF4FA8)))
        case .bevel:
            styled = layer.filtered(.bevel(width: bevelWidth, profile: .chiseled, angle: light))
        }
        drawImage(styled.image, 0, 0)
    }
}
