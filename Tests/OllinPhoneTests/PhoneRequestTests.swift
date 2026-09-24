import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Ollin
import OllinPhone

/// Exercises the wire's **second direction**: the traffic that runs from the Mac
/// down to the phone: the request framing and its own tag space, the codec for
/// each request, the rule that assembles a declared library out of the frames that
/// carry it, and the Mac-side building of a reference from a file. All GPU-free
/// and CI-safe; nothing here needs a phone.
@Suite(.timeLimit(.minutes(1))) struct PhoneRequestTests {

    // MARK: Round-trips

    @Test func roundTripsMode() {
        for mode in PhoneCaptureMode.allCases {
            #expect(roundTrip(.mode(mode)) == .mode(mode))
        }
    }

    @Test func roundTripsLibraryCount() {
        #expect(roundTrip(.library(count: 0)) == .library(count: 0))
        #expect(roundTrip(.library(count: 3)) == .library(count: 3))
    }

    @Test func roundTripsPicture() {
        // A name that leaves ASCII, a real printed width, and bytes that are not
        // text: a reference is a file, so the payload must survive any byte.
        let contents = Data((0...255).map { UInt8($0) })
        let reference = PhoneReference(name: "cartel café", kind: .image,
                                       printedWidth: 0.297, contents: contents)
        #expect(roundTrip(.reference(reference)) == .reference(reference))
    }

    @Test func roundTripsObject() {
        // A scanned object carries no width, and its archive is opaque bytes.
        let reference = PhoneReference(name: "teapot", kind: .object,
                                       printedWidth: 0, contents: Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(roundTrip(.reference(reference)) == .reference(reference))
    }

    @Test func roundTripsEmptyPicture() {
        // The degenerate reference: a name and nothing else. The codec must carry
        // it rather than read the next field out of the missing bytes.
        let reference = PhoneReference(name: "", kind: .image, printedWidth: 0, contents: Data())
        #expect(roundTrip(.reference(reference)) == .reference(reference))
    }

    // MARK: The two directions never mix

    @Test func aSensorFrameIsNotARequest() {
        // The whole point of the separate magic: a frame meant for the Mac, written
        // down the cable by mistake, fails at the header instead of decoding as
        // whichever request shares its kind byte (a body pose is kind 2, and so is
        // a library declaration).
        let sensorFrame = PhoneWire.encode(.pose([]))
        #expect(PhoneHeader.parse(sensorFrame)?.kind == .bodyPose)
        #expect(PhoneRequestHeader.parse(sensorFrame) == nil)
    }

    @Test func aRequestIsNotASensorFrame() {
        let request = PhoneWire.encode(.library(count: 2))
        #expect(PhoneRequestHeader.parse(request)?.kind == .library)
        #expect(PhoneHeader.parse(request) == nil)
    }

    @Test func theTwoTagSpacesOverlapOnPurpose() {
        // Both spaces start at 1 and are free to collide, because a frame's
        // direction is decided by which end reads it. The test states that, so a
        // later reader does not "fix" it by renumbering.
        #expect(PhoneRequestKind.mode.rawValue == PhoneMessageKind.deviceMotion.rawValue)
        #expect(PhoneWire.requestMagic != PhoneWire.magic)
    }

    // MARK: Header validation

    @Test func parsesRequestHeader() {
        let data = PhoneWire.encode(.mode(.markers))
        let header = PhoneRequestHeader.parse(data)
        #expect(header?.kind == .mode)
        #expect(header?.payloadLength == data.count - PhoneWire.headerByteCount)
    }

    @Test func rejectsBadRequestMagic() {
        var data = PhoneWire.encode(.mode(.body))
        data[0] = 0xFF
        #expect(PhoneRequestHeader.parse(data) == nil)
    }

    @Test func rejectsWrongRequestVersion() {
        var data = PhoneWire.encode(.mode(.body))
        data[4] = PhoneWire.version &+ 1
        #expect(PhoneRequestHeader.parse(data) == nil)
    }

    @Test func rejectsUnknownRequestKind() {
        var data = PhoneWire.encode(.mode(.body))
        data[5] = 0x7F
        #expect(PhoneRequestHeader.parse(data) == nil)
    }

    @Test func rejectsShortRequestHeader() {
        #expect(PhoneRequestHeader.parse(Data([0x52, 0x4E])) == nil)
    }

    @Test func rejectsUnknownMode() {
        // A mode byte from a newer app than this build knows: skip the frame rather
        // than switch to a mode that is not in the list.
        let header = PhoneRequestHeader(kind: .mode, payloadLength: 1)
        #expect(PhoneWire.decode(header: header, payload: Data([200])) == nil)
    }

    @Test func rejectsTruncatedReference() {
        // A valid header with a payload cut mid-file: the decoder must say nothing
        // rather than hand back a picture missing its tail.
        let reference = PhoneReference(name: "poster", kind: .image,
                                       printedWidth: 0.3, contents: Data(repeating: 7, count: 64))
        let frame = PhoneWire.encode(.reference(reference))
        let start = frame.startIndex + PhoneWire.headerByteCount
        let payload = frame.subdata(in: start ..< (frame.endIndex - 8))
        let header = PhoneRequestHeader(kind: .reference, payloadLength: payload.count)
        #expect(PhoneWire.decode(header: header, payload: payload) == nil)
    }

    @Test func refusesAnAbsurdLibrary() {
        // A count past the cap is refused whole rather than truncated: a sketch
        // asking for five hundred pictures has a bug, and staging them would cost
        // the phone its memory.
        var payload = Data()
        let count = UInt32(PhoneWire.maxReferences + 1)
        for shift in stride(from: 0, to: 32, by: 8) { payload.append(UInt8((count >> shift) & 0xFF)) }
        let header = PhoneRequestHeader(kind: .library, payloadLength: payload.count)
        #expect(PhoneWire.decode(header: header, payload: payload) == nil)
        // And the encoder never writes one: a longer list is clamped on the way out.
        #expect(roundTrip(.library(count: 9_000)) == .library(count: PhoneWire.maxReferences))
    }

    // MARK: Assembling a declared library

    @Test func commitsOnTheFrameThatCompletesIt() {
        var inbox = PhoneLibraryInbox()
        #expect(inbox.apply(.library(count: 2)) == nil)
        #expect(inbox.isReceiving)
        #expect(inbox.apply(.reference(picture("a"))) == nil)
        let library = inbox.apply(.reference(picture("b")))
        #expect(library?.map(\.name) == ["a", "b"])
        #expect(!inbox.isReceiving)
        #expect(inbox.staged.isEmpty)
    }

    @Test func anEmptyLibraryCommitsAtOnce() {
        // "Look for nothing" has no reference frames to arrive, so the declaration
        // must complete on its own frame, or a sketch could never clear one.
        var inbox = PhoneLibraryInbox()
        #expect(inbox.apply(.library(count: 0))?.isEmpty == true)   // committed, and empty
        #expect(!inbox.isReceiving)
    }

    @Test func aStrayReferenceIsDropped() {
        // No declaration open: a reference that arrives alone is not a library of
        // one, it is a frame from a declaration that was thrown away.
        var inbox = PhoneLibraryInbox()
        #expect(inbox.apply(.reference(picture("orphan"))) == nil)
        #expect(inbox.staged.isEmpty)
        #expect(!inbox.isReceiving)
    }

    @Test func aNewDeclarationThrowsAwayAHalfStagedOne() {
        var inbox = PhoneLibraryInbox()
        _ = inbox.apply(.library(count: 3))
        _ = inbox.apply(.reference(picture("old")))
        #expect(inbox.staged.count == 1)
        #expect(inbox.apply(.library(count: 1)) == nil)
        #expect(inbox.staged.isEmpty)
        let library = inbox.apply(.reference(picture("new")))
        #expect(library?.map(\.name) == ["new"])
    }

    @Test func aHalfReceivedLibraryNeverCommits() {
        // The cable comes out mid-declaration: nothing is handed over, so the phone
        // keeps looking for whatever it was looking for before.
        var inbox = PhoneLibraryInbox()
        _ = inbox.apply(.library(count: 3))
        #expect(inbox.apply(.reference(picture("a"))) == nil)
        #expect(inbox.apply(.reference(picture("b"))) == nil)
        #expect(inbox.isReceiving)
    }

    @Test func aModeRequestLeavesADeclarationAlone() {
        // The two kinds of traffic share one stream, so a mode request arriving
        // between two references must not disturb the set being assembled.
        var inbox = PhoneLibraryInbox()
        _ = inbox.apply(.library(count: 2))
        _ = inbox.apply(.reference(picture("a")))
        #expect(inbox.apply(.mode(.markers)) == nil)
        #expect(inbox.staged.count == 1)
        let library = inbox.apply(.reference(picture("b")))
        #expect(library?.count == 2)
    }

    // MARK: Pulling frames off a stream

    @Test func readsFramesSplitAcrossReads() {
        // TCP says nothing about where one read ends, so the same three frames must
        // come out whether they arrive whole, one byte at a time, or in any other
        // split. Every prime chunk size is tried, which lands cuts inside a header
        // and inside a payload.
        let frames = PhoneWire.encode(.mode(.markers))
            + PhoneWire.encode(.library(count: 1))
            + PhoneWire.encode(.reference(picture("blankets")))
        let expected: [PhoneRequest] = [.mode(.markers), .library(count: 1),
                                        .reference(picture("blankets"))]
        for chunk in [1, 2, 3, 7, 13, 11, frames.count] {
            var buffer = Data()
            var out: [PhoneRequest] = []
            var offset = frames.startIndex
            while offset < frames.endIndex {
                let end = min(offset + chunk, frames.endIndex)
                buffer.append(frames.subdata(in: offset ..< end))
                offset = end
                guard let taken = PhoneWire.takeRequests(from: &buffer) else {
                    return #expect(Bool(false), "the stream was refused at chunk \(chunk)")
                }
                out += taken
            }
            #expect(out == expected, "chunk size \(chunk)")
            #expect(buffer.isEmpty)
        }
    }

    @Test func holdsAPartialFrame() {
        // Half a frame is not an error, it is the rest of a read that has not
        // arrived: nothing comes out, and the bytes stay for the next chunk.
        let frame = PhoneWire.encode(.reference(picture("half")))
        var buffer = frame.subdata(in: frame.startIndex ..< (frame.endIndex - 4))
        let held = buffer.count
        #expect(PhoneWire.takeRequests(from: &buffer)?.isEmpty == true)   // in step, nothing whole
        #expect(buffer.count == held)
        buffer.append(frame.subdata(in: (frame.endIndex - 4) ..< frame.endIndex))
        #expect(PhoneWire.takeRequests(from: &buffer)?.count == 1)
        #expect(buffer.isEmpty)
    }

    @Test func refusesAStreamThatIsNotThisFraming() {
        // A sensor frame written down the cable, or somebody else's tool: the whole
        // connection goes, because there is no way to know where the next frame
        // would start.
        var buffer = PhoneWire.encode(.pose([]))
        #expect(PhoneWire.takeRequests(from: &buffer) == nil)
    }

    @Test func skipsAFrameThatWillNotDecode() {
        // Framed correctly, but the payload is nonsense: the stream is still in
        // step, so that one frame is dropped and the next is read.
        var buffer = Data()
        var bad = PhoneWire.encode(.mode(.markers))
        bad[bad.startIndex + PhoneWire.headerByteCount] = 200        // no such mode
        buffer.append(bad)
        buffer.append(PhoneWire.encode(.library(count: 2)))
        #expect(PhoneWire.takeRequests(from: &buffer) == [.library(count: 2)])
        #expect(buffer.isEmpty)
    }

    // MARK: The mode list

    @Test func modeRawValuesAreContiguousFromOne() {
        // The wire carries a mode as one byte, and zero is never a mode, so a
        // zeroed byte can't read as one.
        let raws = PhoneCaptureMode.allCases.map { Int($0.rawValue) }
        #expect(raws == Array(1...PhoneCaptureMode.allCases.count))
        #expect(PhoneCaptureMode(rawValue: 0) == nil)
    }

    @Test func everyModeHasItsOwnTitle() {
        let titles = Set(PhoneCaptureMode.allCases.map(\.title))
        #expect(titles.count == PhoneCaptureMode.allCases.count)
        #expect(PhoneCaptureMode.markers.title == "Markers")
    }

    // MARK: The phone's answer

    @Test func roundTripsState() {
        let state = PhoneStateSample(timestamp: 12.5, mode: .markers, isSupported: true,
                                     referenceCount: 2, referencesAreDeclared: true,
                                     status: "Looking for what the sketch sent",
                                     notes: ["cartel is hard to recognize: not enough detail.",
                                             "teapot would not read as a scanned object."])
        let data = PhoneWire.encode(.state(state))
        guard let header = PhoneHeader.parse(data) else { return #expect(Bool(false)) }
        let payload = data.subdata(in: (data.startIndex + PhoneWire.headerByteCount) ..< data.endIndex)
        #expect(PhoneWire.decode(header: header, payload: payload) == .state(state))
    }

    @Test func roundTripsBareState() {
        let state = PhoneStateSample(timestamp: 0, mode: .body)
        let data = PhoneWire.encode(.state(state))
        guard let header = PhoneHeader.parse(data) else { return #expect(Bool(false)) }
        let payload = data.subdata(in: (data.startIndex + PhoneWire.headerByteCount) ..< data.endIndex)
        #expect(PhoneWire.decode(header: header, payload: payload) == .state(state))
    }

    // MARK: Building a reference on the Mac

    @Test func readsAPictureFromAPath() throws {
        let url = try write(picturePNG(width: 64, height: 40), as: "poster@30cm.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = try PhoneReference.picture(path: url.path, printedWidth: 0.3)
        // The name is the file's own, with the stated size taken off: the same rule
        // the capture app's folder uses, so one picture declares one marker either way.
        #expect(reference.name == "poster")
        #expect(reference.kind == .image)
        #expect(reference.printedWidth == 0.3)
        // Small enough already, so the file's own bytes travel: a hand-made PNG
        // reaches the phone exactly as the sketch shipped it.
        #expect(reference.contents == (try Data(contentsOf: url)))
    }

    @Test func fitsAPictureTooBigForTheCable() throws {
        let url = try write(picturePNG(width: 3000, height: 2000), as: "wall.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = try PhoneReference.picture(path: url.path, printedWidth: 1.2)
        #expect(reference.contents.count <= PhoneWire.maxPayloadBytes)
        let source = try #require(CGImageSourceCreateWithData(reference.contents as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) == PhoneReference.maxPictureEdge)
        // The shape is kept, so a print's own proportions still measure right.
        #expect(abs(Double(image.width) / Double(image.height) - 1.5) < 0.01)
    }

    @Test func namesAPictureWhenAskedTo() throws {
        let url = try write(picturePNG(width: 32, height: 32), as: "IMG_4021.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = try PhoneReference.picture(path: url.path, printedWidth: 0.1,
                                                            named: "the card")
        #expect(reference.name == "the card")
    }

    @Test func refusesAFileThatIsNotThere() {
        let picture = #expect(throws: FileError.self) {
            try PhoneReference.picture(path: "/nowhere/at/all.png", printedWidth: 0.2)
        }
        #expect(picture?.kind == .missing)
        let object = #expect(throws: FileError.self) {
            try PhoneReference.object(path: "/nowhere/at/all.arobject")
        }
        #expect(object?.kind == .missing)
    }

    @Test func refusesPixelsThatWillNotRead() throws {
        let url = try write(Data("not a picture".utf8), as: "broken.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let error = #expect(throws: FileError.self) {
            try PhoneReference.picture(path: url.path, printedWidth: 0.2)
        }
        #expect(error?.kind == .unreadable)
    }

    @Test func readsAScannedObject() throws {
        // An object archive is opaque to us, so it travels byte for byte and
        // carries no width of its own.
        let url = try write(Data([0x50, 0x4B, 0x03, 0x04, 9, 9]), as: "teapot.arobject")
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = try PhoneReference.object(path: url.path)
        #expect(reference.name == "teapot")
        #expect(reference.kind == .object)
        #expect(reference.printedWidth == 0)
        #expect(reference.contents.count == 6)
    }

    // MARK: Helpers

    private func picture(_ name: String) -> PhoneReference {
        PhoneReference(name: name, kind: .image, printedWidth: 0.2,
                       contents: Data(name.utf8))
    }

    /// A PNG with enough going on that it encodes to something, drawn as a coarse
    /// checker so a resize has a shape to keep.
    private func picturePNG(width: Int, height: Int) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let step = max(8, width / 16)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let dark = ((x / step) + (y / step)) % 2 == 0
                context.setFillColor(gray: dark ? 0.1 : 0.9, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: step, height: step))
            }
        }
        let image = context.makeImage()!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// Write a file under a folder of this run's own, so two test processes
    /// sharing one checkout never collide on a fixed temporary path.
    private func write(_ data: Data, as name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-phone-references-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// Encode a request, split the framed bytes back into header + payload the way
    /// the phone's reader does, and decode: the full trip down the cable.
    private func roundTrip(_ request: PhoneRequest) -> PhoneRequest? {
        let data = PhoneWire.encode(request)
        guard let header = PhoneRequestHeader.parse(data) else { return nil }
        let start = data.startIndex + PhoneWire.headerByteCount
        let payload = data.subdata(in: start ..< data.endIndex)
        return PhoneWire.decode(header: header, payload: payload)
    }
}
