import CoreGraphics
import Foundation
import Metal

/// How far apart the pictures of a piece sit when it is shown as a widget.
///
/// A widget is not a window. The system asks for a handful of pictures at
/// once, keeps them, and puts each one up when its moment comes, minutes
/// apart. Nothing runs in between. So a piece here is one that *changes*
/// rather than one that moves: each picture is drawn on its own, from the
/// moment it stands for, and the viewer sees the difference between two of
/// them rather than the motion between them.
///
/// ```swift
/// // Four pictures, a quarter of an hour apart: the next hour.
/// override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }
/// ```
///
/// Two things follow from the system owning the clock, and both are worth
/// knowing before a piece is written for this surface.
///
/// **The spacing is a wish, not a promise.** The system decides when it comes
/// back for more pictures, and it will not come back every minute for anybody.
/// A quarter of an hour is the shortest spacing worth asking for, and a piece
/// that would look wrong a few minutes late should not be a widget.
///
/// **The whole run is held in memory at once.** Every picture of a pass is
/// drawn before any of them is shown, so `count` is a handful and not a
/// hundred: the surface is a few hundred points across, and an extension the
/// system starts for a moment is given little room to work in.
///
/// See `Docs/Output/Widget.md`.
public struct WidgetTimeline: Sendable, Equatable {

    /// Seconds between one picture and the next.
    public var spacing: Double

    /// How many pictures are drawn in one pass.
    public var count: Int

    /// A quarter of an hour apart, four of them: the next hour, redrawn as the
    /// hour runs out.
    public init(spacing: Double = 15 * 60, count: Int = 4) {
        self.spacing = max(1, spacing)
        self.count = max(1, count)
    }

    /// Minutes between one picture and the next.
    public static func every(minutes: Double, count: Int = 4) -> WidgetTimeline {
        WidgetTimeline(spacing: minutes * 60, count: count)
    }

    /// Hours between one picture and the next.
    public static func every(hours: Double, count: Int = 4) -> WidgetTimeline {
        WidgetTimeline(spacing: hours * 3600, count: count)
    }

    /// How long one pass covers, in seconds: the last picture goes up this far
    /// after the first one did.
    public var span: Double { spacing * Double(count - 1) }

    /// The moment a picture is drawn for, at or before `date`.
    ///
    /// Pictures land on a grid counted from midnight rather than from whenever
    /// the system happened to ask, which is what makes two passes agree: a
    /// quarter-hour piece steps at the quarter hours, and the pass that starts
    /// at twenty past carries on the same grid the one before it was on. The
    /// grid starts over at midnight, so a spacing that does not divide the day
    /// has one short step there.
    public func gridMoment(atOrBefore date: Date,
                           calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(midnight)
        // A moment before midnight (the clock moved back) belongs to the grid
        // of the day it is actually in, so the step is floored rather than
        // truncated.
        let steps = (elapsed / spacing).rounded(.down)
        return midnight.addingTimeInterval(steps * spacing)
    }

    /// Seconds since midnight, which is the clock a widget's sketch runs on.
    public static func timeOfDay(at date: Date, calendar: Calendar = .current) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }

    /// The moments one pass draws for, starting from the grid moment at or
    /// before `date`.
    public func moments(from date: Date, calendar: Calendar = .current) -> [Date] {
        let first = gridMoment(atOrBefore: date, calendar: calendar)
        return (0..<count).map { first.addingTimeInterval(Double($0) * spacing) }
    }
}

/// One picture of a widget's run: what to show, and the moment to show it.
public struct WidgetFrame {
    /// The moment this picture stands for, and the moment it goes up.
    public let date: Date
    /// The picture, drawn at the size that was asked for.
    public let image: CGImage

    public init(date: Date, image: CGImage) {
        self.date = date
        self.image = image
    }
}

extension OllinApp {

