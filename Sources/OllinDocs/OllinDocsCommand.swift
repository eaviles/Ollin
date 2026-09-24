import Darwin
import Foundation
import OllinReference

/// `ollin docs`, `ollin examples`, and `ollin api`: the written reference, the
/// examples set, and the public surface, read in the terminal out of this
/// checkout.
///
/// They live in one binary because they answer one question from three
/// directions ("what does this do", "show me one that does it", and "what is
/// it called and what does it take"), and because a single small target keeps
/// the first run a second or two rather than a framework build. It links nothing but Foundation and the two text
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
        case "api": api(arguments, options: options)
        case "site": site(arguments)
        case "completions": completions(options: options)
        case "help", "--help", "-h": printUsage()
        default: fail("unknown command \"\(command)\". Try docs, examples, api, site, or completions.")
        }
    }

    // MARK: - The shell

    /// `ollin completions`: the zsh completion function, printed. It is written
    /// from the flag table rather than kept by hand, and `Scripts/check-flags.sh`
    /// holds the checked-in copy to what this prints.
    ///
    /// `--list` is the one machine-shaped thing this binary says, and it exists
    /// for that gate: one line per flag, its scope beside it.
    static func completions(options: Options) {
        guard options.list else {
            print(ShellCompletions.zsh(), terminator: "")
            return
        }
        for flag in CommandFlag.all {
            print("\(flag.name)\t\(flag.scope.rawValue)")
        }
    }

    // MARK: - The site

    /// `ollin site [folder]`: the same pages as a website, written into a
    /// folder. The front page, the Guide, the reference, the examples with
    /// their source, and every picture they show, under one set of chrome.
    static func site(_ arguments: [String]) {
        let root = checkout()
        var output = root.appendingPathComponent(".build/site")
        var domain: String?
        var repository = "https://github.com/eaviles/Ollin"
        var branch = "main"
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--domain":
                index += 1
                if index < arguments.count { domain = arguments[index] }
            case "--repository":
                index += 1
                if index < arguments.count { repository = arguments[index] }
            case "--branch":
                index += 1
                if index < arguments.count { branch = arguments[index] }
            default:
                output = URL(fileURLWithPath: arguments[index], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardized
            }
            index += 1
        }

        let builder = SiteBuilder(root: root, repository: repository, branch: branch, domain: domain)
        do {
            let report = try builder.build(into: output)
            print("\(report.pages) pages, \(report.examples) examples, \(report.images) pictures, \(report.sections) searchable sections written to \(output.path)")
            if !report.missing.isEmpty {
                print("")
                print("\(report.missing.count) targets point at nothing in this checkout (left as written):")
                for line in report.missing { print("  " + line) }
            }
            for note in report.notes { print("note: " + note) }
            if let domain { print("CNAME: \(domain)") }
        } catch {
            fail("could not write the site: \(error.localizedDescription)")
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

    // MARK: - The public surface

    /// `ollin api <name>`: what a public name is, read from the listings under
    /// `API/`. Every declaration it names, as the listing spells it, with the
    /// doc comment above it in `Sources/` and the line it is written on; then
    /// the pages that document it and the examples that use it. A type also
    /// lists its members. A name nothing is called prints the names spelled
    /// like it instead, which answers "what is it called".
    ///
    /// Not listed means not public, so this is also the answer to whether a
    /// sketch can reach something at all.
    static func api(_ arguments: [String], options: Options) {
        let root = checkout()
        let all = APIListing.declarations(inAPI: root.appendingPathComponent("API"))
        guard !all.isEmpty else {
            fail("no listings found under \(root.appendingPathComponent("API").path). Is this a full checkout?")
        }
        guard let query = arguments.first?.trimmingCharacters(in: CharacterSet(charactersIn: ".`() ")),
              !query.isEmpty else {
            fail("name something: `ollin api drawCircle`, `ollin api Mesh.tube`, `ollin api Material`.")
        }
        if query == "init" {
            fail("name the type as well: `ollin api Vector2.init`, or `ollin api Vector2` for all of it.")
        }
        let style = options.style

        let answer = APIListing.answer(query, in: all)
        guard !answer.declarations.isEmpty else {
            guard !answer.nearby.isEmpty else {
                fail("no public name is \"\(query)\", and none is spelled like it. `ollin docs --search \(query)` reads the pages for it.")
            }
            print(style.dim("No public name is \"\(query)\". These are spelled like it:"))
            print("")
            for name in answer.nearby { print("  " + name) }
            print("")
            print(style.dim("one of them: ollin api <name>"))
            exit(1)
        }

        let shown = Array(answer.declarations.prefix(40))
        let places = SourceComments.places(of: shown, inSources: root.appendingPathComponent("Sources"))

        // One block per type the name sits on, a type's own block first.
        var order: [String] = []
        var blocks: [String: [Int]] = [:]
        for (index, declaration) in shown.enumerated() {
            let key = declaration.module + " " + declaration.qualifiedName
            if blocks[key] == nil { order.append(key) }
            blocks[key, default: []].append(index)
        }
        order.sort { a, b in
            let left = shown[blocks[a]![0]].kind == .type, right = shown[blocks[b]![0]].kind == .type
            return left != right ? left : false
        }

        for key in order {
            let indices = blocks[key]!
            let first = shown[indices[0]]
            print(style.bold(first.qualifiedName) + style.dim("  " + first.module))
            for index in indices {
                let declaration = shown[index]
                print("  " + (style.color ? style.code(APIListing.tidy(declaration.text)) : APIListing.tidy(declaration.text)))
                guard let place = places[index] else { continue }
                print("      " + style.dim("\(relative(place.file, to: root)):\(place.line)"))
                for line in place.comment.prefix(24) { print("      " + line) }
                if place.comment.count > 24 {
                    print("      " + style.dim("(\(place.comment.count - 24) more lines in the source)"))
                }
            }
            if first.kind == .type {
                members(of: first, in: all, style: style)
            }
            print("")
        }
        if answer.declarations.count > shown.count {
            print(style.dim("\(answer.declarations.count - shown.count) more declarations are named \"\(query)\"; name the type as well to narrow it: ollin api <Type>.\(first(of: query))"))
            print("")
        }

        // Where it is written about, and used. An initializer is written as
        // its type called.
        let lead = shown[0]
        let isType = lead.kind == .type
        let spelled = lead.kind == .initializer ? (lead.owner.last ?? lead.name) : lead.name
        let owners = Array(Set(shown.compactMap(\.owner.last))).sorted()
        let reach: APIReach = isType || lead.kind == .initializer ? .type
            : shown.allSatisfy { $0.owner.isEmpty || $0.owner == ["Sketch"] } ? .bare : .member
        let pages = APIUsage.pages(naming: spelled, reach: reach, owners: isType ? [] : owners,
                                   in: ReferenceLibrary.pages(inDocs: root.appendingPathComponent("Docs")))
        let examples = APIUsage.examples(using: spelled, reach: reach,
                                         in: ExampleCatalog.entries(inExamples: root.appendingPathComponent("Examples")),
                                         root: root)
        let label = { (text: String) in style.dim(text.padding(toLength: 12, withPad: " ", startingAt: 0)) }
        if pages.isEmpty {
            print("  " + label("documented") + style.dim("no page writes it as code"))
        }
        for (number, page) in pages.enumerated() {
            print("  " + label(number == 0 ? "documented" : "") + page.address)
        }
        if examples.isEmpty {
            print("  " + label("used in") + style.dim("no example"))
        }
        let room = max(20, style.width - 14)
        for (number, example) in examples.enumerated() {
            print("  " + label(number == 0 ? "used in" : "") + example.address)
            let line = example.text.count > room ? String(example.text.prefix(room - 1)) + "…" : example.text
            print("  " + label("") + style.dim(line))
        }
        if !isType, lead.kind != .initializer, !answer.nearby.isEmpty {
            print("")
            let also = answer.nearby.prefix(10).joined(separator: ", ")
            for (number, line) in Markdown.wrapped(also, width: max(20, style.width - 8)).enumerated() {
                print("  " + label(number == 0 ? "see also" : "") + style.dim(line))
            }
        }
    }

    /// A type's members: every line when there are few enough to read, and
    /// just the names when there are not.
    static func members(of type: APIDeclaration, in all: [APIDeclaration], style: TerminalStyle) {
        let members = APIListing.members(of: type, in: all)
        guard !members.isEmpty else { return }
        print("")
        guard members.count > 60 else {
            print("  " + style.dim("\(members.count) members"))
            for member in members { print("    " + APIListing.tidy(member.text)) }
            return
        }
        var seen: Set<String> = []
        let names = members.map(\.name).filter { seen.insert($0).inserted }.sorted()
        print("  " + style.dim("\(members.count) members under \(names.count) names; one of them: ollin api \(type.name).<name>"))
        for line in Markdown.wrapped(names.joined(separator: ", "), width: max(20, style.width - 4)) {
            print("    " + line)
        }
    }

    static func first(of query: String) -> String {
        String(query.split(separator: ".").last ?? Substring(query))
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

               ollin api <name>                a public name: its declarations, what the
                                               source says above each, the pages that
                                               document it, and examples that use it;
                                               `Mesh.tube` for one type's, `Material` for
                                               a whole type

               ollin site [folder]             the same pages as a website, written into
                                               a folder (default: .build/site);
                                               --domain <name> writes the CNAME for it

               ollin completions               the zsh completion function, printed;
                                               `ollin install` puts it on your fpath

        options:
          --width <n>   wrap to this many columns (default: the window, at most 100)
          --plain       no color, whatever the terminal is
          --color       color, even when the output is a pipe
          --no-pager    print straight out instead of opening a pager
        """)
    }
}
