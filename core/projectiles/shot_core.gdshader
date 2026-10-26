// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_mix;

// The look of a player's shot (staffs B6a, docs/milestones/M2-staffs.md, "The look of a shot"),
// built here on a pixel grid of GRID x GRID cells, so a shot needs no art and no nodes.
//
// MultiMesh instances (the projectile manager) carry:
//   custom data rgb  the core colour (the first infusion's tint; white for none)
//   custom data a    the body kind as 1 - kind / 16: 1 a bolt (with a trail), 2 a rune, 3 an
//                    orbit shot; 0 draws the texture (below)
//   colour r         the player index (0-3) as n / 255
//   colour g, b      the four look layers, two per channel as (first * 16 + second) / 255:
//                    the first two infusions, then the first two modifiers with a look
//   colour a         the zoom as n / 255: the quad is GRID x zoom screen pixels, and the
//                    shapes grow with it while every line stays one pixel, so a bigger shot
//                    is bigger, never chunkier
// Paint order: the trail (in the player's colour, bolts only), the layers, the core (its
// outline is the player's shadow shade, so a shot says whose it is even in a crowd).
// A layer kind is one of the LOOK_* constants of `core/projectiles` (1-12); each card names
// its own in `look_layer`, so a new card only touches this file for a new kind of effect.
//
// Kind 0 is the old sprite path, still used by Feel's lone Sprite2D flashes: a neutral bone
// sprite whose Spark-coloured pixels take `core_override`'s colour (alpha above 0 turns it on).

uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour of the sprite path: the tint and the fade of a lone Sprite2D.
uniform vec4 body_tint = vec4(1.0);
// Seconds of simulation, set by the projectile manager; everything animates from it, not TIME,
// so a run stepped by hand (the clip recorder) draws the same frames every time.
uniform float sim_time = 0.0;

const float GRID = 16.0;

// docs/STYLE.md: the players' ramps (shadow, base, light) and the colours the layers use.
const vec3 P_SHADOW[4] = vec3[](vec3(0.114, 0.227, 0.420), vec3(0.478, 0.137, 0.278), vec3(0.122, 0.290, 0.227), vec3(0.290, 0.165, 0.420));
const vec3 P_BASE[4] = vec3[](vec3(0.231, 0.451, 0.788), vec3(0.851, 0.278, 0.478), vec3(0.247, 0.561, 0.310), vec3(0.541, 0.310, 0.769));
const vec3 P_LIGHT[4] = vec3[](vec3(0.498, 0.753, 0.941), vec3(0.961, 0.604, 0.722), vec3(0.561, 0.831, 0.416), vec3(0.788, 0.604, 0.941));
const vec3 FIRE_BASE = vec3(0.878, 0.349, 0.184);
const vec3 FIRE_LIGHT = vec3(1.0, 0.635, 0.235);
const vec3 ICE_LIGHT = vec3(0.769, 0.965, 0.949);
const vec3 SPARK_LIGHT = vec3(1.0, 0.953, 0.651);
const vec3 VOID_BASE = vec3(0.627, 0.188, 0.604);
const vec3 VOID_LIGHT = vec3(0.878, 0.541, 0.847);
const vec3 ARC_BASE = vec3(0.706, 0.910, 0.165);
const vec3 ARC_LIGHT = vec3(0.933, 1.0, 0.651);
const vec3 BONE_LIGHT = vec3(0.957, 0.945, 0.918);

// The layer kinds (LOOK_* in projectile_manager.gd).
const float L_FLICKER = 1.0;
const float L_FLECKS = 2.0;
const float L_GUSTS = 3.0;
const float L_PULL = 4.0;
const float L_SPARKS = 5.0;
const float L_MOTES = 6.0;
const float L_HALO = 7.0;
const float L_STRETCH = 8.0;
const float L_RIM = 9.0;
const float L_RING = 10.0;
const float L_WOBBLE = 11.0;
const float L_GLOW = 12.0;

varying flat vec4 body;
varying flat vec3 core;
varying flat float kind;
varying flat float phase;
varying flat float player;
varying flat float zoom;
varying flat vec4 layers;

void vertex() {
	core = core_override.a > 0.0 ? core_override.rgb : INSTANCE_CUSTOM.rgb;
	kind = core_override.a > 0.0 ? 0.0 : floor((1.0 - INSTANCE_CUSTOM.a) * 16.0 + 0.5);
	phase = float(INSTANCE_ID % 4);
	body = COLOR * body_tint;
	player = clamp(floor(COLOR.r * 255.0 + 0.5), 0.0, 3.0);
	zoom = max(floor(COLOR.a * 255.0 + 0.5), 1.0);
	float a = floor(COLOR.g * 255.0 + 0.5);
	float b = floor(COLOR.b * 255.0 + 0.5);
	layers = vec4(floor(a / 16.0), mod(a, 16.0), floor(b / 16.0), mod(b, 16.0));
}

