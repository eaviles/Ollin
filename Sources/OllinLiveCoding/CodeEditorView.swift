import SwiftUI
import AppKit

/// The transparent code layer over the stage: an `NSTextView` in a transparent
/// scroll view, styled entirely through `EditorController`. Configuration
/// happens once in `makeNSView`; SwiftUI never owns the buffer (see
/// `EditorController`), so `updateNSView` only forwards the style knobs.
struct CodeEditorView: NSViewRepresentable {
    let controller: EditorController
    var fontSize: Double
    var backdropOpacity: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // Transparent on every layer, so only the glyph backdrop the
        // highlighter paints separates code from canvas.
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        textView.drawsBackground = false

        // Every substitution off: a smart quote or dash in source is a silent
        // compile break.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
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

        controller.attach(textView)
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        controller.configure(fontSize: fontSize, backdropOpacity: backdropOpacity)
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
    }
}
