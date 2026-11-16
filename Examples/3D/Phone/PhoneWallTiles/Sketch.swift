import Foundation
import Ollin
import OllinAudio
import OllinPhone

/// The tiles of a real wall, pushed out of it by music.
///
/// A recording the phone made of a tiled wall plays back, and the wall's own
/// tiles come out of it in time with a beat. Each block is a piece of the
/// camera's picture, lifted off the surface the phone found and still showing
/// the pixels it left, so it slides against the wall as the camera moves the
/// way a real block would.
///
/// Three things do it. `withPlane(wall)` draws in the wall's own meters.
/// `painted(with: view)` paints what is drawn inside it with the camera's
/// picture: a block takes its pixels where it stands when the scope opens,
/// flat against the wall, and the transform inside the scope then pulls it
/// out. And the grid is lined up with the real tiles by two parameters, the
/// tiles' size and where the first one starts.
///
/// The beat is the sketch's own: a drum, a bass, and a chime on three
/// rhythms, each moving its share of the tiles. So an export carries the
/// sound (`--export-video`) and comes out the same every time. To move the
/// tiles with a track of your own, read a band of it where `level(of:delay:)`
/// reads a rhythm.
///
/// The recording bundled here is a stand-in: a small room drawn on the Mac
/// and written with the writer the phone runs. To play one of your own, make
/// it in **Room** mode, which is the mode that finds surfaces, bring its
/// folder over, and set `OLLIN_PHONE_RECORDING` to its path. Then set
/// `tileSize` and the two offsets until the grid sits on your tiles.
///
/// Key: **space** holds the recording and carries on.
@main
final class PhoneWallTiles: Sketch {

    override var canvasSize: CanvasSize { .size(1080, 1440) }

    /// One lap of the recording, so an export of this sketch loops. The beat
    /// is two bars to the bundled recording's six seconds.
    override var loopDuration: Double? {
        guard let recording = device.recording, recording.frameRate > 0 else { return nil }
        return recording.duration + 1 / recording.frameRate
    }

    let device = PhoneDevice(playing: PhoneWallTiles.open())

    /// The side of one real tile, in meters.
    @Param(0.08...0.6) var tileSize = 0.25
    /// Where a tile's left edge falls, in meters along the wall from its middle.
    @Param(-0.3...0.3) var offsetX = 0.0
    /// Where a tile's bottom edge falls, in meters up the wall from its middle.
    @Param(-0.3...0.3) var offsetY = 0.0
    /// How far the loudest hit pushes a tile out, in meters.
    @Param(0.05...0.6) var depth = 0.3
    /// How much of a tile a block takes, across: under 1 leaves the grout on
    /// the wall and puts the block's sides on the tile's own color.
    @Param(0.6...1) var cover = 0.9

    /// The part of the wall the piece plays on, in the wall's own meters from
    /// its middle. The bundled room has furniture standing in front of the
    /// wall's lower third, and nothing in the recording says where it is, so
    /// the tiles there are left alone.
    let region = Rectangle(x: -2, y: -0.25, width: 4, height: 1.75)

    // The beat: sixteen steps to a bar.
    let tempo: Tempo = 80
    var counter = StepCounter(perBeat: 4)
    let drum = Synth(.drum, polyphony: 4)
    let bass = Synth(.bass, polyphony: 4)
    let chime = Synth(.chime, polyphony: 8)
    let parts = [Rhythm(5, in: 16), Rhythm(3, in: 16, rotation: 6), Rhythm(7, in: 16, rotation: 1)]
    let tuning = Scale(.minorPentatonic, root: "A1")

    /// The recording to play: your own when `OLLIN_PHONE_RECORDING` names one
    /// that opens, the bundled wall otherwise.
    static func open() -> PhoneRecording {
        if let path = ProcessInfo.processInfo.environment["OLLIN_PHONE_RECORDING"],
           let own = try? PhoneRecording(path: path) {
            return own
        }
        return try! PhoneRecording(resource: "Wall", withExtension: "ollinrecording", in: .module)
    }

    override func setup() {
        textFont(OutlineFont.system)
        drum.gain = 0.9
        bass.gain = 0.55
        chime.gain = 0.5
        chime.reverb = Reverb(.hall, mix: 0.25)
        device.start()
    }

    override func draw() {
        background(.black)
        for step in counter.steps(upTo: tempo.beats(at: time)) { play(step) }

        guard let view = device.latestCamera else {
            return drawStatus(device.waitingMessage, style: .info)
        }
        drawPhonePicture(view)
        camera(view)
        guard let wall = device.planes.largest(of: .wall) ?? device.planes.largest else {
            return drawCaption("This recording carries no surface. Record in Room mode to get one.")
        }

        noStroke()
        withPlane(wall) {
            let columns = Int((region.x - offsetX) / tileSize).advanced(by: -1)
                ... Int(((region.x + region.width) - offsetX) / tileSize)
            let rows = Int((region.y - offsetY) / tileSize).advanced(by: -1)
                ... Int(((region.y + region.height) - offsetY) / tileSize)
            for row in rows {
                for column in columns {
                    let x = offsetX + (Double(column) + 0.5) * tileSize
                    let y = offsetY + (Double(row) + 0.5) * tileSize
                    guard region.contains(Vector2(x, y)) else { continue }
                    let out = depth * push(column: column, row: row, at: Vector2(x, y))
                    // A tile that has not moved is the wall itself: the
                    // picture already shows it.
                    guard out > 0.004 else { continue }
                    drawBlock(at: Vector2(x, y), out: out, view: view)
                }
            }
        }
        drawCaption("The wall's own tiles, pushed out by the beat")
    }

