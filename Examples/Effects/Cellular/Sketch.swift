import Ollin

/// Worley cellular noise as a generator: space divided into organic cells by
/// hashed feature points, filled straight on the GPU by `generate(.cellular)`.
/// The `look` knob flips between the three readings of the same field:
/// `cells` (dark cores brightening toward the walls), `borders` (thin cracks
/// tracing the walls), and `mosaic` (flat stained-glass panes). The feature
/// points wander on their own small orbits, periodic over one lap, so the
/// whole field crawls, reforms, and loops seamlessly:
///
/// ```sh
/// swift run Example-Effects-Cellular --export-loop /tmp/cellular.gif
/// ```

enum CellularLook: String, CaseIterable, ParamOption {
    case cells, borders, mosaic

    var style: Generator.CellularStyle {
        switch self {
        case .cells: return .cells
        case .borders: return .borders
        case .mosaic: return .mosaic
        }
    }
}

@main
final class Cellular_Example: Sketch {
    private let period = 12.0
    override var loopDuration: Double? { period }

    @Param(style: .segmented, icon: "circle.hexagongrid") var look: CellularLook = .cells
    @Param(2 ... 32, icon: "squareshape.split.3x3") var cells = 9.0
    @Param(0 ... 1, icon: "wind") var jitter = 1.0

    override func draw() {
        background(Color(hex: 0x101820))
        let field = generate(.cellular(scale: cells, jitter: jitter, style: look.style,
                                       foreground: Color(hex: 0xF2E8DC),
                                       background: Color(hex: 0x101820),
                                       phase: loopProgress(over: period) * .tau))
        drawImage(field.image, 0, 0)
    }
}
