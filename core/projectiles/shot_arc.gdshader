// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// Lightning from the effect's place along its aim for zoom x 4 pixels (Feel's K_ARC: an arc's zap
// or spark, a discharge; its own batch in gameplay/feel/feel.gd; core/README.md, "The shot
// shaders"; owner, 2026-10-30: "arcs should look waaaay cooler"). A jagged bolt that wanders
// widest in its middle, with a white-hot core and coloured edges, up to three forks off it, a star
// where it lands with sparks flying off, and a glow round all of it; re-rolled 30 times a second,
// it strobes, and burns out from its ends as it ages. Its quad is that long plus ARC_MARGIN each
// end, ARC_ACROSS across; the age is the code beside the kind.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

const float ARC_MARGIN = 12.0;
const float ARC_ACROSS = 56.0;
// Pixels between the bolt's bends, and the forks and sparks it has at most.
const float SEG = 5.0;
const int FORKS = 3;
const int SPARKS = 6;

varying flat float age;

void vertex() {
	age = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, false);
	SET_LOOK(L);
}

// How far `p` is from the line `a`-`b`.
float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - (a + ab * t));
}

// Bend `i` of a bolt `len` long with `n` bends, re-rolled on frame `jf`: on the line at both ends,
// wandering up to `amp` across in the middle (a slow sway and a fine jitter on top).
vec2 bend(float i, float n, float len, float jf, float amp) {
	float x = min(i * SEG, len);
	if (i <= 0.0 || i >= n) {
		return vec2(x, 0.0);
	}
	float env = sin(3.14159 * x / len);
	float c = floor(i / 3.0);
	float sway = mix(hash(c, jf, 65.0), hash(c + 1.0, jf, 65.0), fract(i / 3.0)) - 0.5;
	float jitter = hash(i, jf, 61.0) - 0.5;
	return vec2(x, round(env * (sway * 2.4 + jitter * 1.2) * amp));
}

vec4 arc(vec2 uv) {
	float len = zoom * 4.0;
	vec2 size = vec2(len + 2.0 * ARC_MARGIN, ARC_ACROSS);
	// The pixel's middle, the bolt from (0, 0) to (len, 0).
	vec2 p = floor(uv * size) + 0.5 - vec2(ARC_MARGIN, size.y * 0.5);
	float a = age;
	float jf = floor(sim_time * 30.0);
	float n = ceil(len / SEG);
	float amp = clamp(len * 0.12, 2.0, 9.0);
	// It strikes bright, then strobes as it fades.
	float bright = a < 0.12 ? 1.0 : (hash(jf, 0.0, 64.0) < 0.55 ? 1.0 : 0.3) * (1.0 - 0.7 * a);
	bool strong = bright > 0.5;
	// It burns out from the ends inwards as it fades.
	bool kept = hash(floor(p.x), 0.0, 62.0) > a * 1.3 - 0.3;

	// The bolt: its bends round the pixel.
	float dist = 1.0e9;
	float k = floor(p.x / SEG);
	for (int j = -1; j <= 1; j++) {
		float i = k + float(j);
		if (i >= 0.0 && i < n) {
			dist = min(dist, seg_dist(p, bend(i, n, len, jf, amp), bend(i + 1.0, n, len, jf, amp)));
		}
	}

	// The forks: each now and then, from a bend in its first four fifths, off at an angle.
	float fork = 1.0e9;
	if (len >= 14.0 && a < 0.75) {
		for (int b = 0; b < FORKS; b++) {
			float fb = float(b);
			if (hash(fb, jf, 70.0) > 0.6) {
				continue;
			}
			vec2 from = bend(1.0 + floor(hash(fb, jf, 71.0) * max(n - 2.0, 1.0) * 0.8), n, len, jf, amp);
			float turn = (hash(fb, jf, 72.0) < 0.5 ? -1.0 : 1.0) * (0.45 + 0.6 * hash(fb, jf, 73.0));
			vec2 way = vec2(cos(turn), sin(turn));
			vec2 across = vec2(-way.y, way.x);
			float reach = min(len * (0.18 + 0.22 * hash(fb, jf, 74.0)), 26.0);
			vec2 q0 = from;
			for (int s = 1; s <= 3; s++) {
				vec2 q1 = round(from + way * reach * float(s) / 3.0 + across * (hash(fb * 5.0 + float(s), jf, 75.0) - 0.5) * 5.0);
				fork = min(fork, seg_dist(p, q0, q1));
				q0 = q1;
			}
		}
	}

	// Where it lands: a star, and sparks flying off it.
	vec2 end = vec2(len, 0.0);
	vec2 to_end = p - end;
	float flash = max(1.0 - a / 0.4, 0.0);
	float star = max(abs(to_end.x), abs(to_end.y));
	bool on_star = flash > 0.0 && (abs(to_end.x) < 0.6 || abs(to_end.y) < 0.6) && star <= 1.5 + 3.0 * flash;
	bool star_corner = flash > 0.0 && abs(abs(to_end.x) - abs(to_end.y)) < 0.6 && star <= 1.5 + flash;
	bool spark = false;
	bool spark_tail = false;
	if (a < 0.85) {
		for (int s = 0; s < SPARKS; s++) {
			float fs = float(s);
			// Most fly on past the end, a few back.
			float angle = (hash(fs, 0.0, 80.0) - 0.5) * (hash(fs, 0.0, 83.0) < 0.75 ? 2.4 : 6.283);
			float speed = 10.0 + 18.0 * hash(fs, 0.0, 81.0);
			vec2 fly = vec2(cos(angle), sin(angle)) * speed;
			spark = spark || all(equal(floor(end + fly * a), floor(p)));
			spark_tail = spark_tail || all(equal(floor(end + fly * max(a - 0.06, 0.0)), floor(p)));
		}
	}

	// The pixels: core, edges, forks, star and sparks.
	if (kept && dist < 0.75) {
		return vec4(strong ? hot : hi, 1.0);
	}
	if (on_star) {
		return vec4(hot, 1.0);
	}
	if (spark) {
		return vec4(a < 0.4 ? hot : hi, 1.0);
	}
	if (kept && fork < 0.75) {
		return vec4(strong ? hi : mid, 1.0);
	}
	if (kept && dist < 1.6 && hash(floor(p.x), jf, 63.0) < 0.7) {
		return vec4(strong ? hi : mid, 1.0);
	}
	if (star_corner || spark_tail) {
		return vec4(hi, 1.0);
	}
	if (kept && fork < 1.5 && hash(floor(p.x + p.y), jf, 66.0) < 0.3) {
		return vec4(mid, 1.0);
	}
	// The glow round all of it.
	float lit = bright * (0.55 * falloff(dist, 3.0) + 0.35 * falloff(dist, 10.0));
	lit += bright * 0.4 * falloff(fork, 4.0);
	lit += flash * (0.9 * falloff(length(to_end), 4.0) + 0.5 * falloff(length(to_end), 11.0));
	lit += max(1.0 - a / 0.25, 0.0) * 0.5 * falloff(length(p), 4.0);
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = arc(UV);
}
