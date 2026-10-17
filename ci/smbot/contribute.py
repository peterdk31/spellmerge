"""The Contribute page, rebuilt daily (docs/PLAN.md, "Contribute page").

Shows: play today's build, current milestone progress, wanted-now counts per
skill, coming next, recently merged, and top contributors. Data comes from the
plan files in this checkout and from GitHub (read-only token); a section whose
data can't be read says so instead of failing the deploy.
"""

from __future__ import annotations

import datetime as dt
import html
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import config as config_mod
from . import gh

SKILLS = {"code": "Coders", "pixel-art": "Pixel artists", "music": "Musicians", "sfx": "Sound designers",
          "writing": "Writers", "level-design": "Level designers"}
TOP_DAYS = 90


@dataclass
class Milestone:
    code: str = "?"
    name: str = "?"
    design: str = ""
    done_when: str = ""
    parts_done: int = 0
    parts_total: int = 0
    checks_done: int = 0
    checks_total: int = 0


@dataclass
class PageData:
    current: Milestone = field(default_factory=Milestone)
    upcoming: list[tuple[str, str, str, str]] = field(default_factory=list)  # code, name, done when, opens
    wanted: dict[str, int] | None = None
    merged: list[dict[str, str]] | None = None
    top: list[tuple[str, int]] | None = None


def parse_roadmap(text: str) -> tuple[Milestone, list[tuple[str, str, str, str]]]:
    current, upcoming = Milestone(), []
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 5 or not re.fullmatch(r"M\d", cells[0]):
            continue
        code, name_cell, status, done_when, opens = cells
        link = re.search(r"\[([^\]]+)\]\(([^)]+)\)", name_cell)
        name = link.group(1) if link else name_cell
        if "In progress" in status:
            current = Milestone(code, name, link.group(2) if link else "", done_when)
        elif current.code != "?" and status.startswith("Not started"):
            upcoming.append((code, name, done_when, opens))
    return current, upcoming


def parse_progress(m: Milestone, text: str) -> Milestone:
    m.parts_total = len(re.findall(r"^\| \d+ \|", text, re.MULTILINE))
    m.parts_done = len(re.findall(r"^\| \d+ \|.*\| Built", text, re.MULTILINE))
    m.checks_total = len(re.findall(r"^- \[[ xX]\]", text, re.MULTILINE))
    m.checks_done = len(re.findall(r"^- \[[xX]\]", text, re.MULTILINE))
    return m


def gather(cfg: config_mod.Config, root: Path = Path("."), now: dt.datetime | None = None) -> PageData:
    now = now or dt.datetime.now(dt.timezone.utc)
    data = PageData()
    roadmap = root / "docs/ROADMAP.md"
    if roadmap.exists():
        data.current, data.upcoming = parse_roadmap(roadmap.read_text())
        design = root / "docs" / data.current.design
        if data.current.design and design.exists():
            parse_progress(data.current, design.read_text())
    try:
        wanted = {skill: 0 for skill in SKILLS}
        for issue in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels=now&per_page=100"):
            if "pull_request" in issue:
                continue
            for label in issue["labels"]:
                if label["name"] in wanted:
                    wanted[label["name"]] += 1
        data.wanted = wanted
    except gh.GhError:
        pass
    try:
        since = (now - dt.timedelta(days=TOP_DAYS)).date().isoformat()
        found = gh.api(f"search/issues?q=repo:{cfg.repo}+is:pr+is:merged+merged:>={since}&sort=updated&per_page=100")
        items = found.get("items", [])
        data.merged = [{"title": i["title"], "url": i["html_url"], "author": contributor_of(i, cfg)}
                       for i in items[:10]]
        counts: dict[str, int] = {}
        for i in items:
            who = contributor_of(i, cfg)
            if who and who != cfg.owner.login and not who.endswith("[bot]"):
                counts[who] = counts.get(who, 0) + 1
        data.top = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:10]
    except gh.GhError:
        pass
    return data


def contributor_of(item: dict[str, Any], cfg: config_mod.Config) -> str:
    login = (item.get("user") or {}).get("login", "")
    m = re.match(r"Submission from @([\w-]+):", item.get("title", ""))
    return m.group(1) if login == cfg.bot.login and m else login


def _bar(done: int, total: int) -> str:
    pct = 0 if not total else round(100 * done / total)
    return (f'<div class="bar" role="progressbar" aria-valuenow="{pct}" aria-valuemin="0" aria-valuemax="100">'
            f'<span style="width:{pct}%"></span></div><p class="small">{done} of {total} ({pct}%)</p>')


