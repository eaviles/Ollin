import SwiftUI
import AppKit

/// The transparent code layer over the stage: an `NSTextView` in a transparent
/// scroll view, styled entirely through `EditorController`, inside a host view
/// that also holds the completion list. Configuration happens once in
/// `makeNSView`; SwiftUI never owns the buffer (see `EditorController`), so
/// `updateNSView` only forwards the settings.
struct CodeEditorView: NSViewRepresentable {
    let controller: EditorController
    var fontSize: Double
    var backdropOpacity: Double
    var completesAsYouType: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> EditorHostView {
        let host = EditorHostView()
        let scrollView = NSTextView.scrollableTextView()
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = host.bounds
        host.addSubview(scrollView)
        guard let textView = scrollView.documentView as? NSTextView else { return host }

        // Transparent on every layer, so only the glyph backdrop the
        // highlighter paints separates code from canvas.
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        textView.drawsBackground = false

        // Every substitution off: a smart quote or dash in source is a silent
        // compile break, and the system's own inline completion would put
        // words in the code. Completion here is the list, and only the list.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 0.45, green: 0.32, blue: 0.85, alpha: 0.55),
            .foregroundColor: NSColor.white,
        ]
        textView.textContainerInset = NSSize(width: 22, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        controller.attach(textView, host: host)
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return host
    }

    func updateNSView(_ host: EditorHostView, context: Context) {
        controller.configure(fontSize: fontSize, backdropOpacity: backdropOpacity,
                             completesAsYouType: completesAsYouType)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let controller: EditorController

        init(controller: EditorController) {
            self.controller = controller
        }

        nonisolated func textDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                controller.handleTextChange()
            }
        }

        nonisolated func textViewDidChangeSelection(_ notification: Notification) {
            MainActor.assumeIsolated {
                controller.handleSelectionChange()
            }
        }

        /// The completion list sees every key command first (the arrows,
        /// Return, Tab, Escape); what it does not take, the editor runs.
        nonisolated func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            MainActor.assumeIsolated {
                controller.handle(command: commandSelector)
            }
        }
    }
}

/// The view around the editor's scroll view: flipped, so the completion list
/// is placed in the same top-down coordinates the text runs in.
final class EditorHostView: NSView {
    override var isFlipped: Bool { true }
}
