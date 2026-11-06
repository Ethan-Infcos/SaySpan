#!/usr/bin/env python3
"""Build the bilingual static site with repository-based distribution."""
import hashlib
import html
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist'
SITE = json.loads((ROOT / 'site.json').read_text())
BASE = SITE['canonical_origin']
REPO = SITE['repository']
RELEASE = json.loads((ROOT / 'release.json').read_text())
COPY = {lang: json.loads((ROOT / 'content' / f'{lang}.json').read_text()) for lang in ('en', 'zh')}
ASSETS = {}
E = html.escape


def rich(text):
    return text.replace('{repository}', REPO)


def icon(name, cls=''):
    paths = {
        'arrow': '<path d="M5 12h14m-5-5 5 5-5 5"/>',
        'download': '<path d="M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5"/>',
        'globe': '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18Z"/>',
        'copy': '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M15 8V3H3v13h5"/>',
        'check': '<path d="m5 12 4 4L19 6"/>',
        'search': '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
        'lock': '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
        'spark': '<path d="m12 2 2.6 7.4L22 12l-7.4 2.6L12 22l-2.6-7.4L2 12l7.4-2.6L12 2Z"/>',
        'menu': '<path d="M4 7h16M4 12h16M4 17h16"/>',
        'github': '<path d="M9 19c-4 1-4-2-6-2m12 5v-4a3.5 3.5 0 0 0-1-3c3.3-.4 6.7-1.6 6.7-7.3A5.7 5.7 0 0 0 19.2 4a5.3 5.3 0 0 0-.1-3S17.9.6 15 2.5a13.4 13.4 0 0 0-7 0C5.1.6 3.9 1 3.9 1a5.3 5.3 0 0 0-.1 3A5.7 5.7 0 0 0 2.3 7.7C2.3 13.4 5.7 14.6 9 15a3.5 3.5 0 0 0-1 3v4"/>',
        'mac': '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',
    }
    return f'<svg class="icon {cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{paths[name]}</svg>'


def logo():
    return '<span class="brand-mark" aria-hidden="true">S<span>↗</span></span><span>SaySpan</span>'


def button(text, url, kind='primary', glyph='arrow', extra=''):
    return f'<a class="button {kind}" href="{url}" {extra}>{text}{icon(glyph)}</a>'


def shell(lang, route, title, description, body, active='', extra_head=''):
    c = COPY[lang]
    other = 'zh' if lang == 'en' else 'en'
    language = '简体中文' if other == 'zh' else 'English'
    n = c['nav']
    full = f'{BASE}/{lang}/{route}'
    links = [(f'/{lang}/#features', n[0], 'features'), (f'/{lang}/#how-it-works', n[1], 'how'), (f'/{lang}/docs/', n[2], 'docs')]
    nav = ''.join(f'<a href="{u}"'+(' aria-current="page"' if key == active else '')+f'>{v}</a>' for u,v,key in links)
    f = c['footer']
    return f'''<!doctype html>
<html lang="{'zh-Hans' if lang == 'zh' else 'en'}" data-locale="{lang}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{E(title)} | SaySpan</title><meta name="description" content="{E(description)}">
<meta name="theme-color" content="#f7f8f5"><link rel="canonical" href="{full}">
<link rel="alternate" hreflang="en" href="{BASE}/en/{route}"><link rel="alternate" hreflang="zh-Hans" href="{BASE}/zh/{route}"><link rel="alternate" hreflang="x-default" href="{BASE}/en/{route}">
<meta property="og:type" content="website"><meta property="og:site_name" content="SaySpan"><meta property="og:title" content="{E(title)} | SaySpan"><meta property="og:description" content="{E(description)}"><meta property="og:url" content="{full}">
<meta property="og:image" content="{BASE}/assets/social.png"><meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="/assets/{ASSETS['site.css']}"><script src="/assets/{ASSETS['site.js']}" defer></script>{extra_head}</head>
<body><a class="skip-link" href="#main">{c['skip']}</a>
<header class="site-header"><div class="container header-inner"><a class="brand" href="/{lang}/" aria-label="SaySpan">{logo()}</a>
<nav class="main-nav" id="navigation" aria-label="{'主导航' if lang == 'zh' else 'Main navigation'}">{nav}</nav>
<div class="header-actions"><a class="language-switch" href="/{other}/{route}" data-language="{other}" lang="{'zh-Hans' if other == 'zh' else 'en'}">{icon('globe')}<span>{language}</span></a><a class="nav-github" href="{REPO}">{icon('github')}GitHub</a><button class="menu-toggle" aria-expanded="false" aria-controls="navigation" aria-label="{c['menu']}">{icon('menu')}</button></div></div></header>
<main id="main">{body}</main>
<footer class="site-footer"><div class="container footer-top"><div><a class="brand" href="/{lang}/">{logo()}</a><p>{f['description']}</p></div><div class="footer-links"><div><span>{f['product']}</span><a href="/{lang}/#features">{n[0]}</a><a href="{REPO}">{n[3]}</a><a href="/{lang}/download/#release-notes">{f['release']}</a></div><div><span>{f['resources']}</span><a href="/{lang}/docs/">{n[2]}</a><a href="/{lang}/docs/privacy/">{f['privacy']}</a><a href="/{other}/{route}" data-language="{other}">{language}</a></div></div></div><div class="container footer-bottom"><span>© 2026 SaySpan. {f['note']}</span><span class="status"><i></i>{f['status']}</span></div></footer>
<div class="toast" role="status" aria-live="polite" data-success="{c['hero']['copied']}" data-failure="{c['hero']['copyFailed']}"></div></body></html>'''


