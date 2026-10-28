# Story

The canon and tone for every word in Spellmerge. Story text (`content/story/`), component descriptions, item names and any other text in the game are written to fit this file. The vision is in [DESIGN.md](DESIGN.md) (pillar 3, "A mix of tones"). Claude maintains this file. It is short on purpose, so new writing has room to add things. Anything not fixed here is open, but must not contradict what is.

## Tone

**A self-aware, slightly comic magic world with real stakes.**

- **Dry, not silly.** The jokes come from magic being a bit of a mess, staffs being sure of themselves and rules being applied too literally. No pun in every line, no winking at the player every sentence, no memes.
- **The stakes are real.** The crypt is dangerous, nobody has climbed out of it yet, and a downed staff needs a friend. A joke may make a danger funnier; it never makes it small.
- **Short.** One idea per line. Text is read by four players at once, mid-fight. A description is one sentence (at most 60 characters, what the builder's note shows in three lines) that says what the thing does and, if there is room, how it feels.
- **Plain words.** Say what the thing does in words a player already knows. Keep invented words to the few in the canon below.
- **Together.** Magic is better with company. Nothing in the story needs one player to wait for another, and no line talks about "the player" or "the hero". Several wizards are always possible.
- **Original.** No names, quotes, characters or places from other works, and no real people (AGENTS.md, copyright).

## Canon (fixed)

The characters and the story were rewritten on 2026-10-28 at the owner's word (docs/milestones/M2-living-staffs.md).

1. **The staffs.** Every character is a living staff. The players are staffs a wizard threw out, climbing back home together. A staff holds four personalities, one per staff, each with its own head and face; taking a new staff is a personality swap. They are not chosen ones. They are the ones who got dropped.
2. **Magic is built, not learned.** A spell is assembled from parts: a **form** (what it is), an **element** (what it is made of), **modifiers** (how it behaves) and a **trigger** (what happens next, holding another spell). The motto is the game's tagline: *Merge spells. Cause chaos. Together.* Staffs treat a clever combination as a point of pride and a failed one as "an experiment".
3. **The four elements:** fire, frost, storm and void. Fire burns and is eager; frost slows and is patient; storm is quick and spreads; void is quiet and a little rude (it takes things away). Elements react with each other, and the world finds this normal.
4. **The place.** The wizard's tower, and the crypt under it: a long shaft down from a hole in the tower floor, and below it rooms that are not the same from one visit to the next. Home is up. A later biome may be added; it follows the same tone.
5. **The wizard.** Throws staffs away just because: new is better. Drops the old staff down the hole on new-staff day, says "Oops.", and walks off. From the staff's point of view it was an accident. Obviously. Never explains, because there is nothing to explain.
6. **The foes.** **Strays** are the wizard's earlier staffs, all "accidentally" dropped. They are not evil, just sour about it, territorial, and here first. **Bosses** are powerful old staffs with a grudge, each with a reason, which a line of lore can give. The final boss is **the Favourite**, the wizard's current staff, polished and smug; after it, the wizard picks the Favourite up.
7. **The stakes and the ending.** If a run ends, the staff lands at the bottom of the shaft again. If the staffs win, the wizard picks one of them up, says "Huh. Still works.", and drops the Favourite down the hole. New is better; or is it?
8. **Relics** are other things the wizard dropped down the hole. Each has a short, odd history of when and why.

## Writing rules

- Names are plain nouns, two words at most ("Hexed Bolt", not "The Bolt of Eternal Hexing"). Spell parts keep the names of the registry: Bolt, Beam, Nova, Rune, Orbit; Fire, Frost, Storm, Void; Split, Pierce, Homing, Chain, Bigger, Faster; On Hit, On Expire, Timer.
- Describe the effect truthfully first. A description must never promise something the component does not do.
- Humour is aimed at the in-world guild, its wizards and the magic. It never mocks the real player for playing badly or losing, and never targets real groups of people.
- No swearing, no real-world politics or religion, no graphic violence; fights are about spells and imps.
- Speech, if there is any, is in short lines of at most 60 characters.
- The 60-character description limit and the 60-character speech limit are constants of the story validator (`core/story/story_validator.gd`). The description limit is enforced since M2 part 23; the speech limit applies once dialogue exists. The first lore is `content/story/lore/components/`; the Story README has the schema.

## Not fixed yet

The biomes after the crypt, the bosses' names and stories, the shape of the hub, what lies below the crypt, and all dialogue beyond the intro's lines. A PR that adds these must fit the tone and canon above; Claude records the new canon here when it merges.
