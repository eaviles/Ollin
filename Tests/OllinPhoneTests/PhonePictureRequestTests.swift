import Testing
import Foundation
import Ollin
@testable import OllinPhone

/// The picture request: the one Mac-to-phone message that is most of what crosses
/// the cable. Pure codec and bookkeeping invariants; the compressor's own round trip is
/// `PhonePictureRoundTripTests`.
@Suite(.timeLimit(.minutes(1))) struct PhonePictureRequestTests {

    private let sets = [Data([0x40, 0x01, 0x0C]), Data([0x42, 0x01, 0x01, 0x01]), Data([0x44, 0x01])]

    private func roundTrip(_ request: PhoneRequest) -> PhoneRequest? {
        let data = PhoneWire.encode(request)
        guard let header = PhoneRequestHeader.parse(data) else { return nil }
        return PhoneWire.decode(header: header, payload: data.dropFirst(PhoneWire.headerByteCount))
    }

    @Test func aKeyframeTravelsWithItsParameterSets() {
        let picture = PhonePicture(width: 1080, height: 1920, isKeyframe: true, parameterSets: sets,
                                   data: Data((0..<3000).map { UInt8($0 & 0xFF) }))
        #expect(roundTrip(.picture(picture)) == .picture(picture))
        #expect(PhoneRequestHeader.parse(PhoneWire.encode(.picture(picture)))?.kind == .picture)
    }

    @Test func aPictureBuiltOnTheOneBeforeTravelsBare() {
        let picture = PhonePicture(width: 640, height: 360, isKeyframe: false, data: Data([0, 0, 0, 1, 0x02]))
        #expect(roundTrip(.picture(picture)) == .picture(picture))
    }

    @Test func aKeyframeWithNothingToBuildADecoderFromIsRefused() {
        let bare = PhonePicture(width: 640, height: 360, isKeyframe: true, data: Data([1, 2, 3]))
        #expect(roundTrip(.picture(bare)) == nil)
    }

    @Test func aPictureWithNoSizeOrNoBytesIsRefused() {
        #expect(roundTrip(.picture(PhonePicture(width: 0, height: 360, isKeyframe: false,
                                                data: Data([1])))) == nil)
        #expect(roundTrip(.picture(PhonePicture(width: 640, height: 360, isKeyframe: false,
                                                data: Data()))) == nil)
    }

    @Test func aTruncatedPictureIsSkippedAndTheStreamStaysInStep() {
        // Cut the payload short but keep the header honest about the new length:
        // the frame is framed correctly and will not decode, so it is skipped,
        // and the mode request behind it still arrives.
        let picture = PhonePicture(width: 640, height: 360, isKeyframe: true, parameterSets: sets,
                                   data: Data(repeating: 7, count: 40))
        var frame = PhoneWire.encode(.picture(picture))
        frame.removeLast(10)
        let length = UInt32(frame.count - PhoneWire.headerByteCount)
        withUnsafeBytes(of: length.littleEndian) { frame.replaceSubrange(8..<12, with: $0) }
        var buffer = frame + PhoneWire.encode(.mode(.sketch))
        let requests = PhoneWire.takeRequests(from: &buffer)
        #expect(requests == [.mode(.sketch)])
        #expect(buffer.isEmpty)
    }

    @Test func aPictureLeavesADeclarationInProgressAlone() {
        var inbox = PhoneLibraryInbox()
        _ = inbox.apply(.library(count: 1))
        let picture = PhonePicture(width: 2, height: 2, isKeyframe: false, data: Data([1]))
        #expect(inbox.apply(.picture(picture)) == nil)
        #expect(inbox.isReceiving)
    }

    @Test func theNumbersAreFixedForEver() {
        // A case keeps its wire byte for ever, and the picture connection is its
        // own port beside the sensor stream.
        #expect(PhoneRequestKind.picture.rawValue == 4)
        #expect(PhoneCaptureMode.sketch.rawValue == 14)
        #expect(PhoneCaptureMode.sketch.title == "Sketch")
        #expect(PhoneWire.picturePort == 1339)
        #expect(PhoneWire.picturePort != PhoneWire.streamPort)
    }

    @Test func aPictureTooBigForOneFrameIsNotSent() {
        let fits = PhonePicture(width: 2, height: 2, isKeyframe: false,
                                data: Data(count: PhoneWire.maxPayloadBytes - 64))
        let over = PhonePicture(width: 2, height: 2, isKeyframe: false,
                                data: Data(count: PhoneWire.maxPayloadBytes))
        #expect(PhonePictureSender.fits(PhoneWire.encode(.picture(fits))))
        #expect(!PhonePictureSender.fits(PhoneWire.encode(.picture(over))))
    }

    @Test func aCanvasIsSentFittedAndEven() {
        // A square canvas fits whole; a 4K one comes down to the long side's cap
        // with its proportion; an odd size rounds down to even numbers.
        #expect(PhonePictureEncoder.pictureSize(width: 1080, height: 1080, maxSide: 1920) == (1080, 1080))
        #expect(PhonePictureEncoder.pictureSize(width: 3840, height: 2160, maxSide: 1920) == (1920, 1080))
        #expect(PhonePictureEncoder.pictureSize(width: 1081, height: 607, maxSide: 1920) == (1080, 606))
        #expect(PhonePictureEncoder.pictureSize(width: 0, height: 10, maxSide: 1920) == (0, 0))
    }

    @Test func theBitRateFollowsThePictureAndStaysInsideTheCable() {
        #expect(PhonePictureEncoder.bitRate(width: 1080, height: 1080, framesPerSecond: 60) == 8_748_000)
        #expect(PhonePictureEncoder.bitRate(width: 64, height: 64, framesPerSecond: 30) == 4_000_000)
        #expect(PhonePictureEncoder.bitRate(width: 3840, height: 2160, framesPerSecond: 120) == 40_000_000)
    }
}
