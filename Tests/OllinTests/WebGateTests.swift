import Foundation
import OllinWebGate
import Testing

/// The browser gate's own budget. A test names what its page costs at a desk,
/// which is the only number it can honestly know; the machine reading it is
/// measured instead, by the probe the gate already runs before any test does.
@Suite
struct WebGateTests {

    /// A machine with a GPU launches the browser in about a second, and its
    /// pages keep the budget they were written with.
    @Test
    func aFastMachineKeepsTheBudgetTheTestNamed() {
        #expect(HeadlessBrowser.budget(90, launch: 0.9) == 90)
        #expect(HeadlessBrowser.budget(90, launch: 2.3) == 90)
    }

    /// A machine with no GPU rasterizes every WebGL pixel on the CPU, so the
    /// launch it measures is the warning that its pages will be slow too.
    @Test
    func aSlowMachineRaisesIt() {
        #expect(HeadlessBrowser.budget(90, launch: 30) == 240)
        #expect(HeadlessBrowser.budget(90, launch: 60) == 480)
    }

    /// The ceiling is what keeps the timeout doing its job, which is to fail a
    /// hang rather than park a test for as long as the machine is strange.
    @Test
    func theCeilingHolds() {
        #expect(HeadlessBrowser.budget(90, launch: 500) == 600)
        #expect(HeadlessBrowser.budget(90, launch: 10_000) == 600)
    }

    /// A page that already asks for longer than the floor keeps its own ask.
    @Test
    func aLongerAskWins() {
        #expect(HeadlessBrowser.budget(300, launch: 0.9) == 300)
        #expect(HeadlessBrowser.budget(300, launch: 50) == 400)
    }
}
