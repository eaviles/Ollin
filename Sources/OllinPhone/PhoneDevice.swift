import Foundation
import CoreGraphics
import simd
import os
import Ollin
import OllinUSBMux
#if canImport(Darwin)
import Darwin
#endif

/// A live sensor stream from a tethered iPhone running the **Ollin** capture app
/// (Apps/OllinPhoneApp) — the phone runs ARKit on its own Neural Engine and streams
/// typed results the Mac reads in `draw()`: a 3D **body skeleton**, a **face** (the
/// deforming mesh + the 52 expression blendshapes), the **hands** in view (21-joint
/// skeletons, lifted to metric 3D on a LiDAR phone), the **text** it can read in
/// the scene (each line with its corners, lifted the same way), a world-facing
/// **RGBD depth frame** from the rear LiDAR, and **device motion**.
///
/// ```swift
/// let device = PhoneDevice()
/// override func setup() { device.start() }
/// override func draw() {
///     guard let body = device.latestBody else {
///         return drawStatus(device.waitingMessage, style: .info)
///     }
///     camera(.orbiting(target: body.center, radius: 2.5, azimuth: time * 0.3))
///     drawPointCloud(body.cloud())
/// }
/// ```
///
/// In **World** mode the capture app streams a world-facing RGBD frame from the
/// rear LiDAR instead: `latestFrame` / `pointCloud(...)` unproject it into a
/// colored cloud, and each frame's `latestPose` carries the 6DoF camera transform
/// for world fusion. The device is also a `FrameSource` + `VideoFeed`, so a vision
/// tracker can analyze the depth-mode color feed and `drawFrame` can letterbox it.
///
/// In **Room** mode the phone reconstructs the room as a triangle surface and sends
/// it block by block: `sceneMesh` is the room built up so far, ready to draw as one
/// `Mesh`, with every triangle labeled as a wall, the floor, a table, and so on.
/// The same mode reports the flat surfaces it finds, which is the short summary of
/// that room: `planes` holds a floor, a table top, or a wall as an outline to stand
/// something on or hang something from, and it needs no LiDAR.
///
/// In **Markers** mode the phone looks for pictures and scanned objects it has been
/// given, and reports each one it finds: `latestMarkers` carries a name, a placement
/// in the room, and the thing's real size, so a sketch stands on a printed picture.
///
/// In **Wand** mode the phone becomes a pointer rather than an observer:
/// `latestWand` carries where it is, which way it points, and what the thumb is
/// doing on the screen, so a sketch can be pointed at and pressed. It runs on plain
/// world tracking, so it needs no LiDAR.
///
/// In **Attention** mode the phone maps where its picture draws the eye:
/// `latestSaliency` carries a coarse heat map and the regions it peaks in,
/// `latestSaliencyHeatMap` the tintable glow, and `latestSaliencyFrame` the
/// camera frame they were read from.
///
/// `latestLight` says how bright and how warm the room is. It arrives in every mode,
/// so a sketch can match the light it is standing in.
///
/// Launch the Ollin capture app on the iPhone and connect the cable; the device
/// keeps retrying, so plugging in or starting the app mid-run just works. The
/// transport is the standard `usbmuxd` tunnel (port 1338); the wire format is
/// Ollin's own (`PhoneWire`).
@MainActor
public final class PhoneDevice: FrameSource, VideoFeed {

    /// The TCP port the Ollin capture app listens on (tunnelled via usbmuxd) —
    /// defined once in `PhoneWire` so both ends agree.
    public nonisolated static let streamPort: UInt16 = PhoneWire.streamPort

    private let reader: PhoneStreamReader

    // Build the drawable `RGBDFrame` lazily and cache it by the box's sequence, so
    // repeated reads in one `draw()` (frame, frameSize, pointCloud) reuse it.
    private var cachedSequence: Int?
    private var cachedFrame: RGBDFrame?

    // The segmentation matte and cutout are built lazily and cached independently by
    // sequence — so a sketch reading only the matte never pays to build the cutout
    // (the accessor itself is the arm; building runs here on the main actor, not on
    // the reader thread, so an unread surface is never produced).
    private var cachedSegMatteSequence: Int?
    private var cachedSegMatte: Image?
    private var cachedSegCutoutSequence: Int?
    private var cachedSegCutout: Image?

