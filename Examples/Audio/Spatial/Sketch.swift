import Ollin
import OllinAudio

/// Sound that comes from somewhere.
///
/// Three chimes stand around you and one walks a circle past them. Each is a
/// `Synth` placed in the scene, and the camera is what hears: `place(at:heardFrom:)`
/// takes both facts at once, because a position says nothing until something is
/// listening and where the sketch is looking from is where it hears from.
///
/// Wear headphones. The placing is done the way the ear works it out, so a
/// sound behind you is behind you rather than merely quiet. On speakers it
/// falls back to a plain left and right.
///
/// Drag to move the camera, and the whole scene turns around your head.
///
/// It exports placed, too. Where each chime is and where it is being heard from
/// are written down as the frames are drawn, so the walk past your left ear is
/// in the file:
///
/// ```sh
/// swift run --package-path Examples Example-Audio-Spatial \
///     --export-video spatial.mp4 --frames 480
/// ```
@main
final class Spatial: Sketch {

    @Param(2 ... 30, icon: "waveform.path", group: "Room") var range = 12.0
    @Param(0.1 ... 2, icon: "figure.walk", group: "Room") var walkSpeed = 0.55

    struct Post {
        var synth: Synth
        var at: Vector3
        var pitch: Pitch
        var tone: Double
        var lastRang = -10.0
    }

    var posts: [Post] = []
    let walker = Synth(.nylon, polyphony: 6)
    var walkerPitch = 0
    var lastStep = -10.0
    var pings: [(at: Vector3, start: Double, tone: Double)] = []

    let tuning = Scale(.minorPentatonic, root: "A3")

    override func setup() {
        noStroke()
        lightingPreset(.studio)
        for (index, angle) in [0.0, 2.09, 4.19].enumerated() {
            let synth = Synth(.chime, polyphony: 6)
            synth.gain = 0.32
            synth.reverb = Reverb(.hall, mix: 0.3)
            posts.append(Post(synth: synth,
                              at: Vector3(cos(angle) * 5, 0, sin(angle) * 5),
                              pitch: tuning[index * 2],
                              tone: Double(index) / 3))
        }
        walker.gain = 0.4
    }

    override func draw() {
        background(Color(hex: 0x0E1116))

        // The camera is the listener, so it is worked out first and handed to
        // everything that makes a sound.
        cameraShowcase(.autoOrbit(period: 26), target: Vector3(0, 0.8, 0),
                       radius: 13, elevation: 0.34)
        groundGrid()
        // Whatever the rig settled on this frame is what the sketch hears from.
        guard let eye = activeCamera else { return }

        let walkerAt = Vector3(cos(time * walkSpeed) * 3.2, 0, sin(time * walkSpeed) * 3.2)
        walker.place(at: walkerAt, heardFrom: eye)
        walker.hearingRange = 1...range

        // The walker plays as it goes, so there is always something moving.
        if time - lastStep > 0.42 {
            lastStep = time
            walkerPitch = (walkerPitch + Int(random(1, 4))) % 10
            walker.play(tuning[walkerPitch + 5], velocity: 0.75, for: 0.9)
            pings.append((at: walkerAt, start: time, tone: 0.85))
        }

        for index in posts.indices {
            posts[index].synth.place(at: posts[index].at, heardFrom: eye)
            posts[index].synth.hearingRange = 1...range

            // A post answers when the walker comes near it.
            let apart = (walkerAt - posts[index].at).length
            if apart < 2.4, time - posts[index].lastRang > 1.6 {
                posts[index].lastRang = time
                posts[index].synth.play(posts[index].pitch, velocity: 0.9, for: 3)
                pings.append((at: posts[index].at, start: time, tone: posts[index].tone))
            }
        }

        drawScene(walkerAt: walkerAt)

        drawCaption("Wear headphones. Each sound comes from where its shape is.", edge: .top)
        drawCaption("Three chimes standing still and one walking past them, "
                    + "heard from wherever the camera is.")
    }

    private func drawScene(walkerAt: Vector3) {
        lights()
        for post in posts {
            withState {
                translate(post.at.x, post.at.y + 1.1, post.at.z)
                fill(Colormap.magma.color(at: 0.3 + post.tone * 0.5))
                material(.metal(roughness: 0.3))
                drawCylinder(radius: 0.28, height: 2.2)
            }
        }

        withState {
            translate(walkerAt.x, walkerAt.y + 0.5, walkerAt.z)
            fill(Color(white: 0.92))
            material(.plastic)
            drawIcosphere(radius: 0.42)
        }

        // Where a sound came from, spreading out from it. Drawn as flat rings
        // facing the camera rather than as spheres: a mesh takes its color from
        // the fill, so an outlined sphere is a solid one.
        pings.removeAll { time - $0.start > 2.2 }
        blendMode(.add)
        for ping in pings {
            let age = (time - ping.start) / 2.2
            withBillboard(at: Vector3(ping.at.x, ping.at.y + 0.6, ping.at.z)) {
                noFill()
                stroke(Colormap.magma.color(at: 0.35 + ping.tone * 0.45)
                    .withAlpha(pow(1 - age, 1.8) * 0.75))
                strokeWeight(2.5 * scale)
                drawCircle(0, 0, (14 + age * 150) * scale)
            }
        }
        blendMode(.normal)
        noStroke()
    }
}
