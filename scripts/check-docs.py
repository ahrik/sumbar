#!/usr/bin/env python3
"""Check actual generated pages, fragments, assets, and the search catalogue."""
from html.parser import HTMLParser
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parent.parent / 'temp' / 'site'


class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        for name in ('href', 'src'):
            if name in attrs:
                self.links.append(attrs[name])


pages = {}
for page in root.glob('*.html'):
    parser = Links(); parser.feed(page.read_text()); pages[page] = parser
count = 0
for page, parser in pages.items():
    for link in parser.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        target = (page.parent / unquote(url.path)).resolve() if url.path else page
        assert target.is_relative_to(root), f'Link outside site: {page.name}: {link}'
        assert target.exists(), f'Missing target: {page.name}: {link}'
        if url.fragment and target in pages:
            assert unquote(url.fragment) in pages[target].ids, f'Missing fragment: {page.name}: {link}'
        count += 1
search = json.loads((root / 'search-index.json').read_text())
assert len(search) == len(pages) >= 10
assert any('уведомления' in item['text'].lower() for item in search)
assert all((root / item['url']).exists() for item in search)
assert 'releases/latest/download/Sumbar.dmg' in (root / 'index.html').read_text()
print(f'Checked {len(pages)} pages, {count} local links/assets/fragments, and full-text search data.')
