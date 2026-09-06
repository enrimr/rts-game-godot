#!/usr/bin/env python3
"""Builds the publishable documentation site: converts every player/dev
Markdown document to a self-contained HTML page (dark gold-on-dark theme),
rewriting .md links to their .html counterparts. The docs/ folder then serves
directly as a static site (e.g. GitHub Pages -> main branch /docs).

Run from the repo root:  python3 docs/build_site.py

The player manuals (docs/manual/manual_es.html / manual_en.html) are
REGENERATED from docs/guide_es.md / guide_en.md by this script — edit the
Markdown guides, never the manual HTML. Hand-crafted pages (index.html,
design/tech_tree.html, guia-visual, civ gallery) are left untouched.
"""
import datetime
import os
import re
import sys

try:
    import markdown
except ImportError:
    sys.exit("python-markdown is required: pip3 install markdown")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# source (repo-relative) -> output (repo-relative). Root-level docs publish
# into docs/ so the whole site lives under one folder.
PAGES = {
    "docs/guide_es.md": "docs/manual/manual_es.html",
    "docs/guide_en.md": "docs/manual/manual_en.html",
    "GAMEPLAY.md": "docs/gameplay.html",
    "README.md": "docs/about.html",
    "CHANGELOG.md": "docs/changelog.html",
    "CONTRIBUTING.md": "docs/development/contributing.html",
    "SETUP_INSTRUCTIONS.md": "docs/development/setup.html",
    "docs/design/civilizations_en.md": "docs/design/civilizations_en.html",
    "docs/design/civilizations_es.md": "docs/design/civilizations_es.html",
    "docs/design/game-design-document.md": "docs/design/game-design-document.html",
    "docs/design/campaign_story.md": "docs/design/campaign_story.html",
    "docs/design/heroines-design.md": "docs/design/heroines-design.html",
    "docs/architecture/overview.md": "docs/architecture/overview.html",
    "docs/architecture/systems.md": "docs/architecture/systems.html",
    "docs/architecture/audio_synthesis.md": "docs/architecture/audio_synthesis.html",
    "docs/architecture/map_generation.md": "docs/architecture/map_generation.html",
    "docs/architecture/resource_system.md": "docs/architecture/resource_system.html",
    "docs/development/conventions.md": "docs/development/conventions.html",
    "docs/development/getting-started.md": "docs/development/getting-started.html",
    "docs/lore/harimaguada.md": "docs/lore/harimaguada.html",
    "docs/lore/heroes-and-heroines.md": "docs/lore/heroes-and-heroines.html",
    "docs/testing/harnesses.md": "docs/testing/harnesses.html",
}
# CLAUDE.md is intentionally excluded: internal agent instructions, not site content.

# Language pairs get a toggle link in the header.
LANG_PAIRS = {
    "docs/manual/manual_es.html": ("docs/manual/manual_en.html", "English version"),
    "docs/manual/manual_en.html": ("docs/manual/manual_es.html", "Versión en español"),
    "docs/design/civilizations_es.html": ("docs/design/civilizations_en.html", "English version"),
    "docs/design/civilizations_en.html": ("docs/design/civilizations_es.html", "Versión en español"),
}

CSS = """
:root { --bg:#141210; --panel:#1d1a16; --ink:#e8e0cd; --dim:#a89b7f;
        --gold:#d8b45a; --gold-dark:#8a6d2f; --line:#3a3226; --code:#241f19; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink);
       font:17px/1.65 Georgia, 'Times New Roman', serif; }
.wrap { max-width:940px; margin:0 auto; padding:24px 28px 64px; }
header.site { border-bottom:1px solid var(--line); padding:14px 0 12px;
       display:flex; gap:18px; align-items:baseline; flex-wrap:wrap;
       font-family:Verdana, Geneva, sans-serif; font-size:13px; }
header.site .brand { color:var(--gold); font-weight:bold; font-size:15px;
       letter-spacing:.06em; text-decoration:none; }
header.site a { color:var(--dim); text-decoration:none; }
header.site a:hover { color:var(--gold); }
h1,h2,h3,h4 { font-family:Verdana, Geneva, sans-serif; color:var(--gold);
       line-height:1.25; }
h1 { font-size:30px; border-bottom:2px solid var(--gold-dark); padding-bottom:8px; }
h2 { font-size:22px; margin-top:2.2em; border-bottom:1px solid var(--line);
       padding-bottom:5px; }
h3 { font-size:18px; margin-top:1.8em; color:#e6c979; }
a { color:var(--gold); }
code { background:var(--code); padding:1px 6px; border-radius:4px;
       font:14px/1.5 Menlo, Consolas, monospace; color:#e6c979; }
pre { background:var(--code); border:1px solid var(--line); border-radius:8px;
       padding:14px 16px; overflow-x:auto; }
pre code { background:none; padding:0; }
table { border-collapse:collapse; width:100%; margin:1.2em 0;
       font-size:15px; font-family:Verdana, Geneva, sans-serif; }
th { background:#262019; color:var(--gold); text-align:left; }
th,td { border:1px solid var(--line); padding:7px 10px; vertical-align:top; }
tr:nth-child(even) td { background:#1a1712; }
blockquote { border-left:3px solid var(--gold-dark); margin:1em 0;
       padding:2px 18px; color:var(--dim); }
hr { border:none; border-top:1px solid var(--line); margin:2.4em 0; }
img { max-width:100%; border-radius:6px; }
.toc { background:var(--panel); border:1px solid var(--line); border-radius:10px;
       padding:14px 22px; font-family:Verdana, Geneva, sans-serif; font-size:14px; }
.toc ul { margin:6px 0; padding-left:20px; }
.toc a { text-decoration:none; color:var(--dim); }
.toc a:hover { color:var(--gold); }
footer.site { border-top:1px solid var(--line); margin-top:48px; padding-top:14px;
       color:var(--dim); font:12px Verdana, Geneva, sans-serif; }
@media print { body { background:#fff; color:#111; }
       header.site, footer.site, .toc { display:none; }
       h1,h2,h3 { color:#000; } a { color:#000; } }
"""

