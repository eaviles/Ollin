import Foundation

/// A ready-made starting point: a whole small sketch that already does
/// something, rather than an empty `draw()`.
///
/// Templates are the half of the generator meant to be added to over time. Each
/// one names the capabilities its own code needs, so picking a template picks
/// the libraries and the folders with it, and the ones that only make sense for
/// some kinds say so rather than being offered everywhere.
public struct ProjectTemplate: Sendable, Hashable, Identifiable {
    /// Stable slug used on the command line (`--template shader`).
    public let id: String
    public let title: String
    /// One sentence on what the generated sketch does.
    public let summary: String
    /// Capability ids the template's own code needs. They are switched on for
    /// the caller, so a template is never generated missing an import.
    public let requires: [String]
    /// Kind ids this template fits. Empty means every kind that can be built.
    public let kinds: [String]
    /// The sketch's class body. `{{CLASS}}` is the type name; `{{HINTS}}` is the
    /// line inside `setup()` where extra capabilities leave their starter
    /// comments, and every body must carry it exactly once.
    public let source: String
    /// Files written beside the sketch, for a template that needs more than one.
    public let files: [TemplateFile]

    public init(
        id: String,
        title: String,
        summary: String,
        requires: [String] = [],
        kinds: [String] = [],
        source: String,
        files: [TemplateFile] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.requires = requires
        self.kinds = kinds
        self.source = source
        self.files = files
    }

    /// Whether this template can be generated as `kind`.
    public func fits(_ kind: ProjectKind) -> Bool {
        kinds.isEmpty || kinds.contains(kind.id)
    }
}

/// A file a template writes beside the sketch.
public struct TemplateFile: Sendable, Hashable {
    /// Path relative to the project root.
    public let path: String
    public let contents: String
    /// Whether a generated manifest should declare it as a copied resource, so
    /// the sketch can reach it through `Bundle.module`.
    public let isResource: Bool

    public init(path: String, contents: String, isResource: Bool) {
        self.path = path
        self.contents = contents
        self.isResource = isResource
    }
}

extension ProjectTemplate {

    public static let blank = ProjectTemplate(
        id: "blank",
        title: "Blank",
        summary: "A circle breathing on white. The smallest sketch that already moves.",
        source: """
        /// A starter sketch: a circle breathing on white. Run it, then edit and
        /// save; the window reloads in place. Delete `+ sin(time) * 40` and it
        /// holds still.
        final class {{CLASS}}: Sketch {
            override func setup() {
                {{HINTS}}
            }

            override func draw() {
                background(.white)
                noFill()
                stroke(.black)
                strokeWeight(3)
                drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
            }
        }
        """
    )

    public static let motion = ProjectTemplate(
        id: "motion",
        title: "Motion",
        summary: "A ring of dots orbiting, their radius wandering on noise.",
        source: """
        /// Motion by default: nothing here is animated by hand, it is all read
        /// off `time`. The two knobs are draggable while it runs.
        final class {{CLASS}}: Sketch {
            @Param(6 ... 120, icon: "circle.grid.hex") var count = 36
            @Param(0 ... 2, icon: "speedometer") var speed = 0.6

            override func setup() {
                {{HINTS}}
                noStroke()
            }

            override func draw() {
                background(Color(white: 0.06))

                for i in 0 ..< count {
                    let f = Double(i) / Double(count)
                    let angle = f * .tau + time * speed
                    // Noise, not randomness: it wanders smoothly instead of jumping.
                    let radius = 260 * scale + signedNoise(f * 3, time * 0.3) * 120 * scale
                    let position = center + Vector2(cos(angle), sin(angle)) * radius

                    fill(Color(hue: f, saturation: 0.45, brightness: 1))
                    drawCircle(center: position, radius: (6 + sin(time * 2 + f * .tau) * 3) * scale)
                }
            }
        }
        """
    )

    public static let pattern = ProjectTemplate(
        id: "pattern",
        title: "Pattern",
        summary: "A grid where every cell decides its own mark, held still so you can look at it.",
        source: """
        /// A still piece: the decisions happen once in `setup()`, `noLoop()` holds
        /// the frame, and the seed is what makes this particular one. Run it again
        /// with `--seed 4821` to get the same picture back, or press nothing and
        /// get a new one each launch.
        final class {{CLASS}}: Sketch {
            @Param(2 ... 24, icon: "square.grid.3x3") var columns = 9

            override func setup() {
                {{HINTS}}
                noLoop()
            }

            override func draw() {
                background(Color(hex: 0xF3F0E9))
                noStroke()

                let cells = grid(columns: columns, rows: columns,
                                 padding: .all(70 * scale), gutter: 8 * scale)
                for cell in cells.cells {
                    let shade = random(0.0, 1.0)
                    fill(Color(hue: 0.03 + shade * 0.08, saturation: 0.55, brightness: 0.2 + shade * 0.7))

                    // Three ways a cell can answer, picked at random.
                    switch randomChoice([0, 1, 2]) ?? 0 {
                    case 0: drawCircle(center: cell.center, radius: cell.frame.width * 0.36)
                    case 1: drawRect(cell.frame.inset(by: .all(cell.frame.width * 0.18)))
                    default:
                        let r = cell.frame.inset(by: .all(cell.frame.width * 0.16))
                        drawPolygon([r.bottomLeft, Vector2(r.center.x, r.y), r.bottomRight])
                    }
                }
            }
        }
        """
    )

