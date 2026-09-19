// The physics of the picture: where light goes near a black hole, how the disk
// around it shines, and what color a hot body is. Nothing here knows about the
// screen, so the tests read this file on its own and check it against closed
// forms (`Tests/OllinTests/BlackHoleLensTests.swift`).
//
// Units: the radius of the horizon (the Schwarzschild radius, 2GM/c²) is 1, and
// so is the speed of light. In those units the photon sphere, where light can
// circle the hole, is at r = 1.5; the innermost stable orbit, where the disk
// ends, is at r = 3; and a ray passing far from the hole at impact parameter b
// is bent by 2 / b, which is 4GM / (c² b) in ordinary units.

// MARK: - Light paths

// How far the angle advances per step, in radians, and how far a ray may swing
// before it is given up as circling the photon sphere. A ray that has swept
// five half-turns has passed so close to the sphere that its image is thinner
// than a pixel.
#define LENS_STEP 0.08
#define LENS_MAX_STEPS 200

// Everything a traced ray reports.
struct LensTrace {
    // 1 when the ray escaped to the sky, 0 when the hole took it (or it was
    // still circling the photon sphere when the steps ran out).
    float escaped;
    // The direction the light came from, far away. Only meaningful when it
    // escaped.
    float3 sky;
    // The angle the ray swept in its plane before it reached the sky.
    float swept;
    // The ray's impact parameter, and its angular momentum about the disk's
    // axis (y), both per unit of energy at infinity. The second is what the
    // disk's motion makes a Doppler shift of.
    float impact;
    float lz;
    // Where the ray crossed the disk, nearest first: xyz is the point, w its
    // distance from the hole. `hits` says how many are filled. A ray can cross
    // the disk more than once, which is how the far side of the disk comes to
    // be seen over the top of the hole.
    int hits;
    float4 hit0;
    float4 hit1;
    float4 hit2;
};

// The orbit equation for light: u'' = 1.5 u² - u, with u = 1 / r and ' the
// derivative by the angle the ray has swept in its plane. One classical
// Runge-Kutta step of size h, on (u, u').
static float2 lens_step(float u, float du, float h) {
    float2 k1 = float2(du, 1.5 * u * u - u);
    float u2 = u + 0.5 * h * k1.x, du2 = du + 0.5 * h * k1.y;
    float2 k2 = float2(du2, 1.5 * u2 * u2 - u2);
    float u3 = u + 0.5 * h * k2.x, du3 = du + 0.5 * h * k2.y;
    float2 k3 = float2(du3, 1.5 * u3 * u3 - u3);
    float u4 = u + h * k3.x, du4 = du + h * k3.y;
    float2 k4 = float2(du4, 1.5 * u4 * u4 - u4);
    return float2(u + h / 6.0 * (k1.x + 2.0 * k2.x + 2.0 * k3.x + k4.x),
                  du + h / 6.0 * (k1.y + 2.0 * k2.y + 2.0 * k3.y + k4.y));
}

// u part way through a step, from the values and slopes at both ends (a cubic
// Hermite curve, as accurate as the step itself). x runs 0 to 1 over the step.
static float lens_between(float u0, float du0, float u1, float du1, float h, float x) {
    float x2 = x * x, x3 = x2 * x;
    return (2.0 * x3 - 3.0 * x2 + 1.0) * u0 + (x3 - 2.0 * x2 + x) * h * du0
         + (3.0 * x2 - 2.0 * x3) * u1 + (x3 - x2) * h * du1;
}

