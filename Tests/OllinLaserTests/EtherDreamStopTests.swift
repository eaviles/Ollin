import Foundation
import Testing
import OllinTestSupport
@testable import OllinLaser

/// The stop condition a DAC raises from its hardware interlock, and the finder
/// on a port another program holds.
///
/// A DAC answering with the stop condition used to be read as a lost
/// connection: the host dropped the socket, then sent the clear into nothing
/// and set itself to preparing with no connection to prepare on, so a laser
/// whose interlock tripped once stayed dark until the sketch was restarted.
@Suite
struct EtherDreamStopTests {

    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        try await OllinTestSupport.waitFor(timeout: timeout, probe)
    }

    @Test func anEmergencyStopIsClearedAndThePlaybackComesBack() async throws {
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
        // The next command is refused with the stop condition. The host says
        // so, clears the stop, and runs the handshake again...
        _ = try await waitFor { dac.commands.contains(0x63) ? true : nil }
        _ = try await waitFor { dac.isEmergencyStopped ? nil : true }
        // ...so points flow once more on the same connection.
        let before = dac.pointsReceived
        _ = try await waitFor { dac.pointsReceived > before + 100 ? true : nil }
        #expect(client.isPlaying)
        #expect(client.lastError == nil)
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
        held.close()
        // Asked again once the port is free, it comes up.
        try finder.start()
        #expect(finder.isRunning)
    }
}