    // MARK: A block of the wall

    /// How thick a block is while it still lies in the wall, in meters.
    static let thin = 0.004

    /// A block one tile wide lying flat in the wall: its face, and its four
    /// sides, which at rest are slivers along the tile's edges.
    static let face = quad(Vector3(-0.5, -0.5, thin / 2), Vector3(0.5, -0.5, thin / 2),
                           Vector3(0.5, 0.5, thin / 2), Vector3(-0.5, 0.5, thin / 2))
    static let sides: [(mesh: Mesh, shade: Double)] = {
        let b = -thin / 2, f = thin / 2
        return [
            (quad(Vector3(-0.5, 0.5, b), Vector3(0.5, 0.5, b), Vector3(0.5, 0.5, f), Vector3(-0.5, 0.5, f)), 0.86),
            (quad(Vector3(-0.5, -0.5, b), Vector3(-0.5, 0.5, b), Vector3(-0.5, 0.5, f), Vector3(-0.5, -0.5, f)), 0.66),
            (quad(Vector3(0.5, 0.5, b), Vector3(0.5, -0.5, b), Vector3(0.5, -0.5, f), Vector3(0.5, 0.5, f)), 0.6),
            (quad(Vector3(0.5, -0.5, b), Vector3(-0.5, -0.5, b), Vector3(-0.5, -0.5, f), Vector3(0.5, -0.5, f)), 0.42),
        ]
    }()

    static func quad(_ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3) -> Mesh {
        let normal = (b - a).cross(d - a).normalized
        return Mesh(positions: [a, b, c, d], normals: [Vector3](repeating: normal, count: 4),
                    indices: [0, 1, 2, 0, 2, 3])
    }

    /// One tile of the wall, pushed `out` meters. Everything before
    /// `painted` places the block on its tile, where it takes its pixels.
    /// Everything inside moves it: the block is stretched from the wall's
    /// face out to `out`, so its face carries the tile and its sides carry
    /// the tile's edges, drawn out into streaks and shaded as if lit from
    /// above.
    private func drawBlock(at place: Vector2, out: Double, view: PhoneCamera) {
        withState {
            translate(place.x, place.y, 0)
            scale(tileSize * cover, tileSize * cover, 1)
            painted(with: view) {
                translate(0, 0, out / 2)
                scale(1, 1, out / Self.thin)
                fill(.white)
                drawMesh(Self.face)
                for side in Self.sides {
                    fill(Color(white: side.shade))
                    drawMesh(side.mesh)
                }
            }
        }
    }

    // MARK: The beat

    /// How far out a tile is, 0 to 1. Each tile follows one part of the
    /// beat, chosen by a fixed rule on its place in the grid: half follow the
    /// drum, which spreads from the middle of the region as a ring, a third
    /// the bass, which climbs the wall row by row, and the rest the chime,
    /// each on a small delay of its own.
    private func push(column: Int, row: Int, at place: Vector2) -> Double {
        let pick = abs(column &* 7 &+ row &* 13 &+ (column &* row) % 5) % 10
        let middle = Vector2(region.x + region.width / 2, region.y + region.height / 2)
        if pick < 5 {
            return level(of: 0, delay: place.distance(to: middle) * 0.16, decay: 0.22)
        } else if pick < 8 {
            return 0.7 * level(of: 1, delay: (place.y - region.y) * 0.2, decay: 0.3)
        } else {
            return 0.5 * level(of: 2, delay: Double(pick + abs(column) % 3) * 0.02, decay: 0.16)
        }
    }

    /// How loud a part of the beat is at this moment for something that
    /// hears it `delay` seconds late: 1 on a hit, dying away over `decay`
    /// seconds. Read from the rhythm and the clock alone, with no memory of
    /// what was played, so the first frame of a lap already holds the tail of
    /// the lap before it and an export loops.
    private func level(of part: Int, delay: Double, decay: Double) -> Double {
        let heard = time - delay
        let stepLength = tempo.seconds(beats: 0.25)
        let now = Int((heard / stepLength).rounded(.down))
        var loudest = 0.0
        for step in (now - 12)...now where parts[part][((step % 16) + 16) % 16] {
            let age = heard - Double(step) * stepLength
            loudest = max(loudest, exp(-age / decay))
        }
        return loudest
    }

    private func play(_ step: Int) {
        let inBar = ((step % 16) + 16) % 16
        if parts[0][inBar] { drum.play("C2", velocity: 0.95, for: 0.2) }
        if parts[1][inBar] { bass.play(tuning[[0, 3, 2][(step / 5) % 3]], velocity: 0.8, for: 0.5) }
        if parts[2][inBar] { chime.play(tuning[10 + inBar % 5], velocity: 0.45, for: 1.2) }
    }

    override func keyPressed() {
        guard key == " ", let recording = device.recording else { return }
        if recording.isPlaying { recording.pause() } else { recording.play() }
    }
}
