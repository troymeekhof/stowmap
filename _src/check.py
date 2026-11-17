#!/usr/bin/env python3
"""Site checks for docs/ (standard library only).  python3 _src/check.py
Fails on: broken internal links or assets, invalid JSON-LD, FAQ JSON-LD that differs from the visible FAQ,
more than one h1, images without alt or dimensions, duplicate ids, sitemap entries pointing at missing pages,
competitor names, and the banned-phrase list."""
import os, re, sys, json, html
from html.parser import HTMLParser
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = '/stowmap/'
PAGES = ['index.html', 'privacy/index.html', '404.html']
BANNED = [r'\bquietly\b', r'most people', r'\beveryone\b', r'like a pro', r'game.?chang', r'seamless', r'\bpowerful\b', r'\brevolutionary\b', r"that's the whole", r'\bBREAKING\b', r'🚨', r'👇',
          r'daisy\s?disk', r'grandperspective', r'omnidisksweeper', r'cleanmymac', r'disk inventory x', r'\bncdu\b', r'windirstat']
errs = []
class P(HTMLParser):
    def __init__(s): super().__init__(); s.refs=[]; s.ids=[]; s.h1=0; s.imgs=[]; s.ld=[]; s._ld=False; s.text=[]; s._skip=0
    def handle_starttag(s, tag, attrs):
        a = dict(attrs)
        if 'id' in a: s.ids.append(a['id'])
        if tag == 'h1': s.h1 += 1
        if tag in ('script', 'style'): s._skip += 1
        if tag == 'script' and a.get('type') == 'application/ld+json': s._ld = True
        for k in ('href', 'src', 'poster'):
            if k in a: s.refs.append(a[k])
        if 'srcset' in a: s.refs += [x.strip().split(' ')[0] for x in a['srcset'].split(',')]
        if tag == 'img': s.imgs.append(a)
        if tag == 'video' and not (a.get('width') and a.get('height') and a.get('poster')): errs.append('video without width/height/poster')
    def handle_endtag(s, tag):
        if tag in ('script', 'style'): s._skip -= 1; s._ld = False
    def handle_data(s, d):
        if s._ld: s.ld.append(d)
        elif not s._skip: s.text.append(d)
for page in PAGES:
    src = open(os.path.join(ROOT, page), encoding='utf-8').read(); p = P(); p.feed(src)
    here = os.path.dirname(page)
    if p.h1 != 1: errs.append(f'{page}: {p.h1} h1 elements')
    dup = {i for i in p.ids if p.ids.count(i) > 1}
    if dup: errs.append(f'{page}: duplicate ids {dup}')
    for im in p.imgs:
        if 'alt' not in im or not im.get('width') or not im.get('height'): errs.append(f'{page}: img missing alt/width/height {im.get("src")}')
    for r in p.refs:
        if re.match(r'^(https?:|mailto:|#|data:)', r): continue
        path = r.split('#')[0].split('?')[0]
        if not path: continue
        fs = os.path.join(ROOT, path[len(BASE):]) if path.startswith(BASE) else os.path.normpath(os.path.join(ROOT, here, path))
        if os.path.isdir(fs): fs = os.path.join(fs, 'index.html')
        if not os.path.exists(fs): errs.append(f'{page}: broken reference {r}')
        if '#' in r and path.endswith(('/', '.html')):
            tgt = open(fs, encoding='utf-8').read()
            if f'id="{r.split("#")[1]}"' not in tgt: errs.append(f'{page}: missing anchor {r}')
    for r in p.refs:
        if r.startswith('#') and len(r) > 1 and r[1:] not in p.ids: errs.append(f'{page}: missing anchor {r}')
    for block in p.ld:
        try: data = json.loads(block)
        except Exception as e: errs.append(f'{page}: invalid JSON-LD {e}'); continue
        for node in data.get('@graph', []):
            if node.get('@type') == 'FAQPage':
                vis = re.findall(r'<details><summary>(.*?)</summary><p>(.*?)</p></details>', src, re.S)
                ld = [(q['name'], q['acceptedAnswer']['text']) for q in node['mainEntity']]
                if [(html.unescape(a), html.unescape(b)) for a, b in vis] != ld: errs.append(f'{page}: FAQ JSON-LD does not match the visible FAQ')
            if node.get('@type') == 'SoftwareApplication':
                if node['offers']['price'] != '0' or node['applicationCategory'] != 'UtilitiesApplication': errs.append('SoftwareApplication fields changed')
    text = ' '.join(p.text)
    for b in BANNED:
        if re.search(b, text, re.I): errs.append(f'{page}: banned phrase /{b}/')
sm = open(os.path.join(ROOT, 'sitemap.xml'), encoding='utf-8').read()
for loc in re.findall(r'<loc>(.*?)</loc>', sm):
    path = loc.split('/stowmap/', 1)[1]
    fs = os.path.join(ROOT, path, 'index.html') if (path == '' or path.endswith('/')) else os.path.join(ROOT, path)
    if not os.path.exists(fs): errs.append(f'sitemap: missing {loc}')
    elif 'content="noindex"' in open(fs, encoding='utf-8').read(): errs.append(f'sitemap: noindex page {loc}')
for b in BANNED:
    if re.search(b, open(os.path.join(ROOT, 'llms.txt'), encoding='utf-8').read(), re.I): errs.append(f'llms.txt: banned phrase /{b}/')
print('\n'.join(errs) if errs else 'check: ok'); sys.exit(1 if errs else 0)
