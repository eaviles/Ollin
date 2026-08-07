import Foundation

/// How a delimited file separates its cells. `.auto` reads the first line and
/// decides, which is right almost always; name a format when a file is unusual
/// enough that the guess goes wrong.
public enum TableFormat: Sendable {
    /// Sniff the separator from the file's first line.
    case auto
    /// Comma-separated.
    case csv
    /// Tab-separated.
    case tsv
    /// Separated by a character you name (a semicolon, a pipe, …).
    case delimited(Character)
}

/// A table of cells read from a CSV or TSV file: a list of column names and the
/// rows under them.
///
/// Every cell is text, because that is what the file holds; a row reads one as a
/// number, an integer, a flag, or a color when you ask for it that way, and
/// answers `nil` when the cell isn't one.
///
/// ```swift
/// let table = loadTable(resource: "readings", withExtension: "csv", in: .module)!
/// for row in table {
///     let x = row.number("lon") ?? 0
///     let y = row.number("lat") ?? 0
///     drawCircle(x, y, 4)
/// }
/// ```
///
/// Parsing follows the published CSV description: a cell wrapped in double
/// quotes may hold the separator, line breaks, and doubled quotes standing for
/// one. Around that it is forgiving, since files in the wild are: a byte-order
/// mark, any mix of line endings, blank lines, and rows of uneven length all
/// read without complaint, and an unquoted cell has its surrounding spaces
/// trimmed (quote a cell to keep them).
public struct Table: Sendable {
    /// The column names, in file order. Empty when the table was read headerless.
    public let columns: [String]
    /// The rows under the header, in file order.
    public let rows: [Row]

    private init(columns: [String], records: [[String]]) {
        // One name-to-position map, shared by every row rather than copied into
        // each of them.
        let lookup = ColumnLookup(columns)
        self.columns = columns
        self.rows = records.map { Row(cells: $0, lookup: lookup) }
    }

    /// One row's cells, readable by column name or by position.
    public struct Row: Sendable {
        /// The row's cells, in file order. A short row is short: a file with
        /// ragged rows keeps them ragged rather than padding to the header.
        public let cells: [String]

        fileprivate let lookup: ColumnLookup

        /// The cell under `column`, or `nil` when the table has no such column
        /// or this row stops before it.
        public subscript(column: String) -> String? {
            guard let index = lookup.indices[column] else { return nil }
            return self[index]
        }

        /// The cell at `position`, or `nil` past the end of the row.
        public subscript(position: Int) -> String? {
            guard cells.indices.contains(position) else { return nil }
            return cells[position]
        }

        /// The cell under `column` read as a number, or `nil` when it is missing
        /// or isn't one.
        public func number(_ column: String) -> Double? { Table.number(self[column]) }

        /// The cell at `position` read as a number.
        public func number(at position: Int) -> Double? { Table.number(self[position]) }

        /// The cell under `column` read as a whole number, rounding a decimal one.
        public func int(_ column: String) -> Int? { Table.int(self[column]) }

        /// The cell at `position` read as a whole number.
        public func int(at position: Int) -> Int? { Table.int(self[position]) }

        /// The cell under `column` read as a flag. `true`, `yes`, and `1` are
        /// true; `false`, `no`, and `0` are false; anything else is `nil`.
        public func bool(_ column: String) -> Bool? { Table.bool(self[column]) }

        /// The cell at `position` read as a flag.
        public func bool(at position: Int) -> Bool? { Table.bool(self[position]) }

        /// The cell under `column` read as a hex color (`#ff8800`, `f80`), or
        /// `nil` when it isn't one.
        public func color(_ column: String) -> Color? { Table.color(self[column]) }

        /// The cell at `position` read as a hex color.
        public func color(at position: Int) -> Color? { Table.color(self[position]) }
    }

    /// The name-to-position map. A class so the rows share one copy; immutable,
    /// so sharing it costs nothing and stays `Sendable`.
    fileprivate final class ColumnLookup: Sendable {
        let indices: [String: Int]

        init(_ columns: [String]) {
            // First occurrence wins, so a file with a repeated column name still
            // reads the one a person would point at.
            var indices: [String: Int] = [:]
            for (position, name) in columns.enumerated() where indices[name] == nil {
                indices[name] = position
            }
            self.indices = indices
        }
    }
}

// MARK: - Column reads

public extension Table {
    /// Every cell in a column, in row order. Rows that stop before the column
    /// contribute an empty string, so the result lines up with `rows`.
    func column(_ name: String) -> [String] {
        rows.map { $0[name] ?? "" }
    }

