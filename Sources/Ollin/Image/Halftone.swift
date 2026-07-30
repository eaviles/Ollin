import Foundation

/// Halftone: rebuild an image as the classic print dot screen, one round dot
/// per cell of a rotated grid, each dot sized so its ink area matches the
/// tone under the cell. The vector counterpart of the raster screening the
/// print separations use: because the sizing is area-exact, tone survives the
/// screen, and dots in the shadows outgrow their cells and merge into the
/// traditional checkered diamonds.
///
/// ```swift
/// fill(.black)
/// noStroke()
/// drawHalftone(picture, pitch: 14)     // ink dots on the light canvas
/// ```
///
/// By default dark regions get big dots (ink on paper); pass `inverted: true`
/// to size dots by brightness instead (light marks on a dark canvas). Cells
/// lighter than the printable minimum stay bare, so highlights read as clean
/// paper. Deterministic given (image, pitch, angle, bounds).

/// One dot of a halftone screen: where it landed, how big it grew, and what
/// the image looked like underneath, for custom drawing (jitter, per-dot
/// color, swapping the mark for another shape).
public struct HalftoneDot: Sendable {
    /// Lattice coordinates in the rotated screen; `(0, 0)` is the cell at
    /// the image's center.
    public let column: Int
    public let row: Int
    /// The dot's center on the canvas.
    public let center: Vector2
    /// The dot's radius in canvas units: `0` at bare paper, growing past
    /// touching neighbors in the shadows up to `pitch / sqrt(2)` when solid
    /// ink floods the cell.
    public let radius: Double
    /// The cell's ink fraction, `0` bare to `1` solid, after the `inverted`
    /// mapping.
    public let coverage: Double
    /// The average color under the cell (straight alpha).
    public let color: Color
}

// MARK: - Dot geometry

/// Fraction of a screen cell a centered disk of radius `rho` covers, with the
/// cell's half-width as the unit: a quarter circle until the disk meets the
/// edges, then the circle minus the four clipped segments, reaching 1 at the
/// corners (`rho = sqrt(2)`). The growing-disk model both screens share: the
/// raster screen thresholds against it pixel by pixel, and the vector screen
/// inverts it to size each drawn dot.
func halftoneCoveredFraction(_ rho: Double) -> Double {
    if rho <= 0 { return 0 }
    if rho >= 2.0.squareRoot() { return 1 }
    let quarter = .pi * rho * rho / 4
    if rho <= 1 { return quarter }
    return quarter - rho * rho * acos(1 / rho) + (rho * rho - 1).squareRoot()
}

/// The dot radius (in cell half-widths) whose covered cell fraction is
/// `coverage`: the inverse of `halftoneCoveredFraction`. Closed-form on the
/// free-circle branch; the edge-clipped branch is monotonic, so a bisection
/// pins it well below the width of a printed dot's edge.
func halftoneDotRadius(coverage: Double) -> Double {
    if coverage <= 0 { return 0 }
    if coverage >= 1 { return 2.0.squareRoot() }
    if coverage <= .pi / 4 { return 2 * (coverage / .pi).squareRoot() }
    var low = 1.0
    var high = 2.0.squareRoot()
    for _ in 0 ..< 48 {
        let mid = (low + high) / 2
        if halftoneCoveredFraction(mid) < coverage { low = mid } else { high = mid }
    }
    return (low + high) / 2
}

// MARK: - Sampling

@MainActor
private enum HalftoneNotes {
    static var printed = Set<String>()
    static func note(_ message: String) {
        guard !printed.contains(message) else { return }
        printed.insert(message)
        print("Ollin: \(message)")
    }
}

/// Straight sRGB byte to linear light, tabulated so the per-pixel ink
/// integral never pays a transfer-curve evaluation.
private let srgbByteToLinear: [Double] = (0 ... 255).map {
    Color.srgbToLinear(Double($0) / 255)
}

