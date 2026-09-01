// Room: several machines drawing one piece.

import Foundation
import Ollin

/// A room several machines join to draw one piece together, with no server and
/// no address to type: they find each other on the local network by the room's
/// name alone.
///
/// ```swift
/// import OllinRoom
///
/// let room = Room(named: "wall")
///
/// override func setup() {
///     extend(room)
/// }
///
/// override func draw() {
///     background(.white)
///     // Every machine reads the same clock, so the ring turns in step.
///     let angle = room.time
///     drawCircle(540 + cos(angle) * 300, 540 + sin(angle) * 300, 60)
/// }
/// ```
///
/// Three things travel between the machines:
///
/// - **Values a sketch sends.** `room.send("beat", 1.0)` on one machine, and
///   `room.number("beat")` reads it on the others. Read the latest value each
///   frame, or drain everything that arrived with `room.messages()`.
/// - **Knobs.** `room.share("speed")` makes this machine's `@Param` drive the
///   same knob on every other machine, so one person tunes the whole room.
/// - **The time.** `room.time` is the same number on every machine, within a
///   millisecond or two on a quiet network, so an animation runs in step
///   instead of each machine keeping its own clock from its own start.
///
/// For a piece split across screens, each machine reads `room.seat` and
/// `room.seatCount` and draws its own slice of one larger picture. Ask for a
/// fixed seat (`Room(named: "wall", seat: 1)`) when the machines stand in a
/// known order, or let the room hand seats out by name.
///
/// The room name is the only thing needed to join, so anyone on the same network
/// who knows it can. Pass a `passcode` where that matters. The system asks for
/// permission to use the local network the first time a sketch opens a room.
@MainActor
public final class Room: SketchExtension {

    private let session: RoomSession
    private let declaredSeat: Int?

    private var handles: [String: ParamHandle] = [:]
    private var sharedNames: Set<String> = []
    private var sharesEverything = false
    private var lastShared: [String: ParamStored] = [:]
    /// When each shared knob was last turned, and by whom, in room time. What
    /// settles an argument when two people turn one knob at once.
    private var lastTurn: [String: (at: Double, by: String)] = [:]
    /// How many machines had joined when the shared knobs last went out.
    private var lastArrival = 0
    private var sketchName = ""

    // MARK: Making one

    /// Joins the room of this name on the local network.
    ///
    /// - Parameters:
    ///   - name: what the room is called. Every machine that passes the same name
    ///     joins the same room.
    ///   - displayName: the name this machine goes by, which otherwise is the
    ///     computer's name plus a few characters that keep two sketches on one
    ///     Mac apart.
    ///   - seat: the slice of the piece this machine draws, when the machines
    ///     stand in a known order. Leave it out and the room hands seats out by
    ///     name.
    ///   - passcode: a word every machine in the room must know. It never travels
    ///     in the clear.
    public convenience init(named name: String, as displayName: String? = nil, seat: Int? = nil, passcode: String? = nil) {
        self.init(
            transport: LocalNetworkTransport(room: name, as: displayName, passcode: passcode),
            seat: seat
        )
    }

    /// Joins a room over a transport of your own. The local network is the one
    /// that ships; this is the way to run two rooms inside one process, which is
    /// what the tests and the loopback example do.
    public init(transport: RoomTransport, seat: Int? = nil) {
        session = RoomSession(transport: transport)
        declaredSeat = seat
    }

    // MARK: Opening and closing

    /// Opens the room. `extend(room)` does this, so a sketch rarely calls it.
    ///
    /// A headless export never opens the local network. There is nobody to meet
    /// while a file is being written, `room.time` is then the sketch's own
    /// clock, and an export asks for no permission it does not need. A room over
    /// a transport of your own still opens, since that transport is the sketch's
    /// business rather than the network's.
    public func start() {
        if OllinApp.isRenderingHeadless, session.transport is LocalNetworkTransport { return }
        session.start(seat: declaredSeat, sketchName: sketchName)
    }

    /// Leaves the room and drops every connection.
    public func stop() {
        session.stop()
    }

    /// Whether the room is open.
    public var isRunning: Bool { session.isRunning }

    /// What went wrong, when something did. `nil` when all is well.
    ///
    /// The most likely one on a Mac is permission: the first time a sketch opens
    /// a room the system asks to use the local network, and a sketch run from a
    /// terminal inherits the terminal's answer.
    public var problem: String? { session.problem }

