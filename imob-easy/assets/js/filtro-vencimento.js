/* ==========================================================================
   Imob Easy — Filtro de data reutilizável (vencimento / última interação)
   + "Criar lista" a partir do resultado filtrado.

   Uso: window.criarFiltroVencimento({
     container: elemento,
     area: "imoveis" | "proprietarios" | "corretores" | "contratos",
     somentePassado: false,           // true pro caso de Corretores
     rotuloFuturo: "A vencer",        // customizável
     rotuloPassado: "Vencido há",
     buscar: function(de, ate) { return fetch(...).then(r=>r.json()); },
     renderizar: function(itens) { ... escreve na tela ... },
     obterResumoItem: function(item) { return {codigo: ..., rotulo: ...}; }
   });
   ========================================================================== */
(function () {
  "use strict";

  function pad(n) { return n < 10 ? "0" + n : "" + n; }
  function paraISO(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }

  function calcularPeriodo(direcao, tipo, meses) {
    var hoje = new Date();
    var hojeISO = paraISO(hoje);

    // Sem filtro de data (padrao desde 11/09): antes a carga inicial ja
    // mandava de=hoje e cortava a lista de Imoveis para 1.
    if (tipo === "nenhum") return { de: null, ate: null };
    if (tipo === "todos") {
      return direcao === "futuro" ? { de: hojeISO, ate: null } : { de: null, ate: hojeISO };
    }

    var dias;
    if (tipo === "semana") dias = 7;
    else if (tipo === "15dias") dias = 15;
    else if (tipo === "30dias") dias = 30;
    else dias = Math.max(1, parseInt(meses, 10) || 1) * 30;

    var outra = new Date(hoje);
    outra.setDate(outra.getDate() + (direcao === "futuro" ? dias : -dias));
    var outraISO = paraISO(outra);

    return direcao === "futuro" ? { de: hojeISO, ate: outraISO } : { de: outraISO, ate: hojeISO };
  }

  function descreverFiltro(direcao, tipo, meses, rotuloFuturo, rotuloPassado) {
    var rotuloDirecao = direcao === "futuro" ? rotuloFuturo : rotuloPassado;
    if (tipo === "nenhum") return "Sem filtro de data";
    if (tipo === "todos") return "Todos (" + rotuloDirecao.toLowerCase() + ")";
    if (tipo === "semana") return rotuloDirecao + ": esta semana";
    if (tipo === "15dias") return rotuloDirecao + ": 15 dias";
    if (tipo === "30dias") return rotuloDirecao + ": 30 dias";
    return rotuloDirecao + ": " + (meses || 1) + " mes(es)";
  }

  window.criarFiltroVencimento = function (cfg) {
    var somentePassado = !!cfg.somentePassado;
    var rotuloFuturo = cfg.rotuloFuturo || "A vencer";
    var rotuloPassado = cfg.rotuloPassado || "Vencido há";
    var itensAtuais = [];
    var filtroAtualDescricao = "Sem filtro (todos os registros)";

    cfg.container.innerHTML =
      '<div class="filtro-vencimento" data-estado-proprio>' +
        (somentePassado ? "" :
          '<div class="filtro-vencimento__grupo" data-grupo-direcao role="group">' +
            '<button type="button" data-direcao="futuro" aria-pressed="false">' + rotuloFuturo + "</button>" +
            '<button type="button" data-direcao="passado" aria-pressed="false">' + rotuloPassado + "</button>" +
          "</div>"
        ) +
        '<div class="filtro-vencimento__grupo" data-grupo-preset role="group">' +
          '<button type="button" data-preset="nenhum" aria-pressed="true">Sem filtro de data</button>' +
          '<button type="button" data-preset="semana">Esta semana</button>' +
          '<button type="button" data-preset="15dias">15 dias</button>' +
          '<button type="button" data-preset="30dias">30 dias</button>' +
          '<button type="button" data-preset="todos">Todos</button>' +
        "</div>" +
        '<div class="filtro-vencimento__custom">' +
          '<input type="number" min="1" class="entrada" placeholder="Nº de meses" data-custom-meses style="width:110px">' +
          '<button class="btn-neutro btn-mini" type="button" data-aplicar-custom>Aplicar</button>' +
        "</div>" +
        '<button class="btn-azul btn-mini" type="button" data-criar-lista style="margin-left:auto">+ Criar lista</button>' +
      "</div>";

    var direcaoAtual = "futuro";
    var el = cfg.container;
    var grupoDirecao = el.querySelector("[data-grupo-direcao]");
    var grupoPreset = el.querySelector("[data-grupo-preset]");
    var campoMeses = el.querySelector("[data-custom-meses]");

    function marcarAtivo(grupo, botao) {
      if (!grupo) return;
      grupo.querySelectorAll("button").forEach(function (b) { b.setAttribute("aria-pressed", b === botao ? "true" : "false"); });
    }

    function executar(tipo, meses) {
      var periodo = calcularPeriodo(direcaoAtual, tipo, meses);
      filtroAtualDescricao = descreverFiltro(direcaoAtual, tipo, meses, rotuloFuturo, rotuloPassado);
      cfg.buscar(periodo.de, periodo.ate).then(function (itens) {
        itensAtuais = itens || [];
        cfg.renderizar(itensAtuais);
      });
    }

    if (grupoDirecao) {
      grupoDirecao.addEventListener("click", function (evento) {
        var botao = evento.target.closest("[data-direcao]");
        if (!botao) return;
        direcaoAtual = botao.dataset.direcao;
        marcarAtivo(grupoDirecao, botao);
        var presetAtivo = grupoPreset.querySelector('[aria-pressed="true"]');
        var tipo = presetAtivo ? presetAtivo.dataset.preset : "todos";
        // Escolher a direcao e pedir filtro: sai do "sem filtro".
        if (tipo === "nenhum") { tipo = "todos"; marcarAtivo(grupoPreset, grupoPreset.querySelector('[data-preset="todos"]')); }
        executar(tipo);
      });
    }

    grupoPreset.addEventListener("click", function (evento) {
      var botao = evento.target.closest("[data-preset]");
      if (!botao) return;
      marcarAtivo(grupoPreset, botao);
      if (botao.dataset.preset === "nenhum") marcarAtivo(grupoDirecao, null);
      else if (grupoDirecao && !grupoDirecao.querySelector('[aria-pressed="true"]'))
        marcarAtivo(grupoDirecao, grupoDirecao.querySelector('[data-direcao="' + direcaoAtual + '"]'));
      executar(botao.dataset.preset);
    });

    el.querySelector("[data-aplicar-custom]").addEventListener("click", function () {
      var meses = campoMeses.value;
      if (!meses) return;
      marcarAtivo(grupoPreset, null);
      executar("meses", meses);
    });

    el.querySelector("[data-criar-lista]").addEventListener("click", function () {
      // Tela paginada: a lista leva TUDO o que o filtro achou, nao so a
      // pagina que esta na tela (cfg.itensParaLista busca o conjunto).
      var fonte = typeof cfg.itensParaLista === "function" ? cfg.itensParaLista() : Promise.resolve(itensAtuais);
      fonte.then(function (todos) {
      todos = todos || [];
      if (!todos.length) {
        alert("Nenhum item no filtro atual pra virar lista.");
        return;
      }
      var nome = prompt("Nome da lista (" + todos.length + " item(ns)):");
      if (!nome) return;
      var exportadoPor = prompt("Seu nome (fica registrado como quem exportou):") || "não informado";
      var resumo = todos.map(cfg.obterResumoItem);

      fetch(window.API_BASE + "/api/listas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          nome: nome, area: cfg.area, filtro: filtroAtualDescricao,
          itens: resumo, exportado_por: exportadoPor,
        }),
      })
        .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function () { alert('Lista "' + nome + '" criada com ' + resumo.length + " item(ns). Ver em Listas, no menu +."); })
        .catch(function () { alert("Não consegui criar a lista. Tenta de novo."); });
      });
    });

    // carga inicial: SEM filtro de data (todos os registros)
    executar("nenhum");
    return { descricao: function () { return filtroAtualDescricao; } };
  };
})();
