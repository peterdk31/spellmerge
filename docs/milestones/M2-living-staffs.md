# M2 rework: living staffs (the characters and the story)

**Goal:** every character is a living staff. A player is a thrown-out staff with a floating face and four personalities, one per staff button; the enemies are the other staffs the same wizard threw out; the wizard is the villain. One look covers everyone: a body, an eye layer and a brow layer.

**Status (2026-10-28):** designed with the owner in one session, from the owner's idea ("every character in the game being an alive staff"), through nine rounds of mockups; the owner's decisions are in "Owner decisions". Phase H of M2, after phase G (actors) and before D3, so C2's playtest is on the new characters. An owner exception like phases F and G (docs/ROADMAP.md).

**Why:** the owner wanted the wizard and the enemies reworked, and the living staff gives the game one idea for its characters, its controls and its story. It also lands well on phase G: an actor is a body plus a look, and here every body is a staff and every look is the same three layers.

**Done when:**

1. Every part in "Parts" is merged and `ci/build/build.sh --quick --tests` is green.
2. A player's character is the floating staff: it points where it aims, casts from the tip of the staff it is on, and swaps personality (head and face) in the poof when a different staff button is pressed, without delaying the cast.
3. Every enemy in `content/enemies/` is a stray: a staff body, glowing eyes and angry brows, and a staff of player cards.
4. The intro plays on a new save, skippable by any player, in under 15 seconds.
5. `docs/STORY.md`, `docs/STYLE.md` and the area READMEs describe the new characters; nothing in the game says "wizard" about a player.

## The story: thrown out

New canon (`docs/STORY.md`, changed in H1):

