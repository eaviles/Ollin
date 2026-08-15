import Foundation
import CoreGraphics

/// One named part of a sketch, put into words.
///
/// A part is whatever means something together: a shape, or a group of shapes
/// that read as one thing. Give it a name a person would use, and a sentence
/// about what it looks like now.
public struct DescribedElement: Equatable, Sendable {

    /// What the part is called ("the sun", "the crowd on the left").
    public var name: String

    /// What it looks like, in a sentence.
    public var text: String

    /// Where it sits on the canvas, when the sketch knows. A part that carries
    /// a region can be pointed at: a screen reader moves to it by position, and
    /// the accessibility inspector draws a box around it.
    public var region: Rectangle?

    public init(name: String, text: String, region: Rectangle? = nil) {
        self.name = name
        self.text = text
        self.region = region
    }

    /// The one line a screen reader reads: the name, then what it looks like.
    public var spoken: String {
        name.isEmpty ? text : "\(name): \(text)"
    }
}

/// What a sketch says about itself, for somebody who cannot see it.
///
/// A sketch fills this in with `describe(_:)` and `describe(_:as:in:)`, and the
/// window hands it to the platform's accessibility layer. It is empty until a
/// sketch says something, and an empty description changes nothing.
public struct SketchDescription: Equatable, Sendable {

    /// The whole piece in a sentence or two.
    public var summary: String?

    /// One place in the reading order. A part that is not in the picture right
    /// now keeps its place and holds no words, so a part that comes and goes
    /// comes back where it was rather than at the end. Somebody reading with a
    /// screen reader is moving through this order by hand, and it must not
    /// rearrange itself under them.
    private struct Slot: Sendable {
        var name: String
        var element: DescribedElement?
    }

    private var slots: [Slot] = []

    /// The parts that are in the picture, in the order they were first named.
    public var elements: [DescribedElement] { slots.compactMap(\.element) }

    public init(summary: String? = nil, elements: [DescribedElement] = []) {
        self.summary = summary
        self.slots = elements.map { Slot(name: $0.name, element: $0) }
    }

    /// Two descriptions are the same when they read the same. A place once held
    /// by a part that has gone is bookkeeping, not something anybody hears.
    public static func == (a: SketchDescription, b: SketchDescription) -> Bool {
        a.summary == b.summary && a.elements == b.elements
    }

    /// Whether the sketch has said anything at all. Asked once a frame by the
    /// window, so it walks the slots rather than building the element list.
    public var isEmpty: Bool { summary == nil && !hasParts }

    /// Everything there is to read, the summary first.
    public var lines: [String] {
        var out: [String] = []
        if let summary { out.append(summary) }
        out.append(contentsOf: elements.map(\.spoken))
        return out
    }

    /// Set or replace the summary. Empty text clears it.
    mutating func setSummary(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        summary = trimmed.isEmpty ? nil : trimmed
    }

    /// Set or replace the part called `name`, keeping its place in the order.
    ///
    /// A repeat call for the same name replaces what is there, which is what
    /// lets a sketch describe a moving part every frame without the list
    /// growing. Empty text takes the part out of the picture; naming it again
    /// puts it back in the same place.
    mutating func setElement(name: String, text: String, region: Rectangle?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A small linear walk, never a dictionary: the order a screen reader
        // moves through the parts has to be the same on every frame, and there
        // are only ever a handful of parts.
        let element = cleanText.isEmpty
            ? nil
            : DescribedElement(name: cleanName, text: cleanText, region: region)
        if let slot = slots.firstIndex(where: { $0.name == cleanName }) {
            slots[slot].element = element
        } else if element != nil {
            slots.append(Slot(name: cleanName, element: element))
        }
    }

    /// A short string that changes only when the *shape* of the description
    /// changes: a part added, removed, or renamed. The window watches this so it
    /// tells the accessibility layer about a new set of parts, and stays quiet
    /// while a sketch is only rewording what is already there.
    var shape: String {
        (summary == nil ? "-" : "+") + elements.map(\.name).joined(separator: "\u{1F}")
    }

