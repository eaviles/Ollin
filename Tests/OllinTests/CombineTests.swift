import Testing
@testable import Ollin

/// The call-site identity a `Combine` carries for ops that keep per-op state across
/// frames. Screen-space reflections' temporal history is keyed on it, so an SSR op
/// recorded conditionally on some frames can't shift a *different* op onto its
/// history slot; the key is the call site, not a frame-wide ordinal. No GPU, so it
/// runs in CI.
@Suite
struct CombineTests {

    @Test func ssrCarriesItsCallSite() {
        let op = Combine.screenSpaceReflections()
        #expect(!op.sourceID.isEmpty)
        #expect(op.sourceID.contains("CombineTests.swift"))
    }

    @Test func distinctCallSitesGetDistinctIdentities() {
        let a = Combine.screenSpaceReflections()
        let b = Combine.screenSpaceReflections()
        #expect(a.sourceID != b.sourceID)      // different lines → different identities
    }

    @Test func oneCallSiteIsStableAcrossFrames() {
        func perFrame() -> Combine { .screenSpaceReflections() }
        #expect(perFrame().sourceID == perFrame().sourceID)   // re-recorded each frame → same key
    }

    @Test func statelessOpsCarryNone() {
        #expect(Combine.mask().sourceID.isEmpty)
        #expect(Combine.mix().sourceID.isEmpty)
        #expect(Combine.defocus().sourceID.isEmpty)
    }
}
