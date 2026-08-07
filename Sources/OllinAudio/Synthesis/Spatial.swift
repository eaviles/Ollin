import AVFoundation
import Ollin

public extension Synth {
    /// Puts the instrument somewhere in the 3D scene, heard from a camera.
    ///
    /// ```swift
    /// override func draw() {
    ///     let eye = Camera3D.orbiting(distance: 6, angle: time * 0.3)
    ///     camera(eye)
    ///     synth.place(at: Vector3(2, 0, 0), heardFrom: eye)
    /// }
    /// ```
    ///
    /// Both facts are needed at once, which is why they arrive together: a
    /// position on its own says nothing until something is listening, and where
    /// the sketch is looking from is where it hears from. Called every frame, so
    /// a moving object or a moving camera both work.
    ///
    /// Sound placed this way is heard on headphones the way the ear works it
    /// out: how loud, how much later it reaches one ear than the other, and
    /// what a head does to the sound arriving round it. On speakers it is a
    /// plain left and right.
    ///
    /// The first call rebuilds the instrument's audio chain, so make it before
    /// the first note if you can. Once placed, an instrument stays placed;
    /// ``unplace()`` puts it back in the middle of the room.
    ///
    /// - Parameters:
    ///   - position: where the sound comes from, in the scene's own units.
    ///   - camera: where it is heard from. The camera's `eye`, what it is
    ///     looking at, and which way is up all matter.
    func place(at position: Vector3, heardFrom camera: Camera3D) {
        // While a sketch is being exported there is no engine to rewire, so the
        // placing is written down against the export clock the same way the
        // notes are, and applied when the soundtrack is rendered.
        guard !isRecordingForExport else {
            recordPlacement(at: position, camera: camera)
            return
        }
        spatial.place(at: position, camera: camera)
    }

    /// Where the instrument is, or nil if it has not been placed.
    var position: Vector3? {
        isRecordingForExport ? recordedPoses.last?.position : spatial.position
    }

    /// Takes the instrument out of the scene, so it is heard from everywhere at
    /// once again.
    func unplace() {
        guard !isRecordingForExport else {
            recordUnplaced()
            return
        }
        spatial.unplace()
    }

    /// How far away a sound has to be before it stops getting quieter, in scene
    /// units. Past this it holds its level rather than fading to nothing.
    var hearingRange: ClosedRange<Double> {
        get { placementRange }
        set {
            placementRange = newValue
            // Under an export there is no live environment node to tell; the
            // one the soundtrack is rendered through reads this when it is
            // built.
            guard !isRecordingForExport else { return }
            spatial.applyRange()
        }
    }
}

/// The placing side of a `Synth`, kept apart from the instrument itself.
///
/// Placing a sound is not a setting on the sound: it is a different shape of
/// audio graph. A sound that comes from somewhere has to arrive as one stream
/// and be turned into two by something that knows where the ears are, where an
/// ordinary instrument is already however many channels the output has. The two
/// cannot both be wired at once, so the chain is built the first time a sketch
/// asks for one.
@MainActor
final class SpatialPlacement {
    private let environment = AVAudioEnvironmentNode()
    private weak var owner: Synth?

    private(set) var position: Vector3?

    init(owner: Synth) {
        self.owner = owner
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.renderingAlgorithm = .auto
        applyRange()
    }

    /// Whether the instrument's chain has been rebuilt for placing.
    private(set) var isWired = false

    func place(at position: Vector3, camera: Camera3D) {
        self.position = position
        guard let owner else { return }
        if !isWired {
            owner.rewireForPlacement(environment)
            isWired = true
        }

        // The listener is the camera: where it is, what it is looking at, and
        // which way up it is holding its head.
        let listener = ListenerPose(camera)
        environment.listenerPosition = audioPoint(listener.eye)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: audioVector(listener.forward), up: audioVector(listener.up)
        )
        owner.spatialMixing?.position = audioPoint(position)
    }

    func unplace() {
        position = nil
        // Back in the middle of the listener's head, which is the same as not
        // being anywhere: equally in both ears and at full level.
        owner?.spatialMixing?.position = environment.listenerPosition
    }

    /// The instrument owns the range, so an export can read it without a live
    /// environment node having to exist.
    func applyRange() {
        let range = owner?.placementRange ?? 1...50
        applyHearingRange(range, to: environment)
    }
}

