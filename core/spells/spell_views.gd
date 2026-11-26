class_name SpellViews
extends Object
## What the builder, the HUD and the looks read of the runtime (core/spells/spells.gd): a staff
## compiled and shown (`compile_staff`, `staff_view`, `cast_tree`), a card's name, icon and numbers
## (`component_*`, `cards_of`), and every carrier card's look (`register_bodies`, `look_of`, a
## launch's body and light). Methods working on the runtime (`rt`), whose members hold all of it
## (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_profiles", &"_looks", &"_look_drawers"]

var rt: Runtime = null
var _profiles: Dictionary
var _looks: Dictionary
var _look_drawers: Dictionary


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## Publishes the infusion table (every infusion's colour by its look layer, `InfusionTable`) for the
## shaders, reads every carrier card's look once (`_looks`, for `look_of` and `look_shaders`) and hands each
## shot carrier card's own shader (LOOK_SHOT, LOOK_STILL) to the projectile manager now
## (`register_body`, with the mesh its shots are written as; a still one's look shape and clock with
## it, `_shape_body`), so it has its batches and is warmed before the first room, not first drawn
## in the middle of one. A launch numbers and shapes any it did not know too (`_body_of`). The other areas warm the shaders they draw themselves (`look_shaders`).
func register_bodies() -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var source: Node = rt.registry if rt.registry != null else rt.get_node_or_null("/root/Registry")
	if source == null or not source.has_method(&"get_all"):
		return
	# Every infusion's colour by its look layer, for the shaders that weave a look of several.
	InfusionTable.publish(InfusionTable.of_registry(source))
	for card: Resource in source.call(&"get_all", &"spells"):
		var carrier_card := card as CarrierCard
		if carrier_card == null:
			continue
		var mesh: int = _shot_mesh(_remember_look(carrier_card))
		if carrier_card.look_shader != null and mesh != Runtime.NO_SHOT_MESH and projectiles != null:
			_shape_body(projectiles.register_body(carrier_card.look_shader, mesh), carrier_card.id, mesh)


## The carrier card `carrier_card`'s look as the area `drawer` (Carrier.LOOK_*: Feel's beams or swing
## trails, Entities' orbs) draws it: its own shader and light (`CarrierCard.look_shader`,
## `look_light_intensity`, `look_light_reach`), or `CardLook.PLAIN` when its carrier is drawn by
## another area (a bolt's zap is a beam, but a bolt's shader draws heads) and for an id that is no
## carrier card (a chain's jump). So no area reads the card (docs/milestones/card-looks.md). Shared
## and read only; allocates nothing once the card was read.
func look_of(carrier_card: StringName, drawer: int) -> CardLook:
	if not _looks.has(carrier_card) and not _read_look(carrier_card):
		return CardLook.PLAIN
	return _looks[carrier_card] as CardLook if int(_look_drawers[carrier_card]) == drawer else CardLook.PLAIN


## Every carrier card's own shader the area `drawer` draws (Carrier.LOOK_*), so that area warms them
## before the first room (`ShaderWarmup.want`, as it draws them). A new array each call: once, at
## start.
func look_shaders(drawer: int) -> Array[Shader]:
	var found: Array[Shader] = []
	var source: Node = rt.registry if rt.registry != null else rt.get_node_or_null("/root/Registry")
	if source == null or not source.has_method(&"get_all"):
		return found
	for card: Resource in source.call(&"get_all", &"spells"):
		var carrier_card := card as CarrierCard
		if carrier_card != null and carrier_card.look_shader != null and _remember_look(carrier_card) == drawer and not found.has(carrier_card.look_shader):
			found.append(carrier_card.look_shader)
	return found


## Every still carrier card whose shots give off motes while they stand (`CarrierCard.look_motes`,
## drawn by a shader of its own), by id, for Feel to give them off (`gameplay/feel/still_motes.gd`,
## which asks `look_of(carrier card, Carrier.LOOK_STILL)` for them). A new array each call: once, at start.
func still_mote_cards() -> Array[StringName]:
	var found: Array[StringName] = []
	var source: Node = rt.registry if rt.registry != null else rt.get_node_or_null("/root/Registry")
	if source == null or not source.has_method(&"get_all"):
		return found
	for card: Resource in source.call(&"get_all", &"spells"):
		var carrier_card := card as CarrierCard
		if carrier_card != null and carrier_card.look_shader != null and not carrier_card.look_motes.is_empty() and _remember_look(carrier_card) == Carrier.LOOK_STILL:
			found.append(carrier_card.id)
	return found


