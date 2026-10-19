/* ==========================================================================
   Imob Easy — Layout compartilhado do sistema
   Monta barra superior, navegação principal e rodapé em todas as telas.
   ========================================================================== */
(function () {
  "use strict";

  var ICONE = {
    inicio:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true">' +
      '<path d="M4 15a8 8 0 0 1 16 0"/><path d="M12 15l4-4"/><circle cx="12" cy="15" r="1.4" fill="currentColor" stroke="none"/></svg>',
    condominios:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true">' +
      '<rect x="4" y="3" width="16" height="18" rx="1.5"/><path d="M8 7h2M14 7h2M8 11h2M14 11h2M8 15h2M14 15h2"/></svg>',
    imoveis:
      '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<path d="M12 3 2.6 11.1a1 1 0 0 0 .66 1.75H5V20a1 1 0 0 0 1 1h4v-5h4v5h4a1 1 0 0 0 1-1v-7.15h1.74a1 1 0 0 0 .66-1.75Z"/></svg>',
    anuncios:
      '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<path d="M3 10v4a1 1 0 0 0 1 1h2l4 4V5L6 9H4a1 1 0 0 0-1 1Zm12.5 2a4 4 0 0 0-2-3.46v6.92A4 4 0 0 0 15.5 12Zm0-7.6v2.1a5.6 5.6 0 0 1 0 11v2.1a7.6 7.6 0 0 0 0-15.2Z"/></svg>',
    proprietarios:
      '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<circle cx="8" cy="9" r="3"/><circle cx="16.5" cy="9.5" r="2.5"/>' +
      '<path d="M2 19c0-3 2.7-5 6-5s6 2 6 5Zm13.2-4.6c2.6.4 4.8 2.2 4.8 4.6h-4.6c0-1.7-.7-3.3-1.8-4.4a7 7 0 0 1 1.6-.2Z"/></svg>',
    clientes:
      '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<path d="M9 4h6a2 2 0 0 1 2 2v1h3a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h3V6a2 2 0 0 1 2-2Zm0 3h6V6H9Z"/></svg>',
    corretores:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<rect x="4" y="5" width="16" height="14" rx="2"/><circle cx="12" cy="10" r="2.2"/>' +
      '<path d="M8 16c.7-1.8 2.2-2.6 4-2.6s3.3.8 4 2.6"/></svg>',
    locacao:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<circle cx="7.5" cy="15.5" r="3.2"/><path d="M9.8 13.2 17.5 5.5l1.5 1.5-1.5 1.5 1.5 1.5-1.5 1.5-5.3 5.3"/></svg>',
    "visao-geral":
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<circle cx="5" cy="12" r="2.5"/><circle cx="19" cy="6" r="2.5"/><circle cx="19" cy="18" r="2.5"/><path d="M7.4 11 16.6 7M7.4 13l9.2 4"/></svg>',
    agentes:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true">' +
      '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/>' +
      '<rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/></svg>',
    captacao:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<path d="M4 4h16v4H4z"/><path d="M6 8v6a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/></svg>',
    grupos:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/><circle cx="9" cy="14.5" r="1.6"/><circle cx="15" cy="14.5" r="1.6"/></svg>',
    vagas:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<rect x="3.5" y="7" width="17" height="12.5" rx="2"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/><path d="M3.5 12.5h17"/></svg>',
    mais:
      '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<path d="M11 4h2v7h7v2h-7v7h-2v-7H4v-2h7Z"/></svg>',
    sino:
      '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true">' +
      '<path d="M18 8a6 6 0 1 0-12 0c0 6-2 7-2 7h16s-2-1-2-7"/><path d="M10.5 20a2 2 0 0 0 3 0"/></svg>',
    folha:
      '<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">' +
      '<path d="M12 2c3 4 6 6 6 10a6 6 0 0 1-12 0c0-4 3-6 6-10Zm0 4.6C10.4 8.7 9 10.1 9 12a3 3 0 0 0 6 0c0-1.9-1.4-3.3-3-5.4Z"/></svg>'
  };

  /* Reestruturado em 04/09/2026: nada apagado, só reorganizado. As seis
     áreas pedidas ficam na navegação principal; o resto (Condomínios,
     Anúncios, Clientes e o que já estava em "Mais") vai pro dropdown "+". */
  var MENU = [
    { chave: "inicio",        rotulo: "Início",           href: "inicio.html" },
    /* 15/10/2026: "Visão geral" era uma página; 18/10 (Pedro: "pega o que tem lá e põe embaixo do dashboard da aba
       início") ela mora dentro de inicio.html. visao-geral.html continua no ar para o CRM (+ Mais > Visão geral). */
    { chave: "imoveis",       rotulo: "Todos os Imóveis", href: "imoveis.html" },
    { chave: "proprietarios", rotulo: "Proprietários",    href: "proprietarios.html" },
    { chave: "corretores",    rotulo: "Corretores",       href: "corretores.html" },
    /* 11/10/2026 (Pedro: "pega a aba Oportunidades e põe como uma tab dentro da aba Captação e troca lá por uma
       aba Agentes"): Agentes = um quadrado por agente da VPS, com o uso por dia (agentes.html). */
    { chave: "agentes",       rotulo: "Agentes",          href: "agentes.html" },
    /* 06/10/2026 (Pedro: "vou reformular o site: pega o Locação e põe dentro de Captação"): Captação abre um
       menu com as páginas; nenhuma delas mudou. Oportunidades é a 4ª aba de captacao.html (11/10). */
    /* 18/10/2026 (Pedro: "o menu do site está bagunçado, tem abas dentro de abas que não aparecem no menu"): cada aba
       da página Captação aparece aqui como filho, com o hash que a abre (captacao-olx.js lê o hash). */
    { chave: "captacao",      rotulo: "Captação",         href: "captacao.html",
      filhos: [{ rotulo: "Captação WhatsApp",   href: "captacao.html",               chave: "captacao" },
               { rotulo: "Captação OLX",        href: "captacao.html#olx",           chave: "captacao-olx" },
               { rotulo: "Imóveis da OLX Bot",  href: "captacao.html#olxbot",        chave: "captacao-olxbot" },
               { rotulo: "Oportunidades",       href: "captacao.html#oportunidades", chave: "oportunidades" },
               { rotulo: "Modelos da campanha", href: "captacao.html#modelos",       chave: "captacao-modelos" },
               { rotulo: "Locação",             href: "locacao.html",                chave: "locacao" }] },
    /* 18/10/2026 (Pedro: "quero uma aba whatsapp onde vai ficar os grupos e as mensagens aprovadas"): WhatsApp junta
       os Grupos (agenda, métricas, captação ativa: grupos.html, 03/10) e as Mensagens (todos os modelos da Meta em
       cards com o mockup, filtráveis e com etiquetas: whatsapp.html). */
    { chave: "whatsapp",      rotulo: "WhatsApp",         href: "whatsapp.html",
      filhos: [{ rotulo: "Mensagens (modelos da Meta)", href: "whatsapp.html",        chave: "whatsapp" },
               { rotulo: "Grupos",                      href: "grupos.html",          chave: "grupos" },
               { rotulo: "Métricas dos grupos",         href: "grupos.html#metricas", chave: "grupos-metricas" },
               { rotulo: "Captação ativa por grupos",   href: "grupos.html#captacao", chave: "grupos-captacao" }] }
    /* Blog (406) e Nova Nay (06/10) foram para o "Mais" em 18/10 (Pedro: "Blog e nova nay põe para dentro do menu mais").
       Clientes e Vagas foram para o "Mais" (Tel, 28/09) */
  ];

  var SUBMENU = [
    /* O SCRAP (407, 18/10/2026; Pedro: "crie um menu lá no menu que desce do site escrito Scrap ... essa aba scrap vai
       ser um grande gerenciador de listas"): listas de nome + telefone (raspagem da OLX, CSV, mão). */
    { rotulo: "Scrap",             href: "scrap.html",       chave: "scrap" },
    /* 18/10/2026 (Pedro: "Blog e nova nay põe para dentro do menu mais") */
    { rotulo: "Blog",              href: "blog.html",        chave: "blog" },
    /* 19/10/2026 (Pedro: "coloca o criador de post no menu lá dentro de Mais"): o gerador de posts de imóvel
       (gerador-posts.html, o mesmo que o `nay posts` roda na VPS) -- página própria, sem o layout do admin */
    { rotulo: "Gerador de posts",  href: "gerador-posts.html", chave: "gerador-posts" },
    { rotulo: "Nova Nay",          href: "nova-nay.html",    chave: "nova-nay" },
    { rotulo: "Visão geral",       href: "visao-geral.html", chave: "visao-geral" },
    { rotulo: "Clientes",          href: "clientes.html",    chave: "clientes" },
    { rotulo: "Vagas",             href: "vagas.html",       chave: "vagas" },
    { rotulo: "Fluxo de mensagens", href: "fluxo.html",      chave: "fluxo" },
    /* a Nay antiga (06/10): as quatro telas da Nay de hoje, num grupo dentro do "Mais" */
    { grupo: "Nay antiga" },
    { rotulo: "Nay Locação",       href: "nay-locacao.html",   chave: "nay-locacao",   recuo: true },
    { rotulo: "Nay Captação",      href: "nay-captacao.html",  chave: "nay-captacao",  recuo: true },
    { rotulo: "Cérebro da Nay",    href: "nay-cerebro.html",   chave: "nay-cerebro",   recuo: true },
    { rotulo: "Estrutura da Nay",  href: "nay-estrutura.html", chave: "nay-estrutura", recuo: true },
    { grupo: "" },
    { rotulo: "Condomínios",       href: "condominios.html", chave: "condominios" },
    { rotulo: "Anúncios",          href: "anuncios.html",    chave: "anuncios" },
    { rotulo: "Listas",            href: "listas.html",      chave: "listas" },
    { rotulo: "Relatórios",        href: "relatorios.html", chave: "relatorios" },
    { rotulo: "Agenda de Visitas", href: "#" },
    { rotulo: "Arquivos",          href: "#" },
    { rotulo: "Banners",           href: "#" },
    { rotulo: "Usuários",          href: "#" },
    { rotulo: "Feedbacks",         href: "#" },
    { rotulo: "Auditoria",         href: "auditoria.html", chave: "auditoria" }
  ];

  var atual = document.body.dataset.pagina || "";
  var noSubmenu = SUBMENU.some(function (i) { return i.chave && i.chave === atual; });

  /* ---- Barra superior ---- */
  var topo =
    '<header class="barra-topo">' +
      '<div class="barra-topo__interno">' +
        '<a class="barra-topo__logo" href="inicio.html" aria-label="Imob Easy — painel">' +
          '<img src="../assets/img/logo.svg" alt="Imob Easy">' +
        "</a>" +
        '<div class="barra-topo__direita">' +
          '<a class="btn-azul-vazado btn-marca" href="https://n8n.imobeasy.online" target="_blank" rel="noopener">n8n</a>' +
          /* 12/10/2026 (Pedro): "põe um botão no topo do lado do n8n, ver versão mais recente, que recarrega o site
             sem cache" -- o Mac do Tel mostrava a tela de imóveis antiga. Baixa de novo cada script e CSS da página
             e recarrega. */
          '<button class="btn-azul-vazado btn-marca" type="button" data-sem-cache title="Baixa de novo os arquivos desta tela e recarrega">Ver versão mais recente</button>' +
          /* Enviar imóvel ao lado do n8n (Tel, 28/09): o disparo direto para um número. */
          '<a class="btn-azul-vazado btn-marca" href="disparo.html"' + (atual === "disparo" ? ' aria-current="page"' : "") + '>Enviar imóvel</a>' +
          '<a class="btn-azul-vazado" href="../index.html">Pesquisar Imóveis</a>' +
          '<button class="sino" type="button" aria-label="Notificações">' + ICONE.sino + "</button>" +
          '<button class="usuario" type="button">Telmário Araújo ' +
            '<svg viewBox="0 0 12 12" width="11" height="11" fill="currentColor" aria-hidden="true"><path d="M1 3.5 6 9l5-5.5Z"/></svg>' +
          "</button>" +
        "</div>" +
      "</div>" +
    "</header>";

  /* ---- 16/10/2026: a marca de "é da equipe" neste navegador. Só quem passou pela senha do /admin chega aqui; a
     página pública do imóvel lê a marca para mostrar Editar e Ver proprietário (imovel-publico.js). ---- */
  try { localStorage.setItem("imobeasy_equipe", String(Date.now())); } catch (e) { /* sem armazenamento */ }

  /* ---- os lembretes da equipe no sininho (375, Pedro 15/10/2026): o arquivo próprio dá vida ao sino ---- */
  (function () {
    var s = document.createElement("script");
    s.src = "../assets/js/lembretes.js?v=20261015a";
    s.defer = true;
    document.body.appendChild(s);
  })();

  /* ---- o botão "Ver versão mais recente": refaz o download do que esta página usa e recarrega ---- */
  document.addEventListener("click", function (e) {
    var b = e.target.closest ? e.target.closest("[data-sem-cache]") : null;
    if (!b) return;
    b.disabled = true; b.textContent = "Atualizando…";
    var urls = [];
    document.querySelectorAll('script[src], link[rel="stylesheet"][href]').forEach(function (el) {
      var u = el.src || el.href;
      if (u && u.indexOf(location.origin) === 0) urls.push(u);
    });
    urls.push(location.href.split("#")[0]);
    Promise.all(urls.map(function (u) { return fetch(u, { cache: "reload", credentials: "same-origin" }).catch(function () {}); }))
      .then(function () {
        if (window.caches && caches.keys) return caches.keys().then(function (ks) { return Promise.all(ks.map(function (k) { return caches.delete(k); })); });
      })
      .then(function () { location.reload(); }, function () { location.reload(); });
  });

  /* ---- Navegação principal ---- */
  var SETA = '<svg viewBox="0 0 12 12" width="10" height="10" fill="currentColor" aria-hidden="true"><path d="M1 3.5 6 9l5-5.5Z"/></svg>';
  var itens = MENU.map(function (item) {
    var ativo = item.chave === atual;
    if (item.filhos) {
      var dentro = item.filhos.some(function (f) { return f.chave === atual; });
      return '<div class="menu-mais">' +
        '<button class="nav-principal__item' + (dentro ? " ativo" : "") + '" type="button" aria-haspopup="true" aria-expanded="false" data-abre-mais>' +
          '<span class="icone">' + (ICONE[item.chave] || ICONE.folha) + "</span>" + item.rotulo + " " + SETA +
        "</button>" +
        '<ul class="menu-mais__lista" style="left:0;right:auto">' + (item.filhos.length ? item.filhos.map(function (f) {
          return '<li><a href="' + f.href + '"' + (f.chave === atual ? ' aria-current="page"' : "") + ">" + f.rotulo + "</a></li>";
        }).join("") : '<li><span style="display:block;padding:10px 14px;color:var(--texto-fraco)">Vazio por enquanto</span></li>') + "</ul>" +
      "</div>";
    }
    return (
      '<a class="nav-principal__item" href="' + item.href + '"' + (ativo ? ' aria-current="page"' : "") + ">" +
        '<span class="icone">' + (ICONE[item.chave] || ICONE.folha) + "</span>" + item.rotulo +
      "</a>"
    );
  }).join("");

  var grupoAberto = SUBMENU.some(function (i) { return i.recuo && i.chave === atual; });
  var subitens = SUBMENU.map(function (item) {
    var ativo = item.chave && item.chave === atual;
    // GRUPO QUE ABRE E FECHA (Pedro, 06/10: "não quero esses menus ocupando tudo isso de espaço no Mais ... deixa
    // só Nay antiga lá, e quando eu selecionar aparecem esses antigos"). Começa fechado, a não ser que a página
    // aberta seja uma deles.
    if (item.grupo !== undefined) {
      if (!item.grupo) return "";
      return '<li><button type="button" data-abre-grupo aria-expanded="' + grupoAberto + '" style="display:flex;width:100%;align-items:center;justify-content:space-between;gap:8px;border:0;background:transparent;cursor:pointer;padding:10px 14px;border-radius:var(--raio-sm);font:inherit;font-size:var(--fs-md);color:var(--texto);text-align:left">' +
        item.grupo + '<svg viewBox="0 0 12 12" width="10" height="10" fill="currentColor" aria-hidden="true" style="transition:transform .15s;' + (grupoAberto ? "transform:rotate(180deg)" : "") + '"><path d="M1 3.5 6 9l5-5.5Z"/></svg></button></li>';
    }
    if (item.recuo && item.href !== "#") {
      return '<li data-do-grupo' + (grupoAberto ? "" : " hidden") + '><a href="' + item.href + '"' + (ativo ? ' aria-current="page"' : "") + ' style="padding-left:28px">' + item.rotulo + "</a></li>";
    }
    // Sem página ainda: aparece apagado e diz isso, em vez de um link "#"
    // que não fazia nada (revisão 11/09/2026).
    if (item.href === "#") {
      return '<li><span aria-disabled="true" title="Esta área ainda não existe" style="display:block;padding:8px 14px;opacity:.45;cursor:not-allowed">' +
        item.rotulo + " <small>(em breve)</small></span></li>";
    }
    return '<li><a href="' + item.href + '"' + (ativo ? ' aria-current="page"' : "") + ">" + item.rotulo + "</a></li>";
  }).join("");

  var nav =
    '<nav class="nav-principal" aria-label="Navegação principal">' +
      '<div class="nav-principal__interno">' + itens +
        '<div class="menu-mais">' +
          '<button class="nav-principal__item' + (noSubmenu ? " ativo" : "") + '" type="button" ' +
                  'aria-haspopup="true" aria-expanded="false" data-abre-mais>' +
            '<span class="icone">' + ICONE.mais + "</span>Mais " +
            '<svg viewBox="0 0 12 12" width="10" height="10" fill="currentColor" aria-hidden="true"><path d="M1 3.5 6 9l5-5.5Z"/></svg>' +
          "</button>" +
          '<ul class="menu-mais__lista">' + subitens + "</ul>" +
        "</div>" +
      "</div>" +
    "</nav>";

  /* ---- Rodapé ---- */
  var rodape =
    '<footer class="rodape-sistema">' +
      '<div class="rodape-sistema__interno">' +
        "<span>Copyright 2020-2026 © Todos os Direitos Reservados.</span>" +
        /* Referencia obrigatoria das paginas legais. O admin mora em /admin,
           por isso o "../" -- as paginas legais ficam na raiz do site. */
        '<span class="rodape-sistema__links">' +
          '<a href="../termos-de-uso.html">Termos de Uso</a>' +
          '<a href="../politica-de-publicidade.html">Política de Publicidade</a>' +
          '<a href="../exclusao-de-dados.html">Exclusão de Dados</a>' +
        "</span>" +
        ICONE.folha +
      "</div>" +
    "</footer>";

  var alvoTopo = document.querySelector("[data-layout-topo]");
  if (alvoTopo) alvoTopo.outerHTML = topo + nav;

  var alvoRodape = document.querySelector("[data-layout-rodape]");
  if (alvoRodape) alvoRodape.outerHTML = rodape;

  /* ---- Menu "Mais" ---- */
  /* "Nay antiga" dentro do Mais: o clique abre e fecha só o grupo (o Mais continua aberto) */
  document.querySelectorAll("[data-abre-grupo]").forEach(function (b) {
    b.addEventListener("click", function (evento) {
      evento.stopPropagation();
      var abrir = b.getAttribute("aria-expanded") !== "true";
      b.setAttribute("aria-expanded", abrir ? "true" : "false");
      b.querySelector("svg").style.transform = abrir ? "rotate(180deg)" : "";
      b.closest("ul").querySelectorAll("[data-do-grupo]").forEach(function (li) { li.hidden = !abrir; });
    });
  });

  /* os menus que abrem (Captação e Mais): cada botão abre a própria lista e fecha as outras */
  var gatilhos = [].slice.call(document.querySelectorAll("[data-abre-mais]"));
  function alternar(g, abrir) {
    var lista = g.nextElementSibling;
    lista.dataset.aberto = abrir ? "true" : "false";
    g.setAttribute("aria-expanded", abrir ? "true" : "false");
  }
  function fecharTodos(menos) { gatilhos.forEach(function (g) { if (g !== menos) alternar(g, false); }); }
  gatilhos.forEach(function (g) {
    g.addEventListener("click", function (evento) {
      evento.stopPropagation();
      var abrir = g.nextElementSibling.dataset.aberto !== "true";
      fecharTodos(g); alternar(g, abrir);
    });
  });
  if (gatilhos.length) {
    document.addEventListener("click", function (evento) {
      if (!evento.target.closest(".menu-mais")) fecharTodos(null);
    });
    document.addEventListener("keydown", function (evento) {
      if (evento.key !== "Escape") return;
      var aberto = gatilhos.filter(function (g) { return g.getAttribute("aria-expanded") === "true"; })[0];
      fecharTodos(null); if (aberto) aberto.focus();
    });
  }

  /* ---- Botões de dois estados usados nos filtros ---- */
  document.addEventListener("click", function (evento) {
    var botao = evento.target.closest('[aria-pressed]');
    if (!botao) return;
    // Quem controla o proprio estado (filtro de vencimento, filtros das
    // telas novas) nao passa por aqui: antes este clique geral INVERTIA o
    // botao que o filtro tinha acabado de marcar, e o destaque sumia.
    if (botao.closest('[data-estado-proprio]')) return;
    var grupo = botao.closest("[data-grupo-exclusivo]");
    if (grupo) {
      grupo.querySelectorAll('[aria-pressed]').forEach(function (irmao) {
        if (irmao !== botao) irmao.setAttribute("aria-pressed", "false");
      });
    }
    botao.setAttribute("aria-pressed", botao.getAttribute("aria-pressed") === "true" ? "false" : "true");
  });
})();
