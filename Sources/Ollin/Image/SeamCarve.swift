import Foundation

/// Seam carving: change a picture's proportions by taking away the paths that
/// carry the least, instead of squeezing every pixel by the same amount. A
/// *seam* is a connected run of pixels, one per row (or one per column), that
/// walks from one edge to the other. The cheapest seam is the one whose
/// removal costs the picture the least, and removing it narrows the picture by
/// exactly one pixel while the things that matter keep their shape.
///
/// The technique is Shai Avidan and Ariel Shamir's (*Seam Carving for
/// Content-Aware Image Resizing*, 2007); the default cost is the forward
/// energy of Michael Rubinstein, Ariel Shamir, and Shai Avidan (*Improved Seam
/// Carving for Video Retargeting*, 2008), which asks what a removal *adds* to
/// the picture rather than what it takes away.
///
/// ```swift
/// let narrow = picture.seamCarved(toWidth: 240)
/// ```
///
/// Everything here is CPU work at the picture's own resolution, and one seam
/// costs a full pass over the picture. Carve in `setup()`, or build a
/// ``SeamMap`` once and read any width out of it per frame.

/// How much a seam costs to remove.
public enum SeamEnergy: Sendable {
    /// The energy the removal *adds*: the new edges that appear when the two
    /// sides close over the gap. Steadier under heavy carving, and the default.
    case forward
    /// The energy the removal *takes away*: the gradient already at each pixel.
    /// Cheaper to reason about, and the original measure.
    case gradient
}

/// Which way a seam runs through the picture.
public enum SeamDirection: Sendable {
    /// Top to bottom, one pixel per row. Removing one narrows the picture.
    case vertical
    /// Left to right, one pixel per column. Removing one shortens the picture.
    case horizontal
}

// MARK: - The public calls

public extension Image {
    /// A copy of this picture carved to `width` and `height`, seam by seam.
    /// A smaller target removes the cheapest seams; a larger one duplicates
    /// them, spreading the added pixels over the whole picture rather than
    /// stretching one part of it. Leave an axis out to keep it as it is.
    ///
    /// Both axes carve one after the other, width first. A picture can grow to
    /// at most twice its size on an axis, because a seam is only duplicated
    /// once; ask for more and the target clamps.
    ///
    /// - Parameters:
    ///   - width: The width to carve to. `nil` keeps the current width.
    ///   - height: The height to carve to. `nil` keeps the current height.
    ///   - energy: The cost a seam is judged by.
    ///   - protected: A mask whose bright, opaque pixels no seam crosses. Use
    ///     it to hold a face or a horizon still while the rest gives way.
    ///   - discarded: A mask whose bright, opaque pixels every seam is drawn
    ///     to. Carve away as many seams as the marked thing is wide and it
    ///     leaves the picture.
    func seamCarved(toWidth width: Int? = nil,
                    toHeight height: Int? = nil,
                    energy: SeamEnergy = .forward,
                    protecting protected: Image? = nil,
                    discarding discarded: Image? = nil) -> Image {
        guard let source = premultipliedPixels() else {
            print("Ollin: seamCarved needs CPU pixels; a texture-backed image has none. Read a frame through its snapshot first.")
            return self
        }
        let targetWidth = clampedTarget(width ?? self.width, from: self.width)
        let targetHeight = clampedTarget(height ?? self.height, from: self.height)
        guard targetWidth != self.width || targetHeight != self.height else { return self }

        var words = packWords(source)
        var bias = maskBias(protecting: protected, discarding: discarded)
        var currentWidth = self.width
        var currentHeight = self.height

        if targetWidth != currentWidth {
            let steps = abs(targetWidth - currentWidth)
            let order = seamOrder(words: words, bias: bias,
                                  width: currentWidth, height: currentHeight,
                                  steps: steps, energy: energy)
            let grows = targetWidth > currentWidth
            words = resizedWords(words, order: order, width: currentWidth,
                                 height: currentHeight, steps: steps, growing: grows)
            bias = resizedBias(bias, order: order, width: currentWidth,
                               height: currentHeight, steps: steps, growing: grows)
            currentWidth = targetWidth
        }

        if targetHeight != currentHeight {
            var turned = transposedWords(words, width: currentWidth, height: currentHeight)
            var turnedBias = transposedFloats(bias, width: currentWidth, height: currentHeight)
            let steps = abs(targetHeight - currentHeight)
            let order = seamOrder(words: turned, bias: turnedBias,
                                  width: currentHeight, height: currentWidth,
                                  steps: steps, energy: energy)
            let grows = targetHeight > currentHeight
            turned = resizedWords(turned, order: order, width: currentHeight,
                                  height: currentWidth, steps: steps, growing: grows)
            turnedBias = resizedBias(turnedBias, order: order, width: currentHeight,
                                     height: currentWidth, steps: steps, growing: grows)
            words = transposedWords(turned, width: targetHeight, height: currentWidth)
            bias = transposedFloats(turnedBias, width: targetHeight, height: currentWidth)
            currentHeight = targetHeight
        }

        return Image(width: currentWidth, height: currentHeight,
                     premultipliedRGBA: unpackWords(words)) ?? self
    }

