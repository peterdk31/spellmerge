// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_mix;

// Draws a neutral bone sprite whose Spark-coloured pixels (the "core") take an element's
// colour. The bone part is multiplied by the vertex colour (the owner's tint); the core
// colour is the MultiMesh custom data of the shot, or `core_override` for a lone Sprite2D
// (alpha above 0 turns it on). A pixel is core when it is warm (red well above blue);
// every bone shade is near neutral, so no new palette colour is needed. The core keeps the
// three Spark shades as light and dark.
//
// A shot with an element shape (the alpha of the custom data, 1 - kind / 16) is not drawn
// from the sprite: its own silhouette is built here on a pixel grid, with its own
// animation frames, so the four elements read without colour. Kinds 1-4 are the shot
// bodies (flame, frost star, storm zigzag, void ring) and 5-8 their trail marks (ember,
// glint, streak, ring). The edge pixels take the owner's tint, the inside the element's
// colour, so a shot still says whose it is. Kind 0 (the alpha is 1) is the sprite above.
// Kinds 9 and 10 are the bodies of a form, not an element: the rune (a diamond that pulses
// while it waits) and the orbit shot (two beads that spin round their middle and breathe),
// so rune and orbit differ in flight whatever their element.

uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour: the tint and the fade of a lone Sprite2D (its modulate stays white).
uniform vec4 body_tint = vec4(1.0);
// Seconds of simulation, set by the projectile manager; the shapes animate from it, not TIME,
// so a run stepped by hand (the clip recorder) draws the same frames every time.
uniform float sim_time = 0.0;

// Pixels across a shot body and across a trail mark.
const float BODY_GRID = 12.0;
const float MARK_GRID = 6.0;
// The flame has more pixels so its tail reads.
const float FLAME_GRID = 16.0;

varying flat vec4 body;
varying flat vec3 core;
varying flat float kind;
varying flat float phase;

void vertex() {
	body = COLOR * body_tint;
	core = core_override.a > 0.0 ? core_override.rgb : INSTANCE_CUSTOM.rgb;
	kind = core_override.a > 0.0 ? 0.0 : floor((1.0 - INSTANCE_CUSTOM.a) * 16.0 + 0.5);
	phase = float(INSTANCE_ID % 4);
}

