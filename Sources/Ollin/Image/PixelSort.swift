import Foundation

/// Pixel sorting: rearrange runs of an image's own pixels along rows or
/// columns, sorted by brightness, hue, or saturation. Nothing is invented or
/// recolored; the image's pixels just change places, which is what gives the
/// technique its melted, streaked reading. Invented by Kim Asendorf; the
/// interval model here is his. The classic treatment sorts twice, once per
/// axis:
///
/// ```swift
/// let glitched = picture.pixelSorted(.vertical).pixelSorted(.horizontal)
/// ```
///
/// Runs are bounded by a brightness window (`threshold`): only stretches of
/// pixels inside the window sort, so highlights and shadows hold their ground
/// while the midtones streak. Widen the window to `0...1` to sort whole rows
/// or columns. Deterministic, CPU-side, and setup-time-shaped at full
/// resolution; sort a smaller image if you need it every frame.

/// Which axis the runs lie along. `.vertical` sorts columns (the classic
/// falling streaks), `.horizontal` sorts rows.
public enum PixelSortDirection: Sendable {
    case horizontal
    case vertical
}

/// What ordering a run sorts by.
public enum PixelSortKey: Sendable {
    /// Perceptually weighted brightness (dark to bright).
    case brightness
    /// Position on the color wheel (red through green and blue, wrapping).
    case hue
    /// Color purity (gray to vivid).
    case saturation
}

public extension Image {
    /// A copy of this image with threshold-bounded runs of pixels sorted along
    /// `direction`. Pixels whose brightness falls inside `threshold` form the
    /// runs; each run's pixels reorder by `key`, ascending (or `reversed`).
    /// A texture-backed image has no CPU pixels and returns itself unchanged.
    ///
    /// - Parameters:
    ///   - direction: The axis the runs lie along; `.vertical` streaks fall.
    ///   - key: The ordering inside each run.
    ///   - threshold: The brightness window that admits a pixel into a run;
    ///     `0...1` sorts every full row or column.
    ///   - reversed: Flip the order, putting bright (or vivid, or late-hue)
    ///     pixels first.
    func pixelSorted(_ direction: PixelSortDirection = .vertical,
                     by key: PixelSortKey = .brightness,
                     threshold: ClosedRange<Double> = 0.25 ... 0.8,
                     reversed: Bool = false) -> Image {
        guard let input = premultipliedPixels() else { return self }
        let count = width * height
        guard count > 0 else { return self }

        // Whole pixels move together, so work on one 32-bit word per pixel.
        var pixels = [UInt32](repeating: 0, count: count)
        input.withUnsafeBytes { raw in
            pixels.withUnsafeMutableBytes { $0.copyMemory(from: raw) }
        }

        // Straight-color selector (brightness) and sort key for every pixel.
        var selector = [Float](repeating: 0, count: count)
        var keys = [Float](repeating: 0, count: count)
        for i in 0 ..< count {
            let a = Double(input[i * 4 + 3]) / 255
            var r = 0.0, g = 0.0, b = 0.0
            if a > 0 {
                r = Swift.min(Double(input[i * 4]) / 255 / a, 1)
                g = Swift.min(Double(input[i * 4 + 1]) / 255 / a, 1)
                b = Swift.min(Double(input[i * 4 + 2]) / 255 / a, 1)
            }
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            selector[i] = Float(luma)
            switch key {
            case .brightness:
                keys[i] = Float(luma)
            case .hue:
                keys[i] = Float(hueFraction(r, g, b))
            case .saturation:
                let hi = Swift.max(r, g, b)
                keys[i] = hi > 0 ? Float((hi - Swift.min(r, g, b)) / hi) : 0
            }
        }

        let lo = Float(threshold.lowerBound), hi = Float(threshold.upperBound)
        let lineCount = direction == .vertical ? width : height
        let lineLength = direction == .vertical ? height : width
        var indices: [Int] = []
        indices.reserveCapacity(lineLength)
        var sortedWords: [UInt32] = []
        sortedWords.reserveCapacity(lineLength)

        for line in 0 ..< lineCount {
            func pixelIndex(_ step: Int) -> Int {
                direction == .vertical ? step * width + line : line * width + step
            }
            var step = 0
            while step < lineLength {
                // Find the next run inside the brightness window.
                while step < lineLength {
                    let s = selector[pixelIndex(step)]
                    if s >= lo && s <= hi { break }
                    step += 1
                }
                guard step < lineLength else { break }
                indices.removeAll(keepingCapacity: true)
                while step < lineLength {
                    let i = pixelIndex(step)
                    let s = selector[i]
                    guard s >= lo && s <= hi else { break }
                    indices.append(i)
                    step += 1
                }
                guard indices.count > 1 else { continue }

                // Sort the run by key; position breaks ties, so the result is
                // deterministic for any input.
                let ordered = indices.sorted {
                    if keys[$0] != keys[$1] {
                        return reversed ? keys[$0] > keys[$1] : keys[$0] < keys[$1]
                    }
                    return $0 < $1
                }
                sortedWords.removeAll(keepingCapacity: true)
                for i in ordered { sortedWords.append(pixels[i]) }
                for (offset, i) in indices.enumerated() { pixels[i] = sortedWords[offset] }
            }
        }

        var output = [UInt8](repeating: 0, count: count * 4)
        pixels.withUnsafeBytes { raw in
            output.withUnsafeMutableBytes { $0.copyMemory(from: raw) }
        }
        return Image(width: width, height: height, premultipliedRGBA: output) ?? self
    }
}

/// Hue as a `0..<1` fraction of the color wheel; gray reads as `0`.
private func hueFraction(_ r: Double, _ g: Double, _ b: Double) -> Double {
    let hi = Swift.max(r, g, b), lo = Swift.min(r, g, b)
    let chroma = hi - lo
    guard chroma > 0 else { return 0 }
    var hue: Double
    if hi == r { hue = ((g - b) / chroma).truncatingRemainder(dividingBy: 6) }
    else if hi == g { hue = (b - r) / chroma + 2 }
    else { hue = (r - g) / chroma + 4 }
    if hue < 0 { hue += 6 }
    return hue / 6
}