// MARK: - Shared with the export

/// Where a sketch was listening from, at one moment.
///
/// Kept as the three facts the listener is made of rather than as a `Camera3D`,
/// because that is all the placing uses and it makes a pose something two poses
/// can be compared for sameness.
struct ListenerPose: Equatable {
    var eye: Vector3
    var forward: Vector3
    var up: Vector3

    init(_ camera: Camera3D) {
        eye = camera.eye
        forward = normalizedDirection(camera.target - camera.eye)
        up = normalizedDirection(camera.up)
    }
}

/// Where an instrument was and where it was heard from, at one moment.
///
/// A nil `position` means the instrument was taken out of the scene, which is
/// the same as sitting in the middle of the listener's head.
struct RecordedPose: Equatable {
    var at: Double = 0
    var position: Vector3?
    var listener: ListenerPose

    /// Whether this pose puts the sound anywhere different from another. The
    /// time is deliberately left out: a sketch that places an instrument once
    /// and never moves it calls `place` every frame, and those are all one pose.
    func isSamePlacing(as other: RecordedPose) -> Bool {
        position == other.position && listener == other.listener
    }
}

func applyHearingRange(_ range: ClosedRange<Double>, to environment: AVAudioEnvironmentNode) {
    let parameters = environment.distanceAttenuationParameters
    parameters.referenceDistance = Float(max(0.01, range.lowerBound))
    parameters.maximumDistance = Float(max(range.lowerBound + 0.01, range.upperBound))
}

func audioPoint(_ value: Vector3) -> AVAudio3DPoint {
    AVAudio3DPoint(x: Float(value.x), y: Float(value.y), z: Float(value.z))
}

func audioVector(_ value: Vector3) -> AVAudio3DVector {
    AVAudio3DVector(x: Float(value.x), y: Float(value.y), z: Float(value.z))
}

func normalizedDirection(_ value: Vector3) -> Vector3 {
    let length = value.length
    return length > 1e-9 ? value / length : Vector3(0, 0, -1)
}

// MARK: - Writing the placing down

extension Synth {
    /// Writes down where the instrument is and where it is heard from.
    ///
    /// A sketch calls `place` every frame, so most of what arrives here is the
    /// pose that is already in force. Only a change is kept, which is what makes
    /// a still instrument cost one pose rather than one per frame.
    func recordPlacement(at position: Vector3, camera: Camera3D) {
        appendPose(RecordedPose(at: exportClock, position: position,
                                listener: ListenerPose(camera)))
    }

    /// Writes down that the instrument left the scene, keeping whatever the
    /// sketch was last listening from.
    func recordUnplaced() {
        guard let last = recordedPoses.last, last.position != nil else { return }
        appendPose(RecordedPose(at: exportClock, position: nil, listener: last.listener))
    }

    private func appendPose(_ pose: RecordedPose) {
        if let last = recordedPoses.last, last.isSamePlacing(as: pose) { return }
        // A sketch that moves an instrument every frame for an hour should not
        // grow without bound; past this it is a stuck loop rather than a walk.
        guard recordedPoses.count < 200_000 else { return }
        recordedPoses.append(pose)

        // The soundtrack is rendered while the frames are still being drawn, so
        // a move made after the machine was built has to reach it too.
        guard let offline else { return }
        // Unless the machine was built before the sketch had placed anything,
        // in which case it has no listener in it and never will: the chain is
        // fixed when it is built. Say so rather than exporting the sound in the
        // middle of the room and leaving it to be noticed.
        guard offline.canPlace else {
            audioNoteOnce("this instrument was placed after it had already started "
                          + "playing into the export, so the export cannot carry the "
                          + "placing; call place(at:heardFrom:) from the first frame "
                          + "to hear it where the sketch put it.")
            return
        }
        offline.pendingPoses.append(pose)
    }
}
