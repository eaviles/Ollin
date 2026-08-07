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
        spatial.place(at: position, camera: camera)
    }

    /// Where the instrument is, or nil if it has not been placed.
    var position: Vector3? { spatial.position }

    /// Takes the instrument out of the scene, so it is heard from everywhere at
    /// once again.
    func unplace() {
        spatial.unplace()
    }

    /// How far away a sound has to be before it stops getting quieter, in scene
    /// units. Past this it holds its level rather than fading to nothing.
    var hearingRange: ClosedRange<Double> {
        get { spatial.range }
        set { spatial.range = newValue }
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
    var range: ClosedRange<Double> = 1...50 {
        didSet { applyRange() }
    }

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
        let forward = normalized(camera.target - camera.eye)
        let up = normalized(camera.up)
        environment.listenerPosition = point(camera.eye)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: vector(forward), up: vector(up)
        )
        owner.spatialMixing?.position = point(position)
    }

    func unplace() {
        position = nil
        // Back in the middle of the listener's head, which is the same as not
        // being anywhere: equally in both ears and at full level.
        owner?.spatialMixing?.position = environment.listenerPosition
    }

    private func applyRange() {
        let parameters = environment.distanceAttenuationParameters
        parameters.referenceDistance = Float(max(0.01, range.lowerBound))
        parameters.maximumDistance = Float(max(range.lowerBound + 0.01, range.upperBound))
    }

    private func point(_ vector: Vector3) -> AVAudio3DPoint {
        AVAudio3DPoint(x: Float(vector.x), y: Float(vector.y), z: Float(vector.z))
    }

    private func vector(_ value: Vector3) -> AVAudio3DVector {
        AVAudio3DVector(x: Float(value.x), y: Float(value.y), z: Float(value.z))
    }

    private func normalized(_ value: Vector3) -> Vector3 {
        let length = value.length
        return length > 1e-9 ? value / length : Vector3(0, 0, -1)
    }
}
