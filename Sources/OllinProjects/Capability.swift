import Foundation

/// Something a generated sketch is wired for: an asset folder it can load from,
/// or one of the satellite libraries linked beside the core.
///
/// A capability contributes four small things and nothing else: an `import`,
/// a package dependency, any folders the sketch loads from, and one commented
/// starter line inside `setup()`. The line stays a comment on purpose, so a
/// freshly generated sketch always runs, and what it shows is the real first
/// call rather than a placeholder.
public struct Capability: Sendable, Hashable, Identifiable {
    /// Stable slug used on the command line (`--with vision,audio`).
    public let id: String
    public let title: String
    public let summary: String
    /// The satellite module to import, or nil when the core already has it.
    public let module: String?
    /// Folders created beside the sketch, each with a note saying what goes in.
    public let assetFolders: [AssetFolder]
    /// The first call, as a comment inside `setup()`. Empty for none.
    public let starterHint: String

    public struct AssetFolder: Sendable, Hashable {
        public let name: String
        /// What belongs in the folder, written into a README inside it so an
        /// empty folder survives a checkout and still explains itself.
        public let note: String

        public init(name: String, note: String) {
            self.name = name
            self.note = note
        }
    }

    public init(
        id: String,
        title: String,
        summary: String,
        module: String? = nil,
        assetFolders: [AssetFolder] = [],
        starterHint: String = ""
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.module = module
        self.assetFolders = assetFolders
        self.starterHint = starterHint
    }
}

extension Capability {

    // Core capabilities: no extra module, just somewhere to put the material.

    public static let images = Capability(
        id: "images",
        title: "Images",
        summary: "A folder to load pictures from, drawn with drawImage.",
        assetFolders: [.init(
            name: "Images",
            note: "Pictures the sketch loads. Reach one with `loadImage(resource: \"name\", withExtension: \"png\", in: .module)`."
        )],
        starterHint: "let picture = loadImage(resource: \"photo\", withExtension: \"jpg\", in: .module)"
    )

    public static let text = Capability(
        id: "text",
        title: "Text",
        summary: "A folder for fonts, with drawText and the three font kinds.",
        assetFolders: [.init(
            name: "Fonts",
            note: "Fonts the sketch loads (.ttf, .otf, .bdf, .jhf). Reach one with `OutlineFont(resource:in:)`."
        )],
        starterHint: "textFont(.systemMedium); textSize(48)"
    )

    public static let shaders = Capability(
        id: "shaders",
        title: "Shaders",
        summary: "A .metal file beside the sketch, run through the effect graph.",
        assetFolders: [],   // the emitter writes a real Shaders/ stub, not an empty folder
        starterHint: "let effect = Shader(resource: \"effect\", in: .module)"
    )

    public static let params = Capability(
        id: "params",
        title: "Parameters",
        summary: "Parameters you can drag while the sketch runs, typed to the property.",
        starterHint: "@Param(0...1) var amount = 0.5"
    )

    // Satellites: each adds its module and its first call.

    public static let audio = Capability(
        id: "audio",
        title: "Audio",
        summary: "Listen to the microphone, a file, or a tone, and read the sound in draw().",
        module: "OllinAudio",
        starterHint: "let mic = AudioInput()   // then read mic.amplitude or mic.bands(64)"
    )

    public static let vision = Capability(
        id: "vision",
        title: "Camera and vision",
        summary: "The Mac's camera, plus face, hand, body, and contour tracking.",
        module: "OllinVision",
        starterHint: "let camera = Camera()"
    )

    public static let video = Capability(
        id: "video",
        title: "Video playback",
        summary: "Play a video file into the sketch as a live image.",
        module: "OllinVideo",
        assetFolders: [.init(
            name: "Video",
            note: "Clips the sketch plays. Reach one with `VideoPlayer(resource: \"clip\", withExtension: \"mp4\", in: .module)`."
        )],
        starterHint: "let clip = try? VideoPlayer(resource: \"clip\", withExtension: \"mp4\", in: .module)"
    )

    public static let physics = Capability(
        id: "physics",
        title: "Physics",
        summary: "A world you step each frame, so motion comes from simulation.",
        module: "OllinPhysics",
        starterHint: "let world = World()"
    )

    public static let midi = Capability(
        id: "midi",
        title: "MIDI",
        summary: "Read knobs, keys, and clock from MIDI gear, and send back.",
        module: "OllinMIDI",
        starterHint: "lazy var midi = MIDIInput()"
    )

    public static let osc = Capability(
        id: "osc",
        title: "OSC",
        summary: "Send and receive networked control messages across a rig.",
        module: "OllinOSC",
        starterHint: "let receiver = OSCReceiver(port: 5005)"
    )

    public static let serial = Capability(
        id: "serial",
        title: "Serial",
        summary: "Read a USB microcontroller's sensor lines, and write lines back.",
        module: "OllinSerial",
        starterHint: "let serial = SerialPort(matching: \"usbmodem\")   // then serial.open()"
    )

    public static let bluetooth = Capability(
        id: "bluetooth",
        title: "Bluetooth",
        summary: "A Bluetooth sensor read in draw(), and the room of devices in range.",
        module: "OllinBluetooth",
        starterHint: "let sensor = BluetoothDevice(service: .heartRate)   // then sensor.connect()"
    )

    public static let dmx = Capability(
        id: "dmx",
        title: "DMX lighting",
        summary: "Drive stage lights from draw(), or let a console drive the sketch.",
        module: "OllinDMX",
        starterHint: "let lights = DMXSender()"
    )

    public static let syphon = Capability(
        id: "syphon",
        title: "Syphon",
        summary: "Share every rendered frame with other apps on the machine.",
        module: "OllinSyphon",
        starterHint: "publishSyphon(name: \"My Sketch\")"
    )

    public static let controller = Capability(
        id: "controller",
        title: "Game controller",
        summary: "Read a game pad's sticks, buttons, motion, and touchpad in draw().",
        module: "OllinController",
        starterHint: "// read `controller` in draw(): controller.leftStick, controller.isDown(.a)"
    )

    public static let screen = Capability(
        id: "screen",
        title: "Screen capture",
        summary: "Any display, app, or window as a live feed.",
        module: "OllinScreen",
        starterHint: "let screen = ScreenCapture(.mainDisplay)"
    )

    public static let virtualCamera = Capability(
        id: "virtual-camera",
        title: "Virtual camera",
        summary: "Publish the canvas as a system camera every webcam app can read.",
        module: "OllinCamera",
        starterHint: "publishVirtualCamera()"
    )

    public static let phone = Capability(
        id: "phone",
        title: "iPhone sensors",
        summary: "A tethered phone's depth, body, face, segmentation, and motion.",
        module: "OllinPhone",
        starterHint: "let phone = PhoneDevice()"
    )

    public static let record3D = Capability(
        id: "record3d",
        title: "RGBD recordings",
        summary: "A recorded depth clip or a tethered phone's live depth stream.",
        module: "OllinRecord3D",
        starterHint: "let recording = try? Record3DRecording(path: path)"
    )

    /// Every capability, in the order a list should show them: the material a
    /// sketch loads first, then the libraries it links.
    public static let all: [Capability] = [
        .images, .text, .shaders, .params,
        .audio, .vision, .video, .physics,
        .midi, .osc, .serial, .bluetooth, .dmx, .syphon, .controller, .screen, .virtualCamera,
        .phone, .record3D,
    ]

    /// The ones that pull in a satellite library.
    public static var satellites: [Capability] { all.filter { $0.module != nil } }

    public static func named(_ id: String) -> Capability? {
        all.first { $0.id == id }
    }
}