    // MARK: Who is here

    /// The name this machine goes by.
    public var name: String { session.peerName }

    /// The other machines in the room, by name, in the order every machine agrees
    /// on.
    public var peers: [String] { session.peers }

    /// Every machine in the room, this one included.
    public var everyone: [String] { session.everyone }

    /// Whether this machine is the only one here.
    public var isAlone: Bool { session.peers.isEmpty }

    /// The name of the sketch another machine is running, when it has said.
    public func sketchName(of peer: String) -> String? {
        let name = session.members[peer]?.sketchName
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// The machines that joined since the last call.
    public func arrivals() -> [String] { session.drainJoined() }

    /// The machines that left since the last call.
    public func departures() -> [String] { session.drainLeft() }

    // MARK: The piece, split across machines

    /// The slice of the piece this machine draws, counting from zero.
    public var seat: Int { session.seat }

    /// How many slices the piece has.
    public var seatCount: Int { session.seatCount }

    // MARK: The time everyone agrees on

    /// The time the whole room agrees on, in seconds.
    ///
    /// One machine owns the clock (the one whose name sorts first, so every
    /// machine picks the same one) and the others ask it what time it is a few
    /// times a second. Use this instead of the sketch's own `time` for anything
    /// that must run in step.
    public var time: Double { session.time }

    /// Whether this machine owns the clock the room runs on.
    public var ownsClock: Bool { session.ownsClock }

    /// How far `time` can be from the owner's clock, in seconds, or `nil` before
    /// the first answer arrives.
    public var clockError: Double? { session.clockError }

    // MARK: Sending

    /// Sends a number to every machine in the room.
    ///
    /// Pass `reliable: false` for a value you send every frame, where the next
    /// one matters more than the one that went missing.
    public func send(_ key: String, _ value: Double, reliable: Bool = true) {
        session.send(key, .number(value), reliable: reliable, to: [])
    }

    /// Sends a whole number to every machine in the room.
    public func send(_ key: String, _ value: Int, reliable: Bool = true) {
        session.send(key, .int(value), reliable: reliable, to: [])
    }

    /// Sends text to every machine in the room.
    public func send(_ key: String, _ value: String, reliable: Bool = true) {
        session.send(key, .text(value), reliable: reliable, to: [])
    }

    /// Sends a flag to every machine in the room.
    public func send(_ key: String, _ value: Bool, reliable: Bool = true) {
        session.send(key, .bool(value), reliable: reliable, to: [])
    }

    /// Sends a point to every machine in the room.
    public func send(_ key: String, _ value: Vector2, reliable: Bool = true) {
        session.send(key, .point(value), reliable: reliable, to: [])
    }

    /// Sends a color to every machine in the room.
    public func send(_ key: String, _ value: Color, reliable: Bool = true) {
        session.send(key, .color(value), reliable: reliable, to: [])
    }

    /// Sends raw bytes to every machine in the room, for anything the other
    /// kinds do not cover.
    public func send(_ key: String, _ value: Data, reliable: Bool = true) {
        session.send(key, .bytes(value), reliable: reliable, to: [])
    }

    // MARK: Reading the latest value

    /// The most recent message under this key, or `nil` when none has arrived.
    public func message(_ key: String) -> RoomMessage? { session.message(key) }

    /// The latest number under this key.
    public func number(_ key: String) -> Double? { session.message(key)?.number }
    /// The latest number under this key, or `fallback` when none has arrived.
    public func number(_ key: String, default fallback: Double) -> Double { number(key) ?? fallback }

    /// The latest whole number under this key.
    public func int(_ key: String) -> Int? { session.message(key)?.int }
    /// The latest whole number under this key, or `fallback` when none has arrived.
    public func int(_ key: String, default fallback: Int) -> Int { int(key) ?? fallback }

    /// The latest text under this key.
    public func text(_ key: String) -> String? { session.message(key)?.text }
    /// The latest text under this key, or `fallback` when none has arrived.
    public func text(_ key: String, default fallback: String) -> String { text(key) ?? fallback }

    /// The latest flag under this key.
    public func bool(_ key: String) -> Bool? { session.message(key)?.bool }
    /// The latest flag under this key, or `fallback` when none has arrived.
    public func bool(_ key: String, default fallback: Bool) -> Bool { bool(key) ?? fallback }

    /// The latest point under this key.
    public func point(_ key: String) -> Vector2? { session.message(key)?.point }
    /// The latest point under this key, or `fallback` when none has arrived.
    public func point(_ key: String, default fallback: Vector2) -> Vector2 { point(key) ?? fallback }

    /// The latest color under this key.
    public func color(_ key: String) -> Color? { session.message(key)?.color }
    /// The latest color under this key, or `fallback` when none has arrived.
    public func color(_ key: String, default fallback: Color) -> Color { color(key) ?? fallback }

    /// The latest raw bytes under this key.
    public func bytes(_ key: String) -> Data? { session.message(key)?.bytes }

    // MARK: Reading everything that arrived

    /// Everything that arrived since the last call, oldest first. Call it once a
    /// frame for events (a note, a trigger, a click) where every one counts.
    public func messages() -> [RoomMessage] { session.messages() }

    // MARK: Knobs

    /// Drives a `@Param` from a key another machine sends, the same way an
    /// external fader does.
    public func bind(_ key: String, to param: Param<Double>, from input: ClosedRange<Double> = 0...1) {
        session.bind(key, to: param, from: input)
    }

    /// Removes a binding.
    public func unbind(_ key: String) {
        session.unbind(key)
    }

    /// Makes these knobs travel: while the sketch runs, their values go out to
    /// every machine in the room, and a machine that has a knob of the same name
    /// follows along. Name them by their property names.
    ///
    /// ```swift
    /// override func setup() {
    ///     extend(room)
    ///     room.share("speed", "hue")
    /// }
    /// ```
    ///
    /// A machine that calls this both sends and follows, so the knob can be
    /// turned wherever the person happens to be standing. When two people turn
    /// the same knob at the same moment, the later turn wins everywhere, by the
    /// room's own clock.
    public func share(_ names: String...) {
        sharedNames.formUnion(names)
    }

    /// Makes every `@Param` on the sketch travel, as `share(_:)` does for named
    /// ones.
    public func shareAll() {
        sharesEverything = true
    }

    // MARK: Extension hooks

    public func setup(_ sketch: Sketch) {
        discover(sketch)
        start()
    }

    /// The half of `setup` that touches no network: knob discovery. Split out so
    /// the tests drive the knob path with no transport running.
    func discover(_ sketch: Sketch) {
        sketchName = String(describing: type(of: sketch))
        handles = [:]
        for handle in sketch.parameters() { handles[handle.name] = handle }
    }

    public func beforeDraw(_ sketch: Sketch) {
        applyIncomingKnobs()
        pushSharedKnobs()
    }

    /// Applies knobs that arrived from another machine. They land here, between
    /// frames on the main thread, which is where the inspector's own edits land,
    /// rather than on the network thread in the middle of a frame.
    func applyIncomingKnobs() {
        for knob in session.drainIncomingKnobs() {
            guard let handle = handles[knob.name] else { continue }
            guard isNewer(knob) else { continue }
            handle.param.restore(knob.stored)
            // Remembered as if this machine had turned it, so a machine that both
            // shares and follows a knob does not send back what it just took.
            lastShared[knob.name] = knob.stored
            lastTurn[knob.name] = (knob.turnedAt, knob.sender)
        }
    }

    /// Whether an arriving knob is later than the turn this machine already
    /// knows about. Two turns at the very same moment are settled by the
    /// machines' names, so every machine in the room picks the same winner.
    private func isNewer(_ knob: IncomingKnob) -> Bool {
        guard let known = lastTurn[knob.name] else { return true }
        if knob.turnedAt != known.at { return knob.turnedAt > known.at }
        return knob.sender > known.by
    }

    /// Sends the shared knobs whose values changed since the last frame.
    ///
    /// A machine that just joined knows none of them, so an arrival forgets what
    /// was last sent and every shared knob goes out again. Without that, a
    /// machine switched on later shows its own defaults until somebody happens
    /// to touch a knob.
    func pushSharedKnobs() {
        guard sharesEverything || !sharedNames.isEmpty else { return }
        if session.everJoined != lastArrival {
            lastArrival = session.everJoined
            lastShared.removeAll(keepingCapacity: true)
        }
        for (name, handle) in handles {
            guard sharesEverything || sharedNames.contains(name) else { continue }
            let stored = handle.param.stored
            guard lastShared[name] != stored else { continue }
            let turnedAt = session.time
            lastShared[name] = stored
            lastTurn[name] = (turnedAt, self.name)
            session.send(knob: name, stored, turnedAt: turnedAt)
        }
    }
}