    /// The first `count` seams this picture would give up, cheapest first, as
    /// open contours in its own pixel coordinates. Draw them over the picture
    /// to see what the carve is about to take, or send them to a plotter.
    ///
    /// - Parameters:
    ///   - count: How many seams to find.
    ///   - direction: Which way the seams run.
    ///   - energy: The cost a seam is judged by.
    ///   - protected: A mask whose bright, opaque pixels no seam crosses.
    ///   - discarded: A mask whose bright, opaque pixels every seam is drawn to.
    func seams(_ count: Int,
               along direction: SeamDirection = .vertical,
               energy: SeamEnergy = .forward,
               protecting protected: Image? = nil,
               discarding discarded: Image? = nil) -> [Contour] {
        guard let source = premultipliedPixels() else {
            print("Ollin: seams needs CPU pixels; a texture-backed image has none. Read a frame through its snapshot first.")
            return []
        }
        let across = direction == .vertical ? width : height
        let along = direction == .vertical ? height : width
        let steps = Swift.max(0, Swift.min(count, across - 1))
        guard steps > 0 else { return [] }

        var words = packWords(source)
        var bias = maskBias(protecting: protected, discarding: discarded)
        if direction == .horizontal {
            words = transposedWords(words, width: width, height: height)
            bias = transposedFloats(bias, width: width, height: height)
        }
        let order = seamOrder(words: words, bias: bias, width: across,
                              height: along, steps: steps, energy: energy)

        var paths = [[Vector2]](repeating: [], count: steps)
        for row in 0 ..< along {
            for column in 0 ..< across {
                let index = Int(order[row * across + column])
                guard index < steps else { continue }
                paths[index].append(direction == .vertical
                    ? Vector2(Double(column) + 0.5, Double(row) + 0.5)
                    : Vector2(Double(row) + 0.5, Double(column) + 0.5))
            }
        }
        return paths.map { Contour($0, closed: false) }
    }

    /// Every seam this picture holds, worked out once, so any size can be read
    /// back from it at once. Building the map costs one pass per seam, which is
    /// `setup()` work; reading a size out of it is a single copy, which is
    /// cheap enough for `draw()`.
    ///
    /// - Parameters:
    ///   - direction: Which way the seams run.
    ///   - energy: The cost a seam is judged by.
    ///   - protected: A mask whose bright, opaque pixels no seam crosses.
    ///   - discarded: A mask whose bright, opaque pixels every seam is drawn to.
    func seamMap(along direction: SeamDirection = .vertical,
                 energy: SeamEnergy = .forward,
                 protecting protected: Image? = nil,
                 discarding discarded: Image? = nil) -> SeamMap? {
        guard let source = premultipliedPixels() else {
            print("Ollin: seamMap needs CPU pixels; a texture-backed image has none. Read a frame through its snapshot first.")
            return nil
        }
        let across = direction == .vertical ? width : height
        let along = direction == .vertical ? height : width
        guard across > 1, along > 0 else { return nil }

        var words = packWords(source)
        var bias = maskBias(protecting: protected, discarding: discarded)
        if direction == .horizontal {
            words = transposedWords(words, width: width, height: height)
            bias = transposedFloats(bias, width: width, height: height)
        }
        let order = seamOrder(words: words, bias: bias, width: across,
                              height: along, steps: across - 1, energy: energy)
        return SeamMap(width: width, height: height, direction: direction,
                       words: words, order: order)
    }

