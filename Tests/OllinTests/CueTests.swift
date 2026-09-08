import Foundation
import Testing
@testable import Ollin

/// Cues: a named set of every parameter's value, saved from the parameters
/// as they stand and called back at once or over a fade. These pin what a
/// cue holds, how a fade moves each kind, how the sheet is walked and kept,
/// and the command-line cue.
@Suite
@MainActor
struct CueTests {

    private final class Looks: Sketch {
        enum Mood: String, ParamOption {
            case calm, wild
            var optionLabel: String { rawValue }
        }
        @Param(0 ... 100) var size = 10.0
        @Param(0 ... 10) var count = 2
        @Param var lit = false
        @Param var tint: Color = .red
        @Param var mood: Mood = .calm
        override func draw() {}
    }

    private func frame(_ sketch: Sketch, _ n: Int, dt: Double = 1 / 60) {
        for i in 0..<n { sketch.advance(time: Double(i) * dt, deltaTime: dt, frameRate: 1 / dt) }
    }

    @Test func saveCueCapturesEveryParameterAndACallRestoresThem() {
        let s = Looks()
        s.size = 40; s.count = 7; s.lit = true; s.tint = .blue; s.mood = .wild
        s.saveCue("loud")
        #expect(s.cueSheet.cues.map(\.name) == ["loud"])
        #expect(s.cueSheet["loud"]?.values.count == 5)
        #expect(s.currentCue == "loud")
        s.size = 1; s.count = 0; s.lit = false; s.tint = .red; s.mood = .calm
        #expect(s.cue("loud"))
        #expect(s.size == 40 && s.count == 7 && s.lit && s.tint == .blue && s.mood == .wild)
        #expect(!s.cue("nothing"))
    }

    @Test func aFadeEasesWhatCanFadeAndJumpsTheRest() {
        let s = Looks()
        s.size = 0; s.lit = false; s.mood = .calm; s.tint = .black
        s.saveCue("dark")
        s.size = 100; s.lit = true; s.mood = .wild; s.tint = .white
        s.saveCue("bright")
        s.cue("dark")
        #expect(s.size == 0)
        s.cue("bright", over: 1)
        #expect(s.isCueFading)
        frame(s, 1)
        // The switch and the menu flip on the first frame; the number has barely moved.
        #expect(s.lit && s.mood == .wild)
        #expect(s.size < 5)
        frame(s, 29)
        // Halfway through an ease slow at both ends is halfway there.
        #expect(abs(s.size - 50) < 2, "size \(s.size) at the midpoint")
        #expect(s.tint.red > 0.2 && s.tint.red < 0.8, "tint \(s.tint.red) at the midpoint")
        frame(s, 30)
        #expect(s.size == 100 && s.tint == .white)
        #expect(!s.isCueFading)
    }

    @Test func aCueCalledMidFadeStartsFromWhereTheParametersAre() {
        let s = Looks()
        s.size = 0; s.saveCue("a")
        s.size = 100; s.saveCue("b")
        s.cue("a"); s.cue("b", over: 1)
        frame(s, 30)
        let midway = s.size
        s.cue("a", over: 1)
        frame(s, 1)
        #expect(abs(s.size - midway) < 3, "the new fade left from \(s.size), not \(midway)")
        frame(s, 60)
        #expect(s.size == 0)
    }

    @Test func nextAndPreviousWalkTheSheetAndWrap() {
        let s = Looks()
        for (i, name) in ["one", "two", "three"].enumerated() {
            s.size = Double(i + 1) * 10
            s.saveCue(name)
        }
        #expect(!s.nextCue(over: 0) == false)
        s.cue("three")
        #expect(s.nextCue() && s.currentCue == "one" && s.size == 10)
        #expect(s.previousCue() && s.currentCue == "three" && s.size == 30)
        #expect(s.previousCue() && s.currentCue == "two")
        let fresh = Looks()
        #expect(!fresh.nextCue())
        fresh.saveCue("only")
        fresh.currentCue = nil
        #expect(fresh.nextCue() && fresh.currentCue == "only")
        fresh.currentCue = nil
        #expect(fresh.previousCue() && fresh.currentCue == "only")
    }

