@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import Testing

/// A pass that traces nothing draws its lit kinds through pipelines built without
/// the traced paths. On a GPU that traces rays in software the traversal is
/// compiled into every fragment that can trace, and a fragment carrying it pays on
/// every pixel whether a ray is traced or not: a marched field of fifteen nodes
/// drew in 8.7 ms without it and 170.8 ms with it, and at thirty-one nodes that one
/// draw ran long enough for the GPU to report a hang. So the lit fragments have a
/// second build with the traces constant set to false, and a pass with no
/// structure to trace against draws through it.
@Suite
@MainActor
struct UntracedPipelineTests {
    /// A block and a marched field on a floor under one casting light: a
    /// directional one, whose shadow is a map, or a point one, whose shadow a
    /// device that traces traces.
    final class BlockAndField: Sketch {
        var pointCaster = false
        /// The field drawn large and at the reduced march, so it goes through the
        /// pass of its own that the live tiers march in.
        var reducedMarch = false
        /// The field with no mesh beside it: nothing for a traced shadow to trace against.
        var fieldAlone = false
        override var canvasSize: CanvasSize { .size(200, 140) }
        let block = Mesh.box(width: 1.1, height: 1.1, depth: 1.1)
        let floor = Mesh.plane(width: 12, depth: 12)
        override func draw() {
            background(Color(white: 0.1))
            camera(.perspective(eye: Vector3(0, 3.5, 6), target: Vector3(0, 0.4, 0),
                                fieldOfView: .pi / 4))
            if pointCaster {
                pointLight(.white, at: Vector3(-2.5, 3.5, 1.5), intensity: 1.5)
            } else {
                directionalLight(.white, direction: Vector3(0.45, -0.7, -0.55), intensity: 1)
            }
            ambientLight(Color(white: 0.2))
            castShadows()
            fill(Color(white: 0.8))
            material(.glossy)
            if !fieldAlone {
                drawMesh(floor)
                withState { translate(-1.3, 0.55, 0); drawMesh(block) }
            }
            if reducedMarch { raymarchQuality(.performance) }
            withState {
                translate(1.3, 0.7, 0)
                if reducedMarch { scale(3) }
                fill(Color(red: 0.9, green: 0.4, blue: 0.2))
                drawSDF3D(SDF3D.sphere(radius: 0.55)
                    .smoothUnion(SDF3D.box(size: 0.7).colored(Color(red: 0.2, green: 0.5, blue: 0.9)), k: 0.25))
            }
        }
    }

