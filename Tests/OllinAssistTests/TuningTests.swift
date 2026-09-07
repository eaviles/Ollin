import Foundation
import Testing
import Ollin
@testable import OllinAssist
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The tuner without the model: what a sketch's parameters become in a request,
/// the words the model is given, a reply read against every kind, the moves it
/// reports, and the way back. A stand-in model answers each case.
@Suite
@MainActor
struct TuningTests {

    enum Mood: String, CaseIterable, ParamOption { case calm, easeOut, deepBlue }

    /// One parameter of every kind words can set, one they cannot, and one a
    /// show-rule hides.
    final class Subject: Sketch {
        @Param(0...200) var radius = 120.0
        @Param(1...12, group: "Layout") var rings = 5
        @Param var filled = true
        @Param var tint: Color = Color(red: 0.5, green: 0, blue: 1)
        @Param var mood: Mood = .calm
        @Param var caption = "hello"
        @Param(0...1, step: 0.25) var quantized = 0.5
        @Param(x: 0...1080, y: 0...1080) var anchor = Vector2(540, 540)
        @Param(0...10) var grain = 3.0

        override func setup() {
            $grain.show(when: $filled) { !$0 }
        }
        override func draw() {}
    }

    /// Answers with what it was handed, and keeps the request it saw.
    final class Canned: TuningModel, @unchecked Sendable {
        var reply: TuningReply
        var seen: TuningRequest?
        init(_ reply: TuningReply) { self.reply = reply }
        func propose(_ request: TuningRequest) async throws -> TuningReply {
            seen = request
            return reply
        }
    }

    private func subject() -> Subject {
        let sketch = Subject()
        sketch.setup()
        return sketch
    }

    // MARK: - The request

    @Test func everyKindWordsCanSetIsDescribedAndTheRestNamed() {
        let request = TuningRequest(subject().parameters(), look: "warmer", sketchName: "Subject")
        #expect(request.parameters.map(\.name) == ["radius", "rings", "filled", "tint", "mood", "caption", "quantized"])
        #expect(request.leftOut == ["Anchor"])
        let byName = Dictionary(uniqueKeysWithValues: request.parameters.map { ($0.name, $0) })
        #expect(byName["radius"]?.kind == .number(range: 0...200, current: 120))
        #expect(byName["rings"]?.kind == .integer(range: 1...12, current: 5))
        #expect(byName["rings"]?.group == "Layout")
        #expect(byName["filled"]?.kind == .bool(current: true))
        #expect(byName["mood"]?.kind == .choice(options: ["Calm", "Ease Out", "Deep Blue"], current: "Calm"))
        #expect(byName["caption"]?.kind == .text(current: "hello"))
        if case .color(let current) = byName["tint"]?.kind {
            #expect(abs(current.red - 0.5) < 1e-9 && current.blue == 1)
        } else {
            Issue.record("tint should be a color")
        }
    }

    @Test func aHiddenParameterIsLeftOutSilently() {
        let sketch = subject()
        var request = TuningRequest(sketch.parameters(), look: "grainier")
        #expect(!request.parameters.contains { $0.name == "grain" })
        #expect(request.leftOut == ["Anchor"])
        sketch.filled = false
        request = TuningRequest(sketch.parameters(), look: "grainier")
        #expect(request.parameters.contains { $0.name == "grain" })
    }

    @Test func thePromptNamesEachParameterWithItsRangeAndValue() {
        let request = TuningRequest(subject().parameters(), look: "as big as it goes", sketchName: "Subject")
        let prompt = request.promptText
        #expect(prompt.hasPrefix("Sketch: Subject.\nParameters:\n"))
        #expect(prompt.contains("- radius: Radius. a number from 0 to 200, now 120."))
        #expect(prompt.contains("- rings: Rings, in the Layout group. a whole number from 1 to 12, now 5."))
        #expect(prompt.contains("- filled: Filled. true or false, now true."))
        #expect(prompt.contains("- tint: Tint. a color as #RRGGBB, now #8000FF (purple)."))
        #expect(prompt.contains("- mood: Mood. one of Calm, Ease Out, Deep Blue; now Calm."))
        #expect(prompt.contains("- caption: Caption. text, now \"hello\"."))
        #expect(prompt.hasSuffix("\nLook: \"as big as it goes\""))
        #expect(!prompt.contains("anchor"))
        #expect(TuningRequest.instructions.contains("touch nothing else"))
    }

    @Test func numbersReadTheShortWay() {
        #expect(plain(120) == "120")
        #expect(plain(86.5) == "86.5")
        #expect(plain(0.1) == "0.1")
        #expect(plain(1.0 / 3) == "0.333")
        #expect(plain(-2) == "-2")
    }

