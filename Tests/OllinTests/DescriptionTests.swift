import AppKit
import Foundation
import Metal
import Testing
@testable import Ollin

/// A sketch describing itself is words rather than pixels, so there is nothing
/// to snapshot. What can go wrong is the bookkeeping: a part described every
/// frame must not pile up, the order a screen reader walks must not move
/// between frames, and a file that carries no description must be the file it
/// always was.
@Suite
@MainActor
struct DescriptionTests {

    private func sketch() -> Sketch { Sketch() }

    // MARK: - What a sketch says

    @Test func theSummaryIsReplacedRatherThanAppended() {
        let s = sketch()
        s.describe("A red circle.")
        s.describe("A blue square.")
        #expect(s.accessibleDescription.summary == "A blue square.")
        #expect(s.accessibleDescription.elements.isEmpty)
    }

    @Test func emptyTextClearsTheSummary() {
        let s = sketch()
        s.describe("A red circle.")
        s.describe("   ")
        #expect(s.accessibleDescription.summary == nil)
        #expect(s.accessibleDescription.isEmpty)
    }

    @Test func surroundingSpaceIsTrimmed() {
        let s = sketch()
        s.describe("  A red circle.\n")
        s.describe(" sun ", as: "  a yellow disc ")
        #expect(s.accessibleDescription.summary == "A red circle.")
        #expect(s.accessibleDescription.elements.first?.name == "sun")
        #expect(s.accessibleDescription.elements.first?.text == "a yellow disc")
    }

    /// The load-bearing one. A sketch describes its moving parts from inside
    /// `draw()`, so the same names arrive every frame: they have to replace
    /// what is there, and they have to keep their place. A list that grew, or
    /// that reordered itself, would move a screen reader's cursor under the
    /// person using it.
    @Test func aPartDescribedEveryFrameStaysOneEntryInItsOwnPlace() {
        let s = sketch()
        for frame in 0..<10 {
            s.describe("sun", as: "a yellow disc at \(frame)")
            s.describe("sea", as: "a gray band at \(frame)")
        }
        #expect(s.accessibleDescription.elements.count == 2)
        #expect(s.accessibleDescription.elements.map(\.name) == ["sun", "sea"])
        #expect(s.accessibleDescription.elements[0].text == "a yellow disc at 9")
    }

    /// A part that leaves the picture and comes back comes back where it was.
    /// Anything else moves the reading order under somebody who is walking it
    /// by hand: the sun setting must not send it to the bottom of the list at
    /// dawn. Caught by rendering the example, not by reasoning about it.
    @Test func aPartThatComesAndGoesKeepsItsPlaceInTheOrder() {
        let s = sketch()
        s.describe("the sun", as: "a yellow disc")
        s.describe("the water", as: "a flat band")
        s.describe("the boat", as: "a dark hull")

        s.describe("the sun", as: "")                 // it sets
        #expect(s.accessibleDescription.elements.map(\.name) == ["the water", "the boat"])

        s.describe("the sun", as: "a deep orange disc")   // and rises again
        #expect(s.accessibleDescription.elements.map(\.name) == ["the sun", "the water", "the boat"])
    }

    @Test func emptyTextDropsOnePartAndLeavesTheRest() {
        let s = sketch()
        s.describe("sun", as: "a yellow disc")
        s.describe("sea", as: "a gray band")
        s.describe("sun", as: "")
        #expect(s.accessibleDescription.elements.map(\.name) == ["sea"])
    }

    @Test func noDescriptionClearsEverything() {
        let s = sketch()
        s.describe("A seascape.")
        s.describe("sun", as: "a yellow disc")
        s.noDescription()
        #expect(s.accessibleDescription.isEmpty)
        #expect(s.accessibleDescription.elements.isEmpty)
    }

    @Test func aSketchThatSaysNothingHasNothingToRead() {
        #expect(sketch().accessibleDescription.isEmpty)
        #expect(sketch().accessibleDescription.lines.isEmpty)
    }

    // MARK: - What gets read out

