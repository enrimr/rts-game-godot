#!/usr/bin/env python3
"""Site consistency check for the docs/ static site.

Verifies, across every HTML page under docs/ (archived analysis reports are
link-checked but exempt from language rules):
  1. every relative href/src resolves to an existing file (fragments ignored);
  2. Spanish pages (`_es.html`, guia-visual, galeria, index_es) carry Spanish
     chrome and English pages English chrome (TOC title / footer heuristics);
  3. the ES portal links only ES pages outside its labeled English-only
     sections, and the EN portal links only EN pages outside its labeled
     Spanish-only section;
  4. no external CDN <link>/<script> — the site must stay self-contained.

Run from the repo root:  python3 docs/check_site_links.py
Exits non-zero on any failure.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")

ARCHIVED = re.compile(r"analysis-\d{4}|calima-analisis|iso-refactor|_template")

ES_PAGES_HINT = ("_es.html", "guia-visual.html", "galeria-civilizaciones.html",
                 "index_es.html")


def is_spanish(path: str) -> bool:
    name = os.path.basename(path)
    return name.endswith("_es.html") or name in (
        "guia-visual.html", "galeria-civilizaciones.html", "index_es.html")


def main() -> int:
    errors = []
    pages = []
    for dirpath, _dirs, files in os.walk(DOCS):
        for f in files:
            if f.endswith(".html"):
                pages.append(os.path.join(dirpath, f))

    for page in sorted(pages):
        rel_page = os.path.relpath(page, ROOT)
        html = open(page, encoding="utf-8").read()

        archived = bool(ARCHIVED.search(rel_page))

        # 1. broken relative links
        for _attr, href in re.findall(r'(href|src)="([^"#]+)(?:#[^"]*)?"', html):
            if href.startswith(("http://", "https://", "mailto:", "data:", "javascript:")):
                continue
            target = os.path.normpath(os.path.join(os.path.dirname(page), href))
            if not os.path.exists(target):
                errors.append("%s: broken link -> %s" % (rel_page, href))

        if archived:
            continue

        # 4. no CDN stylesheets/scripts/assets (archived reports are exempt)
        for m in re.findall(r'<(?:link|script|img)[^>]+(?:href|src)="(https?://[^"]+)"', html):
            errors.append("%s: CDN reference: %s" % (rel_page, m))

        # 2. chrome language
        spanish = is_spanish(page)
        if spanish:
            for bad in ("<b>Contents</b>", "Generated from", "Documentation portal</a>"):
                if bad in html:
                    errors.append("%s: English chrome on Spanish page: %r"
                                  % (rel_page, bad))
        else:
            for bad in ("<b>Contenido</b>", "Generado desde",
                        "Portal de documentaci"):
                if bad in html:
                    errors.append("%s: Spanish chrome on English page: %r"
                                  % (rel_page, bad))

    # 3. portal purity
    for portal, want_es in (("index_es.html", True), ("index_en.html", False)):
        path = os.path.join(DOCS, portal)
        html = open(path, encoding="utf-8").read()
        # cut everything from the labeled other-language section onward
        cut = html.find("solo en ingl" if want_es else "Spanish only")
        body = html[:cut] if cut != -1 else html
        for href in re.findall(r'href="([^"#]+)"', body):
            if href.startswith(("http", "mailto:")) or href in (
                    "index.html", "index_es.html", "index_en.html"):
                continue
            if not href.endswith(".html"):
                continue
            page_is_es = is_spanish(href)
            if ARCHIVED.search(href):
                continue
            if want_es != page_is_es:
                errors.append("docs/%s: links %s page outside labeled section: %s"
                              % (portal, "EN" if want_es else "ES", href))

    if errors:
        print("\n".join(errors))
        print("%d problem(s)." % len(errors))
        return 1
    print("OK: %d pages checked, links resolve, chrome languages consistent." % len(pages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
