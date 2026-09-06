#!/usr/bin/env python3
"""Regenerates docs/testing/harnesses.md from the ## header comment of every
project/tools/check_*.gd. Run from the repo root: python3 docs/testing/regen_harness_catalog.py"""
import glob, os, re

rows = []
for path in sorted(glob.glob('project/tools/check_*.gd')):
    name = os.path.basename(path)[:-3]
    if name.endswith('_watcher'):
        continue   # helper node of another harness, not standalone
    lines = open(path).read().splitlines()
    doc = []
    for ln in lines[1:18]:
        s = ln.strip()
        if s.startswith('#'):
            text = s.lstrip('#').strip()
            if text:
                doc.append(text)
        elif s == '' or s.startswith('extends'):
            if doc:
                break
            continue
        elif doc:
            break
        else:
            break
    envs = sorted(set(re.findall(r'CALIMA_[A-Z_]+', open(path).read())))
    rows.append((name, ' '.join(doc) if doc else '(no header comment)', envs))

out = []
out.append('# Headless & Renderer Harness Catalog\n')
out.append('Every standalone harness under `project/tools/` (things GUT cannot easily reach:')
out.append('scene loads, real-renderer screenshots, multi-process networking, long simulations).')
out.append("This file is GENERATED from each harness's header comment — keep those comments")
out.append('accurate and regenerate with the snippet at the bottom.\n')
out.append('Run pattern (from the repo root):\n')
out.append('```sh')
out.append('GODOT=/Applications/Godot.app/Contents/MacOS/Godot')
out.append('# headless harnesses:')
out.append('$GODOT --headless --path project res://tools/<name>.tscn')
out.append('# renderer harnesses (screenshots — need a display):')
out.append('CALIMA_SHOT_DIR=/tmp/<dir> $GODOT --path project --resolution 1500x900 res://tools/<name>.tscn')
out.append('```\n')
out.append('The curated CI-gate subset (the ones that MUST pass before a merge) lives in')
out.append('CLAUDE.md > Testing. Screenshot galleries from past reviews are kept under')
out.append('`docs/design/` (unit-redesign-gallery, unit-enhanced-gallery).\n')
out.append('| Harness | Purpose | Env vars |')
out.append('|---|---|---|')
for name, doc, envs in rows:
    doc = doc.replace('|', '\\|')
    if len(doc) > 320:
        doc = doc[:317] + '...'
    out.append('| `%s` | %s | %s |' % (name, doc, ' '.join('`%s`' % e for e in envs) or '—'))
out.append('')
out.append('## Regenerating this catalog\n')
out.append('The table above is scraped from the `##` header block of every `tools/check_*.gd`.')
out.append('After adding or changing a harness, re-run the generator snippet kept in')
out.append('`docs/testing/regen_harness_catalog.py` (python3, from the repo root).')
open('docs/testing/harnesses.md', 'w').write('\n'.join(out) + '\n')
print('written', len(rows), 'harnesses')
