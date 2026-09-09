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
