import Foundation
import Testing
import OllinMutation
@testable import Ollin

/// The data files a sketch reads as input: a table (comma, tab, or semicolon
/// separated, with or without a header) and a JSON document. Each is read and
/// then every value in it is read every way a sketch reads one: as text, a
/// number, a whole number, a switch, and a color.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct DataFileMutationTests {

    @Test func tables() {
        let csv = "city,lat,lon,population,visited,tint\nOaxaca,17.06,-96.72,300050,true,#c0392b\n\"Mexico, City\",19.43,-99.13,9209944,yes,\"rgb\"\nMérida,20.97,-89.62,995129,0,#2ecc71\n"
        let tsv = "1\t2.5\t-3\ttrue\n4\t5e3\t6\tfalse\n"
        let semicolon = "a;b;c\n1,5;2;3\n\"x\"\"y\";;z\n"
        let report = MutationRun.run("table-file", seeds: [csv.bytes, tsv.bytes, semicolon.bytes], count: 500,
                                     numberSweep: true, allocations: fileBound) { bytes in
            guard let table = try? Table(data: Data(bytes)) else { return false }
            for row in table {
                for column in table.columns {
                    _ = row[column]
                    _ = row.number(column)
                    _ = row.int(column)
                    _ = row.bool(column)
                    _ = row.color(column)
                }
                for position in 0..<table.columns.count + 1 {
                    _ = row.number(at: position)
                    _ = row.int(at: position)
                }
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func jsonDocuments() {
        let document = """
        {"name": "rooms", "count": 3, "ratio": 0.75, "big": 1e300, "on": true, "none": null,
         "rooms": [{"id": 1, "size": [4, 5.5], "tags": ["a", "b"]}, {"id": -2, "size": [], "nested": {"deep": [[1], [2, [3]]]}}],
         "unicode": "\\u00e9t\\u00e9"}
        """
        let report = MutationRun.run("json-file", seeds: [document.bytes], count: 600, sweeps: false,
                                     numberSweep: true, allocations: fileBound) { bytes in
            guard let json = try? JSON(data: Data(bytes)) else { return false }
            func read(_ value: JSON, depth: Int) {
                _ = value.text
                _ = value.number
                _ = value.int
                _ = value.bool
                guard depth < 64 else { return }
                for item in value.array { read(item, depth: depth + 1) }
                for key in value.keys { read(value[key], depth: depth + 1) }
                _ = value[0]
                _ = value[-1]
            }
            read(json, depth: 0)
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }
}
