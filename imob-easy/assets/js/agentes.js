/* ==========================================================================
   Agentes de IA (11/10/2026, Pedro: "vários quadrados, cada quadrado um agente que nós temos e seus usos, e seus
   usos da VPS por dia"; depois: "eu pedi agentes de IA e não funções, e quero quadrados de cores mais escuras em
   escalas de cinza"). Só o que pensa com modelo: as Nays, o treino, os Hermes e os lembretes. CRM, site, banco,
   publicador e rotinas ficaram de fora. Lê admin/dados/agentes.json (VPS1) e agentes2.json (VPS2), escritos pelo
   cron nay-agentes a cada 5 min. Nada daqui escreve em lugar nenhum.
   ========================================================================== */
(function () {
  "use strict";
  var grade = document.getElementById("ag-grade");
  if (!grade) return;

  var SVG = {
    chat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5h16v11H9l-5 4z"/></svg>',
    casa: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3 2.6 11.1a1 1 0 0 0 .66 1.75H5V20a1 1 0 0 0 1 1h4v-5h4v5h4a1 1 0 0 0 1-1v-7.15h1.74a1 1 0 0 0 .66-1.75Z"/></svg>',
    treino: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 20V10M10 20V4M16 20v-8M22 20H2"/></svg>',
    fluxo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5" cy="6" r="2"/><circle cx="19" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7 6h10M5 8v4a4 4 0 0 0 4 4h1M19 8v4a4 4 0 0 1-4 4h-1"/></svg>',
    relogio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    olho: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
    telegram: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/></svg>'
  };

  /* Cada quadrado: o tom de cinza (--ag = a face, --ag2 = o brilho), o que faz, de onde vem a medida (itens do
     JSON) e os números de hoje (chaves de "hoje"). `vps: 2` = mora na VPS2. */
  var AGENTES = [
    { id: "nay-nova", nome: "Nay nova", onde: "nay-core + worker + enviador", tom: ["#15161a", "#3a3c44"], icone: "chat",
      faz: "Atende os corretores pelo número da Parceria: entende o pedido, busca no catálogo, manda card e fotos, marca visita.",
      itens: ["nay-core", "nay-core-worker", "nay-core-enviador"], hoje: [["core_turnos", "conversas"], ["core_saidas", "mensagens"], ["core_cards", "cards"]] },
    { id: "captacao", nome: "Nay de captação", onde: "serviço nay-captacao · número oficial", tom: ["#1d1f24", "#44474f"], icone: "casa",
      faz: "Fala com os proprietários pelo número oficial: dispara o modelo, pergunta a situação do imóvel, valor, contrato, fotos e indicação.",
      itens: ["nay-captacao"], hoje: [["captacao_disparos", "disparos"], ["captacao_enviadas", "enviadas"], ["captacao_recebidas", "recebidas"]] },
    { id: "grupos", nome: "Nay dos grupos", onde: "serviço nay-grupos", tom: ["#25272d", "#4e5159"], icone: "olho",
      faz: "Lê os grupos de corretores, extrai cada pedido com o modelo e cruza com o nosso catálogo (Captação ativa). Nada sai sozinho.",
      itens: ["nay-grupos"], hoje: [["grupos_lidas", "mensagens lidas"], ["grupos_pedidos", "pedidos"]] },
    { id: "nay-velha", nome: "Nay velha", onde: "fluxos do n8n", tom: ["#2d2f36", "#585b64"], icone: "fluxo",
      faz: "O que ainda não foi para o núcleo: equipe, comandos do Tel, proprietário, escalar, pendências, alarmes.",
      itens: ["n8n-viux-n8n-1"], hoje: [["velha_turnos", "turnos"]] },
    { id: "treino", nome: "Treino da Nay", onde: "nay-core-treino", tom: ["#35373f", "#62656e"], icone: "treino",
      faz: "Refaz conversas reais em sombra para medir a Nay nova sem mandar nada a ninguém; gera o resumo do dia.",
      itens: ["nay-core-treino"], hoje: [] },
    // ---- VPS2. Os Hermes saíram daqui em 13/10: têm os próprios quadrados, ao vivo, com a mesa de cada um
    // (hermes-painel.js, a seção "Hermes" no alto da página).
    { vps: 2, id: "lembretes", nome: "Lembretes", onde: "serviço lembretes + cron de 10 min", tom: ["#35373f", "#62656e"], icone: "relogio",
      faz: "Agente de lembretes pelo WhatsApp: escuta as mensagens, entende com o modelo e envia os lembretes de 10 em 10 minutos.",
      itens: ["lembretes"], hoje: [] }
  ];

  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function mb(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.round(b / 1048576) + " MB"; }
  function haQuanto(s) {
    if (!s) return "—";
    var m = Math.round(s / 60);
    if (m < 60) return m + " min";
    var h = Math.floor(m / 60);
    if (h < 48) return h + " h " + (m % 60) + " min";
    return Math.floor(h / 24) + " dias";
  }
  function num(n) { return Number(n || 0).toLocaleString("pt-BR"); }

  function topo(a, estado, classe) {
    return '<div class="ag-topo"><div class="ag-icone">' + SVG[a.icone] + "</div>" +
      '<div><div class="ag-nome">' + esc(a.nome) + '</div><span class="ag-onde">' + esc(a.onde) + "</span></div>" +
      '<span class="ag-estado' + (classe ? " " + classe : "") + '">' + estado + "</span></div>";
  }

  function cartao(a, d) {
    var itens = a.itens.map(function (id) { return d.itens.find(function (i) { return i.id === id; }); }).filter(Boolean);
    var estilo = ' style="--ag:' + a.tom[0] + ";--ag2:" + a.tom[1] + '"';
    if (!itens.length) {        // a medição desta VPS ainda não chegou: o quadrado fica, sem números
      return '<article class="ag-card"' + estilo + ">" + topo(a, "sem medição", "ag-estado--mudo") + '<p class="ag-faz">' + esc(a.faz) + "</p></article>";
    }
    var ativo = itens.every(function (i) { return i.ativo; });
    var cpu = 0, mem = 0, desde = Infinity, reinicios = 0;
    itens.forEach(function (i) { cpu += i.cpu_s || 0; mem += i.mem || 0; desde = Math.min(desde, i.desde || Infinity); reinicios += i.reinicios || 0; });
    var noAr = desde === Infinity ? 0 : Math.max(60, d.medido_em - desde);
    var cpuDia = cpu * 86400 / noAr;                      // segundos de CPU por dia, média desde que subiu
    var pct = cpu / noAr * 100;                            // % de 1 CPU
    var hoje = a.hoje.map(function (h) {
      var v = (d.hoje || {})[h[0]];
      return v == null ? "" : "<span><b>" + num(v) + "</b> " + esc(h[1]) + "</span>";
    }).join("");
    return '<article class="ag-card' + (ativo ? "" : " ag-card--parado") + '"' + estilo + ">" +
      topo(a, ativo ? "no ar" : "parado", ativo ? "" : "ag-estado--parado") +
      '<p class="ag-faz">' + esc(a.faz) + "</p>" +
      (hoje ? '<div class="ag-hoje" title="hoje, em Manaus">' + hoje + "</div>" : "") +
      '<dl class="ag-uso">' +
        "<div><dt>CPU por dia</dt><dd>" + (cpuDia >= 60 ? (cpuDia / 60).toFixed(1) + " <small>min</small>" : Math.round(cpuDia) + " <small>s</small>") +
          " <small>· " + pct.toFixed(pct < 1 ? 2 : 1).replace(".", ",") + "% CPU</small></dd></div>" +
        "<div><dt>Memória agora</dt><dd>" + mb(mem) + "</dd></div>" +
        "<div><dt>No ar há</dt><dd>" + haQuanto(noAr) + "</dd></div>" +
        "<div><dt>Reinícios</dt><dd>" + reinicios + "</dd></div>" +
        '<div class="ag-barra" title="parte de 1 CPU que este agente ocupa, na média"><i style="width:' + Math.min(100, Math.max(1, pct)).toFixed(1) + '%"></i></div>' +
      "</dl></article>";
  }

  function linhaVps(d) {
    var v = d.vps || {};
    if (!d.medido_em) return "<span><strong>" + esc(v.nome || "VPS") + "</strong></span><span>sem medição ainda</span>";
    return "<span><strong>" + esc(v.nome || "VPS") + "</strong></span>" +
      "<span>" + (v.cpus || "?") + " CPUs · carga " + esc(v.carga || "—") + "</span>" +
      "<span>memória: <strong>" + mb((v.mem_total || 0) - (v.mem_livre || 0)) + "</strong> de " + mb(v.mem_total || 0) + " em uso</span>" +
      (v.disco ? "<span>disco: <strong>" + mb(v.disco.usado) + "</strong> de " + mb(v.disco.total) + "</span>" : "") +
      '<span class="ag-vps__medido">medido ' + new Date(d.medido_em * 1000).toLocaleString("pt-BR", { timeZone: "America/Manaus" }) + " · a cada 5 min</span>";
  }
  function desenhar(d1, d2) {
    var vazio = { medido_em: 0, vps: {}, hoje: {}, itens: [] };
    document.getElementById("ag-vps").innerHTML = linhaVps(d1 || { medido_em: 0, vps: { nome: "VPS1 (srv1894338)" } });
    grade.innerHTML = AGENTES.filter(function (a) { return !a.vps; }).map(function (a) { return cartao(a, d1 || vazio); }).join("");
    document.getElementById("ag-vps2").innerHTML = linhaVps(d2 || { medido_em: 0, vps: { nome: "VPS2 (srv1877774)" } });
    document.getElementById("ag-grade2").innerHTML = AGENTES.filter(function (a) { return a.vps === 2; }).map(function (a) { return cartao(a, d2 || vazio); }).join("");
  }

  function ler(arq) {
    return fetch("dados/" + arq + "?t=" + Math.floor(Date.now() / 60000)).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }
  Promise.all([ler("agentes.json"), ler("agentes2.json")]).then(function (r) {
    if (!r[0] && !r[1]) { grade.innerHTML = '<p class="ag-vazio">A medição ainda não chegou (o cron escreve admin/dados/agentes.json a cada 5 min).</p>'; return; }
    desenhar(r[0], r[1]);
  });
})();
