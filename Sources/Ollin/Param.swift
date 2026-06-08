import Foundation
import os

/// A tunable parameter the live host surfaces as a slider. Declare it on a
/// sketch and read it like a normal property; the live host discovers it, shows
/// a slider, and persists its value across reloads.
///
/// ```swift
/// final class Pulse: Sketch {
///     @Param(0...200) var radius = 120.0          // label "Radius", from the name
///     @Param("Speed", 0.1...4) var rate = 1.0     // explicit label
///     override func draw() {
///         drawCircle(width / 2, height / 2, radius + sin(time * rate) * 40)
///     }
/// }
/// ```
///
/// The value is always clamped to its range. Pass a label to override the one
/// derived from the property name.
///
/// The value is safe to read and write from any thread: the live inspector
/// drives it from the main thread, and an external control source (a hardware
/// fader, a networked message) may drive the same knob from its own thread, so
/// the storage is guarded by a lock and the type is `Sendable`.
@propertyWrapper
public final class Param: @unchecked Sendable {
    private let storage: OSAllocatedUnfairLock<Double>
    /// The allowed range; the value is clamped to it.
    public let range: ClosedRange<Double>
    /// An explicit display label, or `nil` to derive one from the property name.
    public let label: String?

    public var wrappedValue: Double {
        get { storage.withLock { $0 } }
        set {
            let clamped = Swift.min(Swift.max(newValue, range.lowerBound), range.upperBound)
            storage.withLock { $0 = clamped }
        }
    }

    /// The parameter itself, via `$radius` — handy for passing it around.
    public var projectedValue: Param { self }

    public init(wrappedValue: Double, _ range: ClosedRange<Double>) {
        self.range = range
        self.label = nil
        self.storage = OSAllocatedUnfairLock(
            initialState: Swift.min(Swift.max(wrappedValue, range.lowerBound), range.upperBound))
    }

    public init(wrappedValue: Double, _ label: String, _ range: ClosedRange<Double>) {
        self.range = range
        self.label = label
        self.storage = OSAllocatedUnfairLock(
            initialState: Swift.min(Swift.max(wrappedValue, range.lowerBound), range.upperBound))
    }
}

/// A discovered `@Param` on a sketch: its persistence key (the property name),
/// the parameter itself (read/write the value, read the range), and a display
/// label. The live host builds one slider per handle.
public struct ParamHandle: Identifiable {
    /// The property name — a stable key for persisting the value across reloads.
    public let name: String
    public let param: Param
    public var id: String { name }
    public var label: String { param.label ?? ParamHandle.humanize(name) }

    /// "radius" -> "Radius", "noiseScale" -> "Noise Scale".
    static func humanize(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

public extension Sketch {
    /// The `@Param` parameters declared on this sketch, discovered via reflection
    /// (walking the class hierarchy). The live host uses this to build sliders;
    /// most sketches never call it directly.
    func parameters() -> [ParamHandle] {
        var handles: [ParamHandle] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                guard let param = child.value as? Param, let storageName = child.label else { continue }
                // Property-wrapper storage is named `_radius`; strip the underscore.
                let name = storageName.hasPrefix("_") ? String(storageName.dropFirst()) : storageName
                handles.append(ParamHandle(name: name, param: param))
            }
            mirror = current.superclassMirror
        }
        return handles
    }
}
