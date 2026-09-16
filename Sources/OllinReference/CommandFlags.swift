import Foundation

/// Every flag a person types at the `ollin` command, with the one line that
/// says what it does.
///
/// It is one table for two readers. A shell reads it as completions, so the
/// flags of whichever subcommand is being typed come up with their meanings
/// attached; a gate reads it against the tree, so a flag the code learns and
/// the table does not fails before anybody meets it as silence at the prompt.
/// That second reader is the reason internal flags are in here too: leaving
/// them out would make the table incomplete rather than curated, and there
/// would be no way to tell the difference.
public struct CommandFlag: Sendable, Equatable {

    /// Where a flag is typed. The same spelling can sit in two scopes and mean
    /// two things (`--from` names a value on a contact sheet and an example to
    /// start from), which is exactly why completion is scoped at all.
    public enum Scope: String, Sendable, CaseIterable {
        /// Typed after a sketch file: the export surface and the hosts' own.
        case run
        case new, docs, examples, site, check, phone, doctor
        /// Spelled by a host or a harness, never by a person. Completed nowhere.
        case internalUse
    }

    /// What follows the flag, which is what a shell has to be told to offer.
    public enum Takes: Sendable, Equatable {
        case nothing
        case file
        case directory
        /// A value with no completion, described by the word a person reads.
        case value(String)
        /// A value the flag may be given or left without, which is a different
        /// specification to a shell: offering it must not make it required.
        case optionalValue(String)
    }

    public let name: String
    public let scope: Scope
    public let takes: Takes
    /// One line, lowercase, no full stop: it is a menu row, not a sentence.
    public let summary: String

    public init(_ name: String, _ scope: Scope, _ takes: Takes, _ summary: String) {
        self.name = name
        self.scope = scope
        self.takes = takes
        self.summary = summary
    }
}

public extension CommandFlag {

    /// The whole table, grouped as a person would look for it.
    static let all: [CommandFlag] = exports + timing + quality + variation
        + parameters + recordings + printing + fabrication + dimensional + wall + live
        + newProject + reference + shaderCheck + phone + internals

    /// Just the ones a shell should offer.
    static var completable: [CommandFlag] { all.filter { $0.scope != .internalUse } }

    /// The flags of one scope, in table order.
    static func inScope(_ scope: Scope) -> [CommandFlag] { all.filter { $0.scope == scope } }

    // MARK: Running a sketch

    private static let exports: [CommandFlag] = [
        .init("--export", .run, .file, "write one frame as a PNG"),
        .init("--export-sequence", .run, .directory, "write a numbered PNG sequence"),
        .init("--export-video", .run, .file, "write a movie"),
        .init("--export-gif", .run, .file, "write an animated GIF"),
        .init("--export-loop", .run, .file, "write one seamless lap of a looping sketch"),
        .init("--export-svg", .run, .file, "write the frame as SVG"),
        .init("--export-pdf", .run, .file, "write the frame as PDF"),
        .init("--export-exr", .run, .file, "write the linear frame, before the tone map"),
        .init("--export-web", .run, .file, "write a page that plays the run back in a browser"),
        .init("--export-widget", .run, .directory, "write the run a widget would show, one picture per moment"),
        .init("--export-grid", .run, .file, "write a contact sheet of seeds"),
        .init("--export-sweep", .run, .file, "write a contact sheet sweeping one parameter"),
        .init("--export-separations", .run, .file, "write a master per ink, for printing"),
        .init("--export-plates", .run, .file, "write the proofed plates of a print"),
        .init("--export-usdz", .run, .file, "write the 3D scene as USDZ"),
        .init("--export-spatial", .run, .file, "write a spatial video"),
        .init("--export-dxf", .run, .file, "write a DXF for a cutter"),
        .init("--export-gcode", .run, .file, "write G-code for a pen plotter"),
        .init("--export-embroidery", .run, .file, "write a stitch file"),
    ]

