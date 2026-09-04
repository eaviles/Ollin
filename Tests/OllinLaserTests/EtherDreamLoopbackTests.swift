import Foundation
import Network
import os
import Testing
import Ollin
@testable import OllinLaser

/// The whole streaming loop end to end over real TCP on `127.0.0.1`, against a
/// stand-in DAC written here from the same published protocol: the handshake,
/// the points that arrive, the frame repeating without being asked again, the
/// stale-frame blanking, and a clean stop. Each test takes an ephemeral port,
/// so they are independent. No hardware and no GPU.
@Suite
struct EtherDreamLoopbackTests {

    struct Timeout: Error {}

    /// The probe comes before the clock is read: a starved task can wake past
    /// its own deadline having never looked, and giving up then throws over an
    /// answer that is already there.
    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Waits until the DAC has read a run of blanked points longer than any the
    /// lit frame carries, across its seam: the sign that the swap to the dark
    /// frame has gone out and been parsed on the far side. A fixed sleep here
    /// measured the machine rather than the stream. On a loaded runner the
    /// stand-in's receive lagged the wire, and the lit frame's tail was read
    /// after the sleep, as if the dark frame had never arrived.
    func waitForTheDark(at dac: StandInDAC, after lit: [LaserPoint]) async throws {
        var longest = 0, run = 0
        for point in lit + lit {
            run = point.isBlanked ? run + 1 : 0
            longest = max(longest, run)
        }
        let need = longest + 8
        _ = try await waitFor(timeout: 20) { () -> Bool? in
            let points = dac.points
            guard points.count >= need, points.suffix(need).allSatisfy({ $0.isBlanked }) else { return nil }
            return true
        }
    }

    // MARK: The handshake

