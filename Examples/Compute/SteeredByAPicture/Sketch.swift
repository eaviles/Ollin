import Ollin

/// A quarter of a million particles that steer by a picture the sketch draws.
/// Every frame a word and a disc under the pointer are drawn into a layer, and
/// the layer is blurred into a soft field of light. Each particle reads that
/// field at two points ahead of it, one to each side, and turns toward the
/// brighter one, so the crowd climbs onto the ridges of the letters and traces
/// them in light. Press and drag to add a disc to the field the crowd chases.
///
/// The step reads the blurred layer with `picture(0, point)`, handed over by
/// `stepParticles(_:custom:textures:)`. The layer is read as drawn this frame,
/// after its blur, so moving the pointer moves the field the particles feel on
/// the same frame. Nothing comes back to the CPU: the field stays a texture and
/// the particles stay a buffer.
@main
final class SteeredByAPicture_Example: Sketch {
    @Param(4 ... 80, icon: "drop") var blur = 26.0
    @Param(0 ... 120, icon: "arrow.turn.up.right") var turn = 60.0
    @Param(2 ... 40, icon: "ruler") var reach = 16.0
    @Param(20 ... 300, icon: "hare") var speed = 120.0
    @Param(icon: "eye") var showsField = true

    lazy var swarm = Particles(count: 250_000, step: """
        // The dead come back anywhere, heading any way, with a staggered life.
        if (life <= 0.0) {
            position = hash22(float2(float(id) * 0.61, seedA + float(u.frameCount))) * u.resolution;
            float a = hash12(float2(seedA, float(id))) * 6.2831853;
            velocity = float2(cos(a), sin(a));
            life = 2.0 + hash12(float2(float(id), seedA + 7.0)) * 4.0;
            seedA += 1.0;
        }

        // Two readings of the field ahead, one to each side; turn toward the
        // brighter, with a little wander so a crowd on a ridge keeps moving.
        float2 heading = normalize(velocity);
        float2 side = float2(-heading.y, heading.x);
        float left = picture(0, position + (heading + side * 0.6) * custom.y).r;
        float right = picture(0, position + (heading - side * 0.6) * custom.y).r;
        float here = picture(0, position).r;
        float wander = hash12(float2(float(id), float(u.frameCount))) * 2.0 - 1.0;
        velocity = rotate2D(heading, ((left - right) * custom.x + wander * 2.0) * u.dt);
        position += velocity * custom.z * u.dt;

        // A particle out in the dark lives a shorter life, so the crowd gathers
        // where the field is bright and the dark keeps a thin haze.
        life -= u.dt * (1.0 + 4.0 * (1.0 - saturate(here * 2.0)));

        // Faint and blue in the dark, warm and brighter on the field.
        float lit = saturate(here * 1.6);
        color = float4(mix(float3(0.10, 0.22, 0.55), float3(1.0, 0.70, 0.40), lit), 0.12 + 0.3 * lit);
        size = 1.2;
    """)

    override func setup() {
        toneMap(.aces, exposure: 1.2)
    }

    override func draw() {
        background(Color(hex: 0x05070C))

        // The picture the particles read: a word, and a disc under a pressed pointer.
        let marks = makeRenderTarget()
        withTarget(marks) {
            background(.black)
            noStroke()
            fill(.white)
            textFont(.systemBold)
            textSize(height * 0.22)
            textAlign(.center, .middle)
            drawText("OLLIN", width / 2, height / 2)
            if mouseIsPressed { drawCircle(mouseX, mouseY, height * 0.06) }
        }
        let field = marks.filtered(.gaussianBlur(radius: blur)).image

        if showsField {
            withState {
                tint(Color(white: 1, alpha: 0.12))
                drawImage(field, 0, 0)
            }
        }

        stepParticles(swarm, custom: SIMD4(Float(turn), Float(reach), Float(speed), 0),
                      textures: [field])
        blendMode(.add)
        drawParticles(swarm, style: .light, maxSize: 1.2)
    }
}
