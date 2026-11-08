// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A wizard's staff turning into a hammer (a slam's staff animation, its `hammer` channel; the owner,
// 2026-11-08: "make slam morph the staff into a hammer"). The staff's body drawn as the shots'
// sprite shader draws it (a copy of `shot_sprite.gdshader`'s fragment: its glow and all; keep the
// two alike, as Godot cannot hand TEXTURE to an included function), and over its head a
// hammer's head grows out of it: a block of stone across the staff at its tip, outlined, its
// striking face light and its back in shadow, its two ends bound in the glow's colour. As `hammer` rises from 0
// to 1 its pixels come in from the middle out, white-hot at first; as it falls they go back.
//
// The sprite is a staff's head sheet (gameplay/player/staff_look.gd): frames `hammer_frame.x`
// pixels square, a column per direction (HAMMER_DIRECTIONS, clockwise from pointing right), the
// grip at (`hammer_frame.y`, `hammer_frame.z`) in each frame and its tip `hammer_frame.w` pixels
// from it along the column's direction (`StaffLook.hammer_frame`). The hammer is worked out in
// the frame's own pixels, so it turns, stretches and lands with the staff. Warmed as a sprite
// (RECT) before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"

// The colour the warm pixels take (alpha above 0 turns it on; alpha 0 keeps the sprite's own colours:
// a staff's body glowing with its animation, gameplay/player/staff_look.gd).
uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour: the tint and the fade of a lone Sprite2D.
uniform vec4 body_tint = vec4(1.0);
// How bright the glow is (1.0 the look; 0.0 none).
uniform float glow_strength = 1.0;
// The dissolve (Feel's death, a wizard's dash afterimages): 0 whole, 1 gone. Its pixels turn
// `dissolve_color` (white-hot unless set) and fall out one by one.
uniform float dissolve = 0.0;
uniform vec4 dissolve_color = vec4(0.957, 0.945, 0.918, 1.0);
// The glow: light added round the sprite's own pixels (a combo mark, an afterimage), as bright
// as this; the sprite needs a few empty pixels round it to hold it. Its hue is `glow_color` when
// that has alpha above 0 (a staff's charge in its player's colour), else the tint's or the dissolve's.
uniform float sprite_glow = 0.0;
uniform vec4 glow_color = vec4(0.0);

varying flat vec4 body;
varying flat vec3 core;

void vertex() {
	body = COLOR * body_tint;
	core = core_override.a > 0.0 ? core_override.rgb : vec3(1.0);
}

const float HAMMER_DIRECTIONS = 16.0;
// The hammer's head: half as thick along the staff and half as long across it, in pixels, and
// how far in from the tip its middle is.
const float HALF_THICK = 4.0;
const float HALF_LONG = 7.5;
const float INSET = 3.0;

// How far the head has turned into the hammer's (0 the staff, 1 the hammer).
uniform float hammer = 0.0;
uniform vec4 hammer_frame = vec4(48.0, 24.0, 27.0, 16.0);