def mockup(c):
    h = c['hero']
    return f'''<div class="hero-visual"><div class="float-language lang-one" aria-hidden="true">你好<span>Hello</span></div><div class="float-language lang-two" aria-hidden="true">あ<span>Aa</span></div>
<div class="demo-tabs" role="group" aria-label="{'交互示例' if c is COPY['zh'] else 'Workflow examples'}"><button data-demo="write" aria-pressed="true">{h['write']}</button><button data-demo="read" aria-pressed="false">{h['read']}</button></div>
<div class="demo-window"><div class="window-bar"><div class="window-dots"><i></i><i></i><i></i></div><span>{h['mockApp']}</span>{icon('spark')}</div>
<div class="demo-write"><div class="draft-paper"><span class="paper-line">{h['mockGreeting']}</span><p class="demo-inserted">{h['mockTarget']}<span class="cursor"></span></p></div><div class="composition-card"><div class="composition-top"><span class="mini-brand">S <span>SaySpan</span></span><span class="ready"><i></i>{h['ready']}</span></div><div class="translation-row"><span class="row-label">{h['source']}</span><span data-demo-source lang="zh-Hans">{h['mockSource']}</span></div><div class="translation-row translated"><span class="row-label">{h['target']}</span><span data-demo-target lang="en">{h['mockTarget']}</span></div><div class="key-hints"><span><kbd>↵</kbd>{h['enter']}</span><span><kbd>⇥</kbd>{h['tab']}</span></div></div><div class="demo-bottom"><span>{h['mockFooter']}</span><button data-example-next aria-label="{h['swap']}">{icon('arrow')}</button></div></div>
<div class="demo-read" hidden><div class="read-paper"><span class="editorial-label">A NOTE ON CONNECTION</span><p><mark lang="en">{h['readSource']}</mark></p><span>{h['readHint']}</span></div><div class="selection-card"><div class="composition-top"><strong>{h['selection']}</strong><button class="icon-button" data-copy="{h['readTarget']}" aria-label="{h['copy']}">{icon('copy')}</button></div><p lang="zh-Hans">{h['readTarget']}</p><span>English → 简体中文</span></div></div></div><p class="demo-caption">{h['caption']}</p></div>'''


