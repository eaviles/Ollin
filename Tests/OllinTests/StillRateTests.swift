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

    /// `--at S` names the same moment in seconds of the sketch's clock, so
    /// nobody multiplies by the rate by hand: `--at 2` is `--frame 120` at 60
    /// fps, to the byte, and `--at 3 --fps 10` is the sequence's three-second
    /// frame, where `--frame 3` would be its third of a second.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStillTakesItsMomentInSeconds() throws {
        let bySeconds = ollinTempPath("ollin-still-at-2.png")
        let byFrame = ollinTempPath("ollin-still-frame-120.png")
        let slow = ollinTempPath("ollin-still-at-3-fps-10.png")
        defer { for p in [bySeconds, byFrame, slow] { try? FileManager.default.removeItem(atPath: p) } }
        #expect(OllinApp.handleCommandLine(["--export", bySeconds, "--at", "2"]) { Slider() })
        #expect(OllinApp.handleCommandLine(["--export", byFrame, "--frame", "120"]) { Slider() })
        #expect(OllinApp.handleCommandLine(["--export", slow, "--at", "3", "--fps", "10"]) { Slider() })
        // The pixels, not the files: the recipe each PNG carries names its own flags.
        #expect(try decoded(bySeconds) == decoded(byFrame))
        #expect(abs(try inkLeftEdge(of: bySeconds) - 40) <= 1)
        #expect(abs(try inkLeftEdge(of: slow) - 60) <= 1)
    }

    /// With both given, `--at` wins: the moment is the more specific ask.
    @Test func theMomentWinsOverTheFrame() throws {
        let path = ollinTempPath("ollin-still-at-wins.svg")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(OllinApp.handleCommandLine(["--export-svg", path, "--frame", "30", "--at", "1", "--fps", "10"]) { Slider() })
        let svg = try String(contentsOfFile: path, encoding: .utf8)
        let xs = svg.matches(of: /x="([0-9.]+)"/).compactMap { Double($0.output.1) }
        #expect(xs.contains { abs($0 - 20) < 0.01 }, "the bar's x in the file: \(xs)")
        #expect(OllinApp.stillFlags(["--at", "0.5", "--fps", "24"]).frame == 12)
        #expect(OllinApp.stillFlags(["--at", "nan"]).frame == 0)
    }

    @Test func theVectorStillCountsItsFrameAtTheGivenRate() throws {
        let path = ollinTempPath("ollin-still-rate.svg")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(OllinApp.handleCommandLine(["--export-svg", path, "--frame", "30", "--fps", "10"]) { Slider() })
        let svg = try String(contentsOfFile: path, encoding: .utf8)
        let xs = svg.matches(of: /x="([0-9.]+)"/).compactMap { Double($0.output.1) }
        #expect(xs.contains { abs($0 - 60) < 0.01 }, "the bar's x in the file: \(xs)")
    }

    /// The file's pixels, decoded.
    private func decoded(_ path: String) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        return pixels(of: try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
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