## Reads the card `carrier_card` into `_looks`: false when there is no such carrier card (not kept, so a
## card the registry has not scanned yet is read once it has).
func _read_look(carrier_card: StringName) -> bool:
	var source: Node = rt.registry if rt.registry != null else rt.get_node_or_null("/root/Registry")
	if carrier_card == &"" or source == null or not source.has_method(&"get_resource"):
		return false
	var card := source.call(&"get_resource", &"spells", carrier_card) as CarrierCard
	if card == null:
		return false
	_remember_look(card)
	return true


## Keeps `card`'s look in `_looks` (once) and returns the area that draws its carrier.
func _remember_look(card: CarrierCard) -> int:
	if not _looks.has(card.id):
		_looks[card.id] = CardLook.from_card(card)
		_look_drawers[card.id] = Carriers.of(card.carrier).look_drawer()
	return int(_look_drawers[card.id])


## `spell`'s launch look, in `_launch_look`: its core, look kinds, card, card body (numbered by the
## projectile manager with the mesh its shots are written as) and light.
func _launch_look_of(spell: CompiledSpell) -> LaunchLook:
	var mesh: int = _shot_mesh(spell.look_drawer)
	rt._launch_look.core = spell.tint
	rt._launch_look.look = spell.look
	rt._launch_look.carrier_card = spell.carrier_card_id
	rt._launch_look.body = _body_of(spell.carrier_card_id, spell.look_shader, mesh) if mesh != Runtime.NO_SHOT_MESH else 0
	rt._launch_look.light_intensity = spell.look_light_intensity
	rt._launch_look.light_reach = spell.look_light_reach
	return rt._launch_look


## The card body the carrier card `carrier_card`'s shots are drawn by (its `shader` under `mesh`), numbered
## the first time (`register_body`) and shaped as it is (`_shape_body`): a launch may be the first to
## ask for a card the start did not know. Only a look up once numbered, so a launch costs no more.
func _body_of(carrier_card: StringName, shader: Shader, mesh: int) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var body: int = projectiles.body_of(shader, mesh)
	if body == 0 and shader != null:
		body = projectiles.register_body(shader, mesh)
		_shape_body(body, carrier_card, mesh)
	return body


## Hands a still card's look shape and clock (its `CardLook`: `look_shape`, `look_open`,
## `look_fade`) to the manager for its body `body` (`set_body_shape`), and whether it lies on the
## floor and merges (`set_body_ground`), so its shader draws by the
## numbers its motes leave by (`gameplay/feel/still_motes.gd` reads the same `CardLook`). Every place
## a body is numbered shapes it here. A head body (`mesh` MESH_HEAD) has no still look.
func _shape_body(body: int, carrier_card: StringName, mesh: int) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if body <= 0 or mesh != Runtime.ProjectilesScript.MESH_QUAD or not _looks.has(carrier_card):
		return
	var look: CardLook = _looks[carrier_card]
	projectiles.set_body_shape(body, look.shape, Vector2(look.open, look.fade))
	projectiles.set_body_ground(body, look.on_floor, look.merges)


## The projectile manager's mesh (`MESH_HEAD` or `MESH_QUAD`) the shots of a carrier drawn by
## `drawer` (`Carrier.LOOK_*`) are written as, or NO_SHOT_MESH for one the manager does not draw.
static func _shot_mesh(drawer: int) -> int:
	if drawer == Carrier.LOOK_SHOT:
		return Runtime.ProjectilesScript.MESH_HEAD
	if drawer == Carrier.LOOK_STILL:
		return Runtime.ProjectilesScript.MESH_QUAD
	return Runtime.NO_SHOT_MESH


## True when the card `card_id` does something on the carrier `carrier` (`CarrierCard.carrier`) on its
## own: for the builder, a reward screen or a bot, before the card is placed
## (`StaffCompiler.card_works`). False for an unknown card.
func card_works(card_id: StringName, carrier: StringName) -> bool:
	var card: SpellComponent = _component(card_id)
	return card != null and StaffCompiler.card_works(card, carrier)


