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
    ".cc__status button{font:inherit;border:0;background:none;color:inherit;text-decoration:underline;cursor:pointer;padding:0}" +
    ".cc__marcar{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:4px 14px}" +
    ".cc__marca{display:flex;align-items:center;gap:7px;font-size:13px;cursor:pointer;padding:3px 0}.cc__marca input{width:auto;margin:0}" +
    ".cc__mais{margin-top:6px;max-width:360px}" +
    ".cc__taxas{width:100%;border-collapse:collapse;font-size:13px}.cc__taxas th{text-align:left;font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--texto-fraco,#6b7280);padding:4px 6px}" +
    ".cc__taxas td{padding:3px 6px}.cc__taxas input{padding:6px 8px}.cc__taxas button{font:inherit;border:0;background:none;color:#b91c1c;cursor:pointer}" +
    ".cc textarea{width:100%;box-sizing:border-box;font:inherit;font-size:14px;padding:8px 10px;border:1px solid var(--borda,#d9dce3);border-radius:8px;min-height:72px}" +
    ".cc__ia{margin:12px 0;padding:10px 12px;border:1px solid #f0c36d;background:#fff8e6;border-radius:10px;font-size:13px}" +
    ".cc__ia b{display:block;margin-bottom:4px}.cc__ia ul{margin:4px 0 8px 18px;padding:0}.cc__ia .cc__botao{padding:6px 12px;font-size:13px}";
  document.head.appendChild(css);

  /* campo, rótulo, largura na grade (de 12), dica */
  var ENDERECO = [
    ["bairro", "Bairro", 4], ["logradouro", "Rua / avenida", 6], ["numero", "Número", 2],
    ["complemento", "Complemento / referência", 6, "ex.: próx. ao Condomínio Flex Parque Dez"],
    ["cep", "CEP", 2], ["cidade", "Cidade", 2], ["estado", "Estado", 2]
  ];
  /* 11/10 (Pedro): as duas telas do site antigo (Acqua): torres, andares, apartamentos por andar, ano de
     construção ("2011 e 2013"), construtora, revestimento; lazer / segurança / comodidades em caixinhas; taxas de
     condomínio e IPTU por quartos. O cadastro é UMA vez: vale para todos os imóveis do condomínio. */
  var ESTRUTURA = [
    ["torres", "Número de torres", 3, "ex.: 6"], ["andares", "Número de andares", 3, "ex.: 8"],
    ["aptos_por_andar", "Apartamentos por andar", 3, "ex.: 8"], ["elevador", "Elevador", 3, "Sim, possui 2 por torre / Não possui"],
    ["unidades", "Unidades", 3, "ex.: 120 casas"], ["construtora", "Construtora", 4, "ex.: Construtora Tecnisa"],
    ["ano_construcao", "Ano de construção", 2, "ex.: 2011 e 2013"], ["revestimento", "Revestimento", 3, "ex.: Pintura, Cerâmica"]
  ];
  var LAZER = ["Academia", "Bicicletário", "Brinquedoteca", "Car Wash Box", "Churrasqueira", "Ciclovia", "Cinema", "Espaço Zen",
    "Espaço gourmet", "Fitness", "Forno de Pizza", "Hidromassagem", "Jardim", "Lan House", "Lounge", "Pergolado", "Pet Place",
    "Piscina", "Pista de Caminhada", "Pista de Cooper", "Pista de Skate", "Playground", "Prainha", "Quadra de Areia",
    "Quadra de Vôlei", "Quadra de squash", "Quadra de tênis", "Quadra poliesportiva", "Redário", "Salão de festas",
    "Salão de jogos", "Sauna", "Solarium", "Spa"];
  var SEGURANCA = ["Condomínio fechado", "Guarita 24 Horas", "Portaria", "Segurança 24 horas", "Cerca elétrica",
    "Câmera de segurança", "Portão eletrônico", "Interfone"];
  var COMODIDADES = ["Elevador", "Lavanderia", "Gerador de Energia", "Gerador de Energia - 100%", "Gás Encanado", "Água de Poço", "Recepção"];
  var GRUPOS = [["lazer", "Lazer", LAZER], ["seguranca", "Segurança", SEGURANCA], ["comodidades", "Comodidades e serviços", COMODIDADES]];
  function caixinhas(g) {
    return '<p class="cc__secao">' + esc(g[1]) + '</p><div class="cc__marcar" data-grupo="' + g[0] + '">' +
      g[2].map(function (x) { return '<label class="cc__marca"><input type="checkbox" value="' + esc(x) + '"><span>' + esc(x) + "</span></label>"; }).join("") +
      '</div><div class="cc__chips" data-chips="' + g[0] + '"></div>' +
      '<input class="cc__mais" type="text" data-mais="' + g[0] + '" placeholder="Outro (Enter para acrescentar)">';
  }
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
        '<div class="cc__ia" id="cc-ia" hidden></div>' +
        '<p class="cc__secao">Endereço (fixo: os imóveis deste condomínio usam este)</p>' +
        '<div class="cc__grade">' + ENDERECO.map(campo).join("") + "</div>" +
        '<p class="cc__secao">O condomínio</p>' +
        '<div class="cc__grade">' + ESTRUTURA.map(campo).join("") + "</div>" +
        GRUPOS.map(caixinhas).join("") +
        '<p class="cc__dica" style="margin-top:8px">O andar, a torre e o número do apartamento são do imóvel: ficam no cadastro do imóvel.</p>' +
        '<p class="cc__secao">Taxas de condomínio e IPTU</p>' +
        '<table class="cc__taxas"><thead><tr><th>Número de quartos ou metragem</th><th>Valor do condomínio (R$)</th><th>Valor do IPTU (R$)</th><th></th></tr></thead>' +
          '<tbody id="cc-taxas"></tbody></table>' +
        '<button type="button" class="cc__botao" id="cc-taxa-mais" style="margin-top:6px">+ linha</button>' +
        '<p class="cc__dica">O condomínio varia por tamanho mas é fixo para todos daquele tamanho. O IPTU, só quando for fixo; o de cada casa fica no imóvel.</p>' +
        '<p class="cc__secao">Observação do condomínio</p>' +
        '<textarea id="cc-observacao" data-cc="observacao" maxlength="1000" placeholder="o que vale saber: portaria recebe encomenda, taxa inclui gás…"></textarea>' +
        '<div class="cc__acoes"><button type="submit" class="cc__botao cc__botao--principal" id="cc-salvar">Cadastrar condomínio</button>' +
          '<span class="cc__status" id="cc-status" role="status"></span></div>' +
      "</form>" +
      '<datalist id="cc-bairros"></datalist>' +
    "</div>";

  var $ = function (id) { return document.getElementById(id); };
  var form = $("cc-form"), buscar = $("cc-buscar"), lista = $("cc-lista"), status = $("cc-status");
  var itens = null, lendo = null, atual = null, achados = [], ativo = -1;
  var extras = { lazer: [], seguranca: [], comodidades: [] };   // o que foi marcado fora das caixinhas

  function dizer(texto, tipo, html) {
    status.className = "cc__status" + (tipo ? " cc__status--" + tipo : "");
    if (html) status.innerHTML = html; else status.textContent = texto || "";
  }

  function pintarChips(g) {
    var caixa = painel.querySelector('[data-chips="' + g + '"]');
    if (caixa) caixa.innerHTML = extras[g].map(function (x, i) {
      return '<span class="cc__chip">' + esc(x) + '<button type="button" data-tirar="' + i + '" data-de="' + g + '" aria-label="Tirar ' + esc(x) + '">×</button></span>';
    }).join("");
  }
  function marcados(g) {
    return Array.prototype.map.call(painel.querySelectorAll('[data-grupo="' + g + '"] input:checked'), function (i) { return i.value; }).concat(extras[g]);
  }
  function marcar(g, lista) {
    extras[g] = [];
    var caixas = Array.prototype.slice.call(painel.querySelectorAll('[data-grupo="' + g + '"] input'));
    caixas.forEach(function (i) { i.checked = false; });
    (lista || []).forEach(function (x) {
      var c = caixas.filter(function (i) { return semAcento(i.value) === semAcento(x); })[0];
      if (c) c.checked = true; else if (x && String(x).trim()) extras[g].push(String(x).trim());
    });
    pintarChips(g);
  }
  function acrescentar(g, texto) {
    String(texto || "").split(/[,;\n]/).forEach(function (p) {
      p = p.trim();
      if (p && !marcados(g).some(function (x) { return semAcento(x) === semAcento(p); })) extras[g].push(p);
    });
    pintarChips(g);
  }
  /* 348: o que a IA sugeriu fica numa caixa amarela; "Usar o que está vazio" preenche só os campos vazios e as
     caixinhas não marcadas -- e nada é gravado até o Salvar. */
  var sugestao = null;
  function mostrarSugestao(s) {
    sugestao = s || null;
    var caixa = $("cc-ia");
    if (!caixa) return;
    if (!s) { caixa.hidden = true; caixa.innerHTML = ""; return; }
    var itens = [["Construtora", s.construtora], ["Ano de construção", s.ano_construcao], ["Torres", s.torres], ["Andares", s.andares],
      ["Apartamentos por andar", s.aptos_por_andar], ["Elevador", s.elevador === true ? "sim" : s.elevador === false ? "não" : null],
      ["Rua / avenida", s.logradouro], ["Lazer", (s.lazer || []).join(", ")], ["Segurança", (s.seguranca || []).join(", ")],
      ["Comodidades", (s.comodidades || []).join(", ")], ["Observação", s.observacao]].filter(function (p) { return p[1] != null && p[1] !== ""; });
    caixa.hidden = false;
    caixa.innerHTML = "<b>Sugestão da IA (confiança " + esc(s.confianca || "?") + ") — confira antes de usar</b>" +
      "<ul>" + itens.map(function (p) { return "<li>" + esc(p[0]) + ": " + esc(String(p[1])) + "</li>"; }).join("") + "</ul>" +
      '<button type="button" class="cc__botao" id="cc-ia-usar">Usar o que está vazio</button>';
  }
  function usarSugestao() {
    var s = sugestao;
    if (!s) return;
    [["construtora", s.construtora], ["ano_construcao", s.ano_construcao], ["torres", s.torres], ["andares", s.andares],
     ["aptos_por_andar", s.aptos_por_andar], ["logradouro", s.logradouro],
     ["elevador", s.elevador === true ? "Sim, possui elevador" : s.elevador === false ? "Não possui elevador" : null],
     ["observacao", s.observacao]].forEach(function (p) {
      var el = $("cc-" + p[0]);
      if (el && p[1] != null && p[1] !== "" && !String(el.value || "").trim()) el.value = String(p[1]);
    });
    GRUPOS.forEach(function (g) { (s[g[0]] || []).forEach(function (x) {
      if (!marcados(g[0]).some(function (y) { return semAcento(y) === semAcento(x); })) {
        var c = Array.prototype.filter.call(painel.querySelectorAll('[data-grupo="' + g[0] + '"] input'), function (i) { return semAcento(i.value) === semAcento(x); })[0];
        if (c) c.checked = true; else acrescentar(g[0], x);
      }
    }); });
    dizer("Sugestão aplicada nos campos vazios. Confira e clique em Salvar.", "ok");
  }
  function linhaTaxa(t) {
    t = t || {};
    var quem = t.quartos != null ? String(t.quartos) : (t.metragem || "");
    return "<tr><td><input type=\"text\" data-taxa=\"quem\" value=\"" + esc(quem) + "\" placeholder=\"3 (quartos) ou 90 m²\"></td>" +
      "<td><input type=\"text\" inputmode=\"decimal\" data-taxa=\"condominio\" value=\"" + esc(t.condominio == null ? "" : t.condominio) + "\"></td>" +
      "<td><input type=\"text\" inputmode=\"decimal\" data-taxa=\"iptu\" value=\"" + esc(t.iptu == null ? "" : t.iptu) + "\"></td>" +
      "<td><button type=\"button\" data-taxa-tirar>Remover</button></td></tr>";
  }
  function taxasDaTela() {
    return Array.prototype.map.call($("cc-taxas").querySelectorAll("tr"), function (tr) {
      var quem = tr.querySelector('[data-taxa="quem"]').value.trim();
      var eQuartos = /^\d{1,2}$/.test(quem);
      return { quartos: eQuartos ? quem : "", metragem: eQuartos ? "" : quem,
               condominio: tr.querySelector('[data-taxa="condominio"]').value.trim(), iptu: tr.querySelector('[data-taxa="iptu"]').value.trim() };
    }).filter(function (t) { return t.condominio || t.iptu; });
  }

  function preencher(c) {
    atual = c || null;
    form.querySelectorAll("[data-cc]").forEach(function (el) {
      var v = c ? c[el.dataset.cc] : null;   // condomínio novo: o Tipo começa em "Prédio de apartamentos", não vazio
      el.value = v == null ? (el.tagName === "SELECT" ? "apartamentos" : "") : String(v);
    });
    GRUPOS.forEach(function (g) { marcar(g[0], c ? c[g[0]] : []); });
    mostrarSugestao(c && c.ia_sugestao);
    $("cc-taxas").innerHTML = (c && Array.isArray(c.taxas) ? c.taxas : []).map(linhaTaxa).join("");
    painel.querySelectorAll("[data-mais]").forEach(function (i) { i.value = ""; });
    $("cc-titulo").textContent = c ? c.nome : "Novo condomínio";
    $("cc-sub").textContent = c
      ? (c.imoveis ? c.imoveis + " imóvel(is) ligado(s) a este condomínio." : "Nenhum imóvel ligado a este condomínio ainda.") +
        (c.fonte ? " Ficha: " + c.fonte + "." : "")
      : "Cadastre uma vez. Depois, no cadastro de imóvel, basta escolher o condomínio.";
    $("cc-salvar").textContent = c ? "Salvar alterações" : "Cadastrar condomínio";
    dizer("");
  }

  function listas() {
    var bairros = {};
    (itens || []).forEach(function (c) { if (c.bairro) bairros[c.bairro] = 1; });
    $("cc-bairros").innerHTML = Object.keys(bairros).sort().map(function (b) { return '<option value="' + esc(b) + '">'; }).join("");
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
  painel.addEventListener("click", function (e) {
    var b = e.target.closest("[data-tirar]");
    if (b) { extras[b.dataset.de].splice(Number(b.dataset.tirar), 1); pintarChips(b.dataset.de); return; }
    var t = e.target.closest("[data-taxa-tirar]");
    if (t) { t.closest("tr").remove(); return; }
    if (e.target.id === "cc-taxa-mais") $("cc-taxas").insertAdjacentHTML("beforeend", linhaTaxa());
    if (e.target.id === "cc-ia-usar") usarSugestao();
  });
  painel.addEventListener("keydown", function (e) {
    var m = e.target.closest ? e.target.closest("[data-mais]") : null;
    if (m && (e.key === "Enter" || e.key === ",")) { e.preventDefault(); acrescentar(m.dataset.mais, m.value); m.value = ""; }
  });

  status.addEventListener("click", function (e) {
    var b = e.target.closest("[data-abrir]");
    if (b) abrir(Number(b.dataset.abrir));
  });

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    painel.querySelectorAll("[data-mais]").forEach(function (m) { if (m.value.trim()) { acrescentar(m.dataset.mais, m.value); m.value = ""; } });
    var dados = { lazer: marcados("lazer"), seguranca: marcados("seguranca"), comodidades: marcados("comodidades"), taxas: taxasDaTela() };
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
        // quem abriu este formulário de outro lugar (o Cadastro rápido) fica sabendo qual foi gravado
        try { window.dispatchEvent(new CustomEvent("condominio-salvo", { detail: { id: id, nome: dados.nome, criado: !!x.d.criado } })); } catch (e2) { /* navegador antigo */ }
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
  /* O Cadastro rápido (09/10) mostra este mesmo formulário dentro do popup: o painel é emprestado (o DOM muda de
     lugar e volta), e um condomínio novo já chega com o que a ficha do dono disse (nome, bairro, rua). */
  window.condominioNovoCom = function (inicio) {
    preencher(null);
    var d = inicio || {};
    ["nome", "bairro", "logradouro", "numero", "tipo"].forEach(function (k) {
      var el = form.querySelector('[data-cc="' + k + '"]');
      if (el && d[k]) el.value = d[k];
    });
    carregar();
    return painel;
  };
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