    @Test func theHandshakeIsPrepareThenStart() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        client.pointsPerSecond = 30_000
        defer { client.disconnect(); dac.stop() }

        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 0 ? true : nil }

        let commands = dac.commands
        #expect(commands.prefix(2) == [0x70, 0x62])       // prepare, then start
        #expect(dac.pointRate == 30_000)
        #expect(client.isPlaying)
        #expect(client.lastError == nil)
    }

    @Test func aRateChangeReachesTheWireWhilePlaying() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        defer { client.disconnect(); dac.stop() }

        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 0 ? true : nil }
        client.pointsPerSecond = 12_000
        _ = try await waitFor { dac.commands.contains(0x74) ? true : nil }
        #expect(dac.pointRate == 12_000)
    }

    // MARK: The points

    @Test func thePointsThatArriveAreThePointsPlayed() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        defer { client.disconnect(); dac.stop() }

        let frame = litSquare()
        client.connect()
        client.play(frame)
        let received = try await waitFor { () -> [LaserPoint]? in
            let points = dac.points
            return points.count >= frame.count ? points : nil
        }
        for (sent, arrived) in zip(frame, received) {
            // The wire keeps 16 bits a coordinate, so a point comes back within
            // one step of where it was put.
            #expect(abs(sent.position.x - arrived.position.x) < 1e-4)
            #expect(abs(sent.position.y - arrived.position.y) < 1e-4)
            #expect(sent.isBlanked == arrived.isBlanked)
            #expect(abs(sent.color.green - arrived.color.green) < 1e-4)
        }
    }

    @Test func theFrameRepeatsWithoutBeingAskedAgain() async throws {
        // This is the whole point of the class: a projector has to be fed
        // whether or not the sketch has anything new to say.
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        client.stallTimeout = 60                          // not what is under test here
        defer { client.disconnect(); dac.stop() }

        let frame = litSquare()
        client.connect()
        client.play(frame)
        _ = try await waitFor { dac.pointsReceived > frame.count * 3 ? true : nil }
        #expect(client.pointsSent > frame.count * 3)
    }

    @Test func aFrameThatStopsArrivingIsBlanked() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        client.stallTimeout = 0.05
        defer { client.disconnect(); dac.stop() }

        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 0 ? true : nil }

        // Say nothing for longer than the timeout, then look at what is still
        // going out: it must all be dark.
        try await Task.sleep(nanoseconds: 200_000_000)
        dac.forgetPoints()
        let recent = try await waitFor { () -> [LaserPoint]? in
            let points = dac.points
            return points.count > 50 ? points : nil
        }
        #expect(recent.allSatisfy { $0.isBlanked })
    }

    @Test func aSecondFrameTakesOverAtTheSeam() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        client.stallTimeout = 60
        defer { client.disconnect(); dac.stop() }

        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 0 ? true : nil }
        // A frame in a color the first one never used, so it is unmistakable.
        client.play([LaserPoint(Vector2(0.9, 0.9), color: Color(red: 0, green: 0, blue: 1))])
        _ = try await waitFor { dac.points.contains { $0.color.blue > 0.9 } ? true : nil }
    }

    @Test func aFrameWithNothingInItLeavesTheBeamDark() async throws {
        // Sending nothing at all would be worse: the DAC would drain and stop
        // the mirrors wherever the last lit point left them.
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        client.stallTimeout = 60
        defer { client.disconnect(); dac.stop() }

        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 0 ? true : nil }
        client.play([])
        try await waitForTheDark(at: dac, after: litSquare())
        dac.forgetPoints()
        let recent = try await waitFor { () -> [LaserPoint]? in
            let points = dac.points
            return points.count > 50 ? points : nil
        }
        #expect(recent.allSatisfy { $0.isBlanked })
    }

    // MARK: Stopping

    @Test func disconnectingStopsThePlayback() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        defer { dac.stop() }

        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 0 ? true : nil }
        client.disconnect()
        _ = try await waitFor { dac.commands.contains(0x73) ? true : nil }
        #expect(!client.isPlaying)
    }

    // MARK: Through the projector

    @Test func aProjectorPutsNothingLitOnTheWireUntilItIsArmed() async throws {
        let dac = try StandInDAC()
        let port = try await waitFor { dac.boundPort }
        let laser = LaserProjector(etherDream: "127.0.0.1", port: port)
        laser.safety.stallTimeout = 60
        defer { laser.disconnect(); dac.stop() }

        laser.connect()
        let stream = laser.send(square())
        // The frame is drawn, measured, and ready to preview.
        #expect(laser.isArmed == false)
        #expect(stream.litCount > 0)
        // None of it reaches the beam.
        let received = try await waitFor { () -> [LaserPoint]? in
            let points = dac.points
            return points.count > 30 ? points : nil
        }
        #expect(received.allSatisfy { $0.isBlanked })

        // Armed, the same frame lights up.
        dac.forgetPoints()
        laser.arm()
        laser.send(square())
        _ = try await waitFor { dac.points.contains { !$0.isBlanked } ? true : nil }

        // And disarming puts it out again without dropping the connection. The
        // dark hold takes over at the end of the frame already going out, so
        // wait until the DAC has read that frame's end before looking.
        laser.disarm()
        try await waitForTheDark(at: dac, after: stream.points)
        dac.forgetPoints()
        let after = try await waitFor { () -> [LaserPoint]? in
            let points = dac.points
            return points.count > 30 ? points : nil
        }
        #expect(after.allSatisfy { $0.isBlanked })
        #expect(laser.isConnected)
    }
}

// MARK: - Fixtures

