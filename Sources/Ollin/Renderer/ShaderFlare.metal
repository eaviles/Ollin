// MARK: - Lens flare
//
// The camera's own contribution to the picture. A bright source does not only
// light the scene: some of it reflects off the lens's interfaces instead of
// passing through them, comes back down the barrel, and lands on the sensor
// somewhere it does not belong. That misplaced light is a ghost, and a row of
// ghosts along the line from the source through the middle of the frame is what
// a lens flare is.
//
// The optics are worked out on the CPU (see `LensFlare.swift`), which leaves the
// fragment with almost nothing to do. First-order optics is linear, so each
// ghost maps a point on the front opening to the sensor by one scale and one
// shift. The fragment runs that map *backwards*: from the pixel it is shading to
// the point on the opening whose light would have landed there. Then it asks two
// questions. Did that point start inside the front opening? Did it clear the
// iris? Light that answers yes to both is this ghost's contribution here.
//
// Coordinates are y-normalized: y runs -1…1 over the frame's height and x is
// scaled by the aspect, so a round lens stays round on a wide canvas.

// What this segment builds on. The resolver reads each one in ahead of this file
// and only once, so the segment list itself carries no order (see ShaderIncludes).
#include "ShaderEffects.metal"

// How far a point on the iris plane is from the edge of the opening, negative
// inside. A round iris is a circle; a bladed one is a regular polygon, which is
// what gives a stopped-down ghost its flat sides. The polygon is the region
// every blade leaves clear, so the distance is the largest of the distances to
// the blades' edges, and the edge normals arrive already worked out: a handful
// of dot products, and no angle to fold.
//
// `facing` comes back as the outward normal of the edge the point is nearest,
// which is what lets a caller move the point a little and have the new distance
// for one dot product instead of asking again.
static inline float ollin_flare_iris_distance(float2 p, float inner,
                                              constant OllinLensFlareUniforms &flare,
                                              thread float2 &facing) {
    int count = int(flare.iris.x);
    if (count < 3) {
        float out = length(p);
        facing = out > 1e-6 ? p / out : float2(1.0, 0.0);
        return out - inner;
    }
    float reach = -1e9;
    facing = float2(1.0, 0.0);
    for (int k = 0; k < count; k++) {
        float4 pair = flare.blades[k / 2];
        float2 normal = (k & 1) == 0 ? pair.xy : pair.zw;
        float along = dot(p, normal);
        if (along > reach) { reach = along; facing = normal; }
    }
    return reach - inner;
}

// How much of a disc of radius `disc` lies inside an opening of radius
// `opening` whose middle is `apart` away, as a fraction of the disc.
//
// This is what a source with a size does to a ghost. Every point of the source
// throws its own copy of the ghost, shifted a little, so a pixel sees the
// opening through a disc rather than through a point: partly covered where the
// disc straddles the edge, which is the soft rim, and wholly inside an opening
// *smaller* than the disc, which caps the answer at the ratio of the two areas.
// That cap is what keeps the light the same when a ghost near focus spreads
// into a picture of its source.
//
// The true answer is the area two circles share. It has a closed form, but one
// with two inverse cosines and a root in it, and a ghost's rim asks this six
// times a pixel: measured, that form made a stopped-down lens, whose ghosts are
// nearly all rim, cost more than twice what the same lens costs wide open. What
// the picture needs from it is three things, and a cubic gives all three with
// no transcendental in sight: the level well inside (1, or the ratio of the
// areas), nothing well outside, and between them a smooth ramp exactly as wide
// as the smaller of the two circles, centered where the larger one's edge is.
// It stays within a twentieth of the true area across the ramp.
static inline float ollin_flare_overlap(float apart, float opening, float disc) {
    float larger = max(opening, disc), smaller = max(min(opening, disc), 1e-9);
    float level = opening >= disc ? 1.0 : (opening * opening) / (disc * disc);
    float t = clamp((larger - apart) / smaller, -1.0, 1.0);
    return level * (0.5 + t * (0.75 - 0.25 * t * t));
}

