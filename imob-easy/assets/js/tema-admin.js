/* MODO ESCURO DO ADMIN (Pedro, 28/10/2026): "põe uma opção lá em cima para ficar tudo escuro: eu clico e o que está
   branco fica escuro e os textos brancos, em todo o site admin, mas por padrão branco, porém eu posso mudar".

   Carregado no <head> de cada página do admin, antes de desenhar: a página já nasce no tema escolhido, sem piscar.
   - Padrão: claro. A escolha fica neste navegador (localStorage "admin-tema" = "escuro" | "claro").
   - Como escurece: o admin tem centenas de cores claras escritas direto nos CSS e nas páginas; trocar só as variáveis
     deixaria ilhas brancas. Por isso a página inteira inverte a luz (filter invert + hue-rotate, que mantém o tom das
     cores) e o que é imagem de verdade (fotos, vídeos, mapas, a prévia da arte no gerador de posts) volta à cor real.
   - Dentro de iframe (o CRM mostra páginas do admin, e o Cadastro rápido abre o editor num popup) não faz nada: quem
     manda é a página de fora. No CRM vale o tema do CRM; no popup, a inversão da página de fora já pega o iframe.
   - O botão entra na barra do topo (layout.js), à esquerda dos outros; página sem barra ganha o botão no canto. */
(function () {
  "use strict";
  if (window.self !== window.top) return;
  var CHAVE = "admin-tema";
  var raiz = document.documentElement;
  // a + v(1-2a) com a = 0,92: o que volta à cor real desfaz isso com hue-rotate + invert(1) + contrast(1/0,84)
  var VOLTA = "hue-rotate(180deg) invert(1) contrast(1.1905)";
  var REAL = "img,video,picture,.leaflet-tile-pane,[style*='background-image']";
  var css =
    "html.admin-escuro{filter:invert(.92) hue-rotate(180deg);background:#fff}" +
    // 31/10 (Pedro: "tá passando um filtro negativo nas minhas imagens quando eu vou olhar elas"): a janela aberta com
    // showModal (o visor de fotos), a tela cheia e o popover são desenhados por cima da página, FORA da inversão do <html>;
    // a foto lá dentro voltava de uma inversão que nunca houve e saía em negativo. Elas ganham a mesma inversão da página.
    "html.admin-escuro :is(dialog:modal,:fullscreen,:popover-open){filter:invert(.92) hue-rotate(180deg)}" +
    "html.admin-escuro.tema-ja-escuro :is(dialog:modal,:fullscreen,:popover-open){filter:none}" +
    "html.admin-escuro :is(" + REAL + "){filter:" + VOLTA + "}" +
    "html.admin-escuro.tema-arte :is(canvas,.preview,.nossos-arte,.slide){filter:" + VOLTA + "}" +
    // o que está dentro de algo que já voltou à cor real não volta de novo
    "html.admin-escuro :is(" + REAL + ",.tema-arte canvas,.tema-arte .preview,.tema-arte .nossos-arte,.tema-arte .slide) :is(img,video,picture,canvas,[style*='background-image']){filter:none}" +
    // página que já é escura de fábrica (o Início): só a barra e o menu do topo escurecem; o painel fica como é
    "html.admin-escuro.tema-ja-escuro{filter:none}" +
    "html.admin-escuro.tema-ja-escuro :is(" + REAL + "){filter:none}" +
    "html.admin-escuro.tema-ja-escuro :is(.barra-topo,.nav-principal){filter:invert(.92) hue-rotate(180deg)}" +
    "html.admin-escuro.tema-ja-escuro :is(.barra-topo,.nav-principal) :is(" + REAL + "){filter:" + VOLTA + "}" +
    "html.admin-escuro .barra-topo__logo img,html.admin-escuro.tema-ja-escuro .barra-topo .barra-topo__logo img{filter:none}" +
    ".tema-botao{display:inline-flex;align-items:center;gap:6px}" +
    ".tema-botao svg{width:15px;height:15px;flex:0 0 auto}" +
    ".tema-botao--solto{position:fixed;left:14px;bottom:14px;z-index:99999;height:36px;padding:0 14px;border-radius:999px;" +
      "border:1px solid #cfcfca;background:#fff;color:#16161a;font:600 13px/1 system-ui,sans-serif;cursor:pointer;" +
      "box-shadow:0 4px 14px rgba(0,0,0,.18)}";

  var estilo = document.createElement("style");
  estilo.id = "tema-admin-css";
  estilo.textContent = css;
  (document.head || raiz).appendChild(estilo);

  function escolhido() {
    try { return localStorage.getItem(CHAVE) === "escuro"; } catch (e) { return false; }
  }
  if (/gerador-posts/.test(location.pathname)) raiz.classList.add("tema-arte");
  if (/\/admin\/(inicio(\.html)?)?$/.test(location.pathname)) raiz.classList.add("tema-ja-escuro");
  raiz.classList.toggle("admin-escuro", escolhido());

  var LUA = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg>';
  var SOL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';

  function pintar(b) {
    var escuro = raiz.classList.contains("admin-escuro");
    b.innerHTML = (escuro ? SOL : LUA) + "<span>" + (escuro ? "Modo claro" : "Modo escuro") + "</span>";
    b.setAttribute("aria-pressed", String(escuro));
    b.title = escuro ? "Voltar ao tema claro" : "Deixar o painel escuro";
  }
  function alternar() {
    var escuro = !raiz.classList.contains("admin-escuro");
    raiz.classList.toggle("admin-escuro", escuro);
    try { localStorage.setItem(CHAVE, escuro ? "escuro" : "claro"); } catch (e) { /* sem storage: vale só nesta tela */ }
    var b = document.getElementById("tema-botao");
    if (b) pintar(b);
  }
  window.temaAdmin = { alternar: alternar };

  function porBotao() {
    if (document.getElementById("tema-botao") || !document.body) return;
    var alvo = document.querySelector(".barra-topo__direita");
    var b = document.createElement("button");
    b.type = "button";
    b.id = "tema-botao";
    b.className = alvo ? "btn-azul-vazado btn-marca tema-botao" : "tema-botao tema-botao--solto";
    pintar(b);
    b.addEventListener("click", alternar);
    if (alvo) alvo.insertBefore(b, alvo.firstChild); else document.body.appendChild(b);
  }
  // a barra do topo nasce no layout.js, no fim do <body>: espera ela, e na página sem barra o botão vai para o canto
  document.addEventListener("DOMContentLoaded", function () {
    porBotao();
    // se a barra chegar depois (script atrasado), o botão muda de lugar
    var obs = new MutationObserver(function () {
      var alvo = document.querySelector(".barra-topo__direita");
      var b = document.getElementById("tema-botao");
      if (alvo && b && b.parentNode !== alvo) { b.remove(); porBotao(); obs.disconnect(); }
    });
    obs.observe(document.body, { childList: true, subtree: true });
    setTimeout(function () { obs.disconnect(); }, 5000);
  });
  // outra aba trocou o tema: esta acompanha
  window.addEventListener("storage", function (e) {
    if (e.key !== CHAVE) return;
    raiz.classList.toggle("admin-escuro", e.newValue === "escuro");
    var b = document.getElementById("tema-botao");
    if (b) pintar(b);
  });
})();
