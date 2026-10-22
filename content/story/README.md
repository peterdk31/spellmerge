# Story

## Purpose

Words in the game: **lore** (`lore/`) for item and world descriptions, **dialogue** (`dialogue/`) for conversations, and **events** (`events/`) for short in-run story moments. Items without lore or a description become writing tasks.

**Built in M2, from part 23** (see docs/milestones/M2-spell-system.md), now that `docs/STORY.md` and the first component descriptions exist. Only component lore exists so far; dialogue and events come with their own schema and validator when the first ones are written.

## Contract

- All story content is `.json`. A **lore file about a component** is `lore/components/<id>.json`, where `<id>` is the component's id (the folder name in `content/spells/`), with exactly these keys:
  - `id`: the same as the file name.
  - `about`: `"component"`.
  - `text`: one line, at most **60 characters** (the builder's note shows three lines), that says truthfully what the component does and, if there is room, how it feels. No line breaks, no spaces at either end.
- The validator (`core/story/story_validator.gd`, run by `tests/content/story/test_lore.gd` and at start in a debug build) reports missing fields, unknown keys, wrong types, an `id` that is not the file name, empty or over-long text, a duplicate id, and a component with no lore file. Speech lines (dialogue, not written yet) will be limited to 60 characters.
- It must fit the canon and tone in `docs/STORY.md` (written by Claude before this area opens). Do not contradict established lore.
- Text is short and readable by all 4 players at once. Nothing makes one player wait for another, and no choice blocks the others.
- Original writing only: no quotes, names or characters from other works, and no real people.
- Content is discovered by folder through `core/registry`. Story files refer to other content by id and never call other areas.

## Allowed files

`.json`, plus `.license` files. Limit: 1 MB per file (small is better). No code.

## Steps

1. Copy the example file into the right sub-folder and rename it.
2. Replace the text, keeping the structure and ids valid.
3. Run the check below, then open a PR using the template.

## Example to copy

`content/story/lore/components/bolt.json`:

```json
{
 "id": "bolt",
 "about": "component",
 "text": "A single shot that flies straight. Reliable, which the guild finds suspicious."
}
```

The text appears in the builder when a player points at the component. A new component in `content/spells/` should get its own lore file (a debug build warns without one and the builder shows no description; no test fails, so Spells PRs are not blocked by it).

## Validate

```sh
tools/check.sh
```

## Review questions

Besides the general review:

- Does it fit the canon and tone in `docs/STORY.md`?
- Is it concise, clear and free of spelling mistakes?
- Does it add something (character, world, humour) rather than repeat existing text?