// How much of each source the camera can actually see, one light per pixel of a
// tiny strip. A flare has to follow the *visible* area of its source: an
// occluder should fade it, not switch it off, so an edge sliding across the sun
// dims the whole flare smoothly. The taps ring the source over the disc it is
// treated as filling, and a tap that falls outside the frame counts as seeing
// it, because a source just off the edge is the classic flare and the depth
// buffer knows nothing about what is out there.
//
// params[0] = (tap radius in uv.y, aspect, light count, depth bias)
// params[1 + i] = (source uv.x, source uv.y, source depth, 1 if this light flares)
fragment float4 ollin_flare_visibility(PresentOut in [[stage_in]],
                                       depth2d<float> depthTex [[texture(0)]],
                                       constant float4 *params [[buffer(0)]]) {
    constexpr sampler dsamp(filter::nearest, address::clamp_to_edge);
    uint index = uint(in.position.x);
    if (float(index) >= params[0].z) { return float4(0.0); }
    float4 light = params[1 + index];
    if (light.w < 0.5) { return float4(0.0); }

    float radius = params[0].x;
    float aspect = max(params[0].y, 1e-4);
    float bias = params[0].w;
    // A ring plus the center, at two radii: enough to read a partial cover
    // smoothly without the cost of a dense disc.
    const int kRing = 8;
    float seen = 0.0, total = 0.0;
    for (int step = 0; step < 3; step++) {
        float r = radius * (float(step) / 2.0);
        int count = step == 0 ? 1 : kRing;
        for (int k = 0; k < count; k++) {
            float phi = (2.0 * M_PI_F) * (float(k) + 0.5 * float(step)) / float(count);
            float2 uv = light.xy + float2(cos(phi) * r / aspect, sin(phi) * r);
            total += 1.0;
            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { seen += 1.0; continue; }
            float scene = depthTex.sample(dsamp, uv);
            if (scene > light.z - bias) { seen += 1.0; }
        }
    }
    return float4(total > 0.0 ? seen / total : 0.0);
}

