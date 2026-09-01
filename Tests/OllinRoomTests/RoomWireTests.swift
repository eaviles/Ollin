import Foundation
import Ollin
import Testing
@testable import OllinRoom

// Network-free on purpose: the wire is pure functions over bytes, so every case
// here writes a frame and reads it back, or hands the reader something bad and
// checks that it refuses instead of trapping.

@Suite struct RoomWireTests {

    // MARK: Values

    @Test func everyKindOfValueSurvivesTheTrip() throws {
        let values: [RoomValue] = [
            .number(1.5),
            .int(-42),
            .text("hola"),
            .bool(true),
            .point(Vector2(3, -4)),
            .color(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)),
            .bytes(Data([0, 1, 2, 255]))
        ]
        for value in values {
            let frame = RoomWire.encodeValue(key: "k", value: value)
            let read = try #require(RoomWire.unframe(frame))
            #expect(read.kind == .value)
            let decoded = try #require(RoomWire.decodeValue(read.payload))
            #expect(decoded.key == "k")
            #expect(decoded.value == value)
        }
    }

    @Test func aKeyKeepsItsAccentsAndItsSpaces() throws {
        let frame = RoomWire.encodeValue(key: "mano derecha", value: .text("adiós"))
        let read = try #require(RoomWire.unframe(frame))
        let decoded = try #require(RoomWire.decodeValue(read.payload))
        #expect(decoded.key == "mano derecha")
        #expect(decoded.value.text == "adiós")
    }

    @Test func anEmptyPayloadIsStillAValue() throws {
        let frame = RoomWire.encodeValue(key: "", value: .bytes(Data()))
        let read = try #require(RoomWire.unframe(frame))
        let decoded = try #require(RoomWire.decodeValue(read.payload))
        #expect(decoded.key.isEmpty)
        #expect(decoded.value == .bytes(Data()))
    }

    @Test func numbersReadAcrossTheirKinds() {
        #expect(RoomValue.int(3).number == 3)
        #expect(RoomValue.bool(true).number == 1)
        #expect(RoomValue.number(2.7).int == 2)
        #expect(RoomValue.number(0).bool == false)
        // Text is text, and reads as nothing else.
        #expect(RoomValue.text("3").number == nil)
        #expect(RoomValue.point(Vector2(1, 2)).number == nil)
    }

    // MARK: Framing refusals

    @Test func aFrameFromAnotherApplicationIsRefused() {
        var bytes = [UInt8](RoomWire.encodeValue(key: "k", value: .number(1)))
        bytes[0] = 0x00
        #expect(RoomWire.unframe(Data(bytes)) == nil)
    }

    @Test func aFrameFromAnotherVersionIsRefused() {
        var bytes = [UInt8](RoomWire.encodeValue(key: "k", value: .number(1)))
        bytes[4] = RoomWire.version &+ 1
        #expect(RoomWire.unframe(Data(bytes)) == nil)
    }

    @Test func aKindThisVersionDoesNotKnowIsRefused() {
        var bytes = [UInt8](RoomWire.encodeValue(key: "k", value: .number(1)))
        bytes[5] = 200
        #expect(RoomWire.unframe(Data(bytes)) == nil)
    }

    @Test func aTruncatedFrameIsRefused() {
        let frame = RoomWire.encodeValue(key: "k", value: .number(1))
        for cut in 1...frame.count {
            #expect(RoomWire.unframe(frame.prefix(frame.count - cut)) == nil)
        }
    }

    @Test func aPayloadThatDisagreesWithItsHeaderIsRefused() {
        var bytes = [UInt8](RoomWire.encodeValue(key: "k", value: .number(1)))
        // Claim one byte more than the frame carries.
        bytes[8] = bytes[8] &+ 1
        #expect(RoomWire.unframe(Data(bytes)) == nil)
    }

    @Test func aHeaderClaimingAHugePayloadIsRefused() {
        var bytes = [UInt8](RoomWire.encodeValue(key: "k", value: .number(1)))
        bytes[8] = 0xFF; bytes[9] = 0xFF; bytes[10] = 0xFF; bytes[11] = 0x7F
        #expect(RoomWire.unframe(Data(bytes)) == nil)
    }

    @Test func nothingAtAllIsRefused() {
        #expect(RoomWire.unframe(Data()) == nil)
    }

    @Test func aValuePayloadCutShortIsRefused() {
        let frame = RoomWire.encodeValue(key: "key", value: .point(Vector2(1, 2)))
        let read = RoomWire.unframe(frame)!
        for cut in 1...read.payload.count {
            #expect(RoomWire.decodeValue(Array(read.payload.dropLast(cut))) == nil)
        }
    }

    @Test func aValueTagThisVersionDoesNotKnowIsRefused() {
        let frame = RoomWire.encodeValue(key: "k", value: .number(1))
        var payload = RoomWire.unframe(frame)!.payload
        // The tag sits straight after the four-byte key length and the key.
        payload[4 + 1] = 99
        #expect(RoomWire.decodeValue(payload) == nil)
    }

    @Test func aFrameHandedOverAsASliceReadsTheSameBytes() throws {
        // A message from the network arrives as a slice of a larger buffer, whose
        // first index is not zero. Reading it as if it started at zero decodes
        // the wrong bytes, so the reader copies it first.
        let frame = RoomWire.encodeValue(key: "beat", value: .number(120))
        var padded = Data([9, 9, 9, 9, 9, 9, 9])
        padded.append(frame)
        let slice = padded.dropFirst(7)
        #expect(slice.startIndex != 0)
        let read = try #require(RoomWire.unframe(slice))
        let decoded = try #require(RoomWire.decodeValue(read.payload))
        #expect(decoded.key == "beat")
        #expect(decoded.value.number == 120)
    }

    // MARK: The other messages

    @Test func aGreetingCarriesTheSeatAndTheSketch() throws {
        let frame = RoomWire.encodeHello(seat: 3, sketchName: "WallPiece")
        let read = try #require(RoomWire.unframe(frame))
        #expect(read.kind == .hello)
        let hello = try #require(RoomWire.decodeHello(read.payload))
        #expect(hello.seat == 3)
        #expect(hello.sketchName == "WallPiece")
    }

    @Test func aGreetingWithNoSeatAsksForNone() throws {
        let frame = RoomWire.encodeHello(seat: nil, sketchName: "P")
        let read = try #require(RoomWire.unframe(frame))
        let hello = try #require(RoomWire.decodeHello(read.payload))
        #expect(hello.seat == nil)
    }

    @Test func aKnobTravelsAsThePayloadTheHostsPersist() throws {
        let stored = ParamStored.color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let frame = try #require(RoomWire.encodeKnob(name: "accent", stored: stored, turnedAt: 61.25))
        let read = try #require(RoomWire.unframe(frame))
        #expect(read.kind == .knob)
        let knob = try #require(RoomWire.decodeKnob(read.payload))
        #expect(knob.name == "accent")
        #expect(knob.stored == stored)
        #expect(knob.turnedAt == 61.25)
    }

    @Test func aClockQuestionAndItsAnswerCarryTheirNumbers() throws {
        let question = try #require(RoomWire.unframe(RoomWire.encodeClockPing(id: 7)))
        #expect(question.kind == .clockPing)
        #expect(RoomWire.decodeClockPing(question.payload) == 7)

        let answer = try #require(RoomWire.unframe(RoomWire.encodeClockPong(id: 7, roomTime: 12.5)))
        #expect(answer.kind == .clockPong)
        let pong = try #require(RoomWire.decodeClockPong(answer.payload))
        #expect(pong.id == 7)
        #expect(pong.roomTime == 12.5)
    }

    // MARK: Names

    @Test func aRoomNameBecomesAServiceNameTheSystemAccepts() {
        for name in ["wall", "Sala Grande", "piece #4!", "  ", "a", "gallery-north", "MUY LARGO NOMBRE DE SALA"] {
            let service = RoomWire.serviceType(for: name)
            #expect(service.count <= 15, "\(name) gave \(service)")
            #expect(!service.isEmpty)
            #expect(service.hasPrefix("ollin-"))
            #expect(!service.hasSuffix("-"))
            #expect(!service.contains("--"))
            #expect(service.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
            #expect(service.contains { $0.isLetter })
        }
    }

    @Test func twoLongRoomNamesStayDifferentRooms() {
        // The first characters agree, so only the hash keeps these apart.
        let left = RoomWire.serviceType(for: "wall left of the stage")
        let right = RoomWire.serviceType(for: "wall right of the stage")
        #expect(left != right)
        #expect(left.count <= 15 && right.count <= 15)
    }

    @Test func oneRoomNameAlwaysGivesTheSameServiceName() {
        #expect(RoomWire.serviceType(for: "Sala Grande") == RoomWire.serviceType(for: "sala   grande"))
        #expect(RoomWire.serviceType(for: "wall") == "ollin-wall")
    }

    @Test func aNameWithNothingUsableStillGivesARoom() {
        #expect(RoomWire.serviceType(for: "!!!") == "ollin-room")
        #expect(RoomWire.serviceType(for: "") == "ollin-room")
    }

    @Test func aMachineNameDropsItsDomainAndKeepsItsSuffix() {
        #expect(RoomWire.peerName(host: "studio-mac.local", suffix: "a1b2") == "studio-mac-a1b2")
        #expect(RoomWire.peerName(host: "studio-mac", suffix: "") == "studio-mac")
        #expect(RoomWire.peerName(host: "", suffix: "x") == "ollin-x")
        let long = RoomWire.peerName(host: String(repeating: "m", count: 90), suffix: "abcd")
        #expect(long.utf8.count <= 63)
    }

    @Test func aPasscodeNeverTravelsAsItself() {
        let token = LocalNetworkTransport.token(for: "abrelatas")
        #expect(!token.contains("abrelatas"))
        #expect(token.count == 64)
        #expect(LocalNetworkTransport.token(for: nil).isEmpty)
        #expect(LocalNetworkTransport.token(for: "") .isEmpty)
        #expect(token == LocalNetworkTransport.token(for: "abrelatas"))
        #expect(token != LocalNetworkTransport.token(for: "abrelata"))
    }
}
