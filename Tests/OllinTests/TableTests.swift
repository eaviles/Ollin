import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `Table`. The published CSV description supplies most of
/// these: a quoted cell may hold the separator, a line break, and doubled quotes
/// standing for one. The rest pin the tolerances a file in the wild needs (a
/// byte-order mark, mixed line endings, blank lines, ragged rows) and the two
/// guesses the reader makes when it isn't told (which character separates the
/// cells, and whether the first row names them). No GPU.
@Suite @MainActor
struct TableTests {

    // MARK: The described format

    /// The plain case: a header names the columns and the rows read by name.
    @Test func readsAHeaderAndItsRows() throws {
        let table = try #require(Table(text: "city,pop\nAustin,961\nOslo,709\n"))
        #expect(table.columns == ["city", "pop"])
        #expect(table.count == 2)
        #expect(table[0]["city"] == "Austin")
        #expect(table[1].number("pop") == 709)
    }

    /// A quoted cell may hold the separator, which is the whole reason quoting
    /// exists. Splitting on commas without tracking quotes gets this wrong.
    @Test func aQuotedCellHoldsTheSeparator() throws {
        let table = try #require(Table(text: "name,where\nAda,\"London, England\"\n"))
        #expect(table[0]["where"] == "London, England")
        #expect(table[0].cells.count == 2)
    }

    /// A quoted cell may span lines. The record ends at the newline *after* the
    /// closing quote, not the one inside it.
    @Test func aQuotedCellHoldsALineBreak() throws {
        let table = try #require(Table(text: "id,note\n1,\"first\nsecond\"\n2,plain\n"))
        #expect(table.count == 2)
        #expect(table[0]["note"] == "first\nsecond")
        #expect(table[1]["note"] == "plain")
    }

    /// Two quotes inside a quoted cell stand for one. This is the format's own
    /// escape, and the only one it has: a backslash means nothing here.
    @Test func doubledQuotesStandForOne() throws {
        let table = try #require(Table(text: "line\n\"She said \"\"Hi\"\"\"\n"))
        #expect(table[0][0] == "She said \"Hi\"")
    }

    /// A backslash before a quote is not an escape, so it stays a backslash.
    @Test func aBackslashIsNotAnEscape() throws {
        let table = try #require(Table(text: "line\n\"a\\b\"\n"))
        #expect(table[0][0] == "a\\b")
    }

    // MARK: What files in the wild do

    /// A spreadsheet writes a byte-order mark ahead of the first byte. Left in,
    /// it rides into the first column's name, where nothing shows it and every
    /// lookup of that name fails.
    @Test func aByteOrderMarkDoesNotJoinTheFirstColumnName() throws {
        let table = try #require(Table(text: "\u{FEFF}city,pop\nOslo,709\n"))
        #expect(table.columns.first == "city")
        #expect(table[0]["city"] == "Oslo")
    }

    /// Every line ending in use ends one record, and a carriage return followed
    /// by a newline ends one rather than two.
    @Test func everyLineEndingEndsOneRecord() throws {
        for ending in ["\n", "\r\n", "\r"] {
            let text = "a,b\(ending)1,2\(ending)3,4\(ending)"
            let table = try #require(Table(text: text))
            #expect(table.count == 2, "ending \(ending.debugDescription)")
            #expect(table[1]["b"] == "4", "ending \(ending.debugDescription)")
        }
    }

    /// A trailing newline and a blank line in the middle are both nothing, not
    /// an empty row.
    @Test func blankLinesAreNotRows() throws {
        let table = try #require(Table(text: "a,b\n1,2\n\n3,4\n\n"))
        #expect(table.count == 2)
    }

    /// A file with no trailing newline still hands over its last row.
    @Test func theLastRowNeedsNoNewline() throws {
        let table = try #require(Table(text: "a,b\n1,2"))
        #expect(table.count == 1)
        #expect(table[0]["b"] == "2")
    }

    /// Rows of uneven length stay uneven. A cell that isn't there reads as
    /// nothing rather than shifting the ones that are.
    @Test func raggedRowsStayRagged() throws {
        let table = try #require(Table(text: "a,b,c\n1,2,3\n4,5\n"))
        #expect(table[1].cells.count == 2)
        #expect(table[1]["b"] == "5")
        #expect(table[1]["c"] == nil)
    }

    /// A column the table doesn't have reads as nothing, and so does a position
    /// past the end of a row.
    @Test func whatIsNotThereReadsAsNothing() throws {
        let table = try #require(Table(text: "a\n1\n"))
        #expect(table[0]["missing"] == nil)
        #expect(table[0][7] == nil)
        #expect(table[0].number("missing") == nil)
    }

    /// `a, b` is written by people who mean `b`, so an unquoted cell is trimmed.
    /// Quoting is how a file says it means the spaces, so a quoted cell is not,
    /// including the space before its opening quote.
    @Test func onlyUnquotedCellsAreTrimmed() throws {
        let table = try #require(Table(text: "a,b\n  x  , \"  y  \" \n"))
        #expect(table[0]["a"] == "x")
        #expect(table[0]["b"] == "  y  ")
    }

    /// A repeated column name resolves to the first one, which is the one a
    /// person pointing at the header means.
    @Test func aRepeatedColumnNameResolvesToTheFirst() throws {
        let table = try #require(Table(text: "v,v\n1,2\n"))
        #expect(table[0]["v"] == "1")
    }

