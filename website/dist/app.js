'use strict';
(() => {
  // Release assets verified against GitHub on 2026-11-15. Update together on a new release.
  const release = { version: '0.2.0', bytes: 48606600, page: 'https://github.com/neosay-dev/horizon-ios/releases/tag/ios-v0.2.0', ipa: 'https://github.com/neosay-dev/horizon-ios/releases/download/ios-v0.2.0/Horizon-0.2.0.ipa' };
  const texts = window.HORIZON_TEXT;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const animations = new Set();
  const onElement = new WeakMap();
  let lang = 'ru', screen = 'gameplay';
  const image = document.getElementById('game-screenshot');
  const dialog = document.getElementById('image-dialog');
  const status = document.getElementById('status');
  const languageButton = document.querySelector('[data-language]');
  const t = key => texts[lang][key] || texts.ru[key] || key;
  const load = key => { try { return localStorage.getItem(key); } catch { return null; } };
  const save = (key, value) => { try { localStorage.setItem(key, value); } catch { /* Preferences are optional. */ } };
  function animate(element, frames = [{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'translateY(0)' }], duration = 240) {
    onElement.get(element)?.cancel();
    if (reduced.matches || typeof element.animate !== 'function') return;
    const a = element.animate(frames, { duration, easing: 'cubic-bezier(.23, 1, .32, 1)' });
    onElement.set(element, a); animations.add(a);
    a.finished.then(() => animations.delete(a), () => animations.delete(a));
    return a;
  }
  const header = document.querySelector('.site-header');
  const updateHeader = () => header.classList.toggle('is-scrolled', window.scrollY > 8);
  window.addEventListener('scroll', updateHeader, { passive: true });
  updateHeader();
  const menuButton = document.querySelector('.mobile-menu-toggle');
  const mobileNav = document.getElementById('mobile-nav');
  if (menuButton && mobileNav) {
    mobileNav.innerHTML = document.querySelector('.desktop-nav').innerHTML;
    menuButton.hidden = false;
    const setMenu = open => {
      mobileNav.hidden = !open;
      header.classList.toggle('menu-open', open);
      document.documentElement.classList.toggle('menu-open', open);
      menuButton.setAttribute('aria-expanded', String(open));
      menuButton.setAttribute('aria-label', t(open ? 'menuClose' : 'menuLabel'));
      menuButton.querySelector('use').setAttribute('href', open ? '#close' : '#menu');
    };
    const menuViewport = matchMedia('(max-width: 1100px)');
    menuViewport.addEventListener('change', () => { if (!menuViewport.matches) setMenu(false); });
    mobileNav.addEventListener('click', event => { if (event.target === mobileNav) setMenu(false); });
    menuButton.addEventListener('click', () => setMenu(menuButton.getAttribute('aria-expanded') !== 'true'));
    mobileNav.querySelectorAll('a').forEach(link => link.addEventListener('click', () => setMenu(false)));
    document.addEventListener('pointerdown', event => { if (!header.contains(event.target)) setMenu(false); });
    document.addEventListener('keydown', event => { if (event.key === 'Escape' && !mobileNav.hidden) { setMenu(false); menuButton.focus(); } });
  }
  const cancelMotion = () => [...animations].forEach(a => a.cancel());
  reduced.addEventListener('change', () => { if (reduced.matches) cancelMotion(); });
  window.addEventListener('beforeprint', cancelMotion);
  function translate() {
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(e => { e.textContent = t(e.dataset.i18n); });
    document.querySelectorAll('[data-i18n-aria]').forEach(e => { e.setAttribute('aria-label', t(e.dataset.i18nAria)); });
    document.querySelectorAll('[data-i18n-alt]').forEach(e => { e.alt = t(e.dataset.i18nAlt); });
    languageButton.textContent = lang === 'ru' ? 'EN' : 'RU';
    languageButton.setAttribute('aria-label', t('switchLanguage'));
    document.title = t(document.body.dataset.page === 'install' ? 'installPageTitle' : 'pageTitle');
    document.querySelector('meta[name="description"]').content = t('description');
    document.querySelector('[data-release-label]').textContent = `v${release.version} · ${new Intl.NumberFormat(lang, { maximumFractionDigits: 1 }).format(release.bytes / 1e6)} ${t('megabytes')}`;
    if (menuButton) menuButton.setAttribute('aria-label', t(menuButton.getAttribute('aria-expanded') === 'true' ? 'menuClose' : 'menuLabel'));
    updateDialog();
  }
  function updateDialog() {
    if (!image || !dialog) return;
    const target = document.getElementById('dialog-image');
    target.src = image.src; target.alt = image.alt;
    document.getElementById('dialog-label').textContent = t(`${screen}Caption`);
  }
  function selectScreen(next) {
    if (!image) return;
    if (!['gameplay', 'settings'].includes(next) || next === screen) return;
    screen = next;
    document.querySelectorAll('[data-screen]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.screen === screen)));
    image.dataset.i18nAlt = `${screen}Alt`; image.alt = t(`${screen}Alt`);
    const caption = document.getElementById('screen-caption'); caption.dataset.i18n = `${screen}Caption`; caption.textContent = t(`${screen}Caption`);
    document.querySelector('[data-screen-link]').href = `assets/${screen}.jpg`;
    image.src = `assets/${screen}.jpg`;
    updateDialog();
  }
  image?.addEventListener('load', () => animate(image, [{ opacity: .45 }, { opacity: 1 }], 240));
  document.querySelectorAll('[data-screen]').forEach(b => b.addEventListener('click', () => selectScreen(b.dataset.screen)));
  function selectMethod(next, motion = true) {
    if (!['source', 'manual'].includes(next)) return;
    document.querySelectorAll('[data-method]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.method === next)));
    document.querySelectorAll('[data-method-panel]').forEach(panel => { panel.hidden = panel.dataset.methodPanel !== next; if (!panel.hidden && motion) animate(panel); });
    save('horizon-ios-install-method', next);
  }
  document.querySelectorAll('[data-method]').forEach(b => b.addEventListener('click', () => selectMethod(b.dataset.method)));
  document.querySelectorAll('[data-ipa-link]').forEach(a => { a.href = release.ipa; });
  document.querySelector('[data-release-link]').href = release.page;
  languageButton.hidden = false;
  languageButton.addEventListener('click', () => { lang = lang === 'ru' ? 'en' : 'ru'; save('horizon-ios-language', lang); translate(); });
  if (load('horizon-ios-language') === 'en') lang = 'en';
  document.documentElement.classList.add('js');
  translate(); selectMethod(load('horizon-ios-install-method') || 'source', false);
  const screenPicker = document.querySelector('.screen-picker');
  if (screenPicker) screenPicker.hidden = false;
  const installPicker = document.querySelector('.install-picker');
  if (installPicker) installPicker.hidden = false;
  document.querySelectorAll('[data-copy]').forEach(button => {
    button.hidden = false;
    button.addEventListener('click', async () => {
      const input = document.getElementById(button.dataset.copy);
      try {
        if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(input.value);
        document.getElementById('copy-feedback').dataset.i18n = 'copied'; document.getElementById('copy-feedback').textContent = t('copied'); status.textContent = t('copied');
      } catch {
        input.focus(); input.select();
        document.getElementById('copy-feedback').dataset.i18n = 'copyFallback'; document.getElementById('copy-feedback').textContent = t('copyFallback'); status.textContent = t('copyFallback');
      }
    });
  });
  document.querySelectorAll('[data-screen-link], [data-preview]').forEach(link => link.addEventListener('click', event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || !dialog || typeof dialog.showModal !== 'function') return;
    event.preventDefault();
    if (link.dataset.preview) selectScreen(link.dataset.preview);
    updateDialog(); dialog.showModal(); animate(dialog, undefined, 200);
  }));
  if (dialog) {
    document.querySelector('[data-close]').addEventListener('click', () => dialog.close());
    dialog.addEventListener('click', event => { const r = dialog.getBoundingClientRect(); if (event.target === dialog && (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom)) dialog.close(); });
    dialog.addEventListener('keydown', event => { if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { event.preventDefault(); selectScreen(screen === 'gameplay' ? 'settings' : 'gameplay'); } });
  }
  document.querySelectorAll('.faq-list details, .status-columns details').forEach(details => {
    const summary = details.querySelector('summary'); let active = null, expanded = details.open, revision = 0;
    summary.addEventListener('click', event => {
      if (reduced.matches || typeof details.animate !== 'function') return;
      event.preventDefault(); const next = !(active ? expanded : details.open), height = details.getBoundingClientRect().height, current = ++revision;
      active?.cancel(); expanded = next; details.open = true; details.style.overflow = 'hidden'; summary.setAttribute('aria-expanded', String(next));
      const target = next ? details.offsetHeight : summary.offsetHeight + 1;
      active = animate(details, [{ height: `${height}px` }, { height: `${target}px` }], 240);
      const settle = () => { if (revision !== current) return; details.open = expanded; details.style.overflow = ''; summary.removeAttribute('aria-expanded'); active = null; };
      if (active) active.finished.then(settle, settle); else settle();
    });
  });
  const creditTitle = document.querySelector('.contributors-title');
  const creditTrigger = document.querySelector('.contributors-trigger');
  const creditHint = document.getElementById('claude-credit');
  if (creditTitle && creditTrigger && creditHint) {
  let creditPinned = false;
  const showCredit = open => {
    creditTitle.classList.toggle('is-credit-open', open);
    creditTrigger.setAttribute('aria-expanded', String(open));
    creditHint.setAttribute('aria-hidden', String(!open));
  };
  creditTrigger.addEventListener('pointerenter', () => showCredit(true));
  creditTrigger.addEventListener('pointerleave', () => { if (!creditPinned && !creditTrigger.matches(':focus-visible')) showCredit(false); });
  creditTrigger.addEventListener('focus', () => showCredit(true));
  creditTrigger.addEventListener('blur', () => { if (!creditPinned && !creditTrigger.matches(':hover')) showCredit(false); });
  creditTrigger.addEventListener('click', () => { creditPinned = !creditPinned; showCredit(creditPinned); });
  document.addEventListener('pointerdown', event => { if (!creditTitle.contains(event.target)) { creditPinned = false; showCredit(false); } });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') { creditPinned = false; showCredit(false); } });
  }
  if ('IntersectionObserver' in window && !reduced.matches) {
    const observer = new IntersectionObserver(entries => entries.forEach(entry => { if (entry.isIntersecting) { animate(entry.target, undefined, 600); observer.unobserve(entry.target); } }), { threshold: .08 });
    document.querySelectorAll('.about-heading, .about-description, .about-image, .feature-list > div, .source-banner, .community-content, .screenshots, .contributors, .port-status, .installation, .faq').forEach(e => observer.observe(e));
    reduced.addEventListener('change', () => { if (reduced.matches) observer.disconnect(); });
  }
})();
