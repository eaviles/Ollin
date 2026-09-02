import AppKit
import OllinRuntime

/// The imperative bridge between the SwiftUI host and the editor's `NSTextView`.
/// The text view owns the buffer; SwiftUI never mirrors it (mirroring a live
/// `NSTextView` into view state fights the field editor and loops updates).
/// The session snapshots the text at evaluate/save time via `text()`, and every
/// styling pass (syntax colors, the legibility backdrop, diagnostic tints, the
/// evaluate flash) runs through `rehighlight()` here.
@MainActor
final class EditorController {
    private(set) weak var textView: NSTextView?
    /// Fired on every user edit (dirty tracking). Programmatic `setText` does
    /// not fire it.
    var onTextChange: (() -> Void)?

    private(set) var diagnostics: [CompileDiagnostic] = []
    private var highlighter = SwiftHighlighter()
    /// Buffer content handed over before the view mounted, applied on attach.
    private var pendingText: String?
    private var flashTask: Task<Void, Never>?
    private var isFlashing = false

    /// Called by the representable once the `NSTextView` exists.
    func attach(_ textView: NSTextView) {
        self.textView = textView
        textView.typingAttributes = highlighter.typingAttributes
        if let pendingText {
            self.pendingText = nil
            setText(pendingText)
        } else {
            rehighlight()
        }
    }

    /// Snapshot the buffer (what ⌘↩ evaluates and ⌘S writes).
    func text() -> String {
        textView?.string ?? pendingText ?? ""
    }

    /// Replace the buffer (open / new / recovery restore): resets undo history
    /// and restyles. Does not mark the document dirty.
    func setText(_ string: String) {
        guard let textView else {
            pendingText = string
            return
        }
        textView.string = string
        textView.undoManager?.removeAllActions()
        textView.typingAttributes = highlighter.typingAttributes
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        rehighlight()
    }

    /// Replace the buffer with an edit made for the person at the keyboard (the
    /// parameter values written into their own `@Param` lines), keeping what
    /// `setText` throws away: the caret, the scroll, and one undo step that
    /// takes the whole thing back. It goes through the text view rather than the
    /// storage so the change is an ordinary edit, which is what marks the
    /// document dirty and leaves ⌘S the only thing that writes the file.
    func replaceBuffer(with string: String) {
        guard let textView else {
            pendingText = string
            return
        }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        guard textView.shouldChangeText(in: whole, replacementString: string) else { return }
        let caret = textView.selectedRange().location
        let visible = textView.enclosingScrollView?.contentView.bounds.origin
        textView.textStorage?.replaceCharacters(in: whole, with: string)
        textView.didChangeText()
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(caret, length), length: 0))
        if let visible { textView.enclosingScrollView?.contentView.scroll(to: visible) }
        rehighlight()
    }

    /// Restyle after a user edit; also the dirty-tracking hook's companion
    /// (called by the representable's delegate).
    func handleTextChange() {
        onTextChange?()
        rehighlight()
    }

    /// Update the error-line tints from a compile result.
    func setDiagnostics(_ diagnostics: [CompileDiagnostic]) {
        self.diagnostics = diagnostics
        rehighlight()
    }

    /// Move the caret to a diagnostic's position and reveal it.
    func jump(toLine line: Int, column: Int) {
        guard let textView else { return }
        let text = textView.string as NSString
        var index = 0
        var current = 1
        while current < line, index < text.length {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            index = range.location + range.length
            current += 1
        }
        guard index <= text.length else { return }
        let lineRange = text.lineRange(for: NSRange(location: min(index, max(text.length - 1, 0)), length: 0))
        let caret = min(lineRange.location + max(column - 1, 0), lineRange.location + lineRange.length)
        textView.setSelectedRange(NSRange(location: min(caret, text.length), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        focus()
    }

    /// A brief accent pulse of the text backdrop, the "that ran" cue.
    func flashEvaluate() {
        flashTask?.cancel()
        isFlashing = true
        rehighlight()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isFlashing = false
            rehighlight()
        }
    }

    /// Push the persisted style parameters (font size, backdrop opacity) into the
    /// highlighter; no-ops when nothing changed so SwiftUI update passes stay
    /// cheap.
    func configure(fontSize: Double, backdropOpacity: Double) {
        guard highlighter.fontSize != fontSize
            || highlighter.backdropOpacity != backdropOpacity else { return }
        highlighter.fontSize = fontSize
        highlighter.backdropOpacity = backdropOpacity
        textView?.typingAttributes = highlighter.typingAttributes
        rehighlight()
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func resignFocus() {
        guard let textView, textView.window?.firstResponder === textView else { return }
        textView.window?.makeFirstResponder(nil)
    }

    private func rehighlight() {
        guard let storage = textView?.textStorage else { return }
        highlighter.apply(to: storage, diagnostics: diagnostics, flashing: isFlashing)
    }
}
