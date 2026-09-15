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
    /// The list under the caret; see `CompletionController`.
    let completion = CompletionController()
    private var highlighter = SwiftHighlighter()
    /// Buffer content handed over before the view mounted, applied on attach.
    private var pendingText: String?
    private var flashTask: Task<Void, Never>?
    /// The range the evaluate pulse is lighting up, or nil between pulses.
    private var flashing: NSRange?

    /// Called by the representable once the `NSTextView` exists; `host` is
    /// the view around its scroll view, where the completion list is laid.
    func attach(_ textView: NSTextView, host: NSView) {
        self.textView = textView
        completion.attach(textView: textView, host: host)
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
        completion.dismiss()
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
        completion.dismiss()
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
        completion.textDidChange()
    }

    /// The caret moved; the completion list follows or closes.
    func handleSelectionChange() {
        completion.selectionDidChange()
    }

    /// A key command the text view is about to run, offered to the completion
    /// list first. `true` when the list took it.
    func handle(command: Selector) -> Bool {
        completion.handle(command)
    }

    /// Sketch ▸ Complete Name: open the list at the caret, or close it.
    func toggleCompletion() {
        completion.toggle()
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

    /// A brief accent pulse of the text backdrop, the "that ran" cue, over the
    /// block the caret stands in rather than the whole buffer. The whole buffer
    /// still compiles and the whole instance is still replaced, so the pulse
    /// says where the performer was working, not what the compiler saw; a caret
    /// standing between declarations lights everything, which is honest about
    /// having nothing narrower to point at.
    func flashEvaluate() {
        flashTask?.cancel()
        flashing = evaluatedRegion()?.range
            ?? NSRange(location: 0, length: (textView?.string as NSString?)?.length ?? 0)
        rehighlight()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            flashing = nil
            rehighlight()
        }
    }

    /// The declaration the caret stands in, for the pulse and for a host that
    /// wants to name it.
    func evaluatedRegion() -> SourceRegions.Region? {
        guard let textView else { return nil }
        return SourceRegions.region(in: textView.string,
                                    containingOffset: textView.selectedRange().location)
    }

    /// Push the persisted style parameters (font size, backdrop opacity) into the
    /// highlighter; no-ops when nothing changed so SwiftUI update passes stay
    /// cheap.
    func configure(fontSize: Double, backdropOpacity: Double, completesAsYouType: Bool) {
        completion.completesAsYouType = completesAsYouType
        guard highlighter.fontSize != fontSize
            || highlighter.backdropOpacity != backdropOpacity else { return }
        highlighter.fontSize = fontSize
        highlighter.backdropOpacity = backdropOpacity
        completion.fontSize = fontSize
        textView?.typingAttributes = highlighter.typingAttributes
        rehighlight()
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func resignFocus() {
        completion.dismiss()
        guard let textView, textView.window?.firstResponder === textView else { return }
        textView.window?.makeFirstResponder(nil)
    }

    private func rehighlight() {
        guard let storage = textView?.textStorage else { return }
        highlighter.apply(to: storage, diagnostics: diagnostics, flashing: flashing)
    }
}
