import Testing
@testable import Ollin

/// Behavior of `@Param`'s optional smoothing: an un-smoothed param snaps, `.eased`
/// glides to the target over its duration, `.smoothed` denoises toward it, and
/// `set(_:)` jumps with no glide. The per-frame `advance(by:)` is what the sketch
/// runs each frame; here we drive it directly. No GPU, so it runs in CI.
@Suite
struct ParamTests {

    @Test func unsmoothedSnapsAndDoesNotDrift() {
        let p = Param(wrappedValue: 10.0, 0...100)
        p.wrappedValue = 80
        #expect(p.wrappedValue == 80)        // immediate
        p.advance(by: 1.0 / 60)
        #expect(p.wrappedValue == 80)        // advance is a no-op
    }

    @Test func valueClampsToRange() {
        let p = Param(wrappedValue: 0.0, 0...100)
        p.wrappedValue = 999
        #expect(p.wrappedValue == 100)
        p.wrappedValue = -50
        #expect(p.wrappedValue == 0)
    }

    @Test func easedGlidesOverDuration() {
        let p = Param(wrappedValue: 0, 0...100, smoothing: .eased(duration: 1, curve: .linear))
        p.wrappedValue = 100                 // retarget; doesn't jump
        #expect(p.wrappedValue == 0)
        p.advance(by: 0.5)
        #expect(abs(p.wrappedValue - 50) < 0.001)   // halfway, linear
        p.advance(by: 0.5)
        #expect(abs(p.wrappedValue - 100) < 0.001)  // arrived
        p.advance(by: 0.5)
        #expect(abs(p.wrappedValue - 100) < 0.001)  // stays put
    }

    @Test func smoothedConvergesTowardTarget() {
        let p = Param(wrappedValue: 0, 0...100, smoothing: .smoothed)
        p.wrappedValue = 100
        #expect(p.wrappedValue == 0)         // not yet advanced

        p.advance(by: 1.0 / 60)
        let afterOne = p.wrappedValue
        #expect(afterOne > 0 && afterOne < 100)   // moving, not jumped

        for _ in 0..<600 { p.advance(by: 1.0 / 60) }
        #expect(abs(p.wrappedValue - 100) < 1)    // settled near the target
    }

    @Test func setJumpsWithNoGlide() {
        let p = Param(wrappedValue: 0, 0...100, smoothing: .eased(duration: 1, curve: .linear))
        p.wrappedValue = 100
        p.advance(by: 0.5)                   // mid-glide
        #expect(p.wrappedValue > 0 && p.wrappedValue < 100)

        p.set(40)
        #expect(p.wrappedValue == 40)        // instant
        p.advance(by: 0.5)
        #expect(p.wrappedValue == 40)        // and at rest
    }

    // MARK: The typed family

    @Test func doubleStepSnapsWrites() {
        let p = Param(wrappedValue: 0.6, 0...1, step: 0.25)
        #expect(p.wrappedValue == 0.5)       // the default snaps too
        p.wrappedValue = 0.9
        #expect(p.wrappedValue == 1.0)
        guard case .slider(let control) = p.control else {
            Issue.record("Double should present a slider")
            return
        }
        #expect(control.step == 0.25)
    }

    @Test func intClampsAndSteps() {
        let p = Param(wrappedValue: 5, 1...12)
        p.wrappedValue = 99
        #expect(p.wrappedValue == 12)
        guard case .stepper(let control) = p.control else {
            Issue.record("Int should present a stepper")
            return
        }
        #expect(control.range == 1...12 && control.step == 1)
        control.set(3)
        #expect(p.wrappedValue == 3)
        #expect(p.stored == .number(3))
        p.restore(.number(7))
        #expect(p.wrappedValue == 7)
    }

    @Test func boolTogglesAndRoundTrips() {
        let p = Param(wrappedValue: true)
        guard case .toggle(let control) = p.control else {
            Issue.record("Bool should present a toggle")
            return
        }
        control.set(false)
        #expect(p.wrappedValue == false)
        #expect(p.stored == .boolean(false))
        p.restore(.boolean(true))
        #expect(p.wrappedValue == true)
    }

    @Test func colorRoundTrips() {
        let p = Param(wrappedValue: Color.purple)
        guard case .colorWell(let control) = p.control else {
            Issue.record("Color should present a color well")
            return
        }
        control.set(.orange)
        #expect(p.wrappedValue == .orange)
        let stored = p.stored
        let q = Param(wrappedValue: Color.white)
        q.restore(stored)
        #expect(q.wrappedValue == .orange)
    }