    @Test func colorsHaveWordsAndHex() {
        #expect(ColorWords.hex(Color(red: 1, green: 0.5, blue: 0)) == "#FF8000")
        #expect(ColorWords.hex(Color(red: 0, green: 0, blue: 0, alpha: 0.5)) == "#00000080")
        #expect(ColorWords.name(Color(red: 1, green: 0.5, blue: 0)) == "orange")
        #expect(ColorWords.name(Color(red: 0, green: 0, blue: 0.4)) == "dark blue")
        #expect(ColorWords.name(Color(red: 0.9, green: 0.9, blue: 1)) == "pale blue")
        #expect(ColorWords.name(Color(red: 0.5, green: 0.5, blue: 0.5)) == "gray")
        #expect(ColorWords.name(.white) == "white")
        #expect(ColorWords.name(.black) == "black")
        #expect(ColorWords.color(from: "#FF8000", keepingAlphaOf: .black) == Color(red: 1, green: 128.0 / 255, blue: 0))
        #expect(ColorWords.color(from: "ff8000", keepingAlphaOf: Color(red: 0, green: 0, blue: 0, alpha: 0.25))?.alpha == 0.25)
        #expect(ColorWords.color(from: "#FF800080", keepingAlphaOf: .black)?.alpha == 128.0 / 255)
        #expect(ColorWords.color(from: "orange", keepingAlphaOf: .black) == nil)
        #expect(ColorWords.color(from: "#FF80", keepingAlphaOf: .black) == nil)
    }

    // MARK: - The reply

