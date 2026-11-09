class_name MarkKind
extends Resource
## A kind of floor mark (docs/milestones/spell-spectacle.md, P2): a scorch, a crack, a frost
## rime that a cue stamps into the room's mark layer once and that stays until the room ends.
## One file per kind in `content/marks/<id>.tres`; the registry finds it by its `id`, so a new
## mark is a new file and no list is edited. A cue names it in a part
## (`{"part": "mark", "mark": "scorch", ...}`, core/base/cue_base.gd).
##
## A kind may belong to cards (`cards` by id, `look_ids` by look, like a `MoteKind`; a card a kind
## names by id takes no kind by its layer; spell-spectacle-2.md, S2): a cue's mark part with
## `"cards": true` stamps the marks of the cards it was played with instead of its own when they
## have one, so a frost blast leaves frost where a plain blast leaves a scorch.
##
## **No colours here** (STYLE.md: a mark is at most the shadow and base shades of its material):
## each of its two parts, the body and the edge, names where its colour comes from, the room's
## floor (`floor`: its own art's shades, `RoomBase.floor_colors`), what made it (`spell`: the
## shot's ramp, picked by the shot shaders' `look_of`; for a settled mote, the mote's own ramp,
## a spell's or a surface's) or the surface the cue is about (`surface`: a dying body's own art,
## else the room's walls; the ramp table's row, as the surface motes take it), and which shade
## (`base` or `shadow`). Pixels are hard: a mark has no partial alpha.
##
## **Its shape is worked out by `gameplay/feel/mark.gdshader`** from `form` and three numbers, at
## any size, one pixel a line however big (never a picture scaled up):
## - `blot`: a ragged patch (`rough` how ragged its rim), solid in its middle in the body colour
##   with pin-holes, its rim speckled in the edge colour (`fill` how thick the speckles).
## - `crack`: `lines` jagged lines out from a crushed middle, each forking once, one pixel wide
##   (`rough` how jagged), in the body colour; the crushed middle's specks in the edge colour.
## - `rime`: a ragged patch of film specks in the body colour, strewn with small crosses (crystals,
##   `fill` how many) in the edge colour.
## - `ring`: a ragged band round its rim in the body colour (`rough` how ragged), specks thrown
##   in and out of it in the edge colour (`fill` how many); its middle is untouched.
## - `rune`: a circle one pixel wide at its rim and one inside it, `lines` strokes between them
##   (each a tick with a hook), in the body colour; the inner circle's specks in the edge colour.
## - `speck`: one pixel at its middle in the body colour, whatever its radius (a settled mote).

## Unique name, also its file name.
@export var id: StringName = &""
## The cards (their ids) this kind is the mark of, for a part with `"cards": true`, whatever their
## look layer.
@export var cards: Array[StringName] = []
## The cards' looks (`look_id` of an element or modifier, `LookNames`) this kind is the mark of,
## for a part with `"cards": true` and the cards no kind names by id; empty for a mark that belongs
## to no card (a scorch, a crack).
@export var look_ids: Array[StringName] = []
## `look_ids` as their numbers, the LOOK_* kinds of core/projectiles: what Feel reads.
var look_layers: PackedInt32Array:
	get:
		return LookNames.layers_of(look_ids)
	set(value):
		look_ids = LookNames.names_of(value)
## How the shader draws it (see above).
@export_enum("blot", "crack", "rime", "ring", "rune", "speck") var form: String = "blot"
## How ragged its rim is (or how jagged its lines), 0 a clean circle.
@export_range(0.0, 1.0, 0.05) var rough: float = 0.4
## How thick the speckles of its rim (blot) or its crystals (rime) are.
@export_range(0.0, 1.0, 0.05) var fill: float = 0.5
## Lines out from the middle (crack), or strokes round it (rune).
@export_range(1, 8) var lines: int = 5

@export_group("Colours")
## Where the body's colour comes from, and which shade of it.
@export_enum("floor", "spell", "surface") var body_from: String = "floor"
@export_enum("base", "shadow") var body_shade: String = "shadow"
## Where the edge's colour comes from, and which shade of it.
@export_enum("floor", "spell", "surface") var edge_from: String = "spell"
@export_enum("base", "shadow") var edge_shade: String = "shadow"

## The forms, sources and shades as the shader is told them (their index).
const FORMS: Array[String] = ["blot", "crack", "rime", "ring", "rune", "speck"]
const SOURCES: Array[String] = ["floor", "spell", "surface"]
const SHADES: Array[String] = ["base", "shadow"]


func kind() -> StringName:
	return &"mark"


## What is wrong with this kind, in words; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("a mark kind needs an id")
	if not FORMS.has(form):
		found.append("%s: form '%s' is not one of %s" % [id, form, FORMS])
	for from: String in [body_from, edge_from]:
		if not SOURCES.has(from):
			found.append("%s: a colour comes from one of %s, not '%s'" % [id, SOURCES, from])
	for shade: String in [body_shade, edge_shade]:
		if not SHADES.has(shade):
			found.append("%s: a mark's shade is one of %s (STYLE.md), not '%s'" % [id, SHADES, shade])
	for look in look_ids:
		if not LookNames.known(look):
			found.append("%s: %s is not a look (%s)" % [id, look, ", ".join(LookNames.NAMES)])
	for card in cards:
		if card == &"":
			found.append("%s: a card it names has no id" % id)
	if lines < 1 or lines > 8:
		found.append("%s: a crack or a rune has 1 to 8 lines" % id)
	return found