    /// What the carve reads: a gray picture of how much each pixel costs. Bright
    /// means expensive, so bright is what the seams walk around.
    ///
    /// - Parameters:
    ///   - energy: `.gradient` shows the edge strength already at each pixel;
    ///     `.forward` shows what removing the pixel would add to the picture,
    ///     which is what the default carve answers to.
    ///   - direction: Which way a seam would run. `.gradient` reads the same
    ///     either way; `.forward` does not.
    func seamEnergy(_ energy: SeamEnergy = .forward,
                    along direction: SeamDirection = .vertical) -> Image? {
        guard let source = premultipliedPixels() else {
            print("Ollin: seamEnergy needs CPU pixels; a texture-backed image has none. Read a frame through its snapshot first.")
            return nil
        }
        var words = packWords(source)
        if direction == .horizontal {
            words = transposedWords(words, width: width, height: height)
        }
        let across = direction == .vertical ? width : height
        let along = direction == .vertical ? height : width
        let gray = grayValues(words, count: across * along)
        var cost = [Float](repeating: 0, count: across * along)
        for row in 0 ..< along {
            for column in 0 ..< across {
                cost[row * across + column] = energy == .gradient
                    ? gradientCost(gray, width: across, height: along, x: column, y: row)
                    : straightCost(gray, width: across, x: column, row: row * across)
            }
        }
        let peak = cost.max() ?? 0
        let scale = peak > 0 ? 1 / peak : 0
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0 ..< along {
            for column in 0 ..< across {
                let level = UInt8(Swift.min(255, Swift.max(0, Int((cost[row * across + column] * scale) * 255 + 0.5))))
                let target = direction == .vertical
                    ? (row * width + column) * 4
                    : (column * width + row) * 4
                bytes[target] = level
                bytes[target + 1] = level
                bytes[target + 2] = level
            }
        }
        return Image(width: width, height: height, premultipliedRGBA: bytes)
    }
}

// MARK: - The map

/// Every seam of one picture, in the order the carve gives them up, so a size
/// can be read back without carving again. Build it with
/// ``Image/seamMap(along:energy:protecting:discarding:)``.
public struct SeamMap: Sendable {
    /// The width of the picture the map was built from.
    public let width: Int
    /// The height of the picture the map was built from.
    public let height: Int
    /// Which way the seams run.
    public let direction: SeamDirection

    /// The picture's pixels, held in the direction the seams run.
    private let words: [UInt32]
    /// Which seam takes each pixel; a pixel no seam takes holds `Int32.max`.
    private let order: [Int32]

    init(width: Int, height: Int, direction: SeamDirection,
         words: [UInt32], order: [Int32]) {
        self.width = width
        self.height = height
        self.direction = direction
        self.words = words
        self.order = order
    }

    /// The size across the seams the map was built at: the width for vertical
    /// seams, the height for horizontal ones.
    public var size: Int { direction == .vertical ? width : height }

    /// The sizes the map can hand back, across the seams. A picture shrinks to
    /// one pixel and grows to twice its size.
    public var sizes: ClosedRange<Int> { 1 ... (2 * size - 1) }

    /// The picture at `size` across the seams: the width for vertical seams,
    /// the height for horizontal ones. Sizes outside ``sizes`` clamp.
    public func image(_ size: Int) -> Image? {
        let across = self.size
        let along = direction == .vertical ? height : width
        let target = Swift.min(Swift.max(size, sizes.lowerBound), sizes.upperBound)
        let steps = abs(target - across)
        let resized = steps == 0
            ? words
            : resizedWords(words, order: order, width: across, height: along,
                           steps: steps, growing: target > across)
        return direction == .vertical
            ? Image(width: target, height: along, premultipliedRGBA: unpackWords(resized))
            : Image(width: along, height: target,
                    premultipliedRGBA: unpackWords(transposedWords(resized, width: target, height: along)))
    }

