/* ==========================================================================
   Imob Easy — Seletor de condomínio (revisão 11/09/2026)

   Pedido do Tel: "quando digitar ele sugira os nomes de condomínios, e
   funcione de forma a marcação de condomínio". Enquanto digita (espera
   250 ms), busca em /api/condominios/sugerir -- sem acento, acha no meio do
   nome ("acquarelle" acha "Condomínio Acquarelle") e tolera erro de
   digitação. Escolher vira uma ETIQUETA com o id guardado; o × tira.

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
            esc(c.nome) + "<small>" + esc([c.bairro, c.imoveis ? c.imoveis + " imóvel(is)" : ""].filter(Boolean).join(" · ")) + "</small></button>";
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

    function buscar() {
      var q = input.value.trim();
      if (q.length < 2) { lista.hidden = true; return; }
      var meu = ++pedido;
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

    input.addEventListener("input", function () { clearTimeout(espera); espera = setTimeout(buscar, 250); });
    input.addEventListener("keydown", function (e) {
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
