// Ícones em traço (24x24) — conjunto próprio, inspirado no estilo "outline"
import { html } from '/shared/vendor/preact-htm.js';

const P = {
  camera: 'M3 8.5A2.5 2.5 0 0 1 5.5 6h1.8l1.4-2h6.6l1.4 2h1.8A2.5 2.5 0 0 1 21 8.5v9a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z|M12 16.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z',
  cameraPlus: 'M3 8.5A2.5 2.5 0 0 1 5.5 6h1.8l1.4-2h6.6l1.4 2h1.8A2.5 2.5 0 0 1 21 8.5v9a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z|M12 10v6|M9 13h6',
  mic: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z|M5 11a7 7 0 0 0 14 0|M12 18v3',
  video: 'M3 7.5A1.5 1.5 0 0 1 4.5 6h10A1.5 1.5 0 0 1 16 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-10A1.5 1.5 0 0 1 3 16.5z|M16 10.5l5-3v9l-5-3',
  image: 'M4 5h16v14H4z|M4 16l5-5 4 4 2-2 5 5|M15.5 9.5a1.5 1.5 0 1 0 0-.01',
  plus: 'M12 5v14|M5 12h14',
  plusCircle: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z|M12 8v8|M8 12h8',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  checkCircle: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z|M8 12.5l3 3 5-6',
  x: 'M6 6l12 12|M18 6L6 18',
  trash: 'M4 7h16|M10 11v6|M14 11v6|M6 7l1 13h10l1-13|M9 7V4h6v3',
  edit: 'M4 20h4L19 9l-4-4L4 16z|M13.5 6.5l4 4',
  left: 'M15 5l-7 7 7 7',
  right: 'M9 5l7 7-7 7',
  down: 'M5 9l7 7 7-7',
  up: 'M5 15l7-7 7 7',
  arrowRight: 'M5 12h14|M13 6l6 6-6 6',
  arrowLeft: 'M19 12H5|M11 6l-6 6 6 6',
  home: 'M3 11l9-7 9 7|M5 10v10h5v-6h4v6h5V10',
  list: 'M8 6h12|M8 12h12|M8 18h12|M4 6h.01|M4 12h.01|M4 18h.01',
  clipboard: 'M9 4h6v3H9z|M7 5H5v16h14V5h-2|M8.5 12h7|M8.5 16h5',
  sync: 'M20 11a8 8 0 0 0-14.3-4.9L4 8|M4 4v4h4|M4 13a8 8 0 0 0 14.3 4.9L20 16|M20 20v-4h-4',
  cloud: 'M7 18a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 9.5a4.2 4.2 0 0 1-.5 8.5z|M12 11v6|M9.5 13.5L12 11l2.5 2.5',
  cloudOff: 'M3 3l18 18|M8 8.4A6 6 0 0 0 6.4 9 4.5 4.5 0 0 0 7 18h10|M11 6a6 6 0 0 1 7 3.5 4.2 4.2 0 0 1 2.3 6.8',
  headset: 'M4 14v-2a8 8 0 0 1 16 0v2|M4 14h3v6H5a1 1 0 0 1-1-1z|M20 14h-3v6h2a1 1 0 0 0 1-1z',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z|M4 21a8 8 0 0 1 16 0',
  users: 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z|M2 21a7 7 0 0 1 14 0|M16 3.5a4 4 0 0 1 0 7.5|M18 14a6 6 0 0 1 4 6',
  search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z|M20 20l-4-4',
  file: 'M6 3h8l5 5v13H6z|M14 3v5h5|M9 13h7|M9 17h5',
  sparkles: 'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z|M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z',
  pin: 'M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z|M12 12a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
  target: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z|M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z|M12 12.01V12',
  bolt: 'M13 2L4 14h7l-1 8 9-12h-7z',
  drop: 'M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z',
  flame: 'M12 22a7 7 0 0 0 7-7c0-4-3-6-4-10-1.5 2-2 3.5-2 5-1.5-1-2.5-2.5-2.5-4C7.5 8 5 11 5 15a7 7 0 0 0 7 7z',
  shield: 'M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6z|M9 12l2 2 4-4',
  alert: 'M12 3l10 18H2z|M12 10v5|M12 18v.01',
  play: 'M7 4.5v15l13-7.5z',
  pause: 'M7 5h3v14H7z|M14 5h3v14h-3z',
  stop: 'M6 6h12v12H6z',
  grip: 'M9 6h.01|M15 6h.01|M9 12h.01|M15 12h.01|M9 18h.01|M15 18h.01',
  door: 'M5 21V4a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v17|M3 21h18|M15 12h.01',
  key: 'M8 15a4 4 0 1 0 0-8 4 4 0 0 0 0 8z|M11 11h10|M18 11v3|M15 11v2',
  undo: 'M9 14L4 9l5-5|M4 9h11a5 5 0 0 1 0 10h-3',
  logout: 'M15 4h4v16h-4|M10 8l-4 4 4 4|M6 12h11',
  info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z|M12 11v5|M12 8v.01',
  wave: 'M4 12h.01|M8 8v8|M12 5v14|M16 8v8|M20 12h.01',
  menu: 'M4 6h16|M4 12h16|M4 18h16',
  dots: 'M12 6h.01|M12 12h.01|M12 18h.01',
  box: 'M3 7l9-4 9 4-9 4z|M3 7v10l9 4 9-4V7|M12 11v10',
  building: 'M4 21V5l8-2v18|M12 7l8 2v12|M2 21h20|M7 8h2|M7 12h2|M7 16h2|M15 12h2|M15 16h2',
  house: 'M4 10l8-6 8 6v10H4z|M10 20v-6h4v6',
  layers: 'M12 3l9 5-9 5-9-5z|M3 13l9 5 9-5',
  calendar: 'M4 6h16v15H4z|M4 10h16|M8 3v5|M16 3v5',
  whatsapp: 'M4 20l1.3-4A8 8 0 1 1 8 18.7z|M9 8.5c0 3.5 3 6.5 6.5 6.5l1-1.5-2-1-1 1c-1.2-.5-2.5-1.8-3-3l1-1-1-2z',
  mail: 'M3 6h18v12H3z|M3 7l9 6 9-6',
  send: 'M21 3L10 14|M21 3l-7 18-4-7-7-4z',
  eye: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z|M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  flip: 'M4 12a8 8 0 0 1 14-5.3L20 9|M20 4v5h-5|M20 12a8 8 0 0 1-14 5.3L4 15|M4 20v-5h5',
  zap: 'M13 2L4 14h7l-1 8 9-12h-7z',
  star: 'M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z',
  copy: 'M8 8h12v12H8z|M4 16V4h12',
  link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1|M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
};

export function Icon({ name, size = 20, stroke = 2, cls = '', fill = false }) {
  const d = P[name] || P.info;
  return html`<svg class=${'ic ' + cls} width=${size} height=${size} viewBox="0 0 24 24" fill=${fill ? 'currentColor' : 'none'} stroke="currentColor" stroke-width=${stroke} stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d.split('|').map((p) => html`<path d=${p} />`)}</svg>`;
}

// 24/10: o logo da Imob Easy em todo lugar (branco nos fundos escuros); size = altura em px
export function Logo({ size = 34, dark = false }) {
  return html`<img class="logo-ie" src=${dark ? '/shared/logo-imobeasy-branco.svg' : '/shared/logo-imobeasy.svg'} alt="Imob Easy" style=${`height:${size}px;width:auto`} />`;
}