## Compiles a staff's cards (ids by slot, `&""` for an empty slot) into its cycle, the casts it
## makes until its cycle ends (staffs A4; the rules are docs/milestones/M2-staffs.md, "Reading a
## staff", and `StaffCompiler`). It never errors and refuses nothing: an unknown or useless
## card is listed in `wasted`. `spell_scale` is the casting body's (boss plan OB7, its `Stats`):
## × every spell's size (`Carrier.scale_size`), 1 as the cards say. `slots`: the slots it reads (-1:
## the staff's own; an elite's first staff has one more, connected biomes CB11).
func compile_staff(cards: Array[StringName], staff: StaffBase, spell_scale: float = 1.0, slots: int = -1) -> CompiledStaff:
	return StaffCompiler.new(_component).compile(cards, staff, spell_scale, slots)


## What the builder shows of a staff, as plain values so that nothing outside `core/spells`
## reads a compiled staff: `empty`; `cards` (the card ids by slot, `&""` for an empty slot); `casts`, one Dictionary per cast of the cycle with `slots`
## (read order), `text`, `mana`, `wind_up` (the seconds it winds up before it leaves), `wind_down` (the seconds its staff is busy after it), `delay` (the wait in all: the wind-down, and the staff's cooldown when the cycle ends with it), `damage` (each carrier's hit times its shots and the group's repeats, payloads left out), `ends_cycle`, `wrapped`, `targets` (card slot -> the
## carrier's slot) and `wasted` (slot ->
## true), and `tree` (the cast as the builder's tree draws it, `cast_tree`); `wasted` for the
## staff (cards that did nothing in any cast that read them); `name`, the staff's name shown (`StaffBase.display_name`, "" for none; items I3: the builder names a staff in the bag by it); and `staff`, the StaffBase given, only to hand back to `staff_view` for a preview of other cards
## (the radial builder shows what a card would change before it is put in).
func staff_view(cards: Array[StringName], staff: StaffBase) -> Dictionary:
	var compiled: CompiledStaff = rt.compile_staff(cards, staff)
	var casts: Array[Dictionary] = []
	for cast in compiled.casts:
		casts.append({
			"slots": cast.slots, "text": cast.description, "mana": cast.mana, "wind_up": cast.wind_up, "wind_down": cast.wind_down, "delay": cast.delay,
			"damage": _cast_damage(cast),
			"ends_cycle": cast.ends_cycle, "wrapped": cast.wrapped,
			"targets": cast.targets.duplicate(), "wasted": cast.wasted.duplicate(),
			"tree": rt.cast_tree(cast),
		})
	var row: Array[StringName] = []
	row.assign(compiled.cards)
	return {"empty": compiled.is_empty(), "cards": row, "casts": casts, "wasted": compiled.wasted.duplicate(), "name": staff.display_name if staff != null else "", "staff": staff}


## The rows of one cast as the builder's tree draws them (docs/milestones/M2-builder-tree.md,
## part T3), depth first: a row per carrier and one per trigger that fires. Each row is plain
## values: `depth` (0 for the cast's own carriers, one more per payload level), `trigger` (the
## trigger card's slot, -1 for a carrier row), `slots` (the cards the row shows: a group's
## multicasts on its first carrier's row, then that carrier's own cards, `CompiledSpell.card_slots`;
## a trigger row shows the first carrier its payload fires) and `name` (the carrier's or the
## trigger card's display name). The cast's first row also has its `mana` and `damage`. A
## payload's further carriers (a multicast in it) are rows of their own at the payload's depth,
## with no trigger. A wasted trigger has no row.
func cast_tree(cast: CompiledCast) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if cast.group != null:
		_tree_group(cast.group, 0, -1, &"", rows)
	if not rows.is_empty():
		rows[0]["mana"] = cast.mana
		rows[0]["damage"] = _cast_damage(cast)
	return rows


