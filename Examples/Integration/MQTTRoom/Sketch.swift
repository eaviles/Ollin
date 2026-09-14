import Foundation
import Ollin
import OllinMQTT

/// A building's message bus, drawn as a wall of dials.
///
/// MQTT is how a room talks: sensors publish readings to topics, switches
/// subscribe to them, and a broker in the middle carries one to the other.
/// This sketch joins that bus. Every topic it hears becomes a dial, sized by
/// how recently it spoke, filled by where its reading sits in the range that
/// topic has covered so far.
///
/// It also publishes, so it shows a round trip with no sensor of your own: a
/// slow wave goes out on `ollin/sketch/wave` and comes straight back on the
/// subscription, and a click sends `ON` or `OFF` to `ollin/lamp/set`, which is
/// the message a real lamp takes. So with a bare broker and nothing else, two
/// dials are already turning.
///
/// You need a broker. The usual one is mosquitto:
///
///     brew install mosquitto
///     mosquitto -v
///
/// Then run this. Point `broker` at another machine to join a real house, and
/// widen `filter` to `#` to watch everything on it at once.
@main
final class MQTTRoom: Sketch {

    /// The machine running the broker. `localhost` is the one you just started.
    let broker = "localhost"

    let bus = MQTTClient(host: "localhost",
                         will: MQTTWill(topic: "ollin/sketch/status", text: "gone", retains: true))

    /// What to listen to. `#` is the whole bus, which with nothing but a fresh
    /// broker running is this sketch's own traffic and, in a real house, every
    /// sensor in it. Narrow it to `home/#` or `ollin/#` by typing one in.
    @Param var filter = "#"
    /// How long a topic stays on the wall after its last word, in seconds.
    @Param(5...120) var memory = 40.0
    /// How fast the wave this sketch publishes turns.
    @Param(0.05...2) var speed = 0.3

    /// What each topic has said, newest last.
    private var history: [String: [Double]] = [:]
    private var lastHeard: [String: Double] = [:]
    private var lastPublishedAt = 0.0
    private var lamp = false
    private var subscribed = ""

    override func setup() {
        textFont(.systemMedium)
        try? bus.connect()
        bus.publish("ollin/sketch/status", "here", retains: true)
    }

    override func draw() {
        background(Color(white: 0.06))
        follow(filter)
        speak()
        listen()
        drawWall()
        drawCaption()
    }

    // MARK: - The bus

    /// Keep the subscription matching the parameter, so turning the dial in the
    /// inspector widens what the wall shows.
    private func follow(_ wanted: String) {
        guard wanted != subscribed else { return }
        if !subscribed.isEmpty { bus.unsubscribe(from: subscribed) }
        bus.subscribe(to: wanted)
        subscribed = wanted
        history.removeAll()
        lastHeard.removeAll()
    }

    /// Publish a wave a few times a second, so there is always something on the
    /// bus to watch even with no sensor in the house.
    private func speak() {
        guard time - lastPublishedAt > 0.1 else { return }
        lastPublishedAt = time
        bus.publish("ollin/sketch/wave", (sin(time * speed * .pi * 2) + 1) / 2)
        bus.publish("ollin/sketch/mouse", mouseX / width)
    }

    /// Take everything that arrived since the last frame. The latest value of a
    /// topic is also readable directly, but a wall wants the whole trace.
    private func listen() {
        for message in bus.messages() {
            guard let value = message.number else { continue }
            var trace = history[message.topic] ?? []
            trace.append(value)
            if trace.count > 180 { trace.removeFirst(trace.count - 180) }
            history[message.topic] = trace
            lastHeard[message.topic] = time
        }
        for (topic, heard) in lastHeard where time - heard > memory {
            history[topic] = nil
            lastHeard[topic] = nil
        }
    }

    override func mousePressed() {
        lamp.toggle()
        bus.publish("ollin/lamp/set", lamp, retains: true)
    }

    // MARK: - The wall

