import Foundation

/// A photometric light profile: the measured angular distribution of a real
/// lighting fixture, loaded from an IES file (the IESNA LM-63 format lighting
/// manufacturers publish for their products).
///
/// A profile shapes *where* a light sends its intensity: a downlight with a
/// hot center and a spill ring, a street light's sideways batwing throw, a
/// wall-washer's asymmetric fan, the patterns a plain cone or omni falloff
/// can't draw. Attach one to a point or spot light:
///
/// ```swift
/// let profile = IESProfile(resource: "downlight", in: .module)!
/// pointLight(.white, at: Vector3(0, 300, 0), profile: profile)
/// ```
///
/// The profile's `0` angle aims along the light's axis (a spot's `direction`;
/// a point light takes an `axis:` parameter, straight down by default), and
/// its intensities are normalized so the brightest direction equals `1`:
/// the light's `intensity` still sets overall brightness, and the punctual
/// no-distance-falloff model is unchanged. Parse once (in `setup()`) and keep
/// the value; it's plain data.
///
/// The parser reads Type C photometry (the architectural standard covering
/// effectively all published files) across the LM-63 revisions, honoring the
/// format's lateral-symmetry conventions. Type A/B files (automotive and
/// floodlight aiming conventions) are not supported and fail to parse.
public struct IESProfile: Equatable, Sendable {

    /// The lateral (horizontal) symmetry a file declares through its last
    /// horizontal angle, per LM-63: the stored wedge mirrors or wraps to
    /// cover the full circle.
    enum Symmetry: Equatable, Sendable {
        /// One horizontal angle (or a last angle of 0): the same vertical
        /// falloff in every direction around the axis.
        case axial
        /// Angles span 0-90: each quadrant mirrors the first.
        case quadrant
        /// Angles span 0-180: the far half mirrors across the 0-180 plane.
        case bilateral
        /// Angles span 90-270: mirrored across the 90-270 plane (the rare
        /// LM-63-1995/2002 lateral case).
        case bilateral90
        /// Angles span the full 0-360: no symmetry, the circle wraps.
        case full
    }

    /// Vertical (polar) angles in degrees, ascending. `0` is the beam axis.
    let verticalAngles: [Double]
    /// Horizontal (azimuthal) angles in degrees, ascending, covering the
    /// wedge `symmetry` expands.
    let horizontalAngles: [Double]
    /// `values[h][v]`: intensity at `horizontalAngles[h]`, `verticalAngles[v]`,
    /// normalized so the peak over the whole grid is exactly 1.
    let values: [[Double]]
    /// How the stored wedge covers the full circle.
    let symmetry: Symmetry
    /// A content hash computed once at parse, so per-frame texture-cache
    /// comparisons never re-walk the grid.
    let contentHash: Int

    // MARK: - Parsing

