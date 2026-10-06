/// A closure kept as the state of a lock.
///
/// A lock whose state *is* a function type reabstracts the stored closure on
/// every `withLock`, on the way in and on the way out, and neither a debug nor
/// a release build peels the pair: the stored closure grows two thunk frames a
/// call, so a tap read once per audio block or camera frame overflows its
/// thread's stack within minutes (measured 2026-10-06: 2.0 frames a round
/// trip, and a 512 KB stack gone at 5,562 trips, the video tap's twenty
/// minutes of play). Held in a struct, the closure keeps its stored
/// representation and the read is one call deep however often it is made.
///
/// So a producer-to-reader handoff never stores a bare closure as its lock's
/// state: it stores one of these.
package struct Held<Value> {
    package var value: Value

    package init(_ value: Value) {
        self.value = value
    }
}

extension Held: Sendable where Value: Sendable {}
