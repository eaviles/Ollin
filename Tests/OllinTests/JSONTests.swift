import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `JSON`. The load-bearing part is what happens when a path
/// doesn't lead anywhere: reaching through a key that isn't there has to answer
/// null rather than stop, since that is what lets a sketch follow a path as far
/// as it goes and decide at the end. No GPU.
@Suite @MainActor
struct JSONTests {

    // MARK: Reading each kind

    /// Each kind comes back as itself, and asking for the wrong one answers
    /// nothing rather than a stand-in value.
    @Test func eachKindReadsAsItself() throws {
        let json = try #require(JSON(text: """
            {"text": "hi", "n": 2.5, "flag": true, "nothing": null}
            """))
        #expect(json["text"].string == "hi")
        #expect(json["n"].number == 2.5)
        #expect(json["flag"].bool == true)
        #expect(json["nothing"].isNull)
        #expect(json["text"].number == nil)
        #expect(json["n"].string == nil)
    }

    /// A JSON true arrives from the system reader as a number holding 1, so
    /// without checking its type a flag would read as the number 1 and a 1
    /// would read as a flag that was never written.
    @Test func aFlagIsNotTheNumberOne() throws {
        let json = try #require(JSON(text: #"{"flag": true, "one": 1}"#))
        #expect(json["flag"] == .bool(true))
        #expect(json["one"] == .number(1))
    }

    /// Plenty of documents quote their figures, so a numeric string reads as a
    /// number. Text that isn't a number still doesn't.
    @Test func aQuotedNumberIsANumber() throws {
        let json = try #require(JSON(text: #"{"a": "42", "b": "forty-two"}"#))
        #expect(json["a"].number == 42)
        #expect(json["b"].number == nil)
    }

    /// A whole number rounds rather than truncating.
    @Test func aWholeNumberRounds() throws {
        let json = try #require(JSON(text: #"{"a": 2.6, "b": -2.6}"#))
        #expect(json["a"].int == 3)
        #expect(json["b"].int == -3)
    }

    /// A hex string reads as a color, which is how a document carries one.
    @Test func aHexStringReadsAsAColor() throws {
        // A wider delimiter, because a hex color opens with the `"#` that would
        // otherwise close a single-pound raw string.
        let json = try #require(JSON(text: ##"{"tint": "#ff0000", "other": "red-ish"}"##))
        #expect(json["tint"].color == Color(red: 1, green: 0, blue: 0))
        #expect(json["other"].color == nil)
    }

    // MARK: Reaching in

    /// A key that isn't there answers null, and so does every step after it, so
    /// a whole path can be followed without a check at each joint.
    @Test func aPathThatLeadsNowhereAnswersNull() throws {
        let json = try #require(JSON(text: #"{"a": {"b": 1}}"#))
        #expect(json["a"]["b"].number == 1)
        #expect(json["a"]["missing"].isNull)
        #expect(json["missing"]["b"]["c"][0].isNull)
        #expect(json["missing"]["b"].number == nil)
    }

    /// An index past the end, or into something that isn't an array, is the
    /// same kind of nothing.
    @Test func anIndexPastTheEndAnswersNull() throws {
        let json = try #require(JSON(text: #"{"items": [1, 2]}"#))
        #expect(json["items"][1].number == 2)
        #expect(json["items"][9].isNull)
        #expect(json["items"][-1].isNull)
        #expect(json["a"][0].isNull)
    }

    /// The dotted form reads the same value as the keyed one.
    @Test func theDottedFormReadsTheSameValue() throws {
        let json = try #require(JSON(text: #"{"city": {"name": "Oslo"}}"#))
        #expect(json.city.name.string == "Oslo")
        #expect(json.city.name == json["city"]["name"])
        #expect(json.nowhere.isNull)
    }

    /// Looping over a key that isn't there runs zero times instead of needing a
    /// check first, which is the reason `array` isn't optional.
    @Test func loopingOverWhatIsNotThereRunsZeroTimes() throws {
        let json = try #require(JSON(text: #"{"items": [1, 2, 3]}"#))
        #expect(json["items"].array.count == 3)
        #expect(json["missing"].array.isEmpty)
        #expect(json["items"][0].array.isEmpty)

        var total = 0.0
        for item in json["missing"].array { total += item.number ?? 0 }
        #expect(total == 0)
    }

    /// Keys come back sorted, so walking an object is reproducible rather than
    /// following a dictionary's own order.
    @Test func keysComeBackSorted() throws {
        let json = try #require(JSON(text: #"{"c": 1, "a": 2, "b": 3}"#))
        #expect(json.keys == ["a", "b", "c"])
        #expect(json.count == 3)
        #expect(json["a"].count == 0)
    }

    // MARK: Shapes a document arrives in

    /// A document may be an array at the top level rather than an object.
    @Test func anArrayCanBeTheWholeDocument() throws {
        let json = try #require(JSON(text: #"[{"n": 1}, {"n": 2}]"#))
        #expect(json.count == 2)
        #expect(json[1]["n"].number == 2)
    }

    /// So may a bare value.
    @Test func aBareValueCanBeTheWholeDocument() throws {
        #expect(JSON(text: "42")?.number == 42)
        #expect(JSON(text: #""hello""#)?.string == "hello")
        #expect(JSON(text: "true")?.bool == true)
    }

    /// Nesting holds together through arrays and objects alike.
    @Test func nestingHoldsTogether() throws {
        let json = try #require(JSON(text: """
            {"rows": [{"cells": [{"v": 7}]}]}
            """))
        #expect(json["rows"][0]["cells"][0]["v"].number == 7)
        #expect(json.rows[0].cells[0].v.int == 7)
    }

    // MARK: Refusing

    /// Anything that isn't JSON yields nothing rather than throwing, so a file
    /// from the network fails quietly.
    @Test func whatIsNotJSONYieldsNothing() {
        #expect(JSON(text: "{oops") == nil)
        #expect(JSON(text: "") == nil)
        #expect(JSON(contentsOf: "/nowhere/at/all.json") == nil)
    }

    // MARK: Reading a real file

    /// The path form reads what the text form does.
    @Test func thePathFormReadsAFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-json-\(UUID().uuidString).json")
        try #"{"a": [1, 2]}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let json = try #require(JSON(contentsOf: url.path))
        #expect(json["a"][1].number == 2)
    }
}
