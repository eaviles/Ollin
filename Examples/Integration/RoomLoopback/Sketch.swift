import Foundation
import Ollin
import OllinRoom
import os

/// The room, with no second machine. Two rooms live in this one sketch and
/// talk to each other over a transport that stays inside the process, so the
/// whole loop is visible on one screen: the left panel sends where the pointer
/// is, the right panel draws only what arrived through the room.
///
/// The local network is the transport that ships (`Room(named:)`), and
/// `RoomTransport` is the seam it sits behind. Anything that carries bytes
/// between two rooms can take its place, which is what the little bus below
/// does, and what the tests do.
///
/// Move the pointer over the left panel. Hold the space bar to cut the wire:
/// the left panel keeps drawing and the right one stops, which is what a
/// machine that lost the network looks like.
@main
final class RoomLoopback: Sketch {

    @Param(0.05...1.0) var trail = 0.35

    private let bus = MemoryBus()
    private var here: Room!
    private var there: Room!
    private var sent: [Vector2] = []
    private var arrived: [Vector2] = []
    private var cut = false

    private let paper = Color(red: 0.06, green: 0.07, blue: 0.09)
    private let ink = Color(red: 0.35, green: 0.85, blue: 0.95)

    override func setup() {
        here = Room(transport: MemoryLink(name: "here", bus: bus))
        there = Room(transport: MemoryLink(name: "there", bus: bus))
        // Started by hand rather than through `extend`, because these two rooms
        // trade values and share no knobs.
        here.start()
        there.start()
    }

    override func draw() {
        background(paper)

        cut = isKeyDown(" ")
        bus.carrying = !cut

        let local = Vector2(min(max(mouseX, 0), width * 0.5), mouseY)
        here.send("pointer", local, reliable: false)
        remember(local, in: &sent)

        // The other room reads only what the wire brought it.
        for message in there.messages() {
            if let point = message.point { remember(point, in: &arrived) }
        }

        drawPanel(atX: 0, title: "here: sending", points: sent)
        drawPanel(atX: width * 0.5, title: "there: arrived", points: arrived)

        stroke(Color.white.withAlpha(0.12))
        strokeWeight(1)
        drawLine(width * 0.5, 0, width * 0.5, height)

        drawStatus()
    }

    private func remember(_ point: Vector2, in points: inout [Vector2]) {
        points.append(point)
        let keep = Int(trail * 240)
        if points.count > keep { points.removeFirst(points.count - keep) }
    }

    private func drawPanel(atX x: Double, title: String, points: [Vector2]) {
        withState {
            translate(x, 0)
            noStroke()
            fill(Color.white.withAlpha(0.55))
            textSize(22 * width / 1080)
            drawText(title, 30 * width / 1080, 44 * width / 1080)

            for (index, point) in points.enumerated() {
                let age = Double(index) / Double(max(1, points.count))
                fill(ink.withAlpha(0.08 + 0.62 * age))
                drawCircle(center: point, radius: 4 + 22 * age)
            }
        }
    }

    private func drawStatus() {
        let scale = width / 1080
        noStroke()
        fill(cut ? Color(red: 1, green: 0.5, blue: 0.4) : Color.white.withAlpha(0.45))
        textSize(19 * scale)
        let state = cut ? "wire cut (space)" : "connected: \(here.peers.joined(separator: ", "))"
        drawText(state, 30 * scale, height - 34 * scale)
    }
}

// MARK: - A room that never leaves the process

/// Carries messages between the rooms in this sketch. A transport is only asked
/// to hand bytes to a named peer, which is little enough that a demonstration
/// can write its own.
///
/// The room asks its clock question on a queue of its own, so this is reached
/// from two threads and everything it holds sits behind a lock. The lock is
/// always dropped before a message is delivered: delivering leads straight back
/// into `send`, and a lock still held there would stop the sketch dead.
final class MemoryBus: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(links: [String: MemoryLink], carrying: Bool)>(
        uncheckedState: ([:], true)
    )

    /// Set false to drop everything, which is what the space bar does.
    var carrying: Bool {
        get { state.withLock { $0.carrying } }
        set { state.withLock { $0.carrying = newValue } }
    }

    func join(_ link: MemoryLink) {
        let links = state.withLock { current -> [MemoryLink] in
            current.links[link.peerName] = link
            return Array(current.links.values)
        }
        for member in links {
            member.report(links.map(\.peerName).filter { $0 != member.peerName })
        }
    }

    func leave(_ name: String) {
        let links = state.withLock { current -> [MemoryLink] in
            current.links[name] = nil
            return Array(current.links.values)
        }
        for member in links {
            member.report(links.map(\.peerName).filter { $0 != member.peerName })
        }
    }

    func send(_ data: Data, from sender: String, to peers: [String]) {
        let targets = state.withLock { current -> [MemoryLink] in
            guard current.carrying else { return [] }
            let names = peers.isEmpty ? current.links.keys.filter { $0 != sender } : peers
            return names.compactMap { current.links[$0] }
        }
        for target in targets { target.deliver(data, from: sender) }
    }
}

final class MemoryLink: RoomTransport, @unchecked Sendable {
    let peerName: String
    private let bus: MemoryBus
    private let state = OSAllocatedUnfairLock<(handler: RoomTransportHandler?, peers: [String])>(
        uncheckedState: (nil, [])
    )

    init(name: String, bus: MemoryBus) {
        peerName = name
        self.bus = bus
    }

    var connectedPeers: [String] { state.withLock { $0.peers } }

    func start(_ handler: RoomTransportHandler) {
        state.withLock { $0.handler = handler }
        bus.join(self)
    }

    func stop() {
        bus.leave(peerName)
        state.withLock { $0 = (nil, []) }
    }

    func send(_ data: Data, reliable: Bool, to peers: [String]) {
        bus.send(data, from: peerName, to: peers)
    }

    func deliver(_ data: Data, from sender: String) {
        state.withLock { $0.handler }?.received(data, sender)
    }

    func report(_ peers: [String]) {
        let handler = state.withLock { current -> RoomTransportHandler? in
            current.peers = peers
            return current.handler
        }
        handler?.peersChanged(peers)
    }
}