    // The attention heat map and its color frame, cached the same way: a sketch
    // reading only the regions or the salience query never builds either image.
    private var cachedSaliencyHeatSequence: Int?
    private var cachedSaliencyHeat: Image?
    private var cachedSaliencyFrameSequence: Int?
    private var cachedSaliencyFrame: Image?

    /// Create a device bound to the capture app's stream port.
    public init(port: UInt16 = PhoneDevice.streamPort) {
        reader = PhoneStreamReader(port: port)
    }

    /// Begin connecting and streaming. Safe to call once; the reader retries on its
    /// own until the phone is attached and the app is serving.
    public func start() { reader.start() }

    /// Stop streaming and close the connection. Safe to call when not started.
    public func stop() { reader.stop() }

    /// Whether sensor frames are currently arriving from the phone.
    public var isStreaming: Bool { reader.isConnected }

    /// Every body the phone is tracking, newest set each frame, empty before any
    /// arrive or when nobody is in view. ARKit follows one body today; the list
    /// keeps the surface ready if that grows. Populated in **Body** mode (rear
    /// camera).
    public var latestBodies: [PhoneBody] { reader.latestPoses.map(PhoneBody.init) }

    /// The tracked body, the first of `latestBodies`, or `nil` when nobody is in
    /// view. A fresh value each time the phone sends a pose; read it within the
    /// current `draw()`.
    public var latestBody: PhoneBody? { latestBodies.first }

    /// Every face the phone is tracking — each with mesh, blendshapes, and head pose
    /// — newest set each frame, empty before any arrive or when no face is in view.
    /// The front TrueDepth camera tracks up to 3 faces at once. Populated in **Face**
    /// mode (front camera); body and face are mutually exclusive, so only one of
    /// `latestBody`/`latestFaces` updates at a time.
    public var latestFaces: [PhoneFace] { reader.latestFaces.map(PhoneFace.init) }

    /// The most prominent tracked face — the first of `latestFaces` — or `nil` when
    /// none is in view. The convenience for the common single-person case; read
    /// `latestFaces` to handle several people at once.
    public var latestFace: PhoneFace? { latestFaces.first }

    /// Every hand the phone currently sees (up to 4), newest set each frame, empty
    /// before any arrive or when no hand is in view. Populated in **Hands** mode
    /// (rear camera): each is a 21-joint skeleton with upright 2D image points,
    /// and on a LiDAR phone each joint also carries a metric 3D position in ARKit
    /// world space, lifted through the depth map and the camera pose.
    public var latestHands: [PhoneHand] { reader.latestHands.map(PhoneHand.init) }

    /// The most confident hand in view, or `nil` when none is: the convenience for
    /// the common one-hand case; read `latestHands` to handle several at once.
    public var latestHand: PhoneHand? {
        latestHands.max { $0.confidence < $1.confidence }
    }

    /// Every line of text the phone can currently read, newest set each frame,
    /// empty before any arrive or when none is in view. Populated in **Text** mode
    /// (rear camera): each line carries what it says, the reader's confidence, and
    /// its four corners as upright 2D image points; on a LiDAR phone the corners
    /// also lift to metric 3D in ARKit world space, so a sign stands where it
    /// hangs in the room.
    public var latestTexts: [PhoneText] { reader.latestTexts.map(PhoneText.init) }

    /// The line filling the most of the picture, or `nil` when none is in view:
    /// the convenience for the common one-sign case (a frame of readable text is
    /// usually one big line and several small ones). Read `latestTexts` for all
    /// of them.
    public var latestText: PhoneText? {
        latestTexts.max { $0.imageArea < $1.imageArea }
    }

    /// Every picture and object the phone knows and can currently see, newest set
    /// each frame, empty before any arrive or when none is in view. Populated in
    /// **Markers** mode (rear camera): the phone holds a library of reference
    /// pictures and scanned objects, and reports each one it finds as a named 6DoF
    /// placement in ARKit world space with the thing's real size in meters.
    ///
    /// A picture that has left the view stays in the list with `isTracked` off,
    /// holding its last placement, so a sketch decides whether to keep drawing on it.
    public var latestMarkers: [PhoneMarker] { reader.latestMarkers.map(PhoneMarker.init) }

