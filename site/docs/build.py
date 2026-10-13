#!/usr/bin/env python3
"""Render the short website guides using only the Python standard library.

Guide metadata lives in pages.json; each guide body is an HTML fragment.
The built homepage supplies the shared navigation, icons, and footer so their
links, appearance controls, and icon license cannot drift between pages.
"""
import html
import json
from pathlib import Path
import re
import sys

SOURCE = Path(__file__).resolve().parent
out = Path(sys.argv[1])
version, asset_version = sys.argv[2:4]
pages = json.loads((SOURCE / 'pages.json').read_text())
home = (out / 'index.html').read_text()


def extract(pattern):
    matches = re.findall(pattern, home, re.S)
    if len(matches) != 1:
        raise ValueError(f'Expected one shared homepage fragment: {pattern}')
    return matches[0]


def root_links(fragment):
    return (fragment.replace('href="./"', 'href="/"')
            .replace('href="#install"', 'href="/#install"')
            .replace('src="favicon.svg', 'src="/favicon.svg')
            .replace('href="fonts/', 'href="/fonts/'))


icons = extract(r'<!-- GitHub and Discord icons:.*?</svg>')
header = root_links(extract(r'<header class="top">.*?</header>'))
header = header.replace('href="/docs/"', 'href="/docs/" aria-current="true"')
footer = root_links(extract(r'<footer>.*?</footer>'))
esc = html.escape


def guide_nav(current=None):
    return '<nav class="guide-nav" aria-label="Guides"><a class="all-guides" href="/docs/">← All guides</a>' + ''.join(
        f'<a href="/docs/{p["slug"]}/"' + (' aria-current="page"' if p['slug'] == current else '') +
        f'>{p["title"]}</a>' for p in pages) + '</nav>'


def image(page, eager=False):
    return f'''<figure class="doc-screen"><img src="/img/{page['image']}-800.webp"
      srcset="/img/{page['image']}-800.webp 800w, /img/{page['image']}.webp 1600w"
      sizes="(max-width: 760px) calc(100vw - 40px), (max-width: 1100px) 65vw, 700px"
      width="1600" height="1000" alt="{esc(page['alt'])}" loading="{'eager' if eager else 'lazy'}" decoding="async"></figure>'''


def document(title, description, path, body, kind):
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} | raftaar docs</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="https://rhun.app{path}">
<meta name="theme-color" content="#111216">
<meta name="color-scheme" content="light dark">
<script src="/theme.js?v={asset_version}"></script>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" href="/fonts/InstrumentSans-Latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/style.css?v={asset_version}">
<link rel="stylesheet" href="/docs/docs.css?v={asset_version}">
<script src="/docs/docs.js?v={asset_version}" defer></script>
<meta property="og:type" content="website">
<meta property="og:site_name" content="raftaar">
<meta property="og:title" content="{esc(title)} | raftaar docs">
<meta property="og:description" content="{esc(description)}">
<meta property="og:url" content="https://rhun.app{path}">
<meta property="og:image" content="https://rhun.app/img/card.png">
<meta name="twitter:card" content="summary_large_image">
</head>
<body class="docs {kind}">
{icons}
<a class="skip" href="#main">Skip to content</a>
{header}
{body}
{footer}
</body>
</html>
'''


landing_rail = '<nav class="category-rail" aria-label="Explore the guides"><div class="rail-links">' + ''.join(
    f'<a href="#{p["slug"]}" data-track="{p["slug"]}"><span class="rail-title">{p["title"]}</span></a>'
    for i, p in enumerate(pages, 1)) + '</div><div class="rail-meter" aria-hidden="true"><span></span></div></nav>'
chapters = ''
for i, p in enumerate(pages, 1):
    links = ''.join(f'<a href="/docs/{p["slug"]}/#{sid}">{title}</a>' for sid, title in p['sections'][:3])
    chapters += f'''<section class="doc-chapter" id="{p['slug']}" aria-labelledby="{p['slug']}-title">
      <h2 id="{p['slug']}-title"><a href="/docs/{p['slug']}/">{p['title']}</a></h2>
      <p class="chapter-description">{p['description']}</p>
      <a class="chapter-image-link" href="/docs/{p['slug']}/" aria-label="Read the {p['title'].lower()} guide">{image(p, i == 1)}</a>
      <div class="chapter-bottom"><a class="button" href="/docs/{p['slug']}/">Read the guide</a></div>
      <div class="chapter-topics">{links}</div>
    </section>'''
landing = f'''<main id="main" class="wrap">
  <section class="docs-intro" aria-labelledby="docs-title">
    <div><h1 id="docs-title">Get to know<br><span>your editor.</span></h1></div>
    <div class="intro-aside"><p>Short guides for the things you do every day. From your first file to your next commit.</p>
    <a href="/docs/getting-started/" class="text-link">Start with the basics</a>
    </div>
  </section>
  <div class="docs-explore">{landing_rail}<div class="doc-chapters">{chapters}</div></div>
  <section class="docs-help"><h2>Need a hand?</h2><div><a class="button" href="https://discord.gg/Aj4drpFbWf">Ask on Discord</a><a class="text-link" href="https://github.com/vshvedov/rhun/blob/main/docs/guide.md">Full technical reference</a></div></section>
