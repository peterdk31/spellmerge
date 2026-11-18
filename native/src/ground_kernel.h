// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// A room's ground drawn when it is laid out (connected biomes CB4, docs/milestones/connected-biomes.md):
// the floor, the rock face, the glow, the walls' art and the edges' mote lines from the room's shape,
// mirrored or not. It stands for `GroundDrawing.draw` (gameplay/feel/ground/ground_drawing.gd, the
// twin of tools/ground_shape.py), line by line, to the bit; MoteKernel binds it as `draw_ground`
// (the view's kernel: a class of its own needs the owner's list of native classes). A pure function
// of the dictionary it is handed (`GroundShape.spec`): it keeps nothing. View only, so it keeps
// `std::` maths, as MoteKernel does; tests/gameplay/feel/test_ground_drawing.gd compares it with the
// GDScript byte for byte.

#pragma once

#include <godot_cpp/variant/dictionary.hpp>

namespace godot {
namespace ground {

// `GroundDrawing.draw(spec)`.
Dictionary draw(const Dictionary &spec);

} // namespace ground
} // namespace godot