// The light every ghost adds, by itself, on a canvas half the frame's size each
// way.
//
// The ghosts are the dear half of a flare: a loop over every ghost of every
// light for every pixel, most of whose ghosts are wide. They are also the half
// that can afford fewer pixels. A ghost's edge is never sharper than its source
// is small, and the sun's own disc already blurs one by several pixels of a
// full frame, so a ghost drawn at half size and read back through a smooth
// sampler is the same ghost at a quarter of the work. The star is the other
// way round: its needles are a pixel wide, so it is added at full size below.
fragment float4 ollin_flare_ghosts(PresentOut in [[stage_in]],
                                   texture2d<float> visibility [[texture(0)]],
                                   texture2d<float> coating [[texture(1)]],
                                   sampler samp [[sampler(0)]],
                                   constant OllinLensFlareUniforms &flare [[buffer(0)]]) {
    float pupil = flare.optics.x;
    float sensor = flare.optics.z;
    float aspect = flare.optics.w;
    float inner = flare.iris.z;
    float rows = max(flare.iris.w, 1.0);
    float columns = float(coating.get_width());
    // Where this pixel sits on the frame, and where that is on the sensor in
    // millimeters.
    float2 screen = float2((in.uv.x * 2.0 - 1.0) * aspect, 1.0 - in.uv.y * 2.0);
    float2 here = screen * sensor;

    float3 sum = float3(0.0);
    for (int i = 0; i < flare.lightCount; i++) {
        float seen = visibility.read(uint2(uint(i), 0)).x;
        if (seen <= 0.0) { continue; }
        float2 angle = flare.lights[i].xy;
        float3 source = flare.levels[i].rgb * seen;
        // Which ghosts this light makes that anyone could see, a bit per ghost.
        // More than half of a lens's ghosts are usually far too faint to show,
        // and they tend to be the widest, so they are the dearest to draw too.
        uint shows = uint(flare.levels[i].w);
        for (int g = 0; g < flare.ghostCount; g++) {
            if ((shows & (1u << uint(g))) == 0u) { continue; }
            // Backwards through the green channel's map: the point on the front
            // opening whose light lands here. A pixel outside every channel's
            // reach (the radius is worked out per ghost, with room for how far
            // its three channels part) leaves having cost a few multiplies.
            float4 green = flare.ghosts[g * 3 + 1];
            float4 spread = flare.spreads[g * 3 + 1];
            float2 entry = (here - green.y * angle) / green.x;
            float outside = length(entry);
            if (outside > spread.w) { continue; }
            // Forwards again to the iris, which is what shapes the ghost.
            float2 stop = green.z * entry + green.w * angle;
            float2 facing;
            float edgeGreen = ollin_flare_iris_distance(stop, inner, flare, facing);

            // Glass bends each color a little differently, so the three channels'
            // ghosts differ in size and place by a few percent, and where they
            // stop agreeing is the colored rim. Well inside a ghost they all
            // agree that the pixel is covered, and only the spread differs, so
            // the per-channel edges are worked out in the rim alone.
            float3 cover = float3(0.0);
            float room = flare.spreads[g * 3 + 2].w;
            if (room > 0.0 && edgeGreen < -(spread.y + room * inner)
                && outside < pupil - spread.x - room * pupil) {
                for (int c = 0; c < 3; c++) {
                    float scale = flare.ghosts[g * 3 + c].x;
                    cover[c] = flare.spreads[g * 3 + c].z / max(scale * scale, 1e-8);
                }
            } else {
                for (int c = 0; c < 3; c++) {
                    float4 map = flare.ghosts[g * 3 + c];
                    float4 own = flare.spreads[g * 3 + c];
                    float2 from = (here - map.y * angle) / map.x;
                    float front = ollin_flare_overlap(length(from), pupil, own.x);
                    // The other two channels cross the iris a little way from
                    // where green does, and the edge green is nearest is the edge
                    // they are nearest too, so their distance to it is green's
                    // moved along that edge's normal: a dot product, where asking
                    // the opening again would be a walk round every blade.
                    float2 at = map.z * from + map.w * angle;
                    float edge = edgeGreen + dot(facing, at - stop);
                    float through = ollin_flare_overlap(max(inner + edge, 0.0), inner, own.y);
                    // A ghost spreads the light it carries over the square of its
                    // magnification, which is why the small ones are the bright ones.
                    cover[c] = front * through * own.z / max(map.x * map.x, 1e-8);
                }
                if (max(cover.r, max(cover.g, cover.b)) <= 0.0) { continue; }
            }

            // What the two coatings send back for the ray that lands *here*.
            // It met each surface at its own angle, and a coating's color turns
            // with that angle, so the color runs across the ghost.
            //
            // The ray has to be one that really passes. The light here came
            // through whatever stretch of the front opening the source's disc
            // reaches from this pixel: a small patch around `entry` for a crisp
            // ghost, the whole opening for a ghost near focus, where the source
            // is wider than the opening and `entry` itself can lie far outside
            // it. The middle of that stretch is the ray to read, and its angle
            // moves by what it takes to bring it there.
            float middle = 0.5 * (max(-pupil, outside - spread.x) + min(pupil, outside + spread.x));
            float2 passing = outside > 1e-6 ? entry * (middle / outside) : entry;
            float2 arriving = angle;
            if (abs(green.y) > 1e-6) { arriving += (entry - passing) * (green.x / green.y); }
            float4 meets = flare.incidence[g];
            float outerAngle = length(meets.x * passing + meets.y * arriving);
            float innerAngle = length(meets.z * passing + meets.w * arriving);
            float bothRows = flare.spreads[g * 3].w;
            float innerRow = floor(bothRows / 256.0);
            float outerRow = bothRows - innerRow * 256.0;
            float2 outerAt = float2((clamp(outerAngle / M_PI_2_F, 0.0, 1.0) * (columns - 1.0) + 0.5) / columns,
                                    (outerRow + 0.5) / rows);
            float2 innerAt = float2((clamp(innerAngle / M_PI_2_F, 0.0, 1.0) * (columns - 1.0) + 0.5) / columns,
                                    (innerRow + 0.5) / rows);
            // The table holds square roots, which is what keeps a few parts in a
            // hundred thousand inside a half float.
            float3 outerRoot = coating.sample(samp, outerAt, level(0)).rgb;
            float3 innerRoot = coating.sample(samp, innerAt, level(0)).rgb;
            float3 reflect = (outerRoot * outerRoot) * (innerRoot * innerRoot);

            // A ghost near focus is a picture of the source, and the source is
            // then wider than both openings as that ghost sees them. The two
            // tests above each ask whether the source's disc clears one opening;
            // this asks the question they cannot, whether the two openings clear
            // each other, which is what shades such a ghost toward the edge of
            // the frame and finally puts it out.
            float4 meeting = flare.meeting[g];
            if (meeting.x > 0.0) {
                float both;
                if (meeting.y < 1.5) {
                    float2 center = meeting.z * here;
                    float2 unused;
                    float edge = ollin_flare_iris_distance(center, inner, flare, unused);
                    both = ollin_flare_overlap(max(inner + edge, 0.0), inner, meeting.w);
                } else {
                    float2 center = entry - meeting.z * stop;
                    both = ollin_flare_overlap(length(center), pupil, meeting.w);
                }
                cover *= mix(1.0, both, meeting.x);
            }
            sum += source * reflect * cover;
        }
    }
    return float4(sum, 1.0);
}