    /// The marker with this name, or `nil` when the phone is not seeing it. The
    /// name is the reference file's own name without its extension or its stated
    /// size, so `poster@30cm.png` on the phone is `device.marker(named: "poster")`.
    /// A marker being followed wins over one that has left the view.
    public func marker(named name: String) -> PhoneMarker? {
        let matches = latestMarkers.filter { $0.name == name }
        return matches.first(where: \.isTracked) ?? matches.first
    }

    /// The biggest marker the phone is following, or `nil` when it is following
    /// none: the convenience for the common one-picture case. Read `latestMarkers`
    /// to handle several at once.
    public var latestMarker: PhoneMarker? {
        let followed = latestMarkers.filter(\.isTracked)
        return followed.max { a, b in a.width * a.height < b.width * b.height }
    }

    /// The phone held as a pointer, or `nil` before a reading arrives. Populated in
    /// **Wand** mode (rear camera, plain world tracking, so it needs no LiDAR).
    ///
    /// It carries where the phone is, which way it points, and what the thumb is
    /// doing on the screen. `ray` runs out of the back of the phone, so a sketch
    /// asks it what the person is pointing at.
    public var latestWand: PhoneWand? { reader.latestWand.map(PhoneWand.init) }

    /// The latest CoreMotion sample, or `nil` before one arrives — the cheap
    /// transport smoke-test (it moves the moment the wire is alive, before ARKit
    /// has found a body).
    public var latestMotion: PhoneMotion? { reader.latestMotion.map(PhoneMotion.init) }

    // MARK: - World mode (rear LiDAR RGBD)

    /// The latest world-facing RGBD frame, or `nil` before one arrives. Populated
    /// when the capture app is in **World** mode (rear LiDAR); body/face modes don't
    /// produce depth. A fresh frame each time the phone sends one — read it within
    /// the current `draw()`.
    public var latestFrame: RGBDFrame? {
        guard let box = reader.latestDepth else { return nil }
        if cachedSequence == box.sequence, let cachedFrame { return cachedFrame }
        let frame = RGBDFrame(color: Image(cgImage: box.color), depth: box.depth,
                              confidence: box.confidence, depthWidth: box.depthWidth,
                              depthHeight: box.depthHeight, intrinsics: box.intrinsics)
        cachedSequence = box.sequence
        cachedFrame = frame
        return frame
    }

    /// Unproject the latest depth frame into a `PointCloud` (see `RGBDFrame.pointCloud`
    /// for the parameters). `nil` until the first World-mode frame arrives. The rear
    /// LiDAR reaches across a room, so the defaults open the depth range up.
    public func pointCloud(minConfidence: DepthConfidence = .medium,
                           depthRange: ClosedRange<Double>? = nil,
                           step: Int = 1,
                           pointSize: Double = 0.009) -> PointCloud? {
        latestFrame?.pointCloud(minConfidence: minConfidence, depthRange: depthRange,
                                     step: step, pointSize: pointSize)
    }

    /// The 6DoF camera pose of the latest World-mode frame (ARKit's camera→world
    /// `simd_float4x4`), or `nil` before one arrives. ARKit's world is fixed and
    /// gravity-aligned, so transforming a frame's camera-space cloud by this pose
    /// places it where it really is in the room — feed both to a `WorldCloud` to
    /// fuse a sweep of frames into one scene (see `PointCloud.transformed(by:)`).
    public var latestPose: simd_float4x4? { reader.latestPose3D }

    /// An identifier that changes whenever a new World-mode depth frame arrives —
    /// the frame's stream sequence number. `draw()` runs faster than depth frames
    /// stream in, so a fusion sketch compares this against the last value it fused
    /// to add each frame exactly once. `nil` before the first frame.
    public var latestFrameVersion: Int? { reader.latestDepth?.sequence }

    // MARK: - Segment and Selfie modes (person segmentation)

    /// The latest person-segmentation matte as a tintable white-alpha `Image`, or
    /// `nil` before one arrives. Populated when the capture app is in **Segment**
    /// mode (rear camera, ARKit's on-device person segmentation) or **Selfie** mode
    /// (front camera, a Vision pass; the feed arrives mirrored, like the phone's own
    /// front-camera preview). Drawn as-is it's a
    /// white silhouette; `tint(_:)` recolors it into a shadow, glow, or solid fill.
    /// Draw it into the same rectangle as the color feed and it lines up.
    public var latestSegmentationMatte: Image? {
        guard let box = reader.latestSegmentation else { return nil }
        if cachedSegMatteSequence == box.sequence, let cachedSegMatte { return cachedSegMatte }
        let matte = SegmentationImages.matteImage(from: box.matte)
        cachedSegMatteSequence = box.sequence
        cachedSegMatte = matte
        return matte
    }