def home(lang):
    c = COPY[lang]; h=c['hero']; f=c['features']; m=c['models']; s=c['steps']; q=c['faq']; end=c['closing']
    strip = ''.join(f'<span>{icon(g)}{t}</span>' for g,t in zip(['mac','lock','globe'], c['strip']))
    small = ''.join(f'<article class="small-feature"><span class="feature-number">{n}</span><h3>{t}</h3><p>{d}</p></article>' for n,t,d in f['small'])
    steps = ''.join(f'<article class="step"><span>0{i+1}</span><h3>{t}</h3><p>{d}</p></article>' for i,(t,d) in enumerate(s['items']))
    faq = ''.join(f'<details><summary>{t}<span aria-hidden="true">+</span></summary><p>{rich(d)}</p></details>' for t,d in q['items'])
    body=f'''<section class="hero container"><div class="hero-copy"><p class="eyebrow"><span class="tiny-star">✳</span>{h['eyebrow']}</p><h1>{h['title']}</h1><p class="hero-description">{h['description']}</p><div class="hero-buttons">{button(h['download'],REPO,'primary','github')}{button(h['guide'],'#how-it-works','text')}</div><p class="meta">{h['meta']}</p></div>{mockup(c)}</section>
<div class="container"><div class="trust-strip">{strip}<span class="strip-signature">Say more. Stay you.</span></div></div>
<section class="section container" id="features"><div class="section-intro"><p class="eyebrow">{f['eyebrow']}</p><h2>{f['title']}</h2><p>{f['description']}</p></div>
<div class="feature-pair"><article class="feature-large write-feature"><div class="feature-heading"><span class="pill">{'输入' if lang=='zh' else 'WRITE'}</span><h3>{f['writeTitle']}</h3><p>{f['writeText']}</p><a class="text-link" href="/{lang}/docs/writing/">{f['writeLink']}{icon('arrow')}</a></div><div class="sentence-illustration" aria-hidden="true"><span class="sentence-cn">让每个想法，都有新的可能。</span><div class="candidate-mini"><b>1 可能</b><span>2 可以</span><span>3 可行</span></div><div class="sentence-en">Give every idea<br><em>new possibilities.</em></div><kbd>⇥ Tab</kbd></div></article>
<article class="feature-large read-feature"><div class="feature-heading"><span class="pill">{'阅读' if lang=='zh' else 'READ'}</span><h3>{f['readTitle']}</h3><p>{f['readText']}</p><a class="text-link" href="/{lang}/docs/selection/">{f['readLink']}{icon('arrow')}</a></div><div class="reading-illustration" aria-hidden="true"><span class="paper-rule"></span><span class="paper-rule short"></span><p><mark>A world of ideas,<br>one conversation away.</mark></p><div class="mini-result"><span>English → 简体中文</span><p>一个充满想法的世界，<br>只隔着一次对话。</p>{icon('copy')}</div></div></article></div><div class="small-features">{small}</div></section>
<section class="model-section" id="models"><div class="container model-grid"><div><p class="eyebrow">{m['eyebrow']}</p><h2>{m['title']}</h2><p>{m['description']}</p><a class="text-link" href="/{lang}/docs/models/">{m['link']}{icon('arrow')}</a></div><div class="model-options"><article><div class="model-icon">{icon('mac')}</div><div><h3>{m['local']}</h3><p>{m['localText']}</p><span class="provider-label">Ollama · localhost</span></div></article><article><div class="model-icon">{icon('globe')}</div><div><h3>{m['online']}</h3><p>{m['onlineText']}</p><span class="provider-label">OpenAI-compatible API</span></div></article><p class="keychain-note">{icon('lock')}{m['keychain']}</p></div></div></section>
<section class="section container" id="how-it-works"><div class="section-intro"><p class="eyebrow">{s['eyebrow']}</p><h2>{s['title']}</h2></div><div class="steps">{steps}</div><a class="text-link" href="/{lang}/docs/quick-start/">{s['link']}{icon('arrow')}</a></section>
<section class="faq-section container"><h2>{q['title']}</h2><div>{faq}</div></section>
<section class="closing container"><div class="closing-art" aria-hidden="true">Aa<span>あ</span><b>译</b></div><div><h2>{end[0]}</h2><div class="hero-buttons">{button(end[1],REPO,'primary','github')}{button(end[2],f'/{lang}/docs/','text')}</div></div></section>'''
    return shell(lang,'',c['tagline'],h['description'],body)


def download(lang):
    c=COPY[lang]; d=c['download']; r=RELEASE
    steps=''.join(f'<article class="step"><span>0{i+1}</span><h3>{t}</h3><p>{p}</p></article>' for i,(t,p) in enumerate(d['steps']))
    notes=''.join(f'<li>{p}</li>' for p in d['releaseNotes'])
    body=f'''<section class="download-hero container"><div><p class="eyebrow">{d['eyebrow']}</p><h1>{d['title']}</h1><p class="hero-description">{d['description']}</p><a class="text-link" href="/{lang}/docs/quick-start/">{d['guide']}{icon('arrow')}</a></div><div class="download-card"><span class="download-logo">S<span>↗</span></span><span class="pill">{d['label']}</span><h2>SaySpan <span>{r['version']}</span></h2><p>{d['requirements']}</p>{button(d['button'],REPO,'primary','github')}<span class="release-meta">{d['repositoryNote']}</span><a class="text-link" href="#release-notes">{c['footer']['release']}{icon('arrow')}</a></div></section>
<section class="container"><div class="release-notice"><span class="notice-symbol">i</span><div><h2>{d['noticeTitle']}</h2><p>{d['notice']}</p></div></div></section>
<section class="section container"><p class="eyebrow">{d['next']}</p><div class="steps">{steps}</div></section>
<section class="container release-grid"><div id="release-notes"><p class="eyebrow">{r['date']}</p><h2>{d['releaseTitle']}</h2><ul>{notes}</ul></div><div class="checksum-card"><h3>{d['repositoryTitle']}</h3><p>{d['repositoryText']}</p><a class="text-link" href="{REPO}">{icon('github')}Ethan-Infcos / SaySpan{icon('arrow')}</a></div></section>
<section class="container other-platforms"><h3>{d['otherPlatforms']}</h3><p>{d['otherText']}</p></section>'''
    return shell(lang,'download/',c['nav'][3],d['description'],body,'download')


