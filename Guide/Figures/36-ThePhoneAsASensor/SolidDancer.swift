// figure: frame=38
//
// Guide payoff (Chapter 36): the dancer in solids. A person's pose drawn as
// lit capsules and a head standing on a floor, seen from an angle the film
// never had, with a fading trail behind each hand and foot. The sketch takes
// its body from the phone when one is streaming and from the film that ships
// with Ollin when none is: the Mac's 3D body tracker reads the dancer out of
// the flat picture as the same bones, in meters, that the phone sends, so one
// drawing serves both. Here the film is stepped one of its own frames at a
// time from 7 seconds in, and each frame is measured with the one-shot body
// request, so the figure renders the same everywhere. Live, the film plays
// and the sketch reads `tracker.body`, a BodyTracker3D on it. At frame 38 the
// dancer is in a wide lunge with one arm swept overhead, and the orange trail
// shows the path that arm took to get there.
import Ollin
import OllinPhone
import OllinSamplePhotos
import OllinVideo
import OllinVision

final class SolidDancer: Sketch {
    let device = PhoneDevice()
    let stage = StageDancer(from: 7)

    let bodyColor = Color(hex: 0xEDE7DA)
    let handColor = Color(hex: 0xF2A65A)
    let footColor = Color(hex: 0x6C8CD5)
    let floorColor = Color(hex: 0x23262E)

    /// Where each hand and foot has been, oldest first: left hand, right hand,
    /// left foot, right foot.
    var trails: [[Vector3]] = [[], [], [], []]

    override func setup() {
        device.start()                   // the phone, if one is streaming
    }

    override func draw() {
        background(Color(hex: 0x0E1016))
        camera(.orbiting(target: Vector3(0, 0.85, 0), radius: 4.4,
                         azimuth: 0.9 + time * 0.12, elevation: 0.22,
                         fieldOfView: .pi / 4.5))
        lightingPreset(.studio)
        castShadows()

        material(.matte)
        fill(floorColor)
        drawPlane(width: 12, depth: 12)

        // The phone's body when a phone streams, the film's otherwise.
        // Live, the film's comes from `tracker.body`.
        var person: Person?
        var fromFilm = false
        if let body = device.latestBody {
            person = Person(body)
        } else if let body = stage.step() {
            person = Person(body)
            fromFilm = true
        }
        guard let person else { return }

        // Stand the figure on the floor: lift it until its lowest point sits
        // one capsule radius above y = 0.
        let radius = 0.035
        let lowest = person.bones.map { min($0.0.y, $0.1.y) }.min() ?? 0
        let up = Vector3(0, radius - lowest, 0)

        material(.clay)
        fill(bodyColor)
        for (a, b) in person.bones {
            drawCapsule(from: a + up, to: b + up, radius: radius)
        }
        withState {
            translate(person.head + up)
            drawSphere(radius: 0.11)
        }

        // Each hand and foot leaves a trail that thins and darkens with age.
        for (i, end) in person.ends.enumerated() {
            let p = end + up
            if trails[i].last.map({ $0.distance(to: p) > 0.002 }) ?? true {
                trails[i].append(p)
            }
            if trails[i].count > 36 { trails[i].removeFirst() }
        }
        for (i, trail) in trails.enumerated() {
            let color = i < 2 ? handColor : footColor
            for k in 1 ..< trail.count {
                let t = Double(k) / Double(trail.count)        // near 0 oldest, 1 newest
                fill(color.mixed(with: floorColor, 1 - t))
                drawCapsule(from: trail[k - 1], to: trail[k], radius: 0.006 + 0.018 * t)
            }
        }

        // The flat film the dancer was lifted out of, in the corner.
        // Live, `drawFrame(film, in: corner)`.
        if fromFilm, let picture = stage.lastFrame {
            let corner = Rectangle(x: 28, y: 28, width: 200, height: 200)
            drawImage(picture, in: corner)
        }
    }
}

/// One body from either source, in the phone's terms: meters, the root at the
/// origin, y up, and z toward the camera.
struct Person {
    var bones: [(Vector3, Vector3)]
    var head: Vector3
    /// Left hand, right hand, left foot, right foot.
    var ends: [Vector3]

    init?(_ body: PhoneBody) {
        guard let head = body.position(.head),
              let leftHand = body.position(.leftHand),
              let rightHand = body.position(.rightHand),
              let leftFoot = body.position(.leftFoot),
              let rightFoot = body.position(.rightFoot)
        else { return nil }
        bones = body.bones()
        self.head = head
        ends = [leftHand, rightHand, leftFoot, rightFoot]
    }

    init?(_ body: Body3D) {
        // The film's body counts z away from the camera. Turning z around
        // makes it face the camera the way the phone's body does.
        func facing(_ p: Vector3) -> Vector3 { Vector3(p.x, p.y, -p.z) }
        guard let head = body.position(.centerHead),
              let leftHand = body.position(.leftWrist),
              let rightHand = body.position(.rightWrist),
              let leftFoot = body.position(.leftAnkle),
              let rightFoot = body.position(.rightAnkle)
        else { return nil }
        bones = body.bones().map { (facing($0.0), facing($0.1)) }
        self.head = facing(head)
        ends = [leftHand, rightHand, leftFoot, rightFoot].map(facing)
    }
}

/// The film, stepped one of its own frames at a time from `start` seconds in,
/// with the dancer measured on each frame by the one-shot 3D body request.
/// `step()` returns the same `Body3D` a live `BodyTracker3D` publishes; only
/// the timing has changed, so the figure renders the same everywhere.
@MainActor
final class StageDancer {
    private let clip = try! VideoPlayer(url: SampleClip.dance.url)
    private let start: Double
    private var frame = 0

    /// The frame of the film the last body was measured on.
    private(set) var lastFrame: Image?

    init(from start: Double) {
        self.start = start
        clip.isMuted = true
    }

    /// Advance the dance one frame and measure the body in it.
    func step() -> Body3D? {
        clip.seek(to: start + Double(frame) / 25)    // the film runs at 25 a second
        frame += 1
        guard let picture = clip.snapshot() else { return nil }
        lastFrame = picture
        return try? waitFor(picture) { try await BodyTracker3D.detect(in: $0) }
    }
}