    @Test func aPartReadsAsItsNameThenItsDescription() {
        let named = DescribedElement(name: "sun", text: "a yellow disc")
        let nameless = DescribedElement(name: "", text: "a yellow disc")
        #expect(named.spoken == "sun: a yellow disc")
        #expect(nameless.spoken == "a yellow disc")
    }

    @Test func theSummaryIsReadBeforeTheParts() {
        let s = sketch()
        s.describe("sun", as: "a yellow disc")
        s.describe("A seascape.")
        #expect(s.accessibleDescription.lines == ["A seascape.", "sun: a yellow disc"])
    }

    /// The window tells the accessibility layer to look again only when the set
    /// of parts changes. Rewording a part must stay quiet, or a sketch that
    /// describes itself every frame would interrupt a screen reader sixty times
    /// a second.
    @Test func rewordingAPartDoesNotChangeTheShapeButAddingOneDoes() {
        var description = SketchDescription()
        description.setElement(name: "sun", text: "a yellow disc", region: nil)
        let first = description.shape

        description.setElement(name: "sun", text: "a pale disc, lower now", region: nil)
        #expect(description.shape == first)          // same parts, new words

        description.setElement(name: "sea", text: "a gray band", region: nil)
        #expect(description.shape != first)          // a part that was not there

        var withSummary = SketchDescription()
        withSummary.setElement(name: "sun", text: "a yellow disc", region: nil)
        withSummary.setSummary("A seascape.")
        #expect(withSummary.shape != first)          // a summary is part of the shape
    }

    // MARK: - Where a part is

    /// The canvas counts y down from the top and the window counts it up from
    /// the bottom, so a part in the top-left of the canvas has to land in the
    /// top-left of the window. Getting this backwards points a screen reader at
    /// the mirror image of the piece.
    @Test func aPartInTheTopLeftOfTheCanvasLandsInTheTopLeftOfTheView() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let topLeft = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let rect = viewRect(of: topLeft, canvasWidth: 800, canvasHeight: 800, in: bounds)

        #expect(rect.width == 50 && rect.height == 50)     // half scale
        #expect(rect.minX == 0)
        #expect(rect.maxY == 400)                          // the view's top edge

