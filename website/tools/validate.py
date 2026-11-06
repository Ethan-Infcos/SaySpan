#!/usr/bin/env python3
"""Validate generated pages, localized routes, local links and download integrity."""
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist'


class Page(HTMLParser):
    def __init__(self,path):
        super().__init__();self.path=path;self.ids=set();self.refs=[];self.h1=0;self.lang=None;self.canonical=None;self.alternates={};self.title=False
        self.feed(path.read_text())
    def handle_starttag(self,tag,attributes):
        a=dict(attributes)
        if 'id' in a:
            assert a['id'] not in self.ids, f'Duplicate ID {a["id"]}: {self.path}'
            self.ids.add(a['id'])
        if tag=='html':self.lang=a.get('lang')
        if tag=='h1':self.h1+=1
        if tag=='title':self.title=True
        if tag=='a' and a.get('href'):self.refs.append(a['href'])
        if tag in ('script','img') and a.get('src'):self.refs.append(a['src'])
        if tag=='link':
            if a.get('rel') in ('icon','stylesheet'):self.refs.append(a['href'])
            if a.get('rel')=='canonical':self.canonical=a['href']
            if a.get('rel')=='alternate':self.alternates[a['hreflang']]=a['href']
        if tag=='button':assert a.get('type')!='submit', 'No forms expected'


pages={p.resolve():Page(p) for p in OUT.rglob('*.html')}
count=0
for path,page in pages.items():
    assert page.h1==1 and page.title and page.canonical, f'Missing page metadata: {path}'
    assert page.lang in ('en','zh-Hans')
    rel=path.relative_to(OUT).as_posix()
    if rel.startswith('zh/'):assert page.lang=='zh-Hans'
    if rel.startswith('en/'):assert page.lang=='en'
    assert {'en','zh-Hans','x-default'}==set(page.alternates)
    base='https://sayspan.com/'+rel.removesuffix('index.html')
    for ref in page.refs+list(page.alternates.values()):
        parsed=urlsplit(urljoin(base,ref))
        if parsed.netloc!='sayspan.com':continue
        target=OUT/unquote(parsed.path.lstrip('/'))
        if target.is_dir():target=target/'index.html'
        assert target.is_file(), f'Broken link {ref} in {rel}'
        if parsed.fragment and target.suffix=='.html':
            assert unquote(parsed.fragment) in pages[target.resolve()].ids, f'Broken fragment {ref} in {rel}'
        count+=1
    text=path.read_text()
    assert '/Users/' not in text and 'API_KEY_LOCAL' not in text and 'Vokira' not in text
    assert 'style=' not in text and 'onclick=' not in text, 'CSP does not allow inline scripts/styles'
for lang in ('en','zh'):
    data=json.loads((OUT/'assets'/f'search-{lang}.json').read_text())
    assert len(data)==7
    for entry in data:assert (OUT/entry['url'].strip('/')/'index.html').is_file()
repo=json.loads((ROOT/'site.json').read_text())['repository']
assert not (OUT/'downloads').exists(), 'Direct installer distribution is disabled'
assert not list(OUT.rglob('*.dmg')), 'Installers must not be published with the website'
for page in pages.values():
    assert repo in page.refs, 'Every page must provide a GitHub link'
    assert '/downloads/' not in page.path.read_text()
    assert '{repository}' not in page.path.read_text()
assert (OUT/'assets/social.png').is_file()
print(f'PASS: {len(pages)} pages; {count} internal links/assets/anchors; both search indexes; GitHub links; no hosted installers; localized metadata and CSP compatibility.')
