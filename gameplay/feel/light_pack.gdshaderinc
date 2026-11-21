// SPDX-License-Identifier: GPL-3.0-or-later
// Numbers a pass at the light's resolution writes and its reader reads back (light_passes.gdshaderinc,
// gameplay/feel/light_passes.gd): the pass draws with `render_mode blend_disabled`, so they are written
// as they are, alpha too, into its 8-bit picture, and read back with `texelFetch`, exactly.
// - the light's factor (`light_pack_factor`: three numbers 0 to 2, 10 bits each: the high 8 in r, g, b,
//   the low 2 of each in a; 1.0 exact);
// - one number 0 to 1 (`light_pack_unit`: 16 bits, the high 8 in r, the low 8 in g).

// Three numbers 0 to 2 (the light's factor), 10 bits each: 1.0 is exact.
vec4 light_pack_factor(vec3 m) {
	ivec3 q = clamp(ivec3(round(m * 512.0)), ivec3(0), ivec3(1023));
	ivec3 high = q >> ivec3(2);
	ivec3 low = q & ivec3(3);
	return vec4(vec3(high) / 255.0, float(low.r + low.g * 4 + low.b * 16) / 255.0);
}

vec3 light_unpack_factor(vec4 t) {
	ivec4 b = ivec4(round(t * 255.0));
	ivec3 q = ivec3(b.r, b.g, b.b) * ivec3(4) + ivec3(b.a & 3, (b.a >> 2) & 3, (b.a >> 4) & 3);
	return vec3(q) / 512.0;
}

// One number 0 to 1, 16 bits.
vec4 light_pack_unit(float v) {
	int q = int(round(clamp(v, 0.0, 1.0) * 65535.0));
	return vec4(float(q >> 8) / 255.0, float(q & 255) / 255.0, 0.0, 1.0);
}

float light_unpack_unit(vec4 t) {
	ivec2 b = ivec2(round(t.rg * 255.0));
	return float(b.r * 256 + b.g) / 65535.0;
}
