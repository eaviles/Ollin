import Foundation

/// The recorded frames packed for the page. Weight is the governor, and three
/// things keep it down. A frame whose vector and graph are the previous
/// frame's is stored once, so a still costs one frame. When every frame
/// carries the same cast (the same graph, with the same count of shapes,
/// quads, and vertices and the same tags, the ordinary animation), the columns
/// that never change are stored once as the base (the vertices of it as 16-bit
/// samples) and only the moving ones travel, which is what
/// makes interpolating between frames possible at all. And a moving column of
/// a lap (a track recorded from `loopDuration`) is fitted to the few sines it
/// is made of, so the page evaluates the motion at any time from a handful of
/// coefficients instead of reading it back frame by frame; a column that fits
/// nothing short travels as 16-bit samples, each within a 65,535th of its range
/// of the float the Mac used. A parameter row of an effect pass is a column
/// like any other, so a generator's phase fed the clock fits as the shapes do.
struct WebTrack {
    /// A JSON object: the facts the player reads.
    var meta: String
    /// Base64 uint16: the sampled columns per unique frame (a stable cast), or
    /// every shape and quad of every unique frame, each value quantized inside
    /// its column's range.
    var stream: String
    /// Base64 float32: the first unique frame's shapes, quads, and parameter
    /// rows, for a stable cast; empty otherwise. Its triangle vertices travel
    /// apart, in `vertexBase`.
    var base: String
    /// Base64 float32: the first unique frame's vertex positions, exact, for a
    /// stable cast; empty otherwise. A position is what the multisampled
    /// raster reads, and one quantized over a canvas-wide drawing lands a
    /// sixtieth of a pixel off, which flips a sample on a fill's edge once in
    /// every twenty or so edge pixels; measured on a caption, that put a sixth
    /// of its edge pixels a sample off the Mac.
    var vertexPositions: String
    /// Base64 uint16: the first unique frame's vertex coverage and color, each
    /// field quantized inside its own range across the frame (`meta.vranges`),
    /// for a stable cast; empty otherwise.
    var vertexBase: String
    /// Base64 float32: each sampled column's range (low, high) in `varying`
    /// order for a stable cast, or each field's range across the track for a
    /// changing one. As JSON text a range would weigh thirty-some bytes a
    /// column, twice what the column's samples weigh over a short recording;
    /// as float32 it is eight.
    var ranges: String
    /// Base64 uint32: the sampled columns' indices into the frame vector, for
    /// a stable cast; empty otherwise.
    var varying: String
    /// Base64 float32: the fitted columns' coefficients (the mean, then a
    /// frequency, a cosine, and a sine per term), in `meta.fit` order.
    var fit: String
    /// Base64 float32: the parameter rows of every unique frame when the cast
    /// changes (a row travels whole; its range is not known ahead); empty for a
    /// stable cast.
    var extra: String
    /// Base64 float32: the scene block of every unique frame that marches a 3D
    /// field (`WebGraphRecorder.sceneBlock`), whole and exact, at `meta.sceneOffsets`
    /// with `meta.sceneLengths`; empty when no frame does.
    var scene: String
    /// The controls' axes: each wired column's slopes, packed like a moving
    /// column (one number when they never change, the sines of a lap, or a
    /// sample per frame), as float32 base64.
    var axisData: String
    /// How many columns the controls move between them.
    var wiredColumns: Int
    var uniqueFrames: Int
    var stable: Bool
    /// Columns worked out live from a parameter's formula.
    var drivenColumns: Int
    var fittedColumns: Int
    var sampledColumns: Int
    /// Sine terms across every fitted column.
    var fitTerms: Int
    /// Shader passes the first frame runs (layers and whole-frame filters).
    var passCount: Int
    /// The most triangle vertices any frame draws.
    var vertexCount: Int
    /// The most composed 2D fields any frame draws, and the most raymarched 3D
    /// fields.
    var groupCount: Int
    var fieldCount: Int
    /// What the track weighs on the page by part (`shapes and passes`,
    /// `stroke and fill vertices`, `scenes`, `controls`), each as the bytes it
    /// takes written out, split into what is stored once and what is stored
    /// per frame, so a refusal can say whether fewer frames would help.
    var weights: [WebWeight]

