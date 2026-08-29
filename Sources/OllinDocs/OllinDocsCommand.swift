import Darwin
import Foundation
import OllinReference

/// `ollin docs` and `ollin examples`: the written reference and the examples
/// set, read in the terminal out of this checkout.
///
/// Both commands live in one binary because they answer one question from two
/// directions ("what does this do" and "show me one that does it"), and
/// because a single small target keeps the first run a second or two rather
/// than a framework build. It links nothing but Foundation and the two text
/// targets, exactly as the project generator's command line does.
///
/// What it prints is written for a person and nothing else: no machine format,
/// and no index for another program to read. That is a deliberate line rather
/// than an omission. Serving a page somebody asked for takes no position on a
/// question this project has not settled yet, and a format made for something
/// else to consume would take one.
@main
struct OllinDocsCommand {

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            exit(2)
        }
        arguments.removeFirst()

        let options = Options(taking: &arguments)
        if options.help {
            printUsage()
            exit(0)
        }

        switch command {
        case "docs": docs(arguments, options: options)
        case "examples": examples(arguments, options: options)
        case "help", "--help", "-h": printUsage()
        default: fail("unknown command \"\(command)\". Try docs or examples.")
        }
    }

    // MARK: - The reference

    static func docs(_ arguments: [String], options: Options) {
        let root = checkout()
        let folder = root.appendingPathComponent("Docs")
        let pages = ReferenceLibrary.pages(inDocs: folder)
        guard !pages.isEmpty else {
            fail("no pages found under \(folder.path). Is this a full checkout?")
        }
        let style = options.style

        if options.list {
            for page in pages { print(page.topic) }
            return
        }

        if let query = options.search {
            report(ReferenceSearch.hits(for: query, in: pages), for: query, style: style)
            return
        }

        guard let asked = arguments.first else {
            catalog(pages, order: ReferenceLibrary.groups(inDocs: folder), style: style)
            return
        }

        // `Color#ramps` asks for one section of one page, which is what a
        // reader wants as soon as they know where they are going.
        let parts = asked.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let topic = String(parts[0])
        let wanted = parts.count > 1 ? String(parts[1]) : nil

        switch PageQuery.resolve(topic, in: pages) {
        case .one(let page):
            show(page, section: wanted, style: style, root: root)
        case .several(let matches):
            print(style.bold("\"\(topic)\" matches \(matches.count) pages:"))
            print("")
            rows(matches.map { (it: $0.topic, says: $0.summary) }, style: style, indent: 2)
            exit(1)
        case .none:
            let hits = ReferenceSearch.hits(for: topic, in: pages)
            guard !hits.isEmpty else {
                fail("nothing in the reference matches \"\(topic)\". `ollin docs` lists every page.")
            }
            print(style.dim("No page is called \"\(topic)\", so here is where it is mentioned."))
            report(hits, for: topic, style: style)
            exit(1)
        }
    }

    static func show(_ page: ReferencePage, section: String?, style: TerminalStyle, root: URL) {
        guard let text = try? String(contentsOf: page.url, encoding: .utf8) else {
            fail("could not read \(page.url.path).")
        }
        var body = text
        if let section {
            guard let slice = Markdown.section(section, in: text) else {
                fail("\"\(page.topic)\" has no section called \"\(section)\". It has: "
                     + Markdown.headings(in: text).joined(separator: ", "))
            }
            body = slice
        }
        print(Markdown.render(body, style: style))
        print("")
        print(style.dim(relative(page.url, to: root)))
    }

    static func catalog(_ pages: [ReferencePage], order groups: [String], style: TerminalStyle) {
        let rank = Dictionary(groups.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = pages.sorted { a, b in
            let left = rank[a.group] ?? groups.count
            let right = rank[b.group] ?? groups.count
            if left != right { return left < right }
            if a.group != b.group { return a.group < b.group }
            return a.topic < b.topic
        }
        rows(sorted.map { (it: $0.topic, says: $0.summary) },
             style: style,
             indent: 2,
             groups: sorted.map(\.group))
        print("")
        print(style.dim("one page: ollin docs <topic>    one section: ollin docs <topic>#<heading>"))
    }

    static func report(_ hits: [SearchHit], for query: String, style: TerminalStyle) {
        guard !hits.isEmpty else {
            fail("nothing in the reference mentions \"\(query)\".")
        }
        var topic = ""
        for hit in hits {
            if hit.page.topic != topic {
                topic = hit.page.topic
                print("")
                print(style.bold(topic))
            }
            // The heading leads, because it says where in the page the line
            // sits, and a long line would push it off the end.
            let place = hit.section.isEmpty ? "" : style.dim("(\(hit.section)) ")
            let lines = Markdown.wrapped(Markdown.plain(hit.text), width: max(20, style.width - 8))
            for (number, line) in lines.enumerated() {
                print(number == 0
                      ? "  " + style.dim("\(hit.line):") + " " + place + line
                      : "      " + line)
            }
        }
        print("")
        print(style.dim("read one: ollin docs <topic>"))
    }

    // MARK: - The examples

    static func examples(_ arguments: [String], options: Options) {
        let root = checkout()
        let folder = root.appendingPathComponent("Examples")
        let entries = ExampleCatalog.entries(inExamples: folder)
        guard !entries.isEmpty else {
            fail("no examples found under \(folder.path). Is this a full checkout?")
        }
        let style = options.style

        if options.list {
            for entry in entries { print(entry.path) }
            return
        }

        guard let filter = options.search ?? arguments.first else {
            rows(entries.map { (it: $0.name, says: $0.summary) },
                 style: style,
                 indent: 2,
                 groups: entries.map(\.group))
            print("")
            print(style.dim("one of them: ollin examples <name>    its code: ollin examples <name> --source"))
            return
        }

        let matches = ExampleCatalog.matches(filter, in: entries)
        guard !matches.isEmpty else {
            fail("no example matches \"\(filter)\". `ollin examples` lists them all.")
        }

        if options.source {
            guard matches.count == 1 else {
                print(style.bold("\"\(filter)\" matches \(matches.count) examples. Name one to read it:"))
                print("")
                rows(matches.map { (it: $0.path, says: $0.summary) }, style: style, indent: 2)
                exit(1)
            }
            guard let text = try? String(contentsOf: matches[0].sketch, encoding: .utf8) else {
                fail("could not read \(matches[0].sketch.path).")
            }
            print(style.dim(relative(matches[0].sketch, to: root)))
            print("")
            print(text)
            return
        }

        if matches.count == 1 {
            show(matches[0], style: style, root: root)
            return
        }
        print(style.bold("\(matches.count) examples match \"\(filter)\":"))
        print("")
        rows(matches.map { (it: $0.path, says: $0.summary) }, style: style, indent: 2)
        print("")
        print(style.dim("one of them: ollin examples <name>"))
    }

    static func show(_ example: ExampleEntry, style: TerminalStyle, root: URL) {
        print(style.heading(example.path))
        if !example.summary.isEmpty {
            print("")
            for line in Markdown.wrapped(example.summary, width: style.width) { print(line) }
        }
        print("")
        var facts: [(String, String)] = [("sketch", relative(example.sketch, to: root))]
        if !example.modules.isEmpty {
            facts.append(("imports", example.modules.joined(separator: ", ")))
        }
        if !example.resources.isEmpty {
            facts.append(("material", example.resources.joined(separator: ", ")))
        }
        facts.append(("run", "swift run --package-path Examples \(example.target)"))
        facts.append(("read", "ollin examples \(example.path) --source"))
        for (label, value) in facts {
            print("  " + style.dim(label.padding(toLength: 9, withPad: " ", startingAt: 0)) + value)
        }
    }

    // MARK: - Printing

    /// A name in one column and what it is in the next, wrapped under itself.
    ///
    /// The name column is measured over every row at once, so a listing lines
    /// up down the whole page rather than per group.
    static func rows(_ items: [(it: String, says: String)],
                     style: TerminalStyle,
                     indent: Int = 0,
                     groups: [String] = []) {
        let lead = String(repeating: " ", count: indent)
        let column = min(items.map(\.it.count).max() ?? 0, max(12, style.width / 3))
        var group: String?
        for (number, item) in items.enumerated() {
            if number < groups.count, groups[number] != group {
                group = groups[number]
                print("")
                print(style.bold(group ?? ""))
            }
            guard !item.says.isEmpty else {
                print(lead + item.it)
                continue
            }
            let width = max(20, style.width - indent - column - 2)
            let lines = Markdown.wrapped(item.says, width: width)
            let under = lead + String(repeating: " ", count: column + 2)
            // A name wider than the column takes the line to itself. Padding
            // it out instead would start its first line further right than the
            // ones wrapping under it, and the block would step sideways.
            if item.it.count > column {
                print(lead + item.it)
                for line in lines { print(under + line) }
                continue
            }
            let padded = item.it + String(repeating: " ", count: column - item.it.count)
            print(lead + padded + "  " + (lines.first ?? ""))
            for line in lines.dropFirst() { print(under + line) }
        }
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let parts = url.standardized.resolvingSymlinksInPath().pathComponents
        let rootParts = root.standardized.resolvingSymlinksInPath().pathComponents
        guard parts.count > rootParts.count,
              Array(parts.prefix(rootParts.count)) == rootParts else { return url.path }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }

    // MARK: - Options

    struct Options {
        var list = false
        var source = false
        var help = false
        var search: String?
        var style: TerminalStyle

        /// Takes the options out of the arguments and leaves the rest.
        init(taking arguments: inout [String]) {
            var color = isatty(1) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            var width = terminalWidth()
            var rest: [String] = []
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--list": list = true
                case "--source", "--code": source = true
                case "--color": color = true
                case "--plain", "--no-color": color = false
                // The shell reads this one and never passes it on. It is
                // accepted here so running the binary directly with it does
                // not go looking for a page by that name.
                case "--no-pager": break
                case "--help", "-h": help = true
                case "--search", "-s":
                    index += 1
                    if index < arguments.count { search = arguments[index] }
                case "--width":
                    index += 1
                    if index < arguments.count, let value = Int(arguments[index]) { width = value }
                default: rest.append(arguments[index])
                }
                index += 1
            }
            arguments = rest
            style = TerminalStyle(color: color, width: width)
        }
    }

    /// How wide the window is.
    ///
    /// Asked of the error stream as well as the output one, because the output
    /// is often a pipe into a pager while the terminal is still right there on
    /// the other stream. Capped, because prose in one very long column is
    /// harder to read than prose in a comfortable one.
    static func terminalWidth() -> Int {
        for descriptor in [Int32(1), Int32(2)] {
            var size = winsize()
            if ioctl(descriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
                return min(Int(size.ws_col), 100)
            }
        }
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"], let value = Int(columns) {
            return min(value, 100)
        }
        return 80
    }

    // MARK: - Finding the checkout

    static func checkout() -> URL {
        guard let root = frameworkRoot() else {
            fail("could not find the Ollin folder from this binary.")
        }
        return root
    }

    /// Walk up from this binary to the folder it was built in, the way the
    /// generator's command line does, so the reference is the one belonging to
    /// this copy of the framework.
    static func frameworkRoot() -> URL? {
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8),
               text.contains("name: \"Ollin\"") {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("ollin: " + message + "\n").utf8))
        exit(2)
    }

    static func printUsage() {
        print("""
        usage: ollin docs                      every page, grouped as the reference groups them
               ollin docs <topic>              one page: a name, a path, or part of either
               ollin docs <topic>#<heading>    one section of one page
               ollin docs --search <text>      every place the reference says it
               ollin docs --list               one topic per line

               ollin examples                  every example, grouped by folder
               ollin examples <filter>         the ones matching a name, folder, or description
               ollin examples <name> --source  print the sketch itself
               ollin examples --list           one path per line

        options:
          --width <n>   wrap to this many columns (default: the window, at most 100)
          --plain       no color, whatever the terminal is
          --color       color, even when the output is a pipe
          --no-pager    print straight out instead of opening a pager
        """)
    }
}
