// The names in the prose, checked against the repository.
//
// `Scripts/check-links.sh` resolves every markdown link and anchor. What it
// cannot see is a name written as prose rather than as a link, and that is
// where two shipped errors lived: `ollin docs Color#ramps` naming a heading
// that does not exist, and a "worked examples" line listing an example folder
// that does not exist.
import Foundation

struct NameProblem {
    var page: String
    var line: Int
    var message: String
}

/// `ollin docs Page#section` must resolve to a real page and a real heading.
///
/// The heading match is the reference tool's own: punctuation and backticks
/// dropped, a web anchor's dashes read as spaces, exact before loose.
func docsAnchorProblems(in shellBlocks: [Block], repo: String) -> [NameProblem] {
    var out: [NameProblem] = []
    let docsRoot = repo + "/Docs"
    let pages = (FileManager.default.enumerator(atPath: docsRoot)?
        .compactMap { $0 as? String }
        .filter { $0.hasSuffix(".md") }) ?? []

    for block in shellBlocks {
        for raw in block.body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: #"ollin docs +[^\s|>]+"#, options: .regularExpression)
            else { continue }
            let topic = String(line[range]).replacingOccurrences(of: #"ollin docs +"#, with: "",
                                                                 options: .regularExpression)
            guard topic.contains("#") else { continue }   // a whole page is matched loosely by design
            let parts = topic.components(separatedBy: "#")
            let pageName = parts[0].lowercased()
            let wanted = anchorKey(parts[1])

            let candidates = pages.filter {
                let stem = (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
                return stem.lowercased() == pageName
                    || $0.lowercased().replacingOccurrences(of: ".md", with: "") == pageName
            }
            guard let page = candidates.first else {
                out.append(NameProblem(page: block.page, line: block.line,
                                       message: "`ollin docs \(topic)`: no page called \(parts[0])"))
                continue
            }
            let text = (try? String(contentsOfFile: docsRoot + "/" + page, encoding: .utf8)) ?? ""
            let headings = text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("##") }
                .map { anchorKey($0.drop { $0 == "#" }.description) }
            let hit = headings.contains(wanted) || headings.contains { $0.contains(wanted) }
            if !hit {
                out.append(NameProblem(page: block.page, line: block.line,
                                       message: "`ollin docs \(topic)`: \(page) has no section "
                                                + "matching \"\(parts[1])\". It has: "
                                                + headings.prefix(8).joined(separator: ", ")))
            }
        }
    }
    return out
}

/// The reference tool's own key for a heading or a requested section.
func anchorKey(_ text: String) -> String {
    text.lowercased()
        .replacingOccurrences(of: "-", with: " ")
        .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
        .joined()
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// A line that links to an example folder also names its neighbors in backticks,
/// as prose rather than as links. Those names are checked against the folder.
func exampleNameProblems(page: String, text: String, repo: String) -> [NameProblem] {
    var out: [NameProblem] = []
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
        guard let range = line.range(of: #"\(\.\./Examples/([A-Za-z0-9]+)/\)"#,
                                     options: .regularExpression) else { continue }
        let group = String(line[range])
            .replacingOccurrences(of: "(../Examples/", with: "")
            .replacingOccurrences(of: "/)", with: "")
        let folder = repo + "/Examples/" + group
        let present = Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
        guard !present.isEmpty else { continue }
        // Every backticked bare word on the line is read as an example name. A
        // name with a dot or a slash in it is a file or a path, not one of these.
        let names = line.matches(of: try! Regex(#"`([A-Z][A-Za-z0-9]+)`"#))
            .map { String($0.output[1].substring ?? "") }
        for name in names where !present.contains(name) {
            out.append(NameProblem(page: page, line: index + 1,
                                   message: "`\(name)` is not in Examples/\(group)/"))
        }
    }
    return out
}