/// A small lit frame with a distinct color per corner, so the points can be
/// told apart on arrival.
func litSquare() -> [LaserPoint] {
    [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
        .enumerated()
        .map { LaserPoint($0.element, color: Color(red: 1, green: Double($0.offset) / 4, blue: 0)) }
}

// MARK: - A DAC that is not there

/// A stand-in for the hardware: it speaks the published protocol over TCP on
/// the loopback, records what it is told, and drains its buffer at the rate it
/// was started with, so the client's flow control has something real to work
/// against.
final class StandInDAC: @unchecked Sendable {

    private let listener: NWListener
    private let queue = DispatchQueue(label: "ollin.test.standin.dac")
    private let state = OSAllocatedUnfairLock(initialState: Log())

    private struct Log {
        var commands: [UInt8] = []
        var points: [LaserPoint] = []
        var pointsReceived = 0
        var rate = 0
        var buffered = 0
        var lastDrain = Date()
        var inbox = Data()
        var playing = false
    }

    let capacity = 1_799

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    /// The port it ended up on, once it has one. A listener asked for any port
    /// reports zero until it is ready, and zero is not somewhere to connect.
    var boundPort: Int? {
        guard let port = listener.port?.rawValue, port > 0 else { return nil }
        return Int(port)
    }
    var commands: [UInt8] { state.withLock { $0.commands } }
    var points: [LaserPoint] { state.withLock { $0.points } }
    var pointsReceived: Int { state.withLock { $0.pointsReceived } }
    var pointRate: Int { state.withLock { $0.rate } }

    func forgetPoints() { state.withLock { $0.points = [] } }
    func stop() { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] update in
            guard let self, case .ready = update else { return }
            // A DAC greets a new connection with its status, unasked.
            connection.send(content: self.reply(to: 0x3F), completion: .idempotent)
            self.receive(on: connection)
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else { return }
            if let data, !data.isEmpty {
                for reply in self.consume(data) {
                    connection.send(content: reply, completion: .idempotent)
                }
            }
            guard !isComplete else { return }
            self.receive(on: connection)
        }
    }

    /// Pull whole commands out of the byte stream and answer each one.
    private func consume(_ data: Data) -> [Data] {
        var replies: [Data] = []
        let pending = state.withLock { log -> [UInt8] in
            var taken: [UInt8] = []
            log.inbox.append(data)
            while let (command, length, points) = Self.nextCommand(log.inbox) {
                log.inbox.removeFirst(length)
                log.commands.append(command)
                switch command {
                case 0x62:                                  // start playing
                    log.rate = points.rate
                    log.playing = true
                case 0x74:                                  // change the rate
                    log.rate = points.rate
                case 0x64:                                  // points
                    log.points.append(contentsOf: points.points)
                    log.pointsReceived += points.points.count
                    log.buffered += points.points.count
                case 0x73, 0x00, 0xFF:
                    log.playing = false
                default:
                    break
                }
                taken.append(command)
            }
            return taken
        }
        for command in pending { replies.append(reply(to: command)) }
        return replies
    }

    /// The status a real DAC would report: the buffer drains at the point rate
    /// it was started with, so it fills up when the client sends too fast.
    private func status() -> EtherDreamStatus {
        state.withLock { log in
            let now = Date()
            if log.rate > 0 {
                let drained = Int(now.timeIntervalSince(log.lastDrain) * Double(log.rate))
                log.buffered = max(0, log.buffered - drained)
            }
            log.lastDrain = now
            log.buffered = min(log.buffered, capacity)
            return EtherDreamStatus(protocolVersion: 0, lightEngine: .ready,
                                    playback: log.playing ? .playing : .prepared, source: 0,
                                    lightEngineFlags: 0, playbackFlags: 0, sourceFlags: 0,
                                    bufferFullness: log.buffered, pointRate: log.rate,
                                    pointCount: log.pointsReceived)
        }
    }

    private func reply(to command: UInt8) -> Data {
        EtherDreamResponse(code: .ack, command: command, status: status()).encode()
    }

    /// One whole command from the head of `data`, or `nil` when more bytes are
    /// needed. Lengths come from the protocol, not from guessing.
    static func nextCommand(_ data: Data) -> (UInt8, Int, (rate: Int, points: [LaserPoint]))? {
        guard let first = data.first else { return nil }
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        switch first {
        case 0x3F, 0x70, 0x73, 0x00, 0xFF, 0x63:
            return (first, 1, (0, []))
        case 0x62:                                          // command, low water mark, rate
            guard bytes.count >= 7 else { return nil }
            return (first, 7, (u32(3), []))
        case 0x74:                                          // command, rate
            guard bytes.count >= 5 else { return nil }
            return (first, 5, (u32(1), []))
        case 0x64:                                          // command, count, points
            guard bytes.count >= 3 else { return nil }
            let count = Int(bytes[1]) | Int(bytes[2]) << 8
            let length = 3 + count * 18
            guard bytes.count >= length else { return nil }
            var points: [LaserPoint] = []
            points.reserveCapacity(count)
            for i in 0..<count {
                let at = 3 + i * 18
                func i16(_ o: Int) -> Int16 {
                    Int16(bitPattern: UInt16(bytes[at + o]) | UInt16(bytes[at + o + 1]) << 8)
                }
                func u16(_ o: Int) -> UInt16 {
                    UInt16(bytes[at + o]) | UInt16(bytes[at + o + 1]) << 8
                }
                let position = Vector2(Double(i16(2)) / 32767, Double(i16(4)) / 32767)
                let r = Double(u16(6)) / 65535, g = Double(u16(8)) / 65535, b = Double(u16(10)) / 65535
                if r == 0, g == 0, b == 0 {
                    points.append(LaserPoint(blankedAt: position))
                } else {
                    points.append(LaserPoint(position, color: Color(red: r, green: g, blue: b)))
                }
            }
            return (first, length, (0, points))
        default:
            return (first, 1, (0, []))
        }
    }
}
