import Foundation
import Ollin
import os

// TUIO is the protocol tangible-surface trackers speak: a table watching printed
// markers, a touch wall, a phone app sending finger positions. It rides OSC, so
// it lives here beside the receiver it decodes from, and a sketch reaches it with
// the same `import OllinOSC`.
//
// The wire shape is three messages per surface frame, all at one address:
//
//   /tuio/2Dcur set 12 0.5 0.25 0.0 0.1 0.02   one item, this is its state now
//   /tuio/2Dcur alive 12 13                    everything on the surface, by id
//   /tuio/2Dcur fseq 4218                      the frame those two belong to
//
// The set messages are only sent for what moved, so the alive list is what says
// a touch has left, and the frame number is what says a datagram overtook
// another on the way. Written from the TUIO 1.1 specification.

// MARK: - What the surface reports

/// One touch on a TUIO surface: a fingertip on a table, a contact on a touch
/// wall, a pointer from a phone app.
///
/// Positions are `0...1` across the surface with the origin at the top left,
/// which is the canvas's own direction, so `position(in: bounds)` lands the
/// touch where it belongs with nothing to flip.
public struct TUIOCursor: Sendable, Equatable {
    /// The session id the tracker gave this touch. It holds from the moment the
    /// touch appears until it leaves, so a sketch can follow one finger.
    public let id: Int
    /// Where the touch sits, `0...1` from the top-left corner of the surface.
    public let point: Vector2
    /// How fast it is moving, in surface widths per second.
    public let velocity: Vector2
    /// How fast that speed is changing, in surface widths per second squared.
    public let acceleration: Double

    public init(id: Int, point: Vector2, velocity: Vector2 = .zero, acceleration: Double = 0) {
        self.id = id
        self.point = point
        self.velocity = velocity
        self.acceleration = acceleration
    }

    /// Where the touch lands inside a rectangle on the canvas.
    public func position(in frame: Rectangle) -> Vector2 { frame.point(u: point.x, v: point.y) }
}

/// One tagged object on a TUIO surface: a printed marker on a table, read by
/// the tracker as a number, a place, and a turn.
public struct TUIOObject: Sendable, Equatable {
    /// The session id, which holds while this piece stays on the surface.
    public let id: Int
    /// The number printed on the marker. Two pieces carrying the same symbol can
    /// be on the surface at once, each with its own `id`.
    public let symbol: Int
    /// Where the piece sits, `0...1` from the top-left corner of the surface.
    public let point: Vector2
    /// Which way it is turned, in radians, clockwise like `rotate(_:)`.
    public let angle: Double
    /// How fast it is moving, in surface widths per second.
    public let velocity: Vector2
    /// How fast it is turning, in radians per second.
    public let angularVelocity: Double
    /// How fast the speed is changing, in surface widths per second squared.
    public let acceleration: Double
    /// How fast the turn is changing, in radians per second squared.
    public let angularAcceleration: Double

    public init(id: Int, symbol: Int, point: Vector2, angle: Double = 0,
                velocity: Vector2 = .zero, angularVelocity: Double = 0,
                acceleration: Double = 0, angularAcceleration: Double = 0) {
        self.id = id
        self.symbol = symbol
        self.point = point
        self.angle = angle
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.acceleration = acceleration
        self.angularAcceleration = angularAcceleration
    }

    /// Where the piece lands inside a rectangle on the canvas.
    public func position(in frame: Rectangle) -> Vector2 { frame.point(u: point.x, v: point.y) }
}

/// One untagged shape on a TUIO surface: a hand, a sleeve, a cup, anything the
/// tracker found but cannot name. It carries a size and an area where a cursor
/// carries only a point.
public struct TUIOBlob: Sendable, Equatable {
    /// The session id, which holds while the shape stays on the surface.
    public let id: Int
    /// Where its middle sits, `0...1` from the top-left corner of the surface.
    public let point: Vector2
    /// Which way it lies, in radians, clockwise like `rotate(_:)`.
    public let angle: Double
    /// Its width and height as shares of the surface, `0...1`.
    public let size: Vector2
    /// The share of the surface it covers, `0...1`.
    public let area: Double
    /// How fast it is moving, in surface widths per second.
    public let velocity: Vector2
    /// How fast it is turning, in radians per second.
    public let angularVelocity: Double
    /// How fast the speed is changing, in surface widths per second squared.
    public let acceleration: Double
    /// How fast the turn is changing, in radians per second squared.
    public let angularAcceleration: Double

    public init(id: Int, point: Vector2, angle: Double = 0, size: Vector2 = .zero,
                area: Double = 0, velocity: Vector2 = .zero, angularVelocity: Double = 0,
                acceleration: Double = 0, angularAcceleration: Double = 0) {
        self.id = id
        self.point = point
        self.angle = angle
        self.size = size
        self.area = area
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.acceleration = acceleration
        self.angularAcceleration = angularAcceleration
    }