    private static let timing: [CommandFlag] = [
        .init("--frames", .run, .value("N"), "how many frames to write"),
        .init("--seconds", .run, .value("S"), "how long to write, in the sketch's own seconds"),
        .init("--fps", .run, .value("F"), "frames a second: a number, a fraction, or a named rate"),
        .init("--skip", .run, .value("S"), "run this many seconds before the first written frame"),
        .init("--start", .run, .value("N"), "the number the first file of a sequence is named with"),
        .init("--frame", .run, .value("N"), "which frame to write"),
    ]

    private static let quality: [CommandFlag] = [
        .init("--render-quality", .run, .value("performance|default|detail"), "how hard the render works"),
        .init("--render-scale", .run, .value("N"), "draw each frame N times across and average it down"),
        .init("--settle", .run, .value("N"), "draw each written frame N times with the clock held"),
        .init("--slow-motion", .run, .value("N"), "write a file that plays N times slower than the run"),
        .init("--made-frames", .run, .nothing, "fill the slow motion with frames built between the drawn ones"),
        .init("--path-traced", .run, .optionalValue("samples"), "render offline with a path tracer"),
        .init("--pt-depth", .run, .value("N"), "the longest light path the tracer follows"),
        .init("--denoise", .run, .nothing, "filter the grain out of a path-traced render"),
        .init("--quality", .run, .value("0..1"), "the encoder's quality"),
        .init("--bitrate", .run, .value("MBPS"), "the encoder's bitrate"),
        .init("--codec", .run, .value("h264|hevc|hevcWithAlpha|proRes422|proRes4444"), "the encoder"),
        .init("--gif-width", .run, .value("PX"), "downscale the GIF to this width"),
        .init("--size", .run, .value("WxH"), "the pixel size a widget's run is drawn at"),
        .init("--exr", .run, .nothing, "write a sequence in linear light instead of PNG"),
        .init("--inline", .run, .nothing, "write a page fragment instead of a whole file"),
        .init("--no-controls", .run, .nothing, "leave a page's parameters at their recorded values"),
        .init("--max-page-size", .run, .value("MB"), "the most a written page may weigh"),
        .init("--bench", .run, .optionalValue("frames"), "time the frames and report, instead of drawing them"),
        .init("--gpu", .run, .nothing, "time the GPU too, in the benchmark"),
    ]

    private static let variation: [CommandFlag] = [
        .init("--seed", .run, .value("N"), "the variation to render"),
        .init("--seeds", .run, .value("N"), "how many variations a contact sheet holds"),
        .init("--columns", .run, .value("C"), "the columns of a contact sheet"),
        .init("--tile", .run, .value("PX"), "each thumbnail's width on a contact sheet"),
        .init("--sweep-param", .run, .value("name"), "the parameter a sweep sheet varies"),
        .init("--values", .run, .value("a,b,c"), "the values a sweep visits"),
        .init("--from", .run, .value("A"), "the first value of a sweep"),
        .init("--to", .run, .value("B"), "the last value of a sweep"),
        .init("--steps", .run, .value("N"), "how many values a sweep visits"),
    ]

    private static let parameters: [CommandFlag] = [
        .init("--param", .run, .value("name=value"), "set one declared parameter for this run"),
        .init("--list-params", .run, .nothing, "say what the sketch declares, and stop"),
        .init("--cue", .run, .value("name"), "start at a saved cue"),
        .init("--cues", .run, .file, "the cue sheet to read"),
        .init("--automation", .run, .file, "drive the parameters from written-down curves"),
    ]

    private static let recordings: [CommandFlag] = [
        .init("--record-take", .run, .file, "write the run itself down, input and all"),
        .init("--replay", .run, .file, "play a recorded take back"),
        .init("--record", .run, .file, "keep the live run as a movie from its first frame"),
        .init("--capture-source", .run, .nothing, "record the exact code the files came from"),
    ]

