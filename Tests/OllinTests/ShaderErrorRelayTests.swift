import Testing
@testable import Ollin

/// The relay between the renderer's per-frame record of a user shader's compile
/// error and the host that shows it: a change is forwarded once, and after the
/// shaders are dropped to compile again the next answer is forwarded whatever it
/// is, since the host may have cleared its copy on the save. Without that, a
/// shader saved with the same mistake was never reported again.
///
/// Each answer is taken into a constant before it is checked: `#expect` holds
/// its argument in a closure, where a mutating call is not allowed.
struct ShaderErrorRelayTests {

    @Test func aChangeIsForwardedOnceAndAMatchIsNot() {
        var relay = ShaderErrorRelay()
        let quietStart = relay.shouldForward(nil)
        #expect(!quietStart, "nothing has changed before the first frame")
        let firstError = relay.shouldForward("line 3: planted")
        #expect(firstError)
        let sameError = relay.shouldForward("line 3: planted")
        #expect(!sameError, "the same error on the next frame is not news")
        let anotherError = relay.shouldForward("line 4: another")
        #expect(anotherError)
        let fixed = relay.shouldForward(nil)
        #expect(fixed, "every shader compiling again is news once")
        let stillFixed = relay.shouldForward(nil)
        #expect(!stillFixed)
        #expect(relay.forwarded == nil)
    }

    @Test func aRecompileForwardsTheNextAnswerWhateverItIs() {
        var relay = ShaderErrorRelay()
        let firstError = relay.shouldForward("line 3: planted")
        #expect(firstError)
        // The host clears its copy on the save, and the shader fails the same way.
        relay.invalidate()
        let sameErrorAgain = relay.shouldForward("line 3: planted")
        #expect(sameErrorAgain, "the same error after a recompile has to be said again")
        let andOnce = relay.shouldForward("line 3: planted")
        #expect(!andOnce, "and once is enough")
        // A recompile that fixes the shader says so once.
        relay.invalidate()
        let fixed = relay.shouldForward(nil)
        #expect(fixed)
        // A recompile of a working shader that still works says so again, so a
        // host that cleared nothing hears a nil it already holds, and no more.
        relay.invalidate()
        let stillWorks = relay.shouldForward(nil)
        #expect(stillWorks)
        let quiet = relay.shouldForward(nil)
        #expect(!quiet)
    }

    @Test func invalidationIsSpentByTheNextAnswer() {
        var relay = ShaderErrorRelay()
        relay.invalidate()
        relay.invalidate()
        #expect(relay.isStale)
        let spent = relay.shouldForward(nil)
        #expect(spent)
        #expect(!relay.isStale)
        let quiet = relay.shouldForward(nil)
        #expect(!quiet)
    }
}
