import Foundation
@testable import OllinReference
import Testing

/// The table of flags the ollin command takes, and the zsh function written
/// from it. `Scripts/check-flags.sh` holds the table against the code that
/// reads a command line; these hold the table against itself, which is the half
/// a gate over the tree cannot see.
struct CommandFlagsTests {

    /// A flag can sit in two scopes and mean two things there, but never twice
    /// in one: a shell offered the same flag twice would show it twice.
    @Test func noFlagIsListedTwiceInOneScope() {
        var seen: Set<String> = []
        for flag in CommandFlag.all {
            let key = flag.scope.rawValue + " " + flag.name
            #expect(!seen.contains(key), "\(flag.name) is listed twice in \(flag.scope.rawValue)")
            seen.insert(key)
        }
    }

    /// Each summary is a menu row: something to read, on one line, with no full
    /// stop and no capital to start it.
    @Test func everySummaryReadsAsAMenuRow() {
        for flag in CommandFlag.all {
            #expect(flag.name.hasPrefix("--"))
            #expect(!flag.summary.isEmpty, "\(flag.name) says nothing")
            #expect(!flag.summary.hasSuffix("."), "\(flag.name) ends in a full stop")
            #expect(!flag.summary.contains("\n"), "\(flag.name) runs to a second line")
            #expect(flag.summary.first?.isUppercase == false, "\(flag.name) starts with a capital")
        }
    }

    /// The scope a flag is typed in is the scope it completes in, and the ones
    /// a host spells for itself complete nowhere.
    @Test func everyCompletableFlagIsOfferedAndNoInternalOneIs() {
        let zsh = ShellCompletions.zsh()
        for flag in CommandFlag.completable {
            #expect(zsh.contains("'" + flag.name + "["), "\(flag.name) is not offered")
        }
        for flag in CommandFlag.all where flag.scope == .internalUse {
            #expect(!zsh.contains("'" + flag.name + "["), "\(flag.name) is offered and should not be")
        }
        #expect(!CommandFlag.inScope(.run).isEmpty)
        #expect(!CommandFlag.inScope(.internalUse).isEmpty)
    }

    /// What follows a flag is what the shell is told to offer: a file, a folder,
    /// a word to read, or nothing. A value the flag may be left without is a
    /// different specification, or offering it would make it required.
    @Test func whatFollowsAFlagIsSpelledTheWayZshReadsIt() {
        let zsh = ShellCompletions.zsh()
        #expect(zsh.contains("'--export[write one frame as a PNG]:file:_files'"))
        #expect(zsh.contains("'--in[where to put it]:directory:_files -/'"))
        #expect(zsh.contains("'--denoise[filter the grain out of a path-traced render]'"))
        #expect(zsh.contains("'--rehearse[lay the wall out as N windows on this desk]::N:'"))
    }

    /// An apostrophe in a summary would end the quoted string it sits in, and a
    /// bracket would end the description early. Both are the kind of thing that
    /// breaks a shell at somebody's prompt rather than in a build.
    @Test func aSummaryCannotBreakTheQuotingAroundIt() {
        let zsh = ShellCompletions.zsh()
        for line in zsh.split(separator: "\n") where line.contains("[") && line.contains("]") {
            let description = line.drop { $0 != "[" }.dropFirst().prefix { $0 != "]" }
            // The only apostrophe allowed is the one that closes the quoting and
            // opens it again; anything else would end the string early.
            let bare = description.replacingOccurrences(of: "'\\''", with: "")
            #expect(!bare.contains("'"), "a bare apostrophe survived into \(line)")
        }
        #expect(zsh.contains("this machine'\\''s GPU"))   // the quote, closed and reopened
    }

    /// Every subcommand the script dispatches has a branch, and the run form is
    /// the one that needs no name of its own.
    @Test func everySubcommandIsOffered() {
        let zsh = ShellCompletions.zsh()
        for command in ["new", "generate", "phone", "check", "docs", "examples",
                        "site", "doctor", "completions", "install", "help"] {
            #expect(zsh.contains("'" + command + ":"), "\(command) is not offered")
        }
        #expect(zsh.hasPrefix("#compdef ollin"))
        #expect(zsh.hasSuffix("_ollin \"$@\"\n"))
    }
}