    /// A column read as numbers, in row order.
    ///
    /// Cells that aren't numbers are dropped, which makes this the form to reach
    /// for when reading a column as a series (a range to map, a maximum to scale
    /// by). When the rows have to stay lined up with each other, read each row's
    /// cells instead.
    func numbers(_ name: String) -> [Double] {
        rows.compactMap { $0.number(name) }
    }
}

// MARK: - Rows as a collection

extension Table: RandomAccessCollection {
    public var startIndex: Int { rows.startIndex }
    public var endIndex: Int { rows.endIndex }
    public subscript(position: Int) -> Row { rows[position] }
}

// MARK: - Cell readers

private extension Table {
    static func number(_ cell: String?) -> Double? {
        guard let cell else { return nil }
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    static func int(_ cell: String?) -> Int? {
        guard let value = number(cell), value.isFinite else { return nil }
        return Int(value.rounded())
    }

    static func bool(_ cell: String?) -> Bool? {
        switch cell?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    static func color(_ cell: String?) -> Color? {
        guard let cell else { return nil }
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Color(hex: trimmed)
    }
}

// MARK: - Loading

public extension Table {
    /// Read a table from a file.
    ///
    /// ```swift
    /// let table = Table(contentsOf: "readings.csv")
    /// ```
    ///
    /// - Parameters:
    ///   - path: the file to read.
    ///   - format: how cells are separated. `.auto` decides from the first line.
    ///   - header: whether the first row names the columns. `nil` lets the file
    ///     decide: a first row holding no numbers is a header, anything else is
    ///     data. Say which when the guess goes wrong.
    init?(contentsOf path: String, format: TableFormat = .auto, header: Bool? = nil) {
        self.init(url: URL(fileURLWithPath: path), format: format, header: header)
    }

    /// Read a table from a URL. A network URL blocks until it arrives, so call
    /// this in `setup()` rather than `draw()`.
    init?(url: URL, format: TableFormat = .auto, header: Bool? = nil) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, format: format, header: header)
    }

    /// Read a table from bytes. Bytes that aren't text yield `nil` rather than
    /// trapping, so a file from the network fails quietly.
    init?(data: Data, format: TableFormat = .auto, header: Bool? = nil) {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }
        self.init(text: text, format: format, header: header)
    }

    /// Read a table from text already in hand.
    init?(text: String, format: TableFormat = .auto, header: Bool? = nil) {
        var bytes = [UInt8](text.utf8)
        // A byte-order mark would otherwise ride into the first column's name,
        // where it is invisible and breaks every lookup of it.
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes.removeFirst(3)
        }

        let separator = Table.separator(for: format, in: bytes)
        var records = Table.parse(bytes, separator: separator)
        guard !records.isEmpty else { return nil }

        let hasHeader = header ?? Table.looksLikeHeader(records[0])
        let columns = hasHeader ? records.removeFirst() : []
        self.init(columns: columns, records: records)
    }

    /// Read a table bundled as a resource.
    ///
    /// `in:` has no default on purpose: a default would resolve to Ollin's own
    /// bundle rather than the caller's. Pass `.module` from your sketch.
    init?(resource: String, withExtension ext: String? = "csv", in bundle: Bundle,
          format: TableFormat = .auto, header: Bool? = nil) {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else { return nil }
        self.init(url: url, format: format, header: header)
    }
}

// MARK: - Sniffing

private extension Table {
    static func separator(for format: TableFormat, in bytes: [UInt8]) -> UInt8 {
        switch format {
        case .csv: return UInt8(ascii: ",")
        case .tsv: return UInt8(ascii: "\t")
        case .delimited(let character):
            // Only a single-byte separator can be scanned bytewise; anything
            // wider falls back to a comma rather than splitting a character.
            let utf8 = Array(String(character).utf8)
            return utf8.count == 1 ? utf8[0] : UInt8(ascii: ",")
        case .auto:
            return sniffSeparator(bytes)
        }
    }

