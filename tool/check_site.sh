#!/usr/bin/env bash
#
# Sanity checks for the website in site/ (run tool/sync_site_images.sh first):
#
#  1. Every local href/src resolves to a file. Pages serves the site from
#     /<repo>/, so an absolute path works locally and 404s once deployed.
#  2. The __REPO__ placeholder is still there, so forks keep working.
#  3. Every file a download button asks for is one the release workflow
#     publishes — two lists in two files nobody edits together.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d site/img ]] || { echo "site/img is missing — run ./tool/sync_site_images.sh first." >&2; exit 1; }

python3 - <<'PYTHON'
import pathlib, re, sys

site = pathlib.Path('site')
problems = []

for page in sorted(site.rglob('*.html')):
    text = page.read_text(encoding='utf-8')
    for ref in re.findall(r'(?:href|src)\s*=\s*"([^"]+)"', text):
        if ref.startswith(('http://', 'https://', 'mailto:', 'data:', '#')) or '__' in ref:
            continue
        if ref.startswith('/'):
            problems.append(f'{page}: absolute path {ref!r} breaks on GitHub Pages')
            continue
        target = (page.parent / ref.split('#')[0].split('?')[0])
        if ref.endswith('/') or ref in ('./', '.'):
            target = target / 'index.html'
        if not target.exists():
            problems.append(f'{page}: {ref!r} does not exist')

index = (site / 'index.html').read_text(encoding='utf-8')
if '__REPO__' not in index:
    problems.append('site/index.html: the __REPO__ placeholder is gone (hard-coded repository?)')

release = pathlib.Path('.github/workflows/release.yaml').read_text(encoding='utf-8')
published = set(re.findall(r'artifacts/(PiKeep-[\w.-]+)', release))
wanted = set(re.findall(r'data-asset="([^"]+)"', index)) | set(re.findall(r'download/(PiKeep-[\w.-]+)', index))
for name in sorted(wanted - published):
    problems.append(f'site asks for {name}, which release.yaml does not publish')

if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print(f'site OK: {len(wanted)} release assets referenced, all published')
PYTHON
