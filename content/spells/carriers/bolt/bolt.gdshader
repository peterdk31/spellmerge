// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A bolt in flight (content/spells/carriers/bolt/: its card's own look, `FormBase.look_shader`;
// docs/milestones/card-looks.md): the plain shot head (`core/projectiles/shot_head.gdshader`: read it
// for the instance, the quad kinds and why the fragment stage stays small), drawn by its include, so
// every fix to the head reaches the bolt, with the bolt's own core: a `x` of arms round its white-hot
// pixel, a pixel more each way a zoom, where the plain head has a `+`. Drawn by its card's pair of
// head batches (`ProjectileManager.register_body(shader, MESH_HEAD)`), warmed before the first room.
// To give the bolt a look of its own past its core, replace the include with a copy of it.

// The bolt's core: diagonal arms (`HEAD_ARM`), and the four pixels beside its heart between them
// (`HEAD_BETWEEN`, void's dark ring).
#define HEAD_ARM(a, arms) (a.x == a.y && a.x > 0.0 && a.x <= arms)
#define HEAD_BETWEEN(a) (a.x + a.y == 1.0)

#include "res://core/projectiles/shot_head.gdshaderinc"