## The rows of `group` at `depth`: its first carrier on the row of `trigger` (a slot, -1 for
## none, named `trigger_id`), its others on rows of their own; each carrier's triggers after it.
func _tree_group(group: CompiledGroup, depth: int, trigger: int, trigger_id: StringName, rows: Array[Dictionary]) -> void:
	for at in group.spells.size():
		var spell: CompiledSpell = group.spells[at]
		var slots := PackedInt32Array()
		if at == 0:
			slots.append_array(group.multicast_slots)
		slots.append_array(spell.card_slots)
		var by_trigger: bool = at == 0 and trigger >= 0
		var shown: String = rt.component_name(trigger_id) if by_trigger else _tree_carrier_name(spell)
		rows.append({"depth": depth, "trigger": trigger if by_trigger else -1, "slots": slots, "name": shown})
		# A trigger row's carrier keeps its own payloads one level further in.
		var inner: int = depth + 1
		for fires in spell.triggers:
			if fires.payload != null and not fires.payload.is_empty():
				_tree_group(fires.payload, inner, fires.slot, fires.id, rows)


func _tree_carrier_name(spell: CompiledSpell) -> String:
	return spell.carrier_card_name if spell.carrier_card_name != "" else String(spell.carrier_card_id)


## The damage one cast deals if every shot of it lands once (a beam: every hit of its life):
## each carrier's hit times its shots, times the group's repeats. Payloads are left out (they
## depend on what is hit), so it is the builder's "at least" number; to a tenth (an atom's 0.3).
## A mend's hit deals none (it heals only).
static func _cast_damage(cast: CompiledCast) -> float:
	if cast.group == null:
		return 0.0
	var total: float = 0.0
	for spell in cast.group.spells:
		var damage: float = spell.hit.damage if spell.hit != null else spell.damage
		total += damage * float(maxi(spell.shots, 1) * Carriers.of(spell.carrier).hits_per_target(spell.lifetime))
	return snappedf(total * float(maxi(cast.group.repeats, 1)), 0.1)


## What the builder shows of the component `id`: its name (the id when it has none, "" for
## an unknown id), its 16x16 icon (null when unknown) and its kind (`&"carrier"`, `&"element"`,
## `&"modifier"` or `&"trigger"`, `&""` when unknown). Scripts outside `core/` and
## `content/spells/` learn these here and never read the component's fields.
func component_name(id: StringName) -> String:
	var component: SpellComponent = _component(id)
	return _name_of(component) if component != null else ""


func component_icon(id: StringName) -> Texture2D:
	var component: SpellComponent = _component(id)
	return component.icon if component != null else null


## Card `id`'s 1x icon (`icon_small`, the HUD's small cells), null for none.
func component_icon_small(id: StringName) -> Texture2D:
	var component: SpellComponent = _component(id)
	return component.icon_small if component != null else null


## Card `id`'s icon for a cell `side` layout pixels across: its 1x icon in a cell too small for its
## 2x one (`IconDetail.fitting`).
func component_icon_for(id: StringName, side: float) -> Texture2D:
	var component: SpellComponent = _component(id)
	return IconDetail.fitting(component.icon, component.icon_small, side) if component != null else null