    public static let shader = ProjectTemplate(
        id: "shader",
        title: "Shader",
        summary: "A fragment shader of your own, run over every pixel.",
        source: """
        /// A shader you wrote, run through the effect graph. The contract is one
        /// function: `shade(uv, info)` gets a 0...1 coordinate and returns a color.
        /// A mistake in it is reported at this file's own line numbers.
        final class {{CLASS}}: Sketch {
            private let field = Shader(\"""
            float4 shade(float2 uv, ShaderInfo info) {
                float2 p = (uv * 2.0 - 1.0);
                p.x *= info.resolution.x / info.resolution.y;

                // A slow radial ripple, colored through a cosine palette.
                float d = length(p) * 4.0 - info.time * 0.8;
                float v = 0.5 + 0.5 * sin(d);
                float3 color = palette(v, float3(0.5), float3(0.5),
                                       float3(1.0), float3(0.0, 0.33, 0.67));
                return float4(color, 1.0);
            }
            \""")

            override func setup() {
                {{HINTS}}
            }

            override func draw() {
                drawImage(generate(field).image, 0, 0)
            }
        }
        """
    )

    public static let effects = ProjectTemplate(
        id: "effects",
        title: "Layered effects",
        summary: "Draw into an off-screen layer, filter it on the GPU, composite it back.",
        source: """
        /// Layers: `renderTarget()` makes an off-screen surface, `withTarget { }`
        /// redirects drawing into it, `filtered(_:)` runs a GPU filter over it, and
        /// `drawImage(layer.image)` puts the result on the canvas. Nothing goes
        /// back to the CPU in between.
        final class {{CLASS}}: Sketch {
            @Param(0 ... 4, icon: "lightbulb") var glow = 1.6

            override func setup() {
                {{HINTS}}
                noStroke()
            }

            override func draw() {
                background(Color(white: 0.03))

                let marks = renderTarget()
                withTarget(marks) {
                    background(.clear)
                    let n = 40
                    for i in 0 ..< n {
                        let f = Double(i) / Double(n)
                        let angle = f * .tau + time * 0.4
                        let radius = (250 + sin(time * 1.4 + f * .tau * 3) * 70) * scale
                        fill(Color(hue: f, saturation: 0.4, brightness: 1))
                        drawCircle(center: center + Vector2(cos(angle), sin(angle)) * radius,
                                   radius: 10 * scale)
                    }
                }

                drawImage(marks.filtered(.bloom(threshold: 0.35, intensity: glow)).image, 0, 0)
            }
        }
        """
    )

    public static let threeD = ProjectTemplate(
        id: "3d",
        title: "3D",
        summary: "A lit solid on a ground plane, with the camera drifting around it.",
        source: """
        /// 3D is opt-in: asking for a camera is what turns it on. Lighting is
        /// per-frame, so the lights are placed at the top of `draw()` and shade
        /// every mesh drawn after them.
        final class {{CLASS}}: Sketch {
            override func setup() {
                {{HINTS}}
            }

            override func draw() {
                background(Color(hex: 0x0B0D12))

                // Drifts on its own, and you can drag it. It eases back when you stop.
                cameraShowcase(.autoOrbit(period: 24), target: Vector3(0, 1.1, 0), radius: 7,
                               elevation: 0.30, fieldOfView: .pi / 4)

                ambientLight(Color(white: 0.14))
                directionalLight(.white, direction: Vector3(-0.4, -0.85, -0.45), intensity: 0.9)
                castShadows()

                material(.physicallyBased(metallic: 0.1, roughness: 0.35))
                fill(Color(hue: 0.57, saturation: 0.45, brightness: 0.95))
                withState {
                    translate(0, 1.2, 0)          // sitting on the floor, not floating
                    rotateY(time * 0.3)
                    drawIcosphere(radius: 1.2, subdivisions: 3)
                }

                material(.physicallyBased(metallic: 0, roughness: 0.9))
                fill(Color(white: 0.42))
                drawPlane(width: 12, depth: 12)
            }
        }
        """
    )