    /// The latest person **cutout**, the camera frame's pixels where the matte is on
    /// and transparent elsewhere, or `nil` before a Segment- or Selfie-mode frame
    /// arrives.
    /// The person lifted off the background, ready to composite over anything you
    /// draw. Costs a little more than the matte (the color is masked), so it's built
    /// only when read.
    public var latestSegmentationCutout: Image? {
        guard let box = reader.latestSegmentation else { return nil }
        if cachedSegCutoutSequence == box.sequence, let cachedSegCutout { return cachedSegCutout }
        // Rotate the full-resolution color upright only now, when the cutout is
        // actually read (the matte was rotated upright at decode time); both use the
        // same quarter-turn count, so they stay aligned.
        let color = rotatedCGImage(box.color, quarterTurnsCW: box.orientation) ?? box.color
        let cutout = SegmentationImages.cutoutImage(frame: color, matte: box.matte)
        cachedSegCutoutSequence = box.sequence
        cachedSegCutout = cutout
        return cutout
    }

    // MARK: - Attention mode (where the picture draws the eye)

    /// The latest reading of where the phone's picture draws the eye, or `nil`
    /// before one arrives. Populated in **Attention** mode (rear camera): the
    /// phone runs the attention model on its own Neural Engine and streams the
    /// coarse heat map plus the regions it peaks in. `salience(at:in:)` reads the
    /// value under any canvas point; on a LiDAR phone each region's center also
    /// stands in ARKit world space.
    public var latestSaliency: PhoneSaliency? {
        reader.latestSaliency.map { PhoneSaliency($0.sample) }
    }

    /// The latest attention heat map as a tintable white-alpha `Image`, or `nil`
    /// before an Attention-mode reading arrives. Drawn as-is it is a white glow
    /// where the eye goes; `tint(_:)` recolors it into a spotlight, a fog, a
    /// warm haze. Draw it into the same rectangle as `latestSaliencyFrame` and
    /// it lines up. Coarse on purpose (the model's own resolution): stretching
    /// it over the frame is how it is meant to be used.
    public var latestSaliencyHeatMap: Image? {
        guard let box = reader.latestSaliency else { return nil }
        if cachedSaliencyHeatSequence == box.sequence, let cachedSaliencyHeat {
            return cachedSaliencyHeat
        }
        let sample = box.sample
        guard let gray = SegmentationImages.grayCGImage(fromPlane: sample.heat,
                                                        width: sample.heatWidth,
                                                        height: sample.heatHeight),
              let heat = SegmentationImages.matteImage(from: gray) else { return nil }
        cachedSaliencyHeatSequence = box.sequence
        cachedSaliencyHeat = heat
        return heat
    }

    /// The camera frame the latest attention reading was made from, upright for
    /// how the phone was held, or `nil` before one arrives. The backdrop to draw
    /// the heat map and the region boxes over; built only when read.
    public var latestSaliencyFrame: Image? {
        guard let box = reader.latestSaliency, let color = box.color else { return nil }
        if cachedSaliencyFrameSequence == box.sequence, let cachedSaliencyFrame {
            return cachedSaliencyFrame
        }
        let upright = rotatedCGImage(color, quarterTurnsCW: Int(box.sample.orientation)) ?? color
        let frame = Image(cgImage: upright)
        cachedSaliencyFrameSequence = box.sequence
        cachedSaliencyFrame = frame
        return frame
    }

    // MARK: - Room mode (the reconstructed room surface)

    /// The room the phone has reconstructed so far, as a growing set of triangle
    /// blocks. Populated when the capture app is in **Room** mode (rear LiDAR): the
    /// phone builds a real surface of the space on its own Neural Engine and streams
    /// it block by block, sharpening as you walk around.
    ///
    /// Building its combined `mesh` walks the whole room, so gate the rebuild on
    /// `sceneMeshVersion` instead of doing it every frame.
    public var sceneMesh: PhoneSceneMesh { reader.sceneMesh }

