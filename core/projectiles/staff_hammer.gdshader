// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A wizard's staff turning into a hammer (a slam's staff animation, its `hammer` channel; the owner,
// 2026-11-08: "make slam morph the staff into a hammer", "make it bigger"). Drawn by the staff's
// own Hammer node (gameplay/player/staff_look.gd), a square round the staff's grip above the staff
// and under its face, moved and stretched as the staff is: a hammer's head grows out of the
// staff's head, a block of stone across the staff over its tip, outlined, its striking face light,
// its back in shadow, a dark socket where the staff goes through and its two ends bound in the
// glow's colour, with that light round it. As `hammer` rises from 0 to 1 its pixels come in from
// the middle out, white-hot at first; as it falls they go back. `hammer_size` scales it (1 a plain
// slam's; as many times as its cards grew the spell, a bigger card's 1.6). As it lands its head
// smushes (`hammer_squash`, 0 to 0.5: the staff's squash), as a hammer's head does when its end
// strikes: it shortens along its length (its ends driven in toward the staff) and bulges thicker
// along the staff, and a lip spreads at each end; then it springs back. Blending is premultiplied: its pixels are
// opaque, its light added. Warmed as a rect (RECT) before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"

// The hammer's head at size 1: half as thick along the staff and half as long across it, in pixels;
// how far back from the tip its back face is.
const float HALF_THICK = 5.5;
const float HALF_LONG = 10.0;
const float BACK = 6.0;
// How the head smushes at a squash of 1: the share its length shortens by and its thickness grows
// by, and the pixels the lip at each end spreads past its sides (at size 1).
const float SQUASH_SHORT = 1.2;
const float SQUASH_WIDE = 1.6;
const float SQUASH_LIP = 8.0;

// How far the head has turned into the hammer's (0 the staff, 1 the hammer), how big it is, the way
// the drawn staff points (its head sheet's column) and its tip's distance from the grip.
uniform float hammer = 0.0;
uniform float hammer_size = 1.0;
uniform float hammer_squash = 0.0;
uniform vec2 hammer_dir = vec2(1.0, 0.0);
uniform float hammer_reach = 16.0;
// Its bands' and light's colour (the infusion's, else the player's) and how bright the light is.
uniform vec4 glow_color = vec4(1.0);
uniform float hammer_glow = 0.0;
uniform float glow_strength = 1.0;

// The pixel, from the grip.
varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 p = floor(local) + 0.5;
	vec2 dir = hammer_dir;
	vec2 across_dir = vec2(-dir.y, dir.x);
	float grow = clamp(hammer * 1.3, 0.0, 1.0);
	float squash = clamp(hammer_squash, 0.0, 0.5);
	float ht_rest = floor(HALF_THICK * hammer_size + 0.5) * max(grow, 0.3);
	// Squashed, it is shorter along its length and thicker along the staff, round its middle.
	float ht = floor(ht_rest * (1.0 + SQUASH_WIDE * squash) + 0.5);
	float hl = floor(HALF_LONG * hammer_size * max(1.0 - SQUASH_SHORT * squash, 0.4) + 0.5) * grow;
	vec2 h = dir * (hammer_reach - BACK + ht_rest);
	vec2 d = p - h;
	float along = dot(d, dir);
	float across = dot(d, across_dir);
	// The lips at its ends, spread past its sides while it is squashed (its ends driven in).
	float lip = floor(SQUASH_LIP * hammer_size * squash);
	ht += abs(across) > hl - 1.5 - floor(lip * 0.5) ? lip : 0.0;
	vec2 box = vec2(abs(along) - ht, abs(across) - hl);
	// Its light reaches the same few pixels at any size, so a big one stays inside its square.
	float near = falloff(length(max(box, vec2(0.0))), 6.0) * hammer;
	bool inside = box.x <= 0.5 && box.y <= 0.5 && !(box.x > -0.5 && box.y > -0.5);
	// Its pixels come in from the middle out as it grows, and go back the same way.
	float out_from = length(d) / (HALF_LONG * hammer_size + 1.0);
	bool come = hash_seeded(floor(p.x), floor(p.y), 91.0, 0.0) < hammer * 1.8 - out_from * 0.8;
	vec3 band = glow_color.rgb;
	vec4 colour = vec4(0.0);
	if (inside && come && hl >= 0.5) {
		bool edge = box.x > -0.5 || box.y > -0.5;
		float bands = max(floor(1.5 * hammer_size), 1.0);
		// Its striking face (toward the tip) light, its back in shadow, the socket dark.
		vec3 stone = along > ht - 1.0 - bands ? STONE_LIGHT : (along < -ht + 1.0 + bands ? STONE_SHADOW : STONE_BASE);
		stone = abs(across) < 1.0 && along < ht - 1.0 - bands ? STONE_SHADOW : stone;
		vec3 rgb = edge ? OUTLINE : (abs(across) > hl - 0.5 - bands ? band : stone);
		// White-hot as it forms.
		rgb = mix(rgb, BONE_LIGHT, clamp(1.0 - hammer * 1.6, 0.0, 1.0));
		colour = vec4(rgb, 1.0);
	} else {
		colour = vec4(band * near * (0.25 + hammer_glow) * glow_strength, 0.0);
	}
	COLOR = colour;
}