    /// Draw one picture per moment of a widget's run.
    ///
    /// Each picture gets a sketch of its own, made fresh and drawn once, so a
    /// moment always draws the same picture whether it was the first of a pass
    /// or the last. That is the whole contract of this surface: the picture is
    /// a function of the moment, and nothing carries from one to the next.
    ///
    /// The clock the sketch sees is **the time of day**: `time` is seconds
    /// since midnight of the moment being drawn, so `time / 3600` is the hour
    /// and a piece reads the same at four in the afternoon today and tomorrow.
    /// An elapsed clock could not do that, because the system throws a pass
    /// away and asks again, and the piece would jump back to zero every time it
    /// did. `deltaTime` is the spacing, which is what really passed between
    /// this picture and the one before it, and `date` is the moment itself for
    /// anything the day of the week or the month decides.
    ///
    /// ```swift
    /// let frames = OllinApp.widgetFrames(size: .square(720)) { Ripple() }
    /// ```
    ///
    /// - Parameters:
    ///   - start: the moment the run is asked for, normally now. The first
    ///     picture is the grid moment at or before it.
    ///   - size: the size to draw at, normally the widget's own size in pixels.
    ///     Left out, the sketch's declared canvas is used.
    ///   - count: how many pictures to draw, overriding what the sketch
    ///     declared. The snapshot the system asks for first is one picture.
    ///   - makeSketch: makes the piece. Called once per picture.
    public static func widgetFrames(from start: Date = Date(),
                                    size: CanvasSize? = nil,
                                    count: Int? = nil,
                                    of makeSketch: () -> Sketch) -> [WidgetFrame] {
        // The declaration is read off a sketch that is never set up or drawn,
        // which costs an initializer and keeps the run's shape in one place:
        // the sketch's own file.
        var timeline = makeSketch().widgetTimeline
        if let count { timeline.count = max(1, count) }

        return autoreleasepool { () -> [WidgetFrame] in
            guard let device = MTLCreateSystemDefaultDevice() else { return [] }
            // One renderer for the whole run, the way a contact sheet reuses
            // one across its tiles: the shader library is compiled once rather
            // than once per picture, which on this surface is most of the cost.
            var renderer: MetalRenderer?
            isRenderingHeadless = true
            defer { isRenderingHeadless = false }

            var frames: [WidgetFrame] = []
            for moment in timeline.moments(from: start) {
                autoreleasepool {
                    let sketch = makeSketch()
                    if renderer == nil {
                        renderer = headlessRenderer(for: sketch, device: device)
                        renderer?.automaticQuality = .detail
                    }
                    guard let renderer else { return }
                    if let image = widgetImage(of: sketch, at: moment,
                                               spacing: timeline.spacing,
                                               size: size ?? sketch.canvasSize,
                                               renderer: renderer) {
                        frames.append(WidgetFrame(date: moment, image: image))
                    }
                }
            }
            return frames
        }
    }

    /// One picture, from one moment. The single draw is the point: there is no
    /// warm-up and no frame before this one, because on this surface there
    /// never is.
    private static func widgetImage(of sketch: Sketch, at moment: Date, spacing: Double,
                                    size: CanvasSize, renderer: MetalRenderer) -> CGImage? {
        sketch.heldDate = moment
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.runSetup()
        sketch.advance(time: WidgetTimeline.timeOfDay(at: moment),
                       deltaTime: spacing,
                       frameRate: 1 / spacing)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        if sketch.drawer.accumulates {
            return renderer.accumulatedImage(of: sketch.drawer, viewport: viewport,
                                             width: size.width, height: size.height)
        }
        return renderer.image(of: sketch.drawer, viewport: viewport,
                              width: size.width, height: size.height)
    }
}

extension OllinApp {

    /// Write a widget's whole run as pictures, one file per moment.
    ///
    /// A surface that changes every quarter of an hour cannot be worked on by
    /// waiting for it, so this is the way to see the run now: the same
    /// pictures the system would put up, in a folder, named by the moment each
    /// one stands for. Behind `--export-widget <dir>`.
    ///
    /// Returns the files written. Throws `ExportError` when the folder cannot
    /// be made or a picture cannot be written; the pictures written before it
    /// stay in the folder.
    @discardableResult
    public static func exportWidget(to directory: String, from start: Date = Date(),
                                    size: CanvasSize? = nil, count: Int? = nil,
                                    of makeSketch: () -> Sketch) throws -> [String] {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw ExportError(.unwritable, path: directory,
                              problem: "the folder could not be made: \(error.localizedDescription)")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        var written: [String] = []
        for frame in widgetFrames(from: start, size: size, count: count, of: makeSketch) {
            let path = folder.appendingPathComponent("widget-\(formatter.string(from: frame.date)).png").path
            guard writePNG(frame.image, to: path, recipe: nil) else {
                throw ExportError(.unwritable, path: path, frame: written.count,
                                  problem: "the picture could not be written")
            }
            written.append(path)
        }
        if let first = written.first {
            let size = "\(written.count) picture\(written.count == 1 ? "" : "s")"
            print("Ollin: exported the widget run → \(folder.path) (\(size), from \(URL(fileURLWithPath: first).lastPathComponent))")
        }
        return written
    }
}