    @Test func aRequestRoutesByNameNumberAndStep() {
        let s = Looks()
        s.size = 5; s.saveCue("a")
        s.size = 6; s.saveCue("b")
        #expect(s.cue(.named("a")) && s.size == 5)
        #expect(s.cue(.number(1)) && s.size == 6)
        #expect(!s.cue(.number(2)))
        #expect(!s.cue(.number(-1)))
        #expect(s.cue(.next) && s.currentCue == "a")
        #expect(s.cue(.previous) && s.currentCue == "b")
    }

    @Test func savingAnExistingNameReplacesItInPlace() {
        let s = Looks()
        s.size = 1; s.saveCue("first")
        s.size = 2; s.saveCue("second")
        s.size = 9; s.saveCue("first")
        #expect(s.cueSheet.cues.map(\.name) == ["first", "second"])
        s.size = 0
        s.cue("first")
        #expect(s.size == 9)
        s.saveCue("   ")
        #expect(s.cueSheet.cues.count == 2)
    }

    @Test func deleteTakesTheCueOutAndClearsTheCurrent() {
        let s = Looks()
        s.saveCue("a"); s.saveCue("b")
        s.cue("a")
        s.deleteCue("a")
        #expect(s.cueSheet.cues.map(\.name) == ["b"])
        #expect(s.currentCue == nil)
        s.deleteCue("never")
        #expect(s.cueSheet.cues.count == 1)
    }

    @Test func aCueNamesOnlyWhatItHoldsAndSkipsWhatTheSketchLacks() {
        let s = Looks()
        s.size = 3; s.count = 4
        s.cueSheet.store(Cue(name: "partial", values: ["size": .number(77), "gone": .number(1)]))
        #expect(s.cue("partial"))
        #expect(s.size == 77 && s.count == 4)
        s.cue("partial", over: 1)
        frame(s, 120)
        #expect(s.size == 77 && s.count == 4)
    }

    @Test func cuesChangedFiresOnSaveAndDeleteNotOnACall() {
        let s = Looks()
        var fired = 0
        s.cuesChanged = { fired += 1 }
        s.saveCue("a")
        #expect(fired == 1)
        s.cue("a")
        #expect(fired == 1)
        s.deleteCue("a")
        #expect(fired == 2)
        s.deleteCue("a")
        #expect(fired == 2)
    }

    @Test func theSheetRoundTripsThroughAFileAndRefusesANewerVersion() throws {
        let path = NSTemporaryDirectory() + "ollin-cues-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let s = Looks()
        s.size = 42; s.tint = .blue; s.mood = .wild
        s.saveCue("kept")
        try s.saveCues(to: path)
        let back = Looks()
        try back.loadCues(from: path)
        #expect(back.cueSheet == s.cueSheet)
        #expect(back.cue("kept") && back.size == 42 && back.tint == .blue && back.mood == .wild)

        var newer = CueSheet()
        newer.version = CueSheet.currentVersion + 1
        try newer.write(to: path)
        #expect(throws: CueSheet.LoadError.self) { try CueSheet.load(from: path) }
    }

    @Test func theCommandLineCueLandsAfterSetup() throws {
        let path = NSTemporaryDirectory() + "ollin-cues-\(UUID().uuidString).json"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            OllinApp.cueSheetPath = nil
            OllinApp.startingCue = nil
        }
        let author = Looks()
        author.size = 64; author.saveCue("poster")
        try author.saveCues(to: path)
        OllinApp.readCueFlags(["--cues", path, "--cue", "poster"])
        #expect(OllinApp.cueSheetPath == path && OllinApp.startingCue == "poster")
        let s = Looks()
        s.runSetup()
        #expect(s.size == 64 && s.currentCue == "poster")
        // Without a sheet on the command line the cue is looked for in the
        // sketch's own.
        OllinApp.readCueFlags(["--cue", "poster"])
        let own = Looks()
        try own.loadCues(from: path)
        own.runSetup()
        #expect(own.size == 64)
    }
}