    // MARK: The two guesses

    /// The separator is counted off the first line, so a tab-separated or
    /// semicolon-separated file reads without being told.
    @Test func theSeparatorIsSniffed() throws {
        let tsv = try #require(Table(text: "a\tb\n1\t2\n"))
        #expect(tsv.columns == ["a", "b"])
        #expect(tsv[0]["b"] == "2")

        let semi = try #require(Table(text: "a;b\n1;2\n"))
        #expect(semi.columns == ["a", "b"])
        #expect(semi[0]["b"] == "2")
    }

    /// Naming the format overrides the count, which is the point of naming it:
    /// read as tab-separated, a comma is just text in the only cell there is.
    @Test func namingTheFormatOverridesTheSniff() throws {
        let table = try #require(Table(text: "a,b\n1,2\n", format: .tsv))
        #expect(table.columns == ["a,b"])
        #expect(table[0][0] == "1,2")
    }

    /// A separator inside quotes is not a separator, so it can't win the count
    /// and rename the file's format.
    @Test func aQuotedSeparatorDoesNotDecideTheFormat() throws {
        let table = try #require(Table(text: "a\tb\n\"x;y;z;w\"\t2\n"))
        #expect(table.columns == ["a", "b"])
        #expect(table[0]["a"] == "x;y;z;w")
    }

    /// A first row holding no numbers is a header; one holding a number is data.
    @Test func aFirstRowOfNamesIsAHeader() throws {
        let named = try #require(Table(text: "x,y\n1,2\n"))
        #expect(named.columns == ["x", "y"])
        #expect(named.count == 1)

        let bare = try #require(Table(text: "1,2\n3,4\n"))
        #expect(bare.columns.isEmpty)
        #expect(bare.count == 2)
        #expect(bare[0][0] == "1")
    }

    /// Saying which overrides the guess, in both directions.
    @Test func sayingWhichOverridesTheGuess() throws {
        let forced = try #require(Table(text: "1,2\n3,4\n", header: true))
        #expect(forced.columns == ["1", "2"])
        #expect(forced.count == 1)

        let refused = try #require(Table(text: "x,y\n1,2\n", header: false))
        #expect(refused.columns.isEmpty)
        #expect(refused.count == 2)
    }

    // MARK: Reading cells as something

    /// A cell reads as a number, a whole number, a flag, or a color when asked,
    /// and as nothing when it isn't one.
    @Test func cellsReadAsWhatTheyAreAskedFor() throws {
        let table = try #require(
            Table(text: "n,i,flag,tint,junk\n2.5,2.6,yes,#ff0000,hello\n"))
        let row = table[0]
        #expect(row.number("n") == 2.5)
        #expect(row.int("i") == 3)
        #expect(row.bool("flag") == true)
        #expect(row.color("tint") == Color(red: 1, green: 0, blue: 0))
        #expect(row.number("junk") == nil)
        #expect(row.bool("junk") == nil)
        #expect(row.color("junk") == nil)
    }

    /// The flag spellings a file actually uses, in either case.
    @Test func theFlagSpellings() throws {
        let table = try #require(Table(text: "v\nTRUE\nNo\n1\n0\nmaybe\n", header: true))
        #expect(table.map { $0.bool("v") } == [true, false, true, false, nil])
    }

    /// An empty cell is not a zero. A file with a gap in it should read as a
    /// gap, so a sketch can decide what to do about it.
    @Test func anEmptyCellIsNotAZero() throws {
        let table = try #require(Table(text: "v\n\"\"\n"))
        #expect(table[0].number("v") == nil)
        #expect(table[0]["v"]?.isEmpty == true)
    }

    // MARK: Columns

    /// A column comes back in row order and the same length as the rows, so it
    /// lines up with them. A row that stops short contributes an empty cell.
    @Test func aColumnLinesUpWithTheRows() throws {
        let table = try #require(Table(text: "a,b\n1,2\n3\n"))
        #expect(table.column("b") == ["2", ""])
        #expect(table.column("b").count == table.count)
    }

    /// Read as numbers, a column drops what isn't one, which is what makes it a
    /// series to scale by rather than a row-aligned read.
    @Test func numbersDropWhatIsNotANumber() throws {
        let table = try #require(Table(text: "v\n1\nn/a\n3\n"))
        #expect(table.numbers("v") == [1, 3])
    }

    // MARK: Refusing

    /// Nothing to read yields nothing, rather than an empty table that looks
    /// like a file that parsed.
    @Test func nothingToReadYieldsNothing() {
        #expect(Table(text: "") == nil)
        #expect(Table(text: "\n\n\n") == nil)
        #expect(Table(contentsOf: "/nowhere/at/all.csv") == nil)
    }

    /// Bytes that aren't text fail quietly rather than trapping.
    @Test func bytesThatAreNotTextFailQuietly() {
        // A lone continuation byte is not valid UTF-8; the fallback encoding
        // still reads it as text, so what matters is that neither traps.
        _ = Table(data: Data([0x80, 0x81, 0x82]))
    }

    // MARK: Reading a real file

    /// The path form reads what the text form does.
    @Test func thePathFormReadsAFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-table-\(UUID().uuidString).csv")
        try "a,b\n1,2\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let table = try #require(Table(contentsOf: url.path))
        #expect(table.columns == ["a", "b"])
        #expect(table[0]["b"] == "2")
    }
}
