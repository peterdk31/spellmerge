"""The project's home page, rebuilt daily (docs/PLAN.md, "Contribute page").

Shows: play today's build, current milestone progress, how to report a bug or
share an idea with the community queue's size, coming next, recently merged, and
community reports done recently. Data comes from the plan files in this checkout
and from GitHub (read-only token); a section whose data can't be read says so
instead of failing the deploy.
"""

from __future__ import annotations

import datetime as dt
import html
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from . import config as config_mod
from . import gh

RECENT_DAYS = 90


@dataclass
class Milestone:
    code: str = "?"
    name: str = "?"
    design: str = ""
    done_when: str = ""
    parts_done: int = 0
    parts_total: int = 0
    parts_left: list[tuple[str, str]] = field(default_factory=list)  # id, name, in the design's order
    checks_done: int = 0
    checks_total: int = 0


@dataclass
class PageData:
    current: Milestone = field(default_factory=Milestone)
    upcoming: list[tuple[str, str, str]] = field(default_factory=list)  # code, name, done when
    queue: dict[str, int] | None = None  # scheduled and backlog community issues
    merged: list[dict[str, str]] | None = None
    done: list[dict[str, str]] | None = None  # community reports done recently


def parse_roadmap(text: str) -> tuple[Milestone, list[tuple[str, str, str]]]:
    current, upcoming = Milestone(), []
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4 or not re.fullmatch(r"M\d", cells[0]):
            continue
        code, name_cell, status, done_when = cells
        link = re.search(r"\[([^\]]+)\]\(([^)]+)\)", name_cell)
        name = link.group(1) if link else name_cell
        if "In progress" in status:
            current = Milestone(code, name, link.group(2) if link else "", done_when)
        elif current.code != "?" and status.startswith("Not started"):
            upcoming.append((code, name, done_when))
    return current, upcoming


# A part's id in a design's parts table: a number (M0 and M1's form) or a phase letter and a
# number, with a letter for a split part ("A6c", "F9a"; the staffs design's form).
PART_ID = r"\d+|[A-Z]\d+[a-z]?"


def _part_markers(m: Milestone, text: str, done: bool | None = None) -> set[str]:
    """Part ids named the way tasks and commits name them: "(M2 part 5)", or for a lettered id
    "(part F9a)" or "(staffs B6a)". Follow-ups, halves and polish ("(M2 part 25 follow-up)")
    don't count; only the bare form. `done` keeps only ticked (True) or open (False) tasks."""
    box = {None: r"", True: r"^- \[[xX]\].*?", False: r"^- \[ \].*?"}[done]
    found = set(re.findall(rf"{box}\({re.escape(m.code)} part (\d+)\)", text, re.MULTILINE))
    found |= set(re.findall(rf"{box}\((?:part|[a-z][a-z ]*) ([A-Z]\d+[a-z]?)\)", text, re.MULTILINE))
    return found


def parse_progress(m: Milestone, text: str, next_md: str = "", log_md: str = "", commits: str = "") -> Milestone:
    """Parts built: a "Built" status in the design's parts table (M0's form), or the part named
    by a ticked task in docs/NEXT.md, a docs/LOG.md heading or a commit on main. A part built in
    pieces ("B2a" to "B2d" for B2) is built once every piece named anywhere is, and none is open."""
    parts: dict[str, str] = {}
    for row in re.finditer(rf"^\| ({PART_ID}) \| ([^|]*)\|", text, re.MULTILINE):
        parts.setdefault(row.group(1), row.group(2).strip().strip("*").strip())
    done = set(re.findall(rf"^\| ({PART_ID}) \|.*\| Built", text, re.MULTILINE))
    done |= _part_markers(m, next_md, done=True)
    done |= {d for line in re.findall(r"^## .*$", log_md, re.MULTILINE) for d in _part_markers(m, line)}
    done |= _part_markers(m, commits)
    open_ = _part_markers(m, next_md, done=False)
    for part in parts:
        pieces = {p for p in done | open_ if re.fullmatch(rf"{part}[a-z]", p)}
        if part not in done and pieces and pieces <= done:
            done.add(part)
    m.parts_total = len(parts)
    m.parts_done = len(parts.keys() & done)
    m.parts_left = [(part, name) for part, name in parts.items() if part not in done]
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
            plan = {name: (root / "docs" / name).read_text() if (root / "docs" / name).exists() else ""
                    for name in ("NEXT.md", "LOG.md")}
            parse_progress(data.current, design.read_text(), plan["NEXT.md"], plan["LOG.md"],
                           recent_commits(cfg, now))
    try:
        data.queue = {label: len([i for i in gh.api_paginated(
            f"repos/{cfg.repo}/issues?state=open&labels={label}&per_page=100") if "pull_request" not in i])
            for label in ("scheduled", "backlog")}
    except gh.GhError:
        pass
    since = (now - dt.timedelta(days=RECENT_DAYS)).date().isoformat()
    try:
        # Newest merge first. Search can only sort by update time, which a comment after the
        # merge changes, so take the last 30 and sort by mergedAt here.
        found = json.loads(gh.run("pr", "list", "--repo", cfg.repo, "--state", "merged", "--limit", "30",
                                  "--search", f"merged:>={since}", "--json", "title,url,mergedAt"))
        found.sort(key=lambda p: p["mergedAt"], reverse=True)
        data.merged = [{"title": p["title"], "url": p["url"]} for p in found[:10]]
    except (gh.GhError, ValueError, KeyError):
        pass
    try:
        found = gh.api(f"search/issues?q=repo:{cfg.repo}+is:issue+is:closed+reason:completed+label:triaged"
                       f"+closed:>={since}&sort=updated&per_page=10")
        data.done = [{"title": i["title"], "url": i["html_url"], "author": (i.get("user") or {}).get("login", "")}
                     for i in found.get("items", [])[:10]]
    except gh.GhError:
        pass
    return data


