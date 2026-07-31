import Ollin

/// A ringing square plate stepping through its Chladni figures: sand gathers
/// along the still nodal lines while the mode numbers morph continuously, so
/// each figure holds a beat and then melts into the next. `look` flips between
/// the sand reading and the breathing wave itself; `grain` runs the lines from
/// smooth ink to loose speckle; `weight` is how wide the sand gathers. The
/// whole cycle loops:
///
/// ```sh
/// swift run Example-Patterns-Chladni --export-loop /tmp/chladni.gif
/// ```

enum ChladniLook: String, CaseIterable, ParamOption {
    case sand, wave

    var style: Generator.ChladniStyle {
        self == .sand ? .sand : .wave
    }
}

@main
final class Chladni_Example: Sketch {
    /// The tour of modes, every stop with m > n so the morph between stops
    /// never crosses the still m == n diagonal.
    private let modes: [(m: Double, n: Double)] = [(5, 2), (7, 3), (8, 5), (9, 2), (6, 1), (4, 1)]
    private let period = 30.0
    override var loopDuration: Double? { period }

    @Param(style: .segmented, icon: "waveform") var look: ChladniLook = .sand
    @Param(0.02 ... 0.4, icon: "lineweight") var weight = 0.12
    @Param(0 ... 1, icon: "circle.dotted") var grain = 0.6

    override func draw() {
        background(Color(hex: 0x14181F))
        let tour = loopProgress(over: period) * Double(modes.count)
        let stop = min(Int(tour), modes.count - 1)
        let next = (stop + 1) % modes.count
        let melt = Easing.easeInOutCubic((tour - Double(stop) - 0.55) / 0.45)
        let m = lerp(modes[stop].m, modes[next].m, melt)
        let n = lerp(modes[stop].n, modes[next].n, melt)

        let plate = generate(.chladni(m: m, n: n, style: look.style,
                                      weight: weight, grain: grain,
                                      phase: loopProgress(over: period) * .tau * 10))
        drawImage(plate.image, 0, 0)
    }
}