## The card's own numbers for the builder, as short lines of at most three (none for an unknown
## id): a carrier's damage (times its shots), mana and delay ("Dmg 3x8", "Mana 10", "Delay 1s");
## a modifier's changes ("Dmg x0.5", "Shots x3", "Homes in"); an element's status and how long it
## lasts ("Burn 3s"); when a trigger fires its payload ("On hit"); a multicast's draws.
func component_stats(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var component: SpellComponent = _component(id)
	if component is CarrierCard:
		var carrier_card: CarrierCard = component
		var hits: int = maxi(carrier_card.shots, 1) * Carriers.of(carrier_card.carrier).hits_per_target(carrier_card.lifetime)
		out.append("Dmg " + Runtime._short(carrier_card.base_damage) if hits <= 1 else "Dmg %sx%d" % [Runtime._short(carrier_card.base_damage), hits])
		out.append("Mana " + Runtime._short(carrier_card.mana_cost))
		out.append("Delay %ss" % Runtime._short(carrier_card.wind_down))
	elif component is ModifierBase:
		var modifier: ModifierBase = component
		var words: Dictionary = {
			ModifierBase.Behaviour.HOMING: "Homes in", ModifierBase.Behaviour.CHAIN: "Chains %s",
			ModifierBase.Behaviour.SHIELD: "Blocks %s", ModifierBase.Behaviour.BOUNCE: "Bounces %s",
			ModifierBase.Behaviour.BARRIER: "Barrier %s",
		}
		if words.has(modifier.behaviour):
			var word: String = words[modifier.behaviour]
			out.append(word % Runtime._short(modifier.behaviour_strength) if word.contains("%s") else word)
		elif modifier.behaviour != ModifierBase.Behaviour.NONE:
			out.append(String(ModifierBase.Behaviour.keys()[modifier.behaviour]).capitalize())
		if modifier.extra_pierce != 0:
			out.append("Pierce +%d" % modifier.extra_pierce)
		var mults: Array = [
			["Dmg", modifier.damage_mult], ["Mana", modifier.mana_mult], ["Shots", float(modifier.shot_mult)],
			["Wind-up", modifier.wind_up_mult], ["Delay", modifier.wind_down_mult], ["Speed", modifier.speed_mult], ["Size", modifier.radius_mult],
			["Spread", modifier.spread_mult], ["Reach", modifier.reach_mult],
		]
		for pair: Array in mults:
			if not is_equal_approx(float(pair[1]), 1.0):
				out.append("%s x%s" % [pair[0], Runtime._short(float(pair[1]))])
		if not is_zero_approx(modifier.wind_down_add):
			out.append("Delay %s%ss" % ["+" if modifier.wind_down_add > 0.0 else "", Runtime._short(modifier.wind_down_add)])
		if modifier.lifetime_most > 0.0:
			out.append("Life %ss at most" % Runtime._short(modifier.lifetime_most))
		if not is_equal_approx(modifier.speed_start, 1.0) or not is_equal_approx(modifier.speed_end, 1.0):
			out.append("Speed x%s to x%s" % [Runtime._short(modifier.speed_start), Runtime._short(modifier.speed_end)])
		if not is_equal_approx(modifier.move_start, 1.0) or not is_equal_approx(modifier.move_end, 1.0):
			out.append("Move x%s to x%s" % [Runtime._short(modifier.move_start), Runtime._short(modifier.move_end)])
	elif component is ElementBase:
		var element: ElementBase = component
		if element.status_id != &"":
			out.append("%s %ss" % [String(element.status_id).capitalize(), Runtime._short(element.status_duration)])
		if element.heals:
			out.append("Heals all it hits")
		if not is_equal_approx(element.damage_scale, 1.0):
			out.append("Dmg x" + Runtime._short(element.damage_scale))
	elif component is TriggerBase:
		var trigger: TriggerBase = component
		if trigger.event == TriggerBase.Event.TIMER:
			out.append("Every %ss" % Runtime._short(trigger.wind_up))
		else:
			out.append("On " + String(TriggerBase.Event.keys()[trigger.event]).to_lower().replace("_", " "))
	elif component is MulticastBase:
		var multicast: MulticastBase = component
		if multicast.extra_draws > 0:
			out.append("+%d carriers" % multicast.extra_draws)
		if multicast.repeats > 1:
			out.append("%d times" % multicast.repeats)
		if multicast.mana_cost > 0.0:
			out.append("Mana " + Runtime._short(multicast.mana_cost))
	if out.size() > 3:
		out.resize(3)
	return out


## The one-line description of the component `id` for the builder, from the card itself
## (`SpellComponent.description`). Empty for an unknown id or a card without one; the builder
## shows nothing for an empty one.
func component_description(id: StringName) -> String:
	var component: SpellComponent = _component(id)
	return component.description if component != null else ""


func component_kind(id: StringName) -> StringName:
	var component: SpellComponent = _component(id)
	return component.kind() if component != null else &""


## The cards of the spell registered under `tag`, as plain ids: its carrier card, then its infusions and its
## modifiers in slot order, each once (empty when its generation is gone). For looks only:
## gameplay/feel's motes and marks by card (docs/milestones/spell-spectacle-2.md, S2).
func cards_of(tag: int) -> Array[StringName]:
	var cards: Array[StringName] = []
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return cards
	if spell.carrier_card_id != &"":
		cards.append(spell.carrier_card_id)
	for id in spell.element_ids + spell.modifier_ids:
		if id != &"" and not cards.has(id):
			cards.append(id)
	return cards


func _component(id: StringName) -> SpellComponent:
	var source: Node = rt.registry if rt.registry != null else rt.get_node_or_null("/root/Registry")
	if source == null:
		return null
	return source.call("get_resource", &"spells", id) as SpellComponent


func _name_of(component: SpellComponent) -> String:
	return component.display_name if not component.display_name.is_empty() else String(component.id)
