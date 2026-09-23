import CoreGraphics
import Foundation
import ImageIO
@testable import Ollin
import Testing

/// A one-frame export counts its frame at the rate `--fps` names, the way
/// the sequence does: `--frame 30 --fps 10` is the moment a 10 fps sequence
/// puts at its thirty-first frame, three seconds in, not the half second
/// that thirty frames make at 60. The flag used to be read by the sequence
/// and grid paths only, so a still and the sequence it was meant to match
/// disagreed at every rate but 60 (found by a sketch comparing the two,
/// 2026-09-22).
@Suite(.serialized)
@MainActor
struct StillRateTests {

    /// An 8 px bar whose left edge sits at 20 px per second of the clock.
    final class Slider: Sketch {
        override var canvasSize: CanvasSize { .square(128) }
        override func draw() {
            background(.white)
            fill(.black)
            noStroke()
            drawRect(20 * time, 60, 8, 8)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theStillCountsItsFrameAtTheGivenRate() throws {
        let slow = ollinTempPath("ollin-still-rate-10.png")
        let fast = ollinTempPath("ollin-still-rate-60.png")
        defer { for p in [slow, fast] { try? FileManager.default.removeItem(atPath: p) } }
        #expect(OllinApp.handleCommandLine(["--export", slow, "--frame", "30", "--fps", "10"]) { Slider() })
        #expect(OllinApp.handleCommandLine(["--export", fast, "--frame", "30", "--fps", "60"]) { Slider() })
        // Three seconds at 10 fps puts the bar at 60; half a second at 60 fps at 10.
        #expect(abs(try inkLeftEdge(of: slow) - 60) <= 1)
        #expect(abs(try inkLeftEdge(of: fast) - 10) <= 1)
    }

    @Test func theVectorStillCountsItsFrameAtTheGivenRate() throws {
        let path = ollinTempPath("ollin-still-rate.svg")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(OllinApp.handleCommandLine(["--export-svg", path, "--frame", "30", "--fps", "10"]) { Slider() })
        let svg = try String(contentsOfFile: path, encoding: .utf8)
        let xs = svg.matches(of: /x="([0-9.]+)"/).compactMap { Double($0.output.1) }
        #expect(xs.contains { abs($0 - 60) < 0.01 }, "the bar's x in the file: \(xs)")
    }

    /// The leftmost column holding ink on the bar's row, in pixels.
    private func inkLeftEdge(of path: String) throws -> Double {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &bytes, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let row = 64                                       // the bar spans rows 60 to 68
        for x in 0..<width where bytes[(row * width + x) * 4] < 128 { return Double(x) }
        throw NoInk()
    }

    private struct NoInk: Error {}
}
