# Story

The canon and tone for every word in Spellmerge. Story text (`content/story/`), component descriptions, item names and any other text in the game are written to fit this file. The vision is in [DESIGN.md](DESIGN.md) (pillar 3, "A mix of tones"). Claude maintains this file. It is short on purpose, so new writing has room to add things. Anything not fixed here is open, but must not contradict what is.

## Tone

**A self-aware, slightly comic magic world with real stakes.**

- **Dry, not silly.** The jokes come from magic being a bit of a mess, wizards being sure of themselves and rules being applied too literally. No pun in every line, no winking at the player every sentence, no memes.
- **The stakes are real.** The crypt is dangerous, people have been lost in it, and a downed wizard needs a friend. A joke may make a danger funnier; it never makes it small.
- **Short.** One idea per line. Text is read by four players at once, mid-fight. A description is one sentence (at most 60 characters, what the builder's note shows in three lines) that says what the thing does and, if there is room, how it feels.
- **Plain words.** Say what the thing does in words a player already knows. Keep invented words to the few in the canon below.
- **Together.** Magic is better with company. Nothing in the story needs one player to wait for another, and no line talks about "the player" or "the hero". Several wizards are always possible.
- **Original.** No names, quotes, characters or places from other works, and no real people (AGENTS.md, copyright).

## Canon (fixed)

1. **The wizards.** The player characters are apprentices of the Merge, a loose, underfunded guild of spellbuilders. They are one kind of wizard; hats, robes and colours are only how they look. They are not chosen ones. They are the ones who showed up.
2. **Magic is built, not learned.** A spell is assembled from parts: a **form** (what it is), an **element** (what it is made of), **modifiers** (how it behaves) and a **trigger** (what happens next, holding another spell). The guild's motto is the game's tagline: *Merge spells. Cause chaos. Together.* Wizards treat a clever combination as a point of pride and a failed one as "an experiment".
3. **The four elements:** fire, frost, storm and void. Fire burns and is eager; frost slows and is patient; storm is quick and spreads; void is quiet and a little rude (it takes things away). Elements react with each other, and the world finds this normal.
4. **The place.** The first setting is **the crypt**: the old cellar of an abandoned tower, deeper than the tower is tall. Its rooms are not the same from one visit to the next. Nobody knows who built it. A later biome may be added; it follows the same tone.
5. **The foes.** Creatures of the crypt are called **imps** in general; the first is the **ember imp**. They are not evil, just territorial, and they were here first. Larger, named enemies are **guardians** of a room or a floor, and each guardian has a reason to be there, which a line of lore can give.
6. **The stakes.** Something below the crypt is waking up, and spells there go wrong a little more every year. That is the reason to go down, and the early game never fully explains it. How runs and progress work is set in PLAN, not here; if a run ends, the story explains it as the guild sending the next apprentices, which the guild is quietly embarrassed by.
7. **Relics** are things left in the crypt that change how spells behave. Each has a short, odd history of who lost it and how.

## Writing rules

- Names are plain nouns, two words at most ("Hexed Bolt", not "The Bolt of Eternal Hexing"). Spell parts keep the names of the registry: Bolt, Beam, Nova, Rune, Orbit; Fire, Frost, Storm, Void; Split, Pierce, Homing, Chain, Bigger, Faster; On Hit, On Expire, Timer.
- Describe the effect truthfully first. A description must never promise something the component does not do.
- Humour is aimed at the in-world guild, its wizards and the magic. It never mocks the real player for playing badly or losing, and never targets real groups of people.
- No swearing, no real-world politics or religion, no graphic violence; fights are about spells and imps.
- Speech, if there is any, is in short lines of at most 60 characters.
- The 60-character description limit and the 60-character speech limit are constants of the story validator (`core/story/story_validator.gd`). The description limit is enforced since M2 part 23; the speech limit applies once dialogue exists. The first lore is `content/story/lore/components/`; the Story README has the schema.

## Not fixed yet

The biomes after the crypt, the bosses' names and stories, the shape of the hub, what lies below the crypt, and all dialogue. A PR that adds these must fit the tone and canon above; Claude records the new canon here when it merges.
