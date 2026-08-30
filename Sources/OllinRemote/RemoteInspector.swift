import Foundation
import Network
import Ollin
import os

/// Serves the sketch's `@Param` knobs to a phone or a second machine on the
/// local network, so an installation is tuned from in front of it rather than
/// from behind the Mac running it. Register it on the extension seam:
///
/// ```swift
/// import OllinRemote
///
/// @Param(0.1...4) var speed = 1.4
///
/// override func setup() {
///     extend(RemoteInspector())
/// }
/// ```
///
/// The sketch then prints one line with the address, `http://your-mac.local:9330`
/// by default; any browser on the same network opens a touch surface with the
/// same knobs the inspector sidebar shows, live both ways. Values a visitor
/// drags apply on the main thread between frames, exactly where the inspector's
/// own edits land; edits made on the Mac travel back a few times a second.
///
/// Anyone on the network who has the address can move the knobs while the
/// server is up, so treat it as a studio and venue tool, not something to
/// leave on a hostile network.
///
/// The extension side runs on the main actor with the sketch; the sockets live
/// in a nonisolated server object, and every crossing between the two is a
/// lock-guarded handoff.
public final class RemoteInspector: SketchExtension {

    private let server: RemoteServer

    // Main-actor state, only ever touched from the sketch's loop.
    private weak var sketch: Sketch?
    private var handles: [ParamHandle] = []
    private var handlesByName: [String: ParamHandle] = [:]
    private var lastPush: Double = 0
    private var announced = false

    // MARK: Lifecycle

    /// Creates the server. Pass a `port` to override the default `9330`, or
    /// `0` to let the system pick a free one (read it back from `boundPort`).
    public init(port: Int = 9330) {
        server = RemoteServer(port: UInt16(clamping: port))
    }

    deinit {
        server.shutdown()
    }

    /// The port actually bound, once the listener is up.
    public var boundPort: Int? { server.boundPort }

    /// The address a phone on the same network opens, once the listener is up.
    public var url: String? {
        guard let port = server.boundPort else { return nil }
        return "http://\(ProcessInfo.processInfo.hostName):\(port)"
    }

    /// Stops serving and drops every connection. `deinit` calls it, so a
    /// reload that builds a fresh sketch (and a fresh extension) releases the
    /// port on its own.
    public func stop() {
        server.shutdown()
    }

    // MARK: Extension hooks

    public func setup(_ sketch: Sketch) {
        discover(sketch)
        server.start()
    }

    /// The socket-free half of `setup`: knob discovery and the first wire
    /// snapshot. Split out so tests can drive the apply path with no listener.
    func discover(_ sketch: Sketch) {
        self.sketch = sketch
        handles = sketch.parameters()
        handlesByName = [:]
        for handle in handles { handlesByName[handle.name] = handle }
        _ = server.replaceSnapshot(makeSnapshot(sketchName: String(describing: type(of: sketch))))
    }

    /// Queues one incoming value for the next `beforeDraw`. The network side
    /// is its only production caller; tests use it to stand in for a page.
    nonisolated func enqueue(_ name: String, _ value: ParamStored) {
        server.enqueue(name, value)
    }

    public func beforeDraw(_ sketch: Sketch) {
        for set in server.drainPending() {
            guard let handle = handlesByName[set.name] else { continue }
            RemoteWire.apply(set.value, to: handle)
        }
    }

    public func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {
        announceIfReady()
        let now = sketch.time
        guard now - lastPush >= 0.25 || now < lastPush else { return }
        lastPush = now

        let name = server.currentSnapshot().sketchName
        let previous = server.replaceSnapshot(makeSnapshot(sketchName: name))
        let current = server.currentSnapshot()

        var changedValues: [String: ParamStored] = [:]
        for (key, value) in current.values where previous.values[key] != value {
            changedValues[key] = value
        }
        var changedShown: [String: Bool] = [:]
        for (key, shown) in current.shown where previous.shown[key] != shown {
            changedShown[key] = shown
        }
        if !changedValues.isEmpty || !changedShown.isEmpty {
            server.broadcast(RemoteUpdate(values: changedValues, shown: changedShown))
        }
        server.broadcast(RemoteStats(fps: info.frameRate, clock: sketch.time, frame: sketch.frameCount))
    }

