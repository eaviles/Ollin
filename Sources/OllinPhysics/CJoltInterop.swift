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

func withFloats4(_ values: (Float, Float, Float, Float),
                 _ body: (UnsafePointer<Float>) -> Void) {
    withUnsafeBytes(of: values) {
        body($0.baseAddress!.assumingMemoryBound(to: Float.self))
    }
}
