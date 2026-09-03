import Foundation

/// The recorded frames packed for the page. Weight is the governor, and three
/// things keep it down. A frame whose shapes are the previous frame's is
/// stored once, so a still costs one frame. When every frame carries the same
/// cast (the same count of shapes with the same tags, the ordinary animation),
/// the columns that never change are stored once as the base and only the
/// moving ones travel, which is what makes interpolating between frames
/// possible at all. And a moving column of a lap (a track recorded from
/// `loopDuration`) is fitted to the few sines it is made of, so the page
/// evaluates the motion at any time from a handful of coefficients instead of
/// reading it back frame by frame; a column that fits nothing short travels
/// as 16-bit samples, each within a 65,535th of its range of the float the Mac
/// used.
struct WebTrack {
    /// A JSON object: the facts the player reads.
    var meta: String
    /// Base64 uint16: the sampled columns per unique frame (a stable cast), or
    /// every instance of every unique frame, each value quantized inside its
    /// column's range.
    var stream: String
    /// Base64 float32: the first unique frame whole, for a stable cast; empty
    /// otherwise.
    var base: String
    /// Base64 float32: the fitted columns' coefficients (the mean, then a
    /// frequency, a cosine, and a sine per term), in `meta.fit` order.
    var fit: String
    var uniqueFrames: Int
    var stable: Bool
    /// Columns worked out live from a parameter's formula.
    var drivenColumns: Int
    var fittedColumns: Int
    var sampledColumns: Int
    /// Sine terms across every fitted column.
    var fitTerms: Int

    /// The largest fraction of the frame count a column's fit may spend on
    /// terms and still be worth more than its samples.
    static let maxTermFraction = 8

