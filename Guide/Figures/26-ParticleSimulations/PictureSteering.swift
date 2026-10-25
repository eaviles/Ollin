// figure: frame=300
//
// Guide figure (Chapter 26): one picture, read two ways. The word is drawn into
// a layer and blurred, and the same step reads it in both halves. On the left
// the particles only take their color from it; on the right they also turn
// toward the brighter of two readings ahead, and gather onto the letters'
// ridges. A particle out in the dark lives a shorter life in both.
import Ollin

final class PictureSteering: Sketch {
    override var canvasSize: CanvasSize { .size(1280, 560) }

    static let step = """
        float x0 = custom.y, w = custom.z;
        if (life <= 0.0 || position.x < x0 || position.x > x0 + w) {
            float2 r = hash22(float2(float(id) * 0.61, seedA + float(u.frameCount)));
            position = float2(x0 + r.x * w, r.y * u.resolution.y);
            float a = hash12(float2(seedA, float(id))) * 6.2831853;
            velocity = float2(cos(a), sin(a));
            life = 2.0 + hash12(float2(float(id), seedA + 7.0)) * 4.0;
            seedA += 1.0;
        }
        float2 heading = normalize(velocity);
        float2 side = float2(-heading.y, heading.x);
        float left = picture(0, position + (heading + side * 0.6) * 16.0).r;
        float right = picture(0, position + (heading - side * 0.6) * 16.0).r;
        float here = picture(0, position).r;
        float wander = hash12(float2(float(id), float(u.frameCount))) * 2.0 - 1.0;
        velocity = rotate2D(heading, ((left - right) * custom.x + wander * 2.0) * u.dt);
        position += velocity * 120.0 * u.dt;
        life -= u.dt * (1.0 + 4.0 * (1.0 - saturate(here * 2.0)));
        float lit = saturate(here * 1.6);
        color = float4(mix(float3(0.10, 0.22, 0.55), float3(1.0, 0.70, 0.40), lit), 0.12 + 0.3 * lit);
        size = 1.2;
    """

    lazy var colored = Particles(count: 150_000, step: Self.step)
    lazy var steered = Particles(count: 150_000, step: Self.step)

    override func setup() {
        toneMap(.aces, exposure: 1.2)
    }

    override func draw() {
        background(Color(hex: 0x05070C))
        let half = width / 2

        let marks = makeRenderTarget()
        withTarget(marks) {
            background(.black)
            noStroke()
            fill(.white)
            textFont(.systemBold)
            textSize(height * 0.3)
            textAlign(.center, .middle)
            drawText("LOOP", half / 2, height / 2)
            drawText("LOOP", half * 1.5, height / 2)
        }
        let field = marks.filtered(.gaussianBlur(radius: 16)).image

        withState {
            tint(Color(white: 1, alpha: 0.12))
            drawImage(field, 0, 0)
        }
        stepParticles(colored, custom: SIMD4(0, 0, Float(half), 0), textures: [field])
        stepParticles(steered, custom: SIMD4(60, Float(half), Float(half), 0), textures: [field])
        blendMode(.add)
        drawParticles(colored, style: .light, maxSize: 1.2)
        drawParticles(steered, style: .light, maxSize: 1.2)
        blendMode(.normal)

        noStroke()
        fill(Color(white: 0.8))
        textFont(.system)
        textSize(17)
        textAlign(.center, .bottom)
        drawText("colored by the picture", half / 2, height - 18)
        drawText("steered by it", half * 1.5, height - 18)
    }
}
