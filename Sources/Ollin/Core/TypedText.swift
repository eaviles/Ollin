import Foundation
#if os(macOS)
import AppKit
#endif

// Typed text: what the keyboard types, as a text field receives it. The keys
// themselves keep arriving through `key` and `keyPressed()`; this is the other
// reading of the same presses, after the system's input methods have composed
// them (a dead key's accent, an input method's confirmed word, the emoji
// viewer's pick). The sketch reads it through `typedText()` and sees what is
// still being composed in `composingText`.

public extension String {
    /// Append text `typedText()` returned, the way a text field takes it: a
    /// backspace character (`"\u{8}"`, which Delete types) takes the last
    /// character away, and everything else is appended as it is, Return's
    /// `"\n"` and Tab's `"\t"` included.
    ///
    /// ```swift
    /// caption.append(typing: typedText())
    /// ```
    mutating func append(typing typed: String) {
        for character in typed {
            if character == TypedText.backspace {
                if !isEmpty { removeLast() }
            } else {
                append(character)
            }
        }
    }
}

/// The spellings the input system's commands type, kept in one place so the
/// view that types them and `append(typing:)` that reads them agree.
enum TypedText {
    /// What Delete types: the backspace control character.
    static let backspace: Character = "\u{8}"

    /// The text an editing command stands for, or `nil` for a command that
    /// types nothing (an arrow, Escape, a selection command). A text field
    /// answers these by editing its own text; a sketch has no text of its own,
    /// so the ones that would add or take away a character are handed to it as
    /// characters, and the rest are dropped without the beep an unanswered
    /// command would make.
    static func text(forCommand name: String) -> String? {
        switch name {
        case "insertNewline:", "insertLineBreak:", "insertNewlineIgnoringFieldEditor:",
             "insertParagraphSeparator:":
            return "\n"
        case "insertTab:", "insertTabIgnoringFieldEditor:":
            return "\t"
        case "deleteBackward:", "deleteBackwardByDecomposingPreviousCharacter:":
            return String(backspace)
        default:
            return nil
        }
    }

    /// Inserted text as the sketch receives it: a carriage return reads as a
    /// newline, and any other control character (a Control-key chord no
    /// binding claimed) is dropped, so `typedText()` holds only what a person
    /// meant to type.
    static func cleaned(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r", "\n": out.unicodeScalars.append("\n")
            case "\t": out.unicodeScalars.append(scalar)
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// The plain string inside what an input method hands over, which is a
    /// `String` or an `NSAttributedString`.
    static func plain(_ value: Any) -> String {
        if let attributed = value as? NSAttributedString { return attributed.string }
        return value as? String ?? ""
    }
}

#if os(macOS)
// The canvas takes part in the input system the way a text view does, so the
// system composes text for it: every key press goes through
// `interpretKeyEvents(_:)`, and the input system answers with text to insert,
// text being composed, or an editing command. The sketch has no document, so
// the only text this client ever holds is the composition still under way.
extension OllinMTKView: @MainActor NSTextInputClient {

    /// Hand one key press to the input system, which may answer by typing.
    /// A key with Command held is a shortcut a menu did not claim, and types
    /// nothing; during a replay the recorded run owns the sketch's text.
    func composeText(from event: NSEvent) {
        guard sketch != nil, !event.modifierFlags.contains(.command) else { return }
        if let runner = delegate as? SketchRunner, runner.isReplaying { return }
        interpretKeyEvents([event])
    }

    /// Drop a composition in progress, with nothing typed: the canvas lost
    /// the keyboard, so whatever was half written goes with it, as it does
    /// when a text field loses focus.
    func abandonComposition() {
        guard !markedText.isEmpty else { return }
        markedText = ""
        markedSelection = NSRange(location: 0, length: 0)
        inputContext?.discardMarkedText()
        sketch?.handleComposingText("")
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = TypedText.cleaned(TypedText.plain(string))
        if !markedText.isEmpty {
            markedText = ""
            markedSelection = NSRange(location: 0, length: 0)
            sketch?.handleComposingText("")
        }
        sketch?.handleTypedText(text)
    }

    override func doCommand(by selector: Selector) {
        guard let text = TypedText.text(forCommand: NSStringFromSelector(selector)) else { return }
        sketch?.handleTypedText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = TypedText.plain(string)
        markedSelection = markedText.isEmpty ? NSRange(location: 0, length: 0) : selectedRange
        sketch?.handleComposingText(markedText)
    }

    /// The input method is done composing without choosing: what it showed
    /// counts as typed, the way a text field keeps it.
    func unmarkText() {
        let text = markedText
        guard !text.isEmpty else { return }
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func selectedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: 0, length: 0) : markedSelection
    }

    func markedRange() -> NSRange {
        markedText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (markedText as NSString).length)
    }

    func hasMarkedText() -> Bool { !markedText.isEmpty }

    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? {
        let whole = NSRange(location: 0, length: (markedText as NSString).length)
        let inside = NSIntersectionRange(range, whole)
        guard range.location != NSNotFound, inside.length > 0 else { return nil }
        actualRange?.pointee = inside
        return NSAttributedString(string: (markedText as NSString).substring(with: inside))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// Where the input method puts its candidates: just below the sketch's
    /// `caretPosition`, or below the pointer while the sketch names none.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        var point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if let sketch, let caret = sketch.caretPosition {
            point = viewRect(of: Rectangle(x: caret.x, y: caret.y, width: 0, height: 0),
                             canvasWidth: sketch.width, canvasHeight: sketch.height,
                             in: bounds, through: projection).origin
        }
        return window.convertToScreen(convert(NSRect(origin: point, size: .zero), to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
}
#endif
