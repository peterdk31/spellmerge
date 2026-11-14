extends RefCounted
## The kinds of card as the HUD shows them (items I7: the builder and the inventory group their
## cards alike): the kinds in ring order, the word each is called by and its colour (docs/STYLE.md:
## none near a player colour). Plain data; which kind a card is is `Spells.component_kind`'s.

const KINDS: Array[StringName] = [&"carrier", &"modifier", &"element", &"trigger", &"multicast"]
const WORDS: Dictionary = {
	&"carrier": "Carrier", &"modifier": "Modifier", &"element": "Infusion", &"trigger": "Trigger", &"multicast": "Multicast",
}
const COLORS: Dictionary = {
	&"carrier": Color("#ffa23c"), &"modifier": Color("#4fd6dc"), &"element": Color("#b4e82a"),
	&"trigger": Color("#e08ad8"), &"multicast": Color("#d4d0e0"),
}
