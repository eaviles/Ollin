/// What a piece needs when it runs by itself: on a gallery wall, in a shop
/// window, on a screen at a stand for the length of a fair.
///
/// A sketch at a desk runs for a session, with somebody watching it. A sketch
/// on a wall runs for days, with nobody there, and a different set of things
/// can end it: the screen saver comes on, the display sleeps, somebody
/// unplugs a monitor and plugs it back in, the clock the shaders read runs
/// out of precision. Declaring an installation asks the framework to hold all
/// of that off:
///
/// ```swift
/// override var installation: Installation { .on }
/// ```
///
/// That fills the screen, hides the pointer, and keeps the display awake.
/// Build one by hand to change any part of it:
///
/// ```swift
/// override var installation: Installation {
///     Installation(fillsScreen: false)     // a window, but still left running
/// }
/// ```
///
/// The escape is always the usual one: Command-Q quits, whatever the piece
/// covers. See `Docs/Output/Installation.md`.
public struct Installation: Sendable, Equatable {

    /// A sketch run at a desk. The default: nothing is held off, and the
    /// window behaves like any other.
    public static let off = Installation(runsUnattended: false)

    /// A piece left running: the screen filled, the pointer gone, the display
    /// kept awake, and the clock kept honest.
    public static let on = Installation()

    /// Whether this sketch runs unattended. False only for ``off``: any
    /// installation you build by hand is one you mean to leave running.
    public private(set) var runsUnattended = true

    /// Whether the window covers its whole screen, with no title bar, and the
    /// menu bar and Dock stay out of the way.
    public var fillsScreen = true

    /// Whether the pointer is hidden while the piece runs. Nobody is holding
    /// the mouse, so an arrow parked over the work is only ever a blemish.
    public var hidesPointer = true

    /// Whether the display is kept awake and the screen saver held off, for as
    /// long as the piece runs. A piece nobody touches looks idle to the system,
    /// which is exactly when the screen goes dark.
    public var keepsDisplayAwake = true

    /// When the clock the shaders read starts over. See ``Clock``.
    public var clock: Clock = .automatic

    /// How often the run writes its state down, so a relaunch resumes rather
    /// than restarts. See ``Checkpointing``.
    public var checkpoint: Checkpointing = .off

    /// Whether a run that ends badly is started again. See ``Restarting``.
    public var restarts: Restarting = .never

    /// What the piece does at different times of day: the hours it is on
    /// screen, and the parts of the day it can behave differently in. See
    /// ``Schedule``.
    public var schedule: Schedule = .always

    /// When the clock a shader reads starts counting from zero again.
    ///
    /// A sketch reads `time` as a `Double`, which stays exact for centuries. A
    /// shader reads it as a 32-bit `float`, which does not: after a day of
    /// running, one frame's worth of time is at the limit of what that number
    /// can hold, and after a week the shader clock stops moving between frames
    /// altogether. Motion driven from the sketch keeps going; motion driven
    /// inside a shader judders, then freezes.
    ///
    /// Starting the clock over keeps it small enough to stay exact. The catch
    /// is that it is a jump, so it is only free when the piece repeats anyway.
    public enum Clock: Sendable, Equatable {
        /// Start over every whole loop, for a sketch that declares its
        /// ``Sketch/loopDuration``, and never for one that does not. The jump
        /// lands where the piece repeats, so nothing on screen moves.
        case automatic
        /// Never start over. Right for a run of hours, and for a piece whose
        /// shaders read `time` for something other than a phase.
        case continuous
        /// Start over every `seconds`, whatever the piece does. Pick a whole
        /// number of the periods the shaders animate on, or expect a visible
        /// jump each time.
        case restarting(every: Double)
    }

