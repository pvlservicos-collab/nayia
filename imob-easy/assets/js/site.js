/* ==========================================================================
   Imob Easy — Comportamento do site público
   ========================================================================== */
(function () {
  "use strict";

  var RAIZ = document.body.dataset.raiz || "";

  /* ---- Ícones das especificações ---- */
  var ICONES = {
    area:
      '<svg viewBox="0 0 32 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">' +
      '<rect x="2" y="8" width="28" height="9" rx="2"/><path d="M8 8v4M14 8v6M20 8v4M26 8v6"/></svg>',
    quartos:
      '<svg viewBox="0 0 32 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">' +
      '<path d="M3 18v-9M3 13h26v5M29 18v-4"/><rect x="7" y="8" width="8" height="5" rx="2"/></svg>',
    banheiros:
      '<svg viewBox="0 0 32 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">' +
      '<path d="M13 4h6v5h-6z"/><path d="M16 9v4"/><path d="M8 13h16v3a5 5 0 0 1-5 5h-6a5 5 0 0 1-5-5z"/></svg>',
    garagem:
      '<svg viewBox="0 0 32 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">' +
      '<path d="M5 16h22M7 16v3M25 16v3"/><path d="M7 16l2-6h14l2 6"/><circle cx="11" cy="16" r="1.4"/>' +
      '<circle cx="21" cy="16" r="1.4"/></svg>'
  };

  function escapar(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function pontos(quantidade, ativo) {
    var total = Math.min(quantidade || 6, 24);
    var saida = "";
    for (var i = 0; i < total; i++) {
      saida += '<span class="carrossel__ponto' + (i === (ativo || 0) ? " carrossel__ponto--ativo" : "") + '"></span>';
    }
    return saida;
  }

  function especificacao(titulo, chave, valor) {
    return (
      '<div class="especificacao">' +
      '<div class="especificacao__titulo">' + titulo + "</div>" +
      '<div class="especificacao__icone">' + ICONES[chave] + "</div>" +
      '<div class="especificacao__valor">' + escapar(valor) + "</div>" +
      "</div>"
    );
  }

  /* ---- Monta um cartão de imóvel ---- */
  function fotoSrc(foto) {
    if (!foto) return RAIZ + "assets/img/imovel-01.svg"; // sem foto cadastrada
    if (/^https?:\/\//.test(foto)) return foto; // vem da API, URL real do CDN
    return RAIZ + "assets/img/" + foto; // dado estático de fallback
  }

  function cartaoImovel(item) {
    var selo = item.parceiro
      ? '<span class="imovel__selo">' +
        '<svg viewBox="0 0 16 16" width="13" height="13" fill="currentColor" aria-hidden="true">' +
        '<path d="M8 2 1 6l7 4 7-4-7-4Zm-7 6.5V12l7 4 7-4V8.5l-7 4-7-4Z"/></svg> Imóvel Parceiro</span>'
      : "";

    return (
      '<article class="imovel">' +
        '<div class="imovel__midia">' +
          '<img src="' + fotoSrc(item.foto) + '" alt="Foto do imóvel ' + escapar(item.nome) + '" loading="lazy">' +
          selo +
          '<button class="carrossel__seta carrossel__seta--ant" type="button" aria-label="Foto anterior">&#8249;</button>' +
          '<button class="carrossel__seta carrossel__seta--prox" type="button" aria-label="Próxima foto">&#8250;</button>' +
          '<div class="carrossel__pontos" aria-hidden="true">' + pontos(item.pontos, 0) + "</div>" +
        "</div>" +
        '<div class="imovel__corpo">' +
          '<div class="imovel__cabecalho">' +
            "<div>" +
              '<h3 class="imovel__nome">' + escapar(item.nome) + "</h3>" +
              '<p class="imovel__endereco">' + escapar(item.endereco) +
                (item.complemento ? "<br>" + escapar(item.complemento) : "") +
              "</p>" +
            "</div>" +
            '<button class="btn-selecionar" type="button" aria-pressed="false">Selecionar</button>' +
          "</div>" +
          '<div class="especificacoes">' +
            especificacao("Área", "area", item.area) +
            especificacao("Quartos", "quartos", item.quartos) +
            especificacao("Banheiros", "banheiros", item.banheiros) +
            especificacao("Garagem", "garagem", item.garagem) +
          "</div>" +
          '<dl class="imovel__preco"><dt>' + escapar(item.rotuloPreco) + "</dt><dd>" + escapar(item.preco) + "</dd></dl>" +
          '<a class="btn-roxo btn-bloco" href="#">Ver Imóvel</a>' +
        "</div>" +
      "</article>"
    );
  }

  /* ---- Renderiza listas declaradas via data-lista ----
     Roda uma vez de imediato (com o que dados-site.js tiver nesse momento
     -- estatico, de fallback) e roda de novo sempre que o evento
     "dados-site-atualizados" disparar (quando a API responde de verdade).
     Se a API nunca responder, fica só o estático -- nunca quebra. */
  function renderizarListasDeImoveis() {
    document.querySelectorAll("[data-lista]").forEach(function (alvo) {
      var itens = (window.DADOS_SITE || {})[alvo.dataset.lista] || [];
      alvo.innerHTML = itens.map(cartaoImovel).join("");
    });
  }
  renderizarListasDeImoveis();
  document.addEventListener("dados-site-atualizados", renderizarListasDeImoveis);

  /* ---- Botões de dois estados (Selecionar, quartos, garagem, visão) ---- */
  document.addEventListener("click", function (evento) {
    var botao = evento.target.closest('[aria-pressed]');
    if (!botao) return;

    var grupo = botao.closest("[data-grupo-exclusivo]");
    if (grupo) {
      grupo.querySelectorAll('[aria-pressed]').forEach(function (irmao) {
        if (irmao !== botao) irmao.setAttribute("aria-pressed", "false");
      });
    }
    botao.setAttribute("aria-pressed", botao.getAttribute("aria-pressed") === "true" ? "false" : "true");
  });

  /* ---- Abas Comprar / Alugar ---- */
  document.querySelectorAll("[data-abas]").forEach(function (grupo) {
    grupo.addEventListener("click", function (evento) {
      var aba = evento.target.closest('[role="tab"]');
      if (!aba || !aba.dataset.destino) return;
      window.location.href = aba.dataset.destino;
    });
  });

  /* ---- Remoção dos marcadores de bairro ---- */
  document.addEventListener("click", function (evento) {
    var fechar = evento.target.closest(".marcador button");
    if (fechar) fechar.closest(".marcador").remove();
  });
})();
