/* ==========================================================================
   Imob Easy — aba "Adicionar condomínio" de Todos os imóveis (08/10/2026)

   Pedro: "quero uma aba nova adicionar condomínio ... quero o cadastro de
   condomínio no site normal aba imóveis e no crm também" e "todo condomínio vai
   ter endereço fixo".

   O condomínio é cadastrado UMA vez, com o endereço e o que é fixo dele (torres,
   andares, elevador, características). O cadastro de imóvel só escolhe o
   condomínio: o endereço vem daqui.

   Cria e edita. Em cima, o campo de busca desce a lista filtrando letra a letra;
   clicar num nome abre aquele condomínio para editar. O que está escrito na
   tela é o que vale: campo apagado fica apagado.

   Lê  GET  api/imoveis/condominios        (atrás da senha do painel)
   Grava POST api/imoveis/condominios  e  PUT api/imoveis/condominios/<id>
   -- debaixo de /admin/api/imoveis de propósito: é o que a aba Imóveis do CRM
   deixa passar, então esta mesma tela funciona lá dentro sem cópia.

   window.abrirCadastroDeCondominio(id) abre a aba já naquele condomínio (é o
   que o "editar" da aba Condomínios e o link do cadastro de imóvel chamam).
   ========================================================================== */
(function () {
  "use strict";

  var aba = document.querySelector('[data-painel-abre="condominio-novo"]');
  var painel = document.querySelector('[data-painel="condominio-novo"]');
  if (!aba || !painel) return;

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function semAcento(t) {
    return String(t == null ? "" : t).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }

  var css = document.createElement("style");
  css.textContent =
    ".cc{max-width:980px}" +
    ".cc__topo{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end;margin:0 0 14px}" +
    ".cc__busca{position:relative;flex:1 1 320px;min-width:0}" +
    ".cc label{display:block;font-size:12px;font-weight:600;margin:0 0 4px;color:var(--texto-medio,#4b5563)}" +
    ".cc input,.cc select{width:100%;box-sizing:border-box;font:inherit;font-size:14px;padding:8px 10px;border:1px solid var(--borda,#d9dce3);" +
      "border-radius:8px;background:var(--superficie,#fff);color:var(--texto,#1c2533)}" +
    ".cc input:focus,.cc select:focus{outline:0;border-color:var(--azul,#6d28d9);box-shadow:0 0 0 3px rgba(109,40,217,.15)}" +
    ".cc__lista{position:absolute;left:0;right:0;top:100%;z-index:60;margin-top:2px;max-height:320px;overflow-y:auto;" +
      "background:var(--superficie,#fff);border:1px solid var(--borda,#d9dce3);border-radius:8px;box-shadow:0 8px 24px rgba(20,30,60,.16)}" +
    ".cc__lista[hidden]{display:none}" +
    ".cc__item{display:block;width:100%;text-align:left;border:0;background:none;padding:8px 10px;cursor:pointer;font:inherit;font-size:14px;color:inherit}" +
    ".cc__item small{display:block;color:var(--texto-fraco,#6b7280);font-size:12px}" +
    ".cc__item:hover,.cc__item[aria-selected=true]{background:var(--azul-claro,#f1eaff)}" +
    ".cc__vazio{padding:8px 10px;color:var(--texto-fraco,#6b7280);font-size:13px}" +
    ".cc__botao{font:inherit;font-size:14px;font-weight:600;padding:9px 16px;border-radius:8px;cursor:pointer;" +
      "border:1px solid var(--borda,#d9dce3);background:var(--superficie,#fff);color:var(--texto,#1c2533)}" +
    ".cc__botao--principal{background:var(--azul,#6d28d9);border-color:var(--azul,#6d28d9);color:#fff}" +
    ".cc__botao:disabled{opacity:.55;cursor:default}" +
    ".cc__form{border:1px solid var(--borda,#d9dce3);border-radius:12px;padding:16px 18px;background:var(--superficie,#fff)}" +
    ".cc__titulo{margin:0 0 2px;font-size:18px}" +
    ".cc__sub{margin:0 0 14px;color:var(--texto-fraco,#6b7280);font-size:13px}" +
    ".cc__secao{margin:18px 0 8px;font-size:12px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--texto-fraco,#6b7280)}" +
    ".cc__grade{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:12px}" +
    ".cc__campo{grid-column:span 3;min-width:0}.cc__campo--6{grid-column:span 6}.cc__campo--4{grid-column:span 4}" +
    ".cc__campo--2{grid-column:span 2}.cc__campo--12{grid-column:span 12}" +
    "@media (max-width:760px){.cc__campo,.cc__campo--6,.cc__campo--4,.cc__campo--2{grid-column:span 12}}" +
    ".cc__dica{margin:4px 0 0;font-size:12px;color:var(--texto-fraco,#6b7280)}" +
    ".cc__chips{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 6px}.cc__chips:empty{display:none}" +
    ".cc__chip{display:inline-flex;align-items:center;gap:4px;padding:3px 4px 3px 10px;border-radius:999px;font-size:12px;" +
      "background:var(--azul-claro,#f1eaff);border:1px solid var(--azul-borda,#d3c1f4);color:var(--texto,#1c2533)}" +
    ".cc__chip button{border:0;background:none;cursor:pointer;font-size:14px;line-height:1;padding:0 4px;color:inherit}" +
    ".cc__acoes{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin-top:18px}" +
    ".cc__status{font-size:13px}.cc__status--ok{color:#15803d}.cc__status--erro{color:#b91c1c}" +
    ".cc__status button{font:inherit;border:0;background:none;color:inherit;text-decoration:underline;cursor:pointer;padding:0}";
  document.head.appendChild(css);

  /* campo, rótulo, largura na grade (de 12), dica */
  var ENDERECO = [
    ["bairro", "Bairro", 4], ["logradouro", "Rua / avenida", 6], ["numero", "Número", 2],
    ["cep", "CEP", 3], ["cidade", "Cidade", 4], ["estado", "Estado", 2]
  ];
  var ESTRUTURA = [
    ["torres", "Torres", 3, "ex.: 2 torres"], ["andares", "Andares", 3, "ex.: 18 andares"],
    ["aptos_por_andar", "Apartamentos por andar", 3, "ex.: 4 por andar"], ["elevador", "Elevador", 3, "ex.: Sim, possui 2 elevadores"],
    ["unidades", "Unidades", 3, "ex.: 120 casas"], ["construtora", "Construtora", 4], ["ano_lancamento", "Ano de lançamento", 2],
    ["revestimento", "Revestimento", 3]
  ];
  function campo(c) {
    return '<div class="cc__campo cc__campo--' + c[2] + '"><label for="cc-' + c[0] + '">' + esc(c[1]) + "</label>" +
      '<input id="cc-' + c[0] + '" data-cc="' + c[0] + '" type="text"' + (c[0] === "bairro" ? ' list="cc-bairros"' : "") +
      (c[3] ? ' placeholder="' + esc(c[3]) + '"' : "") + (c[0] === "ano_lancamento" ? ' inputmode="numeric" maxlength="4"' : "") + "></div>";
  }

  painel.innerHTML =
    '<div class="cc">' +
      '<div class="cc__topo">' +
        '<div class="cc__busca"><label for="cc-buscar">Editar um condomínio que já existe</label>' +
          '<input id="cc-buscar" type="text" autocomplete="off" placeholder="Digite o nome (a lista desce a cada letra)">' +
          '<div class="cc__lista" id="cc-lista" role="listbox" hidden></div></div>' +
        '<button type="button" class="cc__botao" id="cc-limpar">+ Condomínio novo</button>' +
      "</div>" +
      '<form class="cc__form" id="cc-form" autocomplete="off" novalidate>' +
        '<h2 class="cc__titulo" id="cc-titulo">Novo condomínio</h2>' +
        '<p class="cc__sub" id="cc-sub"></p>' +
        '<div class="cc__grade">' +
          '<div class="cc__campo cc__campo--6"><label for="cc-nome">Nome do condomínio *</label>' +
            '<input id="cc-nome" data-cc="nome" type="text" maxlength="160" placeholder="como ele é conhecido"></div>' +
          '<div class="cc__campo cc__campo--4"><label for="cc-tipo">Tipo</label><select id="cc-tipo" data-cc="tipo">' +
            '<option value="apartamentos">Prédio de apartamentos</option><option value="casas_lotes">Casas ou lotes</option></select></div>' +
        "</div>" +
        '<p class="cc__secao">Endereço (fixo: os imóveis deste condomínio usam este)</p>' +
        '<div class="cc__grade">' + ENDERECO.map(campo).join("") + "</div>" +
        '<p class="cc__secao">O condomínio</p>' +
        '<div class="cc__grade">' + ESTRUTURA.map(campo).join("") + "</div>" +
        '<p class="cc__secao">Características do condomínio</p>' +
        '<div class="cc__chips" id="cc-chips"></div>' +
        '<div class="cc__grade"><div class="cc__campo cc__campo--6">' +
          '<input id="cc-carac" type="text" list="cc-caracs" placeholder="Piscina, academia, portaria 24h… (Enter para acrescentar)">' +
          '<p class="cc__dica">O andar e o número do apartamento são do imóvel, não do condomínio: ficam no cadastro do imóvel.</p></div></div>' +
        '<div class="cc__acoes"><button type="submit" class="cc__botao cc__botao--principal" id="cc-salvar">Cadastrar condomínio</button>' +
          '<span class="cc__status" id="cc-status" role="status"></span></div>' +
      "</form>" +
      '<datalist id="cc-bairros"></datalist><datalist id="cc-caracs"></datalist>' +
    "</div>";

  var $ = function (id) { return document.getElementById(id); };
  var form = $("cc-form"), buscar = $("cc-buscar"), lista = $("cc-lista"), status = $("cc-status");
  var itens = null, lendo = null, atual = null, lazer = [], achados = [], ativo = -1;

  function dizer(texto, tipo, html) {
    status.className = "cc__status" + (tipo ? " cc__status--" + tipo : "");
    if (html) status.innerHTML = html; else status.textContent = texto || "";
  }

  function pintarChips() {
    $("cc-chips").innerHTML = lazer.map(function (x, i) {
      return '<span class="cc__chip">' + esc(x) + '<button type="button" data-tirar="' + i + '" aria-label="Tirar ' + esc(x) + '">×</button></span>';
    }).join("");
  }
  function acrescentar(texto) {
    String(texto || "").split(/[,;\n]/).forEach(function (p) {
      p = p.trim();
      if (p && !lazer.some(function (x) { return semAcento(x) === semAcento(p); })) lazer.push(p);
    });
    pintarChips();
  }

  function preencher(c) {
    atual = c || null;
    form.querySelectorAll("[data-cc]").forEach(function (el) {
      var v = c ? c[el.dataset.cc] : "";
      el.value = v == null ? (el.tagName === "SELECT" ? "apartamentos" : "") : String(v);
    });
    lazer = c && Array.isArray(c.lazer) ? c.lazer.slice() : [];
    pintarChips();
    $("cc-carac").value = "";
    $("cc-titulo").textContent = c ? c.nome : "Novo condomínio";
    $("cc-sub").textContent = c
      ? (c.imoveis ? c.imoveis + " imóvel(is) ligado(s) a este condomínio." : "Nenhum imóvel ligado a este condomínio ainda.") +
        (c.fonte ? " Ficha: " + c.fonte + "." : "")
      : "Cadastre uma vez. Depois, no cadastro de imóvel, basta escolher o condomínio.";
    $("cc-salvar").textContent = c ? "Salvar alterações" : "Cadastrar condomínio";
    dizer("");
  }

  function listas() {
    var bairros = {}, caracs = {};
    (itens || []).forEach(function (c) {
      if (c.bairro) bairros[c.bairro] = 1;
      (c.lazer || []).forEach(function (x) { caracs[x] = (caracs[x] || 0) + 1; });
    });
    $("cc-bairros").innerHTML = Object.keys(bairros).sort().map(function (b) { return '<option value="' + esc(b) + '">'; }).join("");
    $("cc-caracs").innerHTML = Object.keys(caracs).sort(function (a, b) { return caracs[b] - caracs[a]; }).slice(0, 80)
      .map(function (x) { return '<option value="' + esc(x) + '">'; }).join("");
  }

  function carregar(forcar) {
    if (itens && !forcar) return Promise.resolve(itens);
    if (lendo && !forcar) return lendo;
    lendo = fetch("api/imoveis/condominios", { credentials: "same-origin" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (d) {
        itens = (d.itens || []).map(function (c) { c._n = semAcento(c.nome); c._b = semAcento(c.bairro); return c; });
        listas();
        return itens;
      })
      .catch(function (e) { lendo = null; dizer("Não consegui ler os condomínios (" + e.message + ").", "erro"); return null; });
    return lendo;
  }

  /* a lista que desce, letra a letra */
  function pintarLista() {
    var q = semAcento(buscar.value.trim());
    if (!itens) { lista.innerHTML = '<div class="cc__vazio">Carregando…</div>'; lista.hidden = false; return; }
    var comeca = [], resto = [];
    itens.forEach(function (c) {
      if (!q) comeca.push(c);
      else if (c._n.indexOf(q) === 0 || c._n.replace(/^((condominio|residencial|edificio)\s+)+/, "").indexOf(q) === 0) comeca.push(c);
      else if (c._n.indexOf(q) >= 0 || (q.length >= 3 && c._b.indexOf(q) >= 0)) resto.push(c);
    });
    achados = comeca.concat(resto).slice(0, 80);
    ativo = achados.length && q ? 0 : -1;
    lista.innerHTML = achados.length
      ? achados.map(function (c, i) {
          return '<button type="button" class="cc__item" role="option" data-i="' + i + '" aria-selected="' + (i === ativo) + '">' + esc(c.nome) +
            "<small>" + esc([c.bairro, c.imoveis ? c.imoveis + " imóvel(is)" : "sem imóvel", c.logradouro ? "" : "sem endereço"].filter(Boolean).join(" · ")) + "</small></button>";
        }).join("")
      : '<div class="cc__vazio">Nenhum condomínio com esse nome. Use "+ Condomínio novo" para cadastrar.</div>';
    lista.hidden = false;
  }
  function escolher(c) {
    if (!c) return;
    lista.hidden = true; buscar.value = "";
    preencher(c);
    $("cc-nome").focus();
  }
  buscar.addEventListener("input", pintarLista);
  buscar.addEventListener("focus", function () { carregar().then(pintarLista); });
  buscar.addEventListener("blur", function () { setTimeout(function () { lista.hidden = true; }, 150); });
  buscar.addEventListener("keydown", function (e) {
    if (lista.hidden) return;
    if (e.key === "ArrowDown") { e.preventDefault(); ativo = Math.min(ativo + 1, achados.length - 1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); ativo = Math.max(ativo - 1, 0); }
    else if (e.key === "Enter") { e.preventDefault(); if (ativo >= 0) escolher(achados[ativo]); return; }
    else if (e.key === "Escape") { lista.hidden = true; return; }
    else return;
    lista.querySelectorAll("[data-i]").forEach(function (b, i) { b.setAttribute("aria-selected", i === ativo); });
    var el = lista.querySelector('[aria-selected="true"]'); if (el && el.scrollIntoView) el.scrollIntoView({ block: "nearest" });
  });
  lista.addEventListener("mousedown", function (e) {
    var b = e.target.closest("[data-i]");
    if (!b) return;
    e.preventDefault();
    escolher(achados[Number(b.dataset.i)]);
  });

  $("cc-limpar").addEventListener("click", function () { preencher(null); $("cc-nome").focus(); });
  $("cc-chips").addEventListener("click", function (e) {
    var b = e.target.closest("[data-tirar]");
    if (!b) return;
    lazer.splice(Number(b.dataset.tirar), 1); pintarChips();
  });
  $("cc-carac").addEventListener("keydown", function (e) {
    if (e.key === "Enter" || e.key === ",") { e.preventDefault(); acrescentar(this.value); this.value = ""; }
  });
  $("cc-carac").addEventListener("change", function () { if (this.value.trim()) { acrescentar(this.value); this.value = ""; } });

  status.addEventListener("click", function (e) {
    var b = e.target.closest("[data-abrir]");
    if (b) abrir(Number(b.dataset.abrir));
  });

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    acrescentar($("cc-carac").value); $("cc-carac").value = "";
    var dados = { lazer: lazer.slice() };
    form.querySelectorAll("[data-cc]").forEach(function (el) { dados[el.dataset.cc] = el.value.trim(); });
    if (dados.nome.length < 3) { dizer("Escreva o nome do condomínio.", "erro"); $("cc-nome").focus(); return; }
    var editando = atual && atual.id;
    var botao = $("cc-salvar");
    botao.disabled = true; dizer("Gravando…");
    fetch("api/imoveis/condominios" + (editando ? "/" + encodeURIComponent(atual.id) : ""), {
      method: editando ? "PUT" : "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json" }, body: JSON.stringify(dados)
    })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { return { ok: r.ok, d: d }; }); })
      .then(function (x) {
        botao.disabled = false;
        if (!x.ok || !x.d.ok) {
          if (x.d.id) {
            dizer("", "erro", "Já existe um condomínio com esse nome. <button type=\"button\" data-abrir=\"" + Number(x.d.id) + "\">Abrir o que já existe</button>");
          } else {
            dizer(x.d.motivo || x.d.erro || "Não consegui gravar.", "erro");
          }
          return;
        }
        var id = x.d.id;
        if (window.recarregarCondominios) window.recarregarCondominios();   // os campos de condomínio da página passam a ver este
        carregar(true).then(function (l) {
          var c = (l || []).filter(function (i) { return i.id === id; })[0];
          if (c) preencher(c);
          var mudou = (x.d.mudou || []).length;
          dizer(x.d.criado ? "Condomínio cadastrado. Já aparece nos campos de condomínio."
                           : (mudou ? "Salvo (" + mudou + " campo" + (mudou > 1 ? "s" : "") + ")." : "Nada mudou.") +
                             (x.d.imoveis_renomeados ? " " + x.d.imoveis_renomeados + " imóvel(is) passaram a mostrar o nome novo." : ""), "ok");
        });
      })
      .catch(function (err) { botao.disabled = false; dizer("Não consegui gravar: " + err.message, "erro"); });
  });

  function abrir(id) {
    return carregar().then(function (l) {
      var c = (l || []).filter(function (i) { return i.id === Number(id); })[0];
      if (c) preencher(c);
    });
  }
  window.abrirCadastroDeCondominio = function (id) {
    if (aba.getAttribute("aria-selected") !== "true") aba.click();
    if (id != null) abrir(id);
    try { painel.scrollIntoView({ block: "start" }); } catch (e) { /* navegador antigo */ }
  };

  preencher(null);
  aba.addEventListener("click", function () { carregar(); });

  /* imoveis.html?condominio=123 (ou ?condominio=novo): chega já na aba, naquele condomínio */
  var pedido = new URLSearchParams(location.search).get("condominio");
  if (pedido) {
    setTimeout(function () { window.abrirCadastroDeCondominio(/^\d+$/.test(pedido) ? Number(pedido) : null); }, 0);
  }
})();
