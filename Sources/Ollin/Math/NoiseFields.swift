import Foundation

/// The sketch's noise fields as one value: the classic Perlin field behind
/// `noise`, the simplex field behind `simplexNoise`, and the cell field behind
/// `worley`, seeded together, with every noise method the sketch has.
///
/// A sketch's own `noise` is a method of a main-actor object, so only the main
/// thread can call it. This is the same set of fields as a plain `Sendable`
/// value: take a copy on the main thread and every core can read it at once,
/// with no lock and no hop back to the actor, which is what a job that asks a
/// field a few hundred thousand times a frame wants.
///
/// ```swift
/// let fields = noiseFields                              // seeded as the sketch is
/// DispatchQueue.concurrentPerform(iterations: points.count) { i in
///     out[i] = points[i] + fields.curlNoise(points[i] * 0.5) * 0.3
/// }
/// ```
///
/// It is a value, so a copy keeps the seed it was taken with: reseed the
/// sketch afterward and the copy goes on reading the old field while
/// `noiseFields` reads the new one. `noiseSeed` reseeds the sketch's own;
/// `NoiseFields(seed:)` makes one anywhere.
///
/// The sketch's bare calls, `noise(x, y)`, `fbm`, `curlNoise` and the rest,
/// forward to its `noiseFields`, so the two always answer the same number.
public struct NoiseFields: Sendable {
    /// The classic improved-Perlin field: `noise`, `fbm`, `curlNoise`, the
    /// looping and tiling forms, ridged and turbulent layering, domain warping.
    var perlin: PerlinNoise
    /// The simplex field behind `simplexNoise`, seeded with the classic one so
    /// one seed reproduces every flavor at once.
    var simplex: SimplexNoise
    /// The cell field behind `worley`.
    var worleyNoise: WorleyNoise

    /// The fields seeded by `seed`: what a sketch that called `noiseSeed(seed)`
    /// reads, so a value made here matches a sketch seeded the same.
    public init(seed: Int) {
        let bits = UInt64(bitPattern: Int64(seed))
        perlin = PerlinNoise(seed: bits)
        simplex = SimplexNoise(seed: bits)
        worleyNoise = WorleyNoise(seed: bits)
    }

    /// Reseed every field at once (what `Sketch.noiseSeed` does to its own).
    mutating func reseed(_ seed: Int) {
        let bits = UInt64(bitPattern: Int64(seed))
        perlin.reseed(bits)
        simplex.reseed(bits)
        worleyNoise.reseed(bits)
    }
}