    enum Style: String, CaseIterable, ParamOption { case dots, rings, meshLines }

    @Test func enumPresentsAMenuAndKeysOnCaseNames() {
        let p = Param(wrappedValue: Style.dots)
        guard case .menu(let control) = p.control else {
            Issue.record("A ParamOption enum should present a menu")
            return
        }
        #expect(control.options == ["Dots", "Rings", "Mesh Lines"])   // humanized case names
        control.set(2)
        #expect(p.wrappedValue == .meshLines)
        #expect(p.stored == .option("meshLines"))
        p.restore(.option("rings"))
        #expect(p.wrappedValue == .rings)
        p.restore(.option("gone"))            // an unknown case name is ignored
        #expect(p.wrappedValue == .rings)
    }

    @Test func richStylesRideTheControls() {
        let pad = Param(wrappedValue: Vector2(0, 0), x: 0...1, y: 0...1, style: .pad)
        guard case .vector(let vector) = pad.control else { return }
        #expect(vector.style == .pad)

        let pair = Param(wrappedValue: 1.0...2.0, in: 0...10, style: .field)
        guard case .range(let fieldPair) = pair.control else { return }
        #expect(fieldPair.style == .field)
        let sliderPair = Param(wrappedValue: 1.0...2.0, in: 0...10)
        guard case .range(let defaulted) = sliderPair.control else { return }
        #expect(defaulted.style == .slider)   // the two-thumb track is the default

        let segmented = Param(wrappedValue: Style.dots, style: .segmented)
        guard case .menu(let menu) = segmented.control else { return }
        #expect(menu.style == .segmented)
    }

    @Test func vectorClampsPerAxisAndRoundTrips() {
        let p = Param(wrappedValue: Vector2(540, 540), x: 0...1080, y: 0...400)
        p.wrappedValue = Vector2(2000, -50)
        #expect(p.wrappedValue == Vector2(1080, 0))   // clamped per axis
        guard case .vector(let control) = p.control else {
            Issue.record("Vector2 should present paired x/y fields")
            return
        }
        #expect(control.xRange == 0...1080 && control.yRange == 0...400)
        control.set(Vector2(100, 200))
        #expect(p.wrappedValue == Vector2(100, 200))
        #expect(p.stored == .vector(x: 100, y: 200))
        p.restore(.vector(x: 300, y: 100))
        #expect(p.wrappedValue == Vector2(300, 100))
    }

    @Test func vector3ClampsPerAxisAndRoundTrips() {
        let p = Param(wrappedValue: Vector3(0, 0, 0), x: -1...1, y: -1...1, z: 0...10)
        p.wrappedValue = Vector3(5, -5, -2)
        #expect(p.wrappedValue == Vector3(1, -1, 0))
        guard case .vector3(let control) = p.control else {
            Issue.record("Vector3 should present x/y/z fields")
            return
        }
        #expect(control.zRange == 0...10)
        control.set(Vector3(0.5, -0.5, 3))
        #expect(p.stored == .vector3(x: 0.5, y: -0.5, z: 3))
        p.restore(.vector3(x: 0, y: 1, z: 9))
        #expect(p.wrappedValue == Vector3(0, 1, 9))
    }

    @Test func fieldStyleRidesTheControl() {
        let p = Param(wrappedValue: 2000.0, 0...100_000, style: .field)
        guard case .slider(let control) = p.control else {
            Issue.record("a field-style Double is still the slider control kind")
            return
        }
        #expect(control.style == .field)
        let q = Param(wrappedValue: 1.0, 0...4)
        guard case .slider(let defaulted) = q.control else { return }
        #expect(defaulted.style == .slider)
    }

    @Test func builtInEnumsAreOptions() {
        let p = Param(wrappedValue: BlendMode.normal)
        guard case .menu(let control) = p.control else {
            Issue.record("BlendMode should present a menu")
            return
        }
        #expect(control.options.count == BlendMode.allCases.count)
        p.restore(.option("multiply"))
        #expect(p.wrappedValue == .multiply)
    }