def render(cfg: config_mod.Config, data: PageData, version: str, channel: str, stable: str) -> str:
    e = html.escape
    repo_url = f"https://github.com/{cfg.repo}"
    m = data.current
    issues_url = f"{repo_url}/issues?q=is%3Aopen+label%3Anow"

    if data.wanted is None:
        wanted = "<p class='small'>Couldn't load the task list today.</p>"
    elif not any(data.wanted.values()):
        wanted = ("<p>No open tasks yet: areas open for contributions milestone by milestone (Art and Audio first, "
                  f"in M1). Ideas and feedback are always welcome in <a href='{repo_url}/discussions'>Discussions</a>."
                  "</p>")
    else:
        wanted = "<ul class='skills'>" + "".join(
            f"<li><a href='{issues_url}+label%3A{e(skill)}'><strong>{n}</strong> for {e(label.lower())}</a></li>"
            for skill, label in SKILLS.items() if (n := data.wanted.get(skill, 0))) + "</ul>"

    merged = ("<p class='small'>Nothing merged in the last 90 days yet.</p>" if data.merged == [] else
              "<p class='small'>Couldn't load recent merges today.</p>" if data.merged is None else
              "<ul>" + "".join(f"<li><a href='{e(p['url'])}'>{e(p['title'])}</a> <span class='small'>by "
                               f"@{e(p['author'])}</span></li>" for p in data.merged) + "</ul>")
    top = ("<p class='small'>Be the first!</p>" if not data.top else
           "<ol>" + "".join(f"<li><a href='https://github.com/{e(login)}'>@{e(login)}</a> "
                            f"<span class='small'>{n} merged</span></li>" for login, n in data.top) + "</ol>")
    upcoming = "".join(f"<li><strong>{e(code)}: {e(name)}</strong>. Done when: {e(done)}. Opens: {e(opens)}.</li>"
                       for code, name, done, opens in data.upcoming[:3])
    design_link = f"{repo_url}/blob/main/docs/{e(m.design)}" if m.design else f"{repo_url}/blob/main/docs/ROADMAP.md"

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Spellmerge</title>
<meta name="description" content="Merge spells. Cause chaos. Together. A 1-4 player co-op roguelite built by an AI and its community.">
<style>
  :root {{ color-scheme: dark; --bg: #1b1830; --panel: #252141; --fg: #e8e6f5; --muted: #9a98b8; --accent: #f2c14e;
          --cyan: #7fe3ff; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.55 system-ui, sans-serif; }}
  main {{ max-width: 52rem; margin: 0 auto; padding: 2.5rem 1rem 4rem; }}
  h1 {{ color: var(--accent); font-size: 2.6rem; margin: 0; letter-spacing: 0.01em; }}
  h2 {{ font-size: 1.15rem; margin: 0 0 0.6rem; color: var(--cyan); }}
  .tag {{ color: var(--muted); margin: 0.2rem 0 1.2rem; }}
  a {{ color: var(--accent); }}
  .buttons a {{ display: inline-block; margin: 0.4rem 0.8rem 0.4rem 0; padding: 0.6rem 1.2rem;
                border: 2px solid var(--accent); border-radius: 4px; text-decoration: none; font-weight: 600; }}
  .buttons a.primary {{ background: var(--accent); color: var(--bg); }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(22rem, 1fr)); gap: 1rem; margin-top: 2rem; }}
  section {{ background: var(--panel); border-radius: 6px; padding: 1.1rem 1.2rem; }}
  .small {{ color: var(--muted); font-size: 0.88rem; margin: 0.3rem 0; }}
  .bar {{ height: 0.6rem; background: #3a3560; border-radius: 3px; overflow: hidden; }}
  .bar span {{ display: block; height: 100%; background: var(--accent); }}
  ul, ol {{ margin: 0; padding-left: 1.2rem; }}
  li {{ margin: 0.2rem 0; }}
  .skills {{ list-style: none; padding: 0; }}
  footer {{ margin-top: 2.5rem; }}
</style>
</head>
<body>
<main>
  <h1>Spellmerge</h1>
  <p class="tag">Merge spells. Cause chaos. Together. &middot; Every spell is a merge request.</p>
  <p>A 2D roguelite about building deep, combinable spells, for 1&ndash;4 local co-op players. Claude, an AI, writes the
     code, reviews every contribution and ships a new build every day, together with the community.</p>
  <div class="buttons">
    <a class="primary" href="play/">Play {e(stable)}</a>
    <a href="nightly/">Today's build ({e(version)}, {e(channel)})</a>
    <a href="{repo_url}/releases">Windows &amp; Linux</a>
  </div>

  <div class="grid">
    <section>
      <h2>Now: {e(m.code)} {e(m.name)}</h2>
      <p class="small">Done when: {e(m.done_when)}</p>
      <p>Parts built</p>{_bar(m.parts_done, m.parts_total)}
      <p>Checks passed</p>{_bar(m.checks_done, m.checks_total)}
      <p class="small"><a href="{design_link}">Milestone design</a> &middot;
         <a href="{repo_url}/blob/main/docs/NEXT.md">What Claude does next</a></p>
    </section>
    <section>
      <h2>Wanted now</h2>
      {wanted}
      <p class="small"><a href="{repo_url}/blob/main/CONTRIBUTING.md">How to contribute</a> (no git needed for art,
         sound and writing) &middot; <a href="{repo_url}/blob/main/AGENTS.md">for coding agents</a> &middot;
         <a href="style-guide/">Style Guide and art starter kit</a></p>
    </section>
    <section>
      <h2>Coming next</h2>
      <ul>{upcoming or "<li>See the roadmap.</li>"}</ul>
      <p class="small"><a href="{repo_url}/blob/main/docs/ROADMAP.md">Full roadmap</a></p>
    </section>
    <section>
      <h2>Recently merged</h2>
      {merged}
    </section>
    <section>
      <h2>Top contributors (90 days)</h2>
      {top}
    </section>
  </div>

  <footer class="small">
    <a href="{repo_url}">Source on GitHub</a> &middot; <a href="{repo_url}/discussions">Discussions</a> &middot;
    Free on the web forever; the Steam version (later) funds development. Code GPL-3.0-or-later, assets CC-BY-SA-4.0.
    Page rebuilt {dt.datetime.now(dt.timezone.utc):%Y-%m-%d %H:%M} UTC.
  </footer>
</main>
</body>
</html>
"""