TEMPLATE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Calima: Flames of the Atlantic</title>
<style>{css}</style>
</head>
<body>
<div class="wrap">
<header class="site">
  <a class="brand" href="{home}">CALIMA · DOCS</a>
  <a href="{home}">Portal</a>
  <a href="{manual_es}">Manual (ES)</a>
  <a href="{manual_en}">Manual (EN)</a>
  {lang_link}
</header>
{body}
<footer class="site">Generated from <code>{src}</code> on {date} —
regenerate with <code>python3 docs/build_site.py</code>. ·
<a href="{home}">Documentation portal</a></footer>
</div>
</body>
</html>
"""


def rel(from_out: str, to_out: str) -> str:
    return os.path.relpath(to_out, os.path.dirname(from_out)).replace(os.sep, "/")


GITHUB_BLOB = "https://github.com/enrimr/rts-game-godot/blob/main/"


def rewrite_links(html: str, out_path: str) -> str:
    """Point every relative link at the PUBLISHED site: .md links become their
    .html pages, other repo paths are re-based from the source location to the
    output location, and anything living outside docs/ (LICENSE, CLAUDE.md)
    goes to the GitHub blob so nothing 404s on a static host."""
    out_by_src = {os.path.normpath(s): o for s, o in PAGES.items()}
    src_dir = "docs"
    for s, o in PAGES.items():
        if o == out_path:
            src_dir = os.path.dirname(s)   # may be "" for repo-root docs
            break

    def fix(m: re.Match) -> str:
        attr, href = m.group(1), m.group(2)
        if href.startswith(("http://", "https://", "#", "mailto:", "data:")):
            return m.group(0)
        base, frag = (href.split("#", 1) + [""])[:2]
        frag = "#" + frag if frag else ""
        target = os.path.normpath(os.path.join(src_dir, base))
        if target in out_by_src:
            return '%s="%s%s"' % (attr, rel(out_path, out_by_src[target]), frag)
        if target.startswith("docs" + os.sep) and                 os.path.exists(os.path.join(ROOT, target)):
            return '%s="%s%s"' % (attr, rel(out_path, target), frag)
        if os.path.exists(os.path.join(ROOT, target)):
            return '%s="%s%s"' % (attr, GITHUB_BLOB + target.replace(os.sep, "/"), frag)
        return m.group(0)

    return re.sub(r'(href|src)="([^"]+)"', fix, html)


def build_page(src: str, out: str) -> None:
    text = open(os.path.join(ROOT, src), encoding="utf-8").read()
    md = markdown.Markdown(extensions=["extra", "toc", "sane_lists"],
                           extension_configs={"toc": {"toc_depth": "2-3"}})
    body = md.convert(text)
    title_m = re.search(r"<h1[^>]*>(.*?)</h1>", body, re.S)
    title = re.sub(r"<[^>]+>", "", title_m.group(1)) if title_m else os.path.basename(src)
    # A linked TOC after the H1 for long pages.
    if body.count("<h2") >= 4 and title_m:
        toc = '<nav class="toc"><b>Contents</b>%s</nav>' % md.toc
        body = body.replace(title_m.group(0), title_m.group(0) + toc, 1)
    lang = "es" if out.endswith("_es.html") or "/guia" in out else "en"
    pair = LANG_PAIRS.get(out)
    lang_link = '<a href="%s">%s</a>' % (rel(out, pair[0]), pair[1]) if pair else ""
    html = TEMPLATE.format(
        lang=lang, title=title, css=CSS, body=body, src=src,
        date=datetime.date.today().isoformat(),
        home=rel(out, "docs/index.html"),
        manual_es=rel(out, "docs/manual/manual_es.html"),
        manual_en=rel(out, "docs/manual/manual_en.html"),
        lang_link=lang_link)
    html = rewrite_links(html, out)
    out_abs = os.path.join(ROOT, out)
    os.makedirs(os.path.dirname(out_abs), exist_ok=True)
    open(out_abs, "w", encoding="utf-8").write(html)
    print("built %-46s <- %s" % (out, src))


def main() -> None:
    for src, out in PAGES.items():
        build_page(src, out)
    print("%d pages." % len(PAGES))


if __name__ == "__main__":
    main()
