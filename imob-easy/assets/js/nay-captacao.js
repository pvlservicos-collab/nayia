/* ==========================================================================
   Imob Easy — Nay de Captação (admin)

   Pedido do Tel (15/09/2026): a aba da captação ao lado da Nay Locação, "com o
   prompt e tudo mais e não só os números".

   Lê tudo de /api/nai/captacao; o prompt vem de /api/nai/prompt/captacao, a
   mesma rota dos prompts da locação -- mesma trava de versão e mesmo histórico.
   Salvar aqui vale na mensagem seguinte: o fluxo do n8n lê o prompt do banco a
   cada mensagem.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";

  function esc(t) {
    return String(t == null ? "" : t)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function elemento(id) { return document.getElementById(id); }

  function tempo(seg) {
    if (seg == null) return "—";
    if (seg < 60) return Math.round(seg) + "s";
    return Math.floor(seg / 60) + "min " + Math.round(seg % 60) + "s";
  }

  function cartao(rotulo, valor, nota) {
    return '<div class="painel-cartao">' +
           '<div class="painel-cartao__n">' + esc(valor) + "</div>" +
           '<div class="painel-cartao__r">' + esc(rotulo) + (nota ? " · " + esc(nota) : "") + "</div>" +
           "</div>";
  }

  function tabela(alvo, colunas, linhas, celula) {
    var cabecalho = "<thead><tr>" + colunas.map(function (c) { return "<th>" + esc(c) + "</th>"; }).join("") + "</tr></thead>";
    var corpo = "<tbody>" + (linhas.length
      ? linhas.map(function (l, i) { return "<tr>" + celula(l, i) + "</tr>"; }).join("")
      : '<tr><td colspan="' + colunas.length + '">Nada por aqui ainda.</td></tr>') + "</tbody>";
    alvo.innerHTML = cabecalho + corpo;
  }

  /* ------------------------------------------------------- NAY CAPTAÇÃO ---- */
  /* A campanha com os proprietários (Tel, 15/09). Vem de /api/nai/captacao,
     numa carga própria: a aba só é desenhada quando os dados chegam, e se essa
     chamada falhar o resto da página continua de pé. */
  var captacao = null;

  function desenharCaptacao() {
    if (!captacao) return;
    var r = captacao.resumo || {};
    var cfg = {};
    (captacao.config || []).forEach(function (c) { cfg[c.chave] = c.valor; });

    var ligada = cfg.captacao_pausada === "nao";
    var teste = cfg.modo_teste === "sim";
    elemento("cap-selo").textContent = ligada ? (teste ? "em teste" : "disparando") : "parada";
    elemento("cap-selo").className = "selo " + (ligada ? (teste ? "selo--teste" : "selo--on") : "selo--off");
    elemento("cap-nota").textContent =
      "Dispara das " + (cfg.janela_inicio || "?") + " às " + (cfg.janela_fim || "?") +
      ", até " + (cfg.limite_dia || "?") + " por dia, um a cada " + (cfg.minutos_entre_disparos || "?") + " min · " +
      (Number(cfg.max_followup) > 0
        ? "cobra quem não responde até " + cfg.max_followup + "x"
        : "não cobra quem não responde") +
      " · último disparo " + (cfg._cron_disparo_em || "—");

    var respondeu = Number(r.responderam || 0), falados = Number(r.falados || 0);
    elemento("cap-cartoes").innerHTML =
      cartao("Proprietários na lista", r.leads || 0, (r.na_fila || 0) + " ainda na fila") +
      cartao("Já falou com", falados) +
      cartao("Responderam", respondeu, (falados ? Math.round(respondeu * 100 / falados) + "%" : "")) +
      cartao("Tempo até responder", tempo(r.segundos_ate_responder)) +
      cartao("Disponíveis", r.disponiveis || 0, "para alugar") +
      cartao("Alugados", r.alugados || 0) +
      cartao("Vendidos", r.vendidos || 0) +
      cartao("Com outro imóvel", r.com_outro_imovel || 0, "o que a campanha trouxe") +
      cartao("Pediram para sair", r.pediram_para_sair || 0) +
      cartao("Com o Tel", r.com_o_tel || 0, "ele assumiu a conversa");

    tabela(elemento("cap-tab-captados"),
      ["Quando", "Proprietário", "O que ele disse ter", "Negócio"],
      captacao.captados || [],
      function (c) {
        return "<td>" + esc(String(c.criado_em || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(c.nome || "—") + "</td><td>" + esc(c.descricao) + "</td>" +
               "<td>" + esc(c.negocio) + "</td>";
      });

    tabela(elemento("cap-tab-dias"),
      ["Dia", "Falou com", "Responderam", "Encerrados", "Disponíveis", "Com outro imóvel"],
      captacao.dias || [],
      function (d) {
        return "<td>" + esc(d.dia) + "</td><td>" + esc(d.falados) + "</td>" +
               "<td>" + esc(d.responderam) + "</td><td>" + esc(d.encerrados) + "</td>" +
               "<td>" + esc(d.disponiveis) + "</td><td>" + esc(d.com_outro_imovel) + "</td>";
      });

    tabela(elemento("cap-tab-config"),
      ["Regra", "Valor", "", "O que ela faz"],
      captacao.config || [],
      function (c) {
        var campo = c.editavel
          ? '<input class="entrada" data-cap-chave="' + esc(c.chave) + '" value="' + esc(c.valor) + '">'
          : "<code>" + esc(c.valor) + "</code>";
        var botao = c.editavel
          ? '<button class="btn-mini" type="button" data-cap-salvar="' + esc(c.chave) + '">Salvar</button>'
          : "";
        return "<td><strong>" + esc(c.chave) + "</strong></td><td>" + campo + "</td><td>" + botao + "</td>" +
               "<td>" + esc(c.descricao || "") + "</td>";
      });

    desenharConversasCaptacao();
  }

  function desenharConversasCaptacao() {
    var termo = (elemento("cap-filtro").value || "").trim().toLowerCase();
    var linhas = (captacao.conversas || []).filter(function (c) {
      if (!termo) return true;
      return [c.nome, c.codigo, c.condominio].join(" ").toLowerCase().indexOf(termo) >= 0;
    });
    tabela(elemento("cap-tab-conversas"),
      ["Quando", "Proprietário", "Imóvel", "Situação", "Quem gravou", "Ele disse", "Ela respondeu", ""],
      linhas,
      function (c) {
        var marca = c.opt_out ? " · pediu para sair" : (c.com_o_tel ? " · com o Tel" : "");
        return "<td>" + esc(String(c.respondeu_em || c.ultimo_envio_em || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(c.nome || "—") + "</td>" +
               "<td>" + esc(c.condominio || "—") + (c.codigo ? " <code>" + esc(c.codigo) + "</code>" : "") + "</td>" +
               "<td>" + esc(c.situacao || "—") + "</td>" +
               "<td>" + esc(c.situacao_por || "—") + "</td>" +
               "<td>" + esc((c.ele_disse || "—").slice(0, 70)) + "</td>" +
               "<td>" + esc((c.ela_respondeu || "—").slice(0, 70)) + "</td>" +
               "<td>" + esc(c.etapa) + esc(marca) + "</td>";
      });
  }

  function carregarCaptacao() {
    fetch(API + "/api/nai/captacao")
      .then(function (r) { return r.json(); })
      .then(function (dados) { captacao = dados; desenharCaptacao(); })
      .catch(function () { elemento("cap-nota").textContent = "não consegui carregar a captação."; });
  }

  /* salvar uma regra da campanha */
  document.addEventListener("click", function (e) {
    var botao = e.target.closest("[data-cap-salvar]");
    if (!botao) return;
    var chave = botao.dataset.capSalvar;
    var campo = document.querySelector('[data-cap-chave="' + chave + '"]');
    if (!campo) return;
    botao.disabled = true;
    fetch(API + "/api/nai/captacao/config", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chave: chave, valor: campo.value })
    }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        botao.disabled = false;
        botao.textContent = res.ok && res.j.ok ? "Salvo" : (res.j.erro || "Erro");
        setTimeout(function () { botao.textContent = "Salvar"; }, 2500);
      })
      .catch(function () { botao.disabled = false; botao.textContent = "Sem conexão"; });
  });



  /* -------------------------------------------------------------- ENVIOS ---- */
  /* Tudo que saiu pelo número da captação, dizendo quem mandou (Tel, 15/09). */
  var envios = null;

  function desenharEnvios() {
    if (!envios) return;
    var r = envios.resumo || {};
    elemento("cap-envios-cartoes").innerHTML =
      cartao("Enviadas", r.total || 0, r.pessoas ? r.pessoas + " proprietários" : "") +
      cartao("A Nay escreveu", r.da_nay || 0,
             (r.total ? Math.round((r.da_nay || 0) * 100 / r.total) + "%" : "")) +
      cartao("Primeiras mensagens", r.primeiras || 0, "a abertura da campanha") +
      cartao("Alguém digitou", r.de_gente || 0) +
      cartao("Nas últimas 24h", r.nas_24h || 0);
    desenharTabelaEnvios();
  }

  function desenharTabelaEnvios() {
    var termo = (elemento("cap-envios-filtro").value || "").trim().toLowerCase();
    var linhas = (envios.envios || []).filter(function (e) {
      if (!termo) return true;
      return [e.para_quem, e.codigo, e.texto].join(" ").toLowerCase().indexOf(termo) >= 0;
    });
    tabela(elemento("cap-tab-envios"),
      ["Quando", "Para quem", "Imóvel", "Quem mandou", "Texto"],
      linhas,
      function (e) {
        return "<td>" + esc(String(e.quando || "").replace("T", " ").slice(5, 16)) + "</td>" +
               "<td>" + esc(e.para_quem || "—") + "</td>" +
               "<td>" + esc(e.condominio || "—") + (e.codigo ? " <code>" + esc(e.codigo) + "</code>" : "") + "</td>" +
               "<td>" + esc(e.quem_mandou) + "</td>" +
               "<td>" + esc(e.texto || "—") + "</td>";
      });
  }

  function carregarEnvios() {
    fetch(API + "/api/nai/captacao/envios")
      .then(function (r) { return r.json(); })
      .then(function (d) { envios = d; desenharEnvios(); })
      .catch(function () {});
  }

  /* -------------------------------------------------------------- PROMPT ---- */
  /* Mesma rota dos prompts da locação (/api/nai/prompt/<papel>), com papel
     "captacao": mesma trava de versão, mesmo histórico, mesma função de salvar.
     Se alguém salvar antes, a API devolve 409 e a tela avisa em vez de
     sobrescrever o texto do outro. */
  var versaoPrompt = null;

  function carregarPrompt() {
    elemento("cap-prompt-info").textContent = "carregando…";
    fetch(API + "/api/nai/prompt/captacao")
      .then(function (r) { return r.json(); })
      .then(function (p) {
        elemento("cap-prompt").value = p.texto || "";
        versaoPrompt = p.versao;
        elemento("cap-prompt-info").textContent =
          "versão " + p.versao + " · " + (p.texto || "").length + " caracteres · salvo por " +
          (p.atualizado_por || "—") + " em " + String(p.atualizado_em || "").replace("T", " ").slice(0, 16);
      })
      .catch(function () { elemento("cap-prompt-info").textContent = "não consegui carregar o prompt."; });
  }

  function salvarPrompt() {
    var aviso = elemento("cap-prompt-aviso");
    aviso.textContent = "salvando…";
    fetch(API + "/api/nai/prompt/captacao", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ texto: elemento("cap-prompt").value, versao: versaoPrompt, por: "painel" })
    }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        if (res.ok && res.j.ok) {
          versaoPrompt = res.j.versao;
          aviso.textContent = "salvo — vale na próxima mensagem (versão " + res.j.versao + ")";
        } else {
          aviso.textContent = res.j.erro || "não salvou";
        }
      })
      .catch(function () { aviso.textContent = "sem conexão"; });
  }

  document.addEventListener("DOMContentLoaded", function () {
    elemento("cap-filtro").addEventListener("input", desenharConversasCaptacao);
    elemento("cap-envios-filtro").addEventListener("input", desenharTabelaEnvios);
    elemento("cap-salvar-prompt").addEventListener("click", salvarPrompt);
    carregarCaptacao();
    carregarPrompt();
    carregarEnvios();
  });
})();