    /// Where its middle lands inside a rectangle on the canvas.
    public func position(in frame: Rectangle) -> Vector2 { frame.point(u: point.x, v: point.y) }

    /// The shape's own rectangle inside a rectangle on the canvas, before the
    /// turn `angle` gives it.
    public func bounds(in frame: Rectangle) -> Rectangle {
        Rectangle(center: position(in: frame), width: size.x * frame.width, height: size.y * frame.height)
    }
}

// MARK: - The frame the tracker sends

/// What the three profiles have in common, so one state machine serves them all.
protocol TUIOTracked: Sendable, Equatable {
    var id: Int { get }
    init?(setArguments: [OSCArgument])
}

/// Reads a positional argument, treating a missing or non-numeric one as zero:
/// senders differ in how much of the tail they fill in.
private func value(_ arguments: [OSCArgument], _ index: Int) -> Double {
    index < arguments.count ? (arguments[index].number ?? 0) : 0
}

extension TUIOCursor: TUIOTracked {
    // set s x y X Y m
    init?(setArguments a: [OSCArgument]) {
        guard a.count >= 3, let id = a[0].int else { return nil }
        self.init(id: id,
                  point: Vector2(value(a, 1), value(a, 2)),
                  velocity: Vector2(value(a, 3), value(a, 4)),
                  acceleration: value(a, 5))
    }
}

extension TUIOObject: TUIOTracked {
    // set s i x y a X Y A m r
    init?(setArguments a: [OSCArgument]) {
        guard a.count >= 5, let id = a[0].int, let symbol = a[1].int else { return nil }
        self.init(id: id,
                  symbol: symbol,
                  point: Vector2(value(a, 2), value(a, 3)),
                  angle: value(a, 4),
                  velocity: Vector2(value(a, 5), value(a, 6)),
                  angularVelocity: value(a, 7),
                  acceleration: value(a, 8),
                  angularAcceleration: value(a, 9))
    }
}

extension TUIOBlob: TUIOTracked {
    // set s x y a w h f X Y A m r
    init?(setArguments a: [OSCArgument]) {
        guard a.count >= 4, let id = a[0].int else { return nil }
        self.init(id: id,
                  point: Vector2(value(a, 1), value(a, 2)),
                  angle: value(a, 3),
                  size: Vector2(value(a, 4), value(a, 5)),
                  area: value(a, 6),
                  velocity: Vector2(value(a, 7), value(a, 8)),
                  angularVelocity: value(a, 9),
                  acceleration: value(a, 10),
                  angularAcceleration: value(a, 11))
    }
}

/// One profile's running picture of the surface. The sets since the last commit
/// and the alive list are held aside, and the frame number is what commits them,
/// so a sketch never reads half a frame.
struct TUIOProfile<Item: TUIOTracked>: Sendable {

    /// What is on the surface now, ordered by session id so two reads of one
    /// frame draw the same way.
    private(set) var items: [Item] = []
    /// How many frames have been taken since the receiver started.
    private(set) var frames = 0

    private var live: [Int: Item] = [:]
    private var pending: [Int: Item] = [:]
    private var alive: Set<Int>?
    private var lastFrame = -1

    mutating func receive(_ arguments: [OSCArgument]) {
        guard let command = arguments.first?.text else { return }
        switch command {
        case "set":
            // A tracker that leaves the frame number out ends its frame here,
            // where the next one starts.
            if alive != nil { commit(frame: nil) }
            if let item = Item(setArguments: Array(arguments.dropFirst())) { pending[item.id] = item }
        case "alive":
            if alive != nil { commit(frame: nil) }
            alive = Set(arguments.dropFirst().compactMap(\.int))
        case "fseq":
            commit(frame: arguments.dropFirst().first?.int ?? -1)
        default:
            break   // "source" is read by the receiver, and the rest is not ours
        }
    }

    private mutating func commit(frame: Int?) {
        if let frame, frame >= 0 {
            // A datagram that overtook another carries an older frame number, and
            // taking it would drag a touch back to where it was. A number far
            // below the last one is a tracker that started over, so that one is
            // taken.
            if lastFrame >= 0, frame < lastFrame, lastFrame - frame < 1000 {
                pending.removeAll()
                alive = nil
                return
            }
            lastFrame = frame
        }
        if let alive {
            live = live.filter { alive.contains($0.key) }
            for (id, item) in pending where alive.contains(id) { live[id] = item }
        } else {
            for (id, item) in pending { live[id] = item }
        }
        pending.removeAll()
        alive = nil
        frames += 1
        items = live.values.sorted { $0.id < $1.id }
    }
}

