import Foundation
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
        control.write(3)
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
        control.write(false)
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
        control.write(.orange)
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
        control.write(2)
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
        control.write(Vector2(100, 200))
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
        control.write(Vector3(0.5, -0.5, 3))
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
        p.restore(.rectangle(x: 10, y: 20, width: 30, height: 40))
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
        control.write("ollin")
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
        control.write(control.options.firstIndex(of: "Noir") ?? 0)
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
        control.write(control.options.firstIndex(of: "Gummy") ?? 0)
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

    // MARK: Curves

    @Test func aCurveIsItsOwnValue() {
        // A built-in is its name, so the two spellings of the same curve match.
        #expect(Easing.easeInOut == Easing.easeInOutCubic)
        #expect(Easing.easeIn != Easing.easeOut)
        // A curve from a closure equals itself and every copy of itself, and
        // nothing else: two closures cannot be compared.
        let mine = Easing { t in t * t }
        let copy = mine
        let twin = Easing { t in t * t }
        #expect(mine == mine)
        #expect(mine == copy)
        #expect(mine != twin)
        #expect(mine != .easeInQuad)
    }

    @Test func everyCurveIsListedUnderItsOwnName() {
        // The menu's roster and the curves' own identities are two lists, and a
        // typo in either would key a persisted choice to the wrong curve.
        for (name, curve) in Easing.all {
            #expect(curve.name == name)
        }
        #expect(Easing.all.count == 32)                 // linear + 30 + smoothstep
        #expect(Set(Easing.all.map(\.name)).count == 32)
    }

    @Test func curvesPresentAMenuKeyedOnTheirNames() {
        let p = Param(wrappedValue: Easing.easeInOut)
        guard case .menu(let control) = p.control else {
            Issue.record("Easing should present a menu")
            return
        }
        #expect(control.options.contains("Ease Out Bounce"))       // humanized name
        // The friendly alias reads as the curve it is: easeInOut is the cubic.
        #expect(control.options[control.read()] == "Ease In Out Cubic")
        #expect(p.stored == .option("easeInOutCubic"))

        control.write(control.options.firstIndex(of: "Ease Out Bounce") ?? 0)
        #expect(p.wrappedValue == .easeOutBounce)
        #expect(p.stored == .option("easeOutBounce"))
        p.restore(.option("linear"))
        #expect(p.wrappedValue == .linear)
        p.restore(.option("gone"))                                  // unknown name is ignored
        #expect(p.wrappedValue == .linear)
        // The picked curve still shapes a value, which is the point of it.
        #expect(p.wrappedValue(0.25) == 0.25)
    }

    // MARK: Palettes and ramps

    @Test func aPalettePresentsItsColorsAsAStrip() {
        let p = Param(wrappedValue: Palette(.red, .white, .black))
        guard case .swatches(let control) = p.control else {
            Issue.record("Palette should present a swatch strip")
            return
        }
        #expect(control.style == .blocks)
        #expect(control.count == 1...12)
        // The colors come back in order, spread evenly over 0...1.
        #expect(control.read().map(\.color) == [.red, .white, .black])
        #expect(control.read().map(\.position) == [0, 0.5, 1])
        // The strip draws what the palette itself shows at each step.
        #expect(control.sample(0.1) == .red)
        #expect(control.sample(0.9) == .black)

        control.write([.init(position: 0, color: .blue), .init(position: 1, color: .green)])
        #expect(p.wrappedValue.colors == [.blue, .green])
    }

    @Test func aPaletteRoundTripsAndTruncatesToItsCount() {
        let p = Param(wrappedValue: Palette(.red, .white), count: 1...3)
        guard case .colors(let stops, let space) = p.stored else {
            Issue.record("a palette should store as colors")
            return
        }
        #expect(space == nil)                       // a palette blends through nothing
        #expect(stops.map(\.color) == [.red, .white])

        p.restore(.colors(stops: [ParamColorStop(position: 0, color: .black),
                                  ParamColorStop(position: 0.5, color: .orange),
                                  ParamColorStop(position: 1, color: .purple)],
                          space: nil))
        #expect(p.wrappedValue.colors == [.black, .orange, .purple])

        // One color too many is dropped from the end.
        p.wrappedValue = Palette(.red, .white, .black, .blue)
        #expect(p.wrappedValue.colors == [.red, .white, .black])
        p.restore(.number(3))                       // the wrong kind is ignored
        #expect(p.wrappedValue.count == 3)
    }

    @Test func aRampKeepsItsSpaceAndItsStops() {
        let p = Param(wrappedValue: Ramp(stops: [(0, .black), (0.25, .red), (1, .white)], in: .oklch))
        guard case .swatches(let control) = p.control else {
            Issue.record("Ramp should present a swatch strip")
            return
        }
        #expect(control.style == .gradient)
        #expect(control.count == 2...8)
        #expect(control.read().map(\.position) == [0, 0.25, 1])
        // The band is the ramp's own blend, not a straight line between stops.
        #expect(control.sample(0) == .black)
        #expect(control.sample(0.25) == p.wrappedValue.color(at: 0.25))
        #expect(control.sample(0.6) == p.wrappedValue.color(at: 0.6))
        #expect(control.sample(0.6) != Color.mix(.red, .white, 0.4))   // not a plain line

        // Moving a stop keeps the space the ramp blends through.
        control.write([.init(position: 0, color: .black), .init(position: 0.7, color: .red),
                     .init(position: 1, color: .white)])
        #expect(p.wrappedValue.stops.map(\.position) == [0, 0.7, 1])
        #expect(p.wrappedValue.space == .oklch)

        guard case .colors(_, let space) = p.stored else {
            Issue.record("a ramp should store as colors")
            return
        }
        #expect(space == "oklch")
        p.restore(.colors(stops: [ParamColorStop(position: 0, color: .blue),
                                  ParamColorStop(position: 1, color: .white)],
                          space: "paint"))
        #expect(p.wrappedValue.space == .paint)
        #expect(p.wrappedValue.stops.map(\.color) == [.blue, .white])
    }

    @Test func aStoredPaletteRestoresIntoARampAsAnEvenBlend() {
        // Both kinds carry the same payload, so a parameter that changed from one to
        // the other keeps its colors; a palette names no space, so the ramp
        // falls back to the default one.
        let palette = Param(wrappedValue: Palette(.red, .white, .black))
        let ramp = Param(wrappedValue: Ramp([.blue, .green]))
        ramp.restore(palette.stored)
        #expect(ramp.wrappedValue.stops.map(\.color) == [.red, .white, .black])
        #expect(ramp.wrappedValue.stops.map(\.position) == [0, 0.5, 1])
        #expect(ramp.wrappedValue.space == .oklab)
    }

    @Test func aNewSwatchLandsWhereThereIsRoomForIt() {
        // A palette grows at its end, keeping the color already there.
        let blocks = [ParamControl.Swatches.Stop(position: 0, color: .red),
                      ParamControl.Swatches.Stop(position: 1, color: .blue)]
        let grown = swatchStripAdding(to: blocks, blocks: true, sample: { _ in .green })
        #expect(grown.stops.map(\.color) == [.red, .blue, .blue])
        #expect(grown.selected == 2)

        // A ramp splits its widest gap, and takes the color the band shows
        // there, so adding a stop cannot change the picture.
        let band = [ParamControl.Swatches.Stop(position: 0, color: .black),
                    ParamControl.Swatches.Stop(position: 0.2, color: .red),
                    ParamControl.Swatches.Stop(position: 1, color: .white)]
        let split = swatchStripAdding(to: band, blocks: false, sample: { _ in .green })
        #expect(split.stops.map(\.position) == [0, 0.2, 0.6, 1])   // the 0.2...1 gap
        #expect(split.selected == 2)
        #expect(split.stops[2].color == .green)                    // read off the band

        // A ramp of one stop still has somewhere to put the second.
        let lone = swatchStripAdding(to: [.init(position: 0, color: .black)],
                                     blocks: false, sample: { _ in .white })
        #expect(lone.stops.map(\.position) == [0, 0.5])
        #expect(lone.selected == 1)
    }

    @Test func aSetOfColorsHoldsThroughAKeyAndHasNoParts() {
        // Nothing sits between two palettes, so an automation holds the one it
        // left, the way it does for a switch or a piece of text.
        let from = ParamStored.colors(stops: [ParamColorStop(position: 0, color: .red)], space: nil)
        let to = ParamStored.colors(stops: [ParamColorStop(position: 0, color: .blue)], space: nil)
        #expect(Automation.blend(from, to, 0.5) == from)
        #expect(Automation.parts(of: from).isEmpty)
        #expect(Automation.applying(["red": 1], to: from) == from)
    }

    // MARK: Show-rules

    @Test func parametersShowByDefault() {
        let p = Param(wrappedValue: 1.0, 0...10)
        #expect(p.isShown)
    }

    @Test func aShowRuleFollowsItsSourceParameter() {
        let transmission = Param(wrappedValue: 0.0, 0...1)
        let thickness = Param(wrappedValue: 0.8, 0...3)
        thickness.show(when: transmission) { $0 > 0 }
        #expect(!thickness.isShown)
        transmission.wrappedValue = 0.6
        #expect(thickness.isShown)
        transmission.wrappedValue = 0
        #expect(!thickness.isShown)
        // The value is untouched while hidden: it still holds and restores.
        #expect(thickness.wrappedValue == 0.8)
        thickness.restore(.number(1.5))
        #expect(thickness.wrappedValue == 1.5)
    }

    @Test func aHandleForwardsVisibility() {
        let gate = Param(wrappedValue: false)
        let dependent = Param(wrappedValue: 0.5, 0...1)
        dependent.show(when: gate) { $0 }
        let handle = ParamHandle(name: "dependent", param: dependent)
        #expect(!handle.isShown)
        gate.wrappedValue = true
        #expect(handle.isShown)
    }

    @Test func hiddenRowsLeaveTheSectionsAndAnEmptiedGroupDrops() {
        let a = Param(wrappedValue: 1.0, 0...10)                     // ungrouped, stays
        let b = Param(wrappedValue: 2.0, 0...10, group: "Glass")     // hides
        let c = Param(wrappedValue: 3.0, 0...10, group: "Glass")     // hides
        let d = Param(wrappedValue: 4.0, 0...10, group: "Glow")      // stays
        let gate = Param(wrappedValue: false)
        b.show(when: gate) { $0 }
        c.show(when: gate) { $0 }
        let handles = [ParamHandle(name: "a", param: a),
                       ParamHandle(name: "b", param: b),
                       ParamHandle(name: "c", param: c),
                       ParamHandle(name: "d", param: d)]

        let hidden = ParametersListView.hiddenIDs(in: handles)
        #expect(hidden == ["b", "c"])
        let sections = ParametersListView.visibleSections(of: handles, hiding: hidden)
        #expect(sections.map(\.title) == ["Parameters", "Glow"])
        #expect(sections[0].handles.map(\.id) == ["a"])

        gate.wrappedValue = true
        let all = ParametersListView.visibleSections(
            of: handles, hiding: ParametersListView.hiddenIDs(in: handles))
        #expect(all.map(\.title) == ["Parameters", "Glass", "Glow"])
        #expect(all[1].handles.map(\.id) == ["b", "c"])
    }

    // MARK: Folded groups

    @Test func aStringLiteralGroupStaysOpenAndFoldedSaysSo() {
        let plain = Param(wrappedValue: 1.0, 0...10, group: "Rings")
        #expect(plain.group == "Rings")
        #expect(!plain.groupIsFolded)

        let folded = Param(wrappedValue: 2.0, 0...10, group: .folded("Advanced"))
        #expect(folded.group == "Advanced")
        #expect(folded.groupIsFolded)

        let handle = ParamHandle(name: "folded", param: folded)
        #expect(handle.groupIsFolded)
    }

    @Test func oneFoldedMemberFoldsTheWholeGroupAndTheDefaultNeverFolds() {
        let loose = Param(wrappedValue: 1.0, 0...10)                             // default group
        let a = Param(wrappedValue: 2.0, 0...10, group: "Advanced")              // plain spelling
        let b = Param(wrappedValue: 3.0, 0...10, group: .folded("Advanced"))     // folds the group
        let c = Param(wrappedValue: 4.0, 0...10, group: "Rings")
        let handles = [ParamHandle(name: "loose", param: loose),
                       ParamHandle(name: "a", param: a),
                       ParamHandle(name: "b", param: b),
                       ParamHandle(name: "c", param: c)]

        let sections = ParametersListView.visibleSections(of: handles, hiding: [])
        #expect(sections.map(\.title) == ["Parameters", "Advanced", "Rings"])
        #expect(sections.map(\.isFolded) == [false, true, false])
        // The two spellings of "Advanced" land in one section, in order.
        #expect(sections[1].handles.map(\.id) == ["a", "b"])
    }

    @Test func foldMemoryRemembersPerSketchAndForgetsWithNoName() {
        let defaults = UserDefaults(suiteName: "OllinParamFoldTests")!
        defaults.removePersistentDomain(forName: "OllinParamFoldTests")
        defer { defaults.removePersistentDomain(forName: "OllinParamFoldTests") }

        let depth = Param(wrappedValue: 1.0, 0...10, group: .folded("Advanced"))
        let handles = [ParamHandle(name: "depth", param: depth)]

        // Untouched: closed (nothing remembered), whoever asks.
        #expect(ParamFoldMemory.isOpen(sketch: "Pulse", group: "Advanced", defaults: defaults) == nil)
        #expect(ParametersListView.rememberedOpenGroups(in: handles, sketch: "Pulse",
                                                        defaults: defaults).isEmpty)

        // Opened: remembered for that sketch, and only that sketch.
        ParamFoldMemory.setOpen(true, sketch: "Pulse", group: "Advanced", defaults: defaults)
        #expect(ParametersListView.rememberedOpenGroups(in: handles, sketch: "Pulse",
                                                        defaults: defaults) == ["Advanced"])
        #expect(ParametersListView.rememberedOpenGroups(in: handles, sketch: "Other",
                                                        defaults: defaults).isEmpty)

        // Closed again: back to the declared start.
        ParamFoldMemory.setOpen(false, sketch: "Pulse", group: "Advanced", defaults: defaults)
        #expect(ParametersListView.rememberedOpenGroups(in: handles, sketch: "Pulse",
                                                        defaults: defaults).isEmpty)

        // No sketch identity: nothing is remembered at all.
        ParamFoldMemory.setOpen(true, sketch: "Pulse", group: "Advanced", defaults: defaults)
        #expect(ParametersListView.rememberedOpenGroups(in: handles, sketch: nil,
                                                        defaults: defaults).isEmpty)
    }
}
