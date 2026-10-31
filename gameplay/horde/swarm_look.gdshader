shader_type canvas_item;
// The swarm's look (gameplay/horde/swarm_look.gd; docs/milestones/horde-swarm.md, "The idea"):
// one swarmer of one kind per instance, drawn exactly as the nodes of a full enemy of that kind
// are (its "Sprite", then its Face's eyes and brows). The mesh is three quads in that order, so
// each swarmer is drawn whole before the next, as the actors are; each quad says in its UV which
// layer it is (x: corner + 2 x layer) and its corner. No number of the look is here: every size,
// origin and place is a uniform set from the scene and the scripts' constants (Face, Feel).
//
// Per instance: the transform puts it at the swarmer's place; COLOR is (the hop's lift in px,
// Feel's squash, the eyes' column, the brows' column + 8 while Feel's flash shows + 16 while the
// hurt pose shows); CUSTOM is where the eye layer and the brow layer sit (px, the Face's space).

// The body: the idle frame's place and size in TEXTURE, and the hurt pose's in `hurt_sheet`.
uniform vec2 body_size;
uniform vec2 body_region;
uniform vec2 body_texture_size;
uniform sampler2D hurt_sheet : filter_nearest;
uniform vec2 hurt_region;
uniform vec2 hurt_texture_size;
// The Sprite node: its place, its rest scale, and its offset with the centring in it.
uniform vec2 sprite_position;
uniform vec2 sprite_scale = vec2(1.0);
uniform vec2 sprite_offset;
// The Face node's place, its sheets, a frame of them, where in a frame each layer's anchor is,
// the rows this kind draws and its eyes' tint.
uniform vec2 face_position;
uniform sampler2D eyes_sheet : filter_nearest;
uniform sampler2D brows_sheet : filter_nearest;
uniform vec2 eyes_sheet_size;
uniform vec2 brows_sheet_size;
uniform vec2 frame_size;
uniform vec2 eyes_origin;
uniform vec2 brows_origin;
uniform float eyes_row;
uniform float brows_row;
uniform vec4 glow = vec4(1.0);

varying flat int layer;
varying flat float flash;
varying flat float hurt;
varying vec2 sheet_uv;

void vertex() {
	float which = floor(UV.x * 0.5);
	vec2 corner = vec2(UV.x - 2.0 * which, UV.y);
	layer = int(which);
	float packed = COLOR.a;
	hurt = step(16.0, packed);
	packed -= 16.0 * hurt;
	flash = step(8.0, packed);
	float brow_column = packed - 8.0 * flash;
	if (layer == 0) {
		float squash = COLOR.g;
		vec2 scale = sprite_scale * vec2(1.0 + squash, 1.0 - squash);
		VERTEX = sprite_position + (sprite_offset + vec2(0.0, COLOR.r) + corner * body_size) * scale;
		vec2 region = mix(body_region, hurt_region, hurt);
		vec2 size = mix(body_texture_size, hurt_texture_size, hurt);
		sheet_uv = (region + corner * body_size) / size;
	} else if (layer == 1) {
		VERTEX = face_position + INSTANCE_CUSTOM.xy - eyes_origin + corner * frame_size;
		sheet_uv = (vec2(COLOR.b, eyes_row) + corner) * frame_size / eyes_sheet_size;
	} else {
		VERTEX = face_position + INSTANCE_CUSTOM.zw - brows_origin + corner * frame_size;
		sheet_uv = (vec2(brow_column, brows_row) + corner) * frame_size / brows_sheet_size;
	}
}

void fragment() {
	vec4 colour;
	if (layer == 0) {
		colour = hurt > 0.5 ? texture(hurt_sheet, sheet_uv) : texture(TEXTURE, sheet_uv);
		// Feel's hit flash (hit_flash.gdshader): the body's shape in plain white.
		colour.rgb = mix(colour.rgb, vec3(1.0), flash);
	} else if (layer == 1) {
		colour = texture(eyes_sheet, sheet_uv) * glow;
	} else {
		colour = texture(brows_sheet, sheet_uv);
	}
	COLOR = colour;
}