- **The wizard throws staffs away, just because: new is better.** The wizard drops the old staff down a hole in the tower floor on new-staff day, says "Oops.", and walks off. From the staff's point of view it was an accident. Obviously.
- **The players are thrown-out staffs** climbing back home, together. Several can be dropped on one day.
- **The strays are the wizard's earlier staffs,** all "accidentally" dropped, gone sour about it. They are not evil: territorial, bitter, and here first.
- **Bosses are powerful old staffs** with a grudge (the Old Broom, demoted to sweeping; the Walking Stick). **The final boss is the Favourite:** the wizard's current staff, polished and smug. **The final, final boss is the wizard,** who picks the Favourite up and casts with it. The reason for all the "accidents" is that there isn't one.
- **The ending (owner's choice, A):** beaten, the wizard picks your staff up, says "Huh. Still works.", and drops the Favourite down the hole. The credits roll over the Favourite falling. New is better; or is it?
- **A run that ends** is the staff landing at the bottom again (the thud). Relics are other things the wizard dropped down the hole.

Bosses, the Favourite, the wizard fight and the ending are M3+ content; phase H fixes only the canon and builds the intro.

## The player: one face, four personalities

- **The face is the character:** two floating eyes and two floating brows, drawn over the staff at the "Close" height (the owner, 2026-10-28): the eyes' top row sits 8 px above the grip, so face and staff read as one body.
- **The four staffs are four personalities,** one per button (RB, RT, LB, LT). Each has its own head and its own face style:

| Starter staff | Head | Personality | Eyes | Resting brows |
| --- | --- | --- | --- | --- |
| RB | **Curl:** a spiral 1¾ turns round a gem, gold collar | the Optimist | round, big pupils, looks around | neutral |
| RT | **Star:** an upright star (it does not turn with the staff) | the Show-off | round, sparkling | raised |
| LB | **Moon:** an upright crescent | the Dozer | heavy lids, pupils low | neutral |
| LT | **Crystal:** a claw holding a crystal that points along the aim | the Sergeant | narrow, slit pupils | angry |

- **What never changes:** the player colour on every head (gem, star, crescent, crystal) and the gold wrap on the grip. These say whose staff it is; the player colour stays the players' only (docs/STYLE.md).
- **A found staff brings its own head and personality.** `StaffBase` gains a look (head, tip length, face style, resting brows), so a new staff is a new silhouette, and a new staff is still data, not code.
- **It floats and points.** The staff hovers (no walk frames; a bob and a shadow), swings to point at the aim, and its shots leave from the tip of the head it is on (`tip` per head). Pointing up, the staff passes behind the face, so the eyes are never covered.
- **Downed:** it drops flat on the floor, eyes shut, brows worried; a friend stands it back up (the revive is unchanged).
- **The hurtbox is a circle over the face and the grip,** the size of today's wizard, not the thin staff: hits stay as fair as now.

### The poof: a personality swap

Pressing a staff button other than the one shown swaps the body in a very fast cloud:

- **0.18 s** in all; the body and face switch at 35%, when the cloud is biggest. Bone puffs swell and shrink along the staff, with a few sparks in the player colour. Drawn as a shot-shader effect kind (`KIND_POOF`), like every effect (the owner, 2026-10-27: one visual style).
- **The cast is never delayed:** the shot leaves on the press, from the new staff's tip; the cloud only hides the swap.
- **The same button again does nothing to the body,** so holding or tapping one staff never poofs.
- The brows lift for a quarter second as the new personality arrives.

## The face layers

One `Face` for every actor (players and strays), part of the look that G6 and G7 build:

- **Inputs:** a style (cheer, eager, sleepy, stern, stray), a mood (neutral, raised, angry, furious, worried), a look direction (one of nine: the aim for a player, the target for a stray) and the body's motion.
- **Brows carry the mood;** five shapes cover everything. Eyes carry the style and the look.
- **Follow-through:** the eyes lag the body by about a tenth of a second and the brows lag the eyes; on a cast the eyes pop up 2 px and the brows 1 px more. Offsets on two sprite layers, no extra frames.
- **Idle habits:** blinking, glancing and the odd raised brow, timed per actor and per style (the Dozer's lids droop; the Show-off fidgets).
- **Strays:** eyes glow in their element colour with a slit pupil; brows are always angry and drop to furious while the stray winds up a cast, a telegraph on the face as well as on the floor (the existing staff telegraph is unchanged).

## The strays

Each is a body sprite, an eye colour and a staff of player cards (phase F's rule, unchanged). Strays **hop** on their tips; players float, so the two sides read apart by motion alone.

| Stray | Replaces | Staff | Role |
| --- | --- | --- | --- |
| **Cinder Rod:** a charred rod with a burning crown | the ember imp | fire · bolt | shooter |
| **Splinter:** a broken-off end; one eye floats where the rest used to be | (new) | dash | swarmer, hurts by touch |
| **Rime Crook:** a crook with fangs, ice bands | (new) | frost · hook | puller |
| **Bone Scepter:** a skull on a stick; its eyes are sparks in the sockets | (new) | void · rain | zoner |
| **Storm Fork:** three prongs | (new) | triple · lightning · bolt | spreader |

The training and shooting dummies become staffs staked in the floor (their behaviour is unchanged). A stray whose cards are not built yet (rain, triple) waits for them.

## The intro

Played once per new save, skippable by any player, about 14.5 s (the owner's mockup):

1. "New staff day." The wizard walks in with the old staff (asleep) in one hand and the shiny new one in the other.
2. A glance left, a glance right, a whistle. Nobody is watching.
3. The old staff drops down a hole in the floor. "Oops." The wizard dusts off their hands ("Oh well.") and skips away.
4. **The fall:** the camera follows the staff down a long shaft, past strays' eyes watching from the walls. It wakes on the way down; its eyes trail above it.
5. **The thud:** a hard floor, a shake, dust, one bounce, dizzy stars.
6. "Thrown out? No. Dropped. By accident. Obviously." It rises and points up the shaft: "Home is up there."

With more than one player, the wizard drops one staff per player, faster each time ("Oops. Oops. Oops."). The wizard is drawn in the locked style N (the robe, the pointed hat, two eyes and no mouth): the old player art becomes the villain.

## Things that change for players

- The character is a floating staff that points at the aim; there is no walking animation.
- Which staff is live shows on the body, so teammates can read each other's buttons.
- Enemies are the strays above; the ember imp is the Cinder Rod.
- The intro on a new save.

## Performance

- **Body:** one sprite per player, its frame picked from a 16-direction sheet per head (48×48 frames); no runtime rotation.
- **Face:** two more sprites per actor (eyes, brows), their frames picked by style, mood and look; no per-frame allocations.
- **Poof:** one shot-shader effect per swap, from the existing effect pool.
- Measured with the stress run at the web cap after H5.

## Parts

### Phase H: living staffs (owner, 2026-10-28)

Owner sessions, one PR each, after phase G's G10 and before D3. H2 and H5 may run side by side once H3 has merged.

| # | Part | Area | Delivers |
| --- | --- | --- | --- |
| H1 | **The plan** | `docs/` | This document; STORY.md's new canon; DESIGN.md's build element and art direction (the owner's words); ROADMAP's exception line; NEXT; DECISIONS |
| H2 | **The face** | `gameplay/actor` | `Face` (eye and brow layers, styles, moods, look, lag, idle habits) as part of the look; the eye and brow sheets in `art/`. Tests: mood and look pick the right frames; lag offsets; blink timing per style |
| H3 | **The floating staff** | `gameplay/player`, `content/wizard` | Hover and bob, the body pointing at the aim from a 16-direction sheet, the shot from the head's tip, downed lying flat, the hurtbox circle; the four starter heads and their sheets; `StaffBase` look fields. Tests: the tip per head and direction, downed and revive, the 4-bot smoke test |
| H4 | **The poof** | `gameplay/player`, `core/projectiles` (effect kind), `gameplay/feel` | Swap on a different staff button, 0.18 s, body and face at 35%, no cast delay, no poof on the same button; `KIND_POOF`. Tests: swap timing; a cast on the press; holding one button never poofs |
| H5 | **The strays** | `content/enemies`, `gameplay/ai` | The Cinder Rod (from the imp), the Splinter, the Rime Crook, the staked dummies; hopping; furious brows while winding up; the Scepter and the Fork once rain and triple exist. Tests: `test_ai*`, the dummies, each stray's staff compiles |
| H6 | **The intro** | `gameplay/flow`, `content/story` | The cutscene, the skip, one drop per player, played once per new save. Tests: it plays, skips, and starts the run within its time |
| H7 | **The docs** | `docs/STYLE.md`, READMEs, `art/kit/golden.json` | Golden examples for a player staff and a stray; the face rules; "staff" for the player in every contract |

## Owner decisions (2026-10-28)

1. **Every character is a living staff;** the protagonist is goofy, the enemies look a bit evil.
2. **Cartoon faces:** floating eyes and separate floating eyebrows.
3. **The wand's movement:** the character floats and points where it aims; rendered as a staff.
4. **The curled staff,** made more distinguishable (the big spiral).
5. **Four different staffs per player** that pop in and out in a very fast cloud poof when a different staff button is pressed.
6. **The staff holds four personalities at a time;** picking up a new staff is a personality swap.
7. **Eye height: Close.**
8. **The story:** the wizard throws staffs away on purpose, which the staff sees as an accident; the strays are earlier staffs of the same wizard; bosses are powerful staffs; the final boss is the wizard's current staff, and the final, final boss is the wizard picking it up.
9. **The reason:** just because; new is better (or is it, in the end?).
10. **The intro:** the staff is dropped down a hole and falls for a while until it hits a hard floor.
11. **The ending: A,** the trade-in.

**Defaults the owner has not overruled** (Claude's picks in the mockup; change any of them in H1's review): the enemy name **strays**; strays **hop** while players float; the starter heads **curl, star, moon, crystal** on RB, RT, LB, LT; the personality names (Optimist, Show-off, Dozer, Sergeant).

## Later (in `docs/BACKLOG.md`)

- A beaten stray's personality may offer to join: the way new staffs are found (M3, rewards).
- The bosses, the Favourite, the wizard fight and the ending (M3, M6).
- A mode where you play a dropped Favourite (after the ending exists).
- A sharper moon: the crescent reads as a blob at some angles in the mockup; H3 redraws it or picks another head.

## Self-critique against docs/DESIGN.md

- **Nobody waits for anybody:** the intro is the only shared moment; any player can skip it, it plays once per save, and it is shorter than a menu. The poof never delays a cast.
- **A mix of tones:** the comedy is aimed at the wizard and at the staffs' certainty that it was an accident; the stakes stay (being thrown out, a hard floor, the climb). No real group is the joke.
- **Readable chaos:** the body shows each player's live staff; the player colour stays on the heads only; strays glow in element colours and hop; the stray's brows add a telegraph and remove none.
- **Art direction:** DESIGN.md's locked style N wizard is replaced by the living staff; the style N wizard survives as the villain. This needs the owner's edit of DESIGN.md (H1).
- **Copyright:** every name and design here is original.