    /// Seam number `index`, counting from the cheapest, as an open contour in
    /// the picture's own pixel coordinates.
    public func seam(_ index: Int) -> Contour {
        let across = size
        let along = direction == .vertical ? height : width
        guard index >= 0, index < across - 1 else { return Contour([], closed: false) }
        var points: [Vector2] = []
        points.reserveCapacity(along)
        for row in 0 ..< along {
            for column in 0 ..< across where Int(order[row * across + column]) == index {
                points.append(direction == .vertical
                    ? Vector2(Double(column) + 0.5, Double(row) + 0.5)
                    : Vector2(Double(row) + 0.5, Double(column) + 0.5))
                break
            }
        }
        return Contour(points, closed: false)
    }
}

// MARK: - Carving

/// Work out which seam takes each pixel, for the first `steps` seams. Every
/// pixel a seam takes holds that seam's number; the rest hold `Int32.max`.
///
/// The picture is carved for real as it goes (the pixels close over each gap),
/// because the next seam has to read the picture the last one left behind.
private func seamOrder(words: [UInt32], bias: [Float], width: Int, height: Int,
                       steps: Int, energy: SeamEnergy) -> [Int32] {
    var order = [Int32](repeating: .max, count: width * height)
    guard width > 1, height > 0, steps > 0 else { return order }

    // The picture being carved keeps its first row stride, so a removal is a
    // shift left inside each row rather than a fresh buffer every seam.
    var weight = bias
    var gray = grayValues(words, count: width * height)
    var origin = [Int32](repeating: 0, count: width * height)
    for row in 0 ..< height {
        for column in 0 ..< width { origin[row * width + column] = Int32(column) }
    }

    var live = width
    var cost = [Float](repeating: 0, count: width)
    var previous = [Float](repeating: 0, count: width)
    var parent = [Int8](repeating: 0, count: width * height)
    // Only the gradient cost needs a map of its own; the forward cost is read
    // out of the picture as the pass walks it.
    var gradient = [Float](repeating: 0, count: energy == .gradient ? width * height : 0)

    for step in 0 ..< Swift.min(steps, width - 1) {
        if energy == .gradient {
            for row in 0 ..< height {
                for column in 0 ..< live {
                    gradient[row * width + column] = gradientCost(gray, width: width,
                                                                  height: height,
                                                                  x: column, y: row,
                                                                  live: live)
                }
            }
        }

        for row in 0 ..< height {
            let base = row * width
            for column in 0 ..< live {
                let here = base + column
                let left = gray[base + Swift.max(column - 1, 0)]
                let right = gray[base + Swift.min(column + 1, live - 1)]
                let straight = abs(left - right)

                if row == 0 {
                    cost[column] = (energy == .gradient ? gradient[here] : straight) + weight[here]
                    parent[here] = 0
                    continue
                }

                let up = gray[here - width]
                var best = Float.infinity
                var choice: Int8 = 0
                if energy == .gradient {
                    if column > 0, previous[column - 1] < best { best = previous[column - 1]; choice = -1 }
                    if previous[column] < best { best = previous[column]; choice = 0 }
                    if column < live - 1, previous[column + 1] < best { best = previous[column + 1]; choice = 1 }
                    cost[column] = best + gradient[here] + weight[here]
                } else {
                    // Forward energy: what the two new neighbors cost once the
                    // seam has passed, which is why each way in has its own price.
                    if column > 0 {
                        let candidate = previous[column - 1] + straight + abs(up - left)
                        if candidate < best { best = candidate; choice = -1 }
                    }
                    let straightIn = previous[column] + straight
                    if straightIn < best { best = straightIn; choice = 0 }
                    if column < live - 1 {
                        let candidate = previous[column + 1] + straight + abs(up - right)
                        if candidate < best { best = candidate; choice = 1 }
                    }
                    cost[column] = best + weight[here]
                }
                parent[here] = choice
            }
            swap(&previous, &cost)
        }

        // The cheapest end, then walk the seam back up to the top row. A tie
        // takes the leftmost column, so the same picture always carves the same.
        var column = 0
        var best = Float.infinity
        for candidate in 0 ..< live where previous[candidate] < best {
            best = previous[candidate]
            column = candidate
        }

        for row in stride(from: height - 1, through: 0, by: -1) {
            let base = row * width
            order[row * width + Int(origin[base + column])] = Int32(step)
            let choice = Int(parent[base + column])
            // Closing the gap: everything to the right of the seam shifts left.
            for slot in column ..< (live - 1) {
                gray[base + slot] = gray[base + slot + 1]
                weight[base + slot] = weight[base + slot + 1]
                origin[base + slot] = origin[base + slot + 1]
            }
            column = Swift.max(0, Swift.min(column + choice, live - 1))
        }
        live -= 1
        if live < 2 { break }
    }
    return order
}

