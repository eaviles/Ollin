import AppKit
import OllinRuntime

/// The completion list under the caret: the names the toolchain's own
/// completion service offers for the word being typed, shown in a small list
/// inside the editor's view, taken with Return or Tab. The list is a subview
/// of the editor's container rather than a window of its own, so it rides
/// the stage into fullscreen, hides with the code, and never floats.
///
/// How it behaves, so a set never has to think about it:
/// - Typing a word or a member dot opens the list (a preference; Escape always
///   opens it). More letters filter the same session, which costs about a
///   millisecond; a new word opens a new one. Nothing is asked while the caret
///   sits outside a word, and an empty answer shows nothing rather than an
///   empty panel.
/// - Escape closes it, and opens it when it is closed, so Escape never leaves
///   fullscreen by accident mid-set. Up and Down move, Return and Tab take
///   the row; any other key goes to the editor as typed, so the list never
///   steals a character.
/// - A taken row lands as its call pattern with each parameter as a
///   placeholder, the first one selected. Tab walks the placeholders; a
///   placeholder left behind names its own line in the diagnostics strip at
///   the next evaluation, since the compiler recognizes the spelling.
/// - Every request runs on its own queue and never on the main thread, and a
///   result that arrives after the caret has moved on is dropped, so the stage
///   never waits on the service and the list never shows stale rows. The
///   first request the service ever answers costs seconds while it reads the
///   framework's modules, so the session warms it up at launch.
@MainActor
final class CompletionController {
    /// Where a request's compiler arguments and the buffer's name come from,
    /// set by the session (they follow the open document).
    var request: (@MainActor () -> (name: String, arguments: [String])?)?
    /// Whether a word or a dot opens the list on its own; Escape opens it either way.
    var completesAsYouType = true
    var fontSize: Double = 15 {
        didSet { list.fontSize = fontSize }
    }

    let list = CompletionListView()
    private(set) weak var textView: NSTextView?
    private weak var host: NSView?
    private let queue = DispatchQueue(label: "ollin.livecoding.completion", qos: .userInitiated)
    private let engine = Engine()
    /// The session on screen, if any.
    private var open: Open?
    /// Bumped by every request and every dismissal; a response carrying an
    /// older number is dropped.
    private var generation = 0
    /// The text change a taken row makes is not a keystroke to complete on.
    private var ignoreNextChange = false
    /// Removed in `deinit`, which is not isolated; the token is never read anywhere else.
    nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?

    private struct Open {
        let session: CodeCompleter.Session
        /// The UTF-16 offset of the completion point, where the word begins.
        let wordStart: Int
        /// The text before the point when the session opened; an edit there
        /// moves every offset, so the session is reopened rather than updated.
        let head: String
    }

    /// The completer, loaded once on the queue and touched only there.
    private final class Engine: @unchecked Sendable {
        private var completer: CodeCompleter?
        private var tried = false

        func load() -> CodeCompleter? {
            if !tried {
                tried = true
                completer = CodeCompleter.load()
            }
            return completer
        }
    }

