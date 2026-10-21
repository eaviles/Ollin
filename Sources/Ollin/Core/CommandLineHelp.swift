import Foundation
internal import OllinCommandFlags

/// What a sketch run with `--help` prints: its name, how to run it, the
/// parameters it declares as `--param` takes them, and every flag a sketch
/// reads, grouped, each with its one line from the shared flag table.
enum CommandLineHelp {

    /// The help for `sketch` as it was made, never set up, so its parameters
    /// read the values their `@Param` lines declare. `arguments` is the command
    /// line as it came, whose leading words (the program and, for a host, the
    /// sketch file) make the usage line.
    @MainActor
    static func text(for sketch: Sketch, arguments: [String]) -> String {
        let name = String(describing: type(of: sketch))
        let program = arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? name
        let operands: [String] = Array(arguments.dropFirst().prefix { !$0.hasPrefix("-") })
        let usage: String = ([program] + operands).joined(separator: " ")
        return [
            "\(name), an Ollin sketch.",
            "",
            "usage: \(usage) [flags]",
            "With no flags it opens its window. With an export flag it writes the file and stops, with no window.",
            "",
            ParamListing.text(for: sketch),
            "The values are as declared. --list-params runs setup() first and shows the ones the first frame draws with.",
            "",
            CommandFlag.runUsage(),
            "",
            "Each flag in full: ollin docs Export",
        ].joined(separator: "\n")
    }
}
