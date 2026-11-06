const sidebar = document.querySelector('.sidebar');
const menu = document.querySelector('.menu-button');
const search = document.querySelector('#search');
const results = document.querySelector('.search-results');
let indexPromise;
const compactLayout = window.matchMedia('(max-width:720px)');
const placeResults = () => {
  if (compactLayout.matches) search.after(results);
  else document.querySelector('.article').prepend(results);
};
compactLayout.addEventListener('change', placeResults);
placeResults();
menu.addEventListener('click', () => {
  const open = sidebar.classList.toggle('open');
  menu.setAttribute('aria-expanded', String(open));
  if (open) search.focus();
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    sidebar.classList.remove('open');
    menu.setAttribute('aria-expanded', 'false');
    results.hidden = true;
    search.value = '';
  }
});
search.addEventListener('input', async () => {
  const query = search.value.trim().toLocaleLowerCase('ru');
  results.replaceChildren();
  results.hidden = query.length < 2;
  if (results.hidden) return;
  indexPromise ??= fetch('search-index.json').then((response) => {
    if (!response.ok) throw new Error('search unavailable');
    return response.json();
  });
  try {
    const index = await indexPromise;
    if (search.value.trim().toLocaleLowerCase('ru') !== query) return;
    const words = query.split(/\s+/);
    const matches = index.filter((page) => words.every((word) => page.text.toLocaleLowerCase('ru').includes(word)))
      .sort((a, b) => Number(b.title.toLocaleLowerCase('ru').includes(query)) - Number(a.title.toLocaleLowerCase('ru').includes(query)));
    const heading = document.createElement('h2');
    heading.textContent = matches.length ? 'Найдено в документации' : 'Ничего не найдено';
    results.append(heading);
    for (const page of matches.slice(0, 8)) {
      const link = document.createElement('a');
      link.href = page.url;
      const title = document.createElement('strong');
      title.textContent = page.title;
      const excerpt = document.createElement('span');
      const position = page.text.toLocaleLowerCase('ru').indexOf(words[0]);
      const start = Math.max(0, position - 45);
      excerpt.textContent = (start ? '…' : '') + page.text.slice(start, start + 160) + '…';
      link.append(title, excerpt);
      results.append(link);
    }
    if (!matches.length) {
      const help = document.createElement('p');
      help.textContent = 'Попробуйте другое слово: например, «уведомления», «установка» или «банки».';
      results.append(help);
    }
  } catch {
    indexPromise = undefined;
    const message = document.createElement('p');
    message.textContent = 'Не удалось загрузить поиск. Выберите раздел в меню или обновите страницу.';
    results.append(message);
  }
});