    init(_ recording: WebRecording) {
        // Consecutive duplicates fold onto one record.
        var uniques: [[Float]] = []
        var refs: [Int] = []
        for frame in recording.frames {
            if let last = uniques.last, last == frame.instances {
                refs.append(uniques.count - 1)
            } else {
                uniques.append(frame.instances)
                refs.append(uniques.count - 1)
            }
        }
        uniqueFrames = uniques.count

        let n = WebInstance.floats
        var stable = false
        if let first = uniques.first, first.count % n == 0 {
            stable = uniques.allSatisfy { u in
                guard u.count == first.count else { return false }
                var i = WebInstance.shapeColumn
                while i < u.count {
                    if u[i] != first[i] { return false }
                    i += n
                }
                return true
            }
        }
        self.stable = stable

        var meta: [String: Any] = [
            "width": recording.width,
            "height": recording.height,
            "rate": recording.rate,
            "frames": recording.frames.count,
            "loops": recording.loops,
            "accumulates": recording.frames.contains { $0.clear == nil },
            "recipe": recording.recipe,
        ]
        // A per-frame fact that never changes travels once: the frame map when
        // every frame is its own record, and the clear, the tone map, and the
        // exposure when every frame shares them.
        if refs.enumerated().contains(where: { $0.offset != $0.element }) { meta["refs"] = refs }
        let clears = recording.frames.map { f -> [Float] in f.clear.map { [$0.x, $0.y, $0.z] } ?? [] }
        if let first = clears.first, clears.allSatisfy({ $0 == first }) { meta["clear"] = first } else { meta["clears"] = clears }
        let tones = recording.frames.map(\.toneMapMode)
        if let first = tones.first, tones.allSatisfy({ $0 == first }) { meta["tone"] = first } else { meta["tones"] = tones }
        let exposures = recording.frames.map(\.exposure)
        if let first = exposures.first, exposures.allSatisfy({ $0 == first }) { meta["exposure"] = first } else { meta["exposures"] = exposures }

        var samples: [UInt16] = []
        var ranges: [Float] = []
        var base: [Float] = []
        var coefficients: [Float] = []
        var fitIndex: [[Int]] = []
        var drives: [[Double]] = []
        var drivenColumns = 0
        var fittedColumns = 0
        var fitTerms = 0
        var sampledColumns = 0

        if stable, let first = uniques.first {
            base = first
            var moving: [Int] = []
            for column in first.indices where uniques.contains(where: { $0[column] != first[column] }) {
                moving.append(column)
            }
            // A moving column is first matched to a formula's values (it stays
            // live on the page), then, on a lap, fitted to its sines; what is
            // left travels as samples.
            var sampled: [Int] = []
            let frameCount = recording.frames.count
            for column in moving {
                let signal = refs.map { Double(uniques[$0][column]) }
                let lo = signal.min() ?? 0, hi = signal.max() ?? 0
                let tolerance = max((hi - lo) * 1e-4, 1e-6)
                if let wired = Self.affineFit(signal, against: recording.series, tolerance: tolerance) {
                    drives.append([Double(column), Double(wired.index), wired.alpha, wired.beta])
                    drivenColumns += 1
                    continue
                }
                var fitted: FourierFit? = nil
                if recording.loops, frameCount >= 4 {
                    fitted = FourierFit.fit(signal, tolerance: tolerance,
                                            maxTerms: max(1, frameCount / Self.maxTermFraction))
                }
                if let f = fitted {
                    fitIndex.append([column, f.terms.count])
                    coefficients.append(Float(f.mean))
                    for term in f.terms {
                        coefficients.append(Float(term.frequency))
                        coefficients.append(Float(term.cosine))
                        coefficients.append(Float(term.sine))
                    }
                    fittedColumns += 1
                    fitTerms += f.terms.count
                } else {
                    sampled.append(column)
                }
            }
            sampledColumns = sampled.count
            let columnRanges = sampled.map { column -> (Float, Float) in
                var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
                for u in uniques { lo = min(lo, u[column]); hi = max(hi, u[column]) }
                return (lo, hi)
            }
            for (lo, hi) in columnRanges { ranges.append(lo); ranges.append(hi) }
            for u in uniques {
                for (i, column) in sampled.enumerated() {
                    samples.append(Self.quantize(u[column], in: columnRanges[i]))
                }
            }
            meta["stable"] = true
            meta["count"] = first.count / n
            meta["varying"] = sampled
            meta["fit"] = fitIndex
            meta["drive"] = drives
        } else {
            // Every instance of every unique frame, each field inside the range
            // it spans across the whole track.
            var fieldRanges = [(Float, Float)](repeating: (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude), count: n)
            for u in uniques {
                for (i, v) in u.enumerated() {
                    let c = i % n
                    fieldRanges[c] = (min(fieldRanges[c].0, v), max(fieldRanges[c].1, v))
                }
            }
            if uniques.allSatisfy(\.isEmpty) { fieldRanges = [(Float, Float)](repeating: (0, 0), count: n) }
            for (lo, hi) in fieldRanges { ranges.append(lo); ranges.append(hi) }
            var offsets: [Int] = []
            var counts: [Int] = []
            for u in uniques {
                offsets.append(samples.count)
                counts.append(u.count / n)
                for (i, v) in u.enumerated() {
                    samples.append(Self.quantize(v, in: fieldRanges[i % n]))
                }
            }
            meta["stable"] = false
            meta["offsets"] = offsets
            meta["counts"] = counts
        }
        meta["ranges"] = ranges
        // The formulas travel only when a column reads one live; the page then
        // evaluates every formula, since one may read another.
        meta["formulas"] = drives.isEmpty ? [] : recording.formulas.map(\.meta)
        meta["constants"] = drives.isEmpty ? [:] : recording.constants
        if let clock = recording.clock, !drives.isEmpty { meta["clock"] = clock.meta }
        meta["frameOffset"] = recording.frameOffset
        meta["mouse"] = [recording.mouse.x, recording.mouse.y]

        self.drivenColumns = drivenColumns
        self.fittedColumns = fittedColumns
        self.sampledColumns = sampledColumns
        self.fitTerms = fitTerms
        self.stream = Self.base64(samples)
        self.base = Self.base64(base)
        self.fit = Self.base64(coefficients)
        let json = (try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        self.meta = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003C")
    }

    /// The formula whose values `signal` is an affine image of, within
    /// `tolerance` at every frame, with the two coefficients; `nil` when none
    /// fits. A formula whose values never change cannot move a column, so it
    /// is never matched.
    static func affineFit(_ signal: [Double], against series: [[Float]],
                          tolerance: Double) -> (index: Int, alpha: Double, beta: Double)? {
        let n = signal.count
        guard n > 1 else { return nil }
        let meanY = signal.reduce(0, +) / Double(n)
        for (index, samples) in series.enumerated() {
            guard samples.count == n else { continue }
            let x = samples.map(Double.init)
            let meanX = x.reduce(0, +) / Double(n)
            var sxx = 0.0, sxy = 0.0
            for k in 0 ..< n {
                let dx = x[k] - meanX
                sxx += dx * dx
                sxy += dx * (signal[k] - meanY)
            }
            let spread = (x.max() ?? 0) - (x.min() ?? 0)
            guard spread > 1e-9, sxx > 0 else { continue }
            let alpha = sxy / sxx
            let beta = meanY - alpha * meanX
            var worst = 0.0
            for k in 0 ..< n { worst = max(worst, abs(alpha * x[k] + beta - signal[k])) }
            if worst <= tolerance { return (index, alpha, beta) }
        }
        return nil
    }

    /// A value as a 16-bit position inside its column's range. The page reads
    /// it back as `lo + q * (hi - lo) / 65535`, so the error is at most half a
    /// step; a column that never varies reads back as `lo` exactly.
    static func quantize(_ v: Float, in range: (Float, Float)) -> UInt16 {
        let (lo, hi) = range
        guard hi > lo else { return 0 }
        let t = (Double(v) - Double(lo)) / (Double(hi) - Double(lo))
        return UInt16(clamping: Int((t * 65535).rounded()))
    }

    /// Little-endian float32 bytes, base64.
    static func base64(_ values: [Float]) -> String {
        var data = Data(capacity: values.count * 4)
        for v in values {
            var bits = v.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }

    /// Little-endian uint16 bytes, base64.
    static func base64(_ values: [UInt16]) -> String {
        var data = Data(capacity: values.count * 2)
        for v in values {
            var bits = v.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }
}

// MARK: - The fit

/// One sine term of a fitted column: `cosine * cos(w f) + sine * sin(w f)`
/// where `w` is the lap's angle at the moment asked for.
struct FourierTerm: Equatable {
    var frequency: Int
    var cosine: Double
    var sine: Double
}

/// A column of a lap as the few sines it is made of: the mean plus the terms
/// that bring the reconstruction within a tolerance of every sample, biggest
/// first. A motion written as a sum of sines with whole cycle counts per lap
/// (the ordinary looping sketch) fits exactly, to float rounding, in as many
/// terms as it has sines.
struct FourierFit: Equatable {
    var mean: Double
    var terms: [FourierTerm]

    /// The value at sample position `k` (fractional) of a period `n` samples long.
    func value(at k: Double, period n: Int) -> Double {
        let w = 2 * Double.pi * k / Double(n)
        var v = mean
        for t in terms {
            v += t.cosine * cos(w * Double(t.frequency)) + t.sine * sin(w * Double(t.frequency))
        }
        return v
    }

    /// Fit `samples`, one period, to within `tolerance` of each of them, or
    /// `nil` when it takes more than `maxTerms` (the samples then weigh less).
    static func fit(_ samples: [Double], tolerance: Double, maxTerms: Int) -> FourierFit? {
        let n = samples.count
        guard n >= 4 else { return nil }
        let (re, im) = DiscreteFourier.transform(samples)
        let mean = re[0] / Double(n)
        let half = n / 2
        var candidates: [FourierTerm] = []
        candidates.reserveCapacity(half)
        for m in 1 ... half {
            if n % 2 == 0, m == half {
                // The Nyquist bin stands alone: one cosine at half weight.
                candidates.append(FourierTerm(frequency: m, cosine: re[m] / Double(n), sine: 0))
            } else {
                candidates.append(FourierTerm(frequency: m, cosine: 2 * re[m] / Double(n), sine: -2 * im[m] / Double(n)))
            }
        }
        // Biggest first; ties by the slower motion, so the order is deterministic.
        candidates.sort {
            let a = ($0.cosine * $0.cosine + $0.sine * $0.sine), b = ($1.cosine * $1.cosine + $1.sine * $1.sine)
            if a != b { return a > b }
            return $0.frequency < $1.frequency
        }
        var reconstruction = [Double](repeating: mean, count: n)
        func maxError() -> Double {
            var worst = 0.0
            for k in 0 ..< n { worst = max(worst, abs(reconstruction[k] - samples[k])) }
            return worst
        }
        var kept: [FourierTerm] = []
        if maxError() <= tolerance { return FourierFit(mean: mean, terms: kept) }
        for term in candidates {
            guard kept.count < maxTerms else { return nil }
            kept.append(term)
            for k in 0 ..< n {
                let w = 2 * Double.pi * Double(k * term.frequency) / Double(n)
                reconstruction[k] += term.cosine * cos(w) + term.sine * sin(w)
            }
            if maxError() <= tolerance { return FourierFit(mean: mean, terms: kept) }
        }
        return nil
    }
}

/// A discrete Fourier transform of any length: the mixed-radix split over the
/// small prime factors, and the plain sum for a prime length. `X[m]` is the
/// sum over `k` of `x[k] e^(-2 pi i m k / n)`.
enum DiscreteFourier {
    static func transform(_ x: [Double]) -> (re: [Double], im: [Double]) {
        transform(re: x, im: [Double](repeating: 0, count: x.count))
    }

    static func transform(re: [Double], im: [Double]) -> (re: [Double], im: [Double]) {
        let n = re.count
        guard n > 1 else { return (re, im) }
        let p = smallestFactor(of: n)
        if p == n { return direct(re: re, im: im) }
        let m = n / p
        var subRe: [[Double]] = []
        var subIm: [[Double]] = []
        subRe.reserveCapacity(p)
        subIm.reserveCapacity(p)
        for r in 0 ..< p {
            let (sr, si) = transform(re: stride(from: r, to: n, by: p).map { re[$0] },
                                     im: stride(from: r, to: n, by: p).map { im[$0] })
            subRe.append(sr)
            subIm.append(si)
        }
        var outRe = [Double](repeating: 0, count: n)
        var outIm = [Double](repeating: 0, count: n)
        for k in 0 ..< m {
            for q in 0 ..< p {
                let j = k + m * q
                var sr = 0.0, si = 0.0
                for r in 0 ..< p {
                    let angle = -2 * Double.pi * Double((r * j) % n) / Double(n)
                    let c = cos(angle), s = sin(angle)
                    let xr = subRe[r][k], xi = subIm[r][k]
                    sr += xr * c - xi * s
                    si += xr * s + xi * c
                }
                outRe[j] = sr
                outIm[j] = si
            }
        }
        return (outRe, outIm)
    }

    static func direct(re: [Double], im: [Double]) -> (re: [Double], im: [Double]) {
        let n = re.count
        var outRe = [Double](repeating: 0, count: n)
        var outIm = [Double](repeating: 0, count: n)
        for j in 0 ..< n {
            var sr = 0.0, si = 0.0
            for k in 0 ..< n {
                let angle = -2 * Double.pi * Double((k * j) % n) / Double(n)
                let c = cos(angle), s = sin(angle)
                sr += re[k] * c - im[k] * s
                si += re[k] * s + im[k] * c
            }
            outRe[j] = sr
            outIm[j] = si
        }
        return (outRe, outIm)
    }

    static func smallestFactor(of n: Int) -> Int {
        if n % 2 == 0 { return 2 }
        var d = 3
        while d * d <= n {
            if n % d == 0 { return d }
            d += 2
        }
        return n
    }
}