    @Test func aReplyMovesEveryKindThroughItsOwnControl() async throws {
        let sketch = subject()
        let model = Canned([
            "radius": .number(180), "rings": .number(3), "filled": .bool(false),
            "tint": .text("#FF4500"), "mood": .text("deep blue"), "caption": .text("dusk"),
            "quantized": .number(0.6),
        ])
        let tuning = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "warmer, fewer rings")
        #expect(model.seen?.look == "warmer, fewer rings")
        #expect(sketch.radius == 180)
        #expect(sketch.rings == 3)
        #expect(sketch.filled == false)
        #expect(sketch.mood == .deepBlue)
        #expect(sketch.caption == "dusk")
        #expect(sketch.quantized == 0.5)                    // 0.6 snaps to the 0.25 step
        #expect(abs(sketch.tint.red - 1) < 1e-9 && abs(sketch.tint.green - 69.0 / 255) < 1e-9)
        #expect(tuning.moves.map(\.name) == ["radius", "rings", "filled", "tint", "mood", "caption"])
        #expect(tuning.unreadable.isEmpty)
        #expect(tuning.leftOut == ["Anchor"])
        #expect(tuning.summary == "Moved Radius from 120 to 180, Rings from 5 to 3, Filled from on to off, Tint from #8000FF to #FF4500, Mood from calm to deepBlue, and Caption from \"hello\" to \"dusk\".")
    }

    @Test func valuesAreHeldToTheRangeAndRounded() async throws {
        let sketch = subject()
        let model = Canned(["radius": .number(900), "rings": .number(2.6)])
        let tuning = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "huge")
        #expect(sketch.radius == 200)
        #expect(sketch.rings == 3)
        #expect(tuning.summary == "Moved Radius from 120 to 200 and Rings from 5 to 3.")
    }

    @Test func anUnknownNameAndAnUnchangedValueAreNotMoves() async throws {
        let sketch = subject()
        let model = Canned(["radius": .number(120), "nothing": .number(1), "filled": .text("yes")])
        let tuning = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "the same")
        #expect(tuning.moves.isEmpty)
        #expect(tuning.summary == "Nothing moved: no parameter fits those words. Anchor is not a kind words can set.")
    }

    @Test func aValueTheKindCannotReadIsNamedNotGuessed() async throws {
        let sketch = subject()
        let model = Canned(["tint": .text("orange"), "mood": .text("wistful"), "radius": .bool(true)])
        let tuning = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "orange and wistful")
        #expect(sketch.mood == .calm)
        #expect(sketch.radius == 120)
        #expect(tuning.moves.isEmpty)
        #expect(tuning.unreadable == ["Radius", "Tint", "Mood"])
        #expect(tuning.summary == "Nothing moved: no parameter fits those words. The answer for Radius, Tint, and Mood could not be read. Anchor is not a kind words can set.")
    }

    @Test func aHiddenParameterIsNotMovedEvenWhenAnswered() async throws {
        let sketch = subject()
        let model = Canned(["grain": .number(9)])
        let tuning = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "grainier")
        #expect(sketch.grain == 3)
        #expect(tuning.moves.isEmpty)
    }

    @Test func revertPutsEveryMoveBack() async throws {
        let sketch = subject()
        let model = Canned(["radius": .number(40), "mood": .text("Ease Out"), "tint": .text("#000000")])
        let tuning = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "small, dark, easing")
        #expect(sketch.radius == 40 && sketch.mood == .easeOut && sketch.tint == .black)
        tuning.revert()
        #expect(sketch.radius == 120)
        #expect(sketch.mood == .calm)
        #expect(sketch.tint == Color(red: 0.5, green: 0, blue: 1))
    }

    @Test func anEmptyLookAndASketchWithNothingToTuneAreRefused() async {
        let sketch = subject()
        let model = Canned([:])
        await #expect(throws: TuningError.emptyLook) {
            try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "   ")
        }
        final class Bare: Sketch {
            @Param(x: 0...1, y: 0...1) var anchor = Vector2(0, 0)
            override func draw() {}
        }
        await #expect(throws: TuningError.nothingToTune) {
            try await ParameterTuner(model: model).tune(Bare().parameters(), toward: "warmer")
        }
        #expect(model.seen == nil)
        #expect(TuningError.emptyLook.errorDescription == "Describe the look in a few words first.")
    }

    @Test func theSketchFormUsesTheTypeName() async throws {
        let sketch = subject()
        // The default model is the on-device one; the sketch form only forwards,
        // so check the request shape through the tuner with the same handles.
        let model = Canned(["radius": .number(10)])
        _ = try await ParameterTuner(model: model).tune(sketch.parameters(), toward: "tiny", sketchName: String(describing: type(of: sketch)))
        #expect(model.seen?.sketchName == "Subject")
    }

    // MARK: - The inspector action

    @Test func theInspectorActionReportsTheSummaryAndUndoes() async throws {
        let sketch = subject()
        let model = Canned(["radius": .number(50)])
        let action = ParamTuneAction(tuner: ParameterTuner(model: model)) { sketch.parameters() }
        let outcome = await action.perform("smaller")
        #expect(outcome.message == "Moved Radius from 120 to 50.")
        #expect(sketch.radius == 50)
        outcome.undo?()
        #expect(sketch.radius == 120)
        let refused = await action.perform("")
        #expect(refused.message == "Describe the look in a few words first.")
        #expect(refused.undo == nil)
    }

    @Test func theListViewDiffNamesWhatMoved() {
        let sketch = subject()
        let before = ParametersListView.storedValues(of: sketch.parameters())
        sketch.radius = 10
        sketch.filled = false
        let after = ParametersListView.storedValues(of: sketch.parameters())
        #expect(ParametersListView.moved(from: before, to: after) == ["filled", "radius"])
        #expect(ParametersListView.moved(from: after, to: after).isEmpty)
    }

    // MARK: - The on-device model, without asking it anything

    #if canImport(FoundationModels)

    @Test func theSchemaBuildsForEveryKind() throws {
        let request = TuningRequest(subject().parameters(), look: "warmer")
        let guided = try OnDeviceModel.schema(for: request, guided: true)
        let plain = try OnDeviceModel.schema(for: request, guided: false)
        let text = guided.debugDescription
        for name in request.parameters.map(\.name) { #expect(text.contains(name)) }
        #expect(text.contains("Deep Blue"))
        #expect(!plain.debugDescription.isEmpty)
    }

    @Test func aGeneratedAnswerReadsBackByKind() throws {
        let content = try GeneratedContent(json: ##"{"radius": 180.5, "rings": 3, "filled": false, "tint": "#FF4500", "mood": "Deep Blue", "skip": null, "deep": {"a": 1}, "many": [1, 2]}"##)
        let reply = OnDeviceModel.reply(from: content)
        #expect(reply["radius"] == .number(180.5))
        #expect(reply["rings"] == .number(3))
        #expect(reply["filled"] == .bool(false))
        #expect(reply["tint"] == .text("#FF4500"))
        #expect(reply["mood"] == .text("Deep Blue"))
        #expect(reply["skip"] == nil && reply["deep"] == nil && reply["many"] == nil)
        #expect(OnDeviceModel.reply(from: try GeneratedContent(json: "[1, 2]")).isEmpty)
    }

    @Test func systemErrorsBecomeSentences() {
        struct Named: Error { let name: String }
        enum Fake: Error { case exceededContextWindowSize, guardrailViolation, unsupportedLanguageOrLocale, other }
        #expect(OnDeviceModel.translate(Fake.exceededContextWindowSize) == .tooMuchToDescribe)
        #expect(OnDeviceModel.translate(Fake.guardrailViolation) == .refused)
        #expect(OnDeviceModel.translate(Fake.unsupportedLanguageOrLocale) == .unsupportedLanguage)
        if case .failed = OnDeviceModel.translate(Fake.other) {} else { Issue.record("an unknown error keeps its own words") }
        #expect(TuningError.tooMuchToDescribe.errorDescription == "This sketch has more parameters than the model can read in one ask.")
    }

    /// One real ask, only where the machine's model is on: the plainest phrase
    /// there is, against two parameters, must move the one it names to the top
    /// of its range. Skipped elsewhere (a CI runner has no Apple Intelligence).
    @Test func theOnDeviceModelMovesTheParameterAPhraseNames() async throws {
        guard ParameterTuner.availability.isAvailable else { return }
        final class Two: Sketch {
            @Param(0...200) var radius = 120.0
            @Param var filled = true
            override func draw() {}
        }
        let sketch = Two()
        let tuning = try await ParameterTuner().tune(sketch.parameters(), toward: "the radius as big as it goes", sketchName: "Two")
        #expect(tuning.moves.contains { $0.name == "radius" })
        #expect(sketch.radius == 200)
    }

    #endif
}
