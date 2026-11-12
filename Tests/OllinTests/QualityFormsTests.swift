import Testing
@testable import Ollin

/// Every quality setter on a sketch hands its value to the drawer's own
/// setting and adds nothing: `shadowQuality(.performance)` leaves the drawer
/// holding that tier, `raymarchSteps(77)` an exact count of 77, and the call
/// that resets a dial puts the standing default back. The renderer reads
/// these settings from the drawer, so a setter that wrote the wrong one (the
/// shadow dial into the reflection's, a count into a tier) would change a
/// picture nobody was looking at. Each value asked for is checked against the
/// default first, so a setter that did nothing cannot pass.
@Suite
@MainActor
struct QualityFormsTests {

    /// What the drawer holds for one dial, so one table reads them all.
    enum Setting: Equatable, Sendable {
        case tier(RenderQuality)
        case shadow(ShadowQualitySetting)
        case march(RaymarchQualitySetting)
        case air(VolumetricQualitySetting)
        case count(Int)
        case amount(Double)
        case flag(Bool)
        case lens(focusRange: Double, maxBlur: Double, quality: RenderQuality)
        case unset
    }

    /// One dial: the public setter with a value that is not the default, the
    /// drawer's setting it should land in, and what that setting should then
    /// hold. `reset` is the call that puts the default back: the same call
    /// with no argument where it has that form, and its off form otherwise.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        let set: @MainActor @Sendable (Sketch) -> Void
        let read: @MainActor @Sendable (Sketch) -> Setting
        let expected: Setting
        var reset: (@MainActor @Sendable (Sketch) -> Void)? = nil
        var testDescription: String { name }
    }

    nonisolated static let pairs: [Pair] = [
        Pair(name: "global illumination quality", set: { $0.globalIlluminationQuality(.performance) },
             read: { .tier($0.drawer.giQualitySetting) }, expected: .tier(.performance),
             reset: { $0.globalIlluminationQuality() }),
        Pair(name: "caustics quality", set: { $0.causticsQuality(.detail) },
             read: { .tier($0.drawer.causticsQualitySetting) }, expected: .tier(.detail),
             reset: { $0.causticsQuality() }),
        Pair(name: "shadow quality", set: { $0.shadowQuality(.performance) },
             read: { .shadow($0.drawer.shadowQualitySetting) }, expected: .shadow(.tier(.performance)),
             reset: { $0.shadowQuality() }),
        Pair(name: "shadow samples", set: { $0.shadowSamples(13) },
             read: { .shadow($0.drawer.shadowQualitySetting) }, expected: .shadow(.absolute(13))),
        Pair(name: "shadow softness", set: { $0.shadowSoftness(0.85) },
             read: { .amount($0.drawer.shadowSoftnessAmount) }, expected: .amount(0.85),
             reset: { $0.shadowSoftness() }),
        Pair(name: "reflection quality", set: { $0.reflectionQuality(.performance) },
             read: { .tier($0.drawer.reflectionQualitySetting) }, expected: .tier(.performance),
             reset: { $0.reflectionQuality() }),
        Pair(name: "reflection bounces", set: { $0.reflectionBounces(5) },
             read: { .count($0.drawer.reflectionBouncesSetting) }, expected: .count(5),
             reset: { $0.reflectionBounces() }),
        Pair(name: "glossy reflections", set: { $0.glossyReflections() },
             read: { .flag($0.drawer.glossyReflectionsEnabled) }, expected: .flag(true),
             reset: { $0.glossyReflections(false) }),
        Pair(name: "raymarch quality", set: { $0.raymarchQuality(.detail) },
             read: { .march($0.drawer.raymarchQualitySetting) }, expected: .march(.tier(.detail)),
             reset: { $0.raymarchQuality() }),
        Pair(name: "raymarch steps", set: { $0.raymarchSteps(77) },
             read: { .march($0.drawer.raymarchQualitySetting) }, expected: .march(.absolute(77))),
        Pair(name: "raymarch resolution", set: { $0.raymarchResolution(0.75) },
             read: { .march($0.drawer.raymarchQualitySetting) }, expected: .march(.resolution(0.75))),
        Pair(name: "volumetric quality", set: { $0.volumetricQuality(.performance) },
             read: { .air($0.drawer.volumetricQualitySetting) }, expected: .air(.tier(.performance)),
             reset: { $0.volumetricQuality() }),
        Pair(name: "volumetric steps", set: { $0.volumetricSteps(48) },
             read: { .air($0.drawer.volumetricQualitySetting) }, expected: .air(.absolute(48))),
        // Two features take their tier as an argument of the call that turns
        // them on, and it lands beside the feature's own setting.
        Pair(name: "temporal upscaling's tier", set: { $0.temporalUpscaling(.performance) },
             read: { .tier($0.drawer.temporalUpscalingQuality) }, expected: .tier(.performance),
             reset: { $0.temporalUpscaling() }),
        Pair(name: "depth of field's tier",
             set: { $0.depthOfField(focusRange: 0.4, maxBlur: 21, quality: .performance) },
             read: { sketch in
                 guard let lens = sketch.drawer.depthOfFieldSetting else { return .unset }
                 return .lens(focusRange: lens.focusRange, maxBlur: lens.maxBlur, quality: lens.quality)
             },
             expected: .lens(focusRange: 0.4, maxBlur: 21, quality: .performance),
             reset: { $0.noDepthOfField() }),
    ]

    @Test(arguments: pairs)
    func theSetterReachesTheDrawersSetting(_ pair: Pair) {
        let sketch = Sketch()
        let standing = pair.read(sketch)
        #expect(standing != pair.expected, "the value asked for is the default, so the setter proved nothing")

        pair.set(sketch)
        #expect(pair.read(sketch) == pair.expected)

        if let reset = pair.reset {
            reset(sketch)
            #expect(pair.read(sketch) == standing, "the reset call puts the default back")
        }
    }

    /// The exact counts are held inside the range each one documents, at the
    /// sketch's setter as at the drawer's: a count past either end lands on it.
    @Test func anExactCountIsHeldInsideItsRange() {
        let sketch = Sketch()
        sketch.shadowSamples(900)
        #expect(sketch.drawer.shadowQualitySetting == .absolute(64))
        sketch.shadowSamples(0)
        #expect(sketch.drawer.shadowQualitySetting == .absolute(1))
        sketch.raymarchSteps(3)
        #expect(sketch.drawer.raymarchQualitySetting == .absolute(16))
        sketch.raymarchSteps(4000)
        #expect(sketch.drawer.raymarchQualitySetting == .absolute(512))
        sketch.raymarchResolution(7)
        #expect(sketch.drawer.raymarchQualitySetting == .resolution(1))
        sketch.raymarchResolution(0.01)
        #expect(sketch.drawer.raymarchQualitySetting == .resolution(0.1))
        sketch.volumetricSteps(2)
        #expect(sketch.drawer.volumetricQualitySetting == .absolute(8))
        sketch.volumetricSteps(999)
        #expect(sketch.drawer.volumetricQualitySetting == .absolute(128))
        sketch.shadowSoftness(3)
        #expect(sketch.drawer.shadowSoftnessAmount == 1)
    }
}