// The hammer's pixel at `p` (pixels from the grip in its frame) for a staff pointing along `dir`:
// its colour, or alpha 0; `near` how near its light reaches there.
vec4 hammer_pixel(vec2 p, vec2 dir, out float near) {
	vec2 across_dir = vec2(-dir.y, dir.x);
	float grow = clamp(hammer * 1.3, 0.0, 1.0);
	vec2 h = dir * (hammer_frame.w - INSET);
	vec2 d = p - h;
	float along = dot(d, dir);
	float across = dot(d, across_dir);
	float ht = HALF_THICK * max(grow, 0.3);
	float hl = HALF_LONG * grow;
	vec2 box = vec2(abs(along) - ht, abs(across) - hl);
	near = falloff(length(max(box, vec2(0.0))), 6.0) * hammer;
	bool inside = box.x <= 0.5 && box.y <= 0.5 && !(box.x > -0.5 && box.y > -0.5);
	// Its pixels come in from the middle out as it grows, and go back the same way.
	float out_from = length(d) / (HALF_LONG + 1.0);
	bool come = hash_seeded(floor(p.x), floor(p.y), 91.0, 0.0) < hammer * 1.8 - out_from * 0.8;
	if (!inside || !come || hl < 0.5) {
		return vec4(0.0);
	}
	bool edge = box.x > -0.5 || box.y > -0.5;
	// Its striking face (toward the tip) light, its back in shadow, and its two ends bound in the
	// glow's colour.
	vec3 stone = along > ht - 1.5 ? STONE_LIGHT : (along < -ht + 1.5 ? STONE_SHADOW : STONE_BASE);
	vec3 band = glow_color.a > 0.0 ? glow_color.rgb : BONE_LIGHT;
	vec3 rgb = edge ? OUTLINE : (abs(across) > hl - 1.5 ? band : stone);
	// White-hot as it forms.
	rgb = mix(rgb, BONE_LIGHT, clamp(1.0 - hammer * 1.6, 0.0, 1.0));
	return vec4(rgb, 1.0);
}

void fragment() {
	// The sprite, as `shot_sprite.gdshader` draws it.
	vec4 colour = vec4(0.0);
	vec4 t = texture(TEXTURE, UV);
	vec3 rgb = t.rgb * body.rgb;
	float warm = core_override.a > 0.0 ? smoothstep(0.1, 0.25, t.r - t.b) : 0.0;
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	float shade = clamp((lum - 0.5) / 0.45, 0.0, 1.0);
	vec3 lit = mix(core * 0.55, mix(core, vec3(1.0), 0.55), shade);
	float alpha = t.a * body.a;
	vec3 shown = mix(rgb, lit, warm);
	if (dissolve > 0.0) {
		vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
		if (t.a > 0.5 && hash_seeded(px.x, px.y, 81.0, 0.0) < dissolve * 1.2 - 0.1) {
			alpha = 0.0;
		} else if (t.a > 0.5) {
			shown = mix(shown, dissolve_color.rgb, min(dissolve * 3.0, 1.0));
			alpha = 1.0;
		}
	}
	if (alpha < 0.5 && sprite_glow > 0.0) {
		// The glow: how much of the sprite is near, 2 and 4 pixels away in eight directions.
		float near = 0.0;
		for (int k = 0; k < 8; k++) {
			vec2 dir = vec2(cos(float(k) * 0.7854), sin(float(k) * 0.7854)) * TEXTURE_PIXEL_SIZE;
			near += texture(TEXTURE, UV + dir * 2.0).a * 0.09 + texture(TEXTURE, UV + dir * 4.0).a * 0.035;
		}
		vec3 hue = glow_color.a > 0.0 ? glow_color.rgb : (dissolve > 0.0 ? dissolve_color.rgb : body.rgb);
		colour = vec4(hue * near * sprite_glow * (1.0 - dissolve) * glow_strength, 0.0);
	} else {
		// Premultiplied, as the blend mode wants.
		colour = vec4(shown * alpha, alpha);
	}
	if (hammer > 0.0) {
		vec2 px = UV / TEXTURE_PIXEL_SIZE;
		float frame = hammer_frame.x;
		float column = floor(px.x / frame);
		vec2 p = floor(mod(px, vec2(frame))) + 0.5 - hammer_frame.yz;
		float a = mod(column, HAMMER_DIRECTIONS) * 6.2831853 / HAMMER_DIRECTIONS;
		float near = 0.0;
		vec4 head = hammer_pixel(p, vec2(cos(a), sin(a)), near);
		if (head.a > 0.0) {
			colour = head;
		} else if (colour.a < 0.5) {
			// Its light round it, in the glow's colour.
			vec3 hue = glow_color.a > 0.0 ? glow_color.rgb : BONE_LIGHT;
			colour.rgb += hue * near * max(sprite_glow, 0.4) * 0.5 * glow_strength;
		}
	}
	COLOR = colour;
}
