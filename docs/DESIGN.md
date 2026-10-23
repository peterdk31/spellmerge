# Spellmerge design

The vision and pillars. **Owner-only:** only peterdk31 changes this file. Claude checks every milestone design, task and PR against it; anything that contradicts it is out. Drawn from docs/PLAN.md ("Game design" and "Quality bar").

## The game

Spellmerge is a 2D top-down action roguelite for 1–4 local co-op players, where the build comes from spells you assemble mid-run, in the spirit of Noita's wands and Ember Knights' co-op.

*Merge spells. Cause chaos. Together.*

## Pillars

1. **Deep spell building:** few components, many combinations.
2. **Nobody waits for anybody:** 1–4 players act independently at all times.
3. **A mix of tones:** a self-aware, slightly comic magic world with real stakes.
4. **Readable chaos:** 32×32 pixel art, clear telegraphs, player colours.

## Build elements

| Element | Role |
| --- | --- |
| Wizard | One base character; cosmetics only (hat, robe, colours, staff look). |
| Staff | Chosen before a run; sets the basic attack and a small bonus. |
| Spells | Built from form → element → modifiers → trigger; a trigger holds another spell. Limited by a complexity budget. |
| Relics | Passives found in runs, some altering how components behave. |

Starting components: forms (bolt, beam, nova, rune, orbit), elements (fire, frost, storm, void), modifiers (split, pierce, homing, chain, bigger, faster), triggers (on hit, on expire, timer).

## No-waiting co-op rules

1. No player controls another player's choices; there is no leader and no shared menu.
2. Menus are per-player overlays and never pause the game for others.
3. Rewards are rolled per player.
4. Unpicked rewards carry over as an unspent icon.
5. Shared decisions are made by walking (the door rule).
6. Only the real pause menu stops the game, and any player can open it.

## What makes it fun

- **Game feel from day 1:** every hit has hit-stop, screen shake, knockback, particles and sound.
- **Meaningful choices:** every reward offers 3 options with trade-offs.
- **Surprising combos:** components interact across systems; every new component needs at least 2 interesting interactions.
- **Growing power fantasy:** weak at the start, overpowered by the end.
- **Short loops:** runs of 20–30 minutes, under 3 seconds from death to a new run.
- **Fair difficulty:** every attack is telegraphed and every death is understandable.
- **Discovery:** a codex of found combos, secret interactions, unlocks through play.

Real player feedback outranks Claude's own judgement, and the owner's weekly playtest is the highest-priority input on feel, fun and direction.

## Quality

Professional-looking, very few bugs, genuinely good art, music and gameplay. Quality beats speed everywhere; cut scope, never quality; work that is only "OK" isn't done. Small and excellent beats big and mediocre.

## Art direction (locked)

Chosen on 2026-10-23: style N, a narrow dusk (Stone) robe with a Spark placket, belt and hem, two big tall eyes and no mouth, under a big pointed hat in the player's colour (the only player colour on the wizard). The rules and golden examples are in docs/STYLE.md and art/kit/golden.json.
