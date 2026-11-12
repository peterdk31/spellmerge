extends "res://tests/support/card_rig.gd"
## The Bolt card (content/spells/carriers/bolt/, M2 part 10): one shot that flies straight and hits, and ends after its lifetime.
##
## godot --headless --path . --script res://content/spells/carriers/bolt/test_bolt.gd


func test_the_card_is_a_bolt() -> void:
	_check_card(&"bolt", 1)
	check_equal(_form(&"bolt").carrier, &"atom", "bolt flies (a bigger atom)")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"bolt"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)


func test_the_bolt_is_one_shot_that_flies_straight_and_hits() -> void:
	var imp := _target(Vector2(100.0, 0.0))
	_target(Vector2(100.0, 60.0))
	var tag: int = _cast_form(&"bolt", 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 1, "one shot")
	_tick(30)
	check_equal(_hit_targets(), [imp] as Array, "it hit the imp in its way and not the one beside it")
	check_equal(_spells.hit_profile(tag).damage, _form(&"bolt").base_damage, "a bare bolt hits for its base damage")


func test_the_bolt_ends_after_its_lifetime() -> void:
	_cast_form(&"bolt", 0, Vector2.ZERO)
	_tick(ceili(_form(&"bolt").lifetime / DT) + 4)
	check_equal(_mgr.get_count(), 0, "the shot expired")


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: CarrierCard = load("res://content/spells/carriers/bolt/bolt.tres") as CarrierCard
	check_equal(card.impact_cue, &"impact", "its impact plays impact")


## Its own look (docs/milestones/card-looks.md, phase 1): a bolt's head is drawn by its folder's
## shader, in a pair of head batches of its own, so the atom and nova keep the plain head.
func test_it_is_drawn_by_its_own_head_shader() -> void:
	var card: CarrierCard = load("res://content/spells/carriers/bolt/bolt.tres") as CarrierCard
	check(card.look_shader == preload("res://content/spells/carriers/bolt/bolt.gdshader"), "drawn by its folder's shader")
	check(card.look_problems().is_empty(), "a canvas-item shader")
	var tag: int = _cast_form(&"bolt", 0, Vector2.ZERO)
	check(tag > 0, "cast")
	var slot: int = -1
	for s in _mgr.get_cap():
		if _mgr.is_alive(s):
			slot = s
	check(slot >= 0, "its shot flies")
	if slot < 0:
		return
	var body: int = _mgr._body[slot]
	check(body > 0 and _mgr.body_shader(body) == card.look_shader, "its shot carries its card's body")
	check_equal(_mgr.body_mesh(body), _mgr.MESH_HEAD, "a head body: its shots fly")
	check_equal(_mgr._batch_of(slot), _mgr.body_batch(body, not _mgr.is_hat_ramp(_mgr._ramp[slot])), "drawn in its body's batch")
	var atom: CarrierCard = load("res://content/spells/carriers/atom/atom.tres") as CarrierCard
	check(atom.look_shader == null, "the atom keeps the plain head")
