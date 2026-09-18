import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import Ollin

/// How many frame buffers the system has actually freed, counted by the
/// frames themselves. A frame is built over memory this owns, and the release
/// callback that memory carries is what says the frame is gone.
final class GIFFrameTally: Sendable {
    let freed = Atomic<Int>(0)
}

/// Called by the system when a frame's pixels are let go, on whichever thread
/// drops the last reference, which is why the count is atomic.
private func gifFrameFreed(_ info: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer, _ size: Int) {
    UnsafeMutableRawPointer(mutating: data).deallocate()
    guard let info else { return }
    Unmanaged<GIFFrameTally>.fromOpaque(info).takeUnretainedValue().freed.add(1, ordering: .relaxed)
}

/// A GIF is written as it is drawn, so what it asks of memory does not move
/// with the frame count. Both halves of that are read off the writer and off
/// the frames themselves: what the writer keeps between frames, and whether a
/// frame it was handed survives the call.
///
/// Deliberately not read off the process footprint, which is what these did
/// until a run on the CI runner showed why. The suite shares its process with
/// every other suite in its shard, so that number is the sum of what all of
/// them are doing in the same seconds: it went 144 MB past a bound of 87 MB
/// on a writer holding nothing, and it would equally have come in under the
/// bound while leaking, had a neighbor freed as much in the same window. A
/// measurement that can fail either way on somebody else's work is not
/// evidence. What is given up with it: a field accumulating somewhere outside
/// `heldBytes` would now go unseen, and the footprint could not have caught
/// that reliably either.
@Suite
struct GIFMemoryTests {

    /// A frame with a disc somewhere new in it, so no two frames are alike,
    /// drawn into memory whose release the test can see.
    static func frame(side: Int, _ k: Int, tally: GIFFrameTally) -> CGImage {
        let bytes = side * side * 4
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: raw, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.2, alpha: 1))
        let x = Double(side) * (0.1 + 0.8 * Double(k % 50) / 49), y = Double(side) * (0.2 + 0.6 * Double(k % 7) / 6)
        context.fillEllipse(in: CGRect(x: x - 30, y: y - 30, width: 60, height: 60))

        // The image reads that same memory, and hands it back through the
        // callback when it is let go. The context above never owns it.
        let provider = CGDataProvider(dataInfo: Unmanaged.passUnretained(tally).toOpaque(),
                                      data: raw, size: bytes, releaseData: gifFrameFreed)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// The writer's buffers are sized once: the same bytes after one frame
    /// and after two hundred, at a size where holding them would be plain.
    @Test func theWriterHoldsNoFrame() throws {
        let path = NSTemporaryDirectory() + "ollin-gif-held-\(UUID().uuidString).gif"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tally = GIFFrameTally()
        let side = 480, frames = 200
        let writer = try GIFWriter(path: path, width: side, height: side)

        try autoreleasepool { try writer.append(Self.frame(side: side, 0, tally: tally), delay: 0.04) }
        let afterOne = writer.heldBytes
        for k in 1..<frames {
            try autoreleasepool { try writer.append(Self.frame(side: side, k, tally: tally), delay: 0.04) }
        }
        try writer.finish()

        #expect(writer.heldBytes == afterOne,
                "the writer holds the same bytes after \(frames) frames as after one")
        // Under twenty bytes a pixel, against the ten a frame the old writer
        // kept for every frame of the run.
        #expect(afterOne < side * side * 20 + 8 * 1024 * 1024)
        withExtendedLifetime(tally) {}
    }

    /// No frame handed to the writer survives the call that took it. Holding
    /// them is what would have moved the peak with the frame count, and this
    /// reads it off the frames rather than off a number the whole process
    /// shares.
    @Test func theWriterKeepsNoFrameItWasHanded() throws {
        let path = NSTemporaryDirectory() + "ollin-gif-flat-\(UUID().uuidString).gif"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tally = GIFFrameTally()
        let side = 480, frames = 200
        let writer = try GIFWriter(path: path, width: side, height: side)

        var everBehind = 0
        for k in 0..<frames {
            try autoreleasepool { try writer.append(Self.frame(side: side, k, tally: tally), delay: 0.04) }
            // Every frame appended so far has been let go by now, so the
            // count never falls behind the run. Measured as a high-water mark
            // rather than expected each time round, so a failure reports the
            // worst of the run instead of two hundred times.
            everBehind = max(everBehind, k + 1 - tally.freed.load(ordering: .relaxed))
        }
        #expect(everBehind == 0,
                "the writer was holding \(everBehind) frames at once; it must keep none")

        let freed = tally.freed.load(ordering: .relaxed)
        #expect(freed == frames,
                "all \(frames) frames must be freed before the file is finished, and \(freed) were")
        try writer.finish()
        withExtendedLifetime(tally) {}
    }
}