/// The gradient cost at one pixel: how fast the picture changes there, across
/// and down, with the edges reading their own value back.
private func gradientCost(_ gray: [Float], width: Int, height: Int,
                          x: Int, y: Int, live: Int? = nil) -> Float {
    let span = live ?? width
    let base = y * width
    let left = gray[base + Swift.max(x - 1, 0)]
    let right = gray[base + Swift.min(x + 1, span - 1)]
    let up = gray[Swift.max(y - 1, 0) * width + x]
    let down = gray[Swift.min(y + 1, height - 1) * width + x]
    return abs(left - right) + abs(up - down)
}

/// The cost of a seam passing straight through one pixel: the edge that appears
/// when its two side neighbors become neighbors of each other.
private func straightCost(_ gray: [Float], width: Int, x: Int, row: Int) -> Float {
    abs(gray[row + Swift.max(x - 1, 0)] - gray[row + Swift.min(x + 1, width - 1)])
}

// MARK: - Reading a size out of an order map

/// The picture with its first `steps` seams taken out, or put in twice.
private func resizedWords(_ words: [UInt32], order: [Int32], width: Int, height: Int,
                          steps: Int, growing: Bool) -> [UInt32] {
    let target = growing ? width + steps : width - steps
    var output = [UInt32](repeating: 0, count: target * height)
    for row in 0 ..< height {
        var slot = row * target
        for column in 0 ..< width {
            let index = Int(order[row * width + column])
            if growing {
                output[slot] = words[row * width + column]
                slot += 1
                guard index < steps, slot < (row + 1) * target else { continue }
                // A duplicated seam pixel is the average of the two it sits
                // between, so the copy reads as a widening rather than a stutter.
                let neighbor = words[row * width + Swift.min(column + 1, width - 1)]
                output[slot] = averageWord(words[row * width + column], neighbor)
                slot += 1
            } else if index >= steps {
                output[slot] = words[row * width + column]
                slot += 1
            }
        }
    }
    return output
}

/// The mask weights carried through the same resize, so a second axis carves
/// against the mask the first one left.
private func resizedBias(_ bias: [Float], order: [Int32], width: Int, height: Int,
                         steps: Int, growing: Bool) -> [Float] {
    let target = growing ? width + steps : width - steps
    var output = [Float](repeating: 0, count: target * height)
    for row in 0 ..< height {
        var slot = row * target
        for column in 0 ..< width {
            let index = Int(order[row * width + column])
            let value = bias[row * width + column]
            if growing {
                output[slot] = value
                slot += 1
                guard index < steps, slot < (row + 1) * target else { continue }
                output[slot] = (value + bias[row * width + Swift.min(column + 1, width - 1)]) / 2
                slot += 1
            } else if index >= steps {
                output[slot] = value
                slot += 1
            }
        }
    }
    return output
}

// MARK: - Pixels

/// One pixel per 32-bit word, so a whole pixel moves in one write.
private func packWords(_ bytes: [UInt8]) -> [UInt32] {
    var words = [UInt32](repeating: 0, count: bytes.count / 4)
    bytes.withUnsafeBytes { raw in
        words.withUnsafeMutableBytes { $0.copyMemory(from: raw) }
    }
    return words
}