// MARK: Ghosts followed ray by ray
//
// First order makes every ghost a scaled, shifted copy of the iris, evenly lit.
// A real ghost is none of those things. Its rays pass through spheres, which
// bend a ray near the rim by more than proportion says, so the ghost stretches
// and leans as the light moves off the axis. The barrel stops whatever strays
// past the rim of any element, which is what cuts a wide ghost down to the part
// that survives. And neighboring rays can land on top of one another, which is a
// caustic: the bright rims and cores inside a ghost.
//
// So a grid of rays is laid across the front opening and each is carried through
// the actual surfaces along the ghost's path, here in the vertex stage. The grid
// lands on the sensor as a bent mesh, and the light each cell carried in is
// spread over whatever area that cell ends up covering.

// What a bare interface reflects, unpolarized.
static inline float ollin_flare_bare(float cos0, float n0, float n2) {
    float sin0 = sqrt(max(0.0, 1.0 - cos0 * cos0));
    float sin2 = sin0 * n0 / n2;
    if (sin2 >= 1.0) { return 1.0; }
    float cos2 = sqrt(1.0 - sin2 * sin2);
    float rs = (n0 * cos0 - n2 * cos2) / (n0 * cos0 + n2 * cos2);
    float rp = (n0 * cos2 - n2 * cos0) / (n0 * cos2 + n2 * cos0);
    return clamp(0.5 * (rs * rs + rp * rp), 0.0, 1.0);
}

// What a quarter-wave coated interface reflects at an angle and a wavelength: the
// reflections off the coating's two faces, interfered per polarization over the
// path between them. It runs into the bare value as the angle nears the critical
// one, since the cancellation needs a wave travelling on into the far glass.
static inline float ollin_flare_coated(float cos0, float wavelength, float design,
                                       float n0, float n2) {
    float bare = ollin_flare_bare(cos0, n0, n2);
    if (design <= 0.0) { return bare; }
    float n1 = max(sqrt(n0 * n2), 1.38);
    float thickness = design / 4.0 / n1;
    float sin0 = sqrt(max(0.0, 1.0 - cos0 * cos0));
    float sin1 = sin0 * n0 / n1, sin2 = sin0 * n0 / n2;
    if (sin1 >= 1.0 || sin2 >= 1.0) { return 1.0; }
    float theta0 = acos(clamp(cos0, 0.0, 1.0)), theta1 = asin(sin1), theta2 = asin(sin2);
    float keeps = cos(theta2);
    float value;
    if (theta0 + theta1 <= 1e-4 || theta1 + theta2 <= 1e-4) {
        float r01 = (n0 - n1) / (n0 + n1), r12 = (n1 - n2) / (n1 + n2);
        float t01 = 2.0 * n0 / (n0 + n1);
        float inner = t01 * t01 * r12;
        float phase = 4.0 * M_PI_F / wavelength * thickness * n1;
        value = r01 * r01 + inner * inner + 2.0 * r01 * inner * cos(phase);
    } else {
        float rs01 = -sin(theta0 - theta1) / sin(theta0 + theta1);
        float rp01 = tan(theta0 - theta1) / tan(theta0 + theta1);
        float ts01 = 2.0 * sin(theta1) * cos(theta0) / sin(theta0 + theta1);
        float tp01 = ts01 * cos(theta0 - theta1);
        float rs12 = -sin(theta1 - theta2) / sin(theta1 + theta2);
        float rp12 = tan(theta1 - theta2) / tan(theta1 + theta2);
        float innerS = ts01 * ts01 * rs12, innerP = tp01 * tp01 * rp12;
        float dy = thickness * n1, dx = tan(theta1) * dy;
        float phase = 4.0 * M_PI_F / wavelength * (sqrt(dx * dx + dy * dy) - dx * sin0);
        float outS = rs01 * rs01 + innerS * innerS + 2.0 * rs01 * innerS * cos(phase);
        float outP = rp01 * rp01 + innerP * innerP + 2.0 * rp01 * innerP * cos(phase);
        value = 0.5 * (outS + outP);
    }
    return clamp(value, 0.0, 1.0) * keeps + bare * (1.0 - keeps);
}

