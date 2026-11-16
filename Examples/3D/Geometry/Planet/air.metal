// The air around the world, worked out per pixel from where the light has been.
//
// This is a combine: it reads the lit picture of the world (`sample`) and the
// picture of its city lights (`sampleAux`), and it knows three things the sketch
// tells it, which are where the camera is, which way each pixel looks, and where
// the sun is. From those it follows the pixel's line of sight through a shell of
// air, and at each step asks how much sunlight reaches that point and how much of
// what scatters there survives the trip to the camera. That sum is the blue veil
// over the day side, the bright band at the limb, and the ring standing off the
// edge. The same bookkeeping run toward the sun gives the color of the light that
// reaches the ground, which is white at noon and red at the terminator, because
// the blue has been scattered out of it on the way.
//
// Lengths are in planet radii. The air is three times as deep as the Earth's and a
// third as dense, so a ray going straight down passes the same amount of it and
// the colors come out the same, while the limb is wide enough to see at this size.
//
// Everything here works in linear light. The inputs are read as stored, and the
// result is handed back through `air_encode`, the sRGB curve with no ceiling on
// it, so a glint brighter than white is still brighter than white afterwards.

constant float AIR_TOP = 1.023;              // where the air is thin enough to stop
constant float MOLECULE_HEIGHT = 0.0038;     // the height the gas thins by 1/e over
constant float HAZE_HEIGHT = 0.0012;         // the same for dust and droplets
constant float OZONE_MIDDLE = 0.0118;        // the ozone layer's densest height
constant float OZONE_HALF_WIDTH = 0.0071;

// What each thing does to light per planet radius of it. The gas scatters blue
// about six times as strongly as red; haze scatters every color alike and loses a
// tenth of what it touches; ozone only absorbs, and mostly the middle of the
// spectrum, which is what keeps a long path through the air from going green.
constant float3 MOLECULES = float3(12.30, 28.62, 70.17);
constant float HAZE = 25.0;
constant float HAZE_LOSS = 1.0 / 0.9;
constant float3 OZONE = float3(1.378, 3.988, 0.180);
constant float HAZE_FORWARD = 0.76;          // how strongly haze throws light onward

constant int VIEW_STEPS = 24;
constant int OZONE_STEPS = 6;

// Where a ray meets a sphere about the origin: the near and the far distance
// along it. The near one is past the far one when the ray misses.
static float2 air_sphere(float3 from, float3 dir, float radius) {
    float b = dot(from, dir);
    float c = dot(from, from) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) { return float2(1.0, -1.0); }
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

// How much gas, haze, and ozone there is at a height above the ground, each as
// a share of what there is at its densest.
static float3 air_density(float height) {
    height = max(height, 0.0);
    return float3(exp(-height / MOLECULE_HEIGHT),
                  exp(-height / HAZE_HEIGHT),
                  max(0.0, 1.0 - fabs(height - OZONE_MIDDLE) / OZONE_HALF_WIDTH));
}

// What a depth of each of the three takes out of a beam, per color.
static float3 air_loss(float3 depth) {
    return MOLECULES * depth.x + HAZE * HAZE_LOSS * depth.y + OZONE * depth.z;
}

// How many times deeper a slanting path through a thinning layer is than the
// path straight up. `x` is the distance from the planet's center in scale
// heights, `rise` the cosine of the angle off straight up, zero or more. This is
// the grazing-incidence function of a curved atmosphere in the form it takes
// when the planet is much larger than the layer, where it is an error function,
// and the error function is a rational fit good to a part in a hundred. Against
// a sum of 200,000 steps the whole of it stays within 0.6 percent.
static float air_slant(float x, float rise) {
    const float a = 2.911;
    float y = sqrt(0.5 * x) * rise;
    return sqrt(1.5707963 * x) * a
         / ((a - 1.0) * 1.7724539 * y + sqrt(3.14159265 * y * y + a * a));
}

// How much of a layer that thins by 1/e every `scale` lies between a point and
// open space, along a direction. A direction below level dips to a lowest point
// first and climbs out again, so it is the whole level path through that lowest
// point less the part behind where it starts.
static float air_column(float radius, float rise, float scale) {
    float x = radius / scale;
    float here = exp(-(radius - 1.0) / scale);
    if (rise >= 0.0) { return scale * here * air_slant(x, rise); }
    float level = sqrt(max(0.0, 1.0 - rise * rise));
    float lowest = exp(-(radius * level - 1.0) / scale);
    return scale * (2.0 * lowest * air_slant(x * level, 0.0) - here * air_slant(x, -rise));
}

// How much of each there is between a point and the top of the air, toward the
// sun. The gas and the haze have the closed form above. Ozone is a layer with a
// top and a bottom, so it is counted in steps, and a few are enough for something
// that wide.
static float3 air_depth_to_sun(float3 from, float3 sun) {
    float radius = length(from);
    float rise = dot(from, sun) / radius;
    float reach = air_sphere(from, sun, AIR_TOP).y;
    float pace = reach / float(OZONE_STEPS);
    float ozone = 0.0;
    for (int i = 0; i < OZONE_STEPS; ++i) {
        float3 at = from + sun * ((float(i) + 0.5) * pace);
        ozone += max(0.0, 1.0 - fabs(length(at) - 1.0 - OZONE_MIDDLE) / OZONE_HALF_WIDTH);
    }
    return float3(air_column(radius, rise, MOLECULE_HEIGHT),
                  air_column(radius, rise, HAZE_HEIGHT),
                  ozone * pace);
}