    /// The largest fraction of the frame count a column's fit may spend on
    /// terms and still be worth more than its samples.
    static let maxTermFraction = 8

    /// The most triangle vertices any frame of `recording` draws.
    static func vertexCount(of recording: WebRecording) -> Int {
        recording.frames.map(\.graph.vertexCount).max() ?? 0
    }

    /// Raw bytes as they weigh once base64 encoded (four characters for
    /// every three bytes).
    static func encoded(_ rawBytes: Int) -> Int {
        (rawBytes + 2) / 3 * 4
    }

    init(_ recording: WebRecording) {
        // Consecutive duplicates fold onto one record. A frame's scene block
        // counts: a still field under a turning camera is a new frame every
        // frame, though its vector and its graph never move.
        var uniques: [WebFrame] = []
        var refs: [Int] = []
        for frame in recording.frames {
            if let last = uniques.last, last.vector == frame.vector, last.graph == frame.graph, last.scene == frame.scene {
                refs.append(uniques.count - 1)
            } else {
                uniques.append(frame)
                refs.append(uniques.count - 1)
            }
        }
        uniqueFrames = uniques.count

        let n = WebInstance.floats
        var stable = false
        if let first = uniques.first {
            // The same cast: the graph, the shape tags, and the columns that
            // name a field's program (its kinds and ops, its length).
            let structural = first.graph.structuralColumns
            stable = uniques.allSatisfy { u in
                guard u.graph == first.graph, u.vector.count == first.vector.count,
                      u.scene.count == first.scene.count else { return false }
                var i = WebInstance.shapeColumn
                let end = first.graph.instanceCount * n
                while i < end {
                    if u.vector[i] != first.vector[i] { return false }
                    i += n
                }
                for c in structural where u.vector[c] != first.vector[c] { return false }
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
            "stateful": recording.isStateful,
            "recipe": recording.recipe,
            // A frame that draws triangles or a picture wants the multisampled
            // raster the Mac gives every 2D pass; the page then rasterizes
            // every drawn surface that way for the whole track.
            "msaa": uniques.contains { $0.graph.needsMultisampling },
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
        // The scene blocks, whole, one per unique frame that has one.
        var sceneFloats: [Float] = []
        var sceneOffsets: [Int] = []
        var sceneLengths: [Int] = []
        for u in uniques {
            sceneOffsets.append(sceneFloats.count)
            sceneLengths.append(u.scene.count)
            sceneFloats.append(contentsOf: u.scene)
        }
        var vertexPositions: [Float] = []
        var vertexBase: [UInt16] = []
        var vertexRanges: [Float] = []
        var coefficients: [Float] = []
        var fitIndex: [[Int]] = []
        var drives: [[Double]] = []
        var extra: [Float] = []
        var drivenColumns = 0
        var fittedColumns = 0
        var fitTerms = 0
        var sampledColumns = 0
        // Raw bytes by part, before base64: the shapes (with the quads, the
        // fields, the pass rows) and the vertices, each stored once or per frame.
        var shapesOnce = 0, shapesPerFrame = 0, verticesOnce = 0, verticesPerFrame = 0

        if stable, let first = uniques.first {
            // The shapes, the quads, and the rows as floats; the vertices, the
            // bulk of a drawing, as their positions in float32 and their
            // coverage and color as 16-bit samples by field.
            let vo = first.graph.vertexOffset, po = first.graph.paramOffset
            base = Array(first.vector[0 ..< vo]) + Array(first.vector[po...])
            let v = WebVertex.floats, p = WebVertex.positionFloats, quantized = v - p
            var fieldRanges = [(Float, Float)](repeating: (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude), count: quantized)
            for i in vo ..< po where (i - vo) % v >= p {
                let c = (i - vo) % v - p
                fieldRanges[c] = (min(fieldRanges[c].0, first.vector[i]), max(fieldRanges[c].1, first.vector[i]))
            }
            for c in fieldRanges.indices where fieldRanges[c].0 > fieldRanges[c].1 { fieldRanges[c] = (0, 0) }
            for (lo, hi) in fieldRanges { vertexRanges.append(lo); vertexRanges.append(hi) }
            vertexBase.reserveCapacity((po - vo) / v * quantized)
            vertexPositions.reserveCapacity((po - vo) / v * p)
            for i in vo ..< po {
                let f = (i - vo) % v
                if f < p { vertexPositions.append(first.vector[i]) }
                else { vertexBase.append(Self.quantize(first.vector[i], in: fieldRanges[f - p])) }
            }
            shapesOnce += base.count * 4
            verticesOnce += vertexPositions.count * 4 + vertexBase.count * 2
            func isVertexColumn(_ column: Int) -> Bool { column >= vo && column < po }
            var moving: [Int] = []
            for column in first.vector.indices where uniques.contains(where: { $0.vector[column] != first.vector[column] }) {
                moving.append(column)
            }
            // A moving column is first matched to a formula's values (it stays
            // live on the page), then, on a lap, fitted to its sines; what is
            // left travels as samples.
            var sampled: [Int] = []
            let frameCount = recording.frames.count
            for column in moving {
                let signal = refs.map { Double(uniques[$0].vector[column]) }
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
                    let fitBytes = (1 + 3 * f.terms.count) * 4
                    if isVertexColumn(column) { verticesOnce += fitBytes } else { shapesOnce += fitBytes }
                } else {
                    sampled.append(column)
                    // Its samples per frame, its range and index once.
                    if isVertexColumn(column) { verticesPerFrame += 2 * uniques.count; verticesOnce += 12 }
                    else { shapesPerFrame += 2 * uniques.count; shapesOnce += 12 }
                }
            }
            sampledColumns = sampled.count
            let columnRanges = sampled.map { column -> (Float, Float) in
                var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
                for u in uniques { lo = min(lo, u.vector[column]); hi = max(hi, u.vector[column]) }
                return (lo, hi)
            }
            for (lo, hi) in columnRanges { ranges.append(lo); ranges.append(hi) }
            for u in uniques {
                for (i, column) in sampled.enumerated() {
                    samples.append(Self.quantize(u.vector[column], in: columnRanges[i]))
                }
            }
            meta["stable"] = true
            meta["count"] = first.graph.instanceCount
            meta["vranges"] = vertexRanges
            self.varying = Self.base64(sampled.map { UInt32($0) })
            meta["fit"] = fitIndex
            meta["drive"] = drives
            meta["graph"] = first.graph.meta
        } else {
            // Every shape, quad, field, instruction, and vertex of every unique
            // frame, each field inside the range it spans across the whole
            // track, but a vertex's position, which travels exact; the
            // parameter rows whole.
            let q = WebQuad.floats, v = WebVertex.floats, p = WebVertex.positionFloats
            let gf = WebGroup.floats, nf = WebNode.floats, ff = WebField.floats, n3 = WebNode3D.floats
            let fields = n + q + gf + nf + ff + n3 + v
            var fieldRanges = [(Float, Float)](repeating: (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude), count: fields)
            func field(_ i: Int, _ g: WebGraph) -> Int {
                if i < g.quadOffset { return i % n }
                if i < g.groupOffset { return n + (i - g.quadOffset) % q }
                if i < g.nodeOffset { return n + q + (i - g.groupOffset) % gf }
                if i < g.fieldOffset { return n + q + gf + (i - g.nodeOffset) % nf }
                if i < g.node3DOffset { return n + q + gf + nf + (i - g.fieldOffset) % ff }
                if i < g.vertexOffset { return n + q + gf + nf + ff + (i - g.node3DOffset) % n3 }
                return n + q + gf + nf + ff + n3 + (i - g.vertexOffset) % v
            }
            func isPosition(_ i: Int, _ g: WebGraph) -> Bool {
                i >= g.vertexOffset && (i - g.vertexOffset) % v < p
            }
            var any = false
            for u in uniques {
                for i in 0 ..< u.graph.paramOffset where !isPosition(i, u.graph) {
                    let c = field(i, u.graph)
                    fieldRanges[c] = (min(fieldRanges[c].0, u.vector[i]), max(fieldRanges[c].1, u.vector[i]))
                    any = true
                }
            }
            if !any { fieldRanges = [(Float, Float)](repeating: (0, 0), count: fields) }
            for c in fieldRanges.indices where fieldRanges[c].0 > fieldRanges[c].1 { fieldRanges[c] = (0, 0) }
            for (lo, hi) in fieldRanges { ranges.append(lo); ranges.append(hi) }
            shapesOnce += fields * 8
            self.varying = ""
            var offsets: [Int] = []
            var positionOffsets: [Int] = []
            var lengths: [Int] = []
            var paramOffsets: [Int] = []
            var graphs: [WebGraph] = []
            var graphOf: [Int] = []
            for u in uniques {
                offsets.append(samples.count)
                positionOffsets.append(vertexPositions.count)
                lengths.append(u.vector.count)
                for i in 0 ..< u.graph.paramOffset {
                    if isPosition(i, u.graph) { vertexPositions.append(u.vector[i]) }
                    else { samples.append(Self.quantize(u.vector[i], in: fieldRanges[field(i, u.graph)])) }
                }
                let vertexFloats = u.graph.paramOffset - u.graph.vertexOffset
                verticesPerFrame += vertexFloats / v * (p * 4 + (v - p) * 2)
                shapesPerFrame += u.graph.vertexOffset * 2
                paramOffsets.append(extra.count)
                extra.append(contentsOf: u.vector[u.graph.paramOffset...])
                shapesPerFrame += (u.vector.count - u.graph.paramOffset) * 4
                if let gi = graphs.firstIndex(of: u.graph) { graphOf.append(gi) }
                else { graphs.append(u.graph); graphOf.append(graphs.count - 1) }
            }
            meta["stable"] = false
            meta["offsets"] = offsets
            meta["positionOffsets"] = positionOffsets
            meta["lengths"] = lengths
            meta["paramOffsets"] = paramOffsets
            meta["graphs"] = graphs.map(\.meta)
            meta["graphOf"] = graphOf
        }
        self.ranges = Self.base64(ranges)
        // The formulas travel only when a column reads one live; the page then
        // evaluates every formula, since one may read another.
        meta["formulas"] = drives.isEmpty ? [] : recording.formulas.map(\.meta)
        meta["constants"] = drives.isEmpty ? [:] : recording.constants
        if let clock = recording.clock, !drives.isEmpty { meta["clock"] = clock.meta }
        meta["frameOffset"] = recording.frameOffset
        meta["mouse"] = [recording.mouse.x, recording.mouse.y]
        if !sceneFloats.isEmpty {
            meta["sceneOffsets"] = sceneOffsets
            meta["sceneLengths"] = sceneLengths
        }
        // The controls and their axes. A column a formula already carries live
        // is left to the formula when the formula reads the axis, since the
        // page then moves it through the formula's own value.
        var axisFloats: [Float] = []
        var axesMeta: [[String: Any]] = []
        var drivenBy: [Int: Int] = [:]
        for d in drives { drivenBy[Int(d[0])] = Int(d[1]) }
        let closure = Self.formulaClosure(recording.formulas)
        var wired = 0
        for axis in recording.axes {
            var cols: [[Any]] = []
            for column in axis.columns {
                if column.region == .vector, let f = drivenBy[column.index], f < closure.count,
                   closure[f].contains(axis.name) { continue }
                let offset = axisFloats.count
                let (mode, count) = Self.packSlopes(column.slopes, into: &axisFloats,
                                                    fit: stable && recording.loops && recording.frames.count >= 4)
                cols.append([column.region.rawValue, column.index, column.transform, mode, offset, count])
                wired += 1
            }
            axesMeta.append(["c": axis.control, "name": axis.name, "base": axis.base, "cols": cols])
        }
        meta["controls"] = recording.controls.map(\.meta)
        meta["axes"] = axesMeta
        self.axisData = Self.base64(axisFloats)
        self.wiredColumns = wired
        var weights = [
            WebWeight(name: "shapes and passes", once: Self.encoded(shapesOnce), perFrame: Self.encoded(shapesPerFrame)),
            WebWeight(name: "stroke and fill vertices", once: Self.encoded(verticesOnce), perFrame: Self.encoded(verticesPerFrame)),
        ]
        if !sceneFloats.isEmpty { weights.append(WebWeight(name: "scenes", once: 0, perFrame: Self.encoded(sceneFloats.count * 4))) }
        if !axisFloats.isEmpty { weights.append(WebWeight(name: "controls", once: Self.encoded(axisFloats.count * 4), perFrame: 0)) }
        self.weights = weights.filter { $0.bytes > 0 }

        self.drivenColumns = drivenColumns
        self.fittedColumns = fittedColumns
        self.sampledColumns = sampledColumns
        self.fitTerms = fitTerms
        self.passCount = uniques.first.map { $0.graph.layers.count + $0.graph.frameFilters.count } ?? 0
        self.vertexCount = uniques.map(\.graph.vertexCount).max() ?? 0
        self.groupCount = uniques.map(\.graph.groupCount).max() ?? 0
        self.fieldCount = uniques.map(\.graph.fieldCount).max() ?? 0
        self.scene = Self.base64(sceneFloats)
        self.stream = Self.base64(samples)
        self.base = Self.base64(base)
        self.vertexPositions = Self.base64(vertexPositions)
        self.vertexBase = Self.base64(vertexBase)
        self.fit = Self.base64(coefficients)
        self.extra = Self.base64(extra)
        let json = (try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        self.meta = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003C")
    }

    /// One axis column's slopes packed onto `data`: mode 0 is one number for a
    /// slope that never changes, mode 1 the mean and `count` sine terms of a
    /// lap (frequency, cosine, sine each), mode 2 a sample per frame.
    static func packSlopes(_ slopes: [Float], into data: inout [Float], fit: Bool) -> (mode: Int, count: Int) {
        guard let first = slopes.first else { data.append(0); return (0, 1) }
        let scale = max(abs(first), 1e-6)
        if slopes.allSatisfy({ abs($0 - first) <= scale * 1e-6 }) {
            data.append(first)
            return (0, 1)
        }
        if fit {
            let signal = slopes.map(Double.init)
            let lo = signal.min() ?? 0, hi = signal.max() ?? 0
            if let f = FourierFit.fit(signal, tolerance: max((hi - lo) * 1e-4, 1e-7),
                                      maxTerms: max(1, slopes.count / maxTermFraction)) {
                data.append(Float(f.mean))
                for term in f.terms {
                    data.append(Float(term.frequency))
                    data.append(Float(term.cosine))
                    data.append(Float(term.sine))
                }
                return (1, f.terms.count)
            }
        }
        data.append(contentsOf: slopes)
        return (2, slopes.count)
    }

    /// For each formula, every name it reads, through the other formulas it reads.
    static func formulaClosure(_ formulas: [WebFormula]) -> [Set<String>] {
        var byName: [String: Int] = [:]
        for (i, f) in formulas.enumerated() where byName[f.name] == nil { byName[f.name] = i }
        return formulas.indices.map { i in
            var seen: Set<String> = []
            var stack = formulas[i].reads
            while let name = stack.popLast() {
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                if let j = byName[name] { stack += formulas[j].reads }
            }
            return seen
        }
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

    /// Little-endian uint32 bytes, base64.
    static func base64(_ values: [UInt32]) -> String {
        var data = Data(capacity: values.count * 4)
        for v in values {
            var bits = v.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }

    /// The float32 values a base64 string of them holds (the tests read a
    /// track back through it).
    static func floats(_ base64: String) -> [Float] {
        guard let data = Data(base64Encoded: base64) else { return [] }
        return data.withUnsafeBytes { raw in
            (0 ..< raw.count / 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    /// The uint32 values a base64 string of them holds.
    static func ints(_ base64: String) -> [UInt32] {
        guard let data = Data(base64Encoded: base64) else { return [] }
        return data.withUnsafeBytes { raw in
            (0 ..< raw.count / 4).map { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) }
        }
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
