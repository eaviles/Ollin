import Foundation
import Testing
import OllinTestSupport
@testable import OllinLaser

/// The stop condition a DAC raises from its hardware interlock, and the finder
/// on a port another program holds.
///
/// Two rules meet here. A DAC answering with the stop condition is not a lost
/// connection: reading it as one dropped the socket, so a laser whose
/// interlock tripped once stayed dark until the sketch was restarted. And a
/// stop that clears must never restart the beam on its own, the rule for an
/// emergency stop everywhere: the DAC holds the stop, the projector disarms,
/// and `arm()` is the one deliberate restart.
@Suite
struct EtherDreamStopTests {

    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        try await OllinTestSupport.waitFor(timeout: timeout, probe)
    }

    @Test func aStopConditionIsHeldUntilItIsClearedOnPurpose() async throws {
        let dac = try StandInDAC()
        defer { dac.stop() }
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 100 ? true : nil }
        #expect(client.isPlaying)

        dac.raiseEmergencyStop()
        // The next command is refused with the stop condition. The host keeps
        // the connection, says so, and sends nothing more on its own.
        _ = try await waitFor { client.hasStopCondition ? true : nil }
        #expect(!client.isPlaying)
        #expect(client.lastError?.contains("stop condition") == true)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!dac.commands.contains(0x63))
        #expect(dac.isEmergencyStopped)

        // The deliberate restart: the clear goes out, the handshake runs again
        // on the same connection, and points flow once more.
        client.clearStopCondition()
        _ = try await waitFor { dac.isEmergencyStopped ? nil : true }
        let before = dac.pointsReceived
        _ = try await waitFor { dac.pointsReceived > before + 100 ? true : nil }
        #expect(client.isPlaying)
        #expect(!client.hasStopCondition)
        #expect(client.lastError == nil)
    }

    @Test func aStopTheDACStillHoldsRefusesTheClearAndSaysSo() async throws {
        let dac = try StandInDAC()
        defer { dac.stop() }
        let port = try await waitFor { dac.boundPort }
        let client = EtherDreamDAC(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        client.connect()
        client.play(litSquare())
        _ = try await waitFor { dac.pointsReceived > 100 ? true : nil }

        dac.raiseEmergencyStop(holdingInterlock: true)
        _ = try await waitFor { client.hasStopCondition ? true : nil }
        client.clearStopCondition()
        _ = try await waitFor { client.lastError?.contains("interlock") == true ? true : nil }
        #expect(client.hasStopCondition)
        #expect(!client.isPlaying)

        dac.closeInterlock()
        client.clearStopCondition()
        _ = try await waitFor { client.isPlaying ? true : nil }
        #expect(client.lastError == nil)
    }

    @Test func anEmergencyStopDisarmsTheProjectorAndArmingRestartsIt() async throws {
        let dac = try StandInDAC()
        defer { dac.stop() }
        let port = try await waitFor { dac.boundPort }
        let laser = LaserProjector(etherDream: "127.0.0.1", port: port)
        laser.safety.stallTimeout = 60
        defer { laser.disconnect() }
        laser.connect()
        laser.arm()
        laser.send(square())
        _ = try await waitFor { dac.points.contains { !$0.isBlanked } ? true : nil }

        dac.raiseEmergencyStop()
        _ = try await waitFor { laser.hasStopCondition ? true : nil }
        // The next frame finds the stop and disarms the projector; nothing
        // lit can go out until somebody arms it again.
        laser.send(square())
        #expect(!laser.isArmed)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!dac.commands.contains(0x63))
        #expect(!laser.isPlaying)

        // Arming again is the restart.
        dac.forgetPoints()
        laser.arm()
        _ = try await waitFor { laser.isPlaying ? true : nil }
        laser.send(square())
        _ = try await waitFor { dac.points.contains { !$0.isBlanked } ? true : nil }
        #expect(laser.isArmed)
        #expect(!laser.hasStopCondition)
    }
}

/// The finder on a port another program holds.
@Suite
struct EtherDreamFinderListenerTests {

    @Test func aFinderOnAHeldPortIsNotRunning() async throws {
        let held = try HeldPort(udp: true, port: EtherDreamWire.broadcastPort)
        let finder = EtherDreamFinder()
        defer { finder.stop() }
        try finder.start()
        _ = try await waitFor { finder.isRunning ? nil : true }
        let reason = try #require(finder.lastError)
        #expect(reason.contains("\(EtherDreamWire.broadcastPort)"), Comment(rawValue: reason))
        held.close()
        // Asked again once the port is free, it comes up.
        try finder.start()
        #expect(finder.isRunning)
    }
}