    /// Parse an LM-63 IES file's text. Returns `nil` (never traps) on any
    /// malformed input, with a one-line reason on stderr.
    public init?(string: String) {
        // Everything after the TILT= line is one whitespace-separated number
        // soup; real files break the format's line rules freely, so the only
        // robust read is to tokenize the numbers and count.
        guard let tiltRange = IESProfile.tiltLineRange(in: string) else {
            IESProfile.complain("no TILT= line"); return nil
        }
        let tiltValue = string[tiltRange].trimmingCharacters(in: .whitespaces)
            .dropFirst("TILT=".count)
            .trimmingCharacters(in: .whitespaces)
        let numbers = string[tiltRange.upperBound...]
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { Double($0) }
        guard !numbers.contains(nil) else {
            IESProfile.complain("non-numeric data after TILT"); return nil
        }
        var tokens = numbers.compactMap { $0 }

        // TILT=INCLUDE carries an inline correction block: a lamp-to-luminaire
        // geometry flag, a pair count n, then n angles and n factors. The
        // factors correct for lamp tilt in the measuring rig, which doesn't
        // change the profile's shape, so consume and drop the block. A
        // filename value references an external tilt file, equally droppable.
        if tiltValue.uppercased() == "INCLUDE" {
            guard tokens.count >= 2,
                  let pairs = IESProfile.count(tokens[1]),
                  tokens.count >= 2 + 2 * pairs else {
                IESProfile.complain("truncated TILT block"); return nil
            }
            tokens.removeFirst(2 + 2 * pairs)
        }

        // The 10 + 3 header fields, in the spec's order.
        guard tokens.count >= 13,
              let verticalCount = IESProfile.count(tokens[3]),
              let horizontalCount = IESProfile.count(tokens[4]),
              let photometricType = IESProfile.count(tokens[5]) else {
            IESProfile.complain("truncated or malformed header"); return nil
        }
        tokens.removeFirst(13)

        guard photometricType == 1 else {
            IESProfile.complain("Type \(photometricType == 2 ? "B" : "A") photometry isn't supported (Type C only)")
            return nil
        }
        guard verticalCount >= 1, horizontalCount >= 1,
              verticalCount * horizontalCount <= 1_000_000 else {
            IESProfile.complain("bad angle counts"); return nil
        }
        guard tokens.count >= verticalCount + horizontalCount + verticalCount * horizontalCount else {
            IESProfile.complain("truncated angle or candela data"); return nil
        }

        let vertical = Array(tokens[0 ..< verticalCount])
        let horizontal = Array(tokens[verticalCount ..< verticalCount + horizontalCount])
        guard IESProfile.isAscending(vertical), IESProfile.isAscending(horizontal) else {
            IESProfile.complain("angle lists must ascend"); return nil
        }

        // Candela values: one block per horizontal angle, vertical varying
        // fastest within each block.
        var start = verticalCount + horizontalCount
        var grid: [[Double]] = []
        grid.reserveCapacity(horizontalCount)
        for _ in 0 ..< horizontalCount {
            grid.append(Array(tokens[start ..< start + verticalCount]))
            start += verticalCount
        }

        guard let peak = grid.flatMap({ $0 }).max(), peak > 0 else {
            IESProfile.complain("no positive candela values"); return nil
        }
        let normalized = grid.map { row in row.map { max(0, $0) / peak } }

        // The last horizontal angle names the lateral symmetry (LM-63's
        // convention): 0 = axial, 90 = quadrant, 180 = bilateral, 360 = full,
        // plus the 90-first / 270-last lateral variant.
        let symmetry: Symmetry
        let first = horizontal.first ?? 0
        let last = horizontal.last ?? 0
        if horizontalCount == 1 || last == 0 {
            symmetry = .axial
        } else if last <= 90 {
            symmetry = .quadrant
        } else if abs(first - 90) < 0.001 && abs(last - 270) < 0.001 {
            symmetry = .bilateral90
        } else if last <= 180 {
            symmetry = .bilateral
        } else {
            symmetry = .full
        }

        self.verticalAngles = vertical
        self.horizontalAngles = horizontal
        self.values = normalized
        self.symmetry = symmetry
        var hasher = Hasher()
        for row in normalized { for v in row { hasher.combine(v) } }
        for a in vertical { hasher.combine(a) }
        for a in horizontal { hasher.combine(a) }
        self.contentHash = hasher.finalize()
    }

