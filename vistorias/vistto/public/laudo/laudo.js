(function () {
  // Abas
  const tabs = document.querySelectorAll('#tabs button');
  function show(name) {
    tabs.forEach((b) => b.classList.toggle('on', b.dataset.tab === name));
    document.querySelectorAll('.pane').forEach((p) => p.classList.toggle('on', p.id === 'tab-' + name));
  }
  tabs.forEach((b) => b.addEventListener('click', () => { show(b.dataset.tab); history.replaceState(null, '', b.dataset.tab === 'laudo' ? location.pathname : '#' + b.dataset.tab); window.scrollTo({ top: 0, behavior: 'smooth' }); }));
  const h = location.hash.replace('#', '');
  if (h === 'fotos' || h === 'inconf') show(h);
  if (h === 'inconformidades') show('inconf');

  // Compartilhar
  const share = document.getElementById('share');
  if (share) share.addEventListener('click', async () => {
    const data = { title: document.title, url: location.origin + location.pathname };
    if (navigator.share) { try { await navigator.share(data); } catch (e) {} return; }
    try { await navigator.clipboard.writeText(data.url); share.textContent = 'Link copiado ✔'; setTimeout(() => location.reload(), 1500); } catch (e) { prompt('Copie o link:', data.url); }
  });

  // Lightbox com navegação
  const lb = document.getElementById('lb');
  if (!lb) return;
  const box = lb.querySelector('.lbc'), cap = lb.querySelector('.lbcap');
  let list = [], idx = 0;
  function open(i) {
    idx = (i + list.length) % list.length;
    const f = list[idx];
    const marks = f.querySelector('.imgw') ? Array.from(f.querySelectorAll('.mk')).map((m) => m.outerHTML).join('') : '';
    box.innerHTML = f.dataset.kind === 'video' ? `<video src="${f.dataset.full}" controls autoplay playsinline></video>` : `<div class="imgw"><img src="${f.dataset.full}">${marks}</div>`;
    const dt = f.querySelector('.dt');
    cap.textContent = [f.dataset.cap, dt && dt.textContent].filter(Boolean).join(' · ') + `  (${idx + 1}/${list.length})`;
    lb.classList.add('on');
  }
  document.addEventListener('click', (e) => {
    const f = e.target.closest('.ph');
    if (!f) return;
    const pane = f.closest('.pane');
    list = Array.from((pane || document).querySelectorAll('.ph'));
    open(list.indexOf(f));
  });
  const close = () => { lb.classList.remove('on'); box.innerHTML = ''; };
  lb.querySelector('.x').onclick = close;
  lb.querySelector('.pv').onclick = (e) => { e.stopPropagation(); open(idx - 1); };
  lb.querySelector('.nx').onclick = (e) => { e.stopPropagation(); open(idx + 1); };
  lb.addEventListener('click', (e) => { if (e.target === lb) close(); });
  document.addEventListener('keydown', (e) => { if (!lb.classList.contains('on')) return; if (e.key === 'Escape') close(); if (e.key === 'ArrowLeft') open(idx - 1); if (e.key === 'ArrowRight') open(idx + 1); });
  let sx = null;
  lb.addEventListener('touchstart', (e) => { sx = e.touches[0].clientX; }, { passive: true });
  lb.addEventListener('touchend', (e) => { if (sx === null) return; const d = e.changedTouches[0].clientX - sx; if (Math.abs(d) > 50) open(idx + (d < 0 ? 1 : -1)); sx = null; });
})();
