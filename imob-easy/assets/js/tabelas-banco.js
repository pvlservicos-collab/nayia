/* ==========================================================================
   Imob Easy — Navegador de todas as tabelas do naydb (só na tela Início)
   ========================================================================== */
(function () {
  "use strict";

  /* Categorização vinda do resumo de 05/09/2026 (34-Tabelas-do-Banco.md).
     Só visual -- não muda a leitura, só agrupa e dá uma cor por categoria
     pra facilitar achar a tabela certa. */
  var CATEGORIAS = [
    {
      nome: "O catálogo", cor: "#1673d1",
      tabelas: ["imoveis", "imovel_fotos", "proprietarios", "imovel_privado", "condominios", "contratos_locacao"],
    },
    {
      nome: "Trazido do admin real (imobeasy.com)", cor: "#b45309",
      tabelas: ["clientes_admin_real"],
    },
    {
      nome: "A conversa no WhatsApp", cor: "#1f9d4d",
      tabelas: ["mensagens", "mensagem_saida", "nay_memoria", "corretores", "identidade_lid", "equipe", "contato_corretor"],
    },
    {
      nome: "Os disparos", cor: "#e08a10",
      tabelas: ["grupos", "vagas", "envios", "easy_publicacoes", "entrega_pendente", "lembrete"],
    },
    {
      nome: "O que ela aprende", cor: "#6c25e0",
      tabelas: ["pendencias", "pendencia_interessado", "pendencia_rascunho", "resposta_a_entregar", "imovel_conhecimento", "escalacoes", "regras"],
    },
    {
      nome: "Bairros", cor: "#0d9488",
      tabelas: ["bairro_zona", "bairro_vizinho"],
    },
    {
      nome: "A captação do OLX", cor: "#c0267a",
      tabelas: ["captacoes", "captacao_fotos"],
    },
    {
      nome: "Configuração", cor: "#64748b",
      tabelas: ["config", "imagem_estrutura"],
    },
    {
      nome: "Site (este painel)", cor: "#4338ca",
      tabelas: ["site_listas", "site_proximos_passos"],
    },
    {
      nome: "Arquivo / não usadas", cor: "#94a3b8",
      tabelas: ["escalacoes_arquivo_20260827", "imoveis_backup_20260828", "pendencias_arquivo_20260827",
        "regras_arquivo_20260828", "regras_arquivo_20260828b", "publicacoes", "fila_publicacao",
        "payload_estrutura", "condominio_taxas", "visitas"],
    },
  ];

  var CATEGORIA_DA_TABELA = {};
  CATEGORIAS.forEach(function (cat) {
    cat.tabelas.forEach(function (t) { CATEGORIA_DA_TABELA[t] = cat; });
  });
  var CATEGORIA_RESTANTE = { nome: "Outras", cor: "#94a3b8" };

  var lista = document.getElementById("lista-tabelas");
  if (!lista) return; // só existe em admin/inicio.html

  var titulo = document.getElementById("tabela-selecionada-titulo");
  var cabecalho = document.getElementById("tabela-selecionada-cabecalho");
  var corpo = document.getElementById("tabela-selecionada-corpo");

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function formatarValor(v) {
    if (v == null) return '<span style="color:var(--texto-fraco)">—</span>';
    if (Array.isArray(v)) return esc(v.join(", "));
    if (typeof v === "object") return esc(JSON.stringify(v));
    return esc(v);
  }

  function abrirTabela(nome, botao) {
    lista.querySelectorAll("[data-tabela]").forEach(function (b) { b.setAttribute("aria-current", "false"); });
    if (botao) botao.setAttribute("aria-current", "true");
    titulo.textContent = nome;
    cabecalho.innerHTML = "";
    corpo.innerHTML = '<tr><td>Carregando...</td></tr>';

    fetch(window.API_BASE + "/api/tabelas/" + encodeURIComponent(nome))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (dados) {
        cabecalho.innerHTML = dados.colunas.map(function (c) { return "<th scope=\"col\">" + esc(c) + "</th>"; }).join("");
        if (!dados.linhas.length) {
          corpo.innerHTML = '<tr><td colspan="' + dados.colunas.length + '" style="text-align:center;color:var(--texto-fraco);padding:20px">Tabela vazia.</td></tr>';
          return;
        }
        corpo.innerHTML = dados.linhas.map(function (linha) {
          return "<tr>" + dados.colunas.map(function (c) { return "<td title=\"" + esc(linha[c]) + "\">" + formatarValor(linha[c]) + "</td>"; }).join("") + "</tr>";
        }).join("");
      })
      .catch(function () {
        corpo.innerHTML = '<tr><td>Não foi possível carregar esta tabela.</td></tr>';
      });
  }

  if (!window.API_BASE) {
    lista.textContent = "config.js não define API_BASE.";
    return;
  }

  function itemHtml(t) {
    var cat = CATEGORIA_DA_TABELA[t.tabela] || CATEGORIA_RESTANTE;
    return (
      '<button class="tabelas-banco__item" type="button" data-tabela="' + esc(t.tabela) + '" aria-current="false">' +
        '<span class="tabelas-banco__bolinha" style="background:' + cat.cor + '"></span>' +
        '<span class="tabelas-banco__nome">' + esc(t.tabela) + "</span>" +
        "<span>" + esc(t.linhas) + "</span>" +
      "</button>"
    );
  }

  fetch(window.API_BASE + "/api/tabelas")
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (tabelas) {
      var porTabela = {};
      tabelas.forEach(function (t) { porTabela[t.tabela] = t; });

      var html = "";
      CATEGORIAS.forEach(function (cat) {
        var itens = cat.tabelas.filter(function (nome) { return porTabela[nome]; });
        if (!itens.length) return;
        html += '<div class="tabelas-banco__categoria" style="border-left-color:' + cat.cor + '">' + esc(cat.nome) + "</div>";
        html += itens.map(function (nome) { return itemHtml(porTabela[nome]); }).join("");
      });
      // qualquer tabela nova que apareça no banco sem categoria ainda definida
      var categorizadas = Object.keys(CATEGORIA_DA_TABELA);
      var sobrando = tabelas.filter(function (t) { return categorizadas.indexOf(t.tabela) === -1; });
      if (sobrando.length) {
        html += '<div class="tabelas-banco__categoria" style="border-left-color:' + CATEGORIA_RESTANTE.cor + '">Outras</div>';
        html += sobrando.map(itemHtml).join("");
      }

      lista.innerHTML = html;
      lista.querySelectorAll("[data-tabela]").forEach(function (botao) {
        botao.addEventListener("click", function () { abrirTabela(botao.dataset.tabela, botao); });
      });
    })
    .catch(function () {
      lista.textContent = "Não foi possível carregar a lista de tabelas.";
    });
})();
