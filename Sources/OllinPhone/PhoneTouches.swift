import Foundation
import Ollin
import os

/// One finger on the phone's screen.
///
/// `position` runs -1 to 1 across and -1 to 1 up, with the middle at zero, the
/// same reading the wand's thumb carries, so a sketch can use it as a rate in
/// either direction with no remapping. `point(in:)` maps it onto a rectangle on
/// the canvas instead, for a surface you draw.
///
/// `radius` is how wide the contact is, as a fraction of the screen's width.
/// Every iPhone reports it, and it is what tells a fingertip from a flat finger
/// laid down. `force` is how hard the finger presses, `0...1`, and it is `nil`
/// on a screen that cannot tell, which is most iPhones: read it as *nothing
/// reported* rather than as no pressure.
public struct PhoneTouch: Sendable, Equatable {

    /// The finger's own number. It belongs to this finger from the moment it
    /// lands until it leaves, and it is never handed to another one, so a
    /// number you have not seen before is a finger that just landed.
    public let id: Int

    /// Where the finger sits: -1 to 1 across, -1 to 1 up, the middle at zero.
    public let position: Vector2

    /// How hard it presses, `0...1`, or `nil` on a screen that cannot tell.
    public let force: Double?

    /// How wide the contact is, as a fraction of the screen's width.
    public let radius: Double

    /// How long the finger had been down when the phone sent this reading.
    public let age: Double

    /// Stage a touch with no phone attached (the tests and the Guide figure do).
    public init(id: Int, position: Vector2, force: Double? = nil,
                radius: Double = 0, age: Double = 0) {
        self.id = id
        self.position = position
        self.force = force
        self.radius = radius
        self.age = age
    }

    /// Wrap a decoded wire point.
    public init(_ point: PhoneTouchPoint) {
        id = Int(point.id)
        position = Vector2(Double(point.position.x), Double(point.position.y))
        force = point.hasForce ? Double(point.force) : nil
        radius = Double(point.radius)
        age = Double(point.age)
    }

    /// Where this finger lands inside `rect` on the canvas. The screen's middle
    /// is the rectangle's middle, and up on the phone is up on the canvas.
    public func point(in rect: Rectangle) -> Vector2 {
        PhoneTouch.mapped(position, in: rect)
    }

    static func mapped(_ position: Vector2, in rect: Rectangle) -> Vector2 {
        Vector2(rect.x + (position.x + 1) * 0.5 * rect.width,
                rect.y + (1 - (position.y + 1) * 0.5) * rect.height)
    }
}

/// A finger landing on the screen: where it touched down and when, kept so a
/// sketch reading once a frame never misses one.
///
/// A tap is reported the moment the finger lands, not when it leaves, which is
/// what an instrument wants: a pad that answers on release feels broken.
public struct PhoneTap: Sendable, Equatable {

    /// The finger's number, the same one `PhoneTouch.id` carries while it stays
    /// down, so a tap can be followed into the drag it becomes.
    public let id: Int

    /// Where it landed: -1 to 1 across, -1 to 1 up, the middle at zero.
    public let position: Vector2

    /// How hard it landed, `0...1`, or `nil` on a screen that cannot tell.
    public let force: Double?

    /// How wide the contact was as it landed, as a fraction of the screen's width.
    public let radius: Double

    /// When it landed, in seconds on the phone's clock.
    public let time: Double

    /// Stage a tap with no phone attached (the tests and the Guide figure do).
    public init(id: Int, position: Vector2, force: Double? = nil,
                radius: Double = 0, time: Double = 0) {
        self.id = id
        self.position = position
        self.force = force
        self.radius = radius
        self.time = time
    }

    /// Where this tap landed inside `rect` on the canvas, mapped the way
    /// `PhoneTouch.point(in:)` maps a finger.
    public func point(in rect: Rectangle) -> Vector2 {
        PhoneTouch.mapped(position, in: rect)
    }
}

/// The phone's screen as a control surface: every finger on the glass, and every
/// finger that landed since you last looked.
///
/// This is the phone played rather than the phone watching. Tap **Touch** on the
/// capture app and the whole screen becomes the surface, with no camera running
/// at all, which is what keeps the phone cool and its battery alive through a
/// performance.
///
/// The two reads are the pair every input in Ollin has. *Where are the fingers
/// now?* is a state that comes and goes: `down` is the fingers on the glass,
/// `isTouching` whether there are any, `touch(id:)` one you are following.
/// *Did somebody just tap?* happens once: `taps()` drains the landings since
/// the last call, so a tap between two `draw()` calls is still there to find.
///
/// ```swift
/// let device = PhoneDevice()
/// override func setup() { device.start() }
/// override func draw() {
///     for tap in device.touches.taps() { ripples.append(Ripple(at: tap.point(in: bounds))) }
///     for touch in device.touches.down {
///         drawCircle(center: touch.point(in: bounds), radius: 20 + touch.radius * 400)
///     }
/// }
/// ```
///
/// A finger keeps one `id` from landing to leaving, and the phone never hands
/// that number to another finger, so a number the Mac has not seen is a landing.
/// That is the whole of how taps are found, and it is why nothing is missed: the
/// phone sends a message every time the set of fingers changes, and this object
/// reads every one of them, while `draw()` sees only the latest.
///
/// Times run on the phone's clock, in seconds since it booted. Between readings
/// the Mac carries that clock forward with its own, so a fade on `timeSinceTap`
/// runs smoothly rather than stepping once per message.
///
/// A sketch can be developed with no phone attached: `PhoneTouches()` stands
/// alone, and `feel(_:at:)` feeds it what a phone would have sent, which is how
/// the tests and the Guide figure say exactly which fingers were where.
@MainActor
public final class PhoneTouches {

