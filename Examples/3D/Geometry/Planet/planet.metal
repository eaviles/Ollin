// The maps a planet wears, written once on the GPU.
//
// Every kernel here works in equirectangular map space: u runs once around the
// equator, v from the north pole to the south, which is exactly the uv a sphere
// mesh carries. `planet_direction` turns a texel back into the point on the unit
// sphere it stands for, so every field is a function of a direction rather than
// of a rectangle. That is what keeps the left edge meeting the right edge and
// the poles from tearing.
//
// The first kernel writes the elevation, and the four after it read it rather
// than working the noise out again. So the coast the color shows, the coast the
// relief bends light along, and the coast the cities avoid are all one coast.
//
// Two rules the maps have to keep. Colors are written LINEAR: a float texture
// carries no sRGB decode on read, so what a kernel writes is what the shading
// gets, and `srgbToLinear` is what turns a tone picked by eye into the number to
// store. And a color map's ALPHA IS OPACITY, never a spare channel: the surface
// shader multiplies it into the surface, so a height smuggled in there draws a
// half-transparent world.

constant float SEA = 0.54;               // sea level on the elevation field
constant float TWO_PI = 6.28318530718;

// The point on the unit sphere a map texel stands for. Matches the sphere mesh:
// u is longitude, v runs from the +y pole down, so latitude is (0.5 - v) * pi.
static float3 planet_direction(float2 uv) {
    float lon = uv.x * TWO_PI;
    float lat = (0.5 - uv.y) * 3.14159265359;
    float cl = cos(lat);
    return float3(cl * cos(lon), sin(lat), cl * sin(lon));
}