    /// A number that changes whenever a block of the room arrives or is retired.
    /// The room mesh is large and `draw()` runs far faster than blocks stream in, so
    /// compare this against the last value you built from and rebuild only when it
    /// moves. `nil` before the first block arrives.
    public var sceneMeshVersion: Int? { reader.sceneMeshVersion }

    /// Forget the scanned room and start collecting it again. The phone keeps its
    /// own reconstruction, so blocks return as it re-reports them; this clears what
    /// the Mac is holding, which is what a sketch wants when it starts a new scan.
    public func resetSceneMesh() { reader.resetSceneMesh() }

    /// The flat surfaces the phone has found so far: a floor, a table top, a wall,
    /// each as a labeled outline placed in the room. Populated in **Room** mode
    /// beside the reconstructed surface, and unlike that surface it needs no LiDAR,
    /// so it fills in on any phone that runs the capture app.
    ///
    /// A surface grows as the phone sees more of it, so read it fresh each frame
    /// rather than holding on to one.
    public var planes: PhonePlanes { reader.planes }

    /// A number that changes whenever a surface arrives, grows, or is retired.
    /// Compare it against the last value you built from to rebuild only on a change.
    /// `nil` before the first surface arrives.
    public var planesVersion: Int? { reader.planesVersion }

    /// Forget the flat surfaces found so far and start collecting them again. The
    /// phone keeps its own, so they return as it re-reports them.
    public func resetPlanes() { reader.resetPlanes() }

    // MARK: - The room's light (every mode)

    /// How bright and how warm the room is, or `nil` before the first reading. The
    /// phone measures this from its camera image in **every** mode, a few times a
    /// second, so a sketch can light itself the way the room is lit.
    ///
    /// In **Face** mode it also carries the direction the strongest light comes
    /// from, which ARKit reads off the face itself.
    public var latestLight: PhoneLight? { reader.latestLight.map(PhoneLight.init) }

    // MARK: - FrameSource / VideoFeed (the World-mode color feed)

    /// The analysis tap (`FrameSource`): the live color frame, delivered on the
    /// reader thread so a vision tracker can run over the phone's World-mode camera.
    public var frameTap: FrameTap? {
        didSet { reader.setTap(frameTap) }
    }

    /// The latest World-mode color frame as a drawable `Image` (`VideoFeed`).
    public var frame: Image? { latestFrame?.color }

    /// The pixel size of the latest World-mode color frame (`VideoFeed`).
    public var frameSize: Vector2? {
        guard let box = reader.latestDepth else { return nil }
        return Vector2(Double(box.color.width), Double(box.color.height))
    }

    /// The notice to show before frames arrive — reflects the live connection state
    /// (no device, refused, reconnecting).
    public var waitingMessage: String { reader.statusMessage ?? "Connecting to the phone…" }
}

/// Owns the usbmuxd connection and the background read loop, decoding framed
/// messages off the main thread and handing the latest of each kind across a lock —
/// a serial-producer / locked-reader model.
/// `@unchecked Sendable`: its mutable state lives behind the lock, and the read
/// thread touches nothing main-actor-isolated (the executor-assertion lesson).
final class PhoneStreamReader: @unchecked Sendable {

    private struct State {
        var latestPoses: [PhonePoseSample] = []
        var latestFaces: [PhoneFaceSample] = []
        var latestHands: [PhoneHandSample] = []
        var latestTexts: [PhoneTextSample] = []
        var latestMarkers: [PhoneMarkerSample] = []
        var latestWand: PhoneWandSample?
        var latestMotion: PhoneMotionSample?
        var latestDepth: PhoneDepthFrameBox?
        var depthSequence = 0
        var latestSegmentation: PhoneSegmentationBox?
        var segSequence = 0
        var latestSaliency: PhoneSaliencyBox?
        var saliencySequence = 0
        var sceneMesh = PhoneSceneMesh()
        var sceneMeshVersion: Int?
        var sceneMeshScan: UInt32?
        var planes = PhonePlanes()
        var planesVersion: Int?
        var planesScan: UInt32?
        var latestLight: PhoneLightSample?
        var tap: FrameTap?
        var connected = false
        var message: String? = "Connecting to the phone…"
        var running = false
        var fd: Int32 = -1
    }

    private let port: UInt16
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    init(port: UInt16) { self.port = port }

    // MARK: Public surface (read from the main actor)

