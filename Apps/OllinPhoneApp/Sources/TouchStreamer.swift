import Foundation
import SwiftUI
import UIKit
import simd

/// The phone's screen as a control surface: every finger on the glass, streamed
/// each time the set of them changes.
///
/// This is the second streamer that reports the person rather than the room, and
/// the first that runs no sensor at all: the screen is the sensor. So **Touch**
/// mode starts no camera session, which is what keeps the phone cool and its
/// battery alive through a long set.
///
/// A finger keeps one number from landing to leaving, and a number is never
/// handed to another finger, so the Mac reads a number it has not seen as a
/// landing and needs no press flag on the wire. UIKit hands back the same
/// `UITouch` object for the life of a touch, which is what those numbers are
/// keyed on; a touch missing from the live set has left, and its number retires
/// with it.
///
/// UIKit delivers touches on the main thread, so `onTouches` fires on main.
@MainActor
@Observable
final class TouchStreamer {

    /// Fired (on the main thread) each time the set of fingers changes.
    @ObservationIgnored var onTouches: ((PhoneTouchSample) -> Void)?

    /// Where the fingers sit, in the pad's own -1…1 coordinates, for the marks
    /// the screen draws under them.
    private(set) var marks: [SIMD2<Float>] = []

    /// The live fingers, in landing order: the UIKit object, our own number for
    /// it, and when it landed.
    @ObservationIgnored private var live: [(touch: UITouch, id: UInt32, born: TimeInterval)] = []
    @ObservationIgnored private var nextID: UInt32 = 1

    /// Whether the pad is taking touches. A mode switch away turns it off and
    /// sends one last empty reading, so the Mac never holds a finger that left.
    @ObservationIgnored private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        live.removeAll()
        marks = []
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        live.removeAll()
        marks = []
        onTouches?(PhoneTouchSample(timestamp: ProcessInfo.processInfo.systemUptime, touches: []))
    }

    /// Take the fingers currently on the glass, straight from a UIKit event.
    /// The whole live set arrives every time, so this reconciles rather than
    /// tracking each phase: a touch not seen before has landed, and one that is
    /// gone from the set has left.
    func report(_ touches: [UITouch], in size: CGSize, at time: TimeInterval) {
        guard isRunning, size.width > 0, size.height > 0 else { return }

        let present = Set(touches.map(ObjectIdentifier.init))
        live.removeAll { !present.contains(ObjectIdentifier($0.touch)) }
        let known = Set(live.map { ObjectIdentifier($0.touch) })
        for touch in touches where !known.contains(ObjectIdentifier(touch)) {
            live.append((touch, nextID, time))
            nextID &+= 1
        }
        // Landing order is number order, since the numbers only rise.
        live.sort { $0.id < $1.id }

        var points: [PhoneTouchPoint] = []
        points.reserveCapacity(live.count)
        for entry in live {
            let location = entry.touch.location(in: entry.touch.view)
            let position = Self.padPoint(location, in: size)
            // A screen that cannot weigh a press reports a maximum of zero, so
            // the Mac is told nothing rather than told zero.
            let maximum = Float(entry.touch.maximumPossibleForce)
            let hasForce = maximum > 0
            points.append(PhoneTouchPoint(
                id: entry.id,
                position: position,
                hasForce: hasForce,
                force: hasForce ? min(max(Float(entry.touch.force) / maximum, 0), 1) : 0,
                radius: Float(entry.touch.majorRadius / size.width),
                age: Float(max(0, time - entry.born))))
        }
        marks = points.map(\.position)
        onTouches?(PhoneTouchSample(timestamp: time, touches: points))
    }

    /// Where a touch sits on the pad: -1 to 1 across, -1 to 1 up, the middle at
    /// zero. The screen measures down and the wire carries up, so the y is
    /// turned over here, the way the wand's own pad turns it.
    static func padPoint(_ location: CGPoint, in size: CGSize) -> SIMD2<Float> {
        guard size.width > 0, size.height > 0 else { return .zero }
        let x = min(max(Float(location.x / size.width) * 2 - 1, -1), 1)
        let y = min(max(1 - Float(location.y / size.height) * 2, -1), 1)
        return SIMD2<Float>(x, y)
    }
}

/// The pad itself. SwiftUI's own gestures follow one finger, so the surface is a
/// plain UIKit view with multiple touches turned on: it is the only way to see
/// every finger, its width, and its force.
struct TouchPad: UIViewRepresentable {
    let streamer: TouchStreamer

    func makeUIView(context: Context) -> TouchPadView {
        let view = TouchPadView()
        view.streamer = streamer
        return view
    }

    func updateUIView(_ view: TouchPadView, context: Context) {
        view.streamer = streamer
    }
}

/// A view that reports every finger on it. All four phases funnel into one
/// report of the whole live set, because the streamer reconciles rather than
/// following phases, and because the last release must go out as an empty set.
///
/// Open to one subclass: in Sketch mode the pad is the picture itself.
class TouchPadView: UIView {
    weak var streamer: TouchStreamer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }

    private func report(_ event: UIEvent?) {
        let all = event?.allTouches ?? []
        // A touch in its ending phase is still in the event's set, and it is
        // gone as far as the wire is concerned.
        let live = all.filter { $0.phase != .ended && $0.phase != .cancelled }
        streamer?.report(Array(live), in: bounds.size,
                         at: event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
    }
}
