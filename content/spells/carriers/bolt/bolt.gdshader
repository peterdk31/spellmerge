// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A bolt in flight (content/spells/carriers/bolt/: its card's own look, `CarrierCard.look_shader`;
// docs/milestones/card-looks.md): the plain shot head (`core/projectiles/shot_head.gdshader`: read it
// for the instance, the quad kinds and why the fragment stage stays small), drawn by its include, so
// every fix to the head reaches the bolt, with the bolt's own core: a cut gem, a diamond of facets lit
// from the top-left (its body measured corner to corner, `HEAD_BODY`), with a `x` of rays out of its
// sides a pixel more each way a zoom, where the plain head is a round bead with a `+`. Drawn at the
// art's detail as the head is (ART2). Drawn by its card's pair of head batches
// (`ProjectileManager.register_body(shader, MESH_HEAD)`), warmed before the first room.
// To give the bolt a look of its own past its core, replace the include with a copy of it.

// The bolt's core: a diamond body (`HEAD_BODY`) and diagonal rays (`HEAD_RAY`) past it.
#define HEAD_BODY(q) (abs(q.x) + abs(q.y))
#define HEAD_RAY(a, r, reach) (a.x == a.y && a.x + a.y > r && a.x <= reach * 0.75)

#include "res://core/projectiles/shot_head.gdshaderinc"
