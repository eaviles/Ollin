import Foundation
import os
import Ollin

/// A laser projector a sketch draws to: hand it a frame of line work each
/// `draw()`, and it optimizes, guards, and streams it.
///
/// ```swift
/// let laser = LaserProjector(etherDream: "192.168.1.50")
///
/// override func setup() {
///     laser.connect()
///     laser.arm()                      // nothing goes out before this
/// }
///
/// override func draw() {
///     background(.black)
///     var frame = LaserFrame(canvas: bounds)
///     frame.add(ring, color: .green)
///     laser.send(frame)
///     drawLaserPreview(laser.stream)   // what the beam will trace
/// }
/// ```
///
/// A projector with nothing to connect to is still useful: it optimizes and
/// keeps the stream, so a sketch can be written, previewed, and measured with
/// no hardware in the room, then plugged in unchanged.
///
/// **It will not emit until it is armed.** That is the one rule the framework
/// keeps for you rather than trusting a sketch with. Arming is a call a person
/// has to write, and `disarm()` blanks the beam without dropping the
/// connection, so a rig stays live between cues.
public final class LaserProjector: @unchecked Sendable {

    /// How line work is turned into points. Change it whenever; the next frame
    /// sent uses the new settings.
    public var optimizer = LaserOptimizer()

    /// The rules every stream passes through on its way out.
    public var safety = LaserSafety()

    private let lock = OSAllocatedUnfairLock(initialState: Inner())
    private struct Inner: Sendable {
        var armed = false
        var stream: LaserStream?
        var dac: EtherDreamDAC?
    }

    /// The output, if there is one. Held behind the lock because a sketch may
    /// point the projector somewhere else while the wire is busy.
    private var dac: EtherDreamDAC? {
        get { lock.withLock { $0.dac } }
        set { lock.withLock { $0.dac = newValue } }
    }

    /// A projector with no output: optimizes and previews only.
    public init() {}

    /// A projector that streams to a DAC at a known address. Call `connect()`
    /// to open the connection.
    public convenience init(etherDream host: String, port: Int = EtherDreamWire.controlPort) {
        self.init()
        dac = EtherDreamDAC(host: host, port: port)
    }

    /// A projector that streams to a DAC that announced itself.
    public convenience init(device: EtherDreamDevice) {
        self.init()
        dac = EtherDreamDAC(device: device)
    }

    // MARK: The output

    /// Open the connection to the DAC, if there is one.
    public func connect() {
        guard let dac else { return }
        dac.pointsPerSecond = optimizer.pointsPerSecond
        dac.stallTimeout = safety.stallTimeout
        dac.connect()
    }

    /// Point this projector at a DAC and open the connection.
    public func connect(to device: EtherDreamDevice) {
        dac?.disconnect()
        dac = EtherDreamDAC(device: device)
        connect()
    }

    /// Point this projector at an address and open the connection.
    public func connect(etherDream host: String, port: Int = EtherDreamWire.controlPort) {
        dac?.disconnect()
        dac = EtherDreamDAC(host: host, port: port)
        connect()
    }

    /// Blank the beam and close the connection.
    public func disconnect() {
        disarm()
        dac?.disconnect()
    }

    /// Whether the DAC is connected and taking points.
    public var isPlaying: Bool { dac?.isPlaying ?? false }

    /// What the DAC last said about itself.
    public var status: EtherDreamStatus? { dac?.status }

    /// What went wrong on the wire, if anything has.
    public var lastError: String? { dac?.lastError }

    // MARK: The gate

    /// Whether the beam may light. False until `arm()` is called.
    public var isArmed: Bool { lock.withLock { $0.armed } }

    /// Allow the beam to light. Write this deliberately: it is the moment the
    /// sketch stops being a picture on a screen.
    public func arm() {
        lock.withLock { $0.armed = true }
    }

    /// Blank the beam, keeping the connection and the stream. The projector
    /// goes on playing a dark hold, so the mirrors stay parked and the rig
    /// stays live.
    public func disarm() {
        lock.withLock { $0.armed = false }
        dac?.play(LaserSafety.blankHold())
    }

    // MARK: Sending

    /// Optimize a frame, guard it, and put it on the wire. Call it once per
    /// `draw()`.
    @discardableResult
    public func send(_ frame: LaserFrame) -> LaserStream {
        let guarded = safety.guarded(optimizer.stream(frame))
        lock.withLock { $0.stream = guarded }
        if let dac {
            dac.stallTimeout = safety.stallTimeout
            dac.setPointRate(optimizer.pointsPerSecond)
            dac.play(isArmed ? guarded.points : LaserSafety.blankHold())
        }
        return guarded
    }

    /// The last stream sent, ready to preview or measure. `nil` before the
    /// first frame.
    public var stream: LaserStream? { lock.withLock { $0.stream } }
}

// MARK: - Seeing it without a laser

public extension Sketch {

    /// Draw a point stream the way the beam will trace it: lit segments in
    /// their own colors, and the dark travel between shapes as faint lines.
    ///
    /// This is the laser's preview, and it shows things the drawn picture
    /// cannot. Where the points bunch up, the line is bright and slow; where
    /// they spread, it is faint. The travel lines are time spent drawing
    /// nothing. Turn on `showsPoints` to see the beam's own footsteps.
    ///
    /// ```swift
    /// drawLaserPreview(laser.stream, showsPoints: true)
    /// ```
    func drawLaserPreview(_ stream: LaserStream?, showsTravel: Bool = true,
                          showsPoints: Bool = false, pointRadius: Double = 2.5) {
        guard let stream, stream.points.count > 1 else { return }
        let toCanvas = ProjectorSpace.inverse(to: stream.canvas)
        withState {
            noFill()
            strokeWeight(2)
            for i in 1..<stream.points.count {
                let a = stream.points[i - 1], b = stream.points[i]
                let from = toCanvas(a.position), to = toCanvas(b.position)
                if a.isBlanked || b.isBlanked {
                    guard showsTravel else { continue }
                    withState {
                        strokeWeight(1)
                        stroke(Color(white: 0.35, alpha: 0.5))
                        drawLine(from, to)
                    }
                } else {
                    stroke(b.color)
                    drawLine(from, to)
                }
            }
            if showsPoints {
                noStroke()
                for point in stream.points {
                    fill(point.isBlanked ? Color(white: 0.4, alpha: 0.6) : point.color)
                    drawCircle(center: toCanvas(point.position), radius: pointRadius)
                }
            }
        }
    }
}