    var latestPoses: [PhonePoseSample] { lock.withLock { $0.latestPoses } }
    var latestFaces: [PhoneFaceSample] { lock.withLock { $0.latestFaces } }
    var latestHands: [PhoneHandSample] { lock.withLock { $0.latestHands } }
    var latestTexts: [PhoneTextSample] { lock.withLock { $0.latestTexts } }
    var latestMarkers: [PhoneMarkerSample] { lock.withLock { $0.latestMarkers } }
    var latestWand: PhoneWandSample? { lock.withLock { $0.latestWand } }
    var latestMotion: PhoneMotionSample? { lock.withLock { $0.latestMotion } }
    var latestDepth: PhoneDepthFrameBox? { lock.withLock { $0.latestDepth } }
    var latestSegmentation: PhoneSegmentationBox? { lock.withLock { $0.latestSegmentation } }
    var latestSaliency: PhoneSaliencyBox? { lock.withLock { $0.latestSaliency } }
    var latestPose3D: simd_float4x4? { lock.withLock { $0.latestDepth?.transform } }
    var sceneMesh: PhoneSceneMesh { lock.withLock { $0.sceneMesh } }
    var sceneMeshVersion: Int? { lock.withLock { $0.sceneMeshVersion } }
    var planes: PhonePlanes { lock.withLock { $0.planes } }
    var planesVersion: Int? { lock.withLock { $0.planesVersion } }
    var latestLight: PhoneLightSample? { lock.withLock { $0.latestLight } }
    var isConnected: Bool { lock.withLock { $0.connected } }
    var statusMessage: String? { lock.withLock { $0.message } }

    func setTap(_ tap: FrameTap?) { lock.withLock { $0.tap = tap } }

    func resetSceneMesh() {
        lock.withLock { state in
            state.sceneMesh.reset()
            state.sceneMeshVersion = (state.sceneMeshVersion ?? 0) + 1
        }
    }

    func resetPlanes() {
        lock.withLock { state in
            state.planes.reset()
            state.planesVersion = (state.planesVersion ?? 0) + 1
        }
    }

    func start() {
        let alreadyRunning = lock.withLock { state -> Bool in
            if state.running { return true }
            state.running = true
            return false
        }
        guard !alreadyRunning else { return }
        Thread.detachNewThread { [weak self] in self?.run() }
    }

    func stop() {
        let fd = lock.withLock { state -> Int32 in
            state.running = false
            let fd = state.fd
            state.fd = -1
            state.connected = false
            return fd
        }
        if fd >= 0 { close(fd) }   // breaks a blocking read
    }

    // MARK: Background loop

    private var isRunning: Bool { lock.withLock { $0.running } }

