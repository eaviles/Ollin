import Foundation

/// A string with a bow on it.
///
/// The difference between this and a plucked string is not the string. It is
/// that a pluck happens once and a bow keeps happening: the player goes on
/// putting energy in for as long as the note lasts, so the note has a middle
/// rather than only an attack and a fade.
///
/// ```swift
/// let synth = Synth(.cello)
/// synth.pressure = 0.7         // how hard it is being bowed
/// synth.noteOn("G2")
/// ```
///
/// What makes it sound bowed is one nonlinearity. Rosin grips harder when the
/// bow and the string are moving together than when they are sliding past each
/// other, so the string is caught by the bow, dragged sideways, torn loose,
/// snapped back, and caught again, hundreds of times a second. That cycle is
/// where the tone comes from, and it is why a bowed note is a sawtooth and not
/// a sine: the string spends most of each cycle stuck to the bow.
///
/// The four numbers are the ones a player has: where the bow is, how hard it
/// presses, how long the string would ring on its own, and how bright it is.
public struct BowedString: Sendable, Hashable, Codable {

    /// Where along the string the bow sits, `0...1`, measured from the bridge.
    ///
    /// The same fact as a pluck position, felt differently. Close to the bridge
    /// (small numbers) is thin, bright and edgy, which is what *sul ponticello*
    /// means. Further along is broader and rounder. It also decides which
    /// harmonics have a node under the bow and so cannot sound.
    public var position: Double

    /// How hard the bow presses, `0...1`.
    ///
    /// This is the one that changes the character rather than the loudness.
    /// More force widens the range of speeds over which the rosin still grips,
    /// so the string stays stuck to the bow for longer in each cycle and the
    /// tone gets harder and more strident. Too little and the note will not
    /// catch at all, which is also true of a real bow.
    public var force: Double

    /// How long the string would take to fade if the bow were lifted, in
    /// seconds. Longer is a more resonant instrument.
    public var decay: Double

    /// How much sooner the bright part of the string goes than the low part,
    /// `0...1`. Higher is darker and more muted.
    public var damping: Double

    public init(
        position: Double = 0.13,
        force: Double = 0.5,
        decay: Double = 1.6,
        damping: Double = 0.4
    ) {
        self.position = min(max(0.02, position), 0.5)
        self.force = min(max(0, force), 1)
        self.decay = max(0.05, decay)
        self.damping = min(max(0, damping), 1)
    }

    // MARK: Presets

    /// Bowed close to the bridge, bright and a little edgy.
    public static let violin = BowedString(
        position: 0.14, force: 0.55, decay: 1.4, damping: 0.32
    )

    /// Broader and darker, bowed further from the bridge.
    public static let cello = BowedString(
        position: 0.16, force: 0.6, decay: 2.2, damping: 0.5
    )

    /// A light bow a long way along the string: soft, breathy, almost a sine.
    public static let sustained = BowedString(
        position: 0.20, force: 0.28, decay: 2.6, damping: 0.62
    )

    /// Heavy and close in, which is the sound of the string barely getting
    /// away from the bow at all.
    public static let ponticello = BowedString(
        position: 0.06, force: 0.85, decay: 1.2, damping: 0.2
    )
}

/// A tube being blown.
///
/// A column of air in a tube resonates, and something at one end keeps feeding
/// it. Here that something is a reed, pushed shut by the very pressure that is
/// driving it, which is the feedback that makes the whole thing sing.
///
/// The tube is stopped at the reed and open at the far end, and that one fact
/// is most of the sound. A tube closed at one end fits only a quarter of a
/// wave, so it supports the odd harmonics and not the even ones, which is why
/// it is hollow and woody rather than bright, and why it sounds an octave and a
/// fifth below an open tube of the same length instead of an octave below.
///
/// ```swift
/// let synth = Synth(.clarinet)
/// synth.pressure = 0.8         // how hard it is being blown
/// synth.noteOn("D4")
/// ```
///
/// Like the bow, it is driven rather than struck: the breath goes on for as
/// long as the note does. Stop driving it and the tone stops, which is why
/// `pressure` is the expressive control here rather than the envelope.
public struct BlownTube: Sendable, Hashable, Codable {

    /// How hard the lips are pressed, `0...1`.
    ///
    /// The bite. Higher shuts the reed at a lower pressure, so it never gets
    /// far open, lets less through, and the tone comes out simpler and thinner.
    /// A looser lip lets the reed swing further and gives the fuller, reedier
    /// sound. It is the one setting that survives being called embouchure
    /// without turning into a metaphor.
    public var embouchure: Double

    /// How much of the breath arrives as noise, `0...1`.
    ///
    /// A real player's air is turbulent, and a wind instrument with none of
    /// that in it sounds synthetic in a way that is hard to place until you
    /// hear it put back.
    public var breathiness: Double

    /// How long the tube would ring if the breath stopped, in seconds. This is
    /// short for any real tube; it is what makes a wind note stop when you do.
    public var decay: Double

    /// How much sooner the bright part goes than the low part, `0...1`. It is
    /// the far end of the tube losing the high partials faster, which is most
    /// of what separates a warm tube from a piercing one.
    public var damping: Double

    public init(
        embouchure: Double = 0.5,
        breathiness: Double = 0.12,
        decay: Double = 0.14,
        damping: Double = 0.42
    ) {
        self.embouchure = min(max(0, embouchure), 1)
        self.breathiness = min(max(0, breathiness), 1)
        self.decay = max(0.01, decay)
        self.damping = min(max(0, damping), 1)
    }

    // MARK: Presets

    /// Hollow and woody, with only the odd harmonics in it.
    public static let clarinet = BlownTube(
        embouchure: 0.45, breathiness: 0.1, decay: 0.16, damping: 0.4
    )

    /// Bitten tight and damped hard: thin, pure, and close to a stopped pipe
    /// with almost nothing above the third harmonic.
    public static let reedy = BlownTube(
        embouchure: 0.78, breathiness: 0.14, decay: 0.12, damping: 0.24
    )

    /// A loose reed on a long tube, dark and full of air.
    public static let hollow = BlownTube(
        embouchure: 0.22, breathiness: 0.3, decay: 0.2, damping: 0.62
    )
}