// Linear light to sRGB, with nothing held to 1, so the wrapper's decode gives the
// same number back.
static float3 air_encode(float3 c) {
    c = max(c, 0.0);
    float3 low = c * 12.92;
    float3 high = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return select(low, high, c > 0.0031308);
}

float4 shade(float2 uv, ShaderInfo info) {
    float3 eye = float3(param(info, 0), param(info, 1), param(info, 2));
    float3 right = float3(param(info, 3), param(info, 4), param(info, 5));
    float3 up = float3(param(info, 6), param(info, 7), param(info, 8));
    float3 forward = float3(param(info, 9), param(info, 10), param(info, 11));
    float3 sun = normalize(float3(param(info, 12), param(info, 13), param(info, 14)));
    float amount = param(info, 15);          // how much air
    float sunlight = param(info, 16);        // the sun's intensity, as the scene has it
    float glow = param(info, 17);            // how bright the cities are
    bool lightsOnly = param(info, 18) > 0.5; // hand back the cities and nothing else

    // The pixel's line of sight. `right` and `up` arrive already scaled by the
    // lens, so the corner of the picture is one of each from the middle.
    float2 across = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float3 dir = normalize(forward + across.x * right + across.y * up);

    float3 world = sampleRaw(info, uv).rgb;
    float3 cities = sampleAuxRaw(info, uv).rgb;

    float2 ground = air_sphere(eye, dir, 1.0);
    bool landed = ground.x <= ground.y && ground.x > 0.0;

    // The cities show where the sun has set on them, and come on through dusk
    // rather than at a line.
    float3 night = float3(0.0);
    if (landed) {
        float3 place = eye + dir * ground.x;
        night = cities * glow * smoothstep(0.06, -0.10, dot(place, sun));
    }
    if (lightsOnly) { return float4(air_encode(night), 1.0); }

    float2 air = air_sphere(eye, dir, AIR_TOP);
    if (air.x > air.y || air.y <= 0.0 || amount <= 0.0) {
        return float4(air_encode(world + night), 1.0);
    }

    // March the part of the sight line that is inside the air: from where it
    // enters to the ground, or to where it leaves again if it misses the world.
    float start = max(air.x, 0.0);
    float end = landed ? ground.x : air.y;
    float pace = (end - start) / float(VIEW_STEPS);

    float3 depth = float3(0.0);              // the air between the camera and here
    float3 fromGas = float3(0.0);
    float3 fromHaze = float3(0.0);
    for (int i = 0; i < VIEW_STEPS; ++i) {
        float3 at = eye + dir * (start + (float(i) + 0.5) * pace);
        float3 here = air_density(length(at) - 1.0) * amount * pace;
        depth += here;

        // A point in the world's shadow scatters nothing, which is what keeps the
        // night limb dark without anything being told where the sun is.
        float2 shadow = air_sphere(at, sun, 1.0);
        if (shadow.x <= shadow.y && shadow.x > 0.0) { continue; }

        float3 toSun = air_depth_to_sun(at, sun) * amount;
        float3 arrives = exp(-air_loss(depth + toSun));
        fromGas += arrives * here.x;
        fromHaze += arrives * here.y;
    }

    // How much of what scatters goes toward the camera, by the angle it turns
    // through: evenly fore and aft for the gas, strongly onward for the haze.
    float turn = dot(dir, sun);
    float gasPhase = 3.0 / (16.0 * 3.14159265) * (1.0 + turn * turn);
    float g = HAZE_FORWARD;
    float hazePhase = 3.0 / (8.0 * 3.14159265) * (1.0 - g * g) * (1.0 + turn * turn)
                    / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * turn, 1.5));
    float3 scattered = (fromGas * MOLECULES * gasPhase + fromHaze * HAZE * hazePhase)
                     * sunlight * 3.14159265;

    float3 survives = exp(-air_loss(depth));

    if (landed) {
        // The light on the ground came through the air too. Measured against a
        // sun straight overhead, which is the light the scene was lit with, so
        // noon stays white and only the long slanting paths redden.
        float3 place = eye + dir * ground.x;
        float height = dot(place, sun);
        float3 overhead = float3(MOLECULE_HEIGHT, HAZE_HEIGHT, OZONE_HALF_WIDTH) * amount;
        float3 slant = air_depth_to_sun(place * 1.0002, sun) * amount;
        float3 daylight = exp(-air_loss(max(slant - overhead, 0.0)))
                        * smoothstep(0.0, 0.07, height);
        world *= daylight;
    }

    return float4(air_encode(world * survives + scattered + night * survives), 1.0);
}
