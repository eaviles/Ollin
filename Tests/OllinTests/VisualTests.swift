import Testing
import COllinShaders
@testable import Ollin

/// CPU checks on the `Visual` chain compiler: the generated source must depend
/// only on the chain's *structure* (so the pipeline cache holds while values
/// animate), params must land in traversal order, and the layer routing must
/// dedupe and cap correctly.
@MainActor
struct VisualTests {

    private func chain(angle: Double, frequency: Double) -> Visual {
        .oscillator(frequency: frequency, speed: 1.2, colorShift: 0.3)
            .rotated(angle)
            .kaleidoscope(6)
            .displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.1)
            .saturation(1.3)
    }

    @Test func sameStructureSameSource() {
        let a = chain(angle: 0.4, frequency: 40).compile()
        let b = chain(angle: 0.4, frequency: 40).compile()
        #expect(a.source == b.source)
        #expect(a.params == b.params)
    }

    @Test func valueChangeKeepsSource() {
        let a = chain(angle: 0.4, frequency: 40).compile()
        let b = chain(angle: 1.7, frequency: 12).compile()
        #expect(a.source == b.source)     // animating a value can't recompile
        #expect(a.params != b.params)     // the values ride the uniform buffer
    }

    @Test func structureChangeChangesSource() {
        let a = chain(angle: 0.4, frequency: 40).compile()
        let b = chain(angle: 0.4, frequency: 40).inverted().compile()
        #expect(a.source != b.source)
    }

    @Test func paramsFollowTraversalOrder() {
        let program = Visual.oscillator(frequency: 40, speed: 2, colorShift: 0.1)
            .brightness(0.25)
            .compile()
        #expect(program.params == [40, 2, 0.1, 0.25])
        #expect(program.source.contains("param(info, 3)"))
        #expect(!program.paramsOverflowed)
    }

    @Test func blendModesAreStructural() {
        let base = Visual.oscillator().blended(with: .noise(), .add).compile()
        let other = Visual.oscillator().blended(with: .noise(), .multiply).compile()
        #expect(base.source != other.source)   // the mode is a code path, not a knob
    }

    @Test func layersDedupeByIdentity() {
        let target = RenderTarget(width: 64, height: 64, scale: 1, drawer: nil)
        let program = Visual.layer(target)
            .blended(with: .layer(target), .add)
            .compile()
        #expect(program.layers.count == 1)
        #expect(program.layersDropped == 0)
        #expect(program.source.contains("sample(info,"))
        #expect(!program.source.contains("sampleAux"))
    }

    @Test func secondLayerBindsAsAux() {
        let a = RenderTarget(width: 64, height: 64, scale: 1, drawer: nil)
        let b = RenderTarget(width: 64, height: 64, scale: 1, drawer: nil)
        let program = Visual.layer(a).masked(by: .layer(b)).compile()
        #expect(program.layers.count == 2)
        #expect(program.source.contains("sampleAux(info,"))
    }

    @Test func thirdLayerIsDropped() {
        let a = RenderTarget(width: 64, height: 64, scale: 1, drawer: nil)
        let b = RenderTarget(width: 64, height: 64, scale: 1, drawer: nil)
        let c = RenderTarget(width: 64, height: 64, scale: 1, drawer: nil)
        let program = Visual.layer(a)
            .blended(with: .layer(b), .add)
            .blended(with: .layer(c), .add)
            .compile()
        #expect(program.layers.count == 2)
        #expect(program.layersDropped == 1)
    }

    @Test func overflowBakesLiterals() {
        // Each brightness costs one slot; the sources cost a few more, so 80
        // adjustments sail past the buffer and the tail bakes into the source.
        var v = Visual.oscillator()
        for i in 0..<80 { v = v.brightness(Double(i) * 0.001) }
        let program = v.compile()
        #expect(program.paramsOverflowed)
        #expect(program.params.count == Int(OLLIN_SHADER_PARAM_COUNT))
    }
}
