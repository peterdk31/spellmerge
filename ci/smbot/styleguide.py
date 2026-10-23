"""Builds the Style Guide page and the art starter kit zip for the Pages site.

  python3 -m smbot.styleguide --out site/style-guide     (normally called by smbot.site)

The page is generated from docs/STYLE.md (its sections on the grid, palette, light,
outline, readability, frame counts and the checklist), with swatches from
art/kit/palette.hex.txt, the golden examples listed in art/kit/golden.json and the
animation strip template. The zip holds the files an artist starts from. Neither is
part of the game build or the web export: they exist only on the site.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

from . import config

ROOT = Path(__file__).resolve().parent.parent.parent
STYLE = ROOT / "docs" / "STYLE.md"
KIT = ROOT / "art" / "kit"
SECTIONS = ("The short version", "The 32×32 grid", "Palette", "Light and shading", "Outline", "Readability",
            "Animation frame counts", "Checklist")
GAME = config.load().game
ZIP_NAME = f"{GAME.slug}-art-kit.zip"
PALETTE = f"{GAME.slug}.gpl"  # art/kit/<slug>.gpl.txt, served without the .txt
REPO_BLOB = f"https://github.com/{config.load().repo}/blob/main/"


def sections(markdown: str) -> dict[str, str]:
    """The `## ` sections of a Markdown file, by heading."""
    out: dict[str, str] = {}
    for part in re.split(r"^## ", markdown, flags=re.M)[1:]:
        heading, _, body = part.partition("\n")
        out[heading.strip()] = body.strip()
    return out


def inline(text: str) -> str:
    """Escapes text and renders `code`, **bold** and [links](target)."""
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)

    def link(m: re.Match[str]) -> str:
        target = m.group(2)
        if not re.match(r"https?://", target):  # repo-relative, from docs/
            target = REPO_BLOB + str(Path("docs", target)).replace("docs/../", "")
        return f'<a href="{html.escape(target)}">{m.group(1)}</a>'

    return re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, out)


def render(markdown: str) -> str:
    """The small part of Markdown that docs/STYLE.md uses: paragraphs, lists, task lists, tables."""
    blocks: list[str] = []
    for block in re.split(r"\n\s*\n", markdown.strip()):
        lines = block.splitlines()
        if all(line.startswith("|") for line in lines) and len(lines) >= 2:
            rows = [[cell.strip() for cell in line.strip("|").split("|")] for line in lines]
            head, body = rows[0], [r for r in rows[2:]]
            blocks.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
                          + "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in body)
                          + "</tbody></table>")
        elif all(re.match(r"\d+\. ", line) for line in lines):
            blocks.append("<ol>" + "".join(f"<li>{inline(line.split('. ', 1)[1])}</li>" for line in lines) + "</ol>")
        elif all(line.startswith("- ") for line in lines):
            items = [re.sub(r"^- (\[ \] )?", "", line) for line in lines]
            boxes = all(line.startswith("- [ ] ") for line in lines)
            mark = "&#9744; " if boxes else ""
            blocks.append(f"<ul class='{'checks' if boxes else ''}'>"
                          + "".join(f"<li>{mark}{inline(i)}</li>" for i in items) + "</ul>")
        else:
            blocks.append(f"<p>{inline(' '.join(lines))}</p>")
    return "\n".join(blocks)


def palette() -> list[str]:
    return [line.strip().lower() for line in (KIT / "palette.hex.txt").read_text().splitlines() if line.strip()]


def golden() -> list[dict[str, str]]:
    return json.loads((KIT / "golden.json").read_text())["examples"]


def flat_name(path: str) -> str:
    """content/enemies/ember_imp/idle.svg -> ember_imp_idle.svg (unique, flat)."""
    p = Path(path)
    return f"{p.parent.name}_{p.name}"


def build_zip(out: Path) -> None:
    entries = {PALETTE: KIT / f"{PALETTE}.txt", "palette.hex.txt": KIT / "palette.hex.txt",
               "grid_32.svg": KIT / "grid_32.svg", "sheet_template.svg": KIT / "sheet_template.svg",
               "checklist.md": KIT / "checklist.md", "golden.json": KIT / "golden.json"}
    for example in golden():
        entries[f"golden/{flat_name(example['path'])}"] = ROOT / example["path"]
    notice = (f"{GAME.name} art starter kit, from {REPO_BLOB.removesuffix('blob/main/')} (art/kit/).\n"
              "The art and templates are licensed CC-BY-SA-4.0 (https://creativecommons.org/licenses/by-sa/4.0/):\n"
              f"credit '{GAME.name} contributors' and share changes under the same licence.\n"
              "The rules are in docs/STYLE.md and on the Style Guide page.\n")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, source in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, source.read_bytes())
        zf.writestr(zipfile.ZipInfo("NOTICE.txt", date_time=(2026, 1, 1, 0, 0, 0)), notice)


def page(screenshot: str = "") -> str:
    style = sections(STYLE.read_text())
    missing = [s for s in SECTIONS if s not in style]
    if missing:
        raise ValueError(f"docs/STYLE.md has no section {', '.join(missing)}")
    swatches = "".join(f'<figure class="swatch"><span style="background:#{c}"></span><figcaption>#{c}</figcaption>'
                       "</figure>" for c in palette())
    examples = "".join(
        f'<figure class="golden"><img src="golden/{html.escape(flat_name(e["path"]))}" alt="" width="128" height="128">'
        f"<figcaption>{inline(e['shows'])}<br><code>{html.escape(e['path'])}</code></figcaption></figure>"
        for e in golden())
    parts = []
    for name in SECTIONS:
        body = render(style[name])
        if name == "Palette":
            body = (f'<div class="swatches">{swatches}</div>' + body
                    + f'<p>Download: <a href="kit/{PALETTE}">{PALETTE}</a> (GIMP, Krita, Aseprite, '
                    'LibreSprite, Inkscape) &middot; <a href="kit/palette.hex.txt">palette.hex.txt</a></p>')
        if name == "Animation frame counts":
            body += ('<p>The strip template (download <a href="kit/sheet_template.svg">sheet_template.svg</a>, '
                     'and the <a href="kit/grid_32.svg">32×32 grid</a>):</p>'
                     '<img class="wide" src="kit/sheet_template.svg" alt="Animation strip template">')
        if name == "Checklist":
            body += '<p>As one page: <a href="kit/checklist.md">checklist.md</a></p>'
        parts.append(f'<section><h2>{html.escape(name)}</h2>{body}</section>')
        if name == "The short version":
            parts.append(f'<section><h2>Golden examples</h2><p>The look: the wizard is style N; the rest is redrawn '
                         f'in it over time. Copy their approach, not their pixels.</p><div class="goldens">{examples}</div>'
                         + (f'<p>In the game:</p><img class="wide" src="{html.escape(screenshot)}" '
                            'alt="The arena with four wizards">' if screenshot else "") + "</section>")
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(GAME.name)} Style Guide</title>
<style>
body {{ background: #1b1a2e; color: #e8e6f0; font: 16px/1.55 system-ui, sans-serif; margin: 0 auto; max-width: 960px; padding: 16px; }}
a {{ color: #f4c542; }}
code {{ background: #2b2840; padding: 0 4px; border-radius: 3px; }}
table {{ border-collapse: collapse; width: 100%; margin: 12px 0; display: block; overflow-x: auto; }}
th, td {{ border: 1px solid #3a3858; padding: 4px 8px; text-align: left; vertical-align: top; }}
.swatches {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(84px, 1fr)); gap: 8px; }}
.swatch {{ margin: 0; font-size: 12px; }}
.swatch span {{ display: block; height: 40px; border: 1px solid #3a3858; }}
.goldens {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; }}
.golden {{ margin: 0; font-size: 14px; }}
img {{ image-rendering: pixelated; }}
.golden img {{ background: #4a4663; display: block; }}
img.wide {{ max-width: 100%; height: auto; }}
ul.checks {{ list-style: none; padding-left: 0; }}
.kit {{ background: #2b2840; padding: 12px 16px; border-radius: 6px; }}
</style></head><body>
<h1>{html.escape(GAME.name)} Style Guide</h1>
<p>The art rules, from <a href="{REPO_BLOB}docs/STYLE.md">docs/STYLE.md</a>. The art direction (style N) was chosen in M2.</p>
<p class="kit"><strong>Starter kit:</strong> <a href="{ZIP_NAME}">{ZIP_NAME}</a>: the palette, the 32×32 grid, the strip template, the checklist and the golden examples. CC-BY-SA-4.0.</p>
{chr(10).join(parts)}
<p><a href="../">Back to {html.escape(GAME.name)}</a></p>
</body></html>
"""


def build(out: Path, screenshot_source: Path | None = None) -> None:
    """Writes out/index.html, out/kit/*, out/golden/* and out/<slug>-art-kit.zip."""
    out.mkdir(parents=True, exist_ok=True)
    (out / "kit").mkdir(exist_ok=True)
    (out / "golden").mkdir(exist_ok=True)
    shutil.copyfile(KIT / f"{PALETTE}.txt", out / "kit" / PALETTE)
    for name in ("palette.hex.txt", "grid_32.svg", "sheet_template.svg", "checklist.md"):
        shutil.copyfile(KIT / name, out / "kit" / name)
    for example in golden():
        shutil.copyfile(ROOT / example["path"], out / "golden" / flat_name(example["path"]))
    shot = ""
    if screenshot_source and screenshot_source.is_file():
        shutil.copyfile(screenshot_source, out / "in_game.png")
        shot = "in_game.png"
    (out / "index.html").write_text(page(shot))
    build_zip(out / ZIP_NAME)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--screenshot", type=Path, help="an in-game PNG to show (optional)")
    args = ap.parse_args(argv)
    build(args.out, args.screenshot)
    return 0


if __name__ == "__main__":
    sys.exit(main())