    struct State {
        var down: [PhoneTouch] = []
        var pending: [PhoneTap] = []
        /// The numbers currently on the glass, which is what makes a number the
        /// Mac has not seen a landing.
        var held: Set<Int> = []
        var taps = 0
        var lastTap: Double?
        /// The latest reading's time on the phone's clock, and when it arrived
        /// on the Mac's, so the clock can be carried forward between readings.
        var elapsed: Double = 0
        var arrived: TimeInterval?
        var readings = 0
    }

    nonisolated let state = OSAllocatedUnfairLock(initialState: State())

    /// A surface with nothing on it. The device makes its own; make one here to
    /// develop or test a sketch with no phone attached, feeding it with
    /// `feel(_:at:)`.
    public init() {}

    // MARK: What is down

    /// The fingers on the glass right now, in the order they landed. Empty
    /// before the first reading, and whenever nothing is touching.
    public var down: [PhoneTouch] { state.withLock { $0.down } }

    /// Whether anything is touching the screen right now.
    public var isTouching: Bool { state.withLock { !$0.down.isEmpty } }

    /// One finger by its number, or `nil` once it has left. This is how a drag
    /// is followed: keep the `id` a tap gave you and ask for it each frame.
    public func touch(id: Int) -> PhoneTouch? {
        state.withLock { $0.down.first { $0.id == id } }
    }

    // MARK: What just happened

    /// The fingers that landed since the last call, oldest first. Draining, so
    /// each tap is handed out once: read it in one place per frame.
    public func taps() -> [PhoneTap] {
        state.withLock { state in
            let taps = state.pending
            state.pending.removeAll(keepingCapacity: true)
            return taps
        }
    }

    /// How many fingers have landed since the device started. It only ever
    /// rises, so a sketch that keeps last frame's number sees a tap it was not
    /// looking at without draining anything.
    public var tapCount: Int { state.withLock { $0.taps } }

    /// Seconds since the last finger landed, on the phone's clock carried
    /// forward. Huge if none ever has, so `timeSinceTap < 0.3` reads as a
    /// fading flash.
    public var timeSinceTap: Double {
        let now = Date.timeIntervalSinceReferenceDate
        return state.withLock { state in
            guard let last = state.lastTap else { return .greatestFiniteMagnitude }
            let carried = state.arrived.map { max(0, now - $0) } ?? 0
            return max(0, state.elapsed + carried - last)
        }
    }

    // MARK: Status

    /// Whether the phone is sending touch readings: `true` once the first one
    /// arrives, and it stays true while a hand rests still, since the phone
    /// sends only on a change. It goes false again on `reset()`.
    public var isReporting: Bool { state.withLock { $0.readings > 0 } }

    /// How many readings have arrived since the device started. One reading is
    /// one change in the set of fingers.
    public var readingCount: Int { state.withLock { $0.readings } }

    // MARK: Feeding it

    /// Take one reading, the way the phone sends one: every finger on the glass
    /// at `time` (seconds on the phone's clock). A finger whose `id` was not on
    /// the glass in the previous reading counts as a landing, and becomes a tap.
    ///
    /// The device calls this for every reading off the wire. It is public so a
    /// sketch can be developed against staged fingers with no phone attached,
    /// and so a test or a figure can say exactly what was touched and when.
    nonisolated public func feel(_ touches: [PhoneTouch], at time: Double) {
        let now = Date.timeIntervalSinceReferenceDate
        state.withLock { state in
            var held: Set<Int> = []
            for touch in touches {
                held.insert(touch.id)
                guard !state.held.contains(touch.id) else { continue }
                state.pending.append(PhoneTap(id: touch.id, position: touch.position,
                                              force: touch.force, radius: touch.radius,
                                              time: time))
                state.taps += 1
                state.lastTap = time
            }
            state.held = held
            state.down = touches
            state.elapsed = max(state.elapsed, time)
            state.arrived = now
            state.readings += 1
            if state.pending.count > 256 { state.pending.removeFirst(state.pending.count - 256) }
        }
    }

    /// Take one reading off the wire.
    nonisolated func feel(_ sample: PhoneTouchSample) {
        feel(sample.touches.map(PhoneTouch.init), at: sample.timestamp)
    }

    /// Every finger is gone, because the cable went rather than because a hand
    /// left. The device calls this when the connection drops: the phone sends
    /// only on a change, so without it a finger that was down when the cable
    /// came out would stay down for the rest of the run, which on an instrument
    /// is a note that never ends. The counts and the clock are kept, since
    /// nothing about them stopped being true.
    nonisolated func releaseAll() {
        state.withLock { state in
            guard !state.down.isEmpty else { return }
            state.down = []
            state.held = []
        }
    }

    /// Forget everything: the fingers, the pending taps, the count, and the
    /// clock. The phone keeps sending, so the next reading starts it again.
    public func reset() {
        state.withLock { $0 = State() }
    }
}
