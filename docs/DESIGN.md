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
| Staff | The player character is a living staff (the owner, 2026-10-28): a floating face and four personalities, one per staff button, each with its own head and face. Cosmetics only beyond that. |
| Staffs | Four per player, one per shoulder button (RB, RT, LB, LT; the face buttons work the menus). A staff is a row of slots; there is no separate attack or dodge, only what the player puts in their staffs. Staffs found later differ in slots, speed and recharge. |
| Spells | Cards placed in a staff in any order and read left to right: carriers (what leaves the caster), modifiers and infusions (change the next carrier, or the caster when none follows), multicast (more carriers per cast) and triggers (the next cast becomes the payload). Reading wraps around the staff. Every arrangement is legal and does something; there is no complexity budget. |
| Relics | Passives found in runs, some altering how cards behave. |

Starting cards: carriers (bolt, beam, nova, rune, orbit, dash, teleport, hook, swap, wall, rain, fissure, decoy, familiar), modifiers (split, pierce, homing, chain, bigger, faster, shield, blast, hold, recoil, bounce, echo, linger, heavy, siphon, overcharge, sticky, magnet, ghost, spiral, mirror, growth, relay, sniper, return, slow, arc, possess), infusions (fire, frost, storm, void, lightning, mend), triggers (on hit, on expire, timer, on block, on kill, on cast, on wall, on hurt, on reaction), multicast (double, triple, scatter, burst).

Spell rules (chosen on 2026-10-26, the pivot at C2):

- **Everything hurts everything** (the owner, 2026-10-28): a spell hurts every body it hits, its caster's included. Players' spells hurt each other, and enemies' spells hurt enemies; there is no friendly-fire setting. Teams only decide whom things aim at (the AI, homing), never whom a hit hurts.
- **One mana pool per player**, shared by its staffs; sustained spells reserve part of it.
- **No build limits** beyond what the engine needs to run; limits are added only when measurements ask for them.
- **Small shots:** a shot is a small core; its cards add its look in layers.
- **Test builds are a sandbox:** preview builds start in a room with large staffs, every card and a training dummy.

## No-waiting co-op rules

1. No player controls another player's choices; there is no leader and no shared menu.
2. Menus are per-player (the builder) and never pause the game for others; only the pause menu does (rule 6).
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

Chosen on 2026-10-28 (docs/milestones/M2-living-staffs.md): every character is a living staff. A player is a floating staff that points where it aims, with cartoon floating eyes and brows drawn over its grip; its four staffs are four personalities, each with its own head and face, and the player's colour is only on the heads. Enemies are thrown-out staffs with glowing eyes and angry brows. The style N wizard of 2026-10-23 (a narrow dusk robe with a Spark placket, belt and hem, two big tall eyes and no mouth, under a big pointed hat) is now the villain. The rules and golden examples are in docs/STYLE.md and art/kit/golden.json. Spell shots are the one thing that glows (the owner, 2026-10-27): small white-hot cores, long cooling tails and a soft glow in their colour, drawn by the shot shader (docs/milestones/M2-staffs.md, "The look of a shot").
