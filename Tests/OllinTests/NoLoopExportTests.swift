import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// A sketch that stops its loop is held at the frame it stopped on, by every
/// export, the way a window holds it: the window draws such a sketch once and
/// shows that frame from then on, so an export that drew every frame up to
/// the one asked for wrote a picture nobody saw, and a slow still took as many
/// draws as the frame number. Each probe rolls the sketch's dice in its draw,
/// so a second draw is a different picture and a held one is not.
@Suite @MainActor struct NoLoopExportTests {

    /// A dot at a random place, the sketch's own dice, every draw. `stopAt` is
    /// the draw that calls `noLoop()`: 0 stops in `setup()`, a negative number
    /// never stops.
    final class Dice: Sketch {
        var stopAt = 0
        var draws = 0

        static func make(stopAt: Int = 0) -> Dice {
            let sketch = Dice()
            sketch.stopAt = stopAt
            return sketch
        }

        override var canvasSize: CanvasSize { .square(96) }
        override func setup() {
            seed(11)
            if stopAt == 0 { noLoop() }
        }
        override func draw() {
            draws += 1
            background(.white)
            noStroke()
            fill(.black)
            drawCircle(random(12, 84), random(12, 84), 8)
            if draws == stopAt { noLoop() }
        }
    }

    private func bytes(_ image: CGImage) -> Data {
        let width = image.width, height = image.height
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    /// Stopped in `setup()`, the sketch is drawn once whatever frame is asked
    /// for, and that is the picture: the one its first frame shows. The control
    /// is the same sketch left looping, whose later frame is somewhere else.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillIsDrawnOnce() throws {
        let held = Dice.make()
        let late = try OllinApp.image(of: held, frame: 30)
        #expect(held.draws == 1)
        let first = try OllinApp.image(of: Dice.make(), frame: 0)
        #expect(bytes(late) == bytes(first))

        let looping = try OllinApp.image(of: Dice.make(stopAt: -1), frame: 30)
        #expect(bytes(looping) != bytes(first))
    }

    /// Stopped by its sixth draw, the sketch is held at that frame (the sixth,
    /// frame 5), the frame a window would still be showing at frame 30.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSketchThatStopsLaterIsHeldWhereItStopped() throws {
        let held = Dice.make(stopAt: 6)
        let late = try OllinApp.image(of: held, frame: 30)
        #expect(held.draws == 6)
        let sixth = try OllinApp.image(of: Dice.make(stopAt: 6), frame: 5)
        #expect(bytes(late) == bytes(sixth))
    }

    /// A sequence (the drive under the video, the GIF, and the PNG sequence)
    /// writes every frame it was asked for, and from the frame the loop
    /// stopped on, every one of them is that frame, with nothing drawn again.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSequenceHoldsTheFrameTheLoopStoppedOn() throws {
        let sketch = Dice.make(stopAt: 3)
        var frames: [Data] = []
        try OllinApp.renderFrames(sketch, frames: 8, fps: 60, skipSeconds: 0) { frame, _ in
            frames.append(bytes(try #require(frame.image)))
        }
        #expect(sketch.draws == 3)
        #expect(frames.count == 8)
        #expect(frames[0] != frames[1] && frames[1] != frames[2])
        #expect(frames[3...].allSatisfy { $0 == frames[2] })
    }

    /// Held during the warmup a `--skip` runs, the sketch is rendered once,
    /// and the whole file is that frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSketchHeldDuringTheWarmupFillsTheFile() throws {
        let sketch = Dice.make(stopAt: 2)
        var frames: [Data] = []
        try OllinApp.renderFrames(sketch, frames: 4, fps: 60, skipSeconds: 0.1) { frame, _ in
            frames.append(bytes(try #require(frame.image)))
        }
        #expect(sketch.draws == 2)
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0 == frames[0] })
        let second = try OllinApp.image(of: Dice.make(stopAt: 2), frame: 1)
        #expect(frames[0] == bytes(second))
    }

    /// The vector export writes the frame the loop stopped on. The file's
    /// recipe comment names the frame asked for, so the drawing is compared
    /// with that one line left out.
    @Test func aVectorFileHoldsTheFrameTheLoopStoppedOn() {
        func drawing(_ svg: String) -> String {
            svg.split(separator: "\n").filter { !$0.contains("<!--") }.joined(separator: "\n")
        }
        let held = Dice.make(stopAt: 4)
        let late = drawing(OllinApp.svg(of: held, frame: 20))
        #expect(held.draws == 4)
        #expect(late == drawing(OllinApp.svg(of: Dice.make(stopAt: 4), frame: 3)))
        #expect(late != drawing(OllinApp.svg(of: Dice.make(stopAt: 4), frame: 2)))
    }

    /// A web page records what the renderer was handed, and a sketch stopped
    /// in `setup()` hands it one frame: a page of one frame, held still.
    @Test func aPageOfAStillIsOneFrame() throws {
        let sketch = Dice.make()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 10, fps: 60, controls: false)
        #expect(recording.frames.count == 1)
        #expect(sketch.draws == 1)
    }
}
