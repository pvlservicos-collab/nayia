/* ==========================================================================
   Imob Easy — Seletor de condomínio (revisão 11/09/2026)

   Pedido do Tel: "quando digitar ele sugira os nomes de condomínios, e
   funcione de forma a marcação de condomínio". Enquanto digita (espera
   250 ms), busca em /api/condominios/sugerir -- sem acento, acha no meio do
   nome ("acquarelle" acha "Condomínio Acquarelle") e tolera erro de
   digitação. Escolher vira uma ETIQUETA com o id guardado; o × tira.

   LETRA A LETRA (Pedro, 08/10/2026: "quando se digita um nome desça a lista
   filtrando letra a letra em todos os filtros dos condomínios"). A lista inteira
   (/api/condominios/nomes, uns 600 nomes) é lida UMA vez por página e o filtro
   acontece na tela, sem esperar: abre ao clicar no campo, estreita a cada letra,
   e quem começa com o que foi digitado vem na frente. Só quando nada bate na
   tela é que pergunta ao servidor, que tolera erro de digitação.
   window.recarregarCondominios() relê a lista (depois de cadastrar um novo).

   Uso: var s = criarSeletorCondominio(input, { multiplo: true, aoMudar: fn });
        s.valores()  -> [{id, nome}]
        s.definir([{id, nome}])
        s.limpar()
   ========================================================================== */
