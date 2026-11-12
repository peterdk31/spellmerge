# Story

## Purpose

Words in the game: **lore** (`lore/`) for world descriptions, **dialogue** (`dialogue/`) for conversations, and **events** (`events/`) for short in-run story moments. Items without a description become writing tasks.

**Built in M2, from part 23** (see docs/milestones/M2-spell-system.md), now that `docs/STORY.md` exists. **A card's description is part of the card** (since 2026-11-05): the one line the builder shows lives in the card's own `.tres` (`description`, content/spells/README.md), so a card is one folder. Dialogue, events and other lore come with their own schema and validator when the first ones are written. The intro's captions (living staffs H6) live in `gameplay/flow/intro.gd` until then; they follow `docs/STORY.md`'s canon.

## Contract

- **A card's description** (`description` in `content/spells/<kind>s/<id>/<id>.tres`): one line, at most **60 characters** (the builder's note shows three lines), that says truthfully what the card does and, if there is room, how it feels. No line breaks, no spaces at either end. The validator (`SpellValidator.check_descriptions`, with the line rules of `core/story/story_validator.gd`; run by `tests/content/story/test_lore.gd` and at start in a debug build) reports empty or over-long text and a line that is not one line; a card with none only warns, so a card PR is not blocked by its words. Speech lines (dialogue, not written yet) will be limited to 60 characters.
- It must fit the canon and tone in `docs/STORY.md` (written by Claude before this area opens). Do not contradict established lore.
- Text is short and readable by all 4 players at once. Nothing makes one player wait for another, and no choice blocks the others.
- Original writing only: no quotes, names or characters from other works, and no real people.
- Story files, when they exist, are `.json`, are discovered by folder through `core/registry`, refer to other content by id and never call other areas.

## Allowed files

`.json`, plus `.license` files. Limit: 1 MB per file (small is better). No code. A card's description is a line in its `.tres` (content/spells/README.md).

## Steps

1. For a card's description: edit the `description = "..."` line of its `.tres`.
2. Keep the structure and ids valid.
3. Run the check below, then open a PR using the template.

## Example to copy

`content/spells/carriers/bolt/bolt.tres`:

```
description = "One shot, straight. Reliable, which the guild suspects."
```

The text appears in the builder when a player points at the card.

## Validate

```sh
tools/check.sh
```

## Review questions

Besides the general review:

- Does it fit the canon and tone in `docs/STORY.md`?
- Is it concise, clear and free of spelling mistakes?
- Does it add something (character, world, humour) rather than repeat existing text?