struct OllinFlareRay {
    float2 sensor;
    float2 aperture;
    float relative;       // the furthest toward any element's rim, as a fraction
    float passes;         // what every refraction along the way let through
    float cosOuter, cosInner;
    float outerFrom, outerTo, innerFrom, innerTo;   // the media at each reflection
    float outerDesign, innerDesign;
    bool valid;
};

// Meet one interface and either reflect off it or pass through. The surfaces are
// met in the order the path names, never by which is nearest, and a sphere is
// carried past its own rim by its equation, so a ray outside the glass still
// lands somewhere continuous. Such rays are never drawn; they are what lets the
// mesh be read right up to the edge of the glass.
static inline bool ollin_flare_meet(thread float3 &origin, thread float3 &direction,
                                    int i, bool reflecting, bool forward, int slot,
                                    bool isOuter, thread OllinFlareRay &ray,
                                    constant OllinLensTraceUniforms &lens) {
    float4 face = lens.surfaces[i];
    float3 normal;
    if (face.y == 0.0) {
        if (abs(direction.z) < 1e-9) { return false; }
        origin += direction * ((face.x - origin.z) / direction.z);
        normal = float3(0.0, 0.0, direction.z > 0.0 ? -1.0 : 1.0);
    } else {
        float3 center = float3(0.0, 0.0, face.x + face.y);
        float3 offset = origin - center;
        float b = dot(offset, direction);
        float disc = b * b - (dot(offset, offset) - face.y * face.y);
        if (disc < 0.0) { return false; }
        // The pole that is the lens surface, not the far side of the ball.
        float root = face.y * direction.z > 0.0 ? -sqrt(disc) : sqrt(disc);
        origin += direction * (-b + root);
        normal = normalize(origin - center);
        if (dot(normal, direction) > 0.0) { normal = -normal; }
    }
    if (face.w > 0.5) { ray.aperture = origin.xy; return true; }
    ray.relative = max(ray.relative, length(origin.xy) / max(face.z, 1e-6));

    int row = slot * OLLIN_MAX_LENS_INTERFACES;
    float ahead = lens.index[row + i];
    float behind = i == 0 ? 1.0 : lens.index[row + i - 1];
    float n0 = forward ? behind : ahead, n2 = forward ? ahead : behind;
    float cosine = clamp(-dot(normal, direction), 0.0, 1.0);
    if (reflecting) {
        if (isOuter) {
            ray.cosOuter = cosine; ray.outerFrom = n0; ray.outerTo = n2;
            ray.outerDesign = lens.coatings[i].x;
        } else {
            ray.cosInner = cosine; ray.innerFrom = n0; ray.innerTo = n2;
            ray.innerDesign = lens.coatings[i].x;
        }
        direction -= normal * (2.0 * dot(direction, normal));
        return true;
    }
    if (abs(n0 - n2) < 1e-6) { return true; }
    float eta = n0 / n2;
    float k = 1.0 - eta * eta * (1.0 - cosine * cosine);
    if (k < 0.0) { return false; }          // cannot leave the glass
    // What crosses is what does not reflect, and that runs smoothly to nothing as
    // the ray nears the angle it could no longer leave the glass at. This is what
    // lets the mesh have holes where rays are lost: their neighbors are already
    // dark, so a hole has no outline to show.
    ray.passes *= 1.0 - ollin_flare_bare(cosine, n0, n2);
    direction = normalize(direction * eta + normal * (eta * cosine - sqrt(k)));
    return true;
}

static inline OllinFlareRay ollin_flare_trace(float2 entry, float2 slope, int first, int second,
                                              int slot, constant OllinLensTraceUniforms &lens) {
    OllinFlareRay ray;
    ray.sensor = float2(0.0); ray.aperture = float2(0.0); ray.relative = 0.0;
    ray.passes = 1.0;
    ray.cosOuter = 1.0; ray.cosInner = 1.0;
    ray.outerFrom = 1.0; ray.outerTo = 1.0; ray.innerFrom = 1.0; ray.innerTo = 1.0;
    ray.outerDesign = 0.0; ray.innerDesign = 0.0; ray.valid = false;
    int count = int(lens.frame.w);
    float3 origin = float3(entry, 0.0);
    float3 direction = normalize(float3(slope, 1.0));
    // Forward to the outer reflection, back to the inner one, forward again.
    for (int i = 0; i <= second; i++) {
        if (!ollin_flare_meet(origin, direction, i, i == second, true, slot, true, ray, lens)) { return ray; }
    }
    for (int i = second - 1; i >= first; i--) {
        if (!ollin_flare_meet(origin, direction, i, i == first, false, slot, false, ray, lens)) { return ray; }
    }
    for (int i = first + 1; i < count; i++) {
        if (!ollin_flare_meet(origin, direction, i, false, true, slot, false, ray, lens)) { return ray; }
    }
    if (direction.z < 1e-6) { return ray; }
    origin += direction * ((lens.frame.z - origin.z) / direction.z);
    ray.sensor = origin.xy;
    ray.valid = true;
    return ray;
}