    /// Whether any part is in the picture right now.
    var hasParts: Bool { slots.contains { $0.element != nil } }
}

// MARK: - Placing a part in the window

/// Where a canvas region lands in a view's own coordinates.
///
/// The canvas is drawn to fill the view, so the two differ by a scale; the host
/// letterboxes around the outside. The canvas counts y down from the top and
/// the view counts it up from the bottom, so the region is flipped as well as
/// scaled. A canvas with no size yet gives back the whole view.
func viewRect(of region: Rectangle, canvasWidth: Double, canvasHeight: Double,
              in bounds: CGRect, through projection: ProjectionPlacement? = nil) -> CGRect {
    guard canvasWidth > 0, canvasHeight > 0 else { return bounds }
    if let projection {
        return warpedViewRect(of: region, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                              in: bounds, through: projection)
    }
    let sx = Double(bounds.width) / canvasWidth
    let sy = Double(bounds.height) / canvasHeight
    let width = region.width * sx
    let height = region.height * sy
    let x = Double(bounds.minX) + region.corner.x * sx
    let y = Double(bounds.minY) + Double(bounds.height) - region.corner.y * sy - height
    return CGRect(x: x, y: y, width: width, height: height)
}

/// The same question for a piece fitted to a wall, where the canvas lands as a
/// four-sided shape rather than as a rectangle.
///
/// A screen reader wants a rectangle, so the region's four corners go through
/// the map and the box around them is the answer. It is larger than the part
/// itself wherever the picture is turned, which is the right way to be wrong
/// here: a box that covers the part is findable, and one that misses it is not.
private func warpedViewRect(of region: Rectangle, canvasWidth: Double, canvasHeight: Double,
                            in bounds: CGRect, through projection: ProjectionPlacement) -> CGRect {
    let corners = [region.topLeft, region.topRight, region.bottomRight, region.bottomLeft]
    var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
    for corner in corners {
        let onDisplay = projection.outputPoint(
            fromCanvas: Vector2(corner.x / canvasWidth, corner.y / canvasHeight))
        // The canvas counts y down from the top and the view counts it up from
        // the bottom.
        let x = Double(bounds.minX) + onDisplay.x * Double(bounds.width)
        let y = Double(bounds.minY) + Double(bounds.height) * (1 - onDisplay.y)
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
    return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
}

// MARK: - The sketch's own calls

public extension Sketch {

    /// Say what the whole piece looks like, for somebody who cannot see it.
    ///
    /// ```swift
    /// describe("A pale field with one red circle drifting across it.")
    /// ```
    ///
    /// Say it once in `setup()` if the piece does not change, or every frame in
    /// `draw()` if it does. The later call replaces the earlier one, so a
    /// description written every frame costs one line and always matches what
    /// is on screen.
    ///
    /// Describe what is there, not how it is made: a sentence or two in the
    /// present tense, the way you would tell somebody over the telephone.
    /// Empty text clears the description again.
    ///
    /// To *show* the words as well, draw them: `drawCaption(_:)` puts a line on
    /// the canvas.
    func describe(_ text: String) {
        accessibleDescription.setSummary(text)
    }

    /// Say what one named part of the piece looks like.
    ///
    /// ```swift
    /// describe("the sun", as: "a yellow disc high on the left")
    /// describe("the sun", as: "a yellow disc", in: Rectangle(center: p, width: 80, height: 80))
    /// ```
    ///
    /// A part is a shape, or a group of shapes that mean one thing together.
    /// Naming the same part again replaces what you said before, so a part that
    /// moves can be described from inside `draw()`. Empty text drops the part.
    ///
    /// Keep the parts few. A screen reader reads them one after another, and a
    /// list of fifty shapes tells nobody what the piece looks like.
    ///
    /// Give a `region` when you know where the part is: it lets a screen reader
    /// find the part by position instead of only in order.
    func describe(_ name: String, as text: String, in region: Rectangle? = nil) {
        accessibleDescription.setElement(name: name, text: text, region: region)
    }

    /// Drop the description and every named part.
    func noDescription() {
        accessibleDescription = SketchDescription()
    }
}