    private static let printing: [CommandFlag] = [
        .init("--paper", .run, .value("#RRGGBB"), "the color of the stock"),
        .init("--inks", .run, .value("names"), "the ink set, by catalog name"),
        .init("--screen", .run, .value("dither|halftone"), "pre-screen the masters"),
        .init("--pitch", .run, .value("PX"), "the halftone cell"),
        .init("--profile", .run, .value("name-or-path"), "the printer profile to proof through"),
        .init("--intent", .run, .value("name"), "the rendering intent"),
        .init("--no-marks", .run, .nothing, "write the bare canvas, with no registration marks"),
    ]

    private static let fabrication: [CommandFlag] = [
        .init("--hatch", .run, .nothing, "fill solid areas with hatch lines"),
        .init("--cross-hatch", .run, .nothing, "hatch twice, crossed"),
        .init("--hatch-spacing", .run, .value("PX"), "the gap between hatch lines"),
        .init("--hatch-angle", .run, .value("DEG"), "the angle the hatching runs at"),
        .init("--fill-spacing", .run, .value("MM"), "the spacing a fill is sewn at; 0 sews outlines"),
        .init("--stitch-length", .run, .value("MM"), "the longest stitch"),
        .init("--gcode-machine", .run, .value("name"), "the plotter profile"),
        .init("--gcode-paper", .run, .value("sheet"), "the sheet the G-code is sized to"),
        .init("--gcode-margin", .run, .value("MM"), "the border around the G-code"),
        .init("--gcode-width", .run, .value("MM"), "the physical width of the G-code"),
        .init("--dxf-paper", .run, .value("sheet"), "the sheet the DXF is sized to"),
        .init("--dxf-margin", .run, .value("MM"), "the border around the DXF"),
        .init("--dxf-width", .run, .value("MM"), "the physical width of the DXF"),
        .init("--embroidery-width", .run, .value("MM"), "the physical width of the stitching"),
        .init("--embroidery-margin", .run, .value("MM"), "the border around the stitching"),
    ]

    private static let dimensional: [CommandFlag] = [
        .init("--meters-per-unit", .run, .value("U"), "how big one sketch unit is, in a 3D file"),
        .init("--interocular", .run, .value("X"), "the eye separation of a spatial render"),
        .init("--convergence", .run, .value("D"), "the distance the eyes converge at"),
    ]

    private static let wall: [CommandFlag] = [
        .init("--installation", .run, .nothing, "give the sketch its own full-screen window"),
        .init("--no-installation", .run, .nothing, "ignore what the sketch declares for a long run"),
        .init("--calibrate", .run, .nothing, "line the projection up on its surface"),
        .init("--rehearse", .run, .optionalValue("N"), "lay the wall out as N windows on this desk"),
        .init("--displays", .run, .value("one|spanning|mirroring"), "which displays the canvas spans"),
        .init("--fresh", .run, .nothing, "start over instead of carrying the sketch's saved state"),
    ]

    private static let live: [CommandFlag] = [
        .init("--debug", .run, .nothing, "run a debug build of the host"),
        .init("--keep-clock", .run, .nothing, "carry the clock across a reload"),
        .init("--no-optimize", .run, .nothing, "compile the sketch plain, for debugging it"),
    ]

    // MARK: Making something

    private static let newProject: [CommandFlag] = [
        .init("--kind", .new, .value("id"), "what to make: a folder, an app, a screen saver, an extension"),
        .init("--template", .new, .value("id"), "which ready-made starting point"),
        .init("--from", .new, .value("Group/Name"), "start from an example, material and all"),
        .init("--from-shader", .new, .value("file-or-address"), "start from a GLSL fragment shader"),
        .init("--from-scene", .new, .file, "start from a glTF or USD scene"),
        .init("--seam", .new, .value("id"), "what an extension package is built on"),
        .init("--with", .new, .value("a,b"), "extra libraries and folders to wire in"),
        .init("--canvas", .new, .value("id"), "the canvas size to declare"),
        .init("--team", .new, .value("id"), "the Apple Developer team an iOS app is signed under"),
        .init("--in", .new, .directory, "where to put it"),
        .init("--remote", .new, .nothing, "point the manifest at the published framework"),
        .init("--framework-path", .new, .directory, "point it at a particular copy of the framework"),
        .init("--list", .new, .nothing, "every kind, template, seam, and extra"),
        .init("--examples", .new, .nothing, "every example that can be started from"),
        .init("--help", .new, .nothing, "what this command takes"),
    ]

