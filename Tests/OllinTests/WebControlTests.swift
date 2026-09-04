import Testing
import Foundation
import CoreGraphics
import OllinWebGate
@testable import Ollin

/// Parameters as controls on the web page: the probe sets each part of each
/// `@Param` to a few other values on a fresh sketch, fits every column the
/// setting moved to a line in it at every frame, and wires the ones that fit,
/// so the page offers the parameter as a control that moves the picture the
/// way the Mac would have drawn it. The probe is checked on its own (what
/// wires, what stays recorded and why), then the page at a moved setting
/// against the Mac at the same setting in the shared browser gate.
@Suite @MainActor struct WebControlTests {

    // MARK: Fixtures

    /// A dial for everything the probe should wire: a radius read straight
    /// (slope one), a position that turns with the clock (a slope per frame,
    /// the sines of a lap), a color on the strokes (slope one per channel), a
    /// fade on a fill that breathes (a slope per frame), a paper color that
    /// reaches the clear through linear light, a switch that swaps the fill,
    /// and a point that moves the picture.
    final class Dial: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override var loopDuration: Double? { 2 }
        @Param(0 ... 200) var radius: Double = 60
        @Param(0 ... 1) var fade: Double = 0.5
        @Param var ink: Color = .black
        @Param var paper: Color = .white
        @Param var filled: Bool = false
        @Param(x: 0 ... 240, y: 0 ... 240) var anchor = Vector2(120, 120)
        override func draw() {
            background(paper)
            let phase = time / 2 * .tau
            stroke(ink)
            strokeWeight(4)
            let breath = fade * (0.75 + 0.25 * sin(phase))
            fill(filled ? Color(red: 0.2, green: 0.4, blue: 0.9, alpha: breath) : Color(red: 0.9, green: 0.3, blue: 0.2, alpha: breath))
            drawCircle(anchor.x + cos(phase) * radius * 0.5, anchor.y + sin(phase) * radius * 0.5, 30)
            noFill()
            drawCircle(120, 120, radius)
        }
    }

    /// A radius the sketch squares: the column is not a line in the parameter.
    final class Squared: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(1 ... 20) var radius: Double = 10
        @Param(0 ... 1) var gray: Double = 0.5
        override func draw() {
            background(.white)
            fill(Color(red: gray, green: gray, blue: gray, alpha: 1))
            drawCircle(60, 60, radius * radius / 4)
        }
    }

    /// A count that changes the cast, beside a size that does not.
    final class Counted: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(1 ... 12) var count: Int = 4
        @Param(2 ... 30) var size: Double = 10
        override func draw() {
            background(.white)
            fill(.black)
            for i in 0 ..< count {
                drawCircle(20 + Double(i) * 8, 60, size)
            }
        }
    }

    /// Two parameters whose product sets the radius: each is a line on its
    /// own and the pair is not.
    final class Product: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(0.5 ... 4) var a: Double = 2
        @Param(0.5 ... 4) var b: Double = 3
        @Param(0 ... 40) var offset: Double = 0
        override func draw() {
            background(.white)
            fill(.black)
            drawCircle(60 + offset, 60, a * b * 5)
        }
    }

    /// A shader reading a parameter through its rows.
    final class Shaded: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(0 ... 1) var amount: Double = 0.3
        override func draw() {
            background(.white)
            let s = Shader("""
            float4 shade(float2 uv, ShaderInfo info) {
                float k = param(info, 0);
                return float4(uv.x * k, uv.y * (1.0 - k), k, 1.0);
            }
            """, params: [Float(amount)])
            drawImage(generate(s).image, 0, 0)
        }
    }

    /// A formula driving the radius from a parameter it reads as a constant:
    /// the control reaches the picture through the formula on the page.
    final class Constant: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(20 ... 100) var base: Double = 40
        @Param(0 ... 200) var radius: Double = 40
        override func setup() {
            drive($radius, "base + sin(time * tau / 2) * 10")
        }
        override func draw() {
            background(.white)
            noFill()
            stroke(.black)
            strokeWeight(3)
            drawCircle(60, 60, radius)
        }
    }

    /// A parameter nothing reads, and one that is a menu.
    enum Style: String, ParamOption, CaseIterable { case dots, lines }
    final class Idle: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(0 ... 1) var unused: Double = 0.5
        @Param var style: Style = .dots
        @Param(0 ... 60) var radius: Double = 30
        override func draw() {
            background(.white)
            fill(.black)
            drawCircle(60, 60, radius)
        }
    }

    /// A sketch that draws differently on each run.
    final class Dice: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        @Param(0 ... 60) var radius: Double = 30
        var jitter = 0.0
        override func setup() {
            jitter = Double.random(in: 0 ... 20)
        }
        override func draw() {
            background(.white)
            fill(.black)
            drawCircle(60 + jitter, 60, radius)
        }
    }

    static func control(_ recording: WebRecording, _ name: String) -> WebControl? {
        recording.controls.first { $0.name == name }
    }

    static func reason(_ recording: WebRecording, _ name: String) -> String? {
        recording.leftOut.first { $0.name == name }?.reason
    }

    // MARK: The probe

    @Test func aLinearParameterIsWiredWithItsSlope() throws {
        let recording = try OllinApp.recordWebFrames(of: Dial(), frames: 20, fps: 10)
        #expect(recording.leftOut.isEmpty, "\(recording.leftOut)")
        let radius = try #require(Self.control(recording, "radius"))
        #expect(radius.kind == .number)
        #expect(radius.parts.count == 1 && radius.parts[0].lower == 0 && radius.parts[0].upper == 200)
        #expect(radius.values[""] == 60)
        let axis = recording.axes[try #require(radius.parts[0].axis)]
        #expect(axis.name == "radius" && axis.base == 60)
        // The outline's size columns (size.x, size.y of the second shape) read
        // the radius straight: slope one at every frame. The moving circle's
        // center reads half the radius times the turn: a slope per frame.
        let sizes = axis.columns.filter { $0.region == .vector && $0.index / WebInstance.floats == 1 && [8, 9].contains($0.index % WebInstance.floats) }
        #expect(sizes.count == 2)
        for c in sizes { #expect(c.slopes.allSatisfy { abs($0 - 1) < 1e-4 }, "\(c.slopes.prefix(4))") }
        let centerX = try #require(axis.columns.first { $0.index == 6 })
        #expect(abs(Double(centerX.slopes[0]) - 0.5) < 1e-4)
        #expect(abs(Double(centerX.slopes[5]) - 0.5 * cos(0.5 * .pi)) < 1e-3)
        #expect(centerX.transform == WebAxisColumn.identity)
    }

    @Test func aColorReachesTheStrokesStraightAndTheClearThroughLinearLight() throws {
        let recording = try OllinApp.recordWebFrames(of: Dial(), frames: 6, fps: 10)
        let ink = try #require(Self.control(recording, "ink"))
        #expect(ink.kind == .color)
        #expect(ink.parts.map(\.name) == ["red", "green", "blue", "alpha"])
        let red = recording.axes[try #require(ink.parts[0].axis)]
        // Both shapes' stroke red (column 14 of each) read the channel as it is.
        #expect(red.columns.count == 2)
        #expect(red.columns.allSatisfy { $0.transform == WebAxisColumn.identity && $0.index % WebInstance.floats == 14 })
        #expect(red.columns.allSatisfy { $0.slopes.allSatisfy { abs($0 - 1) < 1e-4 } })
        // The alpha reaches both strokes as it is.
        let alpha = recording.axes[try #require(ink.parts[3].axis)]
        #expect(alpha.columns.count == 2)
        #expect(alpha.columns.allSatisfy { $0.index % WebInstance.floats == 17 && $0.slopes.allSatisfy { abs($0 - 1) < 1e-4 } })
        // The paper is the clear, in linear light.
        let paper = try #require(Self.control(recording, "paper"))
        let green = recording.axes[try #require(paper.parts[1].axis)]
        #expect(green.columns.count == 1)
        let fact = try #require(green.columns.first)
        #expect(fact.region == .fact && fact.index == 1 && fact.transform == WebAxisColumn.srgbToLinear)
        #expect(fact.slopes.allSatisfy { abs($0 - 1) < 1e-4 })
        // Its alpha reaches nothing, so the well has no opacity slider.
        #expect(paper.parts[3].axis == nil)
        // The fade moves the moving circle's fill alpha by the breath, a slope
        // per frame: 0.75 at the start of the lap, 1 a quarter in.
        let fade = try #require(Self.control(recording, "fade"))
        let fadeAxis = recording.axes[try #require(fade.parts[0].axis)]
        #expect(fadeAxis.columns.count == 1)
        let fillAlpha = try #require(fadeAxis.columns.first)
        #expect(fillAlpha.index == 13)
        #expect(abs(Double(fillAlpha.slopes[0]) - 0.75) < 1e-4)
        #expect(abs(Double(fillAlpha.slopes[5]) - 1) < 1e-3)
    }

    @Test func aSwitchAndAPointAreControlsToo() throws {
        let recording = try OllinApp.recordWebFrames(of: Dial(), frames: 4, fps: 10)
        let filled = try #require(Self.control(recording, "filled"))
        #expect(filled.kind == .toggle && filled.values[""] == 0)
        let toggle = recording.axes[try #require(filled.parts[0].axis)]
        // Off to on moves the moving circle's fill from red to blue.
        let fillRed = try #require(toggle.columns.first { $0.index % WebInstance.floats == 10 })
        #expect(abs(Double(fillRed.slopes[0]) - (0.2 - 0.9)) < 1e-4)
        let anchor = try #require(Self.control(recording, "anchor"))
        #expect(anchor.kind == .vector && anchor.parts.map(\.name) == ["x", "y"])
        let x = recording.axes[try #require(anchor.parts[0].axis)]
        #expect(x.columns.count == 1 && x.columns[0].index == 6)
        #expect(x.columns[0].slopes.allSatisfy { abs($0 - 1) < 1e-4 })
        #expect(recording.controls.count == 6)
    }

    @Test func whatCannotBeWiredStaysRecordedAndSaysWhy() throws {
        let squared = try OllinApp.recordWebFrames(of: Squared(), frames: 3, fps: 10)
        #expect(Self.reason(squared, "radius") == OllinApp.webReasonNonlinear)
        #expect(Self.control(squared, "gray") != nil)

        let counted = try OllinApp.recordWebFrames(of: Counted(), frames: 3, fps: 10)
        #expect(Self.reason(counted, "count") == OllinApp.webReasonCast)
        #expect(Self.control(counted, "size") != nil)

        // Each factor is a line on its own; together they are not, and the
        // offset beside them keeps its control.
        let product = try OllinApp.recordWebFrames(of: Product(), frames: 3, fps: 10)
        #expect(Self.reason(product, "a") == OllinApp.webReasonCoupled)
        #expect(Self.reason(product, "b") == OllinApp.webReasonCoupled)
        #expect(Self.control(product, "offset") != nil)

        let idle = try OllinApp.recordWebFrames(of: Idle(), frames: 3, fps: 10)
        #expect(Self.reason(idle, "unused") == OllinApp.webReasonInert)
        #expect(Self.reason(idle, "style") == OllinApp.webReasonNoControl)
        #expect(Self.control(idle, "radius") != nil)

        let dice = try OllinApp.recordWebFrames(of: Dice(), frames: 3, fps: 10)
        #expect(Self.reason(dice, "radius") == OllinApp.webReasonNondeterministic)
        #expect(dice.controls.isEmpty)

        // A formula's own parameter is never a control; the constant it reads is.
        let constant = try OllinApp.recordWebFrames(of: Constant(), frames: 8, fps: 10)
        #expect(Self.reason(constant, "radius") == OllinApp.webReasonDriven)
        #expect(Self.control(constant, "base") != nil)

        // Asking for no controls probes nothing.
        let plain = try OllinApp.recordWebFrames(of: Dial(), frames: 3, fps: 10, controls: false)
        #expect(plain.controls.isEmpty && plain.axes.isEmpty && plain.leftOut.isEmpty)
    }

    @Test func aShadersRowIsWired() throws {
        let recording = try OllinApp.recordWebFrames(of: Shaded(), frames: 3, fps: 10)
        let amount = try #require(Self.control(recording, "amount"))
        let axis = recording.axes[try #require(amount.parts[0].axis)]
        // The row sits in the parameter region, past every record.
        let graph = recording.frames[0].graph
        #expect(axis.columns.count == 1)
        #expect(axis.columns[0].index == graph.paramOffset)
        #expect(axis.columns[0].slopes.allSatisfy { abs($0 - 1) < 1e-4 })
    }

    @Test func theTrackPacksTheAxesAndLeavesADrivenColumnToItsFormula() throws {
        // A lap: the moving circle's center slopes fit to one sine each, the
        // constant slopes travel as one number.
        let dial = try OllinApp.recordWebFrames(of: Dial(), frames: 20, fps: 10)
        let track = WebTrack(dial)
        let meta = try #require(try JSONSerialization.jsonObject(with: Data(track.meta.utf8)) as? [String: Any])
        let controls = try #require(meta["controls"] as? [[String: Any]])
        #expect(controls.count == 6)
        let axes = try #require(meta["axes"] as? [[String: Any]])
        let radius = try #require(axes.first { $0["name"] as? String == "radius" })
        let cols = try #require(radius["cols"] as? [[Double]])
        let modes = Dictionary(grouping: cols, by: { Int($0[3]) }).mapValues(\.count)
        #expect(modes[0] == 2, "\(modes)")   // the two size columns, slope one
        #expect(modes[1] == 2, "\(modes)")   // the center's two columns, one sine each
        #expect(modes[2] == nil, "\(modes)")
        #expect(track.wiredColumns > 0)
        #expect(!track.axisData.isEmpty)

        // The formula carries the constant's effect on the driven column, so
        // the axis does not carry it again; the page reads the control's
        // value under the parameter's name.
        let constant = try OllinApp.recordWebFrames(of: Constant(), frames: 8, fps: 10)
        let ctrack = WebTrack(constant)
        #expect(ctrack.drivenColumns == 2)
        #expect(ctrack.wiredColumns == 0)
        let cmeta = try #require(try JSONSerialization.jsonObject(with: Data(ctrack.meta.utf8)) as? [String: Any])
        let caxes = try #require(cmeta["axes"] as? [[String: Any]])
        #expect(caxes.count == 1 && (caxes[0]["cols"] as? [[Double]])?.isEmpty == true)
        #expect((cmeta["constants"] as? [String: Double])?["base"] == 40)
    }

    @Test func thePanelIsTheStandalonePagesAndTheHandleIsBoth() throws {
        let recording = try OllinApp.recordWebFrames(of: Dial(), frames: 3, fps: 10)
        let standalone = try OllinApp.webPage(of: recording, form: .standalone)
        #expect(standalone.contains("var PANEL = true;"))
        #expect(standalone.contains("--ollin-panel"))
        #expect(standalone.contains(".ollin-controls { color: #1d1d1f; }"))
        let inline = try OllinApp.webPage(of: recording, form: .inline)
        #expect(inline.contains("var PANEL = false;"))
        #expect(inline.contains("player.set = function"))
        let bare = try OllinApp.webPage(of: recording, form: .standalone, panel: false)
        #expect(bare.contains("var PANEL = false;"))
        #expect(!bare.contains("var(--ollin-panel"))
        // A dark paper gets light text on its panel.
        var dark = recording
        dark.frames = dark.frames.map { f in var g = f; g.clear = SIMD3<Float>(0.01, 0.01, 0.01); return g }
        #expect(try OllinApp.webPage(of: dark, form: .standalone).contains(".ollin-controls { color: #e8e8ed; }"))
    }

    @Test func theProbeSettingsAvoidTheValueAndSnapToTheStep() {
        let plain = OllinApp.webProbeSettings(base: 60, lower: 0, upper: 200, step: nil, integer: false)
        #expect(plain.map(\.value).map { ($0 * 1e4).rounded() / 1e4 } == [0, 200, 76.3932, 123.6068])
        #expect(plain.map(\.isEnd) == [true, true, false, false])
        let fromZero = OllinApp.webProbeSettings(base: 0, lower: 0, upper: 1, step: nil, integer: false)
        #expect(fromZero.count == 3 && !fromZero.contains { $0.value == 0 })
        #expect(OllinApp.webProbeSettings(base: 5, lower: 1, upper: 12, step: 1, integer: true).map(\.value) == [1, 12, 8])
        #expect(OllinApp.webProbeSettings(base: 0.5, lower: 0, upper: 1, step: 0.5, integer: false).map(\.value) == [0, 1])
        // No range: a span around the value.
        #expect(OllinApp.webProbeSettings(base: 3, lower: .infinity, upper: -.infinity, step: nil, integer: false).count == 4)
    }

    // MARK: The page against the Mac

    /// The page's pixels at `frame` with `settings` applied through the handle
    /// before the frame is shown.
    static func pagePixels(_ page: String, frame: Int, settings: String) async throws -> CGImage {
        let probe = """
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          var out = document.getElementById('r0');
          try {
            var player = window.ollin;
            if (!player) { out.textContent = 'FAIL no player'; return; }
            player.pause();
            (player.ready || Promise.resolve()).then(function () {
              \(settings)
              player.showFrame(\(frame));
              out.textContent = player.canvas.toDataURL('image/png');
            }).catch(function (e) { out.textContent = 'FAIL ' + e; });
          } catch (e) { out.textContent = 'FAIL ' + e; }
        })();
        </script>
        """
        let html = "<!doctype html><html><body>\n" + page + "\n" + probe + "\n</body></html>"
        let dom = try await HeadlessBrowser.dom(of: html)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        return try WebExportTests.image(fromDataURL: report)
    }

    /// The Mac's frame with `overrides` applied the way `--param` applies them.
    static func reference(_ make: () -> Sketch, frame: Int, fps: Double, overrides: [String: String]) throws -> CGImage {
        let saved = OllinApp.paramOverrides
        defer { OllinApp.paramOverrides = saved }
        OllinApp.paramOverrides = overrides.sorted { $0.key < $1.key }.map { ParamOverride(name: $0.key, text: $0.value) }
        return try #require(OllinApp.image(of: make(), frame: frame, fps: fps))
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func aMovedControlDrawsWhatTheMacDrawsAtThatSetting() async throws {
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int, settings: String, overrides: [String: String])] = [
            ("Dial, radius and ink", { Dial() }, 20, 7,
             "player.set('radius', 140); player.set('ink', '#cc2200');",
             ["radius": "140", "ink": "#CC2200"]),
            ("Dial, paper", { Dial() }, 20, 13, "player.set('paper', [0.1, 0.2, 0.6]);", ["paper": "0.1,0.2,0.6"]),
            ("Dial, fade", { Dial() }, 20, 13, "player.set('fade', 0.9);", ["fade": "0.9"]),
            ("Dial, switch", { Dial() }, 20, 13, "player.set('filled', true);", ["filled": "true"]),
            ("Dial, anchor", { Dial() }, 20, 13, "player.set('anchor', {x: 90, y: 150});", ["anchor": "90,150"]),
            ("Dial, paper, fade, switch, and anchor", { Dial() }, 20, 13,
             "player.set('paper', [0.1, 0.2, 0.6]); player.set('fade', 0.9); player.set('filled', true); player.set('anchor', {x: 90, y: 150});",
             ["paper": "0.1,0.2,0.6", "fade": "0.9", "filled": "true", "anchor": "90,150"]),
            ("Dial, one part", { Dial() }, 20, 0,
             "player.set('ink.green', 0.7); player.set('anchor.y', 80);",
             ["ink": "0,0.7,0", "anchor": "120,80"]),
            ("Shaded", { Shaded() }, 3, 1,
             "player.set('amount', 0.8);",
             ["amount": "0.8"]),
            ("Constant through its formula", { Constant() }, 8, 5,
             "player.set('base', 70);",
             ["base": "70"]),
            ("Reset", { Dial() }, 20, 7,
             "player.set('radius', 140); player.reset();",
             [:]),
        ]
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 10)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await Self.pagePixels(page, frame: c.probe, settings: c.settings)
            let reference = try Self.reference(c.make, frame: c.probe, fps: 10, overrides: c.overrides)
            let difference = try WebExportTests.meanDifference(played, reference)
            print("web page control against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference))")
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateSeesAControlThatDoesNothing() async throws {
        // The page with the radius moved against the Mac at the recorded
        // value must read as different, or the gate above proves nothing.
        let recording = try OllinApp.recordWebFrames(of: Dial(), frames: 4, fps: 10)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let moved = try await Self.pagePixels(page, frame: 1, settings: "player.set('radius', 140);")
        let recorded = try #require(OllinApp.image(of: Dial(), frame: 1, fps: 10))
        let difference = try WebExportTests.meanDifference(moved, recorded)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theHandleReportsItsParameters() async throws {
        let recording = try OllinApp.recordWebFrames(of: Dial(), frames: 3, fps: 10)
        let page = try OllinApp.webPage(of: recording, form: .standalone)
        let probe = """
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          var p = window.ollin, out = [];
          out.push(p.params.map(function (c) { return c.name + ':' + c.kind + ':' + c.parts.map(function (q) { return q.name; }).join('/'); }).join(','));
          out.push(p.get('radius'));
          p.set('radius', 500);
          out.push(p.get('radius'));
          out.push(JSON.stringify(p.get('ink')));
          p.set('ink', '#ff8000');
          out.push(JSON.stringify(p.get('ink')));
          out.push(p.get('filled'));
          out.push(JSON.stringify(p.get('anchor')));
          out.push(document.querySelectorAll('.ollin-controls input').length);
          out.push(document.querySelector('.ollin-controls input[type=range]').value);
          document.getElementById('r0').textContent = out.join(';');
        })();
        </script>
        """
        let html = page.replacingOccurrences(of: "</body>", with: probe + "\n</body>")
        let dom = try await HeadlessBrowser.dom(of: html)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        let parts = report.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        try #require(parts.count == 9, "\(report)")
        #expect(parts[0] == "radius:number:,fade:number:,ink:color:red/green/blue/alpha,paper:color:red/green/blue,filled:toggle:,anchor:vector:x/y")
        #expect(parts[1] == "60")
        #expect(parts[2] == "200")   // clamped to the range
        #expect(parts[3] == "{\"red\":0,\"green\":0,\"blue\":0,\"alpha\":1}")
        #expect(parts[4] == "{\"red\":1,\"green\":0.5019607843137255,\"blue\":0,\"alpha\":1}")
        #expect(parts[5] == "false")
        #expect(parts[6] == "{\"x\":120,\"y\":120}")
        // Two sliders, a well and its alpha slider, a well, a checkbox, two fields.
        #expect(parts[7] == "8")
        #expect(parts[8] == "200")   // the slider follows the handle
    }
}