    /// How often a run writes its state down, and whether it does at all.
    ///
    /// The state is the seed, the clock, every `@Param` value, and every
    /// ``Saved`` property. A relaunch reads the file back and the piece carries
    /// on. What it cannot carry is anything living on the GPU: an accumulated
    /// canvas, a feedback layer, a simulation field.
    ///
    /// Off by default, even under ``on``, because restoring changes what a piece
    /// does on launch. That is exactly right for a wall and confusing at a desk,
    /// so it is asked for rather than assumed.
    public enum Checkpointing: Sendable, Equatable {
        /// Never write the state down. Every launch starts the piece over.
        case off
        /// Write it every `seconds`, and once more on the way out of an
        /// ordinary stop. A minute is a good number: the cost is one frame's
        /// worth of encoding, and the loss when the power goes is a minute.
        case every(seconds: Double)

        /// The cadence in seconds, or `nil` when nothing is written.
        var interval: Double? {
            if case .every(let seconds) = self, seconds > 0 { return seconds }
            return nil
        }
    }

    /// Whether the piece is started again when a run ends badly, and what
    /// counts as badly.
    ///
    /// Off by default, even under ``on``, for the reason the checkpoint is: it
    /// changes what happens when a run ends, which is exactly right on a wall
    /// and confusing at a desk. A piece that crashes while you are working on
    /// it should stay crashed, where you can read the error.
    ///
    /// It pairs with ``Checkpointing``. Starting the piece again is worth most
    /// when the piece comes back where it was rather than back at the start.
    public enum Restarting: Sendable, Equatable {
        /// Never. A run that ends, ends.
        case never
        /// Start the piece again after a crash, and after `stalledAfter`
        /// seconds with no answer from a piece that is still running.
        ///
        /// A run has to answer because a crash is not the only way a piece
        /// stops: a frame that never finishes leaves the process alive and the
        /// wall frozen. Zero seconds waits forever, for a piece that means to
        /// block.
        case onFailure(stalledAfter: Double)

        /// After a crash, and after half a minute with no answer.
        public static let onFailure = Restarting.onFailure(stalledAfter: 30)
    }

    public init(fillsScreen: Bool = true,
                hidesPointer: Bool = true,
                keepsDisplayAwake: Bool = true,
                clock: Clock = .automatic,
                checkpoint: Checkpointing = .off,
                restarts: Restarting = .never,
                schedule: Schedule = .always) {
        self.fillsScreen = fillsScreen
        self.hidesPointer = hidesPointer
        self.keepsDisplayAwake = keepsDisplayAwake
        self.clock = clock
        self.checkpoint = checkpoint
        self.restarts = restarts
        self.schedule = schedule
    }

    /// The private form behind ``off``, the one value that is not running.
    private init(runsUnattended: Bool) {
        self.runsUnattended = runsUnattended
    }

    /// What the run actually uses: what the sketch declares, unless the command
    /// line overrules it. `--installation` puts any sketch on a wall without
    /// editing it, and `--no-installation` gets an installation piece back into
    /// an ordinary window to work on it.
    @MainActor
    static func resolved(for sketch: Sketch,
                         arguments: [String] = CommandLine.arguments) -> Installation {
        if arguments.contains("--no-installation") { return .off }
        if arguments.contains("--installation") {
            return sketch.installation.runsUnattended ? sketch.installation : .on
        }
        return sketch.installation
    }

    /// How many seconds the shader clock runs before it starts over, resolved
    /// against the sketch's own declared loop. `nil` means it never does.
    ///
    /// Under ``Clock/automatic`` the period is the loop itself, so a shader's
    /// phase lands exactly where it started. The loop is repeated up to a
    /// thousand seconds first, so a short loop does not restart the clock
    /// hundreds of times an hour for no reason.
    func clockPeriod(loopDuration: Double?) -> Double? {
        switch clock {
        case .continuous:
            return nil
        case .restarting(let seconds):
            return seconds > 0 ? seconds : nil
        case .automatic:
            guard runsUnattended, let loop = loopDuration, loop > 0 else { return nil }
            let laps = Swift.max(1, (1000 / loop).rounded(.down))
            return loop * laps
        }
    }
}