// Fractal value noise over a direction. The lacunarity is a little off 2 so the
// octave lattices never line up on an axis and leave a grid in the result.
static float planet_fbm(float3 p, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; ++i) {
        sum += amp * valueNoise(p);
        norm += amp;
        p *= 2.03;
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

// The same sum with each octave folded about its middle, so the creases gather
// into lines: the ridge basis a mountain range wants.
static float planet_ridges(float3 p, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; ++i) {
        float n = 1.0 - fabs(2.0 * valueNoise(p) - 1.0);
        sum += amp * n * n;
        norm += amp;
        p *= 2.11;
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

// Fractal noise piles up around its middle, so a field read straight leaves the
// ends of any ramp unused. Spread it about 0.5 before anything reads it.
static float planet_contrast(float v, float gain) {
    return clamp(0.5 + (v - 0.5) * gain, 0.0, 1.0);
}

// How far a place is from the equator, 0 at the equator and 1 at a pole.
static float planet_polarity(float3 dir) { return fabs(dir.y); }

// The map texel's own latitude measure, for a kernel that has no direction in
// hand.
static float planet_row_polarity(uint row, uint rows) {
    return fabs(0.5 - (float(row) + 0.5) / float(rows)) * 2.0;
}

// -----------------------------------------------------------------------------
// Elevation. Everything else reads this: red carries the height, 0 to 1, with
// SEA the waterline.
// -----------------------------------------------------------------------------
kernel void planet_height(texture2d<float, access::write> dst [[texture(0)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float3 dir = planet_direction(uv);
    float seed = p[0];

    // Continents: fractal noise reading its own displaced coordinates, which is
    // what turns an even spatter of blobs into land with bays and peninsulas.
    float3 q = dir * 1.55 + seed * 19.7;
    float3 warp = float3(planet_fbm(q + 4.1, 4),
                         planet_fbm(q + 9.7, 4),
                         planet_fbm(q + 15.3, 4)) - 0.5;
    float land = planet_contrast(planet_fbm(q + warp * 1.35, 10), 1.9);

    // Ranges, only where there is land already, so no mountain rises out of the
    // sea, and a fold of the ridges again at four times the rate for the spurs
    // and side valleys that keep a range from reading as one smooth wall.
    float above = smoothstep(SEA - 0.01, SEA + 0.07, land);
    float ranges = planet_ridges(dir * 6.1 + seed * 5.3, 6);
    float spurs = planet_ridges(dir * 24.0 + seed * 2.9, 4);

    // Two more sums the coast needs. The first breaks the shoreline into bays and
    // headlands at a scale a map texel can hold; the second is the grain under
    // everything, which is what stops a hillside from reading as painted.
    float bays = planet_fbm(dir * 42.0 + seed * 3.7, 4) - 0.5;
    float grain = planet_fbm(dir * 150.0 + seed * 7.1, 3) - 0.5;

    float elev = land
               + 0.15 * ranges * above
               + 0.045 * spurs * above
               + 0.030 * bays
               + 0.008 * grain;
    dst.write(float4(clamp(elev, 0.0, 1.0), 0.0, 0.0, 1.0), gid);
}

// -----------------------------------------------------------------------------
// The surface color. Opaque, linear, and read as the base color of the globe.
// -----------------------------------------------------------------------------
kernel void planet_surface(texture2d<float, access::read> src [[texture(0)]],
                           texture2d<float, access::write> dst [[texture(1)]],
                           constant float *p [[buffer(11)]],
                           uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float3 dir = planet_direction(uv);
    float seed = p[0];

    float elev = src.read(gid).r;
    float pole = planet_polarity(dir);
    // 0 at the shore, 1 at the highest ground there is. The divisor is the range
    // the elevation field actually uses above the waterline, measured rather than
    // assumed: too small a one saturates, and then most of a continent reads as
    // summit and the whole interior turns to rock.
    float height = clamp((elev - SEA) / (1.0 - SEA), 0.0, 1.0);

    // Water. Three stops rather than two: the deep, the slope up to the shelf,
    // and the pale green over the shallowest of it, which is the color that says
    // "shallow" more than any amount of lightening does.
    float depth = clamp((SEA - elev) / 0.30, 0.0, 1.0);
    float3 abyss = srgbToLinear(float3(0.016, 0.055, 0.129));
    float3 sea = srgbToLinear(float3(0.055, 0.184, 0.322));
    float3 shelf = srgbToLinear(float3(0.145, 0.400, 0.463));
    float3 water = mix(shelf, sea, smoothstep(0.0, 0.28, depth));
    water = mix(water, abyss, smoothstep(0.30, 0.85, depth));
    water *= 0.94 + 0.12 * planet_fbm(dir * 26.0 + seed * 4.3, 3);

    // How steep the ground is here, read off the height map itself. Flat low
    // ground holds water and grows things; a slope sheds both and shows its rock.
    // The x step is divided by the cosine of the latitude, because a map like this
    // one packs its columns closer together as it climbs toward a pole, and
    // without that a hillside would read as steeper the further north it stands.
    uint xl = (gid.x + w - 1) % w, xr = (gid.x + 1) % w;
    uint yu = gid.y > 0 ? gid.y - 1 : 0, yd = min(gid.y + 1, h - 1);
    float dhx = (src.read(uint2(xr, gid.y)).r - src.read(uint2(xl, gid.y)).r)
              / max(sqrt(1.0 - dir.y * dir.y), 0.25);
    float dhy = src.read(uint2(gid.x, yd)).r - src.read(uint2(gid.x, yu)).r;
    float slope = length(float2(dhx, dhy)) * float(w) / 2048.0;

    // The land is chosen the way a biome map is: warm or cold, wet or dry. Warmth
    // falls off toward the poles and with altitude. Wet is four things at once,
    // which is what keeps a continent from reading as two or three flat patches:
    // the rain belts (wet at the equator, dry at the horse latitudes, wet again in
    // the middle latitudes), a slow field for which quarter of a continent is
    // green at all, a middling one for the regions inside it, a fine one for the
    // grain, and the ground's own shape, since a valley holds what a ridge sheds.
    float warmth = clamp(1.16 - 1.30 * pow(pole, 2.3) - 0.70 * height, 0.0, 1.0);
    float belts = 0.5 + 0.5 * cos((pole - 0.05) * 8.8);
    float wetBig = planet_contrast(planet_fbm(dir * 4.3 + seed * 3.1 + 31.0, 6), 1.5);
    float wetMid = planet_contrast(planet_fbm(dir * 15.0 + seed * 4.7 + 17.0, 5), 1.35);
    float wetFine = planet_fbm(dir * 55.0 + seed * 9.3, 4) - 0.5;
    float wetGrain = planet_fbm(dir * 190.0 + seed * 13.1, 3) - 0.5;
    float lowland = 1.0 - smoothstep(0.05, 0.55, height);
    float sheltered = 1.0 - smoothstep(0.02, 0.13, slope);
    float wet = clamp(0.22 * belts
                      + 0.34 * wetBig
                      + 0.34 * wetMid
                      + 0.22 * wetFine
                      + 0.10 * wetGrain
                      + 0.12 * (lowland * sheltered - 0.35)
                      - 0.05, 0.0, 1.0);

    float3 rainforest = srgbToLinear(float3(0.106, 0.208, 0.094));
    float3 woodland = srgbToLinear(float3(0.196, 0.286, 0.137));
    float3 grass = srgbToLinear(float3(0.353, 0.396, 0.208));
    float3 steppe = srgbToLinear(float3(0.529, 0.478, 0.310));
    float3 desert = srgbToLinear(float3(0.714, 0.596, 0.388));
    float3 taiga = srgbToLinear(float3(0.145, 0.216, 0.157));
    float3 tundra = srgbToLinear(float3(0.400, 0.412, 0.353));

    // Dry to wet along one ramp. Every step is a smoothstep, so nothing draws a
    // border.
    float3 ground = mix(desert, steppe, smoothstep(0.20, 0.32, wet));
    ground = mix(ground, grass, smoothstep(0.34, 0.45, wet));
    ground = mix(ground, woodland, smoothstep(0.46, 0.58, wet));
    ground = mix(ground, rainforest, smoothstep(0.60, 0.76, wet)
                                     * smoothstep(0.45, 0.75, warmth));

    // The cold end is not one thing. A cold country with rain on it is forest,
    // the widest band of trees there is, and only the cold country without rain
    // is the bare ground that reads as tundra. Collapsing both into one color is
    // what leaves a planet with a grey lid.
    float3 cold = mix(tundra, taiga, smoothstep(0.26, 0.44, wet));
    ground = mix(ground, cold, smoothstep(0.46, 0.18, warmth));

    // The valleys of a dry country are still green, which is where a river would
    // be. This is the cheap stand-in for one: the low flat ground of a place that
    // is warm enough, greener than the country it runs through.
    float3 riparian = srgbToLinear(float3(0.243, 0.318, 0.153));
    float drainage = sheltered * lowland
                   * smoothstep(0.20, 0.55, wet + 0.25 * wetFine)
                   * smoothstep(0.25, 0.55, warmth);
    ground = mix(ground, riparian, drainage * 0.55);

    // Sand where the ground meets the water, a strip a few texels wide.
    float3 beach = srgbToLinear(float3(0.769, 0.686, 0.514));
    ground = mix(ground, beach, (1.0 - smoothstep(0.0, 0.045, height))
                                * smoothstep(0.10, 0.35, warmth));

    // Rock, banded by what it is made of. It shows up two ways: high ground wears
    // it, and so does any slope steep enough to shed its soil, which is what puts
    // bare stone down the sides of a range and leaves the floor between them green.
    float3 rock = srgbToLinear(mix(float3(0.353, 0.322, 0.290),
                                   float3(0.451, 0.408, 0.365),
                                   planet_fbm(dir * 19.0 + seed * 6.1, 4)));
    // The slope band is measured too: on this terrain the open country runs
    // around 0.02 to 0.05, and only the ridge lines and the cliffs pass 0.05.
    float bare = max(smoothstep(0.62, 0.92, height),
                     smoothstep(0.050, 0.105, slope) * smoothstep(0.05, 0.40, height));
    ground = mix(ground, rock, bare);

    // Three grains over everything, an octave apart: the regional color, the
    // county-sized patchiness, and the fine mottle at the scale of a few texels,
    // which together are most of what reads as detail from a distance.
    ground *= 0.90 + 0.20 * planet_fbm(dir * 13.0 + seed * 2.3 + 71.0, 4);
    ground *= 0.93 + 0.14 * planet_fbm(dir * 38.0 + seed * 5.1 + 29.0, 4);
    ground *= 0.94 + 0.12 * planet_fbm(dir * 95.0 + seed * 8.7, 3);
    // And a little color drift with it, so no two regions of one biome match.
    ground *= float3(0.97 + 0.07 * planet_fbm(dir * 9.0 + seed * 1.7, 3),
                     1.0,
                     0.97 + 0.07 * planet_fbm(dir * 9.0 + seed * 1.7 + 41.0, 3));

    // Snow: down to sea level at the caps, only on the summits near the equator.
    // The line wanders, so a cap has a ragged edge rather than a drawn circle.
    float3 snow = srgbToLinear(float3(0.937, 0.949, 0.965));
    float wander = planet_fbm(dir * 7.0 + seed * 5.9 + 13.0, 4) - 0.5;
    float snowLine = 0.96 - 0.46 * height + 0.20 * wander;
    float capped = smoothstep(snowLine - 0.10, snowLine + 0.05, pole);
    ground = mix(ground, snow * (0.84 + 0.22 * planet_fbm(dir * 70.0 + seed, 4)), capped);

    // Sea ice, ragged at its edge the way pack ice is, and thinning to slush.
    float ice = smoothstep(0.88, 0.96, pole + 0.10 * wander);
    water = mix(water, snow * 0.88, ice);

    float3 color = mix(water, ground, smoothstep(SEA - 0.002, SEA + 0.002, elev));
    dst.write(float4(color, 1.0), gid);
}

// -----------------------------------------------------------------------------
// Relief: the elevation's own slopes, encoded as a tangent-space normal map.
// -----------------------------------------------------------------------------
kernel void planet_relief(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    // Longitude wraps, latitude clamps: the map's left edge is the right edge,
    // and there is nothing past a pole.
    uint xl = (gid.x + w - 1) % w, xr = (gid.x + 1) % w;
    uint yu = gid.y > 0 ? gid.y - 1 : 0, yd = min(gid.y + 1, h - 1);

    // Which channel carries the field: red for the elevation, alpha for the
    // cloud's own cover, so one kernel gives both the ground and the weather
    // their relief.
    bool fromAlpha = p[1] > 0.5;
    float hl = fromAlpha ? src.read(uint2(xl, gid.y)).a : src.read(uint2(xl, gid.y)).r;
    float hr = fromAlpha ? src.read(uint2(xr, gid.y)).a : src.read(uint2(xr, gid.y)).r;
    float hu = fromAlpha ? src.read(uint2(gid.x, yu)).a : src.read(uint2(gid.x, yu)).r;
    float hd = fromAlpha ? src.read(uint2(gid.x, yd)).a : src.read(uint2(gid.x, yd)).r;
    float here = fromAlpha ? src.read(gid).a : src.read(gid).r;

    // Only the land has relief. Water is left flat, so the sun glints off it
    // as a mirror rather than off a rippled sheet of noise. Cloud is relief all
    // the way through, so it takes the whole strength wherever it is.
    float land = fromAlpha ? 1.0 : smoothstep(SEA - 0.004, SEA + 0.02, here);
    // A map like this one crowds its columns together toward a pole, so the same
    // step in texels stands for less and less ground and the slopes there read
    // as noise. Let the relief go before that happens.
    float fade = 1.0 - smoothstep(0.72, 0.94, planet_row_polarity(gid.y, h));
    float strength = p[0] * land * fade;

    float dx = (hr - hl) * 0.5 * strength;
    float dy = (hd - hu) * 0.5 * strength;
    float3 n = normalize(float3(-dx, dy, 1.0));
    dst.write(float4(n * 0.5 + 0.5, 1.0), gid);
}

// -----------------------------------------------------------------------------
// Finish: roughness in green, metallic in blue, the standard packing.
// -----------------------------------------------------------------------------
kernel void planet_finish(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float elev = src.read(gid).r;
    float land = smoothstep(SEA - 0.004, SEA + 0.01, elev);

    // Open water is nearly a mirror, which is what puts a sun on the sea. Ground
    // is rough, and ice sits between the two.
    float pole = planet_row_polarity(gid.y, h);
    float icy = smoothstep(0.86, 0.94, pole);
    float rough = mix(0.16, 0.92, land);
    rough = mix(rough, 0.45, icy);

    dst.write(float4(1.0, rough, 0.0, 1.0), gid);
}

// -----------------------------------------------------------------------------
// The lights people leave on: only on land, low ground, away from the caps.
// -----------------------------------------------------------------------------
kernel void planet_lights(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float3 dir = planet_direction(uv);
    float seed = p[0];
    float elev = src.read(gid).r;

    float land = step(SEA, elev);
    float lowland = 1.0 - smoothstep(0.02, 0.16, elev - SEA);   // near the water
    float temperate = 1.0 - smoothstep(0.58, 0.86, planet_polarity(dir));
    // Where a civilization settled at all: a slow field, cubed so most of the
    // world stays dark and a few regions carry nearly all of the light.
    float region = planet_contrast(planet_fbm(dir * 3.1 + seed * 7.9 + 53.0, 4), 1.7);
    region = region * region * region;

    // The towns themselves: cell cores from a Worley field, each a soft point.
    float d = worley(dir * 62.0, 0.95);
    float town = smoothstep(0.30, 0.02, d);
    float scatter = planet_fbm(dir * 140.0 + seed, 2);          // uneven brightness

    float lit = land * lowland * temperate * region * town * (0.45 + 0.55 * scatter);

    // Sodium orange through to a colder white, the mix a city seen from orbit has.
    float3 warm = srgbToLinear(float3(1.000, 0.702, 0.361));
    float3 cool = srgbToLinear(float3(0.851, 0.902, 1.000));
    float3 tint = mix(warm, cool, smoothstep(0.35, 0.75, scatter));
    dst.write(float4(tint * lit * 3.0, 1.0), gid);
}

// -----------------------------------------------------------------------------
// Weather: white cloud, cover in alpha. Sheared by latitude so the bands turn
// at different rates, the way a spinning atmosphere drags them.
// -----------------------------------------------------------------------------
kernel void planet_clouds(texture2d<float, access::write> dst [[texture(0)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float seed = p[0], cover = p[1];
    float pole = planet_row_polarity(gid.y, h);

    // Shear the longitude by latitude before the noise reads it: the same field
    // then arrives stretched into the streaks weather sits in.
    float2 sheared = float2(uv.x + 0.06 * (1.0 - pole) * (1.0 - pole), uv.y);
    float3 dir = planet_direction(sheared);

    float3 q = dir * 3.4 + seed * 11.3;
    float3 warp = float3(planet_fbm(q + 2.7, 4),
                         planet_fbm(q + 8.9, 4),
                         planet_fbm(q + 13.1, 4)) - 0.5;
    float f = planet_contrast(planet_fbm(q + warp * 0.55, 6), 1.5);

    // Bands: a wet belt at the equator, dry latitudes either side of it, storms
    // again in the middle latitudes. The cosine is the cheapest honest shape.
    float band = 0.74 + 0.26 * cos(pole * 9.4);
    float threshold = mix(0.80, 0.30, clamp(cover, 0.0, 1.0));
    float density = smoothstep(threshold, threshold + 0.22, f * band);

    dst.write(float4(1.0, 1.0, 1.0, density), gid);
}