    // MARK: Snapshots

    private func makeSnapshot(sketchName: String) -> RemoteServer.Snapshot {
        var fresh = RemoteServer.Snapshot()
        fresh.sketchName = sketchName
        fresh.host = ProcessInfo.processInfo.hostName
        fresh.descriptors = handles.map(RemoteWire.descriptor(for:))
        for descriptor in fresh.descriptors {
            fresh.values[descriptor.name] = descriptor.value
            fresh.shown[descriptor.name] = descriptor.isShown
        }
        return fresh
    }

    private func announceIfReady() {
        guard !announced, let url else { return }
        announced = true
        print("Remote surface: \(url)")
    }
}

// MARK: - The server

/// The socket side, deliberately outside the main actor: one TCP listener
/// whose connections speak plain HTTP for the page and WebSocket after the
/// upgrade. Events arrive on a private queue; everything shared with the
/// extension crosses through a lock.
final class RemoteServer: @unchecked Sendable {

    /// The wire snapshot the network side reads: descriptors for a hello,
    /// values and visibility for diffing. Built on the main actor, read here.
    struct Snapshot: Sendable {
        var sketchName = ""
        var host = ""
        var descriptors: [RemoteParamDescriptor] = []
        var values: [String: ParamStored] = [:]
        var shown: [String: Bool] = [:]
    }

    /// One accepted connection: its raw byte buffer until the head parses,
    /// then WebSocket frames, with continuation fragments accumulated. All
    /// mutable state is touched only on the server's queue.
    private final class Link: @unchecked Sendable {
        let connection: NWConnection
        var buffer: [UInt8] = []
        var upgraded = false
        var fragments: [UInt8] = []
        var fragmentOpcode: WebSocketFraming.Opcode?
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let desiredPort: UInt16
    private let queue = DispatchQueue(label: "com.ollin.remote.inspector")
    private let listenerStore = OSAllocatedUnfairLock<NWListener?>(uncheckedState: nil)
    private let resolvedPort = OSAllocatedUnfairLock<UInt16?>(initialState: nil)
    private let links = OSAllocatedUnfairLock<[ObjectIdentifier: Link]>(uncheckedState: [:])
    private let pendingSets = OSAllocatedUnfairLock<[(name: String, value: ParamStored)]>(initialState: [])
    private let snapshot = OSAllocatedUnfairLock(initialState: Snapshot())
    private let page: Data

    init(port: UInt16) {
        desiredPort = port
        if let url = Bundle.module.url(forResource: "surface", withExtension: "html"),
           let data = try? Data(contentsOf: url) {
            page = data
        } else {
            page = Data("<!doctype html><p>The control page resource is missing.".utf8)
        }
    }

    deinit {
        shutdown()
    }

    var boundPort: Int? {
        resolvedPort.withLock { $0.map(Int.init) }
    }

    // MARK: Handoffs with the extension

    func enqueue(_ name: String, _ value: ParamStored) {
        pendingSets.withLock { $0.append((name, value)) }
    }

    func drainPending() -> [(name: String, value: ParamStored)] {
        pendingSets.withLock { pending in
            let drained = pending
            pending.removeAll()
            return drained
        }
    }

    func currentSnapshot() -> Snapshot {
        snapshot.withLock { $0 }
    }

    func replaceSnapshot(_ fresh: Snapshot) -> Snapshot {
        snapshot.withLock { held in
            let previous = held
            held = fresh
            return previous
        }
    }

    // MARK: Lifecycle

    func start() {
        let alreadyRunning = listenerStore.withLock { $0 != nil }
        guard !alreadyRunning else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: desiredPort) else { return }
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            print("Remote surface: could not open port \(desiredPort): \(error)")
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.resolvedPort.withLock { $0 = listener.port?.rawValue }
            case .failed(let error):
                // Said out loud on purpose: a port already in use, or a policy
                // that refuses the bind, would otherwise look like silence.
                print("Remote surface: the listener failed: \(error)")
            case .waiting(let error):
                print("Remote surface: waiting to open the port: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.adopt(connection)
        }
        listenerStore.withLock { $0 = listener }
        listener.start(queue: queue)
    }

