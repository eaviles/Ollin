import AppKit
import Carbon.HIToolbox
import Metal
import Testing
@testable import Ollin

/// Typed text: the keyboard read the way a text field reads it, after the
/// system's input methods compose it. A dead key's accent, an input method's
/// confirmed word, and the editing keys arrive through `typedText()`, what is
/// still being composed shows in `composingText`, a take repeats both, and the
/// keys themselves keep reaching `keyPressed()` as they always did.
@Suite
@MainActor
struct TypedTextTests {
    private final class Typist: Sketch {
        var typedHooks: [String] = []
        var presses: [Character?] = []
        var frames: [[String]] = []
        var caption = ""
        override func textTyped() { typedHooks.append(typedTextInbox) }
        override func keyPressed() { presses.append(key) }
        override func draw() {
            caption.append(typing: typedText())
            frames.append([caption, composingText])
        }
    }

    private func view(for sketch: Sketch) throws -> OllinMTKView {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: sketch)
        view.isPaused = true
        return view
    }

    private func step(_ sketch: Sketch) {
        sketch.advance(time: Double(sketch.frameCount + 1) / 60, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
    }

    private let nowhere = NSRange(location: NSNotFound, length: 0)

    // MARK: Through the input client

    /// A dead key holds its accent as composition and the next key finishes
    /// it: Option-E shows "´" being composed, and E types "é" and clears it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDeadKeySequenceArrivesAsTheComposedCharacter() throws {
        let sketch = Typist()
        let canvas = try view(for: sketch)
        canvas.setMarkedText("\u{B4}", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: nowhere)
        #expect(sketch.composingText == "\u{B4}")
        #expect(canvas.hasMarkedText() && canvas.markedRange() == NSRange(location: 0, length: 1))
        #expect(sketch.typedTextInbox.isEmpty, "the accent alone typed something")
        canvas.insertText("\u{E9}", replacementRange: nowhere)
        #expect(sketch.composingText.isEmpty)
        #expect(!canvas.hasMarkedText() && canvas.markedRange().location == NSNotFound)
        #expect(sketch.typedHooks == ["\u{E9}"])
        #expect(sketch.typedText() == "\u{E9}")
        #expect(sketch.typedText().isEmpty, "reading did not empty it")
    }

    /// An input method composes a reading, turns it into characters, and only
    /// the confirmed word is typed: each step shows in `composingText`, and
    /// the hook fires once, for the word.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anInputMethodCompositionArrivesAsTheConfirmedWord() throws {
        let sketch = Typist()
        let canvas = try view(for: sketch)
        var seen: [String] = []
        for reading in ["\u{306B}", "\u{306B}\u{307B}", "\u{306B}\u{307B}\u{3093}", "\u{65E5}\u{672C}"] {
            canvas.setMarkedText(NSAttributedString(string: reading),
                                 selectedRange: NSRange(location: (reading as NSString).length, length: 0),
                                 replacementRange: nowhere)
            seen.append(sketch.composingText)
        }
        #expect(seen == ["\u{306B}", "\u{306B}\u{307B}", "\u{306B}\u{307B}\u{3093}", "\u{65E5}\u{672C}"])
        #expect(sketch.typedHooks.isEmpty, "composition counted as typed")
        #expect(canvas.selectedRange() == NSRange(location: 2, length: 0))
        canvas.insertText(NSAttributedString(string: "\u{65E5}\u{672C}"), replacementRange: nowhere)
        #expect(sketch.typedHooks == ["\u{65E5}\u{672C}"])
        #expect(sketch.composingText.isEmpty)

        // An input method that lets go without choosing keeps what it showed.
        canvas.setMarkedText("\u{8A9E}", selectedRange: NSRange(location: 1, length: 0), replacementRange: nowhere)
        canvas.unmarkText()
        #expect(sketch.typedText() == "\u{65E5}\u{672C}\u{8A9E}")
        #expect(sketch.composingText.isEmpty)
    }

    /// The editing commands a text field answers by editing are typed as the
    /// characters they stand for; the rest type nothing, and nothing beeps.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theEditingKeysTypeTheirCharacters() throws {
        let sketch = Typist()
        let canvas = try view(for: sketch)
        canvas.insertText("abc", replacementRange: nowhere)
        canvas.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        canvas.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        canvas.doCommand(by: #selector(NSResponder.insertTab(_:)))
        canvas.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        canvas.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        canvas.insertText("d\r\u{1}e", replacementRange: nowhere)
        let typed = sketch.typedText()
        #expect(typed == "abc\u{8}\n\td\ne")
        var caption = "x"
        caption.append(typing: typed)
        #expect(caption == "xab\n\td\ne")
        var empty = ""
        empty.append(typing: "\u{8}\u{8}a\u{8}")
        #expect(empty.isEmpty, "a backspace past the start did something")
    }

    /// Losing the keyboard drops a composition half written: nothing is typed
    /// and `composingText` empties, as a text field's does.
    @Test(.enabled(if: Snapshot.hasMetal))
    func losingTheKeyboardDropsAComposition() throws {
        let sketch = Typist()
        let canvas = try view(for: sketch)
        canvas.setMarkedText("\u{306B}\u{307B}", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: nowhere)
        _ = canvas.resignFirstResponder()
        #expect(sketch.composingText.isEmpty)
        #expect(!canvas.hasMarkedText())
        #expect(sketch.typedText().isEmpty)
    }

    // MARK: Through key presses

    private func key(_ characters: String, ignoring: String? = nil, code: Int,
                     _ flags: NSEvent.ModifierFlags = [], repeat isARepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: ignoring ?? characters, isARepeat: isARepeat,
            keyCode: UInt16(code)))
    }

    /// A press types its character and fires `keyPressed()` once; holding it
    /// types again without firing the hook again; a Command chord no menu
    /// claimed types nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPressTypesAndARepeatTypesAgain() throws {
        let sketch = Typist()
        let canvas = try view(for: sketch)
        canvas.keyDown(with: try key("a", code: kVK_ANSI_A))
        canvas.keyDown(with: try key("a", code: kVK_ANSI_A, repeat: true))
        canvas.keyDown(with: try key("k", code: kVK_ANSI_K, .command))
        #expect(sketch.presses == ["a", "k"])
        #expect(sketch.typedText() == "aa")
    }

    // MARK: A take

    /// A take written while text was composed and typed plays it back to the
    /// frame on a fresh instance, and the events keep through the file.
    @Test func aReplayedTakeRepeatsTheTyping() throws {
        let live = Typist()
        live.setCanvasSize(width: 200, height: 200)
        live.takeRecorder = TakeRecorder(sketch: live)
        for k in 0..<20 {
            switch k {
            case 2: live.handleTypedText("Hi")
            case 4: live.handleComposingText("\u{B4}")
            case 5: live.handleComposingText(""); live.handleTypedText("\u{E9}")
            case 8: live.handleTypedText("\u{8}")
            default: break
            }
            step(live)
        }
        let take = live.takeRecorder!.take
        #expect(take.events.count == 5)

        let replay = Typist()
        replay.setCanvasSize(width: 200, height: 200)
        take.install(on: replay)
        for _ in 0..<20 {
            replay.handleTypedText("live")      // live input is gated off during a replay
            step(replay)
        }
        #expect(replay.frames == live.frames)
        #expect(live.frames[4] == ["Hi", "\u{B4}"] && live.frames[5] == ["Hi\u{E9}", ""])
        #expect(live.frames[8] == ["Hi", ""])

        let events: [Take.Event] = [.typed(text: "\u{65E5}\u{672C}\n"), .composing(text: "\u{306B}")]
        let data = try JSONEncoder().encode(events)
        #expect(try JSONDecoder().decode([Take.Event].self, from: data) == events)
    }
}