struct OllinFlareTraceOut {
    float4 position [[position]];
    float2 aperture;
    float relative;
    float3 light;
    float valid;
    // What the fragment needs of its ghost, carried flat so that a pixel does not
    // have to fetch the ghost's whole record to read four numbers of it: how soft
    // the barrel's edge and the iris's are, the ringing scale, and the three
    // wavelengths (the second is 0 for a ghost followed in one color).
    float3 edges [[flat]];
    float3 wavelengths [[flat]];
};

vertex OllinFlareTraceOut ollin_flare_trace_vertex(uint vertexID [[vertex_id]],
                                                   uint instanceID [[instance_id]],
                                                   constant OllinLensTraceUniforms &lens [[buffer(0)]],
                                                   constant OllinFlareGhostDraw *draws [[buffer(1)]],
                                                   texture2d<float> visibility [[texture(0)]]) {
    OllinFlareGhostDraw draw = draws[instanceID];
    int side = max(int(draw.grid.w), 2);
    int column = int(vertexID) % side, line = int(vertexID) / side;
    float2 across = float2(float(column), float(line)) / float(side - 1) * 2.0 - 1.0;
    float2 entry = draw.grid.xy + across * draw.grid.z;
    // One cell of the grid, which is the stretch the beam's squeeze is measured
    // over: the same stretch the triangles drawn from this vertex cover, so the
    // light a cell is given is the light it carried in, however sharply the lens
    // bends across it.
    float step = 2.0 * draw.grid.z / float(side - 1);
    int first = int(draw.path.z), second = int(draw.path.w), slot = int(draw.soft.w);

    // Toward the middle of the grid each way, so the neighbors asked for are
    // rays the grid holds too, and a ray on the grid's edge looks inward rather
    // than out past the glass.
    float2 inward = float2(across.x > 0.0 ? -1.0 : 1.0, across.y > 0.0 ? -1.0 : 1.0);
    OllinFlareRay ray = ollin_flare_trace(entry, draw.path.xy, first, second, slot, lens);
    OllinFlareRay beside = ollin_flare_trace(entry + float2(step * inward.x, 0.0), draw.path.xy, first, second, slot, lens);
    OllinFlareRay above = ollin_flare_trace(entry + float2(0.0, step * inward.y), draw.path.xy, first, second, slot, lens);

    OllinFlareTraceOut out;
    out.edges = float3(draw.soft.x, draw.soft.y, draw.ring.x);
    out.wavelengths = float3(draw.colors[0].w, draw.colors[1].w, draw.colors[2].w);
    out.aperture = ray.aperture;
    out.relative = ray.relative;
    out.valid = ray.valid ? 1.0 : 0.0;
    // The light a cell carried in, spread over the area it lands on: the ratio
    // of the two is how hard the lens squeezed that bundle, and where it goes to
    // nothing is a caustic. It cannot quite go to nothing, since the source has
    // a size and a pixel has one too, which `soft.z` stands for.
    // A neighbor that was lost is asked for again on the other side. A ray with
    // no neighbor either way along some axis sits alone at the edge of a hole, and
    // there is no measuring how its bundle was squeezed: it carries nothing, which
    // is what the fade toward a lost ray was heading for anyway. Falling back to
    // first order's ratio there is wrong in the one place it would be used, since
    // a ghost is stretched most at its rim, and lights single rays up as beads.
    if (ray.valid && !beside.valid) {
        beside = ollin_flare_trace(entry - float2(step * inward.x, 0.0), draw.path.xy, first, second, slot, lens);
    }
    if (ray.valid && !above.valid) {
        above = ollin_flare_trace(entry - float2(0.0, step * inward.y), draw.path.xy, first, second, slot, lens);
    }
    // A lost ray lands nowhere, and its vertex still has to be put somewhere. It
    // goes where a neighbor that made it landed, so the cells round it close up to
    // nothing. First order's idea of where it would have landed is no good here:
    // a ghost that throws its rim rays far off the sensor has real neighbors
    // nowhere near that spot, and the cells between them open into fans across
    // the whole frame, one for each side of the grid.
    float2 sensor = ray.sensor;
    if (!ray.valid) {
        sensor = beside.valid ? beside.sensor : above.valid ? above.sensor
               : draw.ring.z * entry + draw.ring.w * draw.path.xy;
    }
    out.position = float4(sensor.x / (lens.frame.x * lens.frame.y), sensor.y / lens.frame.x, 0.0, 1.0);

    float squeeze = draw.ring.y;
    bool measured = ray.valid && beside.valid && above.valid;
    if (measured) {
        float2 a = (beside.sensor - ray.sensor) / step, b = (above.sensor - ray.sensor) / step;
        squeeze = abs(a.x * b.y - a.y * b.x);
    }
    squeeze = sqrt(squeeze * squeeze + draw.soft.z * draw.soft.z);
    // And a grid this coarse cannot resolve a caustic finer than its own cells: a
    // fold that falls between rays is lit only at the rays nearest it and comes
    // out as a row of beads. So a bundle is never counted as squeezed to less than
    // a twelfth of what first order gives the whole ghost, which keeps the bright
    // rims a grid can draw and drops the pinpricks it cannot.
    squeeze = max(squeeze, draw.ring.y / 12.0);

    float3 light = float3(0.0);
    for (int k = 0; k < 3; k++) {
        float wavelength = draw.colors[k].w;
        if (wavelength <= 0.0) { continue; }
        float reflect = ollin_flare_coated(ray.cosOuter, wavelength, ray.outerDesign, ray.outerFrom, ray.outerTo)
                      * ollin_flare_coated(ray.cosInner, wavelength, ray.innerDesign, ray.innerFrom, ray.innerTo);
        light += draw.colors[k].rgb * reflect;
    }
    // A flare follows how much of its source the camera can see, the followed
    // ghosts like the rest.
    float seen = visibility.read(uint2(uint(draw.source.x), 0)).x;
    out.light = light * (measured ? ray.passes * seen : 0.0) / max(squeeze, 1e-8);
    return out;
}