def recent_commits(cfg: config_mod.Config, now: dt.datetime) -> str:
    """The messages of main's commits from the last RECENT_DAYS days: owner sessions name their
    part only there ("(part F9a)"). The checkout is shallow, so they come from the API; empty if
    it can't be read, and the bar then counts from the plan files alone."""
    since = (now - dt.timedelta(days=RECENT_DAYS)).isoformat(timespec="seconds")
    try:
        found = gh.api_paginated(f"repos/{cfg.repo}/commits?sha=main&since={since}&per_page=100")
        return "\n".join(((c.get("commit") or {}).get("message") or "") for c in found)
    except (gh.GhError, ValueError, AttributeError):
        return ""


def _bar(done: int, total: int) -> str:
    pct = 0 if not total else round(100 * done / total)
    return (f'<div class="bar" role="progressbar" aria-valuenow="{pct}" aria-valuemin="0" aria-valuemax="100">'
            f'<span style="width:{pct}%"></span></div><p class="small">{done} of {total} ({pct}%)</p>')


def render(cfg: config_mod.Config, data: PageData, version: str, channel: str, stable: str,
           preview: str = "") -> str:
    e = html.escape
    repo_url = f"https://github.com/{cfg.repo}"
    m = data.current
    preview_link = f'<a href="preview/">Latest preview ({e(preview)})</a>' if preview else ""

    queue = ("<p class='small'>Couldn't load the queue today.</p>" if data.queue is None else
             f"<p class='small'><a href='{repo_url}/issues?q=is%3Aopen+label%3Ascheduled'>{data.queue['scheduled']} "
             f"in the work queue</a> &middot; <a href='{repo_url}/issues?q=is%3Aopen+label%3Abacklog'>"
             f"{data.queue['backlog']} on the backlog</a></p>")

    merged = ("<p class='small'>Nothing merged in the last 90 days yet.</p>" if data.merged == [] else
              "<p class='small'>Couldn't load recent merges today.</p>" if data.merged is None else
              "<ul>" + "".join(f"<li><a href='{e(p['url'])}'>{e(p['title'])}</a></li>" for p in data.merged) + "</ul>")
    done = ("<p class='small'>Couldn't load them today.</p>" if data.done is None else
            "<p class='small'>None yet: be the first to report a bug or share an idea!</p>" if not data.done else
            "<ul>" + "".join(f"<li><a href='{e(p['url'])}'>{e(p['title'])}</a> <span class='small'>reported by "
                             f"@{e(p['author'])}</span></li>" for p in data.done) + "</ul>")
    upcoming = "".join(f"<li><strong>{e(code)}: {e(name)}</strong>. Done when: {e(done)}.</li>"
                       for code, name, done in data.upcoming[:3])
    design_link = f"{repo_url}/blob/main/docs/{e(m.design)}" if m.design else f"{repo_url}/blob/main/docs/ROADMAP.md"
    # Only designs with a checklist (M0's dry runs) have checks; "0 of 0" says nothing.
    checks = f"<p>Checks passed</p>{_bar(m.checks_done, m.checks_total)}" if m.checks_total else ""
    left = ("<p class='small'>Still to build:</p><ul class='small'>" + "".join(
        f"<li><strong>{e(part)}</strong> {e(name)}</li>" for part, name in m.parts_left) + "</ul>"
            if m.parts_left else "")

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(cfg.game.name)}</title>
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
  <h1>{e(cfg.game.name)}</h1>
  <p class="tag">{e(cfg.game.tagline)}</p>
  <p>A 2D roguelite about building deep, combinable spells, for 1&ndash;4 local co-op players. Claude, an AI, writes the
     code and ships a new build every day. Players shape it: every bug report and idea is read and answered.</p>
  <div class="buttons">
    <a class="primary" href="play/">Play {e(stable)}</a>
    <a href="nightly/">Today's build ({e(version)}, {e(channel)})</a>
    {preview_link}
    <a href="{repo_url}/releases">Windows &amp; Linux</a>
  </div>

  <div class="grid">
    <section>
      <h2>Now: {e(m.code)} {e(m.name)}</h2>
      <p class="small">Done when: {e(m.done_when)}</p>
      <p>Parts built</p>{_bar(m.parts_done, m.parts_total)}
      {left}
      {checks}
      <p class="small"><a href="{design_link}">Milestone design</a> &middot;
         <a href="{repo_url}/blob/main/docs/NEXT.md">What Claude does next</a></p>
    </section>
    <section>
      <h2>Help shape the game</h2>
      <p><a href="{repo_url}/issues/new/choose">Report a bug</a> &middot;
         <a href="{repo_url}/discussions">Share an idea or a combo</a></p>
      {queue}
      <p class="small">Claude reads every new post once a day, answers it, and schedules bugs and good ideas.
         <a href="{repo_url}/blob/main/CONTRIBUTING.md">How it works</a> &middot;
         <a href="style-guide/">Style Guide</a></p>
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
      <h2>Done from your reports</h2>
      {done}
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
