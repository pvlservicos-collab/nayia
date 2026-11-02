/* ==========================================================================
   MÉTRICAS POR IMÓVEL (563, Pedro 02/11/2026) -- a aba "Imóveis" do painel do Início
   "metricas de imoveis que mais tiveram visitas, que mais tiveram vendas x locações, varios numeros ... uma aba de metricas
   só por imovel, visitas, visitas buscadas, vezes que o card foi enviado, todos os filtros disponiveis".

   Uma chamada: GET /admin/api/painel/imoveis?de&ate&parados -> uma linha por imóvel (site_imoveis_metricas). Os filtros
   são feitos aqui, na tela, sem nova chamada. O período e "mostrar os parados" é que pedem outra leitura.
   O painel-metricas.js chama PainelImoveis.abrir() na primeira vez que a aba abre.
   ========================================================================== */
(function () {
  "use strict";

  var raiz = document.querySelector('.pm-aba[data-aba="imoveis"]');
  if (!raiz) return;

  var DESDE = "2026-09-01";   // o começo dos registros de visita e de card
  var est = { periodo: "30d", de: "", ate: "", parados: false, dados: [], f: {}, ordem: "visitas", sentido: -1, pagina: 0, lido: false, lendo: false };
  var POR_PAGINA = 50;

  /* ---------------- pequenas ajudas ---------------- */
  function hoje() { return new Date().toLocaleDateString("en-CA", { timeZone: "America/Manaus" }); }
  function somaDias(iso, n) { var d = new Date(iso + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function n(v) { return v == null || isNaN(v) ? "—" : Number(v).toLocaleString("pt-BR"); }
  function pct(v) { return v == null || !isFinite(v) ? "—" : (v * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + "%"; }
  function reais(v) { return v ? "R$ " + Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 0 }) : ""; }
  function num(v) { return Number(v) || 0; }
  function intervalo() {
    var h = hoje();
    switch (est.periodo) {
      case "7d": return { de: somaDias(h, -6), ate: h };
      case "90d": return { de: somaDias(h, -89), ate: h };
      case "mes": return { de: h.slice(0, 8) + "01", ate: h };
      case "tudo": return { de: DESDE, ate: h };
      case "custom": return { de: est.de || DESDE, ate: est.ate || h };
      default: return { de: somaDias(h, -29), ate: h };
    }
  }

  /* o negócio do imóvel pelo que ele tem de valor: venda, locação ou os dois */
  function negocio(r) {
    var v = num(r.valor_venda) > 0, a = num(r.valor_aluguel) > 0;
    return v && a ? "ambos" : v ? "venda" : a ? "locacao" : "sem";
  }
  var ROT_NEGOCIO = { venda: "Venda", locacao: "Locação", ambos: "Venda e locação", sem: "Sem valor" };
  function visitas(r) { return num(r.visitas_parceria) + num(r.visitas_leads); }
  function cards(r) { return num(r.cards_parceria) + num(r.cards_leads); }
  function leads(r) { return num(r.leads_olx) + num(r.leads_cnm); }
  function valorBase(r) {
    var neg = est.f.negocio;
    if (neg === "locacao") return num(r.valor_aluguel);
    if (neg === "venda") return num(r.valor_venda);
    return num(r.valor_venda) > 0 ? num(r.valor_venda) : num(r.valor_aluguel);
  }

  /* ---------------- as colunas da tabela (também são as ordens) ---------------- */
  var COLUNAS = [
    { k: "visitas", rot: "Visitas pedidas", f: visitas, info: "visitas pedidas no período, pelo dia em que foram marcadas (Parceria + Leads)" },
    { k: "confirmadas", rot: "Confirmadas", f: function (r) { return num(r.visitas_confirmadas); }, info: "visitas confirmadas no período (corretor, equipe ou fim do fluxo)" },
    { k: "agendadas", rot: "Para o período", f: function (r) { return num(r.visitas_agendadas_para); }, info: "visitas marcadas PARA um dia do período, sem as canceladas e expiradas" },
    { k: "realizadas", rot: "Realizadas", f: function (r) { return num(r.visitas_realizadas); }, info: "o que a equipe marcou como Realizada ou Fechou negócio na aba Visitas, pelo dia da visita" },
    { k: "fechou", rot: "Fechou", f: function (r) { return num(r.visitas_fechou); }, info: "visitas marcadas como Fechou negócio" },
    { k: "cards", rot: "Cards enviados", f: cards, info: "vezes que o card saiu: Parceria (a mesma pessoa no mesmo dia conta uma vez) + clientes do Leads" },
    { k: "pessoas", rot: "Pessoas", f: function (r) { return num(r.pessoas_parceria) + num(r.pessoas_leads); }, info: "pessoas diferentes que receberam o card" },
    { k: "grupos", rot: "Grupos", f: function (r) { return num(r.posts_grupo); }, info: "posts do imóvel nos grupos de corretores (cada grupo conta um post)" },
    { k: "leads", rot: "Leads", f: leads, info: "clientes que chegaram perguntando por ele (OLX no WhatsApp Leads e Chaves na Mão)" }
  ];
  function colunaPorK(k) { return COLUNAS.filter(function (c) { return c.k === k; })[0]; }

  /* ---------------- os filtros ---------------- */
  function vazio(v) { return v == null || v === ""; }
  function passa(r) {
    var f = est.f;
    if (f.negocio && negocio(r) !== f.negocio && !(f.negocio !== "sem" && negocio(r) === "ambos")) return false;
    if (f.status && r.status !== f.status) return false;
    if (f.tipo && r.tipo !== f.tipo) return false;
    if (f.bairro && r.bairro !== f.bairro) return false;
    if (f.condominio && (r.condominio || "").toLowerCase().indexOf(f.condominio.toLowerCase()) < 0) return false;
    if (f.quartos) { var q = num(r.quartos); if (f.quartos === "4" ? q < 4 : q !== Number(f.quartos)) return false; }
    if (f.mobilia && (r.mobilia || "") !== f.mobilia) return false;
    if (f.origem && (r.origem || "") !== f.origem) return false;
    if (f.parceiro === "nosso" && r.parceiro) return false;
    if (f.parceiro === "parceiro" && !r.parceiro) return false;
    if (f.captador && (r.captado_por || "") !== f.captador) return false;
    if (f.cnm === "sim" && !r.no_cnm) return false;
    if (f.cnm === "nao" && r.no_cnm) return false;
    if (f.olx === "sim" && !r.no_olx) return false;
    if (f.olx === "nao" && r.no_olx) return false;
    if (f.site === "sim" && !r.no_site) return false;
    if (f.site === "nao" && r.no_site) return false;
    if (!vazio(f.min) || !vazio(f.max)) {
      var v = valorBase(r);
      if (!vazio(f.min) && v < Number(f.min)) return false;
      if (!vazio(f.max) && v > Number(f.max)) return false;
    }
    if (f.soVisitas && !visitas(r)) return false;
    if (f.soCards && !cards(r)) return false;
    if (f.soSemCard && cards(r)) return false;
    if (f.busca) {
      var t = (r.codigo + " " + (r.condominio || "") + " " + (r.bairro || "") + " " + (r.tipo || "")).toLowerCase();
      if (t.indexOf(f.busca.toLowerCase()) < 0) return false;
    }
    return true;
  }

  function distintos(campo) {
    var m = {};
    est.dados.forEach(function (r) { var v = r[campo]; if (v != null && v !== "") m[v] = (m[v] || 0) + 1; });
    return Object.keys(m).sort(function (a, b) { return a.localeCompare(b, "pt-BR"); });
  }
  function opcoes(lista, atual, primeiro) {
    return '<option value="">' + esc(primeiro) + "</option>" + lista.map(function (v) {
      return '<option value="' + esc(v) + '"' + (String(atual) === String(v) ? " selected" : "") + ">" + esc(v) + "</option>";
    }).join("");
  }

  /* ---------------- a estrutura (desenhada uma vez) ---------------- */
  function montar() {
    raiz.innerHTML =
      '<p class="pm-aba__intro">Cada imóvel com o que aconteceu com ele no período: visitas pedidas, confirmadas e realizadas, vezes que o card foi enviado, posts em grupos e leads que chegaram por ele. Use os filtros e clique no título de uma coluna para ordenar.</p>' +
      '<div class="pi-barra">' +
        '<div class="pm-seg" data-grupo="pi-periodo" role="group" aria-label="Período">' +
          '<button type="button" data-v="7d">7 dias</button><button type="button" data-v="30d">30 dias</button>' +
          '<button type="button" data-v="90d">90 dias</button><button type="button" data-v="mes">Este mês</button>' +
          '<button type="button" data-v="tudo">Tudo (desde 01/09)</button><button type="button" data-v="custom">Escolher</button>' +
        "</div>" +
        '<span class="pm-datas pi-datas" hidden><input type="date" id="pi-de" aria-label="De"><span>a</span><input type="date" id="pi-ate" aria-label="Até"></span>' +
        '<label class="pi-chk" title="Mostra também os imóveis Disponíveis que não tiveram nenhum movimento no período: os parados"><input type="checkbox" id="pi-parados"> incluir imóveis parados</label>' +
        '<button type="button" class="pm-botao" id="pi-atualizar">Atualizar</button>' +
        '<small id="pi-periodo" class="pi-fraco"></small>' +
      "</div>" +
      '<p class="pm__aviso" id="pi-aviso" role="status" hidden></p>' +
      '<div class="pi-filtros" id="pi-filtros"></div>' +
      '<div class="pm-kpis pi-kpis" id="pi-kpis"></div>' +
      '<div class="pm-grade" style="margin-top:8px">' +
        '<article class="pm-painel pm-larga"><div class="pm-painel__topo"><h3>Venda × Locação <span class="pm-info" title="O negócio é o do imóvel pelo valor cadastrado: só valor de venda, só aluguel, ou os dois. Respeita todos os filtros abaixo, menos o de negócio.">i</span></h3></div><div id="pi-negocios"></div></article>' +
        '<article class="pm-painel pm-larga"><div class="pm-painel__topo"><h3>Os imóveis <small id="pi-contagem"></small></h3>' +
          '<div class="pi-acoes"><button type="button" class="pm-botao" id="pi-csv">Baixar CSV</button></div></div>' +
          '<div class="pi-tabela-caixa"><table class="pi-tabela" id="pi-tabela"></table></div>' +
          '<div class="pi-paginas" id="pi-paginas"></div>' +
        "</article>" +
      "</div>";
    raiz.querySelector('[data-grupo="pi-periodo"]').addEventListener("click", function (e) {
      var b = e.target.closest("button[data-v]"); if (!b) return;
      est.periodo = b.dataset.v;
      raiz.querySelector(".pi-datas").hidden = est.periodo !== "custom";
      if (est.periodo !== "custom") ler();
      marcarPeriodo();
    });
    var de = raiz.querySelector("#pi-de"), ate = raiz.querySelector("#pi-ate");
    de.max = ate.max = hoje(); de.min = ate.min = DESDE;
    function custom() { est.de = de.value; est.ate = ate.value; if (de.value && ate.value && de.value <= ate.value) ler(); }
    de.addEventListener("change", custom); ate.addEventListener("change", custom);
    raiz.querySelector("#pi-parados").addEventListener("change", function (e) { est.parados = e.target.checked; ler(); });
    raiz.querySelector("#pi-atualizar").addEventListener("click", ler);
    raiz.querySelector("#pi-csv").addEventListener("click", baixarCsv);
    raiz.querySelector("#pi-tabela").addEventListener("click", function (e) {
      var th = e.target.closest("th[data-k]"); if (!th) return;
      if (est.ordem === th.dataset.k) est.sentido = -est.sentido; else { est.ordem = th.dataset.k; est.sentido = th.dataset.k === "codigo" ? 1 : -1; }
      est.pagina = 0; desenharTabela();
    });
    raiz.querySelector("#pi-paginas").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-p]"); if (!b) return;
      est.pagina = Number(b.dataset.p); desenharTabela();
      raiz.querySelector("#pi-tabela").scrollIntoView({ block: "nearest" });
    });
    marcarPeriodo();
  }
  function marcarPeriodo() {
    raiz.querySelectorAll('[data-grupo="pi-periodo"] button').forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.v === est.periodo)); });
  }

  /* os filtros dependem dos dados (os bairros, os tipos...): são redesenhados a cada leitura */
  function desenharFiltros() {
    var f = est.f;
    var sel = function (id, rot, html) { return '<label class="pi-f"><span>' + rot + '</span><select data-f="' + id + '">' + html + "</select></label>"; };
    var tres = function (atual, a, b) { return '<option value="">Todos</option><option value="sim"' + (atual === "sim" ? " selected" : "") + ">" + a + '</option><option value="nao"' + (atual === "nao" ? " selected" : "") + ">" + b + "</option>"; };
    raiz.querySelector("#pi-filtros").innerHTML =
      sel("negocio", "Negócio", '<option value="">Venda e locação</option><option value="venda"' + (f.negocio === "venda" ? " selected" : "") + '>Só venda</option><option value="locacao"' + (f.negocio === "locacao" ? " selected" : "") + ">Só locação</option>") +
      sel("status", "Situação", opcoes(distintos("status"), f.status, "Todas")) +
      sel("tipo", "Tipo de imóvel", opcoes(distintos("tipo"), f.tipo, "Todos")) +
      sel("bairro", "Bairro", opcoes(distintos("bairro"), f.bairro, "Todos")) +
      '<label class="pi-f"><span>Condomínio</span><input type="search" data-f="condominio" placeholder="nome…" value="' + esc(f.condominio || "") + '"></label>' +
      sel("quartos", "Quartos", '<option value="">Todos</option>' + [1, 2, 3].map(function (q) { return '<option value="' + q + '"' + (f.quartos === String(q) ? " selected" : "") + ">" + q + "</option>"; }).join("") + '<option value="4"' + (f.quartos === "4" ? " selected" : "") + ">4 ou mais</option>") +
      sel("mobilia", "Mobília", opcoes(distintos("mobilia"), f.mobilia, "Todas")) +
      '<label class="pi-f pi-f--faixa"><span>Valor (R$)</span><span class="pi-faixa"><input type="number" min="0" step="500" data-f="min" placeholder="de" value="' + esc(f.min == null ? "" : f.min) + '"><input type="number" min="0" step="500" data-f="max" placeholder="até" value="' + esc(f.max == null ? "" : f.max) + '"></span></label>' +
      sel("origem", "Origem do cadastro", opcoes(distintos("origem"), f.origem, "Todas")) +
      sel("captador", "Captado por", opcoes(distintos("captado_por"), f.captador, "Todos")) +
      sel("parceiro", "De quem é", '<option value="">Nossos e de parceiros</option><option value="nosso"' + (f.parceiro === "nosso" ? " selected" : "") + '>Só nossos</option><option value="parceiro"' + (f.parceiro === "parceiro" ? " selected" : "") + ">Só de parceiros</option>") +
      sel("site", "No site", tres(f.site, "Está no site", "Fora do site")) +
      sel("cnm", "No Chaves na Mão", tres(f.cnm, "Está no feed", "Fora do feed")) +
      sel("olx", "Na OLX", tres(f.olx, "Publicado", "Não publicado")) +
      '<label class="pi-f pi-f--busca"><span>Buscar</span><input type="search" data-f="busca" placeholder="código, condomínio, bairro…" value="' + esc(f.busca || "") + '"></label>' +
      '<div class="pi-f pi-f--chk">' +
        '<label class="pi-chk"><input type="checkbox" data-f="soVisitas"' + (f.soVisitas ? " checked" : "") + "> só com visita</label>" +
        '<label class="pi-chk"><input type="checkbox" data-f="soCards"' + (f.soCards ? " checked" : "") + "> só com card enviado</label>" +
        '<label class="pi-chk" title="Imóveis que ninguém recebeu no período"><input type="checkbox" data-f="soSemCard"' + (f.soSemCard ? " checked" : "") + "> nenhum card enviado</label>" +
        '<button type="button" class="pm-botao" id="pi-limpar">Limpar filtros</button>' +
      "</div>";
    var caixa = raiz.querySelector("#pi-filtros");
    caixa.onchange = caixa.oninput = function (e) {
      var el = e.target.closest("[data-f]"); if (!el) return;
      var k = el.dataset.f;
      est.f[k] = el.type === "checkbox" ? el.checked : el.value;
      if (el.type === "search" && e.type === "change") return;     // o "input" já tratou
      est.pagina = 0; desenharResumo(); desenharTabela();
    };
    caixa.querySelector("#pi-limpar").onclick = function () { est.f = {}; est.pagina = 0; desenharFiltros(); desenharResumo(); desenharTabela(); };
  }

  /* ---------------- os números de cima e a comparação venda × locação ---------------- */
  function somar(lista) {
    var t = { imoveis: lista.length, visitas: 0, confirmadas: 0, agendadas: 0, realizadas: 0, fechou: 0, desistiu: 0, cards: 0, cardsP: 0, cardsL: 0, pessoas: 0, grupos: 0, leads: 0, comVisita: 0, comCard: 0 };
    lista.forEach(function (r) {
      t.visitas += visitas(r); t.confirmadas += num(r.visitas_confirmadas); t.agendadas += num(r.visitas_agendadas_para);
      t.realizadas += num(r.visitas_realizadas); t.fechou += num(r.visitas_fechou); t.desistiu += num(r.visitas_desistiu);
      t.cardsP += num(r.cards_parceria); t.cardsL += num(r.cards_leads); t.cards += cards(r);
      t.pessoas += num(r.pessoas_parceria) + num(r.pessoas_leads); t.grupos += num(r.posts_grupo); t.leads += leads(r);
      if (visitas(r)) t.comVisita++; if (cards(r)) t.comCard++;
    });
    return t;
  }
  function filtrados(semNegocio) {
    var guarda = est.f.negocio;
    if (semNegocio) delete est.f.negocio;
    var lista = est.dados.filter(passa);
    if (semNegocio && guarda) est.f.negocio = guarda;
    return lista;
  }
  function kpi(rot, valor, sub, cor, info) {
    return '<article class="pm-painel pm-kpi pi-kpi" style="--cor:' + cor + '"><div class="pm-kpi__rotulo"><span>' + esc(rot) +
      (info ? ' <span class="pm-info" title="' + esc(info) + '">i</span>' : "") + '</span></div><div class="pm-kpi__valor">' + valor + '</div><div class="pm-kpi__sub">' + esc(sub || "") + "</div></article>";
  }
  function desenharResumo() {
    var lista = filtrados(false), t = somar(lista);
    raiz.querySelector("#pi-kpis").innerHTML =
      kpi("Imóveis", n(t.imoveis), n(t.comVisita) + " com visita · " + n(t.comCard) + " com card", "#8ab8ff", "imóveis que passaram nos filtros") +
      kpi("Visitas pedidas", n(t.visitas), n(t.confirmadas) + " confirmadas", "#b877d9", "visitas marcadas no período (Parceria + Leads)") +
      kpi("Realizadas", n(t.realizadas), n(t.desistiu) + " desistiram", "#4fc4cf", "o que a equipe marcou na aba Visitas") +
      kpi("Fecharam", n(t.fechou), t.realizadas ? pct(t.fechou / t.realizadas) + " das realizadas" : "", "#73bf69", "visitas marcadas como Fechou negócio") +
      kpi("Cards enviados", n(t.cards), n(t.cardsP) + " Parceria · " + n(t.cardsL) + " Leads", "#ff9830", "vezes que o card de um imóvel saiu") +
      kpi("Visitas por 100 cards", t.cards ? (t.visitas / t.cards * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) : "—", "quanto o card rende em visita", "#fade2a", "visitas pedidas ÷ cards enviados × 100") +
      kpi("Posts em grupos", n(t.grupos), "", "#e07bc4", "vezes que o imóvel foi postado nos grupos de corretores (cada grupo conta um post)") +
      kpi("Leads", n(t.leads), "OLX e Chaves na Mão", "#f2495c", "clientes que chegaram perguntando por esses imóveis");
    // venda x locação
    var por = { venda: [], locacao: [], ambos: [], sem: [] };
    filtrados(true).forEach(function (r) { por[negocio(r)].push(r); });
    var linhas = [
      ["Imóveis com movimento", function (t) { return n(t.imoveis); }],
      ["Visitas pedidas", function (t) { return n(t.visitas); }],
      ["Visitas confirmadas", function (t) { return n(t.confirmadas); }],
      ["Visitas realizadas", function (t) { return n(t.realizadas); }],
      ["Fecharam negócio", function (t) { return n(t.fechou); }],
      ["Cards enviados", function (t) { return n(t.cards); }],
      ["Visitas por 100 cards", function (t) { return t.cards ? (t.visitas / t.cards * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) : "—"; }],
      ["Visitas por imóvel", function (t) { return t.imoveis ? (t.visitas / t.imoveis).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) : "—"; }],
      ["Leads", function (t) { return n(t.leads); }]
    ];
    var ts = { venda: somar(por.venda), locacao: somar(por.locacao), ambos: somar(por.ambos) };
    raiz.querySelector("#pi-negocios").innerHTML = '<div class="pi-tabela-caixa"><table class="pi-tabela pi-tabela--curta"><thead><tr><th></th><th>Venda</th><th>Locação</th><th>Os dois valores</th></tr></thead><tbody>' +
      linhas.map(function (l) { return "<tr><td>" + l[0] + "</td><td>" + l[1](ts.venda) + "</td><td>" + l[1](ts.locacao) + "</td><td>" + l[1](ts.ambos) + "</td></tr>"; }).join("") +
      "</tbody></table></div>";
  }

  /* ---------------- a tabela ---------------- */
  function ordenar(lista) {
    var k = est.ordem, s = est.sentido;
    var chave = k === "codigo" ? function (r) { return num(r.codigo); } : (colunaPorK(k) ? colunaPorK(k).f : visitas);
    return lista.slice().sort(function (a, b) {
      var d = chave(a) - chave(b);
      if (d) return d * s;
      // empate: o que tem mais visita, depois mais card, depois o código
      return (visitas(b) - visitas(a)) || (cards(b) - cards(a)) || (num(a.codigo) - num(b.codigo));
    });
  }
  function dataCurta(iso) { return iso ? new Date(iso).toLocaleDateString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit" }) : "—"; }
  function desenharTabela() {
    var lista = ordenar(filtrados(false));
    var total = lista.length, paginas = Math.max(1, Math.ceil(total / POR_PAGINA));
    if (est.pagina >= paginas) est.pagina = paginas - 1;
    var fatia = lista.slice(est.pagina * POR_PAGINA, (est.pagina + 1) * POR_PAGINA);
    raiz.querySelector("#pi-contagem").textContent = n(total) + " imóve" + (total === 1 ? "l" : "is");
    var seta = function (k) { return est.ordem === k ? (est.sentido < 0 ? " ▼" : " ▲") : ""; };
    var cab = '<thead><tr><th data-k="codigo" class="pi-th">Código' + seta("codigo") + '</th><th>Imóvel</th><th>Negócio</th>' +
      COLUNAS.map(function (c) { return '<th data-k="' + c.k + '" class="pi-th pi-num" title="' + esc(c.info) + '">' + esc(c.rot) + seta(c.k) + "</th>"; }).join("") +
      '<th title="último card enviado">Último card</th></tr></thead>';
    var corpo = fatia.map(function (r) {
      var neg = negocio(r);
      var valor = neg === "venda" ? reais(r.valor_venda) : neg === "locacao" ? reais(r.valor_aluguel) + "/mês" : neg === "ambos" ? reais(r.valor_venda) + " · " + reais(r.valor_aluguel) + "/mês" : "";
      var marcas = (r.parceiro ? '<em class="pi-tag">parceiro</em>' : "") + (r.status && r.status !== "Disponível" ? '<em class="pi-tag pi-tag--aviso">' + esc(r.status) + "</em>" : "") +
        (r.no_cnm ? '<em class="pi-tag pi-tag--ok" title="está no feed do Chaves na Mão">CNM</em>' : "") + (r.no_olx ? '<em class="pi-tag pi-tag--ok" title="publicado na OLX">OLX</em>' : "");
      var cel = function (v) { return '<td class="pi-num' + (v ? "" : " pi-zero") + '">' + (v ? n(v) : "·") + "</td>"; };
      return "<tr><td><b>#" + esc(r.codigo) + "</b></td><td class=\"pi-imovel\"><span>" + esc(r.condominio || r.tipo || "—") + "</span><small>" +
        esc([r.tipo, r.bairro, r.quartos ? r.quartos + " q" : ""].filter(Boolean).join(" · ")) + "</small>" + marcas + "</td><td>" +
        esc(ROT_NEGOCIO[neg]) + "<small>" + esc(valor) + "</small></td>" +
        COLUNAS.map(function (c) { return cel(c.f(r)); }).join("") + "<td>" + dataCurta(r.ultimo_card_em) + "</td></tr>";
    }).join("");
    raiz.querySelector("#pi-tabela").innerHTML = cab + "<tbody>" + (corpo || '<tr><td colspan="13" class="pi-vazio">Nenhum imóvel com esses filtros.</td></tr>') + "</tbody>";
    var pag = "";
    if (paginas > 1) {
      pag = '<button type="button" class="pm-botao" data-p="' + Math.max(0, est.pagina - 1) + '"' + (est.pagina ? "" : " disabled") + ">← Anterior</button>" +
        "<span>página " + (est.pagina + 1) + " de " + paginas + "</span>" +
        '<button type="button" class="pm-botao" data-p="' + Math.min(paginas - 1, est.pagina + 1) + '"' + (est.pagina < paginas - 1 ? "" : " disabled") + ">Próxima →</button>";
    }
    raiz.querySelector("#pi-paginas").innerHTML = pag;
  }

  function baixarCsv() {
    var lista = ordenar(filtrados(false));
    var cab = ["codigo", "condominio", "tipo", "bairro", "quartos", "negocio", "valor_venda", "valor_aluguel", "situacao", "parceiro", "origem", "captado_por", "no_site", "no_chaves_na_mao", "na_olx"]
      .concat(COLUNAS.map(function (c) { return c.rot; }), ["posts_grupo_detalhe_cards_parceria", "cards_leads", "ultimo_card"]);
    var linhas = lista.map(function (r) {
      return [r.codigo, r.condominio, r.tipo, r.bairro, r.quartos, negocio(r), r.valor_venda, r.valor_aluguel, r.status, r.parceiro ? "sim" : "nao", r.origem, r.captado_por,
        r.no_site ? "sim" : "nao", r.no_cnm ? "sim" : "nao", r.no_olx ? "sim" : "nao"]
        .concat(COLUNAS.map(function (c) { return c.f(r); }), [num(r.cards_parceria), num(r.cards_leads), r.ultimo_card_em || ""]);
    });
    var csv = [cab].concat(linhas).map(function (l) {
      return l.map(function (v) { v = v == null ? "" : String(v); return /[";\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }).join(";");
    }).join("\r\n");
    var a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" }));
    a.download = "metricas-por-imovel-" + intervalo().de + "-a-" + intervalo().ate + ".csv";
    document.body.appendChild(a); a.click(); a.remove();
  }

  /* ---------------- a leitura ---------------- */
  function ler() {
    if (est.lendo) return;
    var iv = intervalo();
    if (!iv.de || !iv.ate || iv.de > iv.ate) return;
    est.lendo = true;
    var aviso = raiz.querySelector("#pi-aviso");
    aviso.hidden = false; aviso.textContent = "Lendo os imóveis…";
    fetch("/admin/api/painel/imoveis?de=" + iv.de + "&ate=" + iv.ate + (est.parados ? "&parados=1" : ""), { credentials: "same-origin" })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.erro || "HTTP " + r.status); return j; }); })
      .then(function (j) {
        est.dados = j.imoveis || []; est.lido = true;
        aviso.hidden = true;
        raiz.querySelector("#pi-periodo").textContent = iv.de.split("-").reverse().join("/") + " a " + iv.ate.split("-").reverse().join("/") + " · " + n(est.dados.length) + " imóveis lidos";
        desenharFiltros(); desenharResumo(); desenharTabela();
      })
      .catch(function (err) { aviso.hidden = false; aviso.textContent = "Não consegui ler as métricas dos imóveis: " + err.message; })
      .then(function () { est.lendo = false; });
  }

  var montada = false;
  window.PainelImoveis = {
    abrir: function () {
      if (!montada) { montada = true; montar(); }
      if (!est.lido) ler();
    }
  };
})();