// What light does at a straight edge a short way from it: the intensity across
// the shadow line of a half plane, which overshoots to about 1.37 just inside,
// rings with a tightening period further in, and is a quarter exactly on the
// line. `w` is the distance inside the edge in the pattern's own unit. The two
// auxiliary functions of the Fresnel integrals are the standard rational fits.
static inline float ollin_flare_edge_pattern(float w, float blur) {
    float reach = abs(w);
    float f = (1.0 + 0.926 * reach) / (2.0 + 1.792 * reach + 3.104 * reach * reach);
    float g = 1.0 / (2.0 + 4.142 * reach + 3.492 * reach * reach + 6.670 * reach * reach * reach);
    float tail = 0.5 * (f * f + g * g);
    if (w < 0.0) { return tail; }
    float phase = 0.5 * M_PI_F * w * w;
    // The rings wash out where they are finer than what blurs them (the source's
    // size and the pixel), and a band of color is never one wavelength, so they
    // fade after the first few in any case.
    float fine = M_PI_F * w * blur;
    float damp = exp(-0.5 * fine * fine) * exp(-0.5 * (0.06 * phase) * (0.06 * phase));
    return 1.0 + tail + damp * ((f - g) * sin(phase) - (f + g) * cos(phase));
}

// The iris's edge again, for a pixel that only wants the distance: the same walk
// round the blades with nothing kept but the largest.
static inline float ollin_flare_iris_edge(float2 p, float inner,
                                          constant OllinLensFlareUniforms &flare) {
    int count = int(flare.iris.x);
    if (count < 3) { return length(p) - inner; }
    float reach = -1e9;
    for (int k = 0; k < count; k++) {
        float4 pair = flare.blades[k / 2];
        reach = max(reach, dot(p, (k & 1) == 0 ? pair.xy : pair.zw));
    }
    return reach - inner;
}