    var isShowing: Bool { !list.isHidden }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    func attach(textView: NSTextView, host: NSView) {
        self.textView = textView
        self.host = host
        list.fontSize = fontSize
        list.onAccept = { [weak self] in self?.accept() }
        host.addSubview(list)
        // A line scrolled under the list moves the caret; the list follows.
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.place() }
            }
        }
    }

    /// Pay the service's first-request cost now, off the main thread, so the
    /// first dot typed in a set answers at once.
    func warmUp() {
        guard let request = request?() else { return }
        let text = textView?.string ?? ""
        queue.async { [engine] in
            guard let completer = engine.load() else { return }
            let session = CodeCompleter.Session(name: request.name, offset: 0)
            _ = try? completer.open(session, source: text, arguments: request.arguments, filter: "", limit: 1)
            completer.close(session)
        }
    }

    // MARK: - Editor events

    /// The buffer changed under the caret (the delegate's text-change hook).
    func textDidChange() {
        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        guard let textView else { return }
        let text = textView.string
        let caret = textView.selectedRange().location
        if CompletionText.isMemberAccess(in: text, caret: caret) {
            guard completesAsYouType || open != nil else { return }
            openSession(at: caret, filter: "")
            return
        }
        let start = CompletionText.wordStart(in: text, caret: caret)
        guard start < caret else {
            dismiss()
            return
        }
        let prefix = CompletionText.prefix(in: text, caret: caret)
        if let open, open.wordStart == start, text.utf16.count >= start,
           String(text.utf16.prefix(start)) == open.head {
            update(filter: prefix)
        } else if completesAsYouType || open != nil {
            openSession(at: start, filter: prefix)
        }
    }

    /// The caret moved (the delegate's selection hook): a caret that left the
    /// word the list is for closes it.
    func selectionDidChange() {
        guard let open, let textView else { return }
        let range = textView.selectedRange()
        let text = textView.string
        let caret = range.location
        let start = CompletionText.isMemberAccess(in: text, caret: caret) && caret == open.wordStart
            ? caret : CompletionText.wordStart(in: text, caret: caret)
        if range.length > 0 || start != open.wordStart { dismiss() }
    }

    /// Escape and the menu: close the list, or open it where the caret is.
    func toggle() {
        if isShowing { dismiss() } else { trigger() }
    }

    /// Open the list at the caret whatever the preference says: the word so
    /// far, the members after a dot, or everything in scope.
    func trigger() {
        guard let textView else { return }
        let text = textView.string
        let caret = textView.selectedRange().location
        if CompletionText.isMemberAccess(in: text, caret: caret) {
            openSession(at: caret, filter: "")
        } else {
            let start = CompletionText.wordStart(in: text, caret: caret)
            openSession(at: start, filter: CompletionText.prefix(in: text, caret: caret))
        }
    }

    /// A key command the text view is about to run. `true` when the list took
    /// it; anything else reaches the editor untouched.
    func handle(_ command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.moveUp(_:)) where isShowing:
            list.moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)) where isShowing:
            list.moveSelection(by: 1)
            return true
        case #selector(NSResponder.pageUp(_:)) where isShowing, #selector(NSResponder.scrollPageUp(_:)) where isShowing:
            list.moveSelection(by: -list.visibleRows)
            return true
        case #selector(NSResponder.pageDown(_:)) where isShowing, #selector(NSResponder.scrollPageDown(_:)) where isShowing:
            list.moveSelection(by: list.visibleRows)
            return true
        case #selector(NSResponder.insertNewline(_:)) where isShowing:
            accept()
            return true
        case #selector(NSResponder.insertTab(_:)):
            if isShowing {
                accept()
                return true
            }
            return jumpToPlaceholder()
        case #selector(NSResponder.cancelOperation(_:)):
            toggle()
            return true
        case #selector(NSResponder.complete(_:)):
            trigger()
            return true
        default:
            return false
        }
    }

    /// Close the list and end its session.
    func dismiss() {
        generation += 1
        list.isHidden = true
        guard let open else { return }
        self.open = nil
        let session = open.session
        queue.async { [engine] in
            engine.load()?.close(session)
        }
    }

    /// Select the next placeholder after the caret, wrapping to the first;
    /// `false` when the buffer holds none, so Tab stays a tab.
    @discardableResult
    func jumpToPlaceholder() -> Bool {
        guard let textView else { return false }
        let selection = textView.selectedRange()
        guard let next = CompletionText.placeholder(
            in: textView.string, after: selection.location + selection.length) else { return false }
        textView.setSelectedRange(next)
        textView.scrollRangeToVisible(next)
        return true
    }

    // MARK: - Sessions

    private func openSession(at wordStart: Int, filter: String) {
        guard let textView, let request = request?() else { return }
        let text = textView.string
        guard wordStart <= text.utf16.count else { return }
        let session = CodeCompleter.Session(
            name: request.name, offset: CompletionText.utf8Offset(of: wordStart, in: text))
        let previous = open?.session
        open = Open(session: session, wordStart: wordStart, head: String(text.utf16.prefix(wordStart)) ?? "")
        generation += 1
        let generation = generation
        queue.async { [engine] in
            guard let completer = engine.load() else { return }
            if let previous { completer.close(previous) }
            let rows = (try? completer.open(session, source: text, arguments: request.arguments, filter: filter)) ?? []
            Task { @MainActor in self.show(rows, generation: generation) }
        }
    }

    private func update(filter: String) {
        guard let open, let textView, let request = request?() else { return }
        let text = textView.string
        generation += 1
        let generation = generation
        queue.async { [engine] in
            guard let completer = engine.load() else { return }
            let rows: [CodeCompleter.Completion]
            if let filtered = try? completer.update(open.session, filter: filter) {
                rows = filtered
            } else {
                // The service lost the session (it was restarted, or it timed
                // the session out); the same point opens again.
                rows = (try? completer.open(open.session, source: text, arguments: request.arguments, filter: filter)) ?? []
            }
            Task { @MainActor in self.show(rows, generation: generation) }
        }
    }

    private func show(_ rows: [CodeCompleter.Completion], generation: Int) {
        guard generation == self.generation, open != nil else { return }
        guard !rows.isEmpty else {
            list.isHidden = true
            return
        }
        list.show(rows)
        list.isHidden = false
        place()
    }

    /// Put the list under the word's first character, or above the line when
    /// the stage has no room below, and inside the editor either way.
    private func place() {
        guard isShowing, let textView, let host, let open, let window = textView.window else { return }
        let onScreen = textView.firstRect(forCharacterRange: NSRange(location: open.wordStart, length: 0),
                                          actualRange: nil)
        let inHost = host.convert(window.convertFromScreen(onScreen), from: nil)
        // Wide enough for a long signature, never a bar across the stage; a
        // longer row ends in an ellipsis.
        let size = list.preferredSize(maxWidth: min(host.bounds.width - 24, 720))
        var origin = CGPoint(x: inHost.minX - 8, y: inHost.maxY + 3)
        if origin.y + size.height > host.bounds.height - 6 {
            origin.y = inHost.minY - 3 - size.height
        }
        origin.x = max(6, min(origin.x, host.bounds.width - size.width - 6))
        origin.y = max(6, origin.y)
        list.frame = CGRect(origin: origin, size: size)
    }

    /// Replace the word with the selected row's call pattern and select its
    /// first placeholder. One ordinary edit, so undo takes it back whole.
    private func accept() {
        guard let textView, let open, let item = list.selectedItem else { return }
        let text = textView.string
        let caret = textView.selectedRange().location
        var start = open.wordStart
        if item.bytesToErase > 0 {
            start = CompletionText.utf16Offset(ofUTF8: open.session.offset - item.bytesToErase, in: text)
        }
        let range = NSRange(location: start, length: max(0, caret - start))
        ignoreNextChange = true
        dismiss()
        textView.setSelectedRange(range)
        textView.insertText(item.insertion, replacementRange: range)
        let end = start + (item.insertion as NSString).length
        if let first = CompletionText.placeholder(in: textView.string, after: start), first.location < end {
            textView.setSelectedRange(first)
        } else {
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

/// The list itself: a dark rounded panel of rows in the editor's own type,
/// the selected row in the editor's selection color. It refuses the keyboard
/// (the text view keeps it) and accepts a row on a double click.
@MainActor
final class CompletionListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var fontSize: Double = 15 {
        didSet {
            table.rowHeight = rowHeight
            table.reloadData()
        }
    }
    var onAccept: (@MainActor () -> Void)?
    private(set) var items: [CodeCompleter.Completion] = []

    private let scroll = NSScrollView()
    private let table = CompletionTable()
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("completion")

    private var rowHeight: CGFloat { CGFloat(fontSize) + 10 }
    private var font: NSFont { .monospacedSystemFont(ofSize: max(fontSize - 1, 9), weight: .regular) }
    /// How many rows fit before the list scrolls.
    var visibleRows: Int { 8 }

    var selectedItem: CodeCompleter.Completion? {
        let row = table.selectedRow
        return row >= 0 && row < items.count ? items[row] : nil
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 0.93).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor

        let column = NSTableColumn(identifier: Self.rowIdentifier)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.style = .fullWidth
        table.rowHeight = rowHeight
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        table.sizeLastColumnToFit()
    }

    func show(_ items: [CodeCompleter.Completion]) {
        self.items = items
        table.reloadData()
        guard !items.isEmpty else { return }
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let next = max(0, min(items.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    /// The size the rows want: as wide as the widest of the first rows, within
    /// bounds, and as tall as the rows that fit before scrolling.
    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let rows = min(items.count, visibleRows)
        let widest = items.prefix(40).map { attributedRow($0).size().width }.max() ?? 200
        let width = min(max(widest + 30, 240), max(maxWidth, 120))
        return NSSize(width: width, height: CGFloat(rows) * rowHeight + 8)
    }

    @objc private func rowDoubleClicked() {
        guard selectedItem != nil else { return }
        onAccept?()
    }

    // MARK: - Rows

    private static let glyphColor = NSColor(white: 1, alpha: 0.42)
    private static let nameColor = NSColor(white: 0.97, alpha: 1)
    private static let detailColor = NSColor(white: 1, alpha: 0.66)
    private static let typeColor = NSColor(white: 1, alpha: 0.42)

    /// `f  drawCircle(x: Double, y: Double, radius: Double)  Void`: a kind
    /// glyph, the name bright, its parameters a shade dimmer, the type dim.
    private func attributedRow(_ item: CodeCompleter.Completion) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let base: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let row = NSMutableAttributedString()
        func append(_ text: String, _ color: NSColor) {
            row.append(NSAttributedString(string: text, attributes: base.merging([.foregroundColor: color]) { $1 }))
        }
        append(Self.glyph(for: item.kind) + "  ", Self.glyphColor)
        let label = item.label
        if let paren = label.firstIndex(of: "(") {
            append(String(label[..<paren]), Self.nameColor)
            append(String(label[paren...]), Self.detailColor)
        } else {
            append(label, Self.nameColor)
        }
        if !item.typeName.isEmpty, item.typeName != "Void" {
            append("  " + item.typeName, Self.typeColor)
        }
        return row
    }

    private static func glyph(for kind: CodeCompleter.Kind) -> String {
        switch kind {
        case .function: "f"
        case .initializer: "i"
        case .property: "v"
        case .type: "T"
        case .enumCase: "c"
        case .keyword: "k"
        case .other: "·"
        }
    }

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            guard row < items.count else { return nil }
            let cell: NSTableCellView
            if let reused = table.makeView(withIdentifier: Self.rowIdentifier, owner: nil) as? NSTableCellView,
               let field = reused.textField {
                cell = reused
                field.attributedStringValue = attributedRow(items[row])
            } else {
                cell = NSTableCellView()
                cell.identifier = Self.rowIdentifier
                let field = NSTextField(labelWithAttributedString: attributedRow(items[row]))
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(field)
                cell.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            return cell
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        MainActor.assumeIsolated { CompletionRowView() }
    }
}

/// A table that leaves the keyboard with the text view, whatever is clicked.
private final class CompletionTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

/// The selected row: the editor's own selection color, rounded, inset.
private final class CompletionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor(red: 0.45, green: 0.32, blue: 0.85, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}