    private func drawWall() {
        let topics = history.keys.sorted()
        guard !topics.isEmpty else {
            drawEmptyWall()
            return
        }
        let columns = Int(ceil(sqrt(Double(topics.count))))
        let cell = min(width, height - 180) / Double(columns)
        let left = (width - cell * Double(columns)) / 2
        let top = 150.0

        for (index, topic) in topics.enumerated() {
            let column = index % columns
            let row = index / columns
            let center = Vector2(left + (Double(column) + 0.5) * cell,
                                 top + (Double(row) + 0.5) * cell)
            drawDial(topic, at: center, size: cell * 0.86)
        }
    }

    private func drawDial(_ topic: String, at center: Vector2, size: Double) {
        let trace = history[topic] ?? []
        guard let value = trace.last else { return }
        let low = trace.min() ?? 0
        let high = trace.max() ?? 1
        let span = high - low
        let fraction = span > 0 ? (value - low) / span : 0.5
        let freshness = 1 - min(1, (time - (lastHeard[topic] ?? 0)) / memory)
        let radius = size * 0.34

        // The ring: how far this reading sits through the range the topic has
        // covered since the sketch started listening.
        noFill()
        stroke(Color(white: 0.18))
        strokeWeight(size * 0.05)
        drawCircle(center: center, radius: radius)

        stroke(Color(hue: 0.08 + fraction * 0.5, saturation: 0.75,
                     brightness: 0.45 + freshness * 0.55))
        drawArc(center: center, radiusX: radius, radiusY: radius,
                start: -.pi / 2, stop: -.pi / 2 + fraction * .pi * 2)

        // The trace: what the topic has been doing, oldest on the left.
        if trace.count > 1 && span > 0 {
            stroke(Color(white: 0.45 + freshness * 0.3))
            strokeWeight(1.5)
            let step = size * 0.5 / Double(trace.count - 1)
            var points: [Vector2] = []
            for (index, reading) in trace.enumerated() {
                let t = span > 0 ? (reading - low) / span : 0.5
                points.append(Vector2(center.x - size * 0.25 + Double(index) * step,
                                      center.y + radius * 0.55 - t * radius * 0.5))
            }
            drawPolyline(points)
        }

        noStroke()
        fill(Color(white: 0.95, alpha: 0.4 + freshness * 0.6))
        textSize(size * 0.13)
        textAlign(.center)
        drawText(reading(value), center.x, center.y + size * 0.05)
        textSize(size * 0.075)
        fill(Color(white: 0.55))
        drawText(lastLevel(of: topic), center.x, center.y + radius + size * 0.13)
        textAlign(.left)
    }

    /// A reading as a dial shows one: plain decimal, no exponent, no long tail.
    private func reading(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// A wall has room for the end of a topic, not all of it: `home/kitchen/
    /// temperature` reads as `kitchen/temperature`, which is the part that says
    /// what the dial is.
    private func lastLevel(of topic: String) -> String {
        topic.split(separator: "/").suffix(2).joined(separator: "/")
    }

    private func drawEmptyWall() {
        noStroke()
        fill(Color(white: 0.85))
        textSize(26)
        drawText(bus.isConnected ? "Connected. Nothing on \(filter) yet." : "Waiting for a broker at \(broker)", 60, height / 2 - 30)
        textSize(17)
        fill(Color(white: 0.55))
        let advice = bus.isConnected
            ? "Publish something and it appears here:\n\n    mosquitto_pub -t ollin/room/light -m 42\n\nWiden the filter parameter to # to watch the whole bus."
            : "Start one and this fills in:\n\n    brew install mosquitto\n    mosquitto -v\n\n\(bus.lastError ?? "")"
        drawText(advice, in: Rectangle(x: 60, y: height / 2, width: width - 120, height: 260))
    }

    private func drawCaption() {
        noStroke()
        fill(Color(white: 0.95))
        textSize(26)
        drawText(bus.isConnected ? "on the bus" : "off the bus", 44, 60)
        textSize(15)
        fill(Color(white: 0.5))
        drawText("\(broker) · \(filter) · \(history.count) topics · lamp \(lamp ? "on" : "off") · click to flip it",
                 44, 90)

        // A light that says whether the line is up, since everything else on
        // screen is history and history keeps drawing after a broker goes away.
        fill(bus.isConnected ? Color(hue: 0.35, saturation: 0.7, brightness: 0.8)
                             : Color(hue: 0.02, saturation: 0.8, brightness: 0.7))
        drawCircle(width - 50, 54, 9)
    }
}