def search(lang):
    d=COPY[lang]['docs']
    return f'<div class="docs-search">{icon("search")}<input type="search" id="docs-search" aria-label="{d["search"]}" placeholder="{d["search"]}" autocomplete="off" aria-controls="search-results" data-empty="{d["noResults"]}"><div class="search-results" id="search-results" aria-live="polite" hidden></div></div>'


def docs(lang, doc=None):
    c=COPY[lang]; d=c['docs']
    if doc is None:
        cards=''.join(f'<a class="guide-card" href="/{lang}/docs/{x["slug"]}/"><span class="guide-number">0{i+1}</span><h2>{x["title"]}</h2><p>{x["summary"]}</p>{icon("arrow")}</a>' for i,x in enumerate(d['items']))
        body=f'<section class="container docs-home"><p class="eyebrow">{d["eyebrow"]}</p><h1>{d["title"]}</h1><p class="hero-description">{d["description"]}</p>{search(lang)}<div class="guide-grid">{cards}</div><p class="meta">{d["version"]}</p></section>'
        return shell(lang,'docs/',c['nav'][2],d['description'],body,'docs')
    sidebar=''.join(f'<a href="/{lang}/docs/{x["slug"]}/"'+(' aria-current="page"' if x['slug']==doc['slug'] else '')+f'>{x["title"]}</a>' for x in d['items'])
    toc=''.join(f'<a href="#{sid}">{title}</a>' for sid,title,_ in doc['sections'])
    sections=''.join(f'<section id="{sid}"><h2>{title}</h2>{rich(text)}</section>' for sid,title,text in doc['sections'])
    idx=d['items'].index(doc); nxt=d['items'][(idx+1)%len(d['items'])]
    body=f'''<div class="container doc-layout"><aside class="docs-sidebar"><a class="docs-back" href="/{lang}/docs/">← {d['back']}</a>{search(lang)}<nav aria-label="{c['nav'][2]}">{sidebar}</nav><p class="meta">{d['version']}</p></aside><article class="doc-article"><p class="eyebrow">{d['guideLabel']}</p><h1>{doc['title']}</h1><p class="doc-lead">{doc['summary']}</p><details class="mobile-toc"><summary>{d['contents']}</summary>{toc}</details>{sections}<a class="next-guide" href="/{lang}/docs/{nxt['slug']}/"><span>{d['next']}</span><strong>{nxt['title']}{icon('arrow')}</strong></a></article><aside class="toc"><span>{d['contents']}</span><nav>{toc}</nav></aside></div>'''
    return shell(lang,f'docs/{doc["slug"]}/',doc['title'],doc['summary'],body,'docs')


def write(route, content):
    p=OUT/route/'index.html';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(content)


def main():
    OUT.mkdir(exist_ok=True)
    assets=OUT/'assets';assets.mkdir(exist_ok=True)
    for p in (ROOT/'src/assets').iterdir():
        if p.suffix in ('.css','.js'):
            target=f'{p.stem}.{hashlib.sha256(p.read_bytes()).hexdigest()[:10]}{p.suffix}';ASSETS[p.name]=target
        else:target=p.name
        shutil.copy2(p,assets/target)
    routes=[]
    for lang in COPY:
        write(lang,home(lang));routes.append(f'/{lang}/')
        write(f'{lang}/download',download(lang));routes.append(f'/{lang}/download/')
        write(f'{lang}/docs',docs(lang));routes.append(f'/{lang}/docs/')
        index=[]
        for item in COPY[lang]['docs']['items']:
            route=f'/{lang}/docs/{item["slug"]}/'
            write(route.strip('/'),docs(lang,item));routes.append(route)
            text=' '.join(title+' '+re.sub('<[^>]+>',' ',body) for _,title,body in item['sections'])
            index.append({'url':route,'title':item['title'],'summary':item['summary'],'text':html.unescape(text)})
        (assets/f'search-{lang}.json').write_text(json.dumps(index,ensure_ascii=False))
    root=home('en').replace('data-locale="en"','data-locale="en" data-language-entry="true"',1)
    write('',root)
    (OUT/'404.html').write_text(shell('en','','Page not found','Find your way back to SaySpan.', '<section class="container not-found"><p class="eyebrow">404</p><h1>A little lost<br>in navigation.</h1><p>This page doesn’t exist. / 此页面不存在。</p>'+button('SaySpan → English','/en/')+button('SaySpan → 简体中文','/zh/','secondary')+'</section>'))
    (OUT/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: '+BASE+'/sitemap.xml\n')
    (OUT/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join(f'<url><loc>{BASE}{route}</loc></url>' for route in routes)+'</urlset>\n')
    print(f'Built {len(routes)} localized pages, root entry and 404. Download actions point to GitHub.')


if __name__=='__main__':main()
