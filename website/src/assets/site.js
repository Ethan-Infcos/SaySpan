'use strict';

const root = document.documentElement;
const locale = root.dataset.locale;
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
if (root.dataset.languageEntry) {
  let preferred;
  try { preferred = localStorage.getItem('sayspan.language'); } catch (_) { /* Storage is optional. */ }
  if (!['en', 'zh'].includes(preferred)) preferred = (navigator.language || '').startsWith('zh') ? 'zh' : 'en';
  location.replace(`/${preferred}/${location.search}${location.hash}`);
}

document.querySelectorAll('[data-language]').forEach(link => {
  link.addEventListener('click', () => {
    try { localStorage.setItem('sayspan.language', link.dataset.language); } catch (_) { /* Navigation still works. */ }
    if (location.hash) link.hash = location.hash;
  });
});

const menu = document.querySelector('.menu-toggle');
menu?.addEventListener('click', () => {
  const open = menu.getAttribute('aria-expanded') !== 'true';
  menu.setAttribute('aria-expanded', String(open));
  document.querySelector('.main-nav').classList.toggle('is-open', open);
});
document.querySelectorAll('.main-nav a').forEach(link => link.addEventListener('click', () => {
  menu?.setAttribute('aria-expanded', 'false');
  document.querySelector('.main-nav').classList.remove('is-open');
}));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    menu?.setAttribute('aria-expanded', 'false');
    document.querySelector('.main-nav')?.classList.remove('is-open');
    const results = document.querySelector('#search-results');
    if (results) results.hidden = true;
  }
});

document.querySelectorAll('[data-demo]').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('[data-demo]').forEach(tab => tab.setAttribute('aria-pressed', String(tab === button)));
  const reading = button.dataset.demo === 'read';
  document.querySelector('.demo-write').hidden = reading;
  document.querySelector('.demo-read').hidden = !reading;
}));

const examples = [
  ['我们明天上午十点见。', 'Let’s meet tomorrow at 10 AM.'],
  ['谢谢你的耐心，我很快回复你。', 'Thank you for your patience. I’ll get back to you soon.'],
  ['这个想法很有意思，我们试试吧。', 'That’s an interesting idea. Let’s give it a try.']
];
let exampleIndex = 0;
document.querySelector('[data-example-next]')?.addEventListener('click', () => {
  exampleIndex = (exampleIndex + 1) % examples.length;
  const [source, target] = examples[exampleIndex];
  document.querySelector('[data-demo-source]').textContent = source;
  document.querySelector('[data-demo-target]').textContent = target;
  const inserted = document.querySelector('.demo-inserted');
  inserted.replaceChildren(document.createTextNode(target));
  const caret = document.createElement('span'); caret.className = 'cursor'; inserted.append(caret);
  if (!reducedMotion) document.querySelector('.composition-card').animate([{opacity: .45, transform: 'translateY(4px)'}, {opacity: 1, transform: 'translateY(0)'}], {duration: 250});
});

let toastTimer;
document.querySelectorAll('[data-copy]').forEach(button => button.addEventListener('click', async () => {
  const toast = document.querySelector('.toast');
  try {
    await navigator.clipboard.writeText(button.dataset.copy);
    toast.textContent = toast.dataset.success;
  } catch (_) {
    toast.textContent = toast.dataset.failure;
  }
  clearTimeout(toastTimer); toast.classList.add('visible');
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 3000);
}));

const search = document.querySelector('#docs-search');
let searchData;
let searchPromise;
async function loadIndex() {
  if (!searchPromise) searchPromise = fetch(`/assets/search-${locale}.json`).then(response => {
    if (!response.ok) throw new Error('Search index unavailable');
    return response.json();
  }).then(data => { searchData = data; return data; }).catch(error => { searchPromise = undefined; throw error; });
  return searchPromise;
}
search?.addEventListener('focus', () => { loadIndex().catch(() => {}); });
search?.addEventListener('input', async () => {
  const query = search.value.trim().toLocaleLowerCase();
  const results = document.querySelector('#search-results');
  if (!query) { results.hidden = true; results.replaceChildren(); return; }
  try {
    const data = searchData || await loadIndex();
    if (query !== search.value.trim().toLocaleLowerCase()) return;
    const terms = query.split(/\s+/);
    const matches = data.filter(item => terms.every(term => `${item.title} ${item.summary} ${item.text}`.toLocaleLowerCase().includes(term))).slice(0, 7);
    results.replaceChildren(); results.hidden = false;
    if (!matches.length) { const p = document.createElement('p'); p.textContent = search.dataset.empty; results.append(p); }
    matches.forEach(item => {
      const link = document.createElement('a'); link.href = item.url;
      const title = document.createElement('strong'); title.textContent = item.title;
      const summary = document.createElement('span'); summary.textContent = item.summary;
      link.append(title, summary); results.append(link);
    });
  } catch (_) {
    results.hidden = false;
    results.textContent = locale === 'zh' ? '暂时无法加载搜索，请使用下方的指南链接。' : 'Search is unavailable. Please use the guide links below.';
  }
});
document.addEventListener('click', event => {
  if (!event.target.closest('.docs-search')) {
    const results = document.querySelector('#search-results'); if (results) results.hidden = true;
  }
});

if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) {
      document.querySelectorAll('.toc a').forEach(link => {
        if (link.hash === '#' + entry.target.id) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }
  }, {rootMargin: '-15% 0px -65% 0px'});
  document.querySelectorAll('.doc-article section[id]').forEach(section => observer.observe(section));
}