fragment float4 ollin_flare_trace_fragment(OllinFlareTraceOut in [[stage_in]],
                                           constant OllinLensFlareUniforms &flare [[buffer(0)]]) {
    // A pixel the ghost does not reach is thrown away as early as that is known.
    // The pass adds, so writing nothing there would be the same picture, but it
    // would still pay for the blade walk and the blend: measured, keeping the
    // early outs is worth between a tenth and a quarter of the pass.
    //
    // A cell with a lost ray at one corner fades toward that corner rather than
    // being cut out whole, which would draw the grid's own squares.
    if (in.valid <= 0.0) { discard_fragment(); }
    // Stopped by the barrel: past the rim of some element along the way. The
    // edge is as soft as the source is wide, like every other edge of a ghost.
    float rim = max(in.edges.x, 0.004);
    float barrel = 1.0 - smoothstep(1.0 - rim, 1.0 + rim, in.relative);
    if (barrel <= 0.0) { discard_fragment(); }
    float inner = flare.iris.z;
    float edge = ollin_flare_iris_edge(in.aperture, inner, flare);
    float through = ollin_flare_overlap(max(inner + edge, 0.0), inner, in.edges.y);
    if (through <= 0.0) { discard_fragment(); }
    float3 shaped = float3(through);
    // Close to a crisp edge the light rings. Only a small source shows it: once
    // the source's blur is as wide as the first ring, the plain soft edge is all
    // there is, and the pattern is not worked out at all.
    float scale = in.edges.z;
    float blurred = in.edges.y * scale;
    if (scale > 0.0 && blurred < 1.0 && -edge * scale < 14.0 && -edge * scale > -6.0) {
        float keep = 1.0 - smoothstep(0.35, 1.0, blurred);
        if (in.wavelengths.y > 0.0) {
            // Three colors in one pass, each ringing at its own scale, which is
            // what tints the rings.
            for (int c = 0; c < 3; c++) {
                float own = scale * sqrt(550.0 / max(in.wavelengths[c], 1.0));
                float pattern = ollin_flare_edge_pattern(-edge * own, in.edges.y * own);
                shaped[c] = mix(through, pattern, keep);
            }
        } else {
            float own = scale * sqrt(550.0 / max(in.wavelengths.x, 1.0));
            shaped = float3(mix(through, ollin_flare_edge_pattern(-edge * own, in.edges.y * own), keep));
        }
    }
    return float4(in.light * shaped * (barrel * in.valid * in.valid), 1.0);
}

// Add the flare to the resolved frame, in linear light and before the tone map,
// because a flare is light arriving at the sensor rather than paint on the
// finished picture: the ghosts, read from the half-size canvas they were worked
// out on, and the star, read at full size.
fragment float4 ollin_flare_composite(PresentOut in [[stage_in]],
                                      texture2d<float> frame [[texture(0)]],
                                      texture2d<float> visibility [[texture(1)]],
                                      texture2d<float> starPattern [[texture(2)]],
                                      texture2d<float> ghosts [[texture(3)]],
                                      texture2d<float> followed [[texture(4)]],
                                      sampler samp [[sampler(0)]],
                                      constant OllinLensFlareUniforms &flare [[buffer(0)]]) {
    float4 base = frame.sample(samp, in.uv);
    float aspect = flare.optics.w;
    float2 screen = float2((in.uv.x * 2.0 - 1.0) * aspect, 1.0 - in.uv.y * 2.0);
    float3 sum = ghosts.sample(samp, in.uv, level(0)).rgb;
    // The ghosts that were followed ray by ray, gathered on a canvas of their own.
    if (flare.starTints[0].w > 0.5) { sum += followed.sample(samp, in.uv, level(0)).rgb; }
    for (int i = 0; i < flare.lightCount; i++) {
        float seen = visibility.read(uint2(uint(i), 0)).x;
        if (seen <= 0.0) { continue; }
        // The star sits on the source itself, where the ghosts deliberately do
        // not. Its pattern is the opening's own power spectrum, baked once, so
        // the arms count the blades and their tips fan into color.
        float reachOut = flare.iris.y;
        if (reachOut > 0.0) {
            float2 offset = (screen - flare.lights[i].zw) / reachOut;
            if (abs(offset.x) < 1.0 && abs(offset.y) < 1.0) {
                // The frame measures y upward and the baked pattern downward, so
                // the read turns that axis over. Every regular opening's pattern
                // happens to be even about it, but the coordinate is still the
                // coordinate.
                float2 uv = float2(offset.x * 0.5 + 0.5, 0.5 - offset.y * 0.5);
                float3 pattern = starPattern.sample(samp, uv, level(0)).rgb;
                sum += pattern * flare.starTints[i].rgb * seen;
            }
        }
    }
    return float4(base.rgb + sum, base.a);
}
