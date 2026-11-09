// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A portal's gate whose card names no shader of its own (`FormBase.look_shader`; Feel's portal look,
// `Carrier.LOOK_PORTAL`; core/README.md, "The shot shaders"): the plain dark lens, its edge in the
// first infusion's shadow (`shot_portal.gdshaderinc`). The portal card draws its own (the mote rift's
// lens, `content/spells/forms/portal/portal.gdshader`); this is only the fallback. Its lips, its
// loose motes and the line to each exit are motes. Blending is premultiplied: its pixels are opaque.

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
	COLOR = plain_gate(gate_pixel(), pal);
}
