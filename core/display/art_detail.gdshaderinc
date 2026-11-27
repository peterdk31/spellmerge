// SPDX-License-Identifier: GPL-3.0-or-later
// The art's detail for shaders (ArtDetail.DETAIL, core/display/art_detail.gd; docs/STYLE.md, "The
// picture and the art's detail"): a shader drawing in the world works its shapes out at the middle
// of each art pixel, two a world pixel each way, so a curve, a diagonal and an edge step by the
// finer pixel while every shape keeps its world size. Included by the shot palette and by every
// room look worked out in a shader (the marks, the mist, the light, the tints, the bodies' shadows).
#ifndef ART_DETAIL_INC
#define ART_DETAIL_INC

const float ART_DETAIL = 2.0;

// The middle of the art pixel under `p` (world pixels): `floor(p) + 0.5` at the art's detail.
vec2 art_centre(vec2 p) {
	return (floor(p * ART_DETAIL) + 0.5) / ART_DETAIL;
}

#endif
