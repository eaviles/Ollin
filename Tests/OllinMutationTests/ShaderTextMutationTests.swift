import Foundation
import Testing
import OllinMutation
@testable import Ollin
@testable import OllinProjects

/// The shader text a sketch is handed: a fragment shader pasted from the web
/// for the GLSL importer to translate, and a Metal file whose `#include`s the
/// resolver follows. Both are text a person did not write for Ollin, so both
/// run under the harness; the resolver's run keeps a cycle (a file that
/// includes itself through another) and a missing file in play on every case.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct ShaderTextMutationTests {

    @Test func glslShaders() {
        let image = """
        precision highp float;
        struct Ray { vec3 o; vec3 d; };
        const float TAU = 6.2831853;
        float field(vec2 p, float t) { return sin(p.x * 3.0 + t) * cos(p.y * 2.0 - t); }
        vec3 tint(float v) { return 0.5 + 0.5 * cos(TAU * (v + vec3(0.0, 0.33, 0.67))); }
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
            float v = field(uv * 4.0, iTime);
            vec4 prior = texture(iChannel0, fragCoord / iResolution.xy);
            float grid[3] = float[3](1.0, 0.5, 0.25);
            v += mod(uv.x, 0.5) * grid[int(mod(float(iFrame), 3.0))];
            if (iMouse.z > 0.0) { v *= 1.5; }
            fragColor = vec4(mix(tint(v), prior.rgb, 0.2), 1.0);
        }
        """
        let plain = """
        uniform float time;
        out vec4 color;
        void main() {
            vec2 p = gl_FragCoord.xy / 512.0;
            mat2 r = mat2(cos(time), -sin(time), sin(time), cos(time));
            p = r * p;
            color = vec4(fract(p * 8.0), 0.5 + 0.5 * sin(time), 1.0);
            if (p.x > 0.5) discard;
        }
        """
        let report = MutationRun.run("glsl-shader", seeds: [image.bytes, plain.bytes], count: 500, sweeps: false,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let result = ShaderImport.translate(glsl: String(decoding: bytes, as: UTF8.self),
                                                provenance: .init(title: "t", author: "a", url: "u"))
            _ = result.needsAttention
            return !result.metalSource.isEmpty
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func includedShaderFiles() {
        let root = """
        #include "noise.metal"
        #include "loop.metal"
        #include "missing.metal"
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(noise(uv), 0, 1);
        }
        """
        var files = [
            "noise.metal": "#include \"hash.metal\"\nfloat noise(float2 p) { return hash(p); }\n",
            "hash.metal": "float hash(float2 p) { return fract(sin(dot(p, float2(12.9, 78.2))) * 43758.5); }\n",
            "loop.metal": "#include \"back.metal\"\n",
            "back.metal": "#include \"loop.metal\"\n#include \"sketch.metal\"\n",
        ]
        func resolve(_ text: String) -> ShaderIncludes.Result {
            ShaderIncludes.resolve(text, name: "sketch.metal", startLine: 3, leadingLineDirective: true,
                                   rootKey: "sketch.metal") { spelling, _ in
                guard let body = spelling == "sketch.metal" ? text : files[spelling] else { return nil }
                return ShaderIncludes.Source(key: spelling, name: spelling, text: body)
            }
        }
        let fromRoot = MutationRun.run("include-root", seeds: [root.bytes], count: 500, sweeps: false,
                                       allocations: fileBound) { bytes in
            let result = resolve(String(decoding: bytes, as: UTF8.self))
            return !result.source.isEmpty
        }
        #expect(fromRoot.seedsRefused.isEmpty, "\(fromRoot)")
        #expect(fromRoot.oversizedCount == 0, "\(fromRoot)")

        let original = files["noise.metal"] ?? ""
        let fromIncluded = MutationRun.run("include-file", seeds: [original.bytes], count: 500, sweeps: false,
                                           allocations: fileBound) { bytes in
            files["noise.metal"] = String(decoding: bytes, as: UTF8.self)
            let result = resolve(root)
            return result.problems.count >= 2
        }
        #expect(fromIncluded.seedsRefused.isEmpty, "\(fromIncluded)")
        #expect(fromIncluded.oversizedCount == 0, "\(fromIncluded)")
    }
}
