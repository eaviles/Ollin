// figure: frame=0 themed
//
// Guide figure (Chapter 17): a pattern field written by hand, next to the
// built-in it imitates. The gyroid really is one line of sin and cos products,
// sliced at a moving plane, and this is the evidence behind the chapter's claim
// that these fields are readable rather than magic.
import Ollin

final class HandRolledField: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }

    // The gyroid: a surface defined by one implicit equation. Reading it at a
    // fixed z is a flat slice through it, and the bands are where the equation
    // comes out near zero.
    let mine = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = (uv - 0.5) * 14.0;
        float z = info.time;
        float g = sin(p.x) * cos(p.y) + sin(p.y) * cos(z) + sin(z) * cos(p.x);
        float band = 1.0 - smoothstep(0.0, 0.55, abs(g));
        return float4(mix(float3(0.16, 0.19, 0.24), float3(0.91, 0.86, 0.78), band), 1.0);
    }
    """)

    override func draw() {
        background(paper)

        let tile = 396
        let panels: [(String, Image)] = [
            ("five lines of your own", generate(mine, width: tile, height: tile).image),
            (".gyroid(phase: time)",
             generate(.gyroid(phase: 1.2), width: tile, height: tile).image),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = 26 + Double(index) * (Double(tile) + 32)
            drawImage(panel.1, in: Rectangle(x: x, y: 22, width: Double(tile),
                                             height: Double(tile)))
            noStroke()
            fill(ink.withAlpha(0.62))
            textSize(17)
            textAlign(.center, .top)
            drawText(panel.0, x + Double(tile) / 2, 22 + Double(tile) + 10)
        }
    }
}