    private func run() {
        while isRunning {
            let fd: Int32
            do {
                fd = try USBMux.connect(toPort: port)
            } catch {
                lock.withLock { $0.connected = false; $0.message = Self.message(for: error) }
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }
            // A read timeout so the loop re-checks `running` even when frames stall.
            var tv = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            lock.withLock { $0.fd = fd; $0.connected = true; $0.message = nil }

            readLoop: while isRunning {
                switch readMessage(fd) {
                case .message(.depth(let sample)):
                    // Decode the RGBD frame (JPEG + intrinsics) on this thread, off
                    // the main actor (the executor-assertion lesson), then fire the
                    // FrameSource tap with the color image.
                    let seq = lock.withLock { state -> Int in state.depthSequence += 1; return state.depthSequence }
                    if let box = decodePhoneDepth(sample, sequence: seq) {
                        let tap = lock.withLock { state -> FrameTap? in
                            state.latestDepth = box
                            return state.tap
                        }
                        tap?(box.color)
                    }
                case .message(.segmentation(let sample)):
                    // JPEG-decode the color on this thread (off the main actor), then
                    // store the boxed frame; the matte/cutout images are built lazily
                    // on the main actor when the sketch reads them.
                    let seq = lock.withLock { state -> Int in state.segSequence += 1; return state.segSequence }
                    if let box = decodePhoneSegmentation(sample, sequence: seq) {
                        lock.withLock { $0.latestSegmentation = box }
                    }
                case .message(.saliency(let sample)):
                    // JPEG-decode the color on this thread (off the main actor), then
                    // store the boxed reading; the heat-map and frame images are built
                    // lazily on the main actor when the sketch reads them.
                    let seq = lock.withLock { state -> Int in state.saliencySequence += 1; return state.saliencySequence }
                    if let box = decodePhoneSaliency(sample, sequence: seq) {
                        lock.withLock { $0.latestSaliency = box }
                    }
                case .message(.sceneMesh(let sample)):
                    // Place the block into world space on this thread, off the main
                    // actor and outside the lock (a block carries thousands of
                    // vertices, and the lock is held by every read in draw()).
                    let chunk = sample.isRemoved ? nil : phoneSceneChunk(from: sample)
                    guard sample.isRemoved || chunk != nil else { continue }
                    lock.withLock { state in
                        // A new run of the scanner resets the phone's world origin,
                        // so blocks from the run before it are in a space that no
                        // longer exists. Drop the old room rather than mixing them.
                        if state.sceneMeshScan != sample.scan {
                            state.sceneMeshScan = sample.scan
                            state.sceneMesh.reset()
                        }
                        if let chunk {
                            state.sceneMesh.apply(chunk)
                        } else {
                            state.sceneMesh.remove(sample.id)
                        }
                        state.sceneMeshVersion = (state.sceneMeshVersion ?? 0) + 1
                    }
                case .message(.plane(let sample)):
                    // Place the surface into world space on this thread, off the main
                    // actor and outside the lock, the way a mesh block is.
                    let plane = sample.isRemoved ? nil : phonePlane(from: sample)
                    guard sample.isRemoved || plane != nil else { continue }
                    lock.withLock { state in
                        // A new run of the scanner moves the world origin, so surfaces
                        // from the run before it describe a space that is gone.
                        if state.planesScan != sample.scan {
                            state.planesScan = sample.scan
                            state.planes.reset()
                        }
                        if let plane {
                            state.planes.apply(plane)
                        } else {
                            state.planes.remove(sample.id)
                        }
                        state.planesVersion = (state.planesVersion ?? 0) + 1
                    }
                case .message(let message):
                    lock.withLock { state in
                        switch message {
                        case .motion(let m): state.latestMotion = m
                        case .pose(let p): state.latestPoses = p
                        case .face(let f): state.latestFaces = f
                        case .hands(let h): state.latestHands = h
                        case .texts(let t): state.latestTexts = t
                        case .markers(let m): state.latestMarkers = m
                        case .wand(let w): state.latestWand = w
                        case .light(let l): state.latestLight = l
                        case .depth, .segmentation, .saliency, .sceneMesh, .plane: break   // handled above
                        }
                    }
                case .skip:
                    continue            // a bad frame, but the stream is still in sync
                case .desync:
                    break readLoop      // framing lost — drop and reconnect
                }
            }

            // Close the fd only if it's still ours. If stop() already reset
            // state.fd and closed it, an unconditional close here would
            // double-close a descriptor another thread may have reused
            // (mirrors stop()'s own guard).
            let stillOurs = lock.withLock { state -> Bool in
                let stillOurs = state.fd == fd
                if stillOurs { state.fd = -1 }
                state.connected = false
                if state.running { state.message = "Reconnecting to the phone…" }
                return stillOurs
            }
            if stillOurs { close(fd) }
            if isRunning { Thread.sleep(forTimeInterval: 0.5) }
        }
    }

    private enum ReadOutcome { case message(PhoneMessage), skip, desync }

    private func readMessage(_ fd: Int32) -> ReadOutcome {
        let headerData = USBMux.readFully(fd, PhoneWire.headerByteCount)
        guard headerData.count == PhoneWire.headerByteCount,
              let header = PhoneHeader.parse(headerData) else { return .desync }

        let payload = header.payloadLength > 0
            ? USBMux.readFully(fd, header.payloadLength) : Data()
        guard payload.count == header.payloadLength else { return .desync }

        guard let message = PhoneWire.decode(header: header, payload: payload) else { return .skip }
        return .message(message)
    }

    private static func message(for error: Error) -> String {
        guard let muxError = error as? USBMux.USBMuxError else { return "\(error)" }
        switch muxError {
        case .noDevice:
            return "Connect an iPhone over USB."
        case .socketUnavailable:
            return "Can't reach the USB service (usbmuxd)."
        case .connectFailed(3):
            return "Launch the Ollin capture app on the iPhone."
        case .connectFailed, .handshakeFailed:
            return "Waiting for the Ollin capture stream…"
        }
    }
}