    func shutdown() {
        listenerStore.withLock { listener in
            listener?.cancel()
            listener = nil
        }
        links.withLock { all in
            for link in all.values { link.connection.cancel() }
            all.removeAll()
        }
    }

    // MARK: Connections

    private func adopt(_ connection: NWConnection) {
        let link = Link(connection)
        links.withLock { $0[ObjectIdentifier(link)] = link }
        connection.stateUpdateHandler = { [weak self, weak link] state in
            switch state {
            case .failed, .cancelled:
                guard let link else { return }
                self?.links.withLock { $0[ObjectIdentifier(link)] = nil }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: link)
    }

    private func receive(on link: Link) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self, weak link] data, _, isComplete, error in
            guard let self, let link else { return }
            if let data, !data.isEmpty {
                link.buffer.append(contentsOf: data)
                self.process(link)
            }
            if isComplete || error != nil {
                self.drop(link)
            } else {
                self.receive(on: link)
            }
        }
    }

    private func drop(_ link: Link) {
        link.connection.cancel()
        links.withLock { $0[ObjectIdentifier(link)] = nil }
    }

    private func process(_ link: Link) {
        if !link.upgraded {
            guard let (request, consumed) = RemoteHTTP.parseHead(link.buffer) else { return }
            link.buffer.removeFirst(consumed)
            if RemoteHTTP.isWebSocketUpgrade(request),
               let key = request.headers["sec-websocket-key"] {
                link.upgraded = true
                let accept = RemoteHTTP.acceptKey(for: key)
                link.connection.send(content: RemoteHTTP.upgradeResponse(accept: accept),
                                     completion: .contentProcessed { _ in })
                sendHello(to: link)
            } else if request.method == "GET", request.path == "/" || request.path == "/index.html" {
                link.connection.send(content: RemoteHTTP.pageResponse(html: page),
                                     completion: .contentProcessed { [weak self, weak link] _ in
                                         guard let self, let link else { return }
                                         self.drop(link)
                                     })
                return
            } else {
                link.connection.send(content: RemoteHTTP.notFound(),
                                     completion: .contentProcessed { [weak self, weak link] _ in
                                         guard let self, let link else { return }
                                         self.drop(link)
                                     })
                return
            }
        }
        guard link.upgraded else { return }
        guard let frames = WebSocketFraming.decode(buffer: &link.buffer) else {
            drop(link)
            return
        }
        for frame in frames { handle(frame, on: link) }
    }

    private func handle(_ frame: WebSocketFraming.Frame, on link: Link) {
        switch frame.opcode {
        case .text, .binary, .continuation:
            if frame.opcode != .continuation {
                link.fragments = frame.payload
                link.fragmentOpcode = frame.opcode
            } else {
                link.fragments.append(contentsOf: frame.payload)
            }
            guard frame.fin, link.fragmentOpcode == .text else { return }
            let payload = link.fragments
            link.fragments = []
            link.fragmentOpcode = nil
            receiveMessage(payload)
        case .ping:
            link.connection.send(content: WebSocketFraming.encode(.pong, payload: frame.payload),
                                 completion: .contentProcessed { _ in })
        case .close:
            link.connection.send(content: WebSocketFraming.encode(.close, payload: []),
                                 completion: .contentProcessed { _ in })
            drop(link)
        case .pong:
            break
        }
    }

    private func receiveMessage(_ payload: [UInt8]) {
        guard let set = try? JSONDecoder().decode(RemoteSet.self, from: Data(payload)),
              set.kind == .set else { return }
        enqueue(set.name, set.value)
    }

    // MARK: Sending

    private func sendHello(to link: Link) {
        let current = currentSnapshot()
        let hello = RemoteHello(sketch: current.sketchName, host: current.host,
                                params: current.descriptors)
        guard let data = try? JSONEncoder().encode(hello),
              let text = String(data: data, encoding: .utf8) else { return }
        link.connection.send(content: WebSocketFraming.encodeText(text),
                             completion: .contentProcessed { _ in })
    }

    func broadcast(_ message: some Encodable) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        let frame = WebSocketFraming.encodeText(text)
        let all = links.withLock { $0.values.filter(\.upgraded) }
        for link in all {
            link.connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }
}