// Follow a ray backward from a camera hovering at `camera` (held in place, not
// falling), leaving along the unit vector `ray` in the camera's own frame. The
// disk lies in the plane y = 0 between radii `inner` and `outer`.
//
// Light stays in one plane through the hole: the plane holding the camera and
// the ray. In that plane the path is u(φ), stepped with a fixed step in φ. A
// ray that swings close to the hole sweeps more angle, so the steps crowd in
// there without being asked, and the sky is u = 0, reached at a finite angle,
// so the direction the light came from is read where u crosses zero rather than
// guessed at some large radius. The disk's plane meets the ray's plane in a
// line through the hole, so the ray can only cross the disk at the two angles
// along that line, every half-turn; the crossings are found exactly, and the
// disk can be infinitely thin.
static LensTrace lens_trace(float3 camera, float3 ray, float inner, float outer) {
    LensTrace t;
    t.escaped = 0.0;
    t.sky = float3(0.0);
    t.swept = 0.0;
    t.impact = 0.0;
    t.lz = 0.0;
    t.hits = 0;
    t.hit0 = float4(0.0);
    t.hit1 = float4(0.0);
    t.hit2 = float4(0.0);

    float r0 = length(camera);
    float3 e1 = camera / r0;
    float outward = dot(ray, e1);
    float3 across = ray - outward * e1;
    // The sine of the angle off the radial, taken from a cross product rather
    // than from `across`, whose subtraction cancels for a ray aimed nearly at
    // the hole from far away.
    float sideways = length(cross(ray, e1));

    // A camera held in place sees light a little blueshifted, and measures
    // angles against its own clock and ruler. Both enter as this factor.
    float held = sqrt(1.0 - 1.0 / r0);
    t.impact = r0 * sideways / held;
    // The light arriving here travels along -ray; its angular momentum is
    // camera x (-ray), per unit energy at infinity.
    t.lz = -cross(camera, ray).y / held;

    if (sideways < 1e-7) {
        // Straight out or straight in, with no plane to turn in.
        if (outward > 0.0) {
            t.escaped = 1.0;
            t.sky = e1;
        }
        return t;
    }
    float3 e2 = normalize(across);

    // The camera's angle to the hole fixes where the ray starts on its orbit:
    // tan(angle from the radial) = u * sqrt(1 - u) / |du/dφ| for a camera held
    // in place, which is the flat-space rule stretched by the curvature there.
    float u = 1.0 / r0;
    float du = -u * sqrt(1.0 - u) * outward / sideways;

    // The ray's plane meets the disk's plane where cos(φ) e1.y + sin(φ) e2.y
    // is zero: at `node` and every half-turn after it.
    const float pi = 3.14159265358979;
    float node = 1e9;
    if (abs(e1.y) > 1e-7 || abs(e2.y) > 1e-7) {
        node = atan2(-e1.y, e2.y);
        node -= pi * floor(node / pi);
        if (node < 1e-6) { node += pi; }
    }

    float phi = 0.0;
    for (int i = 0; i < LENS_MAX_STEPS; ++i) {
        // Inside the photon sphere and still falling, nothing turns a ray back.
        if (u > 2.0 / 3.0 && du > 0.0) { return t; }

        float2 next = lens_step(u, du, LENS_STEP);
        float phiNext = float(i + 1) * LENS_STEP;

        if (node <= phiNext) {
            float uc = lens_between(u, du, next.x, next.y, LENS_STEP, (node - phi) / LENS_STEP);
            if (uc > 0.0) {
                float rc = 1.0 / uc;
                if (rc >= inner && rc <= outer) {
                    float3 at = (cos(node) * e1 + sin(node) * e2) * rc;
                    float4 hit = float4(at.x, 0.0, at.z, rc);
                    if (t.hits == 0) { t.hit0 = hit; }
                    else if (t.hits == 1) { t.hit1 = hit; }
                    else if (t.hits == 2) { t.hit2 = hit; }
                    t.hits = min(t.hits + 1, 3);
                }
            }
            node += pi;
        }

        if (next.x <= 0.0) {
            // u reaches zero inside this step. So close to it the bending
            // term 1.5 u² is negligible and the path is a sine, whose zero is
            // exact.
            float rest = atan2(u, -du);
            t.escaped = 1.0;
            t.swept = phi + rest;
            t.sky = cos(t.swept) * e1 + sin(t.swept) * e2;
            return t;
        }
        u = next.x;
        du = next.y;
        phi = phiNext;
    }
    return t;
}

// MARK: - The disk

// The disk's material circles at the Keplerian rate, which a circular orbit
// keeps exactly in this geometry: Ω = sqrt(GM / r³), sqrt(1 / (2 r³)) here.
static float disk_turn_rate(float r) {
    return sqrt(0.5 / (r * r * r));
}

