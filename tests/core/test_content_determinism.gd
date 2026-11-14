extends "res://tests/support/suite.gd"
## New content is covered by itself (online-ready N12, docs/milestones/online-ready.md): every card,
## every enemy (and boss) and every premade item (items I6) the registry finds plays a short scripted fight
## (tests/core/content_fight.gd) twice, and through a snapshot taken after a tick of its own
## (between SNAPSHOT_FROM and SNAPSHOT_TO, by its id, so a failure plays again the same): both
## times agree at every tick, and the fight restored from the snapshot into a fresh world agrees
## with the first from the next tick on. When they part, the desync report names the first tick,
## the areas and each member. A card that never casts in its fight fails too, so no card passes by
## doing nothing.
##
## It keeps no list: a card or enemy is covered the day its folder lands, with no test written for
## it (as tests/core/test_card_rules.gd plays every card on every carrier). The rooms are played on
## the real game, each by itself (tests/core/test_snapshot_game.gd).
##
## The runner plays it in processes side by side (tests/support/suite.gd, "shards"):
# unit-test-shards: 14

const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## Ticks a fight runs (five seconds of game).
const TICKS: int = 300
## The earliest and the latest tick a fight's snapshot is taken after.
const SNAPSHOT_FROM: int = 30
const SNAPSHOT_TO: int = 240
## How many tests the cards are split into (see `_cards_part`).
const CARD_PARTS: int = 12

var _registry: RegistryScript


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


func test_it_finds_the_content_itself() -> void:
	check(_cards().size() >= 50, "it finds the cards (%d)" % _cards().size())
	check(_enemies().size() >= 5, "it finds the enemies (%d)" % _enemies().size())


## Items I6: every premade item (the hub's rack) lies by a wizard, who takes it and casts it.
func test_every_item_plays_the_same_twice_and_through_a_snapshot() -> void:
	check(_premade().size() >= 1, "it finds the premade items (%d)" % _premade().size())
	for item in _premade():
		_check(ContentFight.ITEM, item)


func test_every_enemy_plays_the_same_twice_and_through_a_snapshot() -> void:
	for enemy in _enemies():
		_check(ContentFight.ENEMY, enemy)


# The cards are played in CARD_PARTS tests, so the runner can play them side by side.
func test_every_card_plays_the_same_twice_and_through_a_snapshot_01() -> void:
	_cards_part(0)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_02() -> void:
	_cards_part(1)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_03() -> void:
	_cards_part(2)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_04() -> void:
	_cards_part(3)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_05() -> void:
	_cards_part(4)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_06() -> void:
	_cards_part(5)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_07() -> void:
	_cards_part(6)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_08() -> void:
	_cards_part(7)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_09() -> void:
	_cards_part(8)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_10() -> void:
	_cards_part(9)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_11() -> void:
	_cards_part(10)


func test_every_card_plays_the_same_twice_and_through_a_snapshot_12() -> void:
	_cards_part(11)


## The cards' part `part` (from 0) of CARD_PARTS: every CARD_PARTS-th card by id, from the
## `part`-th.
func _cards_part(part: int) -> void:
	var cards: Array[SpellComponent] = _cards()
	for i in cards.size():
		if i % CARD_PARTS == part:
			_check(ContentFight.CARD, cards[i])


## Every card in content/spells/, by id.
func _cards() -> Array[SpellComponent]:
	var out: Array[SpellComponent] = []
	for card: Resource in _registry.get_all(&"spells"):
		if card is SpellComponent:
			out.append(card as SpellComponent)
	return out


## Every premade item of every kind (`ItemKinds.premade_of`), by kind, folder and id.
func _premade() -> Array[Resource]:
	var out: Array[Resource] = []
	for kind: StringName in ItemKinds.kinds():
		for folder: StringName in ItemKinds.premade_of(kind):
			for item: Resource in _registry.get_all(folder):
				if ItemKinds.stack_of(item) != null:
					out.append(item)
	return out


## Every enemy and boss, by folder then id.
func _enemies() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for folder: StringName in [&"enemies", &"bosses"]:
		for data: Resource in _registry.get_all(folder):
			if data is EnemyBase and (data as EnemyBase).scene != null:
				out.append(data as EnemyBase)
	return out


## The tick `resource`'s fight is snapshotted after: its own, by its id.
static func _snapshot_tick(resource: Resource) -> int:
	return SNAPSHOT_FROM + posmod(hash(String(resource.get(&"id"))), SNAPSHOT_TO - SNAPSHOT_FROM)


## `resource`'s fight twice and through its snapshot; each parting is a failure with its report.
func _check(kind: StringName, resource: Resource) -> void:
	var label: String = "%s %s" % [kind, resource.get(&"id")]
	var at: int = _snapshot_tick(resource)
	var played: Array = _play(kind, resource, at)
	var first: Desync = played[0]
	var snapshot: Snapshot = played[1]
	if kind == ContentFight.CARD or kind == ContentFight.ITEM:
		check(int(played[2]) > 0, "%s: its player casts it" % label)
	for problem in snapshot.problems:
		check(false, "%s, its snapshot: %s" % [label, problem])
	var second: Desync = _play(kind, resource, at)[0]
	var tick: int = Desync.first_parting(first, second)
	if tick >= 0:
		check(false, "%s played twice: %s" % [label, Desync.compare(_play(kind, resource, at, tick)[0], _play(kind, resource, at, tick)[0])])
	var restored: Array = _resume(kind, resource, snapshot, at)
	for problem: String in restored[1]:
		check(false, "%s restored: %s" % [label, problem])
	var after := Desync.new()
	after.hashes = first.hashes.slice(at + 1)
	tick = Desync.first_parting(after, restored[0])
	if tick < 0:
		return
	var kept: Desync = _play(kind, resource, at, at + 1 + tick)[0]
	kept.hashes = kept.hashes.slice(at + 1)
	kept.keep_tick = tick
	check(false, "%s restored from tick %d parts %d ticks after: %s" % [label, at, tick + 1, Desync.compare(kept, _resume(kind, resource, snapshot, at, tick)[0])])


## `resource`'s fight from a fresh world: [its hashes (the leaves of tick `keep` kept), its
## snapshot after tick `at`, the player's casts of the content].
func _play(kind: StringName, resource: Resource, at: int, keep: int = -1) -> Array:
	var fight := ContentFight.new(root, kind, resource)
	var run := Desync.new(keep)
	var snapshot: Snapshot = null
	for i in TICKS:
		fight.step()
		run.capture(fight.areas())
		if i == at:
			snapshot = Snapshot.take(fight.areas(), fight.world)
	var casts: int = fight.item_casts if kind == ContentFight.ITEM else fight.wizard_casts
	fight.free_all()
	return [run, snapshot, casts]


## A fresh world of `resource`'s fight made as `snapshot` (taken after tick `at`) says, played on to
## TICKS: [its hashes from tick `at` + 1 (the leaves of the `keep`-th kept), the restore's problems].
func _resume(kind: StringName, resource: Resource, snapshot: Snapshot, at: int, keep: int = -1) -> Array:
	var fight := ContentFight.new(root, kind, resource)
	var problems: PackedStringArray = fight.restore(snapshot, at)
	var run := Desync.new(keep)
	for i in range(at + 1, TICKS):
		fight.step()
		run.capture(fight.areas())
	fight.free_all()
	return [run, problems]