    // MARK: Reading

    private static let reference: [CommandFlag] = [
        .init("--search", .docs, .value("text"), "every place the reference says it"),
        .init("--list", .docs, .nothing, "one topic per line"),
        .init("--code", .docs, .nothing, "only the code blocks of a page"),
        .init("--width", .docs, .value("n"), "wrap to this many columns"),
        .init("--plain", .docs, .nothing, "no color, whatever the terminal is"),
        .init("--color", .docs, .nothing, "color, even when the output is a pipe"),
        .init("--no-color", .docs, .nothing, "no color"),
        .init("--no-pager", .docs, .nothing, "print straight out instead of opening a pager"),
        .init("--help", .docs, .nothing, "what this command takes"),
        .init("--source", .examples, .nothing, "print the sketch itself"),
        .init("--list", .examples, .nothing, "one path per line"),
        .init("--width", .examples, .value("n"), "wrap to this many columns"),
        .init("--plain", .examples, .nothing, "no color, whatever the terminal is"),
        .init("--no-pager", .examples, .nothing, "print straight out instead of opening a pager"),
        .init("--domain", .site, .value("name"), "write the CNAME for this domain"),
        .init("--repository", .site, .value("owner/name"), "the repository the pages link into"),
        .init("--branch", .site, .value("name"), "the branch the pages link into"),
    ]

    private static let shaderCheck: [CommandFlag] = [
        .init("--as", .check, .value("generator|filter|combine"), "compile it as this shape"),
        .init("--using", .check, .value("all|none|color,hash,noise,sdf,domain,visual"),
              "which sections of the shader library to splice in"),
        .init("--help", .check, .nothing, "what this command takes"),
    ]

    private static let phone: [CommandFlag] = [
        .init("--device", .phone, .value("name-or-id"), "which paired phone or tablet"),
        .init("--devices", .phone, .nothing, "list the paired devices and stop"),
        .init("--team", .phone, .value("id"), "the signing team"),
        .init("--once", .phone, .nothing, "build, install, launch, and stop watching"),
        .init("--fresh", .phone, .nothing, "start the sketch over instead of carrying its state"),
        .init("--port", .phone, .value("n"), "the local port the parameters are proxied to"),
        .init("--verbose", .phone, .nothing, "show every build line"),
        .init("--help", .phone, .nothing, "what this command takes"),
        .init("--help", .doctor, .nothing, "what this command takes"),
    ]

    // MARK: Spelled by a host, never by a person

    private static let internals: [CommandFlag] = [
        .init("--selftest", .internalUse, .nothing, "the host's headless gate"),
        .init("--watchtest", .internalUse, .nothing, "the file watcher's headless gate"),
        .init("--paramtest", .internalUse, .nothing, "the parameter plumbing's headless gate"),
        .init("--savetest", .internalUse, .nothing, "the write-back's headless gate"),
        .init("--dragtest", .internalUse, .nothing, "the shape drag's headless gate"),
        .init("--sessiontest", .internalUse, .nothing, "the shared session's headless gate"),
        .init("--controltest", .internalUse, .nothing, "the performance controls' headless gate"),
        .init("--cycletest", .internalUse, .nothing, "the gallery's headless gate"),
        .init("--stagetest", .internalUse, .nothing, "the generator stage's headless gate"),
        .init("--self-shot", .internalUse, .nothing, "the gallery photographs its own window"),
        .init("--cycle-filter", .internalUse, .value("text"), "which examples the gallery cycles"),
        .init("--cycle-hold", .internalUse, .value("seconds"), "how long the gallery holds each one"),
        .init("--single-build", .internalUse, .nothing, "evaluate in one speed, not two"),
    ]
}