</main>'''
(out / 'docs').mkdir(exist_ok=True)
(out / 'docs/index.html').write_text(document('Get to know your editor', 'Short guides to installing raftaar, editing code, using the terminal, following agents, Git, and customization.', '/docs/', landing, 'docs-index'))

for i, page in enumerate(pages):
    slug = page['slug']
    content = (SOURCE / f'{slug}.html').read_text()
    for section_id, _ in page['sections']:
        if content.count(f'id="{section_id}"') != 1:
            raise ValueError(f'{slug}: expected section {section_id}')
    toc = '<nav class="page-toc" aria-label="On this page"><p class="toc-title">On this page</p>' + ''.join(
        f'<a href="#{sid}" data-track="{sid}">{title}</a>' for sid, title in page['sections']) + '</nav>'
    adjacent = ''
    for j, direction in [(i - 1, 'Previous'), (i + 1, 'Next')]:
        if 0 <= j < len(pages):
            p = pages[j]
            adjacent += f'<a href="/docs/{p["slug"]}/"><strong>{p["title"]} <span aria-hidden="true">{"←" if direction == "Previous" else "→"}</span></strong></a>'
        else:
            adjacent += '<a href="/docs/"><strong>All guides</strong></a>'
    body = f'''<main id="main" class="wrap guide-layout">
    <aside class="guide-sidebar">{guide_nav(slug)}</aside>
    <div class="guide-main">
      <header class="guide-heading"><h1>{page['title']}</h1><p>{page['description']}</p></header>
      {image(page, True)}
      <div class="mobile-toc">{toc.replace('aria-label="On this page"', 'aria-label="Page sections"').replace(' data-track=', ' data-mobile-track=')}</div>
      <article class="guide-content" aria-label="{page['title']}">{content}</article>
      <nav class="adjacent-guides" aria-label="Continue reading">{adjacent}</nav>
    </div><aside class="guide-toc">{toc}</aside>
    </main>'''
    target = out / 'docs' / slug
    target.mkdir(exist_ok=True)
    (target / 'index.html').write_text(document(page['title'], page['description'], f'/docs/{slug}/', body, 'docs-guide'))

# Keep discovery URLs in sync with the actual generated pages.
sitemap = out / 'sitemap.xml'
xml = sitemap.read_text()
urls = ['/docs/'] + [f'/docs/{p["slug"]}/' for p in pages]
sitemap.write_text(xml.replace('</urlset>', ''.join(f'  <url><loc>https://rhun.app{url}</loc></url>\n' for url in urls) + '</urlset>'))