private func unpackWords(_ words: [UInt32]) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: words.count * 4)
    words.withUnsafeBytes { raw in
        bytes.withUnsafeMutableBytes { $0.copyMemory(from: raw) }
    }
    return bytes
}

/// Two pixels averaged channel by channel, in the premultiplied form they are
/// already held in, so transparency averages with its color.
private func averageWord(_ a: UInt32, _ b: UInt32) -> UInt32 {
    var result: UInt32 = 0
    for shift in stride(from: 0, through: 24, by: 8) {
        let left = (a >> UInt32(shift)) & 0xFF
        let right = (b >> UInt32(shift)) & 0xFF
        result |= ((left + right) / 2) << UInt32(shift)
    }
    return result
}

/// The brightness the carve reads, straight (not premultiplied) so a
/// translucent pixel is read by its own color. A clear pixel reads as black.
private func grayValues(_ words: [UInt32], count: Int) -> [Float] {
    var gray = [Float](repeating: 0, count: count)
    for i in 0 ..< count {
        let word = words[i]
        let alpha = Double((word >> 24) & 0xFF) / 255
        guard alpha > 0 else { continue }
        let r = Swift.min(Double(word & 0xFF) / 255 / alpha, 1)
        let g = Swift.min(Double((word >> 8) & 0xFF) / 255 / alpha, 1)
        let b = Swift.min(Double((word >> 16) & 0xFF) / 255 / alpha, 1)
        gray[i] = Float(0.2126 * r + 0.7152 * g + 0.0722 * b)
    }
    return gray
}

private func transposedWords(_ words: [UInt32], width: Int, height: Int) -> [UInt32] {
    var output = [UInt32](repeating: 0, count: words.count)
    for row in 0 ..< height {
        for column in 0 ..< width {
            output[column * height + row] = words[row * width + column]
        }
    }
    return output
}

private func transposedFloats(_ values: [Float], width: Int, height: Int) -> [Float] {
    var output = [Float](repeating: 0, count: values.count)
    for row in 0 ..< height {
        for column in 0 ..< width {
            output[column * height + row] = values[row * width + column]
        }
    }
    return output
}

// MARK: - Masks

/// How far a target size may go: down to one pixel, up to twice the size, since
/// a seam is only ever duplicated once.
private func clampedTarget(_ target: Int, from size: Int) -> Int {
    Swift.min(Swift.max(target, 1), Swift.max(1, 2 * size - 1))
}

private extension Image {
    /// The per-pixel cost the masks add: a large price on what is protected, a
    /// large discount on what is to be discarded. A mask marks with brightness
    /// and opacity together, so white on black and white on clear both read.
    func maskBias(protecting protected: Image?, discarding discarded: Image?) -> [Float] {
        var bias = [Float](repeating: 0, count: width * height)
        guard protected != nil || discarded != nil else { return bias }
        // Far above any real energy, which tops out near 3, so a marked pixel
        // decides the seam by itself.
        let strength: Float = 1000
        if let protected { add(protected, to: &bias, scale: strength, what: "protecting") }
        if let discarded { add(discarded, to: &bias, scale: -strength, what: "discarding") }
        return bias
    }

    private func add(_ mask: Image, to bias: inout [Float], scale: Float, what: String) {
        guard mask.width == width, mask.height == height else {
            print("Ollin: the \(what) mask is \(mask.width)x\(mask.height); this picture is \(width)x\(height). The mask was left out.")
            return
        }
        guard let bytes = mask.premultipliedPixels() else {
            print("Ollin: the \(what) mask has no CPU pixels; a texture-backed image has none. The mask was left out.")
            return
        }
        for i in 0 ..< bias.count {
            let alpha = Float(bytes[i * 4 + 3]) / 255
            guard alpha > 0 else { continue }
            let r = Float(bytes[i * 4]) / 255
            let g = Float(bytes[i * 4 + 1]) / 255
            let b = Float(bytes[i * 4 + 2]) / 255
            // Premultiplied already, so this is brightness times opacity.
            bias[i] += scale * (0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
    }
}