        let bottomLeft = Rectangle(x: 0, y: 700, width: 100, height: 100)
        let flipped = viewRect(of: bottomLeft, canvasWidth: 800, canvasHeight: 800, in: bounds)
        #expect(flipped.minY == 0)                         // the view's bottom edge
    }

    @Test func aCanvasWithNoSizeYetGivesBackTheWholeView() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rect = viewRect(of: Rectangle(x: 0, y: 0, width: 10, height: 10),
                            canvasWidth: 0, canvasHeight: 0, in: bounds)
        #expect(rect == bounds)
    }

    // MARK: - What travels with the file

    final class Described: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            fill(.black)
            drawCircle(50, 50, 20)
            describe("A black circle in the middle of a white square.")
            describe("the circle", as: "black & 40 wide",
                     in: Rectangle(center: Vector2(50, 50), width: 40, height: 40))
        }
    }

    final class Silent: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            fill(.black)
            drawCircle(50, 50, 20)
        }
    }

    @Test func anSVGCarriesWhatTheSketchSaid() {
        let svg = OllinApp.svg(of: Described())
        #expect(svg.contains("<title id=\"ollin-title\">A black circle in the middle of a white square.</title>"))
        #expect(svg.contains("<desc id=\"ollin-desc\">the circle: black &amp; 40 wide</desc>"))
        #expect(svg.contains("role=\"img\""))
        #expect(svg.contains("aria-labelledby=\"ollin-title ollin-desc\""))
        // The description belongs at the top, where a reader looks for it.
        let title = svg.range(of: "<title")!
        let circle = svg.range(of: "<circle")!
        #expect(title.lowerBound < circle.lowerBound)
    }

    /// A sketch that describes nothing writes exactly the file it wrote before
    /// any of this existed: no attributes on the tag, no elements inside it.
    @Test func aSilentSketchWritesTheFileItAlwaysDid() {
        let svg = OllinApp.svg(of: Silent())
        #expect(!svg.contains("role=\"img\""))
        #expect(!svg.contains("aria-labelledby"))
        #expect(!svg.contains("<title"))
        #expect(!svg.contains("<desc"))
        #expect(svg.contains("viewBox=\"0 0 100 100\">\n"))
    }

    // MARK: - What the window hands to the accessibility layer

    /// The wiring is the feature: a description nothing reads is worth nothing.
    /// These drive a real canvas view, so they cover the mapping from what the
    /// sketch said to what a screen reader is given.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDescribedCanvasBecomesSomethingAScreenReaderCanRead() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let s = Sketch()
        s.setCanvasSize(width: 800, height: 800)
        let view = makeOllinMTKView(device: device, size: CGSize(width: 400, height: 400), sketch: s)

        // Nothing said: the canvas stays out of the way entirely.
        #expect(view.isAccessibilityElement() == false)
        #expect(view.accessibilityLabel() == nil)

        // A summary alone: one picture with a name.
        s.describe("A bay at noon.")
        view.refreshDescription()
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .image)
        #expect(view.accessibilityLabel() == "A bay at noon.")

        // Named parts: a group somebody can move through, each part placed.
        s.describe("the sun", as: "a yellow disc",
                   in: Rectangle(x: 0, y: 0, width: 400, height: 400))   // canvas top-left quarter
        s.describe("the water", as: "a flat band")
        view.refreshDescription()
        #expect(view.accessibilityRole() == .group)
        let parts = try #require(view.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(parts.count == 2)
        #expect(parts[0].accessibilityLabel() == "the sun: a yellow disc")
        #expect(parts[1].accessibilityLabel() == "the water: a flat band")

        // The sun's quarter of an 800 canvas is the top-left 200 points of a
        // 400-point view, and AppKit counts y up, so it sits at the top.
        let sun = parts[0].accessibilityFrameInParentSpace()
        #expect(sun.width == 200 && sun.height == 200)
        #expect(sun.minX == 0 && sun.maxY == 400)

        // A part with no region of its own stands for the whole canvas.
        #expect(parts[1].accessibilityFrameInParentSpace() == CGRect(x: 0, y: 0, width: 400, height: 400))
    }

    /// A part that is reworded keeps the same accessibility element, so a
    /// screen reader sitting on it is not thrown off; a part that arrives gets
    /// a new one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func rewordingAPartKeepsTheElementItIsReadthrough() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let s = Sketch()
        s.setCanvasSize(width: 100, height: 100)
        let view = makeOllinMTKView(device: device, size: CGSize(width: 100, height: 100), sketch: s)

        s.describe("the sun", as: "a yellow disc")
        view.refreshDescription()
        let first = try #require(view.accessibilityChildren()?.first as? NSAccessibilityElement)

        s.describe("the sun", as: "a deep orange disc, lower now")
        view.refreshDescription()
        let again = try #require(view.accessibilityChildren()?.first as? NSAccessibilityElement)
        #expect(first === again)
        #expect(again.accessibilityLabel() == "the sun: a deep orange disc, lower now")

        s.describe("the water", as: "a flat band")
        view.refreshDescription()
        #expect(view.accessibilityChildren()?.count == 2)
    }

    @Test func aPDFCarriesTheSummaryAsItsTitle() {
        let data = OllinApp.pdf(of: Described())
        let document = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        var title: CGPDFStringRef?
        #expect(CGPDFDictionaryGetString(document!.info!, "Title", &title))
        let read = CGPDFStringCopyTextString(title!) as String?
        #expect(read == "A black circle in the middle of a white square.")
    }

    @Test func aSilentSketchWritesNoPDFTitle() {
        let data = OllinApp.pdf(of: Silent())
        let document = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        var title: CGPDFStringRef?
        #expect(!CGPDFDictionaryGetString(document!.info!, "Title", &title))
    }
}
