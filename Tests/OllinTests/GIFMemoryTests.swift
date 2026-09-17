import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// A GIF is written as it is drawn, so what it asks of memory does not move
/// with the frame count. These read that off the writer's own books and off
/// the process.
@Suite
struct GIFMemoryTests {

    /// The bytes this process holds right now, as the kernel counts them.
    static func footprint() -> Int {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Int(info.ri_phys_footprint) : -1
    }

    /// A frame with a disc somewhere new in it, so no two frames are alike.
    static func frame(side: Int, _ k: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.2, alpha: 1))
        let x = Double(side) * (0.1 + 0.8 * Double(k % 50) / 49), y = Double(side) * (0.2 + 0.6 * Double(k % 7) / 6)
        context.fillEllipse(in: CGRect(x: x - 30, y: y - 30, width: 60, height: 60))
        return context.makeImage()!
    }

    /// The writer's buffers are sized once: the same bytes after one frame
    /// and after sixty.
    @Test func theWriterHoldsNoFrame() throws {
        let path = NSTemporaryDirectory() + "ollin-gif-held-\(UUID().uuidString).gif"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let side = 240
        let writer = try GIFWriter(path: path, width: side, height: side)
        try writer.append(Self.frame(side: side, 0), delay: 0.04)
        let afterOne = writer.heldBytes
        for k in 1..<60 { try writer.append(Self.frame(side: side, k), delay: 0.04) }
        try writer.finish()
        #expect(writer.heldBytes == afterOne)
        // Under twenty bytes a pixel, against the ten a frame the old writer
        // kept for every frame of the run.
        #expect(afterOne < side * side * 20 + 8 * 1024 * 1024)
    }

    /// The process footprint after two hundred frames is where it was after
    /// ten. Holding the frames would have added about 175 MB at this size
    /// (190 frames of four bytes a pixel); the bound is half of that. The
    /// footprint is the whole process's, and the suite shares its process
    /// with every other suite in the shard, so the room is for whatever they
    /// allocate in the same seconds: a bound of 40 MB measured 44 on the
    /// runner with the writer holding nothing (2026-09-17).
    @Test func thePeakIsFlatInTheFrameCount() throws {
        let path = NSTemporaryDirectory() + "ollin-gif-flat-\(UUID().uuidString).gif"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let side = 480, frames = 200
        let writer = try GIFWriter(path: path, width: side, height: side)
        var afterTen = 0
        for k in 0..<frames {
            try autoreleasepool { try writer.append(Self.frame(side: side, k), delay: 0.04) }
            if k == 9 { afterTen = Self.footprint() }
        }
        let afterAll = Self.footprint()
        try writer.finish()
        try #require(afterTen > 0 && afterAll > 0)
        let grew = afterAll - afterTen
        let held = (frames - 10) * side * side * 4
        #expect(grew < held / 2, "grew \(grew / 1_048_576) MB over \(frames - 10) frames that would hold \(held / 1_048_576) MB")
    }
}
