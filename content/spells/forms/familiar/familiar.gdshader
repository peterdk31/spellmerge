// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A familiar card's own look (content/spells/forms/familiar/: `FormBase.look_shader`;
// docs/milestones/card-looks.md): for now the plain orbit shot (`core/projectiles/shot_orbit.gdshader`,
// the fallback), drawn by its include, so every fix to it reaches the familiar. To give the familiar
// a look of its own, replace the include with a copy of it and change that. Entities draws every
// familiar's orb with it; warmed as a batch before the first room.

#include "res://core/projectiles/shot_orbit.gdshaderinc"
