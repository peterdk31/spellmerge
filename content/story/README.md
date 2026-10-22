# Story

## Purpose

Words in the game: **lore** (`lore/`) for item and world descriptions, **dialogue** (`dialogue/`) for conversations, and **events** (`events/`) for short in-run story moments. Items without lore or a description become writing tasks.

**Built in M2, from part 23** (Spell system, which has started; see docs/milestones/M2-spell-system.md), once `docs/STORY.md` and the first component descriptions exist. **The example to copy arrives with Claude's first story content in M2**; this README is updated then with its path.

## Contract

- All story content is `.json`, in the schema the first example defines. Validators for missing fields, unknown keys and over-long text arrive with the first example.
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

Arrives with Claude's first content in M2. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
```

## Review questions

Besides the general review:

- Does it fit the canon and tone in `docs/STORY.md`?
- Is it concise, clear and free of spelling mistakes?
- Does it add something (character, world, humour) rather than repeat existing text?