// g, the ratio of the frequency the camera sees to the frequency the disk sent,
// for light leaving the disk at radius r with angular momentum lz about the
// axis. The disk turns counter-clockwise seen from above (+y). Three effects
// in one: the climb out of the well (sqrt(1 - 1.5 / r), which includes the time
// dilation of the moving material), the Doppler shift of that motion (the
// 1 - Ω lz), and the camera's own blueshift from being held in place at r0.
// `beaming` scales only the Doppler part: 1 is the physics, 0 takes the motion
// away. g above 1 is bluer and brighter, below 1 redder and dimmer.
static float disk_shift(float r, float lz, float r0, float beaming) {
    float omega = disk_turn_rate(r);
    return sqrt(1.0 - 1.5 / r) / (sqrt(1.0 - 1.0 / r0) * (1.0 - beaming * omega * lz));
}

// The heat a thin disk radiates at radius r, from Page and Thorne (1974) for a
// disk that exerts no torque at its inner edge, the innermost stable orbit.
// Scaled so its peak (at r = 4.776) is 1; zero at the inner edge, and falling
// off as r^-3 far out. The temperature goes as its fourth root.
static float disk_flux(float r) {
    const float s3 = 1.7320508, s32 = 1.2247449;
    float x = sqrt(r);
    float log_term = log(((x + s32) * (s3 - s32)) / ((x - s32) * (s3 + s32)));
    float f = (x - s3 + 0.5 * s32 * log_term) / ((r - 1.5) * r * r * x);
    return max(f / 9.1671579e-4, 0.0);
}

// MARK: - Color from temperature

// The CIE 1931 color matching functions, as the multi-lobe Gaussian fit of
// Wyman, Sloan and Shirley (2013). Wavelength in nanometers.
static float3 cie_observer(float w) {
    float x1 = (w - 442.0) * (w < 442.0 ? 0.0624 : 0.0374);
    float x2 = (w - 599.8) * (w < 599.8 ? 0.0264 : 0.0323);
    float x3 = (w - 501.1) * (w < 501.1 ? 0.0490 : 0.0382);
    float y1 = (w - 568.8) * (w < 568.8 ? 0.0213 : 0.0247);
    float y2 = (w - 530.9) * (w < 530.9 ? 0.0613 : 0.0322);
    float z1 = (w - 437.0) * (w < 437.0 ? 0.0845 : 0.0278);
    float z2 = (w - 459.0) * (w < 459.0 ? 0.0385 : 0.0725);
    return float3(0.362 * exp(-0.5 * x1 * x1) + 1.056 * exp(-0.5 * x2 * x2) - 0.065 * exp(-0.5 * x3 * x3),
                  0.821 * exp(-0.5 * y1 * y1) + 0.286 * exp(-0.5 * y2 * y2),
                  1.217 * exp(-0.5 * z1 * z1) + 0.681 * exp(-0.5 * z2 * z2));
}

// The CIE XYZ of a black body at `kelvin`: Planck's law weighed by the
// observer, summed every 20 nm across the visible. Units are arbitrary but
// fixed, so two temperatures compare: a hotter body is brighter, as it is.
static float3 blackbody_xyz(float kelvin) {
    float3 sum = float3(0.0);
    for (int i = 0; i < 20; ++i) {
        float w = 390.0 + 20.0 * float(i);
        float micrometers = w * 1e-3;
        // c2 = hc / k, in micrometer kelvin. The exponent is held short of
        // where a float overflows; that far down the light is nothing anyway.
        float e = min(14387.77 / (micrometers * max(kelvin, 1.0)), 80.0);
        float planck = 1.0 / (pow(micrometers, 5.0) * (exp(e) - 1.0));
        sum += planck * cie_observer(w);
    }
    return sum * 20.0;
}

// CIE XYZ to linear sRGB (IEC 61966-2-1, D65 white). Colors outside the gamut
// come back with a negative component, which the caller clips.
static float3 xyz_to_linear_srgb(float3 c) {
    return float3( 3.2406 * c.x - 1.5372 * c.y - 0.4986 * c.z,
                  -0.9689 * c.x + 1.8758 * c.y + 0.0415 * c.z,
                   0.0557 * c.x - 0.2040 * c.y + 1.0570 * c.z);
}