// MARK: - The receiver

/// Reads a tangible surface: touches, tagged pieces, and shapes arriving from a
/// TUIO tracker over the network. Make one in `setup()`, `start()` it, then read
/// it in `draw()` the way you read the mouse.
///
/// ```swift
/// let surface = TUIOReceiver()          // the port trackers use unless told otherwise
///
/// override func setup() { try? surface.start() }
///
/// override func draw() {
///     background(.white)
///     for touch in surface.cursors {
///         drawCircle(center: touch.position(in: bounds), radius: 40)
///     }
///     for piece in surface.objects {
///         withState {
///             translate(piece.position(in: bounds))
///             rotate(piece.angle)
///             drawRect(center: .zero, width: 120, height: 120)
///         }
///     }
/// }
/// ```
///
/// A tracker sends the whole surface several times a second, so the three lists
/// are what is there right now: an id that stops appearing has left. Ids hold
/// while a touch lasts, which is how a sketch keeps a stroke or a color with one
/// finger.
///
/// The receiver opens its own socket. To share one with the OSC traffic a sketch
/// already reads, leave it unstarted and hand it the messages instead:
///
/// ```swift
/// for message in osc.messages() { surface.receive(message) }
/// ```
///
/// Datagrams arrive on a background queue and the sketch reads on the main
/// thread; the surface is held behind a lock, which is what makes that safe.
public final class TUIOReceiver: @unchecked Sendable {

    /// The port trackers send to unless they were told otherwise.
    public static let defaultPort = 3333

    private struct Surface: Sendable {
        var cursors = TUIOProfile<TUIOCursor>()
        var objects = TUIOProfile<TUIOObject>()
        var blobs = TUIOProfile<TUIOBlob>()
        var source: String?
    }
    private let surface = OSAllocatedUnfairLock(initialState: Surface())
    private let osc: OSCReceiver

    /// Creates a receiver bound to `port`. Pass `0` to let the system assign a
    /// free one (read it back from `boundPort` after `start()`).
    public init(port: Int = TUIOReceiver.defaultPort) {
        osc = OSCReceiver(port: port)
        osc.observe { [weak self] message in self?.receive(message) }
    }

    /// Begins listening. Throws if the port is invalid or the socket can't open.
    public func start() throws { try osc.start() }

    /// Stops listening. Safe to call when not running.
    public func stop() { osc.stop() }

    /// Whether the socket is open.
    public var isRunning: Bool { osc.isRunning }

    /// The port actually in use once the socket is ready, or `nil` before then.
    public var boundPort: Int? { osc.boundPort }

    // MARK: Reading the surface

    /// The touches on the surface right now, by session id.
    public var cursors: [TUIOCursor] { surface.withLock { $0.cursors.items } }

    /// The tagged pieces on the surface right now, by session id.
    public var objects: [TUIOObject] { surface.withLock { $0.objects.items } }

    /// The untagged shapes on the surface right now, by session id.
    public var blobs: [TUIOBlob] { surface.withLock { $0.blobs.items } }

    /// How many frames have arrived, counted across the three profiles (a tracker
    /// that reports touches and markers sends a frame of each). A tracker with
    /// nothing on it still sends a frame every tick, so this is what says a tracker
    /// is there at all, where an empty `cursors` only says nobody is touching it.
    public var framesReceived: Int {
        surface.withLock { $0.cursors.frames + $0.objects.frames + $0.blobs.frames }
    }

    /// What the tracker calls itself, once it has said so. Trackers that never
    /// send their name leave this `nil`.
    public var sourceName: String? { surface.withLock { $0.source } }

    // MARK: Taking messages

    /// Applies one OSC message. Anything that isn't TUIO is ignored, so a sketch
    /// can pour its whole inbox in.
    public func receive(_ message: OSCMessage) {
        guard message.address.hasPrefix("/tuio/") else { return }
        let profile = String(message.address.dropFirst(6))
        if message.arguments.first?.text == "source" {
            let name = message.arguments.dropFirst().first?.text
            surface.withLock { $0.source = name }
            return
        }
        surface.withLock { surface in
            switch profile {
            case "2Dcur": surface.cursors.receive(message.arguments)
            case "2Dobj": surface.objects.receive(message.arguments)
            case "2Dblb": surface.blobs.receive(message.arguments)
            default: break   // the 2.5D, 3D, and TUIO 2.0 profiles are not read
            }
        }
    }

    /// Applies a whole packet, message or bundle, in the order it was sent.
    public func receive(_ packet: OSCPacket) {
        switch packet {
        case .message(let message): receive(message)
        case .bundle(let bundle): bundle.elements.forEach(receive)
        }
    }

    deinit { stop() }
}