    /// Parse IES file bytes (ASCII or UTF-8, with a Latin-1 fallback for the
    /// odd legacy file).
    public init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            IESProfile.complain("undecodable bytes"); return nil
        }
        self.init(string: text)
    }

    /// Parse an IES file at a URL.
    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            IESProfile.complain("can't read \(url.path)"); return nil
        }
        self.init(data: data)
    }

    /// Parse a bundled `.ies` resource. `in:` is the bundle that carries the
    /// file; pass `.module` from the sketch that bundles it.
    public init?(resource: String, in bundle: Bundle) {
        let name = resource.hasSuffix(".ies") ? String(resource.dropLast(4)) : resource
        guard let url = bundle.url(forResource: name, withExtension: "ies") else {
            IESProfile.complain("no resource \(resource).ies"); return nil
        }
        self.init(contentsOf: url)
    }

    // MARK: - Sampling

    /// The profile's intensity toward a direction, `0…1` (`1` is the fixture's
    /// brightest direction). `vertical` is the angle off the light's axis in
    /// radians (`0` straight along the beam, `π` directly behind); `horizontal`
    /// is the azimuth around the axis, also radians. Directions outside the
    /// file's measured vertical range are dark, as the fixture is.
    public func intensity(vertical: Double, horizontal: Double = 0) -> Double {
        let theta = vertical * 180 / .pi
        var phi = (horizontal * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if phi < 0 { phi += 360 }

        // Fold the query azimuth into the stored wedge per the symmetry.
        switch symmetry {
        case .axial:
            return sampleVertical(theta, row: 0)
        case .quadrant:
            phi = phi.truncatingRemainder(dividingBy: 180)
            if phi > 90 { phi = 180 - phi }
        case .bilateral:
            if phi > 180 { phi = 360 - phi }
        case .bilateral90:
            if phi < 90 || phi > 270 {
                phi = (180 - phi).truncatingRemainder(dividingBy: 360)
                if phi < 0 { phi += 360 }
            }
        case .full:
            break
        }

        // Interpolate between the two bracketing horizontal angles. The full
        // case wraps between the last and first angles across 360.
        let angles = horizontalAngles
        let wraps = symmetry == .full && angles.count > 1 && angles[angles.count - 1] < 359.999
        if phi <= angles[0] {
            return wraps ? wrapSample(theta: theta, phi: phi) : sampleVertical(theta, row: 0)
        }
        if phi >= angles[angles.count - 1] {
            return wraps ? wrapSample(theta: theta, phi: phi)
                         : sampleVertical(theta, row: angles.count - 1)
        }
        var hi = 1
        while angles[hi] < phi { hi += 1 }
        let lo = hi - 1
        let span = angles[hi] - angles[lo]
        let t = span > 0 ? (phi - angles[lo]) / span : 0
        let a = sampleVertical(theta, row: lo)
        let b = sampleVertical(theta, row: hi)
        return a + (b - a) * t
    }

    /// Interpolate across the wrap seam of a full-circle file whose last
    /// angle stops short of 360 (spec-violating but seen in the wild).
    private func wrapSample(theta: Double, phi: Double) -> Double {
        let lo = horizontalAngles.count - 1
        let span = horizontalAngles[0] + 360 - horizontalAngles[lo]
        var offset = phi - horizontalAngles[lo]
        if offset < 0 { offset += 360 }
        let t = span > 0 ? min(1, offset / span) : 0
        let a = sampleVertical(theta, row: lo)
        let b = sampleVertical(theta, row: 0)
        return a + (b - a) * t
    }

    /// Piecewise-linear interpolation down one horizontal row's vertical
    /// angles; zero outside the measured range (a downlight file ending at
    /// 90° emits nothing upward).
    private func sampleVertical(_ theta: Double, row: Int) -> Double {
        let angles = verticalAngles
        let row = values[row]
        if theta < angles[0] - 0.0001 || theta > angles[angles.count - 1] + 0.0001 {
            return 0
        }
        if theta <= angles[0] { return row[0] }
        if theta >= angles[angles.count - 1] { return row[row.count - 1] }
        var hi = 1
        while angles[hi] < theta { hi += 1 }
        let lo = hi - 1
        let span = angles[hi] - angles[lo]
        let t = span > 0 ? (theta - angles[lo]) / span : 0
        return row[lo] + (row[hi] - row[lo]) * t
    }

    // MARK: - GPU bake

    /// Resample the (non-uniform, wedge-stored) grid onto a uniform full-sphere
    /// table for the GPU: `height` rows of `width` floats, u spanning vertical
    /// 0…π at texel centers, v spanning azimuth 0…2π (the sampler wraps v).
    func bakedTable(width: Int, height: Int) -> [Float] {
        var table = [Float](repeating: 0, count: width * height)
        for row in 0 ..< height {
            let phi = (Double(row) + 0.5) / Double(height) * 2 * .pi
            for col in 0 ..< width {
                let theta = (Double(col) + 0.5) / Double(width) * .pi
                table[row * width + col] = Float(intensity(vertical: theta, horizontal: phi))
            }
        }
        return table
    }

    // MARK: - Helpers

    /// Find the `TILT=` line (the boundary between the keyword header and the
    /// numeric data). Keyword lines may mention TILT in comments, so it must
    /// start the line.
    private static func tiltLineRange(in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let r = text.range(of: "TILT", range: searchStart ..< text.endIndex) {
            let lineStart = text[..<r.lowerBound].lastIndex(where: { $0.isNewline })
                .map(text.index(after:)) ?? text.startIndex
            let prefix = text[lineStart ..< r.lowerBound]
            if prefix.allSatisfy({ $0 == " " || $0 == "\t" }) {
                let lineEnd = text[r.upperBound...].firstIndex(where: { $0.isNewline })
                    ?? text.endIndex
                return lineStart ..< lineEnd
            }
            searchStart = r.upperBound
        }
        return nil
    }

    /// A header field as a small non-negative Int, or `nil` when it isn't one
    /// (`Int(_: Double)` traps on out-of-range values; a malformed file must
    /// never trap).
    private static func count(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value < 1_000_000 else { return nil }
        return Int(value)
    }

    private static func isAscending(_ list: [Double]) -> Bool {
        for i in 1 ..< max(list.count, 1) where list[i] <= list[i - 1] { return false }
        return true
    }

    private static func complain(_ reason: String) {
        FileHandle.standardError.write(Data("Ollin: IESProfile failed to parse: \(reason).\n".utf8))
    }
}