    public static let plotter = ProjectTemplate(
        id: "plotter",
        title: "Plotter line work",
        summary: "Pen-ready line work on paper, made to leave as an SVG or a PDF.",
        source: """
        /// Line work for a pen: no fills, one weight, sized to a real sheet. Export
        /// it as vectors with `--export-svg out.svg` (or `--export-pdf out.pdf`) and
        /// the lines stay lines all the way to the plotter.
        final class {{CLASS}}: Sketch {
            override var canvasSize: CanvasSize { .a4 }

            override func setup() {
                {{HINTS}}
                noLoop()
            }

            override func draw() {
                background(.white)
                noFill()
                stroke(.black)
                strokeWeight(1)

                // Lines that ride a noise field, so no two are quite parallel.
                let margin = 48.0
                var y = margin
                while y < height - margin {
                    var points = [Vector2]()
                    var x = margin
                    while x <= width - margin {
                        let lift = signedNoise(x * 0.006, y * 0.01) * 14
                        points.append(Vector2(x, y + lift))
                        x += 6
                    }
                    drawPolyline(points)
                    y += 9
                }
            }
        }
        """
    )

    public static let camera = ProjectTemplate(
        id: "camera",
        title: "Camera",
        summary: "The webcam as live material, ready for a tracker to be attached.",
        requires: ["vision"],
        source: """
        /// The camera as an image the sketch draws. This is the foundation the
        /// trackers build on: attach a `FaceTracker` (or a hand, body, or contour
        /// one) to this same camera and read its results in `draw()`.
        final class {{CLASS}}: Sketch {
            let camera = Camera()

            override func setup() {
                {{HINTS}}
                try? camera.start()
            }

            override func draw() {
                background(Color(white: 0.07))
                drawFrame(camera)
            }
        }
        """
    )

    public static let sound = ProjectTemplate(
        id: "sound",
        title: "Sound reactive",
        summary: "Bars driven by what the microphone hears.",
        requires: ["audio"],
        source: """
        /// The microphone read as a picture. `bands(_:)` hands back log-spaced,
        /// normalized levels, which is the shape a drawing actually wants.
        final class {{CLASS}}: Sketch {
            let mic = AudioInput()
            @Param(8 ... 128, icon: "waveform") var bars = 64

            override func setup() {
                {{HINTS}}
                noStroke()
                try? mic.start()
            }

            override func draw() {
                background(Color(white: 0.05))

                let levels = mic.bands(bars)
                let barWidth = width / Double(levels.count)
                for (i, level) in levels.enumerated() {
                    let h = Double(level) * height * 0.8
                    fill(Color(hue: Double(i) / Double(levels.count) * 0.7, saturation: 0.5, brightness: 1))
                    drawRect(Double(i) * barWidth, height - h, barWidth - 2, h)
                }
            }
        }
        """
    )

    public static let physics = ProjectTemplate(
        id: "physics",
        title: "Physics",
        summary: "A pile of discs settling under gravity, stepped every frame.",
        requires: ["physics"],
        source: """
        /// Motion from simulation rather than from typed numbers: the world is
        /// stepped once a frame and the sketch draws wherever things ended up.
        final class {{CLASS}}: Sketch {
            let world = World()
            let count = 140

            override func setup() {
                {{HINTS}}
                noStroke()

                world.bounds = bounds
                world.bounce = 0.4
                world.collisions = true

                for _ in 0 ..< count {
                    let radius = random(10, 26) * scale
                    _ = world.addParticle(at: Vector2(random(0, width), random(0, height * 0.4)),
                                          radius: radius, mass: radius * radius)
                }
            }

            override func draw() {
                background(Color(hex: 0x101318))
                world.step(dt: deltaTime)

                for (i, particle) in world.particles.enumerated() {
                    fill(Color(hue: Double(i) / Double(count) * 0.5 + 0.5, saturation: 0.4, brightness: 1))
                    drawCircle(center: particle.position, radius: particle.radius)
                }
            }
        }
        """
    )

    /// Every template, in the order a gallery should show them: the plainest
    /// first, then the ones that reach for more of the framework.
    public static let all: [ProjectTemplate] = [
        .blank, .motion, .pattern, .shader, .effects, .threeD, .plotter,
        .camera, .sound, .physics,
    ]

    public static func named(_ id: String) -> ProjectTemplate? {
        all.first { $0.id == id }
    }

    /// The templates that can be generated as `kind`.
    public static func fitting(_ kind: ProjectKind) -> [ProjectTemplate] {
        all.filter { $0.fits(kind) }
    }
}