(function () {
  "use strict";

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function semAcento(t) {
    return String(t == null ? "" : t).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  }
  // "Condomínio Residencial Acquarelle" também começa com "acq"
  function semPrefixo(t) {
    return t.replace(/^((condominio|residencial|edificio|cond\.?|ed\.?|res\.?)\s+)+/, "");
  }

  var TODOS = null, lendo = null;
  function lerTodos() {
    if (TODOS) return Promise.resolve(TODOS);
    if (!lendo) {
      lendo = fetch(window.API_BASE + "/api/condominios/nomes")
        .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function (l) {
          TODOS = (l || []).map(function (c) {
            var n = semAcento(c.nome);
            return { id: c.id, nome: c.nome, bairro: c.bairro, _n: n, _c: semPrefixo(n), _b: semAcento(c.bairro) };
          });
          return TODOS;
        })
        .catch(function () { lendo = null; return null; });
    }
    return lendo;
  }
  window.recarregarCondominios = function () { TODOS = null; lendo = null; return lerTodos(); };

  /* quem começa com o que foi digitado, depois quem tem uma palavra que começa, depois quem tem no meio */
  function filtrarNaTela(q, limite) {
    if (!TODOS) return null;
    if (!q) return TODOS.slice(0, limite);
    var comeca = [], palavra = [], meio = [];
    for (var i = 0; i < TODOS.length; i++) {
      var c = TODOS[i];
      if (c._c.indexOf(q) === 0 || c._n.indexOf(q) === 0) comeca.push(c);
      else if ((" " + c._n).indexOf(" " + q) >= 0) palavra.push(c);
      else if (c._n.indexOf(q) >= 0 || (q.length >= 3 && c._b.indexOf(q) >= 0)) meio.push(c);
    }
    return comeca.concat(palavra, meio).slice(0, limite);
  }

  if (!document.getElementById("estilo-seletor-condominio")) {
    var css = document.createElement("style");
    css.id = "estilo-seletor-condominio";
    css.textContent =
      ".sel-condo{position:relative}" +
      ".sel-condo__etiquetas{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:6px}" +
      ".sel-condo__etiquetas:empty{display:none}" +
      ".sel-condo__etiqueta{display:inline-flex;align-items:center;gap:6px;background:var(--selecao,#e8eefc);" +
      "border:1px solid var(--primaria,#2c58c7);color:var(--texto,#1c2533);border-radius:999px;padding:3px 6px 3px 10px;font-size:var(--fs-xs,12px)}" +
      ".sel-condo__etiqueta button{border:0;background:transparent;cursor:pointer;font-size:14px;line-height:1;padding:0 2px;color:inherit}" +
      ".sel-condo__lista{position:absolute;left:0;right:0;top:100%;z-index:50;background:#fff;border:1px solid var(--borda,#d9dce3);" +
      "border-radius:var(--raio-md,8px);box-shadow:0 8px 24px rgba(20,30,60,.14);max-height:280px;overflow-y:auto;margin-top:2px}" +
      ".sel-condo__lista[hidden]{display:none}" +
      ".sel-condo__item{display:block;width:100%;text-align:left;border:0;background:#fff;padding:8px 10px;cursor:pointer;font-size:var(--fs-sm,14px)}" +
      ".sel-condo__item small{display:block;color:var(--texto-fraco,#6b7280);font-size:var(--fs-xs,12px)}" +
      ".sel-condo__item[aria-selected=true],.sel-condo__item:hover{background:var(--selecao,#e8eefc)}" +
      ".sel-condo__vazio{padding:8px 10px;color:var(--texto-fraco,#6b7280);font-size:var(--fs-sm,14px)}";
    document.head.appendChild(css);
  }

  window.criarSeletorCondominio = function (input, opcoes) {
    opcoes = opcoes || {};
    var multiplo = opcoes.multiplo !== false;
    var escolhidos = [];
    var sugestoes = [];
    var ativo = -1;
    var espera = null;
    var pedido = 0;

    var caixa = document.createElement("div");
    caixa.className = "sel-condo";
    input.parentNode.insertBefore(caixa, input);
    var etiquetas = document.createElement("div");
    etiquetas.className = "sel-condo__etiquetas";
    caixa.appendChild(etiquetas);
    caixa.appendChild(input);
    var lista = document.createElement("div");
    lista.className = "sel-condo__lista";
    lista.hidden = true;
    lista.setAttribute("role", "listbox");
    caixa.appendChild(lista);
    input.setAttribute("autocomplete", "off");
    input.setAttribute("role", "combobox");
    input.setAttribute("aria-autocomplete", "list");
    if (!input.placeholder) input.placeholder = "Digite o nome do condomínio";

    function avisar() { if (typeof opcoes.aoMudar === "function") opcoes.aoMudar(escolhidos.slice()); }

    function pintarEtiquetas() {
      etiquetas.innerHTML = escolhidos.map(function (c, i) {
        return '<span class="sel-condo__etiqueta">' + esc(c.nome) +
          '<button type="button" data-tirar="' + i + '" aria-label="Tirar ' + esc(c.nome) + '">×</button></span>';
      }).join("");
      input.hidden = !multiplo && escolhidos.length > 0;
    }

    function pintarLista() {
      if (!sugestoes.length) {
        lista.innerHTML = '<div class="sel-condo__vazio">Nenhum condomínio com esse nome.</div>';
      } else {
        lista.innerHTML = sugestoes.map(function (c, i) {
          return '<button type="button" class="sel-condo__item" role="option" data-i="' + i + '" aria-selected="' + (i === ativo) + '">' +
            esc(c.nome) + (c.bairro || c.imoveis ? "<small>" + esc([c.bairro, c.imoveis ? c.imoveis + " imóvel(is)" : ""].filter(Boolean).join(" · ")) + "</small>" : "") + "</button>";
        }).join("");
      }
      lista.hidden = false;
    }

    function escolher(c) {
      if (!c) return;
      if (!escolhidos.some(function (e) { return e.id === c.id; })) {
        if (multiplo) escolhidos.push({ id: c.id, nome: c.nome });
        else escolhidos = [{ id: c.id, nome: c.nome }];
      }
      input.value = "";
      lista.hidden = true;
      pintarEtiquetas();
      avisar();
    }

    function doServidor(q, meu) {
      fetch(window.API_BASE + "/api/condominios/sugerir?q=" + encodeURIComponent(q))
        .then(function (r) { return r.ok ? r.json() : []; })
        .then(function (itens) {
          if (meu !== pedido) return;
          sugestoes = itens || [];
          ativo = sugestoes.length ? 0 : -1;
          pintarLista();
        })
        .catch(function () { lista.hidden = true; });
    }

    /* a cada letra, na hora: a lista inteira já está na tela */
    function buscar() {
      var q = semAcento(input.value.trim());
      var meu = ++pedido;
      var naTela = filtrarNaTela(q, 60);
      if (naTela === null) {            // a lista ainda não chegou (ou não veio): espera por ela, ou pergunta ao servidor
        lerTodos().then(function (l) {
          if (meu !== pedido) return;
          if (l) buscar(); else if (q) doServidor(q, meu); else lista.hidden = true;
        });
        return;
      }
      if (!naTela.length && q.length >= 3) { clearTimeout(espera); espera = setTimeout(function () { doServidor(q, meu); }, 200); return; }
      sugestoes = naTela;
      ativo = sugestoes.length && q ? 0 : -1;
      pintarLista();
    }

    lerTodos();
    input.addEventListener("input", buscar);
    input.addEventListener("focus", buscar);
    input.addEventListener("click", function () { if (lista.hidden) buscar(); });
    input.addEventListener("keydown", function (e) {
      if (lista.hidden && e.key === "ArrowDown") { e.preventDefault(); buscar(); return; }
      if (lista.hidden && e.key !== "Enter") return;
      if (e.key === "ArrowDown") { e.preventDefault(); ativo = Math.min(ativo + 1, sugestoes.length - 1); pintarLista(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); ativo = Math.max(ativo - 1, 0); pintarLista(); }
      else if (e.key === "Enter") { e.preventDefault(); if (!lista.hidden && ativo >= 0) escolher(sugestoes[ativo]); }
      else if (e.key === "Escape") { lista.hidden = true; }
    });
    lista.addEventListener("mousedown", function (e) {
      var b = e.target.closest("[data-i]");
      if (!b) return;
      e.preventDefault();
      escolher(sugestoes[Number(b.dataset.i)]);
    });
    etiquetas.addEventListener("click", function (e) {
      var b = e.target.closest("[data-tirar]");
      if (!b) return;
      escolhidos.splice(Number(b.dataset.tirar), 1);
      pintarEtiquetas();
      avisar();
      input.focus();
    });
    input.addEventListener("blur", function () { setTimeout(function () { lista.hidden = true; }, 150); });

    return {
      valores: function () { return escolhidos.slice(); },
      definir: function (v) { escolhidos = (v || []).filter(function (c) { return c && c.id; }); pintarEtiquetas(); },
      limpar: function () { escolhidos = []; input.value = ""; pintarEtiquetas(); }
    };
  };
})();
