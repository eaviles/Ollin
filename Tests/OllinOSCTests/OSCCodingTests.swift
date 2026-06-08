import Foundation
import Testing
@testable import OllinOSC

/// Wire-format correctness for the hand-written OSC 1.0 encoder/decoder: every
/// argument type round-trips, 4-byte padding lands on the boundaries, and any
/// malformed datagram decodes to `nil` rather than trapping. No network, no GPU,
/// so these run everywhere including CI.
@Suite
struct OSCCodingTests {

    /// Encode then decode, expecting a message back unchanged.
    func roundTrip(_ message: OSCMessage, sourceLocation: SourceLocation = #_sourceLocation) {
        let data = message.encode()
        // Length is always a multiple of 4 for a well-formed packet.
        #expect(data.count % 4 == 0, sourceLocation: sourceLocation)
        guard case .message(let decoded)? = OSCPacket(data: data) else {
            Issue.record("decode failed", sourceLocation: sourceLocation)
            return
        }
        #expect(decoded == message, sourceLocation: sourceLocation)
    }

    @Test func everyArgumentTypeRoundTrips() {
        roundTrip(OSCMessage("/i", .int(-42)))
        roundTrip(OSCMessage("/f", .float(0.5)))
        roundTrip(OSCMessage("/s", .string("hello")))
        roundTrip(OSCMessage("/b", .blob(Data([1, 2, 3, 4, 5]))))
        roundTrip(OSCMessage("/d", .double(3.141592653589793)))
        roundTrip(OSCMessage("/h", .int64(9_000_000_000)))
        roundTrip(OSCMessage("/T", .bool(true)))
        roundTrip(OSCMessage("/F", .bool(false)))
        roundTrip(OSCMessage("/N", .null))
        roundTrip(OSCMessage("/I", .impulse))
    }

    @Test func mixedArgumentsRoundTrip() {
        roundTrip(OSCMessage("/synth/1/freq", 0.8, 1, "on", true, .double(2.5)))
    }

    @Test func noArgumentMessageRoundTrips() {
        roundTrip(OSCMessage("/ping"))
    }

    /// Strings (address and `s` args) pad with at least one null up to a multiple
    /// of four — including the awkward exact-multiple case, which still adds four.
    @Test(arguments: ["", "a", "ab", "abc", "abcd", "abcde", "/a/longer/address"])
    func stringPaddingRoundTrips(_ value: String) {
        roundTrip(OSCMessage("/s", .string(value)))
        roundTrip(OSCMessage(value.isEmpty ? "/x" : "/" + value, .int(1)))
    }

    /// Blobs of every length-mod-4 pad correctly and survive the trip.
    @Test(arguments: [0, 1, 2, 3, 4, 5, 7, 8, 16, 100])
    func blobPaddingRoundTrips(_ length: Int) {
        let bytes = Data((0..<length).map { UInt8($0 & 0xFF) })
        roundTrip(OSCMessage("/blob", .blob(bytes)))
    }

    @Test func bundleRoundTrips() {
        let bundle = OSCBundle(.immediate, [
            .message(OSCMessage("/x", 0.25)),
            .message(OSCMessage("/y", 0.75)),
            .bundle(OSCBundle(.immediate, [.message(OSCMessage("/nested", "deep"))])),
        ])
        guard case .bundle(let decoded)? = OSCPacket(data: bundle.encode()) else {
            Issue.record("bundle decode failed")
            return
        }
        #expect(decoded == bundle)
    }

    @Test func timeTagRoundTripsThroughBundle() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let tag = OSCTimeTag(date)
        let bundle = OSCBundle(tag, [.message(OSCMessage("/t", 1))])
        guard case .bundle(let decoded)? = OSCPacket(data: bundle.encode()) else {
            Issue.record("bundle decode failed"); return
        }
        #expect(decoded.timeTag == tag)
        // And the tag maps back to about the same instant (NTP fixed-point is exact
        // to well under a millisecond).
        let recovered = decoded.timeTag.date
        #expect(recovered != nil)
        #expect(abs((recovered ?? .distantPast).timeIntervalSince1970 - 1_700_000_000.5) < 0.001)
    }

    @Test func immediateTimeTagHasNoDate() {
        #expect(OSCTimeTag.immediate.isImmediate)
        #expect(OSCTimeTag.immediate.date == nil)
    }

    // MARK: Robustness — malformed input never traps, always returns nil

    @Test func emptyDataDecodesToNil() {
        #expect(OSCPacket(data: Data()) == nil)
    }

    @Test func truncatedArgumentDecodesToNil() {
        // "/x" + ",i" tags but no int32 payload.
        var data = OSCMessage("/x", .int(7)).encode()
        data.removeLast(4)   // drop the int32
        #expect(OSCPacket(data: data) == nil)
    }

    @Test func unknownTypeTagDecodesToNil() {
        // A valid message whose tag string claims an unsupported type 'z'.
        var data = Data()
        OSCCoding.writeString("/x", into: &data)
        OSCCoding.writeString(",z", into: &data)
        #expect(OSCPacket(data: data) == nil)
    }

    @Test func missingTypeTagCommaDecodesToNil() {
        var data = Data()
        OSCCoding.writeString("/x", into: &data)
        OSCCoding.writeString("nope", into: &data)   // doesn't start with ','
        #expect(OSCPacket(data: data) == nil)
    }

    @Test func unterminatedStringDecodesToNil() {
        // Four non-null bytes: no terminator anywhere.
        #expect(OSCPacket(data: Data([0x2F, 0x78, 0x79, 0x7A])) == nil)
    }

    @Test func garbageDoesNotTrap() {
        // Fuzz-ish: random buffers must only ever return a value or nil.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let length = Int.random(in: 0...64, using: &generator)
            let bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            _ = OSCPacket(data: Data(bytes))   // must not crash
        }
    }

    // MARK: Coercion accessors

    @Test func numericCoercion() {
        #expect(OSCMessage("/x", .int(3)).float == 3)
        #expect(OSCMessage("/x", .float(2.9)).int == 2)
        #expect(OSCMessage("/x", .bool(true)).float == 1)
        #expect(OSCMessage("/x", .impulse).bool == true)
        #expect(OSCMessage("/x", .string("hi")).string == "hi")
        #expect(OSCMessage("/x", .string("hi")).float == nil)
    }
}