    /// Count each candidate on the first line that holds one, outside quotes,
    /// and take the most frequent. A comma wins a tie, since it is the format
    /// the file extension usually promises.
    static func sniffSeparator(_ bytes: [UInt8]) -> UInt8 {
        let candidates = [UInt8(ascii: ","), UInt8(ascii: "\t"), UInt8(ascii: ";"), UInt8(ascii: "|")]
        var counts = [Int](repeating: 0, count: candidates.count)
        var inQuotes = false

        for byte in bytes {
            if byte == UInt8(ascii: "\"") { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if byte == 0x0A || byte == 0x0D {
                // Stop at the end of the first line that counted something; a
                // leading blank line decides nothing.
                if counts.contains(where: { $0 > 0 }) { break }
                continue
            }
            if let index = candidates.firstIndex(of: byte) { counts[index] += 1 }
        }

        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else {
            return UInt8(ascii: ",")
        }
        return candidates[best]
    }

    /// A first row of names looks nothing like a first row of readings: it holds
    /// no numbers. That is the whole rule, and it is what a person reads too.
    static func looksLikeHeader(_ record: [String]) -> Bool {
        !record.contains { number($0) != nil }
    }
}

// MARK: - Parsing

private extension Table {
    /// The published CSV description as a byte scanner.
    ///
    /// Bytes rather than characters because every byte it compares against is
    /// ASCII, and in UTF-8 no byte of a multi-byte character can be mistaken for
    /// one: the scan is exact and the text inside a cell rides through untouched.
    static func parse(_ bytes: [UInt8], separator: UInt8) -> [[String]] {
        let quote = UInt8(ascii: "\"")

        var records: [[String]] = []
        var record: [String] = []
        var cell: [UInt8] = []
        var inQuotes = false
        var wasQuoted = false
        var afterClosingQuote = false
        var recordHeldQuotes = false
        var index = 0

        func endCell() {
            let text = String(decoding: cell, as: UTF8.self)
            // A quoted cell is verbatim: quoting is how a file says it means the
            // spaces. An unquoted one is trimmed, because `a, b` is written by
            // people who mean `b`.
            record.append(wasQuoted ? text : text.trimmingCharacters(in: .whitespaces))
            cell.removeAll(keepingCapacity: true)
            wasQuoted = false
            afterClosingQuote = false
        }

        func endRecord() {
            endCell()
            // A blank line arrives here as one empty unquoted cell, and so does
            // the newline that ends the last real row. Neither is a row. A line
            // holding `""` is one, though, which is why the quotes count: it is
            // a file saying, in the only way it can, that the cell is empty.
            let isBlankLine = record.count == 1 && record[0].isEmpty && !recordHeldQuotes
            if !isBlankLine { records.append(record) }
            record.removeAll(keepingCapacity: true)
            recordHeldQuotes = false
        }

        while index < bytes.count {
            let byte = bytes[index]

            if inQuotes {
                if byte == quote {
                    // Two quotes inside a quoted cell stand for one.
                    if index + 1 < bytes.count, bytes[index + 1] == quote {
                        cell.append(quote)
                        index += 2
                        continue
                    }
                    inQuotes = false
                    afterClosingQuote = true
                    index += 1
                    continue
                }
                cell.append(byte)
                index += 1
                continue
            }

            // The separator and the line endings are tested first, because a
            // tab is both a separator and whitespace and the separator reading
            // has to win.
            switch byte {
            case separator:
                endCell()
            case 0x0A:
                endRecord()
            case 0x0D:
                endRecord()
                // A CRLF pair ends one record, not two.
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 1 }
            case quote where !wasQuoted && cell.allSatisfy(isSpace):
                // Whitespace before the opening quote isn't part of the cell.
                cell.removeAll(keepingCapacity: true)
                inQuotes = true
                wasQuoted = true
                recordHeldQuotes = true
            case _ where afterClosingQuote && isSpace(byte):
                // Nor is whitespace after the closing one. Without this a cell
                // written ` "y" ` keeps the space the quotes were there to
                // exclude, since a quoted cell is otherwise taken verbatim.
                break
            default:
                cell.append(byte)
            }
            index += 1
        }

        // Whatever the last line left, with no newline to close it. Closing an
        // already-closed record costs nothing: it reads as a blank line and is
        // dropped by the same rule.
        endRecord()
        return records
    }

    static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Read a CSV or TSV file by path: `loadTable("readings.csv")`. Returns `nil`
    /// when the file can't be read or holds no rows. Call it in `setup()` and
    /// keep the result in a property.
    func loadTable(_ path: String, format: TableFormat = .auto, header: Bool? = nil) -> Table? {
        Table(contentsOf: path, format: format, header: header)
    }

    /// Read a table from a URL. A network URL blocks until it arrives.
    func loadTable(_ url: URL, format: TableFormat = .auto, header: Bool? = nil) -> Table? {
        Table(url: url, format: format, header: header)
    }

    /// Read a table bundled as a resource. Pass `.module` for the sketch's own
    /// bundle; a default here would resolve to Ollin's.
    func loadTable(resource: String, withExtension ext: String? = "csv", in bundle: Bundle,
                   format: TableFormat = .auto, header: Bool? = nil) -> Table? {
        Table(resource: resource, withExtension: ext, in: bundle, format: format, header: header)
    }
}
