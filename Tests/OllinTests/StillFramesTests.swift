import Foundation
import Testing
@testable import Ollin

/// A still picture standing in for a camera: it is a feed with a frame ready
/// before anything asks, and it hands that frame over the moment a tap is
/// installed rather than making an analyzer wait for the next publish.
@Suite @MainActor struct StillFramesTests {

    private func picture() -> Image {
        let image = Image(width: 40, height: 30, color: .white)
        image[10, 10] = .red
        return image
    }

    @Test func theFrameIsReadyBeforeAnythingAsks() {
        let feed = StillFrames(picture())
        // Unlike a camera, which has nothing until its first capture lands, so
        // `drawFrame` never shows a waiting notice for a still.
        #expect(feed.frame != nil)
        #expect(feed.frameSize == Vector2(40, 30))
    }

    @Test func installingATapDeliversTheFrameAtOnce() {
        let feed = StillFrames(picture())
        let delivered = Locked(0)
        feed.frameTap = { image in
            delivered.withLock { $0 += 1 }
            #expect(image.width == 40)
            #expect(image.height == 30)
        }
        // No `start()`, no waiting on the publishing thread: setting the tap is
        // what delivers, so an analyzer attached at any moment is told at once.
        #expect(delivered.withLock { $0 } == 1)
    }

    @Test func theRateNeverFallsToZero() {
        // A rate of zero would divide into an infinite sleep, so it is floored.
        #expect(StillFrames(picture(), rate: 0).rate > 0)
        #expect(StillFrames(picture(), rate: -5).rate > 0)
        #expect(StillFrames(picture(), rate: 12).rate == 12)
    }
}

/// A tiny box for counting across the tap closure, which is `@Sendable`.
private final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

/// Taking a shape out of a picture, the companion to resizing it.
@Suite struct ImageCropTests {

    private func striped() -> Image {
        // 40 by 20, left half red and right half blue, so a crop's contents are
        // checkable by reading one pixel.
        let image = Image(width: 40, height: 20, color: .white)
        for y in 0 ..< 20 {
            for x in 0 ..< 40 { image[x, y] = x < 20 ? .red : .blue }
        }
        return image
    }

    @Test func aCropTakesTheRectangleItIsGiven() {
        let piece = striped().cropped(x: 20, y: 5, width: 10, height: 10)
        #expect(piece.width == 10)
        #expect(piece.height == 10)
        // Entirely inside the blue half.
        #expect(piece[0, 0].blue > 0.9)
        #expect(piece[9, 9].blue > 0.9)
    }

    @Test func aCropOffTheEdgeComesBackSmallerRatherThanEmpty() {
        let piece = striped().cropped(x: 30, y: 0, width: 100, height: 100)
        #expect(piece.width == 10)
        #expect(piece.height == 20)
        let far = striped().cropped(x: 999, y: 999, width: 10, height: 10)
        #expect(far.width >= 1)
        #expect(far.height >= 1)
    }

    @Test func anAspectCropIsCenteredAndScalesNothing() {
        // A square out of a 2:1 picture keeps the full height and the middle
        // half of the width.
        let square = striped().cropped(toAspect: 1)
        #expect(square.width == 20)
        #expect(square.height == 20)
        // The middle of a left-red right-blue picture straddles both.
        #expect(square[0, 0].red > 0.9)
        #expect(square[19, 0].blue > 0.9)

        // A wide slice out of the same picture keeps the full width.
        let wide = striped().cropped(toAspect: 4)
        #expect(wide.width == 40)
        #expect(wide.height == 10)
    }
}