    @Test func rectangleClampsPerFieldAndRoundTrips() {
        let p = Param(wrappedValue: Rectangle(x: 100, y: 100, width: 200, height: 200),
                      x: 0...1080, y: 0...1080, width: 10...500, height: 10...500)
        p.wrappedValue = Rectangle(x: -5, y: 2000, width: 900, height: 0)
        #expect(p.wrappedValue == Rectangle(x: 0, y: 1080, width: 500, height: 10))
        guard case .rectangle(let control) = p.control else {
            Issue.record("Rectangle should present x/y/w/h fields")
            return
        }
        #expect(control.widthRange == 10...500)
        p.restore(.rect(x: 10, y: 20, width: 30, height: 40))
        #expect(p.wrappedValue == Rectangle(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func insetsClampEachEdgeAndRoundTrip() {
        let p = Param(wrappedValue: Insets.all(20), 0...100)
        p.wrappedValue = Insets(top: -5, right: 500, bottom: 50, left: 0)
        #expect(p.wrappedValue == Insets(top: 0, right: 100, bottom: 50, left: 0))
        guard case .insets(let control) = p.control else {
            Issue.record("Insets should present t/r/b/l fields")
            return
        }
        #expect(control.edgeRange == 0...100)
        p.restore(.insets(top: 1, right: 2, bottom: 3, left: 4))
        #expect(p.wrappedValue == Insets(top: 1, right: 2, bottom: 3, left: 4))
    }

    @Test func rangeStaysOrderedInsideOuter() {
        let p = Param(wrappedValue: 5.0...20.0, in: 0...100)
        p.wrappedValue = 50...200
        #expect(p.wrappedValue == 50...100)      // upper clamped to outer
        // A default entirely outside the outer bounds pins to an ordered pair.
        let q = Param(wrappedValue: 60.0...90.0, in: 0...50)
        #expect(q.wrappedValue == 50...50)
        guard case .range(let control) = p.control else {
            Issue.record("ClosedRange should present min/max fields")
            return
        }
        #expect(control.outer == 0...100)
        p.restore(.range(lower: 80, upper: 30))  // an unordered payload is ignored
        #expect(p.wrappedValue == 50...100)
        p.restore(.range(lower: 10, upper: 60))
        #expect(p.wrappedValue == 10...60)
    }

    @Test func stringPresentsATextBox() {
        let p = Param(wrappedValue: "hello", "Title")
        guard case .text(let control) = p.control else {
            Issue.record("String should present a text field")
            return
        }
        control.set("ollin")
        #expect(p.wrappedValue == "ollin")
        #expect(p.stored == .text("ollin"))
        p.restore(.text("moved"))
        #expect(p.wrappedValue == "moved")
    }

    @Test func choicesPresentAMenuKeyedOnNames() {
        let p = Param(wrappedValue: LightingPreset.standard)
        guard case .menu(let control) = p.control else {
            Issue.record("LightingPreset should present a menu")
            return
        }
        #expect(control.options.contains("Golden Hour"))   // humanized choice name
        control.set(control.options.firstIndex(of: "Noir") ?? 0)
        #expect(p.wrappedValue == .noir)
        #expect(p.stored == .option("noir"))
        p.restore(.option("moonlight"))
        #expect(p.wrappedValue == .moonlight)
        p.restore(.option("gone"))                          // unknown name is ignored
        #expect(p.wrappedValue == .moonlight)
    }

    @Test func theMaterialLibraryPresentsAMenu() {
        let p = Param(wrappedValue: Material.glossy)
        guard case .menu(let control) = p.control else {
            Issue.record("Material should present a menu")
            return
        }
        #expect(control.options.contains("Frosted Glass"))  // humanized choice name
        control.set(control.options.firstIndex(of: "Gummy") ?? 0)
        #expect(p.wrappedValue == .gummy)
        #expect(p.stored == .option("gummy"))
        p.restore(.option("polishedMetal"))
        #expect(p.wrappedValue == .polishedMetal)
    }

    @Test func mismatchedRestoreIsIgnored() {
        let p = Param(wrappedValue: 50.0, 0...100)
        p.restore(.boolean(true))
        #expect(p.wrappedValue == 50)
        p.restore(.option("dots"))
        #expect(p.wrappedValue == 50)
    }

    @Test func metadataRidesTheParam() {
        let p = Param(wrappedValue: 1.0, "Sweep", 0...4, icon: "wind", group: "Motion")
        #expect(p.label == "Sweep" && p.icon == "wind" && p.group == "Motion")
    }
}
