import SwiftUI
import AppKit
import OllinProjects
import OllinRuntime

/// The stage when what will be written is a library rather than a sketch: the
/// file itself, colored, selectable, and read-only, on the same black the
/// running preview sits on.
///
/// A library has nothing to run, so the honest thing to show is the text that
/// will land on disk, exactly as the plan holds it. Typing a name in the
/// inspector re-plans, and the file on the stage renames itself as you type,
/// which is the same promise the running preview makes for a sketch: what you
/// watch is what you get.
struct SourceStage: NSViewRepresentable {
    /// The path the text will be written to, relative to the project. When it
    /// changes the view scrolls back to the top; when only the text changes (a
    /// name being typed) the scroll position holds.
    let path: String
    let text: String

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // Tokens colored for the black stage, the palette the performance host
    // reads code over its own visuals with.
    private static let textColor = NSColor(white: 0.92, alpha: 1)
    private static let plainColor = NSColor(white: 0.80, alpha: 1)
    private static let keywordColor = NSColor(red: 1.00, green: 0.45, blue: 0.66, alpha: 1)
    private static let typeColor = NSColor(red: 0.45, green: 0.86, blue: 1.00, alpha: 1)
    private static let stringColor = NSColor(red: 1.00, green: 0.80, blue: 0.40, alpha: 1)
    private static let numberColor = NSColor(red: 0.78, green: 0.65, blue: 1.00, alpha: 1)
    private static let commentColor = NSColor(red: 0.58, green: 0.66, blue: 0.60, alpha: 1)
    private static let attributeColor = NSColor(red: 0.55, green: 0.90, blue: 0.60, alpha: 1)

    final class Coordinator {
        var shownPath: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        textView.drawsBackground = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 0.45, green: 0.32, blue: 0.85, alpha: 0.55),
            .foregroundColor: NSColor.white,
        ]
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.textContainer?.widthTracksTextView = true

        show(in: textView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text || context.coordinator.shownPath != path else { return }
        let changedFile = context.coordinator.shownPath != path
        show(in: textView, context: context)
        if changedFile {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func show(in textView: NSTextView, context: Context) {
        guard let storage = textView.textStorage else { return }
        let swift = path.hasSuffix(".swift")
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: Self.font,
            .foregroundColor: swift ? Self.textColor : Self.plainColor,
        ]))
        // A manifest is Swift too; a README and a .gitignore are not, and
        // coloring them as if they were would be lying in small letters.
        if swift {
            for run in SwiftTokens.runs(in: text) {
                storage.addAttribute(.foregroundColor, value: Self.color(for: run.kind), range: run.range)
            }
        }
        storage.endEditing()
        context.coordinator.shownPath = path
    }

    private static func color(for kind: SwiftTokens.Kind) -> NSColor {
        switch kind {
        case .type: typeColor
        case .number: numberColor
        case .keyword: keywordColor
        case .attribute: attributeColor
        case .string: stringColor
        case .comment: commentColor
        }
    }
}

/// The files an extension package will be written as, one chip each, under the
/// stage that shows the chosen one. It sits where the 3D strip sits for the
/// same reason: what governs the stage belongs directly under it.
struct SourceFileStrip: View {
    let files: [GeneratedFile]
    @Binding var shown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Files")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Text("as they will be written")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                // The reference page is the authority on what each seam
                // promises, so the strip says where it is.
                Link(destination: Self.extensionsPage) {
                    HStack(spacing: 3) {
                        Text("Writing an extension").font(.system(size: 10))
                        SwiftUI.Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            HStack(spacing: 6) {
                ForEach(files, id: \.path) { file in
                    chip(file)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func chip(_ file: GeneratedFile) -> some View {
        let chosen = shown == file.path
        return Button { shown = file.path } label: {
            Text((file.path as NSString).lastPathComponent)
                .font(.system(size: 11, weight: chosen ? .medium : .regular, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(chosen ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(file.path)
    }

    static let extensionsPage = URL(string: "https://github.com/eaviles/Ollin/blob/main/Docs/Tools/Extensions.md")!
}
