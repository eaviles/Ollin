// The maps a planet uses, written on the GPU.
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
constant float PI = 3.14159265359;
constant float TWO_PI = 6.28318530718;

// The point on the unit sphere a map texel stands for. Matches the sphere mesh:
// u goes round from the back (-z) by -x, the front (u = 0.5 on +z), and +x, which
// is west to east for someone looking at the ball; v runs from the +y pole down,
// so latitude is (0.5 - v) * pi.
static float3 planet_direction(float2 uv) {
    float turn = uv.x * TWO_PI;
    float lat = (0.5 - uv.y) * PI;
    float cl = cos(lat);
    return float3(-cl * sin(turn), sin(lat), -cl * cos(turn));
}

// And back: the place on the map a direction lands.
static float2 planet_place(float3 dir) {
    float turn = atan2(-dir.x, -dir.z);
    float lat = asin(clamp(dir.y, -1.0, 1.0));
    return float2(fract(turn / TWO_PI + 1.0), 0.5 - lat / PI);
}

// Fractal noise over a direction, 0 to 1 with its middle at a half. Each octave
// is simplex noise, whose lattice has no axes to line up along, and the step
// between octaves is a little off 2 and carries a shift, so no two of them share
// a lattice either.
//
// How many octaves a caller asks for is not a matter of taste. A 4096-wide map
// holds about 650 texels to the radian, and a wave it can carry smoothly needs
// three of them or more, so nothing here is asked for past about 200 cycles to
// the radius. A finer octave is still noise in a still picture. On a world
// that turns it is a shimmer, each texel coming and going as it crosses a pixel.
static float planet_fbm(float3 p, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; ++i) {
        sum += amp * simplexNoise(p);
        norm += amp;
        p = p * 2.03 + 17.3;
        amp *= 0.5;
    }
    return clamp(0.5 + 0.72 * sum / max(norm, 1e-5), 0.0, 1.0);
}

