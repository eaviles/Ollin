import simd

/// A four-by-five matrix over the channels of a color: what each channel of
/// the result takes from the input's red, green, blue, and alpha, and a number
/// added at the end.
///
/// Every output channel is a weighted sum of the four input channels plus an
/// offset, which is enough to trade channels, mix a gray from any recipe, lift
/// or invert one channel, or tint. A photo tool's channel mixer is a matrix
/// like this with the alpha row left alone. `Filter.channelMixer(_:)` runs one
/// over a layer, in linear light, with the color straightened out of its alpha
/// for the multiply and put back after.
///
/// Rows are given per output channel, each `[r, g, b, a, offset]`; a row left
/// out keeps its channel as it is:
///
/// ```swift
/// ColorMatrix(red: [0, 0, 1], blue: [1, 0, 0])       // red and blue traded
/// ColorMatrix(red: [1, 0, 0, 0, 0.1])                // red lifted by a tenth
/// ColorMatrix.gray(red: 0.6, green: 0.3, blue: 0.1)  // a red-filter monochrome
/// ```
public struct ColorMatrix: Sendable, Equatable {

    /// A channel of a color, for the presets that trade two.
    public enum Channel: Sendable, CaseIterable {
        case red, green, blue, alpha

        /// The channel's row and column in the matrix.
        var index: Int {
            switch self {
            case .red:   return 0
            case .green: return 1
            case .blue:  return 2
            case .alpha: return 3
            }
        }
    }

    /// The twenty numbers, row-major: the red row, then green, blue, and
    /// alpha, each holding the weights of the input's red, green, blue, and
    /// alpha and then the offset added last.
    public let values: [Double]

    /// A matrix from four rows, each `[r, g, b, a, offset]`: how much of the
    /// input's red, green, blue, and alpha goes into that channel, and a
    /// number added at the end. A row left out keeps its channel as it is, a
    /// row shorter than five reads its missing entries as zero, and a longer
    /// one is read to its fifth number.
    public init(red: [Double] = [1, 0, 0, 0, 0], green: [Double] = [0, 1, 0, 0, 0],
                blue: [Double] = [0, 0, 1, 0, 0], alpha: [Double] = [0, 0, 0, 1, 0]) {
        func five(_ row: [Double]) -> [Double] {
            Array(row.prefix(5)) + Array(repeating: 0, count: max(0, 5 - row.count))
        }
        values = five(red) + five(green) + five(blue) + five(alpha)
    }

    /// Every channel as it is.
    public static let identity = ColorMatrix()

    /// The gray a display makes of a color: the same brightness in red, green,
    /// and blue, weighted as the primaries' light is (the BT.709 weights, in
    /// linear light). Alpha is kept.
    public static let gray = ColorMatrix.gray()

    /// A gray mixed to a recipe: red, green, and blue each get `red` of the
    /// input's red, `green` of its green, and `blue` of its blue, the way a
    /// black-and-white photographer's colored filter weights a scene. The
    /// defaults are the display's own weights; a recipe that adds up to one
    /// keeps the brightness, and one that does not lifts or darkens it.
    public static func gray(red: Double = 0.2126, green: Double = 0.7152,
                            blue: Double = 0.0722) -> ColorMatrix {
        let row = [red, green, blue, 0, 0]
        return ColorMatrix(red: row, green: row, blue: row)
    }

    /// Two channels traded: `.swapping(.red, .blue)` shows the red channel
    /// where blue was and blue where red was. The same channel twice is the
    /// identity.
    public static func swapping(_ a: Channel, _ b: Channel) -> ColorMatrix {
        var rows: [[Double]] = [[1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 1, 0]]
        rows.swapAt(a.index, b.index)
        return ColorMatrix(red: rows[0], green: rows[1], blue: rows[2], alpha: rows[3])
    }

    /// The rows as the shader reads them: four rows of the input weights, in
    /// the order of the output channels, then the offsets as a fifth row.
    var shaderRows: [SIMD4<Float>] {
        func row(_ i: Int) -> SIMD4<Float> {
            SIMD4(Float(values[i * 5]), Float(values[i * 5 + 1]),
                  Float(values[i * 5 + 2]), Float(values[i * 5 + 3]))
        }
        let offsets = SIMD4(Float(values[4]), Float(values[9]), Float(values[14]), Float(values[19]))
        return [row(0), row(1), row(2), row(3), offsets]
    }
}
