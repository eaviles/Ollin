import Ollin
import simd

/// What the light in the room is doing, measured by the phone from its own camera
/// image. It arrives in every capture mode, a few times a second, so a sketch can
/// match the room it is standing in.
///
/// ```swift
/// if let light = device.latestLight {
///     ambientLight(light.ambient)          // as bright and as warm as the room
///     if let key = light.key { self.light(key) }   // Face mode knows the direction
/// }
/// ```
///
/// `intensity` is scaled so that **1 is an ordinary indoor room** (ARKit's 1000
/// lumens), and `kelvin` is the color temperature, where **6500 is neutral white**.
/// A lamp reads warm and low, a window on an overcast day reads cool and high.
///
/// `direction`, `keyIntensity`, and `sphericalHarmonics` arrive only in **Face**
/// mode. A face gives ARKit a shape it knows, so it can work out where the light
/// comes from by how the face is shaded. A world-facing session cannot do that, and
/// reports brightness and warmth alone.
public struct PhoneLight: Sendable {

    /// The capture timestamp of the frame this was measured from, in the phone's
    /// clock (seconds).
    public let timestamp: Double

    /// The measured brightness in lumens, as ARKit reports it. 1000 is an ordinary
    /// indoor room.
    public let lumens: Double

    /// The same brightness scaled so 1 is an ordinary indoor room. A dim room reads
    /// below 1, bright sunlight well above it. This is the number to multiply a
    /// light or a color by.
    public let intensity: Double

    /// The color temperature in kelvin. 6500 is neutral white, lower is the warm
    /// yellow of a lamp, higher the cool blue of a window or an overcast sky.
    public let kelvin: Double

    /// The room's white, as a color: what a white wall in this room looks like.
    /// Brightness is not in it, so multiply by `intensity` or reach for `ambient`.
    public let color: Color

    /// The way the strongest light travels, as a unit vector in world space, or
    /// `nil` outside Face mode. A ceiling lamp points down.
    public let direction: Vector3?

    /// How strong that strongest light is, on the same scale as `intensity`, or
    /// `nil` outside Face mode.
    public let keyIntensity: Double?

    /// The 27 spherical-harmonic coefficients ARKit reports in Face mode (nine per
    /// color channel), or `nil` elsewhere. The compact description of light arriving
    /// from every direction at once, for a sketch that wants to shade with all of it
    /// rather than with one direction.
    public let sphericalHarmonics: [Float]?

    /// The room's light as one color, ready for `ambientLight(_:)`: the room's white
    /// scaled by how bright the room is, so a dim lamp-lit room lights a sketch dim
    /// and warm.
    public var ambient: Color {
        let k = min(1.5, max(0, intensity))
        return Color(red: color.red * k, green: color.green * k, blue: color.blue * k)
    }

    /// The strongest light in the room as a `Light` you can add to a scene, or `nil`
    /// outside Face mode. It carries the room's own color and brightness.
    ///
    /// ```swift
    /// if let key = device.latestLight?.key { light(key) }
    /// ```
    public var key: Light? {
        guard let direction, let keyIntensity else { return nil }
        return .directional(color, direction: direction, intensity: min(4, max(0, keyIntensity)))
    }

    /// A reading built by hand. The phone fills these in, and this is here so a
    /// sketch can be developed against a stand-in room with no phone attached, and
    /// so a test or a figure can say exactly what the light is doing.
    ///
    /// ```swift
    /// let lamplight = PhoneLight(lumens: 480, kelvin: 2700)
    /// ```
    public init(lumens: Double, kelvin: Double, direction: Vector3? = nil,
                keyIntensity: Double? = nil, sphericalHarmonics: [Float]? = nil,
                timestamp: Double = 0) {
        self.timestamp = timestamp
        self.lumens = lumens
        self.intensity = lumens / 1000
        self.kelvin = kelvin
        self.color = Color(kelvin: kelvin)
        self.direction = direction.map { $0.lengthSquared > 1e-12 ? $0.normalized : Vector3(0, -1, 0) }
        self.keyIntensity = keyIntensity
        self.sphericalHarmonics = sphericalHarmonics
    }

    /// Wrap a decoded wire sample, turning lumens into a multiplier and the color
    /// temperature into a color.
    init(_ sample: PhoneLightSample) {
        timestamp = sample.timestamp
        lumens = Double(sample.ambientIntensity)
        intensity = lumens / 1000
        kelvin = Double(sample.colorTemperature)
        color = Color(kelvin: kelvin)
        if sample.hasDirection {
            let d = Vector3(Double(sample.direction.x), Double(sample.direction.y),
                            Double(sample.direction.z))
            direction = d.lengthSquared > 1e-12 ? d.normalized : Vector3(0, -1, 0)
            keyIntensity = Double(sample.directionalIntensity) / 1000
            sphericalHarmonics = sample.sphericalHarmonics.isEmpty ? nil : sample.sphericalHarmonics
        } else {
            direction = nil
            keyIntensity = nil
            sphericalHarmonics = nil
        }
    }
}
