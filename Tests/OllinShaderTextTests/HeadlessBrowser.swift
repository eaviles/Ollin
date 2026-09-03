import Foundation

/// A headless browser as a GLSL compiler. WebGL compiles a shader synchronously,
/// so a page that compiles one and writes the result into its own DOM reports
/// through the browser's DOM dump; no server, no driver, no waiting on a promise.
enum HeadlessBrowser {

    /// The browser to run, if one is installed: `OLLIN_CHROME` first, then the
    /// usual application paths.
    static let executable: String? = {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["OLLIN_CHROME"], fm.isExecutableFile(atPath: env) {
            return env
        }
        let candidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }()

    static var isAvailable: Bool { executable != nil }

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// Loads `html` from a temporary file and returns the DOM once its scripts
    /// have run. A browser that never exits is killed after `timeout`, so a hang
    /// fails the test instead of parking the run.
    ///
    /// No `--user-data-dir` is passed on purpose: with one, the browser here
    /// dumped the DOM and then never exited.
    static func dom(of html: String, timeout: TimeInterval = 90) throws -> String {
        guard let browser = executable else { throw Failure(description: "no browser is installed") }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-web-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = folder.appendingPathComponent("page.html")
        try html.write(to: page, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: browser)
        process.arguments = ["--headless=new", "--no-first-run", "--enable-unsafe-swiftshader",
                             "--dump-dom", page.absoluteString]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw Failure(description: "the browser wrote nothing (exit status \(process.terminationStatus))")
        }
        return text
    }

    /// The text content of the element with `id`, with the DOM dump's escapes undone.
    static func text(of id: String, in dom: String) -> String? {
        guard let attribute = dom.range(of: "id=\"\(id)\"") else { return nil }
        let rest = dom[attribute.upperBound...]
        guard let open = rest.range(of: ">"),
              let close = rest.range(of: "</", range: open.upperBound..<rest.endIndex) else { return nil }
        return unescape(String(rest[open.upperBound..<close.lowerBound]))
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// The two pages the gate uses: one that compiles and links a list of fragment
/// shaders, and one that draws a fragment shader across a row of pixels and
/// reads the bytes back.
enum WebGLPage {

    /// Each shader lands in `<script id="sN">`, each verdict in `<pre id="rN">`:
    /// `OK`, or `FAIL` followed by the compiler's log.
    static func compile(_ shaders: [String]) -> String {
        var html = "<!doctype html><html><body>\n"
        for (i, shader) in shaders.enumerated() {
            html += "<script type=\"text/plain\" id=\"s\(i)\">\(shader)</script>\n"
            html += "<pre id=\"r\(i)\">PENDING</pre>\n"
        }
        html += """
        <script>
        (function () {
          var count = \(shaders.count);
          function report(i, text) { document.getElementById('r' + i).textContent = text; }
          var gl = document.createElement('canvas').getContext('webgl2');
          if (!gl) { for (var i = 0; i < count; i++) report(i, 'FAIL no WebGL2 context'); return; }
          var vertexSource = '#version 300 es\\nvoid main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }';
          for (var i = 0; i < count; i++) {
            var source = document.getElementById('s' + i).textContent;
            var fs = gl.createShader(gl.FRAGMENT_SHADER);
            gl.shaderSource(fs, source);
            gl.compileShader(fs);
            if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) {
              report(i, 'FAIL compile\\n' + gl.getShaderInfoLog(fs));
              continue;
            }
            var vs = gl.createShader(gl.VERTEX_SHADER);
            gl.shaderSource(vs, vertexSource);
            gl.compileShader(vs);
            var program = gl.createProgram();
            gl.attachShader(program, vs);
            gl.attachShader(program, fs);
            gl.linkProgram(program);
            if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
              report(i, 'FAIL link\\n' + gl.getProgramInfoLog(program));
              continue;
            }
            report(i, 'OK');
          }
        })();
        </script>
        </body></html>
        """
        return html
    }

    /// Draws `fragment` over a `width` by 1 canvas and writes the pixels read back
    /// into `<pre id="r0">` as bytes, `r,g,b,a` per pixel joined by `;`. A failure
    /// to compile or link reports as the compile page does.
    static func pixels(fragment: String, width: Int) -> String {
        """
        <!doctype html><html><body>
        <script type="text/plain" id="s0">\(fragment)</script>
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          function report(text) { document.getElementById('r0').textContent = text; }
          var canvas = document.createElement('canvas');
          canvas.width = \(width); canvas.height = 1;
          var gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, antialias: false, premultipliedAlpha: false });
          if (!gl) { report('FAIL no WebGL2 context'); return; }
          var vertexSource = '#version 300 es\\nvoid main() {'
            + ' vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);'
            + ' gl_Position = vec4(p, 0.0, 1.0); }';
          var vs = gl.createShader(gl.VERTEX_SHADER);
          gl.shaderSource(vs, vertexSource); gl.compileShader(vs);
          var fs = gl.createShader(gl.FRAGMENT_SHADER);
          gl.shaderSource(fs, document.getElementById('s0').textContent); gl.compileShader(fs);
          if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) { report('FAIL compile\\n' + gl.getShaderInfoLog(fs)); return; }
          var program = gl.createProgram();
          gl.attachShader(program, vs); gl.attachShader(program, fs); gl.linkProgram(program);
          if (!gl.getProgramParameter(program, gl.LINK_STATUS)) { report('FAIL link\\n' + gl.getProgramInfoLog(program)); return; }
          gl.useProgram(program);
          gl.viewport(0, 0, \(width), 1);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
          var bytes = new Uint8Array(\(width) * 4);
          gl.readPixels(0, 0, \(width), 1, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
          var pixels = [];
          for (var i = 0; i < \(width); i++) pixels.push(Array.from(bytes.slice(i * 4, i * 4 + 4)).join(','));
          report(pixels.join(';'));
        })();
        </script>
        </body></html>
        """
    }

    /// The bytes a `pixels` page reported, one `[r, g, b, a]` per pixel.
    static func bytes(from report: String) -> [[Int]] {
        report.split(separator: ";").map { $0.split(separator: ",").compactMap { Int($0) } }
    }
}