float triangle(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

// The animation frame (0-3) at `rate` frames a second. Each shot starts on its own frame, so
// a volley does not blink together.
float frame_of(float rate) {
	return mod(floor(sim_time * rate + phase + 0.001), 4.0);
}

// A number in [0, 1) from a seed and the frame: the same on every machine.
float hash(float seed, float f) {
	return fract(sin(seed * 12.9898 + f * 78.233 + phase * 37.719) * 43758.5453);
}

bool has_layer(float look) {
	return any(equal(layers, vec4(look)));
}

// True when the pixel centred at `q` is the pixel of the point `at` (both in pixels).
bool on(vec2 q, vec2 at) {
	return all(equal(floor(q), floor(at)));
}

// One layer at pixel `q` (relative to the core's centre), its distances in units of `z`
// pixels and its strokes one pixel wide: a colour, or alpha 0 for nothing.
vec4 layer(float look, vec2 q, float z) {
	float r = length(q);
	if (look == L_FLICKER) {
		// Fire drops embers behind it that drift off the line, two at a time.
		float f = frame_of(12.0);
		for (float n = 0.0; n < 2.0; n += 1.0) {
			vec2 at = vec2(-3.0 - n * 2.0 - mod(f + n, 2.0), (hash(n, f) - 0.5) * 5.0) * z;
			if (on(q, at)) {
				return vec4(n < 0.5 ? FIRE_LIGHT : FIRE_BASE, 1.0);
			}
		}
	} else if (look == L_FLECKS) {
		// Frost: two glints circling the core in quarter turns.
		float a = frame_of(4.0) * 1.5708 + 0.785;
		vec2 at = vec2(cos(a), sin(a)) * 3.6 * z;
		if (on(q, at) || on(q, -at)) {
			return vec4(ICE_LIGHT, 1.0);
		}
	} else if (look == L_GUSTS) {
		// Storm: two short streaks beside the shot, blown backwards.
		float x = q.x + (2.0 + frame_of(20.0)) * z;
		if (abs(abs(q.y) - 3.5 * z) < 0.5 && x < 0.0 && x > -3.0 * z) {
			return vec4(SPARK_LIGHT, 1.0);
		}
	} else if (look == L_PULL) {
		// Void: four pixels falling inward from the corners, over and over.
		float d = (6.0 - mod(sim_time * 10.0 + phase, 4.0)) * z;
		for (float n = 0.0; n < 4.0; n += 1.0) {
			float a = n * 1.5708 + 0.785;
			if (on(q, vec2(cos(a), sin(a)) * d)) {
				return vec4(d < 3.5 * z ? VOID_LIGHT : VOID_BASE, 1.0);
			}
		}
	} else if (look == L_SPARKS) {
		// Lightning: sparks jump round it every frame, and now and then a one-frame arc.
		float f = floor(sim_time * 16.0 + phase);
		for (float n = 0.0; n < 2.0; n += 1.0) {
			float a = hash(n + 3.0, f) * 6.2832;
			if (on(q, vec2(cos(a), sin(a)) * (3.0 + 2.0 * hash(n + 7.0, f)) * z)) {
				return vec4(ARC_LIGHT, 1.0);
			}
		}
		if (hash(11.0, f) > 0.7) {
			float a = hash(13.0, f) * 6.2832;
			vec2 dir = vec2(cos(a), sin(a));
			float along = dot(q, dir);
			float jag = floor(hash(floor(along / z), f) * 3.0) - 1.0;
			if (along > 2.5 * z && along < 7.0 * z && abs(dot(q, vec2(-dir.y, dir.x)) - jag) < 0.6) {
				return vec4(ARC_BASE, 1.0);
			}
		}
	} else if (look == L_MOTES) {
		// Mend: motes that rise off the shot.
		float y = (2.0 + mod(sim_time * 6.0 + phase, 4.0)) * z;
		if (on(q, vec2(-2.0 * z, -y)) || on(q, vec2(1.0 * z, -y - 2.0 * z))) {
			return vec4(ARC_LIGHT, 1.0);
		}
	} else if (look == L_HALO) {
		// Bigger: a dotted halo round the core.
		if (abs(r - 3.4 * z) < 0.5 && mod(floor(q.x) + floor(q.y), 2.0) < 0.5) {
			return vec4(BONE_LIGHT, 0.8);
		}
	} else if (look == L_STRETCH) {
		// Pierce: a bright point in front.
		if (on(q, vec2(3.5 * z, 0.0)) || on(q, vec2(3.5 * z, -1.0))) {
			return vec4(BONE_LIGHT, 1.0);
		}
	} else if (look == L_RIM) {
		// Blast: a rim that pulses out twice a second.
		float f = frame_of(8.0);
		if (f < 3.0 && abs(r - (3.0 + f * 0.5) * z) < 0.5) {
			return vec4(FIRE_LIGHT, 1.0);
		}
	} else if (look == L_RING) {
		// Shield: a dotted ring that holds still.
		if (abs(r - 5.0 * z) < 0.55 && mod(floor(atan(q.y, q.x) / 0.3927), 2.0) < 0.5) {
			return vec4(BONE_LIGHT, 1.0);
		}
	} else if (look == L_GLOW) {
		// Hold: a soft checkered glow.
		if (r < 4.0 * z && r > 2.5 * z && mod(floor(q.x) + floor(q.y), 2.0) < 0.5) {
			return vec4(SPARK_LIGHT, 0.5);
		}
	}
	return vec4(0.0);
}

// Rune: a diamond outline about its hit size that swells and settles while it waits, with a
// sparse dotted fill so the floor shows through and a bright heart. `h` is half the quad
// in pixels. Returns the tier (0 none, 1 the player's edge, 2 the core colour, 3 its light).
float rune(vec2 q, float h, float f) {
	float swell = f < 0.5 ? 0.0 : (f < 1.5 ? 1.0 : (f < 2.5 ? 2.0 : 1.0));
	float reach = h * (0.44 + 0.04 * swell);
	float d = abs(q.x) + abs(q.y);
	if (d > reach) {
		return 0.0;
	}
	if (d > reach - 1.5) {
		return 1.0;
	}
	if (d > reach - 2.5 || d < 2.5) {
		return d < 1.5 && swell > 1.5 ? 3.0 : 2.0;
	}
	return mod(floor(q.x), 3.0) < 0.5 && mod(floor(q.y), 3.0) < 0.5 ? 2.0 : 0.0;
}

// Orbit shot: two beads on opposite sides of a middle that turns in eighth turns and breathes.
// `z` is the zoom; the beads are about 5 pixels across at zoom 1.
float beads(vec2 q, float z, float f) {
	float a = f * 0.7854;
	float breathe = (3.5 + 0.7 * triangle(f * 0.25)) * z;
	vec2 off = vec2(cos(a), sin(a)) * breathe;
	float near = min(length(q - off), length(q + off));
	if (near > 1.6 * z + 0.9) {
		return 0.0;
	}
	if (near > 1.6 * z) {
		return 1.0;
	}
	return near < 0.8 * z ? 3.0 : 2.0;
}

vec4 procedural(vec2 uv) {
	// The screen pixel, with +x along the flight, the centre of the quad at 0, pixel centres at .5.
	float size = GRID * zoom;
	vec2 q = floor(uv * size) - size * 0.5 + 0.5;
	int pi = int(player);
	vec3 light = mix(core, vec3(1.0), 0.55);
	vec4 colour = vec4(0.0);
	vec2 c = vec2(0.0);
	if (kind < 1.5 && has_layer(L_WOBBLE)) {
		// Homing: the shot weaves a pixel either side.
		c.y = triangle(sim_time * 3.0 + phase * 0.25) > 0.0 ? 1.0 : 0.0;
	}
	// The trail: two pixels wide near the shot, one further back, in the player's colour.
	if (kind < 1.5) {
		float t = (c.x - 2.0 * zoom - q.x) / zoom;
		float dy = q.y - c.y;
		if (t > 0.0 && t < 7.0) {
			bool near = t < 3.5 && abs(dy) < zoom;
			bool far = t >= 3.5 && dy > 0.0 && dy < max(zoom * 0.5, 1.0) && (t < 6.0 || mod(floor(sim_time * 10.0 + phase), 2.0) < 0.5);
			if (near || far) {
				colour = vec4(near ? P_LIGHT[pi] : P_BASE[pi], 1.0);
			}
		}
	}
	for (int n = 0; n < 4; n++) {
		if (layers[n] > 0.5) {
			vec4 l = layer(layers[n], q - c, zoom);
			if (l.a > 0.0) {
				colour = l;
			}
		}
	}
	float t = 0.0;
	if (kind < 1.5) {
		vec2 d = q - c;
		if (has_layer(L_STRETCH)) {
			d.x *= 0.6;
		}
		float r = length(d);
		bool flicker = has_layer(L_FLICKER) && frame_of(12.0) > 1.5;
		t = r < 0.8 * zoom ? (flicker ? 2.0 : 3.0) : (r < 1.6 * zoom ? 2.0 : (r < 1.6 * zoom + 0.9 ? 1.0 : 0.0));
	} else if (kind < 2.5) {
		t = rune(q, size * 0.5, frame_of(3.0));
	} else {
		t = beads(q, zoom, mod(floor(sim_time * 8.0 + phase), 8.0));
	}
	if (t > 0.5) {
		vec3 rgb = t < 1.5 ? P_SHADOW[pi] : (t < 2.5 ? core : light);
		colour = vec4(rgb, 1.0);
	}
	return colour;
}

void fragment() {
	if (kind > 0.5) {
		COLOR = procedural(UV);
	} else {
		vec4 t = texture(TEXTURE, UV);
		vec3 rgb = t.rgb * body.rgb;
		float warm = smoothstep(0.1, 0.25, t.r - t.b);
		float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		float shade = clamp((lum - 0.5) / 0.45, 0.0, 1.0);
		vec3 lit = mix(core * 0.55, mix(core, vec3(1.0), 0.55), shade);
		COLOR = vec4(mix(rgb, lit, warm), t.a * body.a);
	}
}
