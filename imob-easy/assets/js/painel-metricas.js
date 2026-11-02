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

  /* ---------------- AS ABAS (404, Pedro 17/10: "distribua as coisas por categoria ... cada gráfico por função") ----
     Cada aba tem os números grandes dela (com o ▲/▼ do período anterior) e no máximo um ou dois gráficos da função.
     Só a aba aberta é desenhada; as outras são desenhadas quando forem abertas (o Chart.js não mede canvas escondido). */
  var ABAS = ["resumo", "corretores", "visitas", "donos", "olx", "catalogo", "imoveis", "fechamentos", "novidades"];
  var desenhadas = {};
  try { var abaGuardada = localStorage.getItem("painelMetricasAba"); if (ABAS.indexOf(abaGuardada) >= 0) est.aba = abaGuardada; } catch (e) { /* padrão */ }
  if (ABAS.indexOf(est.aba) < 0) est.aba = "resumo";

  function tile(k, i, aba) {
    var v = k.v(dados), a = anterior && !k.semDelta ? k.v(anterior) : null;
    var txt = k.fmt === "pct" ? pct(v) : k.fmt === "1" ? n1(v) : n(v);
    return '<article class="pm-painel pm-kpi" style="--cor:' + k.cor + '">' +
      '<div class="pm-kpi__rotulo"><span>' + esc(k.rot) + (k.info ? ' <span class="pm-info" title="' + esc(k.info) + '">i</span>' : "") +
      "</span>" + delta(v, a) + "</div>" +
      '<div class="pm-kpi__valor">' + txt + "</div>" +
      '<div class="pm-kpi__sub">' + esc(k.sub ? k.sub(dados) : "") + "</div>" +
      '<div class="pm-kpi__spark"><canvas id="pm-spark-' + aba + "-" + i + '"></canvas></div></article>';
  }
  function renderKpis(aba, lista) {
    var caixa = document.getElementById("pm-kpis-" + aba);
    if (!caixa) return;
    caixa.innerHTML = lista.map(function (k, i) { return tile(k, i, aba); }).join("");
    lista.forEach(function (k, i) {
      if (!k.s) return;
      desenhar("pm-spark-" + aba + "-" + i, {
        type: "line",
        data: { labels: labels(), datasets: [{ data: k.s(dados), borderColor: k.cor, borderWidth: 1.5, pointRadius: 0, tension: 0.35,
          fill: "origin", backgroundColor: alfa(k.cor, 0.16), spanGaps: true }] },
        options: { responsive: true, maintainAspectRatio: false, animation: false, events: [],
          plugins: { legend: { display: false }, tooltip: { enabled: false } },
          scales: { x: { display: false }, y: { display: false, beginAtZero: true } }, layout: { padding: 0 } }
      });
    });
  }
  function funil(id, passos, nota) {
    var base = Math.max(1, passos[0][1] || 0);
    document.getElementById(id).innerHTML = passos.map(function (p, i) {
      var v = p[1] || 0, ref = i > 0 ? passos[i - 1][1] || 0 : null;
      return '<div class="pm-funil__passo"><span>' + esc(p[0]) + '</span><div class="pm-funil__barra" style="--cor:' + p[2] +
        '"><i style="width:' + Math.min(100, Math.round(v / base * 100)) + '%"></i></div><div class="pm-funil__num">' + n(v) +
        (ref ? "<small>" + pct(v / ref) + " do passo antes</small>" : "") + "</div></div>";
    }).join("") + (nota ? '<p style="margin:10px 0 0;color:#8e8ea0;font-size:11px">' + nota + "</p>" : "");
  }
  var VISITAS = ["visitas", "visitas_olx"];

  /* RESUMO: os números do negócio inteiro, o caminho até o negócio e os três números de WhatsApp */
  function renderResumo() {
    var l = est.linha;
    renderKpis("resumo", [
      { rot: "Pessoas que falamos", cor: COR.azul, info: "pessoas distintas com conversa " + (l === "todas" ? "nos três números" : "no número " + LINHAS[l].rotulo),
        v: function (d) { return pessoasTotal(d, l, "conversaram"); },
        sub: function (d) { return temPessoas(d) ? n(pessoasTotal(d, l, "novas")) + " novas" : "sem o CRM agora"; },
        s: function (d) { return pessoasSerie(d, l, "conversaram") || zeros(d); } },
      { rot: "Visitas agendadas", cor: COR.roxo, info: "visitas marcadas no período (Parceria e clientes da OLX)",
        v: function (d) { return somaT(d, VISITAS); },
        sub: function (d) { return n(T(d, "visitas_nay")) + " Nay · " + n(T(d, "visitas_crm")) + " CRM · " + n(T(d, "visitas_olx")) + " OLX"; },
        s: function (d) { return soma(d, VISITAS); } },
      { rot: "Visitas realizadas", cor: COR.teal, info: "o que a equipe marcou como Realizada ou Fechou negócio (aba Visitas)",
        v: function (d) { return T(d, "visitas_realizadas"); },
        sub: function (d) { return n(T(d, "visitas_sem_resultado")) + " ainda a marcar"; },
        s: function (d) { return S(d, "visitas_realizadas"); } },
      { rot: "Negócios fechados", cor: COR.verde, info: "visitas marcadas como Fechou negócio; e os concluídos na aba Fechamento",
        v: function (d) { return T(d, "visitas_fechou"); },
        sub: function (d) { return n(T(d, "fech_concluidos")) + " concluídos na aba Fechamento"; },
        s: function (d) { return S(d, "visitas_fechou"); } },
      { rot: "Imóveis enviados", cor: COR.laranja, info: "pares pessoa × imóvel que saíram (corretores e clientes)",
        v: function (d) { return somaT(d, ["enviados", "enviados_captacao"]); },
        sub: function (d) { return n(T(d, "destinatarios") + T(d, "destinatarios_captacao")) + " pessoas receberam"; },
        s: function (d) { return soma(d, ["enviados", "enviados_captacao"]); } },
      { rot: "Imóveis novos", cor: COR.rosa, info: "imóveis que entraram no cadastro",
        v: function (d) { return T(d, "imoveis_novos"); },
        sub: function (d) { return n(T(d, "olx_anuncios")) + " anúncios novos na OLX"; },
        s: function (d) { return S(d, "imoveis_novos"); } }
    ]);
    var p = pessoasTotal(dados, "todas", "conversaram");
    funil("pm-funil-negocio", [
      ["Pessoas que falamos", p, COR.azul],
      ["Visitas agendadas", somaT(dados, VISITAS), COR.roxo],
      ["Visitas realizadas", T(dados, "visitas_realizadas"), COR.teal],
      ["Fechou negócio", T(dados, "visitas_fechou"), COR.verde]
    ], T(dados, "visitas_sem_resultado") ? n(T(dados, "visitas_sem_resultado")) + " visitas do período ainda sem resultado: marque na aba Visitas." : "");
    renderPessoasPorNumero();
    renderLinhas();
  }
  function renderPessoasPorNumero() {
    var med = est.medida === "alcancados" ? "conversaram" : est.medida;
    var ds = Object.keys(LINHAS).map(function (k) { return linha(LINHAS[k].rotulo, pessoasSerie(dados, k, med) || zeros(dados), LINHAS[k].cor); });
    ds.push(linha("Todas (sem repetir)", pessoasSerie(dados, "todas", med) || zeros(dados), "#d8d9da", { borderDash: [4, 4], borderWidth: 1.5 }));
    desenhar("pm-g-pessoas", { data: { labels: labels(), datasets: ds }, options: opcoes({ scales: { y: { stacked: false } } }) });
    $("#pm-g-pessoas-vazio").hidden = !!temPessoas(dados);
  }

  /* CORRETORES: um gráfico, corretores × imóveis */
  function renderCorretores() {
    renderKpis("corretores", [
      { rot: "Corretores atendidos", cor: COR.roxo, info: "pessoas com conversa no número da Parceria",
        v: function (d) { return pessoasTotal(d, "parceria", "conversaram"); },
        sub: function (d) { return temPessoas(d) ? n(pessoasTotal(d, "parceria", "novas")) + " novos" : "sem o CRM agora"; },
        s: function (d) { return pessoasSerie(d, "parceria", "conversaram") || zeros(d); } },
      { rot: "Receberam imóvel", cor: COR.ciano, info: "corretores (e clientes da Parceria) que receberam ao menos um imóvel",
        v: function (d) { return T(d, "destinatarios"); }, s: function (d) { return S(d, "destinatarios"); } },
      { rot: "Imóveis enviados", cor: COR.laranja, info: "pares corretor × imóvel que saíram pela Parceria",
        v: function (d) { return T(d, "enviados"); },
        sub: function (d) { return n(T(d, "enviados_nay")) + " pela Nay · " + n(T(d, "enviados_equipe")) + " pela equipe"; },
        s: function (d) { return S(d, "enviados"); } },
      { rot: "Média por corretor", cor: COR.amarelo, fmt: "1", info: "imóveis enviados ÷ quem recebeu",
        v: function (d) { return T(d, "destinatarios") ? T(d, "enviados") / T(d, "destinatarios") : null; },
        s: function (d) { return razao(S(d, "enviados"), S(d, "destinatarios")); } },
      { rot: "Pedidos nos grupos", cor: COR.azul, info: "pedidos de imóvel dos corretores nos grupos (o mesmo pedido em vários grupos conta uma vez)",
        v: function (d) { return T(d, "pedidos_grupo"); },
        sub: function (d) { return n(T(d, "pedidos_grupo_atendidos")) + " atendidos"; }, s: function (d) { return S(d, "pedidos_grupo"); } },
      { rot: "Visitas pela Parceria", cor: COR.teal, info: "visitas marcadas pelos corretores (Nay e CRM)",
        v: function (d) { return T(d, "visitas"); }, s: function (d) { return S(d, "visitas"); } }
    ]);
    desenhar("pm-g-corretores", { data: { labels: labels(), datasets: [
      barra("Imóveis enviados pela Nay", S(dados, "enviados_nay"), COR.verde),
      barra("Imóveis enviados pela equipe", S(dados, "enviados_equipe"), COR.azul),
      linha("Corretores que receberam", S(dados, "destinatarios"), "#d8d9da", { borderDash: [4, 4], borderWidth: 1.5 }),
      linha("Média por corretor", razao(S(dados, "enviados"), S(dados, "destinatarios")), COR.amarelo, { yAxisID: "y1", formato: "1", stack: "media" })
    ] }, options: opcoes({ scales: { y: { title: { display: true, text: "imóveis / corretores", color: "#8e8ea0" } },
      y1: eixoDireito({ ticks: { precision: 1 }, title: { display: true, text: "média por corretor", color: "#8e8ea0" } }) } }) });
    var g = function (rot, v, sub) { return "<div><span>" + rot + "</span><strong>" + n(v) + "</strong>" + (sub ? "<small>" + sub + "</small>" : "") + "</div>"; };
    $("#pm-grupos").innerHTML =
      g("Posts de imóvel nos grupos", T(dados, "grupo_posts")) +
      g("Imóveis divulgados", T(dados, "grupo_imoveis")) +
      g("Pedidos dos corretores", T(dados, "pedidos_grupo")) +
      g("Pedidos atendidos", T(dados, "pedidos_grupo_atendidos"),
        T(dados, "pedidos_grupo") ? pct(T(dados, "pedidos_grupo_atendidos") / T(dados, "pedidos_grupo")) : "") +
      g("Perguntas ao Tel", T(dados, "perguntas")) +
      g("Respondidas pelo Tel", T(dados, "perguntas_respondidas"));
    renderTop();
  }

  /* VISITAS: os números do resultado, um gráfico e a lista para marcar */
  function renderVisitasAba() {
    renderKpis("visitas", [
      { rot: "Agendadas", cor: COR.roxo, info: "visitas marcadas no período (pelo dia em que foram marcadas)",
        v: function (d) { return somaT(d, VISITAS); }, s: function (d) { return soma(d, VISITAS); } },
      { rot: "Realizadas", cor: COR.azul, info: "marcadas como Realizada ou Fechou negócio (pelo dia da visita)",
        v: function (d) { return T(d, "visitas_realizadas"); }, s: function (d) { return S(d, "visitas_realizadas"); } },
      { rot: "Fechou negócio", cor: COR.verde, info: "marcadas como Fechou negócio",
        v: function (d) { return T(d, "visitas_fechou"); }, s: function (d) { return S(d, "visitas_fechou"); } },
      { rot: "Desistiu", cor: COR.vermelho, info: "marcadas como Desistiu",
        v: function (d) { return T(d, "visitas_desistiu"); }, s: function (d) { return S(d, "visitas_desistiu"); } },
      { rot: "A marcar", cor: COR.amarelo, semDelta: true, info: "visitas do período que já passaram e ainda não têm resultado",
        v: function (d) { return T(d, "visitas_sem_resultado"); }, s: function (d) { return S(d, "visitas_sem_resultado"); } },
      { rot: "Visita → negócio", cor: COR.teal, fmt: "pct", info: "fechou negócio ÷ visitas realizadas",
        v: function (d) { return T(d, "visitas_realizadas") ? T(d, "visitas_fechou") / T(d, "visitas_realizadas") : null; } }
    ]);
    var real = S(dados, "visitas_realizadas"), fechou = S(dados, "visitas_fechou");
    desenhar("pm-g-visitas", { data: { labels: labels(), datasets: [
      barra("Fechou negócio", fechou, COR.verde),
      barra("Realizada", real.map(function (v, i) { return Math.max(0, v - (fechou[i] || 0)); }), COR.azul),
      barra("Desistiu", S(dados, "visitas_desistiu"), COR.vermelho),
      barra("A marcar", S(dados, "visitas_sem_resultado"), COR.cinza, { backgroundColor: alfa(COR.cinza, 0.35) }),
      linha("Agendadas", soma(dados, VISITAS), COR.roxo)
    ] }, options: opcoes() });
    renderVlista();
  }

  /* DONOS E DISPAROS: o funil do disparo, um gráfico e cada disparo */
  function renderDonos() {
    renderKpis("donos", [
      { rot: "Disparos", cor: COR.azul, info: "mensagens de captação que saíram para proprietários (oficial e Z-API)",
        v: function (d) { return T(d, "disparos"); },
        sub: function (d) { return n(T(d, "disparos_oficial")) + " oficial · " + n(T(d, "disparos_zapi")) + " Z-API"; },
        s: function (d) { return S(d, "disparos"); } },
      { rot: "Responderam", cor: COR.laranja, info: "donos que responderam no período",
        v: function (d) { return T(d, "responderam"); }, s: function (d) { return S(d, "responderam"); } },
      { rot: "Mudaram o status", cor: COR.amarelo, info: "o dono disse algo novo e o cadastro mudou",
        v: function (d) { return T(d, "status_mudou"); }, s: function (d) { return S(d, "status_mudou"); } },
      { rot: "Confirmaram", cor: COR.verde, info: "o dono confirmou o cadastro como está",
        v: function (d) { return T(d, "status_confirmado"); }, s: function (d) { return S(d, "status_confirmado"); } }
    ]);
    var c = (dados.coortes_disparo || []).reduce(function (a, r) {
      a.e += r.enviados; a.r += r.responderam; a.m += r.mudaram; a.t += r.atualizaram; return a;
    }, { e: 0, r: 0, m: 0, t: 0 });
    funil("pm-funil-donos", [
      ["Receberam disparo", c.e, COR.azul],
      ["Responderam (7 dias)", c.r, COR.laranja],
      ["Atualizaram o cadastro", c.t, COR.verde],
      ["Mudaram o status", c.m, COR.amarelo]
    ]);
    desenhar("pm-g-disparos", { data: { labels: labels(), datasets: [
      barra("Oficial (Meta)", S(dados, "disparos_oficial"), COR.azul),
      barra("Z-API", S(dados, "disparos_zapi"), COR.verde),
      linha("Responderam", S(dados, "responderam"), COR.laranja, { yAxisID: "y1", stack: "r" }),
      linha("Cadastros atualizados", soma(dados, ["status_mudou", "status_confirmado"]), COR.amarelo, { yAxisID: "y1", stack: "s" })
    ] }, options: opcoes({ scales: { y1: eixoDireito({ title: { display: true, text: "respostas", color: "#8e8ea0" } }) } }) });
    renderCoortes();
  }

  /* CLIENTES OLX */
  function renderOlx() {
    renderKpis("olx", [
      { rot: "Contatos da OLX", cor: COR.laranja, info: "contatos que a OLX mandou no período",
        v: function (d) { return T(d, "olx_leads"); }, s: function (d) { return S(d, "olx_leads"); } },
      { rot: "Chegaram ao WhatsApp", cor: COR.amarelo, info: "clientes da OLX que a Nay atende no 8595",
        v: function (d) { return T(d, "olx_whatsapp"); }, s: function (d) { return S(d, "olx_whatsapp"); } },
      { rot: "Orgânicos (8595)", cor: COR.azul, info: "quem escreveu direto no 8595 sem vir da OLX",
        v: function (d) { return T(d, "organicos"); }, s: function (d) { return S(d, "organicos"); } },
      { rot: "Imóveis enviados", cor: COR.verde, info: "imóveis que a Nay do WhatsApp mandou para esses clientes",
        v: function (d) { return T(d, "enviados_captacao"); }, s: function (d) { return S(d, "enviados_captacao"); } },
      { rot: "Visitas OLX", cor: COR.roxo, info: "visitas marcadas com clientes da OLX",
        v: function (d) { return T(d, "visitas_olx"); },
        sub: function (d) { return n(T(d, "visitas_olx_confirmadas")) + " confirmadas"; }, s: function (d) { return S(d, "visitas_olx"); } },
      { rot: "Anúncios publicados", cor: COR.rosa, info: "anúncios nossos que entraram na OLX",
        v: function (d) { return T(d, "olx_anuncios"); }, s: function (d) { return S(d, "olx_anuncios"); } }
    ]);
    renderFunil();
    desenhar("pm-g-olx", { data: { labels: labels(), datasets: [
      barra("Contatos da OLX", S(dados, "olx_leads"), COR.laranja),
      barra("Orgânicos (8595)", S(dados, "organicos"), COR.azul),
      linha("Chegaram ao WhatsApp", S(dados, "olx_whatsapp"), COR.amarelo),
      linha("Visitas OLX", S(dados, "visitas_olx"), COR.roxo)
    ] }, options: opcoes() });
  }

  /* CATÁLOGO: as coisas novas, um gráfico */
  function renderCatalogo() {
    renderKpis("catalogo", [
      { rot: "Imóveis novos", cor: COR.rosa, info: "imóveis que entraram no cadastro (a carga da planilha antiga de 26/09 não conta)",
        v: function (d) { return T(d, "imoveis_novos"); },
        sub: function (d) { return n(T(d, "imoveis_novos_olx")) + " OLX · " + n(T(d, "imoveis_novos_crm")) + " CRM · " + n(T(d, "imoveis_novos_site") + T(d, "imoveis_novos_outros")) + " site"; },
        s: function (d) { return S(d, "imoveis_novos"); } },
      { rot: "Anúncios na OLX", cor: COR.laranja, info: "anúncios nossos publicados na OLX",
        v: function (d) { return T(d, "olx_anuncios"); }, s: function (d) { return S(d, "olx_anuncios"); } },
      { rot: "Cadastros atualizados", cor: COR.amarelo, info: "o dono respondeu e o cadastro mudou ou foi confirmado",
        v: function (d) { return somaT(d, ["status_mudou", "status_confirmado"]); },
        s: function (d) { return soma(d, ["status_mudou", "status_confirmado"]); } },
      { rot: "Divulgados nos grupos", cor: COR.ciano, info: "imóveis diferentes postados nos grupos de corretores",
        v: function (d) { return T(d, "grupo_imoveis"); }, sub: function (d) { return n(T(d, "grupo_posts")) + " posts"; },
        s: function (d) { return S(d, "grupo_imoveis"); } }
    ]);
    desenhar("pm-g-catalogo", { data: { labels: labels(), datasets: [
      barra("Novos pela OLX", S(dados, "imoveis_novos_olx"), COR.laranja),
      barra("Novos pelo CRM", S(dados, "imoveis_novos_crm"), COR.azul),
      barra("Novos pelo site", soma(dados, ["imoveis_novos_site", "imoveis_novos_outros"]), COR.rosa),
      linha("Anúncios publicados na OLX", S(dados, "olx_anuncios"), COR.amarelo, { yAxisID: "y1", stack: "an" }),
      linha("Cadastros atualizados pelos donos", soma(dados, ["status_mudou", "status_confirmado"]), COR.verde, { yAxisID: "y1", stack: "st" })
    ] }, options: opcoes({ scales: { y: { title: { display: true, text: "imóveis novos", color: "#8e8ea0" } },
      y1: eixoDireito({ title: { display: true, text: "anúncios / atualizados", color: "#8e8ea0" } }) } }) });
  }

  /* FECHAMENTOS */
  function renderFechamentosAba() {
    var lista = dados.fechamentos || [];
    var feitos = lista.filter(function (f) { return f.dias != null; });
    var media = feitos.length ? feitos.reduce(function (a, f) { return a + Number(f.dias); }, 0) / feitos.length : null;
    renderKpis("fechamentos", [
      { rot: "Concluídos", cor: COR.verde, info: "fechamentos concluídos na aba Fechamento",
        v: function (d) { return T(d, "fech_concluidos"); }, s: function (d) { return S(d, "fech_concluidos"); } },
      { rot: "Abertos no período", cor: COR.azul, info: "fechamentos que começaram no período",
        v: function (d) { return T(d, "fech_iniciados"); }, s: function (d) { return S(d, "fech_iniciados"); } },
      { rot: "Tempo médio", cor: COR.amarelo, fmt: "1", semDelta: true, info: "dias do começo à conclusão (os concluídos do período)",
        v: function () { return media; }, sub: function () { return "dias até concluir"; } },
      { rot: "Visitas que fecharam", cor: COR.teal, info: "visitas marcadas como Fechou negócio",
        v: function (d) { return T(d, "visitas_fechou"); }, s: function (d) { return S(d, "visitas_fechou"); } }
    ]);
    desenhar("pm-g-fech", { data: { labels: labels(), datasets: [
      barra("Abertos", S(dados, "fech_iniciados"), COR.azul, { stack: "a" }),
      barra("Concluídos", S(dados, "fech_concluidos"), COR.verde, { stack: "c" })
    ] }, options: opcoes({ scales: { x: { stacked: false }, y: { stacked: false } } }) });
    renderFechamentos();
  }

  var RENDER = { resumo: renderResumo, corretores: renderCorretores, visitas: renderVisitasAba, donos: renderDonos,
                 olx: renderOlx, catalogo: renderCatalogo, fechamentos: renderFechamentosAba, novidades: renderNovidades,
                 imoveis: function () { if (window.PainelImoveis) window.PainelImoveis.abrir(); } };   // 563: a aba Imóveis tem o próprio arquivo
  function mostrarAba(aba) {
    est.aba = aba;
    try { localStorage.setItem("painelMetricasAba", aba); } catch (e) { /* tanto faz */ }
    raiz.querySelectorAll(".pm-abas [data-aba]").forEach(function (b) { b.setAttribute("aria-selected", String(b.dataset.aba === aba)); });
    raiz.querySelectorAll(".pm-aba").forEach(function (s) { s.hidden = s.dataset.aba !== aba; });
    desenharAba();
  }
  function desenharAba() {
    var aba = est.aba;
    if (aba !== "novidades" && aba !== "imoveis" && !dados) return;
    if (desenhadas[aba]) return;
    desenhadas[aba] = true;
    RENDER[aba]();
  }
  raiz.querySelector(".pm-abas").addEventListener("click", function (e) {
    var b = e.target.closest("[data-aba]"); if (b) mostrarAba(b.dataset.aba);
  });

  /* A LISTA DAS VISITAS, com o resultado marcado à mão */
  var visitas = [], vfiltro = "amarcar";
  var VFILTROS = [["amarcar", "A marcar"], ["todas", "Todas"], ["realizada", "Realizadas"], ["fechou", "Fechou negócio"],
                  ["desistiu", "Desistiu"], ["proximas", "Próximas"]];
  var RESULTADOS = [["desistiu", "Desistiu"], ["realizada", "Realizada"], ["fechou", "Fechou negócio"]];
  function carregarVisitas() {
    var iv = intervalo();
    if (!iv.de) return Promise.resolve();
    return pedir("/admin/api/painel/visitas?de=" + iv.de + "&ate=" + somaDias(hoje(), 14)).then(function (j) {
      visitas = j.visitas || [];
      var amarcar = visitas.filter(function (v) { return v.passou && !v.resultado; }).length;
      var badge = $("#pm-aba-amarcar");
      badge.hidden = !amarcar; badge.textContent = amarcar;
      if (desenhadas.visitas) renderVlista();
    }).catch(function (err) {
      $("#pm-vlista").innerHTML = '<p style="color:#ff8a98;font-size:12px">Não consegui ler as visitas: ' + esc(err.message) + "</p>";
    });
  }
  function passaFiltro(v) {
    if (vfiltro === "todas") return true;
    if (vfiltro === "amarcar") return v.passou && !v.resultado;
    if (vfiltro === "proximas") return !v.passou;
    return v.resultado === vfiltro;
  }
  function quandoTexto(iso) {
    var d = new Date(iso);
    var dia = d.toLocaleDateString("pt-BR", { timeZone: "America/Manaus", weekday: "short", day: "2-digit", month: "2-digit" });
    var hora = d.toLocaleTimeString("pt-BR", { timeZone: "America/Manaus", hour: "2-digit", minute: "2-digit" });
    return [dia.replace(".", ""), hora];
  }
  function renderVlista() {
    var cont = {};
    VFILTROS.forEach(function (f) { var k = f[0], keep = vfiltro; vfiltro = k; cont[k] = visitas.filter(passaFiltro).length; vfiltro = keep; });
    $("#pm-vfiltros").innerHTML = VFILTROS.map(function (f) {
      return '<button type="button" class="pm-chip" data-vf="' + f[0] + '" aria-pressed="' + (vfiltro === f[0]) + '" style="--cor:' +
        (f[0] === "amarcar" ? COR.amarelo : f[0] === "fechou" ? COR.verde : f[0] === "desistiu" ? COR.vermelho : f[0] === "realizada" ? COR.azul : COR.cinza) +
        '"><i></i>' + f[1] + " · " + cont[f[0]] + "</button>";
    }).join("");
    var lista = visitas.filter(passaFiltro);
    $("#pm-vcontagem").textContent = visitas.length + " no período (e as dos próximos 14 dias)";
    if (!lista.length) {
      $("#pm-vlista").innerHTML = '<p style="color:#8e8ea0;font-size:12px;padding:8px 0">' +
        (vfiltro === "amarcar" ? "Nenhuma visita esperando resultado. 👍" : "Nenhuma visita com esse filtro.") + "</p>";
      return;
    }
    $("#pm-vlista").innerHTML = lista.map(function (v) {
      var q = quandoTexto(v.quando);
      var origem = v.origem === "olx" ? '<span class="pm-pilula" style="background:rgba(255,152,48,.15);color:#ffb366">OLX</span>'
                                      : '<span class="pm-pilula">' + esc(v.marcada_por) + "</span>";
      var pessoas = [v.cliente ? "Cliente <b>" + esc(v.cliente) + "</b>" : "", v.corretor ? "Corretor <b>" + esc(v.corretor) + "</b>" : ""]
        .filter(Boolean).join(" · ") || "—";
      var botoes = RESULTADOS.map(function (r) {
        return '<button type="button" data-r="' + r[0] + '" aria-pressed="' + (v.resultado === r[0]) + '"' +
          (v.passou ? "" : ' disabled title="a visita ainda não aconteceu"') + ">" + r[1] + "</button>";
      }).join("");
      var salvo = v.resultado && v.marcado_em ? "marcado por " + esc(v.marcado_por || "") + " em " +
        new Date(v.marcado_em).toLocaleDateString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit" }) : "";
      return '<div class="pm-visita" data-o="' + v.origem + '" data-id="' + v.id + '">' +
        '<div class="pm-visita__quando"><strong>' + esc(q[0]) + "</strong><small>" + esc(q[1]) + "</small></div>" +
        '<div class="pm-visita__imovel"><a href="imovel-editar.html?codigo=' + encodeURIComponent(v.codigo) + '">#' + esc(v.codigo) + "</a> " +
          "<span>" + esc(v.imovel || "") + "</span><div style=\"margin-top:3px\">" + origem +
          ' <small style="color:#8e8ea0">' + esc(String(v.estado || "").replace(/_/g, " ")) + "</small></div></div>" +
        '<div class="pm-visita__pessoas">' + pessoas + (v.nota_do_sistema ? '<br><span title="o que o sistema anotou">' + esc(v.nota_do_sistema) + "</span>" : "") + "</div>" +
        '<div class="pm-visita__acoes"><div class="pm-res">' + botoes + '</div><div class="pm-visita__salvo">' + salvo + "</div></div></div>";
    }).join("");
  }
  var recarga = null;
  $("#pm-vfiltros").addEventListener("click", function (e) {
    var b = e.target.closest("[data-vf]"); if (!b) return;
    vfiltro = b.dataset.vf; renderVlista();
  });
  $("#pm-vlista").addEventListener("click", function (e) {
    var b = e.target.closest(".pm-res button"); if (!b || b.disabled) return;
    var linhaEl = b.closest(".pm-visita"), origem = linhaEl.dataset.o, id = +linhaEl.dataset.id;
    var v = visitas.filter(function (x) { return x.origem === origem && x.id === id; })[0];
    if (!v) return;
    var novo = v.resultado === b.dataset.r ? "" : b.dataset.r;     // clicar no marcado limpa
    var salvoEl = linhaEl.querySelector(".pm-visita__salvo");
    salvoEl.textContent = "salvando…";
    fetch("/admin/api/painel/visitas/" + origem + "/" + id, {
      method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ resultado: novo })
    }).then(function (r) { return r.json().then(function (j) { if (!r.ok || !j.ok) throw new Error(j.erro || "não salvou"); return j; }); })
      .then(function (j) {
        v.resultado = j.resultado || null; v.marcado_por = "você"; v.marcado_em = new Date().toISOString();
        var amarcar = visitas.filter(function (x) { return x.passou && !x.resultado; }).length;
        $("#pm-aba-amarcar").hidden = !amarcar; $("#pm-aba-amarcar").textContent = amarcar;
        renderVlista();
        // os números do painel refazem em silêncio (um pouco depois, para juntar vários cliques)
        clearTimeout(recarga);
        recarga = setTimeout(function () { carregar(true); }, 1500);
      })
      .catch(function (err) { salvoEl.textContent = "não salvou: " + err.message; });
  });

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
    est.medida = b.dataset.v; guardar(); sincronizarControles(); if (dados && desenhadas.resumo) renderPessoasPorNumero();
  });
  $("#pm-linha").addEventListener("change", function () {
    est.linha = this.value; guardar(); if (dados) { renderHero(); desenhadas.resumo = false; if (est.aba === "resumo") desenharAba(); }
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
  function carregar(silencioso) {
    var iv = intervalo();
    if (!iv.de || !iv.ate) return;
    var tam = diasEntre(iv.de, iv.ate) + 1;
    var antes = { de: somaDias(iv.de, -tam), ate: somaDias(iv.de, -1) };
    carregando = true;
    if (!silencioso) { raiz.classList.add("pm-carregando"); if (typeof carregarVisitas === "function" && visitas) carregarVisitas(); }
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
      renderHero();
      desenhadas = { novidades: desenhadas.novidades };
      desenharAba();
    }).catch(function (err) {
      var aviso = $(".pm__aviso"); aviso.hidden = false; aviso.textContent = "Não consegui carregar o painel: " + err.message;
    }).then(function () {
      carregando = false;
      raiz.classList.remove("pm-carregando");
      $("#pm-atualizar").classList.remove("girando");
    });
  }

  sincronizarControles();
  mostrarAba(est.aba);
  carregar();
  // de 5 em 5 minutos, com a aba à vista
  setInterval(function () { if (document.visibilityState === "visible" && !carregando) carregar(); }, 5 * 60 * 1000);
})();
