import Foundation
internal import CJolt

// Tuple ↔ C-array marshaling for the solver bridge. The C side takes and
// fills fixed-size float arrays; on the Swift side those are homogeneous
// tuples, and the ONE legal way to hand their storage across is
// `withUnsafe(Mutable)Bytes(of:)` over the whole tuple. A pointer taken to
// `&tuple.0` is valid for that single element only, and the compiler is free
// to materialize a temporary for it, silently dropping every element the C
// side writes past the first (a real bug this file exists to prevent).

/// Calls `body` with a pointer the C side fills with `count` floats, and
/// returns them as a tuple's storage.
func readFloats3(_ body: (UnsafeMutablePointer<Float>) -> Void) -> (Float, Float, Float) {
    var out: (Float, Float, Float) = (0, 0, 0)
    withUnsafeMutableBytes(of: &out) {
        body($0.baseAddress!.assumingMemoryBound(to: Float.self))
    }
    return out
}

func readFloats4(_ body: (UnsafeMutablePointer<Float>) -> Void) -> (Float, Float, Float, Float) {
    var out: (Float, Float, Float, Float) = (0, 0, 0, 1)
    withUnsafeMutableBytes(of: &out) {
        body($0.baseAddress!.assumingMemoryBound(to: Float.self))
    }
    return out
}

/// Calls `body` with a pointer to three floats the C side reads.
func withFloats3(_ values: (Float, Float, Float),
                 _ body: (UnsafePointer<Float>) -> Void) {
    withUnsafeBytes(of: values) {
        body($0.baseAddress!.assumingMemoryBound(to: Float.self))
    }
}

/// Scratch storage for a shape description's flat data (hull points, mesh
/// indices, height-field samples, compound child descriptors): plain
/// allocations the arena owns and frees, pinned for as long as the arena
/// lives. Compound colliders make the number of buffers data-dependent (one
/// per child, recursively), which rules out the fixed
/// `withUnsafeBufferPointer` nesting the simple shapes used; keep the arena
/// alive across the create call with `withExtendedLifetime`.
final class ShapeDescArena {
    private var deallocators: [() -> Void] = []

    /// Copies `values` into arena-owned storage and returns its base pointer
    /// (`nil` for an empty array).
    func store<T>(_ values: [T]) -> UnsafePointer<T>? {
        guard !values.isEmpty else { return nil }
        let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: values.count)
        _ = buffer.initialize(fromContentsOf: values)
        deallocators.append {
            buffer.deinitialize()
            buffer.deallocate()
        }
        return UnsafePointer(buffer.baseAddress!)
    }

    deinit {
        for free in deallocators { free() }
    }
}

func withFloats4(_ values: (Float, Float, Float, Float),
                 _ body: (UnsafePointer<Float>) -> Void) {
    withUnsafeBytes(of: values) {
        body($0.baseAddress!.assumingMemoryBound(to: Float.self))
    }
}
