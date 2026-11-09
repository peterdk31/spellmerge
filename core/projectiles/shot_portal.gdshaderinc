// SPDX-License-Identifier: GPL-3.0-or-later
// A portal's gate as the portal look hands it over (Feel's `portal_look.gd`, `Carrier.LOOK_PORTAL`;
// docs/milestones/carrier-looks-fixes.md, phase 2): one quad an open gate. Its transform's x axis
// runs across the way through the gate (the lens's width now, plus GATE_PAD each side), its y axis
// up it (its height now, plus GATE_PAD each side), its origin the gate's middle: so how open it is
// (tall, then wide) is the quad's own size, worked out once by the look, which places the lips'
// motes by the same numbers. Its colour is the portal's look (`ProjectileManager.look_color`), its
// custom data the core colour and, in alpha, a mouth (0.5 and up) or an exit with the gate's own
// seed (the rest, times two). The shader that includes this calls PLACE_GATE in vertex() (after
// SET_LOOK) and draws from `gate_pixel()`; `plain_gate` is the plain drawing (`shot_portal.gdshader`).
// The lips, the loose motes and the line to each exit are motes (the look's, not the shader's).

// Pixels round the lens inside its quad (room for its edge).
const float GATE_PAD = 2.0;
// The lens's dark.
const vec3 GATE_DARK = vec3(0.078, 0.071, 0.122);

// Worked out once a gate (vertex): the lens's half width and half height now, the way things go
// through it (1 into a mouth, -1 out of an exit) and its seed; its unit axes (across, up) and its
// middle in the world; and the world point under each fragment.
varying flat vec4 gate;
varying flat vec4 gate_axes;
varying flat vec2 gate_centre;
varying vec2 gate_world;

#define PLACE_GATE gate_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; gate_centre = MODEL_MATRIX[3].xy; gate_axes = vec4(normalize(MODEL_MATRIX[0].xy), normalize(MODEL_MATRIX[1].xy)); gate = vec4(max(length(MODEL_MATRIX[0].xy) * 0.5 - GATE_PAD, 0.0), max(length(MODEL_MATRIX[1].xy) * 0.5 - GATE_PAD, 0.0), INSTANCE_CUSTOM.a >= 0.5 ? 1.0 : -1.0, fract(INSTANCE_CUSTOM.a * 2.0) * 97.0)

// The seed a gate's look is drawn with (its own, from its instance), for `look_from_color`.
float gate_seed(float custom_a) {
	return fract(custom_a * 2.0) * 97.0;
}

// The world pixel under this fragment, from the gate's middle: x across the way through, y up it.
vec2 gate_pixel() {
	vec2 d = floor(gate_world) + 0.5 - gate_centre;
	return vec2(dot(d, gate_axes.xy), dot(d, gate_axes.zw));
}

// Half the lens's width `j` pixels up it.
float gate_half(float j) {
	float n = j / max(gate.y, 0.001);
	return gate.x * sqrt(max(0.0, 1.0 - n * n));
}

// 2 inside the lens, 1 on its edge (a pixel round it), 0 outside, at the gate's pixel `q`.
float gate_part(vec2 q) {
	if (gate.y < 0.5 || abs(q.y) > gate.y) {
		return 0.0;
	}
	float h = gate_half(q.y);
	return abs(q.x) > h ? 0.0 : (abs(q.x) > h - 1.0 ? 1.0 : 2.0);
}

// The plain gate at its pixel `q`: a dark lens, its edge in the first infusion's shadow (the look's
// shadow with none; `pal` from `palette_floats`). Nothing outside it.
vec4 plain_gate(vec2 q, vec4 pal) {
	float part = gate_part(q);
	if (part < 0.5) {
		return vec4(0.0);
	}
	return vec4(part < 1.5 ? palette_turn(pal, 0, 0, lo) : GATE_DARK, 1.0);
}
