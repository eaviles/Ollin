/// One thing a sound classifier thinks it is hearing, and how sure it is.
///
/// The label is one of *that classifier's* own names: the built-in vocabulary
/// spells them in lower case with underscores (`"dog_bark"`, `"finger_snapping"`,
/// `"electric_guitar"`), and a model you bring spells them however it was
/// trained.
///
/// This value lives in the core so every pair of ears reports the same thing:
/// the Mac's own classifier over a microphone or a playing sound, and a tethered
/// iPhone's classifier over its microphone, read through `PhoneDevice.sounds`.
/// A sketch written against one reads the other unchanged.
public struct SoundClassification: Sendable, Equatable {
    /// What the classifier heard.
    public let label: String
    /// How sure it is, `0...1`.
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// A sound that just started: a label crossing a classifier's `threshold`
/// after being under it. The trigger half of the listening surface, where
/// `confidence(of:)` is the level half.
public struct SoundEvent: Sendable, Equatable {
    /// What was heard.
    public let label: String
    /// How sure the classifier was when it crossed.
    public let confidence: Double
    /// When it crossed, in seconds of audio since the classifier started. This
    /// is the sample clock, not the wall clock, so the same audio always
    /// produces the same times.
    public let time: Double

    public init(label: String, confidence: Double, time: Double) {
        self.label = label
        self.confidence = confidence
        self.time = time
    }
}
