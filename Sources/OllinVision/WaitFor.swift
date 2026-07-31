import Foundation
import Ollin

/// Runs a one-shot vision call and blocks until its result is ready, so a
/// synchronous context can analyze a still image inline:
///
/// ```swift
/// let faces = try waitFor(photo) { try await FaceTracker.detect(in: $0) }
/// ```
///
/// Built for the places a sketch is synchronous by design: `setup()`, or a
/// deterministic export that must hold a result before its first frame
/// renders. Pass the image (or pair, for `FlowTracker.flow(from:to:)`) as an
/// argument rather than capturing it: `Image` isn't `Sendable`, and the
/// argument form is what carries it safely into the analysis task while the
/// caller waits.
///
/// Two cautions. It parks the calling thread until the analysis finishes, so
/// never call it from an async context (just `await` there), and don't await
/// main-actor work inside the closure (the main thread may be the one parked).
/// The common way to trip the second one is to read a property of the calling
/// sketch from inside the closure: a `Sketch` is main-actor isolated, stored
/// and static properties included, so the read waits on the thread that is
/// already waiting and the call hangs with no diagnostic. Read what the closure
/// needs into locals first.
///
/// A live sketch usually wants neither: start a `Task`, stash the result, and
/// keep drawing until it lands.
public func waitFor<T: Sendable>(
    _ image: Image,
    _ work: @escaping @Sendable (Image) async throws -> T
) throws -> T {
    try waitForBoxed([image]) { try await work($0[0]) }
}

/// The two-image form, for the calls that measure between a pair of stills
/// (`FlowTracker.flow(from: $0, to: $1)`). See `waitFor(_:_:)`.
public func waitFor<T: Sendable>(
    _ first: Image, _ second: Image,
    _ work: @escaping @Sendable (Image, Image) async throws -> T
) throws -> T {
    try waitForBoxed([first, second]) { try await work($0[0], $0[1]) }
}

/// The image-sequence form, for the calls that run across ordered frames
/// (`ObjectTracker.track(seed, across: $0)`, `TrajectoryTracker.detect(across: $0)`,
/// `FlowTracker.flow(across: $0)`). See `waitFor(_:_:)`.
public func waitFor<T: Sendable>(
    _ images: [Image],
    _ work: @escaping @Sendable ([Image]) async throws -> T
) throws -> T {
    try waitForBoxed(images, work)
}

/// The shared engine: carries the non-`Sendable` images across to a detached
/// analysis task inside an `@unchecked Sendable` box, parks the caller on a
/// semaphore, and hands the result (or error) back. Sound because the caller
/// is parked for the whole crossing: the images are never touched from two
/// threads at once, and the semaphore orders the result's trip back.
private final class WaitBox<Value>: @unchecked Sendable {
    let images: [Image]
    var result: Result<Value, Error>?
    let done = DispatchSemaphore(value: 0)
    init(_ images: [Image]) { self.images = images }
}

private func waitForBoxed<T: Sendable>(
    _ images: [Image],
    _ work: @escaping @Sendable ([Image]) async throws -> T
) throws -> T {
    let box = WaitBox<T>(images)
    Task.detached(priority: .userInitiated) {
        do { box.result = .success(try await work(box.images)) }
        catch { box.result = .failure(error) }
        box.done.signal()
    }
    box.done.wait()
    return try box.result!.get()
}
