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
    oportunidades:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">' +
      '<circle cx="12" cy="12" r="8.2"/><circle cx="12" cy="12" r="4.4"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/></svg>',
    captacao:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<path d="M4 4h16v4H4z"/><path d="M6 8v6a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/></svg>',
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
    { chave: "imoveis",       rotulo: "Todos os Imóveis", href: "imoveis.html" },
    { chave: "proprietarios", rotulo: "Proprietários",    href: "proprietarios.html" },
    { chave: "corretores",    rotulo: "Corretores",       href: "corretores.html" },
    { chave: "locacao",       rotulo: "Locação",          href: "locacao.html" },
    { chave: "oportunidades", rotulo: "Oportunidades",    href: "oportunidades.html" },
    { chave: "captacao",      rotulo: "Captação",         href: "captacao.html" },
    { chave: "clientes",      rotulo: "Clientes",         href: "clientes.html" }
  ];

  var SUBMENU = [
    { rotulo: "Fluxo de mensagens", href: "fluxo.html",      chave: "fluxo" },
    { rotulo: "Nay Locação",       href: "nay-locacao.html", chave: "nay-locacao" },
    { rotulo: "Nay Captação",      href: "nay-captacao.html", chave: "nay-captacao" },
    { rotulo: "Cérebro da Nay",    href: "nay-cerebro.html", chave: "nay-cerebro" },
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
  var noSubmenu = SUBMENU.some(function (i) { return i.chave === atual; });

  /* ---- Barra superior ---- */
  var topo =
    '<header class="barra-topo">' +
      '<div class="barra-topo__interno">' +
        '<a class="barra-topo__logo" href="inicio.html" aria-label="Imob Easy — painel">' +
          '<img src="../assets/img/logo.svg" alt="Imob Easy">' +
        "</a>" +
        '<div class="barra-topo__direita">' +
          '<a class="btn-azul-vazado btn-marca" href="https://n8n.imobeasy.online" target="_blank" rel="noopener">n8n</a>' +
          '<a class="btn-azul-vazado" href="../index.html">Pesquisar Imóveis</a>' +
          '<button class="sino" type="button" aria-label="Notificações">' + ICONE.sino + "</button>" +
          '<button class="usuario" type="button">Telmário Araújo ' +
            '<svg viewBox="0 0 12 12" width="11" height="11" fill="currentColor" aria-hidden="true"><path d="M1 3.5 6 9l5-5.5Z"/></svg>' +
          "</button>" +
        "</div>" +
      "</div>" +
    "</header>";

  /* ---- Navegação principal ---- */
  var itens = MENU.map(function (item) {
    var ativo = item.chave === atual;
    return (
      '<a class="nav-principal__item" href="' + item.href + '"' + (ativo ? ' aria-current="page"' : "") + ">" +
        '<span class="icone">' + ICONE[item.chave] + "</span>" + item.rotulo +
      "</a>"
    );
  }).join("");

  var subitens = SUBMENU.map(function (item) {
    var ativo = item.chave && item.chave === atual;
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
  var gatilho = document.querySelector("[data-abre-mais]");
  if (gatilho) {
    var lista = gatilho.nextElementSibling;

    function alternar(abrir) {
      lista.dataset.aberto = abrir ? "true" : "false";
      gatilho.setAttribute("aria-expanded", abrir ? "true" : "false");
    }

    gatilho.addEventListener("click", function (evento) {
      evento.stopPropagation();
      alternar(lista.dataset.aberto !== "true");
    });

    document.addEventListener("click", function (evento) {
      if (!evento.target.closest(".menu-mais")) alternar(false);
    });

    document.addEventListener("keydown", function (evento) {
      if (evento.key === "Escape") { alternar(false); gatilho.focus(); }
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
