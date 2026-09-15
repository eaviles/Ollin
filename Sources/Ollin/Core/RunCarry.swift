import Foundation

/// Carrying a run across a hot swap.
///
/// A swap always brings a fresh instance: the code it runs lives in a new
/// dynamic library, so there is no way to keep the old object and change what
/// its methods do. What can be kept is everything the old instance had *become*
/// by the time the swap happened, and that is what this carries over, so the
/// live host can put an edit on stage without the piece starting again.
///
/// What comes across is exactly what survives a relaunch, plus the drawing:
///
/// - The drawing state and the canvas: the fresh instance draws through the
///   running instance's own ``Drawer``, so the accumulated canvas, the fill and
///   stroke, the blend mode, the text settings, the loaded fonts and images and
///   the retained batches are the ones the piece already had. Adopting it whole
///   is what makes this exact: every field it holds comes across, including the
///   ones added after this was written.
/// - The random streams: the variation, and where `random()` and the three
///   noise fields had each got to, so the next number is the next number rather
///   than the first one again.
/// - The ``Saved`` properties, matched by name the way a checkpoint matches
///   them, so a piece marks what it would hate to lose once and that mark
///   covers a relaunch and an edit both.
/// - The things `setup()` registered that are not state at all: the extensions
///   the sketch installed for itself, and the automation it wrote. Both were
///   put there by code that is not going to run again, so without this they
///   would quietly disappear on an edit.
///
/// The clock is carried by the runner (it owns it), and tuned parameters by the
/// session (it owns those). Anything else is a fresh instance's declared value:
/// a stored property the sketch did not mark is back where the file puts it.
/// That is the contract the live host classifies edits against, and the reason
/// an edit that would lose state it cannot carry starts the run over instead.
extension Sketch {

    /// Take over the run `other` is in the middle of. Call on the main thread,
    /// before the fresh instance draws anything.
    func carryRun(from other: Sketch) {
        // The drawing, whole. A drawer holds no reference back to its sketch,
        // so the running one can simply change hands; the renderer reads it
        // through the sketch each frame and finds the same object with the same
        // caches, and the persistent canvas it is pointing at is untouched.
        drawer = other.drawer

        // Where the randomness had got to. Carrying the seed alone would start
        // the same sequence over, which a piece driven by `random()` shows as a
        // jump; carrying the generators themselves is what makes the next mark
        // the next mark.
        variation = other.variation
        rng = other.rng
        perlin = other.perlin
        simplex = other.simplex
        worleyNoise = other.worleyNoise
        gaussianSpare = other.gaussianSpare
        recordedRandomSeed = other.recordedRandomSeed
        recordedNoiseSeed = other.recordedNoiseSeed

        // What `setup()` registered rather than computed. The automation the
        // running instance holds wins over anything the session just installed,
        // because it is the same tracks plus whatever `setup()` wrote itself.
        adoptExtensions(from: other)
        if let running = other.automation { automation = running }
        accessibleDescription = other.accessibleDescription

        // Where the sketch is being looked at from, which the person at the
        // keyboard set with the mouse and did not ask to have reset.
        view2D = other.view2D
        // A still sketch stays still: `noLoop()` was called in code that is not
        // going to run again, so the state it left behind is carried instead.
        isLooping = other.isLooping

        // The state the piece said it would hate to lose, by name, each one its
        // own success or failure so a single property that will not travel does
        // not cost the rest.
        let waiting = Dictionary(savedProperties().map { ($0.name, $0.property) },
                                 uniquingKeysWith: { first, _ in first })
        for handle in other.savedProperties() {
            guard let destination = waiting[handle.name] else { continue }
            do {
                try destination.decodeValue(from: handle.property.encodedValue())
            } catch {
                print("Ollin: '\(handle.name)' could not be carried across the swap: \(error)")
            }
        }
    }
}