float triangle(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

// The animation frame (0-3) at `rate` frames a second: fire flickers fast, storm jitters,
// frost ticks slowly. Each shot starts on its own frame, so a volley does not blink together.
float frame_of(float rate) {
	return mod(floor(sim_time * rate + phase + 0.001), 4.0);
}

// The pixel colour tiers: 0 = none, 1 = the owner's edge, 2 = the element, 3 = its light.
vec4 tier(float t, vec3 edge, vec3 mid, vec3 light, float alpha) {
	if (t < 0.5) {
		return vec4(0.0);
	}
	vec3 rgb = t < 1.5 ? edge : (t < 2.5 ? mid : light);
	return vec4(rgb, alpha);
}

// Flame: a fat teardrop with a long wavering tail, head forward (on a finer grid).
float flame(vec2 p, float f) {
	float wave = 0.22 * sin(p.x * 5.0 + f * 1.5708) * clamp(0.4 - p.x, 0.0, 1.0);
	float dy = abs(p.y - wave);
	float x = p.x - 0.2;
	float half_w = x >= 0.0 ? sqrt(max(0.0, 0.66 * 0.66 - x * x)) : 0.66 * pow(clamp((p.x + 1.0) / 1.2, 0.0, 1.0), 0.8);
	if (dy > half_w || half_w <= 0.0) {
		return 0.0;
	}
	if (dy > half_w - 0.17) {
		return 1.0;
	}
	return (dy < half_w * 0.45 && p.x > -0.2) ? 3.0 : 2.0;
}

// Frost: a four-point star that ticks between upright and turned, with a glint on the tips.
float star(vec2 p, float f) {
	if (mod(f, 2.0) > 0.5) {
		p = vec2(p.x - p.y, p.x + p.y) * 0.7071;
	}
	float r = length(p);
	if (r > 0.95 || (abs(p.x) * abs(p.y) > 0.07 && r > 0.3)) {
		return 0.0;
	}
	if (r > 0.7) {
		return f < 2.0 ? 3.0 : 1.0;
	}
	return r < 0.3 ? 3.0 : 2.0;
}

// Storm: a zigzag along the aim that jumps a little every frame.
float zigzag(vec2 p, float f) {
	if (abs(p.x) > 0.95) {
		return 0.0;
	}
	float dy = abs(p.y - triangle(p.x * 1.2 + f * 0.31) * 0.45);
	if (dy < 0.09) {
		return 3.0;
	}
	if (dy < 0.19) {
		return 2.0;
	}
	return dy < 0.3 ? 1.0 : 0.0;
}

// Void: a hollow ring that breathes, with one bright pixel circling it.
float ring(vec2 p, float f) {
	float pulse = f < 0.5 ? 0.0 : (f < 1.5 ? 1.0 : (f < 2.5 ? 2.0 : 1.0));
	float radius = 0.5 + 0.12 * pulse;
	float a = f * 1.5708;
	if (length(p - vec2(cos(a), sin(a)) * (radius + 0.12)) < 0.2) {
		return 3.0;
	}
	float d = length(p) - radius;
	if (abs(d) > 0.2) {
		return 0.0;
	}
	return d > 0.05 ? 1.0 : 2.0;
}

// Rune: a diamond that swells and settles while it waits, with a bright heart at the swell.
// It never turns, so it reads as planted.
float rune(vec2 p, float f) {
	float swell = f < 0.5 ? 0.0 : (f < 1.5 ? 1.0 : (f < 2.5 ? 2.0 : 1.0));
	float reach = 0.55 + 0.13 * swell;
	float d = abs(p.x) + abs(p.y);
	if (d > reach) {
		return 0.0;
	}
	if (d > reach - 0.3) {
		return 1.0;
	}
	return (d < 0.3 || swell > 1.5) ? 3.0 : 2.0;
}

// Orbit shot: two beads on opposite sides of a middle that turns in eighth turns and
// breathes (the beads move in and out), so it reads as spinning even from one frame.
float beads(vec2 p, float f) {
	float a = f * 0.7854;
	// Centre at most 0.6 from the middle plus radius 0.32 stays inside the quad (1.0).
	float breathe = 0.5 + 0.1 * triangle(f * 0.25);
	vec2 off = vec2(cos(a), sin(a)) * breathe;
	float near = min(length(p - off), length(p + off));
	if (near > 0.32) {
		return 0.0;
	}
	if (near > 0.2) {
		return 1.0;
	}
	return near < 0.09 ? 3.0 : 2.0;
}

// Trail marks, small and plain: an ember, a glint, a streak, a ring.
float mark(vec2 p, float k, float f) {
	if (k < 5.5) {
		return max(abs(p.x), abs(p.y)) < 0.55 ? (f < 2.0 ? 3.0 : 2.0) : 0.0;
	}
	if (k < 6.5) {
		return ((abs(p.x) < 0.2 || abs(p.y) < 0.2) && length(p) < 0.85) ? 3.0 : 0.0;
	}
	if (k < 7.5) {
		return (abs(p.y) < 0.25 && abs(p.x) < 0.9) ? 3.0 : 0.0;
	}
	float r = length(p);
	return (r > 0.4 && r < 0.9) ? 2.0 : 0.0;
}

void fragment() {
	if (kind > 0.5 && kind < 10.5) {
		float grid = kind > 8.5 ? BODY_GRID : kind > 4.5 ? MARK_GRID : (kind < 1.5 ? FLAME_GRID : BODY_GRID);
		vec2 p = (floor(UV * grid) + 0.5) / grid * 2.0 - 1.0;
		float t = 0.0;
		if (kind < 1.5) {
			t = flame(p, frame_of(12.0));
		} else if (kind < 2.5) {
			t = star(p, frame_of(4.0));
		} else if (kind < 3.5) {
			t = zigzag(p, frame_of(20.0));
		} else if (kind < 4.5) {
			t = ring(p, frame_of(6.0));
		} else if (kind > 9.5) {
			t = beads(p, mod(floor(sim_time * 8.0 + phase), 8.0));
		} else if (kind > 8.5) {
			t = rune(p, frame_of(3.0));
		} else {
			t = mark(p, kind, frame_of(10.0));
		}
		vec3 light = mix(core, vec3(1.0), 0.55);
		COLOR = tier(t, body.rgb, core, light, body.a);
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