// The same sum with each octave folded about zero, so the creases gather into
// lines, and with each octave held back where the one before it was low. Detail
// then piles up on the crests and the valley floors stay smooth, which is the
// difference between a mountain range and crumpled paper.
static float planet_ridges(float3 p, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0, carry = 1.0;
    for (int i = 0; i < octaves; ++i) {
        float n = 1.0 - fabs(simplexNoise(p));
        n = n * n * n * carry;
        carry = clamp(n * 2.0, 0.0, 1.0);
        sum += amp * n;
        norm += amp;
        p = p * 2.11 + 9.1;
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

// The sum again with each octave only a little weaker than the last, so the
// fine end carries nearly as much as the coarse: the texture of cloud, which is
// ragged at every size at once.
static float planet_vapor(float3 p, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; ++i) {
        sum += amp * simplexNoise(p);
        norm += amp;
        p = p * 2.07 + 23.9;
        amp *= 0.62;
    }
    return clamp(0.5 + 0.9 * sum / max(norm, 1e-5), 0.0, 1.0);
}

// Fractal noise piles up around its middle, so a field read straight leaves the
// ends of any ramp unused. Spread it about 0.5 before anything reads it.
static float planet_contrast(float v, float gain) {
    return clamp(0.5 + (v - 0.5) * gain, 0.0, 1.0);
}

// A bump centered on `middle` and about `width` to either side, for anything
// that happens in a band of latitude.
static float planet_band(float at, float middle, float width) {
    float d = (at - middle) / width;
    return exp(-d * d);
}

// How far a place is from the equator, 0 at the equator and 1 at a pole.
static float planet_polarity(float3 dir) { return fabs(dir.y); }

// The map row's own latitude, in radians, for a kernel with no direction in hand.
static float planet_row_latitude(uint row, uint rows) {
    return (0.5 - (float(row) + 0.5) / float(rows)) * PI;
}

// The slope of a map's field at a texel, as change per radian going east and
// going south. Longitude wraps and latitude clamps: the map's left edge is its
// right edge, and there is nothing past a pole. The east step is divided by the
// cosine of the latitude, because a map like this one packs its columns closer
// together as it climbs toward a pole, and without that a hillside would read as
// steeper the further north it stands. Measured per radian rather than per
// texel, so a map of any size gives the same slope for the same ground.
//
// The field is the map's red channel, or for the weather its red times its
// alpha: how bright the cloud is, which is how thick, times how much of it there
// is, which together are how high its top stands.
static float2 planet_grade(texture2d<float, access::read> map, uint2 gid, bool fromAlpha) {
    uint w = map.get_width(), h = map.get_height();
    uint xl = (gid.x + w - 1) % w, xr = (gid.x + 1) % w;
    uint yu = gid.y > 0 ? gid.y - 1 : 0, yd = min(gid.y + 1, h - 1);
    float4 l = map.read(uint2(xl, gid.y)), r = map.read(uint2(xr, gid.y));
    float4 u = map.read(uint2(gid.x, yu)), d = map.read(uint2(gid.x, yd));
    float east = fromAlpha ? r.a * r.r - l.a * l.r : r.r - l.r;
    float south = fromAlpha ? d.a * d.r - u.a * u.r : d.r - u.r;
    float narrow = max(cos(planet_row_latitude(gid.y, h)), 0.05);
    return float2(east / (2.0 * TWO_PI / float(w) * narrow),
                  south / (2.0 * PI / float(h)));
}

// How much open water lies within `reach` degrees of a texel, 0 for none and 1
// for water on every side. Eight looks around a ring.
static float planet_shore(texture2d<float, access::read> map, uint2 gid, float reach) {
    int w = int(map.get_width()), h = int(map.get_height());
    float narrow = max(cos(planet_row_latitude(gid.y, uint(h))), 0.08);
    float wet = 0.0;
    for (int i = 0; i < 8; ++i) {
        float a = (float(i) + 0.5) * TWO_PI / 8.0;
        int dx = int(round(cos(a) * reach / 360.0 * float(w) / narrow));
        int dy = int(round(sin(a) * reach / 180.0 * float(h)));
        int x = ((int(gid.x) + dx) % w + w) % w;
        int y = clamp(int(gid.y) + dy, 0, h - 1);
        wet += step(map.read(uint2(uint(x), uint(y))).r, SEA);
    }
    return wet / 8.0;
}

// A point turned about an axis through the center, by the right-hand rule.
static float3 planet_turned(float3 p, float3 axis, float angle) {
    float c = cos(angle), s = sin(angle);
    return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

// -----------------------------------------------------------------------------
// Elevation. Everything else reads this. Red carries the height, 0 to 1, with
// SEA the waterline. Green says how much of that height is mountain rather than
// plain, and blue is the continent's broad shape with none of the detail on it.
// This map is never drawn, so its channels are free to be data.
// -----------------------------------------------------------------------------
kernel void planet_height(texture2d<float, access::write> dst [[texture(0)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float3 dir = planet_direction(uv);
    float seed = p[0];

    // Continents. A slow field, three octaves and no more, says where the land
    // is: a few masses with open ocean between them. It reads its own displaced
    // coordinates, which is what bends an even spatter of blobs into shapes with
    // arms and gulfs. It is squeezed toward two levels, the ocean floor and the
    // continental plain, without ever reaching either, so the inside of a
    // continent keeps some height left over for its mountains.
    float3 q = dir * 0.80 + seed * 19.7;
    float3 warp = float3(planet_fbm(q * 1.6 + 4.1, 4),
                         planet_fbm(q * 1.6 + 9.7, 4),
                         planet_fbm(q * 1.6 + 15.3, 4)) - 0.5;
    float lean = (planet_fbm(q + warp * 0.55, 3) - 0.5) * 7.0;
    float continent = 0.43 + 0.30 * lean / (1.0 + fabs(lean));
    // The coast is everything finer, seven octaves of it, so the shoreline is
    // still breaking up at the size of a few texels.
    float coast = planet_fbm(dir * 3.4 + warp * 0.8 + seed * 2.7 + 60.0, 7) - 0.5;
    float land = clamp(continent + 0.30 * coast, 0.0, 1.0);

    // Ranges, only where there is land already, so no mountain rises out of the
    // sea. They come in belts, the way they do where two plates meet, rather
    // than evenly over every continent: a slow field says where the belts are,
    // and the ridges are strong inside one and low hills outside it.
    float above = smoothstep(SEA - 0.01, SEA + 0.06, land);
    float belt = smoothstep(0.46, 0.64,
                            planet_fbm(dir * 2.3 + warp * 0.9 + seed * 8.1 + 40.0, 4));
    float ranges = planet_ridges(dir * 4.4 + warp * 0.5 + seed * 5.3, 6);
    float mountain = ranges * (0.14 + 0.86 * belt) * above;

    float elev = land + 0.30 * mountain;
    dst.write(float4(clamp(elev, 0.0, 1.0), mountain, continent, 1.0), gid);
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

    float4 field = src.read(gid);
    float elev = field.r, mountain = field.g, continent = field.b;
    float pole = planet_polarity(dir);
    float latitude = asin(pole) * 57.29578;            // degrees off the equator
    // 0 at the shore, 1 at the highest ground there is. The divisor is the range
    // the elevation field actually uses above the waterline, measured rather than
    // assumed: too small a one saturates, and then most of a continent reads as
    // summit and the whole interior turns to rock.
    float height = clamp((elev - SEA) / (1.0 - SEA), 0.0, 1.0);

    // How steep the ground is here, read off the height map itself. Flat low
    // ground holds water and grows things; a slope sheds both and shows its rock.
    float slope = length(planet_grade(src, gid, false)) * 0.0061;

    // How close the sea is, near and far. The sea is where the rain comes from,
    // so a coast is greener than the middle of the same continent.
    float shore = 0.5 * planet_shore(src, gid, 2.0) + 0.5 * planet_shore(src, gid, 6.0);

    // Water. Deep ocean is nearly black with a little blue in it: most of the
    // blue of a sea seen from space is the air over it, which the sketch adds
    // afterwards. The pale green of a shallow shelf belongs to warm water, so it
    // shows in the tropics and thins out toward the poles.
    float depth = clamp((SEA - elev) / 0.30, 0.0, 1.0);
    float3 abyss = srgbToLinear(float3(0.012, 0.043, 0.110));
    float3 sea = srgbToLinear(float3(0.020, 0.078, 0.176));
    float3 shelf = srgbToLinear(float3(0.047, 0.243, 0.290));
    float3 water = mix(sea, abyss, smoothstep(0.10, 0.75, depth));
    float tropical = 1.0 - smoothstep(18.0, 42.0, latitude);
    float shoal = (1.0 - smoothstep(0.0, 0.085, depth))
                * (0.25 + 0.75 * tropical)
                * planet_contrast(planet_fbm(dir * 21.0 + seed * 6.7, 4), 2.2);
    water = mix(water, shelf, shoal * 0.8);
    // Currents and plankton: slow swirls a shade greener or darker than the rest.
    float3 swirl = dir * 5.0 + seed * 4.3;
    swirl += (float3(planet_fbm(swirl + 3.1, 3), planet_fbm(swirl + 7.7, 3),
                     planet_fbm(swirl + 12.9, 3)) - 0.5) * 1.6;
    float bloom = planet_fbm(swirl * 2.6, 5);
    water *= float3(0.86, 0.92 + 0.22 * bloom, 0.90 + 0.16 * bloom);

    // The land is chosen the way a biome map is: warm or cold, wet or dry.
    //
    // Warmth falls off toward the poles and with altitude, and altitude here is
    // mostly the mountains: a high plain is a little cooler than the coast, and
    // a summit is a great deal cooler.
    float altitude = 0.14 * height + 1.05 * mountain;
    float warmth = clamp(1.0 - 1.10 * pole * pole - altitude, -0.3, 1.0);

    // Wet is several things at once, which is what keeps a continent from
    // reading as two or three flat patches. The rain belts come first: wet at
    // the equator where the air rises, dry either side of it where the same air
    // comes down again, wet once more under the storm tracks of the middle
    // latitudes. Then the sea's reach, a slow field for which side of a
    // continent the weather favors, finer ones for the regions inside that, and
    // the ground's own shape, since a valley holds what a ridge sheds.
    float rain = planet_band(latitude, 0.0, 16.0) + 0.74 * planet_band(latitude, 47.0, 18.0);
    float wetBig = planet_contrast(planet_fbm(dir * 3.3 + seed * 3.1 + 31.0, 5), 1.7);
    float wetMid = planet_contrast(planet_fbm(dir * 12.0 + seed * 4.7 + 17.0, 5), 1.6);
    float wetFine = planet_fbm(dir * 48.0 + seed * 9.3, 3) - 0.5;
    float wetGrain = planet_fbm(dir * 110.0 + seed * 13.1, 2) - 0.5;
    float lowland = 1.0 - smoothstep(0.05, 0.50, height + 0.6 * mountain);
    float sheltered = 1.0 - smoothstep(0.02, 0.12, slope);
    float inland = smoothstep(0.60, 0.70, continent) * (1.0 - shore);
    float wet = clamp(0.40 * rain
                      + 0.27 * wetBig
                      + 0.17 * wetMid
                      + 0.16 * wetFine
                      + 0.08 * wetGrain
                      + 0.22 * shore
                      - 0.12 * inland
                      + 0.10 * (lowland * sheltered - 0.35)
                      - 0.10, 0.0, 1.0);

    float3 rainforest = srgbToLinear(float3(0.071, 0.165, 0.063));
    float3 woodland = srgbToLinear(float3(0.149, 0.243, 0.110));
    float3 grass = srgbToLinear(float3(0.325, 0.380, 0.196));
    float3 steppe = srgbToLinear(float3(0.553, 0.482, 0.314));
    float3 taiga = srgbToLinear(float3(0.102, 0.176, 0.106));
    float3 tundra = srgbToLinear(float3(0.380, 0.365, 0.286));

    // A desert is not one color. Pale sand, red sand where there is iron in it,
    // and dark stone pavements, in patches the size of countries.
    float3 sand = srgbToLinear(float3(0.812, 0.678, 0.482));
    float3 redSand = srgbToLinear(float3(0.659, 0.427, 0.275));
    float3 pavement = srgbToLinear(float3(0.396, 0.325, 0.267));
    float iron = planet_contrast(planet_fbm(dir * 4.1 + seed * 2.9 + 83.0, 4), 2.4);
    float stony = planet_contrast(planet_fbm(dir * 9.5 + seed * 7.3 + 61.0, 5), 2.6);
    float3 desert = mix(sand, redSand, iron * 0.55);
    desert = mix(desert, pavement, smoothstep(0.55, 0.85, stony) * 0.8);
    // Dunes: long parallel crests, too fine to see one by one, that show as a
    // grain running one way across the sand.
    float dunes = planet_fbm(dir * float3(30.0, 120.0, 30.0) + seed * 3.3, 2);
    desert *= 0.90 + 0.20 * dunes;

    // Dry to wet along one ramp. Every step is a smoothstep, so nothing draws a
    // border, and each is nudged by the fine wetness, so where two kinds of
    // country meet they interleave rather than fade.
    float ragged = wet + 0.05 * wetGrain;
    float3 ground = mix(desert, steppe, smoothstep(0.20, 0.30, ragged));
    ground = mix(ground, grass, smoothstep(0.32, 0.42, ragged));
    ground = mix(ground, woodland, smoothstep(0.43, 0.54, ragged));
    ground = mix(ground, rainforest, smoothstep(0.56, 0.72, ragged)
                                     * smoothstep(0.50, 0.78, warmth));

    // The cold end is not one thing. A cold country with rain on it is forest,
    // the widest band of trees there is, and only the cold country without rain
    // is the bare ground that reads as tundra. Collapsing both into one color is
    // what leaves a planet with a gray lid.
    float3 cold = mix(tundra, taiga, smoothstep(0.24, 0.42, ragged));
    ground = mix(ground, cold, smoothstep(0.34, 0.14, warmth));

    // The valleys of a dry country are still green, which is where a river would
    // be. This is the cheap stand-in for one: the low flat ground of a place that
    // is warm enough, greener than the country it runs through.
    float3 riparian = srgbToLinear(float3(0.196, 0.286, 0.129));
    float drainage = sheltered * lowland
                   * smoothstep(0.18, 0.50, wet + 0.25 * wetFine)
                   * smoothstep(0.20, 0.50, warmth);
    ground = mix(ground, riparian, drainage * 0.45);

    // Rock, banded by what it is made of, and taking a little of the color of
    // the country it stands in. It shows up two ways: high ground has it, and so
    // does any slope steep enough to shed its soil, which is what puts bare stone
    // down the sides of a range and leaves the floor between them green.
    float3 rock = srgbToLinear(mix(float3(0.318, 0.290, 0.263),
                                   float3(0.431, 0.388, 0.345),
                                   planet_fbm(dir * 19.0 + seed * 6.1, 4)));
    rock = mix(rock, desert * 0.72, (1.0 - smoothstep(0.18, 0.36, wet)) * 0.6);
    float bare = max(smoothstep(0.24, 0.56, mountain),
                     smoothstep(0.045, 0.110, slope) * smoothstep(0.06, 0.26, mountain));
    ground = mix(ground, rock, bare);

    // Three grains over everything, an octave or so apart: the regional color,
    // the county-sized patchiness, and the fine mottle at the scale of a few
    // texels, which together are most of what reads as detail from a distance.
    ground *= 0.88 + 0.24 * planet_fbm(dir * 13.0 + seed * 2.3 + 71.0, 4);
    ground *= 0.90 + 0.20 * planet_fbm(dir * 44.0 + seed * 5.1 + 29.0, 3);
    ground *= 0.90 + 0.20 * planet_fbm(dir * 120.0 + seed * 8.7, 2);
    // And a little color drift with it, so no two regions of one biome match.
    ground *= float3(0.96 + 0.08 * planet_fbm(dir * 9.0 + seed * 1.7, 3),
                     1.0,
                     0.96 + 0.08 * planet_fbm(dir * 9.0 + seed * 1.7 + 41.0, 3));

    // Snow lies where it is cold enough: all of the far north and south, and the
    // summits anywhere. The line wanders, so a cap has a ragged edge rather than
    // a drawn circle, and a steep face sheds its snow and shows as rock.
    float3 snow = srgbToLinear(float3(0.925, 0.941, 0.961));
    float wander = planet_fbm(dir * 6.0 + seed * 5.9 + 13.0, 5) - 0.5;
    float frost = warmth + 0.16 * wander + 0.05 * wetFine;
    float capped = smoothstep(0.065, -0.005, frost)
                 * (1.0 - 0.55 * smoothstep(0.09, 0.16, slope));
    ground = mix(ground, snow * (0.86 + 0.20 * planet_fbm(dir * 70.0 + seed, 2)), capped);

    // Sea ice, ragged at its edge the way pack ice is, with leads of open water
    // through it, thinning to slush before it ends.
    float pack = smoothstep(0.045, -0.035, warmth + 0.14 * wander + 0.10 * wetFine + 0.02);
    float leads = smoothstep(0.30, 0.50, planet_fbm(dir * 85.0 + seed * 2.1, 2));
    water = mix(water, snow * 0.90, pack * (0.35 + 0.65 * leads));

    float3 color = mix(water, ground, smoothstep(SEA - 0.0015, SEA + 0.0015, elev));
    dst.write(float4(color, 1.0), gid);
}

// -----------------------------------------------------------------------------
// Relief: a field's own slopes, encoded as a tangent-space normal map. The first
// parameter is how tall the field stands, in planet radii at its full value.
// -----------------------------------------------------------------------------
kernel void planet_relief(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    // Which map this is: the elevation, with its field in red, or the weather,
    // whose field is its brightness times its cover. One kernel gives both the
    // ground and the cloud their relief.
    bool fromAlpha = p[1] > 0.5;
    float4 here = src.read(gid);

    // Only the land has relief. Water is left flat, and its roughness is what
    // spreads the sun across it. Cloud is relief all the way through, so it takes
    // the whole strength wherever it is.
    float land = fromAlpha ? 1.0 : smoothstep(SEA - 0.004, SEA + 0.02, here.r);
    // Right at a pole every column of the map is the same place, and a slope
    // measured between two of them means nothing. Let the relief go there.
    float polar = fabs(planet_row_latitude(gid.y, h)) / (0.5 * PI);
    float fade = 1.0 - smoothstep(0.90, 0.985, polar);

    float2 tilt = planet_grade(src, gid, fromAlpha) * p[0] * land * fade;
    float3 n = normalize(float3(-tilt.x, tilt.y, 1.0));
    dst.write(float4(n * 0.5 + 0.5, 1.0), gid);
}

// -----------------------------------------------------------------------------
// Finish: roughness in green, metallic in blue, the standard packing.
// -----------------------------------------------------------------------------
kernel void planet_finish(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float3 dir = planet_direction(uv);
    float seed = p[0];
    float elev = src.read(gid).r;
    float land = smoothstep(SEA - 0.004, SEA + 0.01, elev);

    // The sea is not a mirror. Wind keeps it covered in waves far too small to
    // see from here, each one a facet turned a little away from level, and
    // between them they spread the sun's reflection into a soft patch hundreds
    // of kilometers wide. That is a rough surface in the sense the shading
    // means. Where the wind drops the patch tightens and brightens, so the
    // roughness follows a slow field of calms and blows.
    float wind = planet_contrast(planet_fbm(dir * 4.6 + seed * 6.7 + 91.0, 5), 1.8);
    float gusts = planet_fbm(dir * 31.0 + seed * 2.3 + 47.0, 4) - 0.5;
    float water = clamp(0.36 + 0.20 * wind + 0.08 * gusts, 0.28, 0.62);

    // Ground is rough, and ice sits between the two.
    float icy = smoothstep(0.86, 0.94, fabs(planet_row_latitude(gid.y, h)) / (0.5 * PI));
    float rough = mix(water, 0.93, land);
    rough = mix(rough, 0.62, icy);

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
    float4 field = src.read(gid);
    float elev = field.r;

    float land = step(SEA, elev);
    float height = clamp((elev - SEA) / (1.0 - SEA), 0.0, 1.0);
    float lowland = 1.0 - smoothstep(0.10, 0.42, height + 1.8 * field.g);
    float temperate = 1.0 - smoothstep(0.62, 0.88, planet_polarity(dir));
    // People live by the water: a coast, a strait, an inland sea.
    float coast = 0.50 + 0.50 * smoothstep(0.0, 0.45, planet_shore(src, gid, 1.6));

    // Where a civilization settled at all: a slow field, squared so most of the
    // world stays dark and a few regions carry nearly all of the light. Inside
    // a region the density has provinces, and inside those, districts.
    float region = planet_contrast(planet_fbm(dir * 3.3 + seed * 7.9 + 53.0, 4), 2.2);
    region = region * region;
    float province = planet_contrast(planet_fbm(dir * 13.0 + seed * 3.3 + 7.0, 4), 2.2);
    float district = planet_contrast(planet_fbm(dir * 58.0 + seed * 5.1 + 23.0, 3), 2.0);
    float people = region * (0.20 + 0.80 * province) * coast * lowland * temperate;

    // Three sizes of place. A few great cities, each a bright core in a wide
    // dimmer sprawl, larger where there are more people to fill it. Towns, many
    // and small. And the scatter under both: single texels switched on at random,
    // more of them where the country is fuller, which from this far is what
    // villages and roads add up to.
    float metro = worley(dir * 52.0 + seed * 1.3, 1.0);
    float reach = 0.05 + 0.22 * sqrt(people);
    float city = 0.6 * exp(-pow(metro / reach, 2.0) * 3.0) * smoothstep(0.05, 0.30, people);
    city += 2.2 * exp(-pow(metro / (0.30 * reach), 2.0) * 3.0) * smoothstep(0.10, 0.40, people);

    float town = worley(dir * 130.0 + seed * 2.9, 1.0);
    float towns = exp(-pow(town / 0.20, 2.0) * 3.0) * smoothstep(0.42, 0.72, district)
                * smoothstep(0.02, 0.14, people);

    float3 dice = hash33(float3(float2(gid) + 0.5, seed * 13.0 + 1.0));
    float scatter = step(1.0 - 0.30 * people * (0.20 + 0.80 * district), dice.x)
                  * (0.25 + 0.75 * dice.y);

    float lit = land * (1.3 * city + 0.8 * towns + 0.6 * scatter);

    // Sodium orange through to a colder white, the mix a city seen from orbit
    // has: the old streets orange, the new ones and the brightest cores white.
    float3 warm = srgbToLinear(float3(1.000, 0.682, 0.337));
    float3 cool = srgbToLinear(float3(0.925, 0.933, 1.000));
    float3 tint = mix(warm, cool, smoothstep(0.55, 1.0, dice.z) * 0.6
                                  + 0.3 * smoothstep(1.2, 2.6, city));
    dst.write(float4(tint * lit * 2.0, 1.0), gid);
}

// -----------------------------------------------------------------------------
// Weather: white cloud, cover in alpha.
// -----------------------------------------------------------------------------
kernel void planet_clouds(texture2d<float, access::write> dst [[texture(0)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float seed = p[0], cover = clamp(p[1], 0.0, 1.0);
    float3 dir = planet_direction(uv);
    float latitude = asin(planet_polarity(dir)) * 57.29578;

    // Storms. The big weather of the middle latitudes is a wheel: air drawn in
    // toward a low and turned by the planet's spin, counterclockwise north of
    // the equator and clockwise south of it. So before any noise is read, the
    // place it is read at is wound around each of a handful of centers, tightly
    // near the middle and not at all at the rim. Whatever the noise holds there
    // comes out wound into arms.
    float3 at = dir;
    float storm = 0.0;
    for (int k = 0; k < 11; ++k) {
        float3 roll = hash33(float3(float(k) * 7.31 + 1.7, seed * 3.17 + 0.5, 11.9));
        float side = (k % 2 == 0) ? 1.0 : -1.0;
        // Most of them follow the storm tracks; every fourth is a tropical one,
        // smaller and wound tighter.
        bool tropical = (k % 4 == 3);
        float lat = side * (tropical ? mix(12.0, 22.0, roll.x) : mix(36.0, 62.0, roll.x))
                  / 57.29578;
        float lon = roll.y * TWO_PI;
        float3 center = float3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));
        float size = tropical ? mix(0.09, 0.15, roll.z) : mix(0.22, 0.38, roll.z);
        float d = acos(clamp(dot(at, center), -1.0, 1.0)) / size;
        if (d < 1.0) {
            float fall = (1.0 - d) * (1.0 - d);
            float wind = (tropical ? 1.9 : 1.25) * fall / (d + 0.22);
            at = planet_turned(at, center, -side * wind);
            storm = max(storm, fall * (tropical ? 1.25 : 1.0));
        }
    }

    // Weather lies along the wind, which blows mostly east or west. Reading the
    // noise with its north-south axis squeezed leaves every feature longer east
    // to west than it is tall.
    float3 s = at * float3(1.0, 1.6, 1.0);

    // How much water the air holds here: one fractal, weighted toward its fine
    // end so the field is ragged at every size, read through a gentle warp.
    float3 q = s * 2.2 + seed * 11.3;
    float3 warp = float3(planet_fbm(q + 2.7, 3),
                         planet_fbm(q + 8.9, 3),
                         planet_fbm(q + 13.1, 3)) - 0.5;
    float vapor = planet_vapor(q + warp * 0.7, 7);

    // The climate under it: a belt of towering cloud along the equator where
    // the air rises, clear skies either side of it where the same air comes down
    // and makes the deserts, and the storm tracks beyond.
    float climate = 0.10 * planet_band(latitude, 4.0, 8.0)
                  - 0.09 * planet_band(latitude, 25.0, 10.0)
                  + 0.05 * planet_band(latitude, 53.0, 15.0)
                  + 0.03 * planet_band(latitude, 90.0, 22.0);
    // Cloud forms where there is more water than the air can hold. `cover`
    // moves that limit.
    float excess = vapor + climate + (0.08 + 0.10 * cover) * storm
                 - mix(0.90, 0.307, cover);

    // A field of cumulus is cells: each lump a rising column with clear air
    // sinking around it. Inside a thick cloud the cells are its lumpy top; where
    // the air is only nearly full they stand alone, as a scatter of small
    // clouds with ground showing between them.
    float2 cells = worley2(s * 64.0 + warp * 3.0 + seed, 1.0);
    float puff = smoothstep(0.62, 0.12, cells.x);
    float depth = max(excess, 0.0) * (0.60 + 0.70 * puff)
                + max(excess + 0.07, 0.0) * puff * puff * 0.55;

    // How much of the ground a cloud hides goes with how deep it is the way
    // light through fog does: quickly at first, then less and less.
    float thick = 1.0 - exp(-depth * 11.0);
    // How high its top stands, 0 to 1. A deeper cloud is also a brighter one, so
    // the same number is its shade of white, and the relief is read off the two
    // together.
    float tops = 1.0 - exp(-depth * 5.0);

    // And over and around the thick cloud, the thin kind: ice high up, drawn out
    // into streaks by faster wind, that never hides the ground and only veils it.
    float3 high = at * float3(1.0, 3.0, 1.0);
    float streaks = planet_vapor(high * 7.0 + warp * 1.5 + seed * 6.1 + 21.0, 4);
    float veil = smoothstep(-0.16, 0.06, excess) * smoothstep(0.48, 0.78, streaks) * 0.34;

    float density = 1.0 - (1.0 - thick) * (1.0 - veil);
    dst.write(float4(float3(0.74 + 0.26 * tops), density), gid);
}

// -----------------------------------------------------------------------------
// The shadow the weather throws on the ground, written again every frame,
// because the sun moves over the ground and the weather drifts across it.
//
// For each place on the ground: go toward the sun until the height the cloud
// stands at, and ask how much cloud is there. The answer is black, with that
// much opacity, for a shell drawn between the ground and the cloud.
//
// Parameters: the direction to the sun in the ground's own frame (3), how far
// the weather has turned ahead of the ground about the axis (1), how high the
// cloud stands in planet radii (1), and how dark a full shadow is (1).
// -----------------------------------------------------------------------------
kernel void planet_shadow(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float *p [[buffer(11)]],
                          uint2 gid [[thread_position_in_grid]]) {
    constexpr sampler across(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    uint w = dst.get_width(), h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float3 dir = planet_direction(uv);
    float3 sun = normalize(float3(p[0], p[1], p[2]));
    float ahead = p[3], lift = p[4], dark = p[5];

    // Night has no shadows, and a sun on the horizon throws one too long to
    // follow, so it fades out before that.
    float up = dot(dir, sun);
    if (up <= 0.03) { dst.write(float4(0.0), gid); return; }

    // Where the line toward the sun crosses the cloud's height.
    float along = -up + sqrt(up * up + 2.0 * lift + lift * lift);
    float3 above = normalize(dir + sun * along);

    // That is a place over the ground. The weather has turned on since, so the
    // same place in the weather's own map is that much further back.
    float c = cos(ahead), s = sin(ahead);
    float3 inWeather = float3(above.x * c - above.z * s, above.y, above.x * s + above.z * c);

    float cover = src.sample(across, planet_place(inWeather), level(0.0)).a;
    float shade = cover * dark * smoothstep(0.03, 0.16, up);
    dst.write(float4(0.0, 0.0, 0.0, shade), gid);
}