    /// One frame on a renderer of its own, and the lit pipelines that renderer built.
    private func render(pointCaster: Bool, untraced: Bool = true, reducedMarch: Bool = false,
                        fieldAlone: Bool = false) throws -> (image: CGImage, lit: [MetalRenderer.PipelineKey]) {
        let sketch = BlockAndField()
        sketch.pointCaster = pointCaster
        sketch.reducedMarch = reducedMarch
        sketch.fieldAlone = fieldAlone
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        renderer.usesUntracedPipelines = untraced
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let image = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
        return (image, renderer.pipelines.keys.filter(\.holdsTracedPaths))
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPassWithNothingToTraceDrawsThroughTheUntracedPipelines() throws {
        let frame = try render(pointCaster: false)
        let fragments = Set(frame.lit.map(\.fragment))
        #expect(fragments.contains("ollin_mesh_fragment") && fragments.contains("ollin_raymarch_fragment"),
                "the scene drew no lit mesh or no field: \(fragments)")
        let traced = frame.lit.filter { !$0.untraced }
        #expect(traced.isEmpty, "a pass with nothing to trace built a pipeline that traces: \(traced.map(\.fragment))")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPassThatTracesKeepsTheTracedPaths() throws {
        let frame = try render(pointCaster: true)
        let fragments = Set(frame.lit.map(\.fragment))
        #expect(fragments.contains("ollin_mesh_fragment") && fragments.contains("ollin_raymarch_fragment"),
                "the scene drew no lit mesh or no field: \(fragments)")
        let untraced = frame.lit.filter(\.untraced)
        #expect(untraced.isEmpty, "a pass with a traced shadow drew through a pipeline that cannot trace: \(untraced.map(\.fragment))")
    }

    /// A field with no mesh in the frame, under a point light that casts: the
    /// field shadows itself by its own march, and there is nothing for a traced
    /// shadow to trace against, so no structure is built and the field marches
    /// through the untraced build. A field beside a mesh under the same light
    /// is the case that still pays for the tracer.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFieldAloneUnderAPointCasterTracesNothing() throws {
        let frame = try render(pointCaster: true, fieldAlone: true)
        let field = frame.lit.filter { $0.fragment == "ollin_raymarch_fragment" }
        #expect(!field.isEmpty, "the field was not drawn")
        #expect(field.allSatisfy { $0.untraced }, "a field with nothing to trace against marched through the traced build")
    }

    /// The reduced march's own pass picks its pipeline by the same rule as the
    /// canvas pass: the field's single-sample pipeline is the untraced one when
    /// nothing traces, and the traced one beside a traced shadow.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theReducedMarchPicksItsPipelineTheSameWay() throws {
        for pointCaster in [false, true] {
            let frame = try render(pointCaster: pointCaster, reducedMarch: true)
            let own = frame.lit.filter { $0.fragment == "ollin_raymarch_fragment" && $0.singleSample }
            #expect(!own.isEmpty, "the field did not march in a pass of its own")
            #expect(own.allSatisfy { $0.untraced == !pointCaster },
                    "point caster \(pointCaster): the reduced march's pipeline is \(own.map(\.untraced))")
        }
    }

    /// The untraced build is the same fragment less the paths the frame never
    /// takes, so it changes no picture.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func bothBuildsDrawTheSamePicture() throws {
        let untraced = try render(pointCaster: false, untraced: true)
        let traced = try render(pointCaster: false, untraced: false)
        #expect(traced.lit.allSatisfy { !$0.untraced }, "the switch did not reach the pipelines")
        let difference = try #require(imageDifference(untraced.image, traced.image))
        #expect(difference.max == 0, "the two builds differ by up to \(difference.max) levels (mean \(difference.mean))")
        // And the picture is a picture: the field and the block are both in it.
        let gray = try #require(flat(like: untraced.image))
        let blank = try #require(imageDifference(untraced.image, gray))
        #expect(blank.max > 60, "the frame is blank")
    }

    /// The constant reaches the compiler: the untraced build of each lit fragment
    /// reads no acceleration structure, so Metal lists none among what it uses,
    /// where the traced build uses the one it traces against.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing),
          arguments: [("ollin_mesh_vertex", "ollin_mesh_fragment"),
                      ("ollin_raymarch_vertex", "ollin_raymarch_fragment")])
    func theUntracedBuildBindsNoStructure(vertex: String, fragment: String) throws {
        let renderer = try OllinApp.headlessRenderer(for: BlockAndField())
        func bindsAStructure(untraced: Bool) throws -> Bool {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = renderer.library.makeFunction(name: vertex)
            descriptor.fragmentFunction = try renderer.fragmentFunction(named: fragment, peel: false,
                                                                        untraced: untraced,
                                                                        using: renderer.library)
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            descriptor.depthAttachmentPixelFormat = .depth32Float
            var reflection: MTLRenderPipelineReflection?
            _ = try renderer.device.makeRenderPipelineState(descriptor: descriptor, options: [.bindingInfo],
                                                            reflection: &reflection)
            let bindings = try #require(reflection).fragmentBindings
            // An argument the compiled function never reads stays listed, marked unused.
            return bindings.contains {
                $0.isUsed && ($0.type == .instanceAccelerationStructure || $0.type == .primitiveAccelerationStructure)
            }
        }
        #expect(try bindsAStructure(untraced: false), "the traced build of \(fragment) binds no structure")
        #expect(try !bindsAStructure(untraced: true), "the untraced build of \(fragment) still binds a structure")
    }

    /// A device that does not trace has one build of each fragment, and the flag
    /// stays off it, so no pipeline is built twice.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDeviceThatDoesNotTraceBuildsOneVariant() throws {
        let sketch = BlockAndField()
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        guard !renderer.rayTracedShadows else { return }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        _ = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
        #expect(renderer.pipelines.keys.allSatisfy { !$0.untraced })
    }

    /// A flat image of the background's gray, the size of `image`.
    private func flat(like image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(gray: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}

/// The untraced fragments hold no ray traversal, read off the shader sources and
/// off the GPU's own compiler, so both run anywhere and draw nothing.
@Suite
struct UntracedShaderTests {
    private static var shaderDirectory: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Ollin/Renderer").path
    }

    /// Every traced reflection and refraction asks `ollin_rt_reflects`, which is
    /// where the traces constant is read: a gate that read the lighting's flag on
    /// its own would keep its traced path in the build that traces nothing.
    @Test(arguments: [("Shader3D", 1), ("ShaderRaymarch", 0)])
    func everyReflectionGateAsksTheHelper(file: String, reads: Int) throws {
        let source = try String(contentsOfFile: "\(Self.shaderDirectory)/\(file).metal", encoding: .utf8)
        var found: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = line.components(separatedBy: "//")[0]
            if code.contains("rtReflections") { found.append(code.trimmingCharacters(in: .whitespaces)) }
        }
        #expect(found.count == reads, "\(file) reads rtReflections outside the helper: \(found)")
        if reads == 1 { #expect(found[0].contains("kOllinTraces")) }
    }

    /// Every shader segment in the source tree as one compile unit, each file
    /// once and after what it names, the way the renderer assembles them (its
    /// own assembly is the main actor's, and this suite stays off it).
    private func composedLibrary() throws -> String {
        let directory = Self.shaderDirectory
        func source(_ path: String) -> ShaderIncludes.Source? {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            let key = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            return ShaderIncludes.Source(key: key, name: key, text: text)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".metal") }.sorted()
        let roots = names.compactMap { source("\(directory)/\($0)") }
        try #require(roots.count == names.count && roots.count > 10)
        return ShaderIncludes.resolveAll(roots) { spelling, askedBy in
            let folder = (askedBy as NSString).deletingLastPathComponent
            return source(((folder.isEmpty ? directory : folder) as NSString).appendingPathComponent(spelling))
        }.source
    }

    /// Run a tool and return its exit code and what it printed.
    private func run(_ tool: String, _ arguments: [String], in directory: URL) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [tool] + arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// How many ray-query calls each function of a compiled library reaches,
    /// through its calls: the library as LLVM text, read function by function.
    private func rayQueryReach(inLLVM text: String) -> (String) -> Int? {
        var bodies: [String: String] = [:]
        for chunk in text.components(separatedBy: "\ndefine ").dropFirst() {
            guard let at = chunk.firstIndex(of: "@"),
                  let paren = chunk[at...].firstIndex(of: "(") else { continue }
            let name = chunk[chunk.index(after: at) ..< paren].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let body = chunk.range(of: "\n}\n").map { String(chunk[..<$0.lowerBound]) } ?? chunk
            bodies[name] = body
        }
        func callees(of body: String) -> [String] {
            var found: [String] = []
            for line in body.split(separator: "\n") where line.contains("call ") || line.contains("invoke ") {
                guard let at = line.firstIndex(of: "@"), let paren = line[at...].firstIndex(of: "(") else { continue }
                found.append(line[line.index(after: at) ..< paren].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
            return found
        }
        return { entry in
            guard bodies[entry] != nil else { return nil }
            var seen: Set<String> = [], pending = [entry], queries = 0
            while let function = pending.popLast() {
                guard seen.insert(function).inserted, let body = bodies[function] else { continue }
                for callee in callees(of: body) {
                    if callee.hasPrefix("air."), callee.contains("intersection_query") { queries += 1 }
                    if bodies[callee] != nil { pending.append(callee) }
                }
            }
            return queries
        }
    }

    /// The library built as the untraced pipelines build it (the traces constant
    /// false), compiled by the Metal front end to LLVM text: no lit fragment
    /// reaches a ray query through anything it calls, where the passes that trace
    /// on purpose still do. A traced path that does not ask the constant leaves a
    /// query reachable from the build that should hold none, and brings the
    /// software traversal back into it with no picture changing to say so.
    /// Skipped where the Metal toolchain is not installed.
    @Test func noLitFragmentReachesARayQueryWhenBuiltUntraced() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-untraced-\(ProcessInfo.processInfo.processIdentifier)-\(UInt32.random(in: 0 ..< .max))")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let found = try? run("-f", ["metal"], in: scratch), found.code == 0 else { return }

        // The library as a device that traces compiles it, with the two function
        // constants written in as the untraced pipeline sets them.
        var source = try composedLibrary()
        func fold(_ declaration: String, _ replacement: String) throws {
            try #require(source.contains(declaration), "the shader no longer declares: \(declaration)")
            source = source.replacingOccurrences(of: declaration, with: replacement)
        }
        try fold("constant bool kOllinPeelSet [[function_constant(15)]];", "")
        try fold("constant bool kOllinPeel = is_function_constant_defined(kOllinPeelSet) && kOllinPeelSet;",
                 "constant bool kOllinPeel = false;")
        try fold(", function_constant(kOllinPeel)]]", "]]")
        try fold("constant bool kOllinTracesSet [[function_constant(16)]];", "")
        try fold("constant bool kOllinTraces = !is_function_constant_defined(kOllinTracesSet) || kOllinTracesSet;",
                 "constant bool kOllinTraces = false;")
        try ("#define OLLIN_RT_SHADOWS 1\n" + source)
            .write(to: scratch.appendingPathComponent("lib.metal"), atomically: true, encoding: .utf8)

        let frontEnd = try run("metal", ["-std=metal4.0", "-mmacosx-version-min=26.0", "-O2", "-w",
                                         "-S", "-emit-llvm", "lib.metal", "-o", "lib.ll"], in: scratch)
        try #require(frontEnd.code == 0, "the library did not compile: \(frontEnd.output.prefix(600))")
        let text = try String(contentsOf: scratch.appendingPathComponent("lib.ll"), encoding: .utf8)
        let reach = rayQueryReach(inLLVM: text)

        // The walk sees a query where there is one: the traced export's kernel traces.
        let kernel = try #require(reach("ollin_pt_trace"), "the traced export's kernel is not in the library")
        #expect(kernel > 0, "the walk found no ray query in a kernel that traces")
        for fragment in ["ollin_mesh_fragment", "ollin_mesh_textured_fragment", "ollin_mesh_nm_fragment",
                         "ollin_mesh_maps_fragment", "ollin_raymarch_fragment"] {
            let queries = try #require(reach(fragment), "\(fragment) is not in the library")
            #expect(queries == 0, "\(fragment), built untraced, still reaches \(queries) ray-query calls")
        }
    }
}