@MainActor
func halftoneDots(of image: Image,
                  pitch: Double,
                  angle: Double,
                  bounds: Rectangle,
                  inverted: Bool) -> [HalftoneDot] {
    guard image.width > 0, image.height > 0,
          bounds.width > 0, bounds.height > 0 else { return [] }
    guard let pixels = image.premultipliedPixels() else {
        HalftoneNotes.note("halftone needs CPU pixels; a texture-backed image has none. Read a video frame through its snapshot first.")
        return []
    }
    // The same floor the raster screen applies: below it the cells are finer
    // than the marks they'd hold, and the dot count explodes.
    let cell = Swift.max(2, pitch)

    // The image keeps its aspect inside `bounds`; the screen is anchored at
    // the fitted rect's center, so the lattice stays put under resizes.
    let fitted = Rectangle(fitting: image.size, in: bounds)
    let scale = fitted.width / Double(image.width)
    let cosA = cos(angle), sinA = sin(angle)
    let centerX = fitted.x + fitted.width / 2
    let centerY = fitted.y + fitted.height / 2

    // Lattice extent: the fitted corners carried into screen coordinates.
    var minU = Double.infinity, maxU = -Double.infinity
    var minV = Double.infinity, maxV = -Double.infinity
    for corner in [Vector2(fitted.x, fitted.y),
                   Vector2(fitted.x + fitted.width, fitted.y),
                   Vector2(fitted.x, fitted.y + fitted.height),
                   Vector2(fitted.x + fitted.width, fitted.y + fitted.height)] {
        let dx = corner.x - centerX, dy = corner.y - centerY
        let u = (dx * cosA + dy * sinA) / cell
        let v = (-dx * sinA + dy * cosA) / cell
        minU = Swift.min(minU, u); maxU = Swift.max(maxU, u)
        minV = Swift.min(minV, v); maxV = Swift.max(maxV, v)
    }
    let columnLow = Int(minU.rounded()) - 1, columnHigh = Int(maxU.rounded()) + 1
    let rowLow = Int(minV.rounded()) - 1, rowHigh = Int(maxV.rounded()) + 1
    let columns = columnHigh - columnLow + 1
    let rows = rowHigh - rowLow + 1
    guard columns > 0, rows > 0 else { return [] }

    // Bin every image pixel into its rotated cell (exact membership, the same
    // partition the raster screen thresholds), accumulating the ink integral
    // and the premultiplied color sums.
    let cellCount = columns * rows
    var counts = [Int](repeating: 0, count: cellCount)
    var alphaSum = [Double](repeating: 0, count: cellCount)
    var lumaSum = [Double](repeating: 0, count: cellCount)
    var redSum = [Double](repeating: 0, count: cellCount)
    var greenSum = [Double](repeating: 0, count: cellCount)
    var blueSum = [Double](repeating: 0, count: cellCount)

    let width = image.width, height = image.height
    let uStepX = scale * cosA / cell
    let vStepX = -scale * sinA / cell
    for py in 0 ..< height {
        let y = fitted.y + (Double(py) + 0.5) * scale
        let dy = y - centerY
        let x0 = fitted.x + 0.5 * scale
        var u = ((x0 - centerX) * cosA + dy * sinA) / cell
        var v = (-(x0 - centerX) * sinA + dy * cosA) / cell
        var i = py * width * 4
        for _ in 0 ..< width {
            let column = Int(u.rounded()) - columnLow
            let row = Int(v.rounded()) - rowLow
            let slot = row * columns + column
            let alphaByte = Int(pixels[i + 3])
            counts[slot] += 1
            if alphaByte > 0 {
                let alpha = Double(alphaByte) / 255
                // Straight bytes back out of the premultiplied store, then
                // linear-light luminance: dot area maps to reflectance, so
                // the ink integral runs in linear, the stipple rule.
                let red = Swift.min(Int(pixels[i]) * 255 / alphaByte, 255)
                let green = Swift.min(Int(pixels[i + 1]) * 255 / alphaByte, 255)
                let blue = Swift.min(Int(pixels[i + 2]) * 255 / alphaByte, 255)
                let luma = 0.2126 * srgbByteToLinear[red]
                         + 0.7152 * srgbByteToLinear[green]
                         + 0.0722 * srgbByteToLinear[blue]
                alphaSum[slot] += alpha
                lumaSum[slot] += luma * alpha
                redSum[slot] += Double(pixels[i])
                greenSum[slot] += Double(pixels[i + 1])
                blueSum[slot] += Double(pixels[i + 2])
            }
            u += uStepX
            v += vStepX
            i += 4
        }
    }

    // The smallest dot a press holds, shared with the raster screen: coverage
    // below it prints as bare paper, above its complement as solid ink.
    let minimumDot = 0.02

    var dots: [HalftoneDot] = []
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            let slot = row * columns + column
            let count = counts[slot]
            guard count > 0 else { continue }
            let ink = inverted ? lumaSum[slot] : alphaSum[slot] - lumaSum[slot]
            var coverage = ink / Double(count)
            if coverage < minimumDot { continue }
            if coverage > 1 - minimumDot { coverage = 1 }

            let latticeColumn = Double(column + columnLow)
            let latticeRow = Double(row + rowLow)
            let center = Vector2(
                centerX + (latticeColumn * cosA - latticeRow * sinA) * cell,
                centerY + (latticeColumn * sinA + latticeRow * cosA) * cell)
            guard fitted.contains(center) else { continue }

            let alpha = alphaSum[slot] / Double(count)
            let denominator = Swift.max(alphaSum[slot] * 255, 1e-9)
            let straight = alpha > 0
                ? Color(red: Swift.min(redSum[slot] / denominator, 1),
                        green: Swift.min(greenSum[slot] / denominator, 1),
                        blue: Swift.min(blueSum[slot] / denominator, 1),
                        alpha: alpha)
                : .clear
            dots.append(HalftoneDot(
                column: column + columnLow,
                row: row + rowLow,
                center: center,
                radius: halftoneDotRadius(coverage: coverage) * cell / 2,
                coverage: coverage,
                color: straight))
        }
    }
    return dots
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The halftone screen of `image` as data: one `HalftoneDot` per cell of
    /// a grid rotated by `angle` (the classic 45-degree screen by default),
    /// each dot sized so its ink area matches the tone under the cell. The
    /// image keeps its aspect inside `bounds` (the whole canvas by default);
    /// cells lighter than the printable minimum are omitted. Deterministic,
    /// so a screen is snapshot- and recipe-safe.
    ///
    /// Use this form for custom drawing; `drawHalftone` is the one-call form.
    func halftone(of image: Image,
                  pitch: Double = 12,
                  angle: Double = .pi / 4,
                  in bounds: Rectangle? = nil,
                  inverted: Bool = false) -> [HalftoneDot] {
        halftoneDots(of: image, pitch: pitch, angle: angle,
                     bounds: bounds ?? canvasRectangle, inverted: inverted)
    }

    /// Draw `image` as a classic halftone dot screen: round dots on a grid
    /// `pitch` canvas units apart, rotated by `angle`, each sized so its ink
    /// area matches the tone underneath. Dark regions grow big dots that
    /// merge into the traditional checkered diamonds; pass `inverted: true`
    /// for light marks on a dark canvas. Dots draw with the current `fill`
    /// and `stroke`, or tinted by the image itself with `colored: true`.
    ///
    /// ```swift
    /// fill(.black)
    /// noStroke()
    /// drawHalftone(picture, pitch: 14)
    /// ```
    ///
    /// For the pixel-space version of the same look, see the `.halftone` and
    /// `.cmykHalftone` filters; this form emits real circles, so it feeds the
    /// vector SVG and PDF exports and the pen-plotter path.
    func drawHalftone(_ image: Image,
                      pitch: Double = 12,
                      angle: Double = .pi / 4,
                      in bounds: Rectangle? = nil,
                      inverted: Bool = false,
                      colored: Bool = false) {
        let dots = halftone(of: image, pitch: pitch, angle: angle,
                            in: bounds, inverted: inverted)
        guard !dots.isEmpty else { return }
        if colored {
            withState {
                for dot in dots {
                    fill(dot.color)
                    drawCircle(center: dot.center, radius: dot.radius)
                }
            }
        } else {
            drawCircles(dots.map { Circle(center: $0.center, radius: $0.radius) })
        }
    }
}
