/* ==========================================================================
   PAINEL DE MÉTRICAS DO INÍCIO (399, Pedro 16/10/2026)
   "um grande painel dashboard de métricas, focado em analisar o desempenho por dia, por semana, por mês ... no início
   uma métrica geral, pessoas que falamos x visitas, em um gráfico contínuo bonito por dia, filtrável e selecionável".

   Uma chamada: GET /admin/api/painel?de&ate&grao -> o que mora no naydb (site_painel_metricas) + "pessoas" por número
   (o CRM). Outra igual para o período anterior, do mesmo tamanho, que dá o ▲/▼ de cada número.
   Selecionar: arrastar no gráfico de cima escolhe o período; clicar numa semana/mês abre os dias dela; "Voltar" desfaz.
   ========================================================================== */
(function () {
  "use strict";

  var raiz = document.getElementById("painel-metricas");
  if (!raiz) return;

  var COR = {
    verde: "#73bf69", azul: "#5794f2", roxo: "#b877d9", laranja: "#ff9830", amarelo: "#fade2a",
    vermelho: "#f2495c", ciano: "#8ab8ff", rosa: "#e07bc4", teal: "#4fc4cf", cinza: "#9aa0ac"
  };
  var LINHAS = {
    parceria: { rotulo: "Parceria", numero: "92 9445-3618", cor: COR.roxo, papel: "corretores" },
    captacao: { rotulo: "Captação", numero: "92 8595-6408", cor: COR.verde, papel: "clientes da OLX, orgânicos e donos" },
    oficial:  { rotulo: "Oficial (Meta)", numero: "92 8456-0874", cor: COR.azul, papel: "disparos para proprietários" }
  };
  // o que é conversão em cada número (Pedro: "para o número de parceria e captação é visitas agendadas, para o
  // captação imóveis novos ... caso tenha várias conversões no mesmo número")
  var CONVERSOES = {
    todas:    [{ rot: "Visitas (Parceria)", s: ["visitas"], cor: COR.roxo }, { rot: "Visitas (OLX)", s: ["visitas_olx"], cor: COR.laranja }],
    parceria: [{ rot: "Visitas agendadas", s: ["visitas"], cor: COR.roxo }],
    captacao: [{ rot: "Visitas OLX", s: ["visitas_olx"], cor: COR.laranja }, { rot: "Imóveis novos", s: ["imoveis_novos"], cor: COR.verde }],
    oficial:  [{ rot: "Status atualizados", s: ["status_oficial"], cor: COR.amarelo }]
  };
  // o que mais aparece no card do número, sem ser conversão
  var EXTRAS = { oficial: [{ rot: "responderam o disparo", s: ["responderam_oficial"] }] };
  var MEDIDAS = { conversaram: "Conversaram", escreveram: "Escreveram", novas: "Novas", alcancados: "Alcançados" };

  var est = { periodo: "30d", de: null, ate: null, grao: "dia", linha: "todas", medida: "conversaram", pilha: [], areas: null };
  try {
    var guardado = JSON.parse(localStorage.getItem("painelMetricas") || "{}");
    ["periodo", "grao", "linha", "medida"].forEach(function (k) { if (guardado[k]) est[k] = guardado[k]; });
    if (est.periodo === "custom") est.periodo = "30d";
  } catch (e) { /* sem armazenamento: fica o padrão */ }
  function guardar() {
    try { localStorage.setItem("painelMetricas", JSON.stringify({ periodo: est.periodo, grao: est.grao, linha: est.linha, medida: est.medida })); } catch (e) { /* tanto faz */ }
  }

  var dados = null, anterior = null, graficos = {}, carregando = false;
  var $ = function (sel) { return raiz.querySelector(sel); };

  if (!window.Chart) {
    $(".pm__aviso").hidden = false;
    $(".pm__aviso").textContent = "Não consegui carregar a biblioteca dos gráficos (Chart.js). Recarregue a página.";
    return;
  }
  Chart.defaults.color = "#8e8ea0";
  Chart.defaults.borderColor = "rgba(204,204,220,0.07)";
  Chart.defaults.font.family = "Rubik, Barlow, system-ui, sans-serif";
  Chart.defaults.font.size = 11;

  /* ---------------- datas ---------------- */
  function hoje() { return new Date().toLocaleDateString("en-CA", { timeZone: "America/Manaus" }); }
  function somaDias(iso, n) { var d = new Date(iso + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
  function diasEntre(a, b) { return Math.round((new Date(b + "T12:00:00Z") - new Date(a + "T12:00:00Z")) / 864e5); }
  function fimDoMes(iso) { var d = new Date(iso.slice(0, 8) + "01T12:00:00Z"); d.setUTCMonth(d.getUTCMonth() + 1); d.setUTCDate(0); return d.toISOString().slice(0, 10); }
  function menor(a, b) { return a < b ? a : b; }
  function intervalo() {
    var h = hoje();
    switch (est.periodo) {
      case "hoje": return { de: h, ate: h };
      case "7d": return { de: somaDias(h, -6), ate: h };
      case "90d": return { de: somaDias(h, -89), ate: h };
      case "mes": return { de: h.slice(0, 8) + "01", ate: h };
      case "mes_passado": var f = somaDias(h.slice(0, 8) + "01", -1); return { de: f.slice(0, 8) + "01", ate: f };
      case "custom": return { de: est.de, ate: est.ate };
      default: return { de: somaDias(h, -29), ate: h };
    }
  }
  var SEMANA = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
  var MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
  var MESES_LONGOS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
  function dm(iso) { return iso.slice(8, 10) + "/" + iso.slice(5, 7); }
  function rotulo(iso) {
    if (!dados) return iso;
    if (dados.grao === "mes") return MESES[+iso.slice(5, 7) - 1] + "/" + iso.slice(2, 4);
    return dm(iso);
  }
  function rotuloLongo(iso) {
    if (!dados) return iso;
    if (dados.grao === "mes") return MESES_LONGOS[+iso.slice(5, 7) - 1] + " de " + iso.slice(0, 4);
    if (dados.grao === "semana") return "semana de " + dm(iso) + " a " + dm(menor(somaDias(iso, 6), dados.ate));
    return SEMANA[new Date(iso + "T12:00:00Z").getUTCDay()] + ", " + dm(iso) + "/" + iso.slice(0, 4);
  }
  function fimDoPeriodo(iso) {
    if (dados.grao === "semana") return menor(somaDias(iso, 6), hoje());
    if (dados.grao === "mes") return menor(fimDoMes(iso), hoje());
    return iso;
  }

  /* ---------------- números ---------------- */
  function n(v) { return v == null || isNaN(v) ? "—" : Number(v).toLocaleString("pt-BR"); }
  function n1(v) { return v == null || isNaN(v) || !isFinite(v) ? "—" : Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 1 }); }
  function pct(v) { return v == null || isNaN(v) || !isFinite(v) ? "—" : (v * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + "%"; }
  function reais(v) { return v ? "R$ " + Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 0 }) : ""; }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function alfa(hex, a) {
    var h = hex.replace("#", ""); var r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16);
    return "rgba(" + r + "," + g + "," + b + "," + a + ")";
  }
  function zeros(d) { return (d.periodos || []).map(function () { return 0; }); }
  function S(d, nome) { return (d.serie && d.serie[nome]) || zeros(d); }
  function T(d, nome) { return (d.totais && d.totais[nome]) || 0; }
  function soma(d, nomes) {
    var out = zeros(d);
    nomes.forEach(function (nm) { S(d, nm).forEach(function (v, i) { out[i] += v; }); });
    return out;
  }
  function somaT(d, nomes) { return nomes.reduce(function (a, nm) { return a + T(d, nm); }, 0); }
  function razao(a, b) { return a.map(function (v, i) { return b[i] ? v / b[i] : null; }); }
  function temPessoas(d) { return d && d.pessoas && !d.pessoas.erro && d.pessoas.serie; }
  function pessoasSerie(d, linha, medida) {
    if (!temPessoas(d)) return null;
    var idx = {}, out = zeros(d);
    d.periodos.forEach(function (p, i) { idx[p] = i; });
    d.pessoas.serie.forEach(function (r) { if (r.linha === linha && idx[r.p] !== undefined) out[idx[r.p]] = r[medida]; });
    return out;
  }
  function pessoasTotal(d, linha, medida) {
    if (!temPessoas(d)) return null;
    var t = d.pessoas.totais.filter(function (r) { return r.linha === linha; })[0];
    return t ? t[medida] : 0;
  }
  function convSerie(d, linha) { return soma(d, [].concat.apply([], CONVERSOES[linha].map(function (c) { return c.s; }))); }
  function convTotal(d, linha) { return somaT(d, [].concat.apply([], CONVERSOES[linha].map(function (c) { return c.s; }))); }
  function delta(atual, antes) {
    if (atual == null || antes == null) return "";
    if (antes === 0 && atual === 0) return '<span class="pm-delta pm-delta--igual">=</span>';
    if (antes === 0) return '<span class="pm-delta pm-delta--sobe" title="o período anterior teve 0">▲ novo</span>';
    var v = (atual - antes) / antes;
    if (v >= 1) return '<span class="pm-delta pm-delta--sobe" title="vs o período anterior (' + n1(antes) + ')">▲ ' +
      (atual / antes).toLocaleString("pt-BR", { maximumFractionDigits: atual / antes >= 10 ? 0 : 1 }) + "×</span>";
    if (Math.abs(v) < 0.005) return '<span class="pm-delta pm-delta--igual" title="igual ao período anterior">=</span>';
    return '<span class="pm-delta pm-delta--' + (v > 0 ? "sobe" : "desce") + '" title="vs o período anterior (' + n1(antes) + ')">' +
      (v > 0 ? "▲ " : "▼ ") + Math.abs(v * 100).toLocaleString("pt-BR", { maximumFractionDigits: 0 }) + "%</span>";
  }

  /* ---------------- gráficos ---------------- */
  function desenhar(id, conf) {
    var canvas = document.getElementById(id);
    if (!canvas) return null;
    if (graficos[id]) graficos[id].destroy();
    graficos[id] = new Chart(canvas, conf);
    return graficos[id];
  }
  function barra(rot, data, cor, extra) {
    return Object.assign({ type: "bar", label: rot, data: data, backgroundColor: alfa(cor, 0.82), hoverBackgroundColor: cor,
      borderWidth: 0, borderRadius: 2, stack: "barras", yAxisID: "y", order: 3, maxBarThickness: 38 }, extra || {});
  }
  function linha(rot, data, cor, extra) {
    var poucos = data.length <= 45;
    return Object.assign({ type: "line", label: rot, data: data, borderColor: cor, backgroundColor: alfa(cor, 0.14),
      borderWidth: 2, pointRadius: poucos ? 2 : 0, pointHoverRadius: 4, pointBackgroundColor: cor, tension: 0.32,
      yAxisID: "y", order: 1, fill: false, stack: "l-" + rot, spanGaps: true }, extra || {});
  }
  function opcoes(extra) {
    var base = {
      responsive: true, maintainAspectRatio: false, animation: { duration: 350 },
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { position: "bottom", labels: { boxWidth: 10, boxHeight: 10, padding: 12, color: "#ccccdc" } },
        tooltip: {
          backgroundColor: "#22252b", borderColor: "rgba(204,204,220,.2)", borderWidth: 1, titleColor: "#e4e5ea",
          bodyColor: "#ccccdc", padding: 9, boxPadding: 4,
          callbacks: {
            title: function (it) { return it.length ? rotuloLongo(dados.periodos[it[0].dataIndex]) : ""; },
            label: function (c) {
              var v = c.raw;
              if (c.dataset.formato === "pct") return " " + c.dataset.label + ": " + pct(v);
              if (c.dataset.formato === "1") return " " + c.dataset.label + ": " + n1(v);
              return " " + c.dataset.label + ": " + n(v);
            }
          }
        }
      },
      scales: {
        x: { stacked: true, grid: { display: false }, ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 12 } },
        y: { stacked: true, beginAtZero: true, ticks: { precision: 0 }, grid: { color: "rgba(204,204,220,0.07)" } }
      }
    };
    return mesclar(base, extra || {});
  }
  function mesclar(a, b) {
    Object.keys(b).forEach(function (k) {
      if (b[k] && typeof b[k] === "object" && !Array.isArray(b[k]) && a[k] && typeof a[k] === "object") mesclar(a[k], b[k]);
      else a[k] = b[k];
    });
    return a;
  }
  function eixoDireito(extra) {
    return Object.assign({ position: "right", beginAtZero: true, stacked: false, grid: { display: false }, ticks: { precision: 0 } }, extra || {});
  }
  function labels() { return dados.periodos.map(rotulo); }

  /* ---------------- o gráfico de cima: pessoas x visitas ---------------- */
  var heroDatasets = [];
  function renderHero() {
    var d = dados, l = est.linha;
    var conv = CONVERSOES[l];
    var titulo = (l === "todas" || l === "parceria") ? "Pessoas que falamos × Visitas" : "Pessoas que falamos × Conversões";
    $("#pm-hero-titulo").textContent = titulo + (l === "todas" ? "" : " · " + LINHAS[l].rotulo);
    var pes = pessoasSerie(d, l, "conversaram"), esc_ = pessoasSerie(d, l, "escreveram"), nov = pessoasSerie(d, l, "novas");
    var convS = convSerie(d, l);
    var ds = [];
    conv.forEach(function (c) { ds.push(barra(c.rot, soma(d, c.s), c.cor, { yAxisID: "y1", stack: "conv" })); });
    if (pes) {
      ds.push(linha("Pessoas que falamos", pes, COR.azul, { fill: "origin", borderWidth: 2.5, order: 0,
        backgroundColor: function (ctx) {
          var a = ctx.chart.chartArea; if (!a) return alfa(COR.azul, 0.15);
          var g = ctx.chart.ctx.createLinearGradient(0, a.top, 0, a.bottom);
          g.addColorStop(0, alfa(COR.azul, 0.35)); g.addColorStop(1, alfa(COR.azul, 0.02)); return g;
        } }));
      ds.push(linha("Escreveram para nós", esc_, COR.ciano, { borderDash: [5, 4], borderWidth: 1.5, hidden: true }));
      ds.push(linha("Pessoas novas", nov, COR.amarelo, { borderWidth: 1.5, hidden: true }));
      ds.push(linha("Taxa de conversão", razao(convS, pes), COR.verde, { yAxisID: "y2", formato: "pct", borderWidth: 1.5, hidden: true, stack: "taxa" }));
    }
    heroDatasets = ds;
    var g = desenhar("pm-hero", {
      data: { labels: labels(), datasets: ds },
      options: opcoes({
        plugins: { legend: { display: false } },
        scales: {
          y: { stacked: false, title: { display: true, text: "pessoas", color: "#8e8ea0" } },
          y1: eixoDireito({ stacked: true, title: { display: true, text: l === "todas" || l === "parceria" ? "visitas" : "conversões", color: "#8e8ea0" } }),
          y2: { display: false, beginAtZero: true, stacked: false }
        }
      })
    });
    // as fichas da legenda: clicar liga e desliga a série
    var chips = $("#pm-hero-chips");
    chips.innerHTML = ds.map(function (x, i) {
      var cor = typeof x.borderColor === "string" ? x.borderColor : COR.azul;
      if (x.type === "bar") cor = x.hoverBackgroundColor;
      return '<button type="button" class="pm-chip" data-i="' + i + '" aria-pressed="' + (!x.hidden) + '" style="--cor:' + cor + '"><i></i>' + esc(x.label) + "</button>";
    }).join("");
    chips.querySelectorAll(".pm-chip").forEach(function (b) {
      b.addEventListener("click", function () {
        var i = +b.dataset.i, vis = g.isDatasetVisible(i);
        g.setDatasetVisibility(i, !vis); g.update(); b.setAttribute("aria-pressed", String(!vis));
      });
    });
    $("#pm-hero-vazio").hidden = !!pes;
    $("#pm-hero-vazio").textContent = pes ? "" : "Sem as pessoas do CRM agora: só as visitas aparecem.";

    // os números de cima
    var pT = pessoasTotal(d, l, "conversaram"), pA = anterior ? pessoasTotal(anterior, l, "conversaram") : null;
    var cT = convTotal(d, l), cA = anterior ? convTotal(anterior, l) : null;
    var nT = pessoasTotal(d, l, "novas"), nA = anterior ? pessoasTotal(anterior, l, "novas") : null;
    var taxa = pT ? cT / pT : null, taxaA = (anterior && pA) ? cA / pA : null;
    $("#pm-hero-numeros").innerHTML =
      num("Pessoas que falamos", n(pT), delta(pT, pA)) +
      num(l === "todas" || l === "parceria" ? "Visitas agendadas" : "Conversões", n(cT), delta(cT, cA)) +
      num("Pessoas → " + (l === "todas" || l === "parceria" ? "visita" : "conversão"), pct(taxa), delta(taxa, taxaA)) +
      num("Pessoas novas", n(nT), delta(nT, nA));
    function num(r, v, dl) { return '<div class="pm-hero__num"><span>' + r + "</span><strong>" + v + "</strong>" + (dl ? "<em>" + dl + "</em>" : "") + "</div>"; }
  }

  // SELECIONAR NO GRÁFICO: arrastar escolhe o período; clicar numa semana ou mês abre os dias
  (function ligarSelecao() {
    var caixa = $("#pm-hero-caixa"), sel = $("#pm-hero-caixa .pm-selecao"), canvas = document.getElementById("pm-hero");
    var x0 = null, x1 = null;
    function px(e) { var r = canvas.getBoundingClientRect(); return Math.max(0, Math.min(r.width, e.clientX - r.left)); }
    function indice(x) {
      var g = graficos["pm-hero"]; if (!g || !dados) return null;
      var v = g.scales.x.getValueForPixel(x);
      return Math.max(0, Math.min(dados.periodos.length - 1, Math.round(v)));
    }
    canvas.addEventListener("mousedown", function (e) { if (e.button !== 0 || !dados) return; x0 = x1 = px(e); });
    window.addEventListener("mousemove", function (e) {
      if (x0 === null) return;
      x1 = px(e);
      if (Math.abs(x1 - x0) < 4) { sel.style.display = "none"; return; }
      sel.style.display = "block"; sel.style.left = Math.min(x0, x1) + "px"; sel.style.width = Math.abs(x1 - x0) + "px";
    });
    window.addEventListener("mouseup", function () {
      if (x0 === null) return;
      var a = x0, b = x1; x0 = null; sel.style.display = "none";
      var i0 = indice(Math.min(a, b)), i1 = indice(Math.max(a, b));
      if (i0 === null) return;
      if (Math.abs(b - a) < 4) {             // um clique: abre os dias daquela semana/mês
        if (dados.grao === "dia") return;
        escolher(dados.periodos[i0], fimDoPeriodo(dados.periodos[i0]), "dia");
        return;
      }
      if (i0 === i1 && dados.grao === "dia") return;
      var de = dados.periodos[i0], ate = fimDoPeriodo(dados.periodos[i1]);
      escolher(de, ate, (i0 === i1) ? "dia" : est.grao);
    });
    caixa.addEventListener("mouseleave", function () { if (x0 !== null) sel.style.display = "none"; });
  })();
  function escolher(de, ate, grao) {
    est.pilha.push({ periodo: est.periodo, de: est.de, ate: est.ate, grao: est.grao });
    est.periodo = "custom"; est.de = de; est.ate = ate; est.grao = grao;
    sincronizarControles(); carregar();
  }

  /* ---------------- os números grandes ---------------- */
  function kpis() {
    var l = est.linha;
    return [
      { rot: "Pessoas que falamos", cor: COR.azul, info: "pessoas distintas com conversa (escreveram ou receberam mensagem que não é modelo) " + (l === "todas" ? "nos três números" : "no número " + LINHAS[l].rotulo),
        v: function (d) { return pessoasTotal(d, l, "conversaram"); },
        sub: function (d) { return temPessoas(d) ? n(pessoasTotal(d, l, "escreveram")) + " escreveram · " + n(pessoasTotal(d, l, "novas")) + " novas" : "sem o CRM agora"; },
        s: function (d) { return pessoasSerie(d, l, "conversaram") || zeros(d); } },
      { rot: "Visitas agendadas", cor: COR.roxo, info: "visitas marcadas no período: Parceria (pela Nay e pelo CRM) + clientes da OLX",
        v: function (d) { return somaT(d, ["visitas", "visitas_olx"]); },
        sub: function (d) { return n(T(d, "visitas_nay")) + " Nay · " + n(T(d, "visitas_crm")) + " CRM · " + n(T(d, "visitas_olx")) + " OLX"; },
        s: function (d) { return soma(d, ["visitas", "visitas_olx"]); } },
      { rot: "Pessoas → visita", cor: COR.verde, fmt: "pct", info: "visitas agendadas ÷ pessoas que falamos (todos os números)",
        v: function (d) { var p = pessoasTotal(d, "todas", "conversaram"); return p ? somaT(d, ["visitas", "visitas_olx"]) / p : null; },
        sub: function (d) { return n(T(d, "visitas_confirmadas") + T(d, "visitas_olx_confirmadas")) + " confirmadas"; },
        s: function (d) { var p = pessoasSerie(d, "todas", "conversaram"); return p ? razao(soma(d, ["visitas", "visitas_olx"]), p) : zeros(d); } },
      { rot: "Imóveis enviados", cor: COR.laranja, info: "pares pessoa × imóvel que saíram (card ou foto): Nay, equipe pela caixa da Nay e Nay do WhatsApp (captação)",
        v: function (d) { return somaT(d, ["enviados", "enviados_captacao"]); },
        sub: function (d) { return n(T(d, "enviados_nay")) + " Nay · " + n(T(d, "enviados_equipe")) + " equipe · " + n(T(d, "enviados_captacao")) + " captação"; },
        s: function (d) { return soma(d, ["enviados", "enviados_captacao"]); } },
      { rot: "Média por corretor", cor: COR.amarelo, fmt: "1", info: "imóveis enviados ÷ pessoas que receberam (Parceria)",
        v: function (d) { return T(d, "destinatarios") ? T(d, "enviados") / T(d, "destinatarios") : null; },
        sub: function (d) { return n(T(d, "destinatarios")) + " receberam imóvel"; },
        s: function (d) { return razao(S(d, "enviados"), S(d, "destinatarios")); } },
      { rot: "Imóveis novos", cor: COR.teal, info: "imóveis que entraram no cadastro (a carga da planilha antiga de 26/09 não conta)",
        v: function (d) { return T(d, "imoveis_novos"); },
        sub: function (d) { return n(T(d, "imoveis_novos_olx")) + " OLX · " + n(T(d, "imoveis_novos_crm")) + " CRM · " + n(T(d, "imoveis_novos_site") + T(d, "imoveis_novos_outros")) + " site"; },
        s: function (d) { return S(d, "imoveis_novos"); } },
      { rot: "Negócios fechados", cor: COR.verde, info: "fechamentos concluídos na aba Fechamento",
        v: function (d) { return T(d, "fech_concluidos"); },
        sub: function (d) { return n(T(d, "fech_iniciados")) + " abertos no período"; },
        s: function (d) { return S(d, "fech_concluidos"); } },
      { rot: "Clientes da OLX", cor: COR.laranja, info: "contatos que a OLX mandou (webhook) no período",
        v: function (d) { return T(d, "olx_leads"); },
        sub: function (d) { return n(T(d, "olx_whatsapp")) + " no WhatsApp · " + n(T(d, "visitas_olx")) + " visitas"; },
        s: function (d) { return S(d, "olx_leads"); } },
      { rot: "Disparos", cor: COR.azul, info: "mensagens de captação que saíram para proprietários (oficial e Z-API)",
        v: function (d) { return T(d, "disparos"); },
        sub: function (d) { return n(T(d, "responderam")) + " responderam"; },
        s: function (d) { return S(d, "disparos"); } },
      { rot: "Status atualizados", cor: COR.amarelo, info: "o dono respondeu e o cadastro mudou (ou foi confirmado como está), pelos dois números da captação",
        v: function (d) { return somaT(d, ["status_mudou", "status_confirmado"]); },
        sub: function (d) { return n(T(d, "status_mudou")) + " mudaram · " + n(T(d, "status_confirmado")) + " confirmaram"; },
        s: function (d) { return soma(d, ["status_mudou", "status_confirmado"]); } },
      { rot: "Pedidos nos grupos", cor: COR.ciano, info: "pedidos de imóvel dos corretores nos grupos (o mesmo pedido em vários grupos conta uma vez)",
        v: function (d) { return T(d, "pedidos_grupo"); },
        sub: function (d) { return n(T(d, "pedidos_grupo_atendidos")) + " atendidos"; },
        s: function (d) { return S(d, "pedidos_grupo"); } },
      { rot: "Perguntas ao Tel", cor: COR.rosa, info: "a fila de perguntas no PV do Tel (a limpeza de 16/10 não conta)",
        v: function (d) { return T(d, "perguntas"); },
        sub: function (d) { return n(T(d, "perguntas_respondidas")) + " respondidas"; },
        s: function (d) { return S(d, "perguntas"); } }
    ];
  }
  function renderKpis() {
    var lista = kpis();
    $("#pm-kpis").innerHTML = lista.map(function (k, i) {
      var v = k.v(dados), a = anterior ? k.v(anterior) : null;
      var txt = k.fmt === "pct" ? pct(v) : k.fmt === "1" ? n1(v) : n(v);
      return '<article class="pm-painel pm-kpi" style="--cor:' + k.cor + '">' +
        '<div class="pm-kpi__rotulo"><span>' + esc(k.rot) + ' <span class="pm-info" title="' + esc(k.info) + '">i</span></span>' + delta(v, a) + "</div>" +
        '<div class="pm-kpi__valor">' + txt + "</div>" +
        '<div class="pm-kpi__sub">' + esc(k.sub(dados)) + "</div>" +
        '<div class="pm-kpi__spark"><canvas id="pm-spark-' + i + '"></canvas></div></article>';
    }).join("");
    lista.forEach(function (k, i) {
      desenhar("pm-spark-" + i, {
        type: "line",
        data: { labels: labels(), datasets: [{ data: k.s(dados), borderColor: k.cor, borderWidth: 1.5, pointRadius: 0, tension: 0.35, fill: "origin",
          backgroundColor: alfa(k.cor, 0.16), spanGaps: true }] },
        options: { responsive: true, maintainAspectRatio: false, animation: false, events: [],
          plugins: { legend: { display: false }, tooltip: { enabled: false } },
          scales: { x: { display: false }, y: { display: false, beginAtZero: true } }, layout: { padding: 0 } }
      });
    });
  }

  /* ---------------- por número ---------------- */
  function renderLinhas() {
    var d = dados;
    $("#pm-linhas").innerHTML = Object.keys(LINHAS).map(function (k) {
      var L = LINHAS[k], p = pessoasTotal(d, k, "conversaram"), c = convTotal(d, k);
      var pa = anterior ? pessoasTotal(anterior, k, "conversaram") : null, ca = anterior ? convTotal(anterior, k) : null;
      var quebra = CONVERSOES[k].map(function (cv) {
        return '<span><b>' + n(somaT(d, cv.s)) + "</b> " + esc(cv.rot.toLowerCase()) + "</span>";
      }).join("<span>·</span>") + (EXTRAS[k] || []).map(function (ex) {
        return "<span>·</span><span><b>" + n(somaT(d, ex.s)) + "</b> " + esc(ex.rot) + "</span>";
      }).join("");
      return '<article class="pm-painel pm-linha" style="--cor:' + L.cor + '">' +
        '<div class="pm-linha__cab"><h3>' + esc(L.rotulo) + "</h3><span>" + esc(L.numero) + " · " + esc(L.papel) + "</span></div>" +
        '<div class="pm-linha__nums">' +
          '<div><span>Pessoas</span><strong>' + n(p) + "</strong> " + delta(p, pa) + "</div>" +
          '<div><span>Escreveram</span><strong>' + n(pessoasTotal(d, k, "escreveram")) + "</strong></div>" +
          '<div><span>Novas</span><strong>' + n(pessoasTotal(d, k, "novas")) + "</strong></div>" +
          '<div><span>Conversões</span><strong>' + n(c) + "</strong> " + delta(c, ca) + "</div>" +
        "</div>" +
        '<div class="pm-linha__conv">' + quebra + "<span>·</span><span>taxa <b>" + pct(p ? c / p : null) + "</b></span>" +
          (k === "oficial" ? ' <span class="pm-info" title="status e respostas dos donos que hoje estão no número oficial">i</span>' : "") + "</div>" +
        '<div class="pm-grafico"><canvas id="pm-linha-' + k + '"></canvas></div></article>';
    }).join("");
    Object.keys(LINHAS).forEach(function (k) {
      var ds = CONVERSOES[k].map(function (cv) { return barra(cv.rot, soma(d, cv.s), cv.cor, { yAxisID: "y1", stack: "conv" }); });
      var pes = pessoasSerie(d, k, "conversaram");
      if (pes) ds.push(linha("Pessoas", pes, LINHAS[k].cor, { fill: "origin", backgroundColor: alfa(LINHAS[k].cor, 0.12), order: 0 }));
      desenhar("pm-linha-" + k, { data: { labels: labels(), datasets: ds }, options: opcoes({
        plugins: { legend: { display: false } },
        scales: { y: { stacked: false }, y1: eixoDireito({ stacked: true }), x: { ticks: { maxTicksLimit: 6 } } } }) });
    });
  }

  /* ---------------- a grade dos gráficos ---------------- */
  function renderGrade() {
    var d = dados;
    // pessoas por número, com a medida escolhida
    var med = est.medida;
    var dsP = Object.keys(LINHAS).map(function (k) { return linha(LINHAS[k].rotulo, pessoasSerie(d, k, med) || zeros(d), LINHAS[k].cor); });
    dsP.push(linha("Todas (sem repetir)", pessoasSerie(d, "todas", med) || zeros(d), "#d8d9da", { borderDash: [4, 4], borderWidth: 1.5 }));
    desenhar("pm-g-pessoas", { data: { labels: labels(), datasets: dsP }, options: opcoes({ scales: { y: { stacked: false } } }) });
    $("#pm-g-pessoas-vazio").hidden = temPessoas(d);

    desenhar("pm-g-visitas", { data: { labels: labels(), datasets: [
      barra("Pela Nay", S(d, "visitas_nay"), COR.roxo),
      barra("Pelo CRM", S(d, "visitas_crm"), COR.azul),
      barra("Clientes da OLX", S(d, "visitas_olx"), COR.laranja),
      linha("Confirmadas", soma(d, ["visitas_confirmadas", "visitas_olx_confirmadas"]), COR.verde),
      linha("Marcadas para o dia", S(d, "visitas_marcadas_para"), COR.amarelo, { borderDash: [4, 4], hidden: true })
    ] }, options: opcoes() });

    desenhar("pm-g-enviados", { data: { labels: labels(), datasets: [
      barra("Pela Nay", S(d, "enviados_nay"), COR.verde),
      barra("Pela equipe", S(d, "enviados_equipe"), COR.azul),
      barra("Nay do WhatsApp (captação)", S(d, "enviados_captacao"), COR.laranja),
      linha("Média por corretor", razao(S(d, "enviados"), S(d, "destinatarios")), COR.amarelo, { yAxisID: "y1", formato: "1", stack: "media" }),
      linha("Pessoas que receberam", S(d, "destinatarios"), COR.ciano, { borderDash: [4, 4], hidden: true })
    ] }, options: opcoes({ scales: { y1: eixoDireito({ ticks: { precision: 1 }, title: { display: true, text: "média", color: "#8e8ea0" } }) } }) });

    desenhar("pm-g-grupos", { data: { labels: labels(), datasets: [
      barra("Posts de imóvel nos grupos", S(d, "grupo_posts"), COR.ciano),
      linha("Imóveis divulgados", S(d, "grupo_imoveis"), COR.roxo, { yAxisID: "y1", stack: "gi" }),
      linha("Pedidos dos corretores", S(d, "pedidos_grupo"), COR.laranja, { yAxisID: "y1", stack: "gp" }),
      linha("Pedidos atendidos", S(d, "pedidos_grupo_atendidos"), COR.verde, { yAxisID: "y1", stack: "ga" })
    ] }, options: opcoes({ scales: { y1: eixoDireito() } }) });

    desenhar("pm-g-novos", { data: { labels: labels(), datasets: [
      barra("OLX", S(d, "imoveis_novos_olx"), COR.laranja),
      barra("CRM", S(d, "imoveis_novos_crm"), COR.azul),
      barra("Site", S(d, "imoveis_novos_site"), COR.rosa),
      barra("Outros", S(d, "imoveis_novos_outros"), COR.cinza)
    ] }, options: opcoes() });

    desenhar("pm-g-olx", { data: { labels: labels(), datasets: [
      barra("Anúncios publicados", S(d, "olx_anuncios"), COR.amarelo, { yAxisID: "y1", stack: "an", backgroundColor: alfa(COR.amarelo, 0.35) }),
      linha("Contatos da OLX", S(d, "olx_leads"), COR.laranja),
      linha("Chegaram ao WhatsApp", S(d, "olx_whatsapp"), COR.verde),
      linha("Orgânicos (8595)", S(d, "organicos"), COR.azul),
      linha("Visitas OLX", S(d, "visitas_olx"), COR.roxo),
      linha("Chats com proprietários", S(d, "olx_chats_donos"), COR.cinza, { borderDash: [4, 4], hidden: true })
    ] }, options: opcoes({ scales: { y: { stacked: false }, y1: eixoDireito({ title: { display: true, text: "anúncios", color: "#8e8ea0" } }) } }) });

    desenhar("pm-g-disparos", { data: { labels: labels(), datasets: [
      barra("Oficial (Meta)", S(d, "disparos_oficial"), COR.azul),
      barra("Z-API", S(d, "disparos_zapi"), COR.verde),
      linha("Responderam", S(d, "responderam"), COR.laranja, { yAxisID: "y1", stack: "r" }),
      linha("Status atualizados", soma(d, ["status_mudou", "status_confirmado"]), COR.amarelo, { yAxisID: "y1", stack: "s" })
    ] }, options: opcoes({ scales: { y1: eixoDireito({ title: { display: true, text: "respostas", color: "#8e8ea0" } }) } }) });

    desenhar("pm-g-perguntas", { data: { labels: labels(), datasets: [
      barra("Perguntas na fila", S(d, "perguntas"), COR.rosa, { stack: "p" }),
      barra("Respondidas pelo Tel", S(d, "perguntas_respondidas"), COR.verde, { stack: "r" })
    ] }, options: opcoes({ scales: { x: { stacked: false }, y: { stacked: false } } }) });

    desenhar("pm-g-fech", { data: { labels: labels(), datasets: [
      barra("Abertos", S(d, "fech_iniciados"), COR.azul, { stack: "a" }),
      barra("Concluídos", S(d, "fech_concluidos"), COR.verde, { stack: "c" })
    ] }, options: opcoes({ scales: { x: { stacked: false }, y: { stacked: false } } }) });
  }

  /* ---------------- funil, coortes, tabelas ---------------- */
  function renderFunil() {
    var f = dados.funil_olx || {};
    var passos = [
      ["Contatos da OLX", f.leads_olx, COR.laranja],
      ["Chegaram ao WhatsApp", f.no_whatsapp, COR.amarelo],
      ["Receberam imóvel", f.receberam_imovel, COR.verde],
      ["Pediram visita", f.pediram_visita, COR.teal],
      ["Visita confirmada", f.visita_confirmada, COR.azul],
      ["Visitaram", f.visitaram, COR.roxo]
    ];
    var base = Math.max(1, f.leads_olx || 0, f.no_whatsapp || 0);
    $("#pm-funil").innerHTML = passos.map(function (p, i) {
      // a partir de "Receberam imóvel" a base é quem chegou ao WhatsApp (os passos não são um dentro do outro)
      var v = p[1] || 0, ref = i === 1 ? f.leads_olx : i > 1 ? f.no_whatsapp : null;
      var nota = i === 1 ? "dos contatos" : "de quem chegou";
      return '<div class="pm-funil__passo"><span>' + p[0] + '</span><div class="pm-funil__barra" style="--cor:' + p[2] + '"><i style="width:' +
        Math.round(v / base * 100) + '%"></i></div><div class="pm-funil__num">' + n(v) +
        (ref ? "<small>" + pct(v / ref) + " " + nota + "</small>" : "") + "</div></div>";
    }).join("") + '<p style="margin:8px 0 0;color:#8e8ea0;font-size:11px">+ ' + n(f.organicos) +
      " orgânicos (escreveram direto no 8595) no período. Visitaram = visita confirmada cujo horário já passou.</p>";
  }
  function renderCoortes() {
    var rows = dados.coortes_disparo || [];
    if (!rows.length) { $("#pm-coortes").innerHTML = '<p style="color:#8e8ea0;font-size:12px">Nenhum disparo no período.</p>'; return; }
    $("#pm-coortes").innerHTML = '<div class="pm-tabela-rolagem"><table class="pm-tabela"><thead><tr><th>Dia</th><th>Número</th>' +
      '<th class="num">Enviados</th><th class="num">Responderam</th><th class="num">Mudaram o status</th><th class="num">Atualizaram</th></tr></thead><tbody>' +
      rows.map(function (r) {
        var lr = r.linha === "oficial" ? '<span class="pm-pilula">Oficial</span>' : '<span class="pm-pilula pm-pilula--verde">Z-API</span>';
        return "<tr><td>" + dm(r.dia) + "</td><td>" + lr + '</td><td class="num">' + n(r.enviados) + "</td>" +
          celula(r.responderam, r.enviados, COR.laranja) + celula(r.mudaram, r.enviados, COR.amarelo) + celula(r.atualizaram, r.enviados, COR.verde) + "</tr>";
      }).join("") + "</tbody></table></div>";
    function celula(v, t, cor) {
      var p = t ? v / t : 0;
      return '<td class="num">' + n(v) + ' <small style="color:#8e8ea0">' + pct(p) + '</small><span class="pm-mini-barra" style="--cor:' + cor + '"><i style="width:' + Math.round(p * 100) + '%"></i></span></td>';
    }
  }
  function renderTop() {
    var rows = dados.top_imoveis || [];
    $("#pm-top").innerHTML = rows.length ? '<div class="pm-tabela-rolagem"><table class="pm-tabela"><thead><tr><th>Código</th><th>Imóvel</th><th class="num">Valor</th><th class="num">Pessoas</th></tr></thead><tbody>' +
      rows.map(function (r) {
        var nome = [r.tipo, r.condominio, r.bairro].filter(Boolean).join(" · ");
        var valor = r.aluguel ? reais(r.aluguel) + "/mês" : reais(r.venda);
        return '<tr><td><a href="imovel-editar.html?codigo=' + encodeURIComponent(r.codigo) + '">' + esc(r.codigo) + "</a></td><td style=\"white-space:normal\">" + esc(nome) +
          '</td><td class="num">' + esc(valor) + '</td><td class="num">' + n(r.vezes) + "</td></tr>";
      }).join("") + "</tbody></table></div>" : '<p style="color:#8e8ea0;font-size:12px">Nenhum imóvel enviado no período.</p>';
  }
  function renderFechamentos() {
    var rows = dados.fechamentos || [];
    $("#pm-fechamentos").innerHTML = rows.length ? '<div class="pm-tabela-rolagem"><table class="pm-tabela"><thead><tr><th>Cliente</th><th>Tipo</th><th>Começou</th><th>Concluiu</th><th class="num">Dias</th></tr></thead><tbody>' +
      rows.map(function (r) {
        var tipo = r.tipo === "locacao" ? "Locação" : r.tipo === "venda" ? "Venda" : "—";
        return "<tr><td>" + esc(r.nome || "—") + "</td><td>" + tipo + "</td><td>" + dm(String(r.iniciado_em).slice(0, 10)) + "</td><td>" +
          (r.concluido_em ? '<span class="pm-pilula pm-pilula--verde">' + dm(String(r.concluido_em).slice(0, 10)) + "</span>" : '<span class="pm-pilula pm-pilula--amarelo">em aberto</span>') +
          '</td><td class="num">' + n1(r.dias) + "</td></tr>";
      }).join("") + "</tbody></table></div>" : '<p style="color:#8e8ea0;font-size:12px">Nenhum fechamento no período.</p>';
  }

  /* ---------------- novidades dos últimos 30 dias ---------------- */
  function renderNovidades() {
    var AREAS = window.PAINEL_AREAS || {}, todas = window.PAINEL_NOVIDADES || [];
    var corte = somaDias(hoje(), -30);
    var lista = todas.filter(function (x) { return x.d >= corte; });
    if (!est.areas) { est.areas = {}; Object.keys(AREAS).forEach(function (k) { est.areas[k] = true; }); }
    var contagem = {};
    lista.forEach(function (x) { contagem[x.a] = (contagem[x.a] || 0) + 1; });
    var filtros = $("#pm-novidades-filtros");
    if (!filtros.dataset.pronto) {
      filtros.innerHTML = Object.keys(AREAS).filter(function (k) { return contagem[k]; }).map(function (k) {
        return '<button type="button" class="pm-tag" data-area="' + k + '" aria-pressed="true" style="--cor:' + AREAS[k].cor + '">' + esc(AREAS[k].rotulo) + " · " + contagem[k] + "</button>";
      }).join("") + '<input class="pm-campo pm-novidades__busca" type="search" placeholder="Procurar (ex.: OLX, 391, visita)" aria-label="Procurar nas novidades">';
      filtros.dataset.pronto = "1";
      filtros.addEventListener("click", function (e) {
        var b = e.target.closest(".pm-tag"); if (!b) return;
        var k = b.dataset.area, sozinha = e.altKey || e.metaKey;
        if (sozinha) Object.keys(est.areas).forEach(function (a) { est.areas[a] = a === k; });
        else est.areas[k] = !est.areas[k];
        filtros.querySelectorAll(".pm-tag").forEach(function (t) { t.setAttribute("aria-pressed", String(!!est.areas[t.dataset.area])); });
        desenharLista();
      });
      filtros.querySelector("input").addEventListener("input", desenharLista);
    }
    desenharLista();
    function desenharLista() {
      var q = (filtros.querySelector("input").value || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
      var vis = lista.filter(function (x) {
        if (!est.areas[x.a]) return false;
        if (!q) return true;
        var txt = [x.t, x.x, x.n, (AREAS[x.a] || {}).rotulo].join(" ").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
        return txt.indexOf(q) >= 0;
      });
      var porDia = {};
      vis.forEach(function (x) { (porDia[x.d] = porDia[x.d] || []).push(x); });
      var dias = Object.keys(porDia).sort().reverse();
      $("#pm-novidades-total").textContent = vis.length + " de " + lista.length;
      $("#pm-novidades").innerHTML = dias.length ? dias.map(function (dia) {
        return '<section class="pm-novidades__dia"><h4>' + rotuloDia(dia) + "</h4>" + porDia[dia].map(function (x) {
          var A = AREAS[x.a] || { rotulo: x.a, cor: "#9aa0ac" };
          return '<div class="pm-novidade"><span><span class="pm-tag" style="--cor:' + A.cor + '">' + esc(A.rotulo) + "</span></span><p><b>" + esc(x.t) + "</b>" +
            (x.x ? " — " + esc(x.x) : "") + (x.n ? ' <small>(' + esc(x.n) + ")</small>" : "") + "</p></div>";
        }).join("") + "</section>";
      }).join("") : '<p style="color:#8e8ea0;font-size:12px">Nada com esse filtro.</p>';
    }
    function rotuloDia(iso) { return SEMANA[new Date(iso + "T12:00:00Z").getUTCDay()] + ", " + dm(iso); }
  }

  /* ---------------- controles e carga ---------------- */
  function sincronizarControles() {
    raiz.querySelectorAll('[data-grupo="periodo"] button').forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.v === est.periodo)); });
    raiz.querySelectorAll('[data-grupo="grao"] button').forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.v === est.grao)); });
    raiz.querySelectorAll('[data-grupo="medida"] button').forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.v === est.medida)); });
    $("#pm-linha").value = est.linha;
    var custom = est.periodo === "custom";
    $(".pm-datas").hidden = !custom;
    if (custom) { $("#pm-de").value = est.de || ""; $("#pm-ate").value = est.ate || ""; }
    $("#pm-voltar").hidden = !est.pilha.length;
  }
  raiz.querySelector('[data-grupo="periodo"]').addEventListener("click", function (e) {
    var b = e.target.closest("button"); if (!b) return;
    if (b.dataset.v === "custom") {
      var iv = intervalo(); est.de = iv.de; est.ate = iv.ate;
    }
    est.pilha = []; est.periodo = b.dataset.v; guardar(); sincronizarControles();
    if (b.dataset.v !== "custom") carregar();
  });
  raiz.querySelector('[data-grupo="grao"]').addEventListener("click", function (e) {
    var b = e.target.closest("button"); if (!b) return;
    est.grao = b.dataset.v; guardar(); sincronizarControles(); carregar();
  });
  raiz.querySelector('[data-grupo="medida"]').addEventListener("click", function (e) {
    var b = e.target.closest("button"); if (!b) return;
    est.medida = b.dataset.v; guardar(); sincronizarControles(); if (dados) renderGrade();
  });
  $("#pm-linha").addEventListener("change", function () {
    est.linha = this.value; guardar(); if (dados) { renderHero(); renderKpis(); }
  });
  function datasMudaram() {
    var de = $("#pm-de").value, ate = $("#pm-ate").value;
    if (!de || !ate) return;
    if (de > ate) { var t = de; de = ate; ate = t; }
    est.de = de; est.ate = menor(ate, hoje()); carregar();
  }
  $("#pm-de").addEventListener("change", datasMudaram);
  $("#pm-ate").addEventListener("change", datasMudaram);
  $("#pm-atualizar").addEventListener("click", function () { carregar(); });
  $("#pm-voltar").addEventListener("click", function () {
    var s = est.pilha.pop(); if (!s) return;
    est.periodo = s.periodo; est.de = s.de; est.ate = s.ate; est.grao = s.grao;
    sincronizarControles(); carregar();
  });

  function pedir(url) {
    return fetch(url, { credentials: "same-origin" }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página e entre de novo");
        if (!r.ok) throw new Error(d.erro || ("HTTP " + r.status));
        return d;
      });
    });
  }
  function rota(iv) { return "/admin/api/painel?de=" + iv.de + "&ate=" + iv.ate + "&grao=" + est.grao; }
  function carregar() {
    var iv = intervalo();
    if (!iv.de || !iv.ate) return;
    var tam = diasEntre(iv.de, iv.ate) + 1;
    var antes = { de: somaDias(iv.de, -tam), ate: somaDias(iv.de, -1) };
    carregando = true;
    raiz.classList.add("pm-carregando");
    $("#pm-atualizar").classList.add("girando");
    Promise.all([pedir(rota(iv)), pedir(rota(antes)).catch(function () { return null; })]).then(function (r) {
      dados = r[0]; anterior = r[1];
      var aviso = $(".pm__aviso");
      if (!temPessoas(dados)) {
        aviso.hidden = false;
        aviso.textContent = "Pessoas por número: o CRM não respondeu agora (" + ((dados.pessoas && dados.pessoas.erro) || "sem resposta") +
          "). O resto do painel está completo.";
      } else aviso.hidden = true;
      $("#pm-periodo").textContent = "de " + dm(dados.de) + "/" + dados.de.slice(0, 4) + " a " + dm(dados.ate) + "/" + dados.ate.slice(0, 4) +
        " · por " + { dia: "dia", semana: "semana", mes: "mês" }[dados.grao] + " · atualizado às " +
        new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
      renderHero(); renderKpis(); renderLinhas(); renderGrade(); renderFunil(); renderCoortes(); renderTop(); renderFechamentos();
    }).catch(function (err) {
      var aviso = $(".pm__aviso"); aviso.hidden = false; aviso.textContent = "Não consegui carregar o painel: " + err.message;
    }).then(function () {
      carregando = false;
      raiz.classList.remove("pm-carregando");
      $("#pm-atualizar").classList.remove("girando");
    });
  }

  sincronizarControles();
  renderNovidades();
  carregar();
  // de 5 em 5 minutos, com a aba à vista
  setInterval(function () { if (document.visibilityState === "visible" && !carregando) carregar(); }, 5 * 60 * 1000);
})();
