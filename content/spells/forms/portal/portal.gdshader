// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A portal's gate, the mote rift (content/spells/forms/portal/; the owner's pick, 2026-11-09): a dark
// lens standing across the way through, its edge in the first infusion's shadow, its stars twinkling
// motes of light drifting through it (into a mouth, out of an exit), each in an infusion of its
// palette in turn (`palette_turn`). It opens tall, then wide, and closes the other way: the portal look
// sizes its quad by how open it is (`shot_portal.gdshaderinc`, `gameplay/feel/portal_look.gd`), and
// lays the lips' streams of motes, the loose motes spiralling in and thrown out, and the dotted line
// to each exit as real motes round it. Drawn by Feel's portal look (`Carrier.LOOK_PORTAL`), warmed
// before the first room. Blending is premultiplied: its pixels are opaque.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_portal.gdshaderinc"

// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 pal;

void vertex() {
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, gate_seed(INSTANCE_CUSTOM.a), false);
	SET_LOOK(L);
	PLACE_GATE;
	pal = palette_floats(L.core, L.bits);
}

void fragment() {
	vec2 q = gate_pixel();
	vec4 colour = plain_gate(q, pal);
	// A star: now and then a pixel of the dark lit, drifting across with the way through.
	if (gate_part(q) > 1.5 && hash(q.y, floor(q.x + sim_time * 3.0 * gate.z), gate.w) > 0.95) {
		colour = vec4(palette_turn(pal, int(q.x + q.y), hash(q.x, q.y, 4.0) > 0.7 ? 2 : 1, hash(q.x, q.y, 4.0) > 0.7 ? hi : mid), 1.0);
	}
	COLOR = colour;
}
