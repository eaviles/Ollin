import Foundation

/// How hard the two ends work to deliver one message.
///
/// MQTT defines a third level, exactly once, which costs a four-packet handshake
/// and a stored state machine on both sides. A sketch reading a room does not
/// need it: a sensor that publishes every second is better served by the newest
/// reading than by a guarantee that an old one arrived once. This client asks for
/// at most `atLeastOnce`, so a broker never opens that handshake with it.
public enum MQTTQoS: Int, Sendable, Hashable, CaseIterable {
    /// Send it and forget it. The fastest, and the right level for a value that
    /// is published again in a moment anyway.
    case atMostOnce = 0
    /// Keep it until the far end acknowledges it, resending after a reconnection.
    /// A duplicate is possible, which is why `MQTTMessage.isDuplicate` is readable.
    case atLeastOnce = 1
}

/// The message a broker publishes on a client's behalf when that client drops off
/// without saying goodbye. It is handed over at connection time and sits at the
/// broker until it is either needed or cancelled by a clean disconnect, which is
/// what makes it the way an installation announces its own failure.
public struct MQTTWill: Sendable, Hashable {

    /// Where the broker publishes it.
    public var topic: String
    /// What it publishes.
    public var payload: Data
    /// The level the broker publishes it at.
    public var qos: MQTTQoS
    /// Whether the broker keeps it as the topic's retained value, so a client
    /// subscribing later still learns the sketch went away.
    public var retains: Bool

    /// A will carrying text, which is what a status topic almost always holds.
    public init(topic: String, text: String, qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        self.init(topic: topic, payload: Data(text.utf8), qos: qos, retains: retains)
    }

    /// A will carrying raw bytes.
    public init(topic: String, payload: Data, qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retains = retains
    }
}

/// One message as it arrived: the topic it came in on and the bytes it carried,
/// with the readings a sketch actually wants layered over them.
///
/// MQTT says nothing about what a payload means, so the readings here follow what
/// the devices in the wild do. A sensor publishes `"21.4"`, a switch publishes
/// `"ON"` or `"OFF"`, and a bridge publishes a small JSON object. Those are the
/// three shapes `number`, `bool`, and `number(named:)` read.
public struct MQTTMessage: Sendable, Hashable {

    /// The topic the message arrived on. Never a filter: a published topic has no
    /// wildcards in it.
    public let topic: String
    /// The bytes exactly as they arrived.
    public let payload: Data
    /// The level it was delivered at.
    public let qos: MQTTQoS
    /// Whether the broker sent it as a topic's stored value rather than as
    /// something that just happened. A fresh subscription gets the retained value
    /// immediately, which is how a sketch starts up already knowing the room.
    public let isRetained: Bool
    /// Whether the sender marked it as a resend. Only possible above
    /// `MQTTQoS.atMostOnce`.
    public let isDuplicate: Bool

    public init(topic: String, payload: Data, qos: MQTTQoS = .atMostOnce,
                isRetained: Bool = false, isDuplicate: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.isRetained = isRetained
        self.isDuplicate = isDuplicate
    }

    /// A message carrying text.
    public init(topic: String, text: String, qos: MQTTQoS = .atMostOnce,
                isRetained: Bool = false) {
        self.init(topic: topic, payload: Data(text.utf8), qos: qos, isRetained: isRetained)
    }

    // MARK: Reading the payload

    /// The payload as UTF-8 text, or `nil` if it is not valid UTF-8.
    public var text: String? { String(data: payload, encoding: .utf8) }

    /// The payload read as a number. Whitespace around it is ignored, so a line a
    /// device ended with a newline still reads.
    public var number: Double? {
        guard let text else { return nil }
        return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The payload read as a whole number, rounded from `number`.
    public var int: Int? {
        guard let number, number.isFinite else { return nil }
        return Int(number.rounded())
    }

    /// The payload read as a switch. `on`, `true`, `1`, `yes`, `open`, and
    /// `online` are true and their opposites are false, in any casing; anything
    /// else is `nil`. These are the words the devices publish, so a lamp reads
    /// without a table of your own.
    public var bool: Bool? {
        guard let text else { return nil }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on", "true", "1", "yes", "open", "online", "active": return true
        case "off", "false", "0", "no", "closed", "offline", "inactive": return false
        default: return nil
        }
    }

    /// A named field of a JSON object payload, read as text. `nil` when the
    /// payload is not a JSON object or has no such key.
    public func text(named key: String) -> String? {
        switch field(key) {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    /// A named field of a JSON object payload, read as a number. A field that is
    /// itself a string of digits reads too, which is what several bridges publish.
    public func number(named key: String) -> Double? {
        switch field(key) {
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    /// A named field of a JSON object payload, read as a whole number.
    public func int(named key: String) -> Int? {
        guard let value = number(named: key), value.isFinite else { return nil }
        return Int(value.rounded())
    }

    /// A named field of a JSON object payload, read as a switch. A real JSON
    /// boolean reads, and so do the words a string field spells it with.
    public func bool(named key: String) -> Bool? {
        switch field(key) {
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
            return value.doubleValue != 0
        case let value as String:
            return MQTTMessage(topic: topic, text: value).bool
        default: return nil
        }
    }

    private func field(_ key: String) -> Any? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        return object[key]
    }
}

// MARK: - Topic filters

/// The subscription-matching rules, which are the one piece of MQTT a sketch has
/// to think about.
///
/// A topic is levels separated by `/`. A filter may put `+` where any one level
/// goes, and `#` at the end for every level from there down. Two rules are easy
/// to miss and both are pinned by tests: `home/#` matches the bare topic `home`
/// as well as everything under it, and a wildcard at the start never reaches a
/// topic beginning with `$`, which is where brokers keep their own statistics.
public enum MQTTTopic {

    /// Whether `topic` is delivered to a subscription on `filter`.
    public static func matches(_ topic: String, filter: String) -> Bool {
        let topicLevels = topic.split(separator: "/", omittingEmptySubsequences: false)
        let filterLevels = filter.split(separator: "/", omittingEmptySubsequences: false)
        guard !topicLevels.isEmpty, !filterLevels.isEmpty else { return false }

        // A leading wildcard never reaches the broker's own `$` namespace.
        if topicLevels[0].hasPrefix("$") && (filterLevels[0] == "#" || filterLevels[0] == "+") {
            return false
        }

        var topicIndex = 0
        for (filterIndex, level) in filterLevels.enumerated() {
            if level == "#" {
                // Only legal as the last level, and it covers the parent level too,
                // so `sport/#` matches `sport` itself.
                return filterIndex == filterLevels.count - 1
            }
            guard topicIndex < topicLevels.count else { return false }
            if level != "+" && level != topicLevels[topicIndex] { return false }
            topicIndex += 1
        }
        return topicIndex == topicLevels.count
    }

    /// Whether a filter is one a broker will accept: no empty filter, `#` only as
    /// a whole last level, `+` only as a whole level.
    public static func isValidFilter(_ filter: String) -> Bool {
        guard !filter.isEmpty, filter.utf8.count <= 65535 else { return false }
        let levels = filter.split(separator: "/", omittingEmptySubsequences: false)
        for (index, level) in levels.enumerated() {
            if level.contains("#") {
                guard level == "#", index == levels.count - 1 else { return false }
            }
            if level.contains("+") {
                guard level == "+" else { return false }
            }
        }
        return true
    }
}
