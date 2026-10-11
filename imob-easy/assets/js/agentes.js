/* ==========================================================================
   Agentes (11/10/2026, Pedro: "uma aba Agentes, lá vai ter vários quadrados, cada quadrado um agente que nós temos
   e seus usos, e seus usos da VPS por dia, cria uma cor para cada"). Lê admin/dados/agentes.json, que o cron
   nay-agentes escreve a cada 5 min na VPS1 (nay-agentes/medir_agentes.sh). Nada daqui escreve em lugar nenhum.
   ========================================================================== */
(function () {
  "use strict";
  var grade = document.getElementById("ag-grade");
  if (!grade) return;

  var SVG = {
    chat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5h16v11H9l-5 4z"/></svg>',
    casa: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3 2.6 11.1a1 1 0 0 0 .66 1.75H5V20a1 1 0 0 0 1 1h4v-5h4v5h4a1 1 0 0 0 1-1v-7.15h1.74a1 1 0 0 0 .66-1.75Z"/></svg>',
    grupo: '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="8" cy="9" r="3"/><circle cx="16.5" cy="9.5" r="2.5"/><path d="M2 19c0-3 2.7-5 6-5s6 2 6 5Zm13.2-4.6c2.6.4 4.8 2.2 4.8 4.6h-4.6c0-1.7-.7-3.3-1.8-4.4a7 7 0 0 1 1.6-.2Z"/></svg>',
    envio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/></svg>',
    treino: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 20V10M10 20V4M16 20v-8M22 20H2"/></svg>',
    fluxo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5" cy="6" r="2"/><circle cx="19" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7 6h10M5 8v4a4 4 0 0 0 4 4h1M19 8v4a4 4 0 0 1-4 4h-1"/></svg>',
    crm: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M9 20V10"/></svg>',
    site: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>',
    banco: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/></svg>',
    relogio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    olho: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>'
  };

  /* Cada quadrado: a cor, o que faz, de onde vem a medida (itens do JSON) e os números de hoje (chaves de "hoje").
     `vps: 2` = mora na VPS2 (srv1877774), medida pelo medir_vps2.sh e trazida em agentes2.json. */
  var AGENTES = [
    { id: "nay-nova", nome: "Nay nova", onde: "núcleo: nay-core + worker", cor: ["#6d28d9", "#c084fc"], icone: "chat",
      faz: "Atende os corretores pelo número da Parceria: entende o pedido, busca no catálogo, manda card e fotos, marca visita.",
      itens: ["nay-core", "nay-core-worker"], hoje: [["core_turnos", "conversas"], ["core_saidas", "mensagens"], ["core_cards", "cards"]] },
    { id: "enviador-nucleo", nome: "Enviador do núcleo", onde: "nay-core-enviador", cor: ["#0ea5e9", "#67e8f9"], icone: "envio",
      faz: "Entrega o que a Nay nova decide: texto, card e fotos, na ordem e no ritmo certos, pela Z-API.",
      itens: ["nay-core-enviador"], hoje: [["core_saidas", "entregas"]] },
    { id: "treino", nome: "Treino da Nay", onde: "nay-core-treino", cor: ["#8b5cf6", "#a5b4fc"], icone: "treino",
      faz: "Refaz conversas reais em sombra para medir a Nay nova sem mandar nada a ninguém; gera o resumo do dia.",
      itens: ["nay-core-treino"], hoje: [] },
    { id: "captacao", nome: "Nay de captação", onde: "serviço nay-captacao · número oficial", cor: ["#059669", "#6ee7b7"], icone: "casa",
      faz: "Fala com os proprietários pelo número oficial: dispara o modelo, pergunta a situação do imóvel, valor, contrato, fotos e indicação.",
      itens: ["nay-captacao"], hoje: [["captacao_disparos", "disparos"], ["captacao_enviadas", "enviadas"], ["captacao_recebidas", "recebidas"]] },
    { id: "grupos", nome: "Nay dos grupos", onde: "serviço nay-grupos", cor: ["#ea580c", "#fdba74"], icone: "olho",
      faz: "Lê os grupos de corretores, extrai cada pedido e cruza com o nosso catálogo (Captação ativa). Nada sai sozinho.",
      itens: ["nay-grupos"], hoje: [["grupos_lidas", "mensagens lidas"], ["grupos_pedidos", "pedidos"]] },
    { id: "publicador", nome: "Publicador", onde: "serviço nay-publicador + grade", cor: ["#db2777", "#f9a8d4"], icone: "grupo",
      faz: "Posta os imóveis nos grupos da Parceria pela agenda, com card, colagem e lista; marca o que já foi.",
      itens: ["nay-publicador"], hoje: [["publicador_posts", "posts"]] },
    { id: "enviador-manual", nome: "Enviador manual", onde: "serviço nay-enviador-manual", cor: ["#0891b2", "#a5f3fc"], icone: "envio",
      faz: "Manda o imóvel que a equipe escolheu (aba Enviar imóvel, botão da Captação ativa), fora do n8n.",
      itens: ["nay-enviador-manual"], hoje: [["velha_envios", "envios"]] },
    { id: "nay-velha", nome: "Nay velha (n8n)", onde: "fluxos do n8n", cor: ["#4f46e5", "#818cf8"], icone: "fluxo",
      faz: "O que ainda não foi para o núcleo: equipe, comandos do Tel, proprietário, escalar, pendências, alarmes.",
      itens: ["n8n-viux-n8n-1"], hoje: [["velha_turnos", "turnos"]] },
    { id: "crm", nome: "CRM", onde: "crm-imobeasy", cor: ["#7c3aed", "#f0abfc"], icone: "crm",
      faz: "Parceria, Oficial, Captação, Grupos e Chat OLX; funis, visitas, follow-ups e o espelho das conversas.",
      itens: ["crm-imobeasy"], hoje: [] },
    { id: "site", nome: "Site e API", onde: "nay-site-web + nay-site-api", cor: ["#2563eb", "#93c5fd"], icone: "site",
      faz: "O site público, o admin e a API que o CRM, o painel e as Nays usam para ler e gravar imóveis.",
      itens: ["nay-site-api", "nay-site-web"], hoje: [["imoveis_ofertaveis", "imóveis ofertáveis"]] },
    { id: "painel", nome: "Painel da Nay", onde: "nay-painel", cor: ["#9333ea", "#d8b4fe"], icone: "treino",
      faz: "As telas da Nay antiga (Locação, Captação, Cérebro, Estrutura).",
      itens: ["nay-painel"], hoje: [] },
    { id: "banco", nome: "Banco de dados", onde: "nay-postgres (naydb)", cor: ["#475569", "#94a3b8"], icone: "banco",
      faz: "Tudo mora aqui: imóveis, conversas, filas, captação, grupos. Backup todo dia às 03:05 e cópia para fora às 03:35.",
      itens: ["nay-postgres"], hoje: [["banco_mb", "MB no banco"]] },
    // ---- VPS2 (11/10: "quero todos das minhas 2 VPS lá")
    { vps: 2, id: "n8n-captacao", nome: "n8n da captação", onde: "n8n-captacao.imobeasy.online", cor: ["#059669", "#a7f3d0"], icone: "fluxo",
      faz: "A entrada da captação: webhook do número oficial e da Z-API, áudio, foto, gravar na fila; o simulador da captação.",
      itens: ["n8n-captacao", "caddy-captacao"], hoje: [] },
    { vps: 2, id: "evolution", nome: "Evolution API", onde: "evolution-api + postgres", cor: ["#16a34a", "#bbf7d0"], icone: "chat",
      faz: "A ponte de WhatsApp da VPS2 (número da captação e dos lembretes), com o banco dela.",
      itens: ["evolution-api", "evolution-postgres"], hoje: [] },
    { vps: 2, id: "portal", nome: "Portal do corretor", onde: "portal-corretor + postgres", cor: ["#2563eb", "#bfdbfe"], icone: "site",
      faz: "O portal dos corretores parceiros, com o banco próprio e o cron de cada minuto.",
      itens: ["portal-corretor", "portal-postgres"], hoje: [] },
    { vps: 2, id: "financas", nome: "Finanças", onde: "financas", cor: ["#ca8a04", "#fde68a"], icone: "banco",
      faz: "O sistema de finanças da imobiliária. Backup todo dia às 23:00.",
      itens: ["financas"], hoje: [] },
    { vps: 2, id: "hermes-corretores", nome: "Hermes · corretores", onde: "serviço hermes-gateway-corretores", cor: ["#dc2626", "#fecaca"], icone: "chat",
      faz: "Agente Hermes no perfil corretores (gateway de mensagens).",
      itens: ["hermes-gateway-corretores"], hoje: [] },
    { vps: 2, id: "hermes-telegram", nome: "Hermes · Telegram", onde: "serviço hermes-gateway-telegram", cor: ["#0284c7", "#bae6fd"], icone: "chat",
      faz: "Agente Hermes no perfil Telegram (gateway de mensagens).",
      itens: ["hermes-gateway-telegram"], hoje: [] },
    { vps: 2, id: "lembretes", nome: "Lembretes", onde: "serviço lembretes + cron de 10 min", cor: ["#ea580c", "#fed7aa"], icone: "relogio",
      faz: "Agente de lembretes pelo WhatsApp: escuta as mensagens e envia os lembretes de 10 em 10 minutos.",
      itens: ["lembretes"], hoje: [] }
  ];

  var ROTINAS2 = [
    ["lembretes_envio", "Envio dos lembretes", "a cada 10 min", 1],
    ["lembrete_groq", "Lembrete (Groq)", "todo dia 09:00", 26],
    ["backup_financas", "Backup das finanças", "todo dia 23:00", 26],
    ["backups_vps1", "Cópia dos backups da VPS1", "todo dia (vindo da VPS1)", 26]
  ];

  var ROTINAS = [
    ["catalogo", "Catálogo do site antigo", "todo dia 05:17", 26],
    ["ficha", "Ficha dos anúncios", "a cada 3 h", 4],
    ["backup", "Backup do banco", "todo dia 03:05", 26],
    ["backup_fora", "Backup para fora", "todo dia 03:35", 26],
    ["geocodificar", "Imóvel novo no mapa", "de hora em hora", 2],
    ["etapas_crm", "Conferência do CRM", "a cada minuto", 0.2],
    ["visitas", "Detectar visitas", "a cada minuto", 0.2],
    ["pendencias", "Ciclo de pendências", "a cada minuto", 0.2],
    ["grade", "Grade do publicador", "a cada minuto", 0.2],
    ["avisar_saidas", "Avisos de saída", "a cada minuto", 0.2],
    ["vigia", "Vigia do WhatsApp", "a cada minuto", 0.2]
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

  function cartao(a, d) {
    var itens = a.itens.map(function (id) { return d.itens.find(function (i) { return i.id === id; }); }).filter(Boolean);
    var ativo = itens.length > 0 && itens.every(function (i) { return i.ativo; });
    var cpu = 0, mem = 0, desde = Infinity, reinicios = 0;
    itens.forEach(function (i) { cpu += i.cpu_s || 0; mem += i.mem || 0; desde = Math.min(desde, i.desde || Infinity); reinicios += i.reinicios || 0; });
    var noAr = desde === Infinity ? 0 : Math.max(60, d.medido_em - desde);
    var cpuDia = cpu * 86400 / noAr;                      // segundos de CPU por dia, média desde que subiu
    var pct = cpu / noAr * 100;                            // % de 1 CPU
    var hoje = a.hoje.map(function (h) {
      var v = (d.hoje || {})[h[0]];
      return v == null ? "" : "<span><b>" + num(v) + "</b> " + esc(h[1]) + "</span>";
    }).join("");
    return '<article class="ag-card' + (ativo ? "" : " ag-card--parado") + '" style="--ag:' + a.cor[0] + ";--ag2:" + a.cor[1] + '">' +
      '<div class="ag-topo"><div class="ag-icone">' + SVG[a.icone] + "</div>" +
        '<div><div class="ag-nome">' + esc(a.nome) + '</div><span class="ag-onde">' + esc(a.onde) + "</span></div>" +
        '<span class="ag-estado">' + (ativo ? "no ar" : "parado") + "</span></div>" +
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

  function cartaoRotinas(d, lista) {
    var linhas = (lista || ROTINAS).map(function (r) {
      var it = d.itens.find(function (i) { return i.id === r[0]; });
      var ha = it && it.ultima ? d.medido_em - it.ultima : null;
      var atrasada = ha != null && ha > r[3] * 3600;
      return '<li class="' + (atrasada ? "atrasada" : "") + '"><span>' + esc(r[1]) + ' <small style="color:var(--texto-fraco)">· ' + esc(r[2]) + "</small></span>" +
        "<span>" + (ha == null ? "sem log" : "há " + haQuanto(ha)) + "</span></li>";
    }).join("");
    return '<article class="ag-card" style="--ag:#b45309;--ag2:#fcd34d;grid-column:span 2">' +
      '<div class="ag-topo"><div class="ag-icone">' + SVG.relogio + '</div><div><div class="ag-nome">Rotinas do servidor</div>' +
      '<span class="ag-onde">cron do root e /etc/cron.d</span></div><span class="ag-estado">agenda</span></div>' +
      '<p class="ag-faz">O que roda sozinho, de tempos em tempos. "Há quanto" é a última vez que o log de cada uma mexeu; em vermelho, passou do prazo.</p>' +
      '<ul class="ag-rotinas">' + linhas + "</ul></article>";
  }

  function linhaVps(d) {
    var v = d.vps || {};
    return
      "<span><strong>" + esc(v.nome || "VPS") + "</strong></span>" +
      "<span>" + (v.cpus || "?") + " CPUs · carga " + esc(v.carga || "—") + "</span>" +
      "<span>memória: <strong>" + mb((v.mem_total || 0) - (v.mem_livre || 0)) + "</strong> de " + mb(v.mem_total || 0) + " em uso</span>" +
      (v.disco ? "<span>disco: <strong>" + mb(v.disco.usado) + "</strong> de " + mb(v.disco.total) + "</span>" : "") +
      '<span class="ag-vps__medido">medido ' + new Date(d.medido_em * 1000).toLocaleString("pt-BR", { timeZone: "America/Manaus" }) + " · a cada 5 min</span>";
  }
  function desenhar(d1, d2) {
    var vazio = { medido_em: Math.floor(Date.now() / 1000), vps: {}, hoje: {}, itens: [] };
    document.getElementById("ag-vps").innerHTML = linhaVps(d1 || { medido_em: 0, vps: { nome: "VPS1 (srv1894338)" } });
    grade.innerHTML = AGENTES.filter(function (a) { return !a.vps; }).map(function (a) { return cartao(a, d1 || vazio); }).join("") + cartaoRotinas(d1 || vazio);
    document.getElementById("ag-vps2").innerHTML = linhaVps(d2 || { medido_em: 0, vps: { nome: "VPS2 (srv1877774) · sem medição ainda" } });
    document.getElementById("ag-grade2").innerHTML =
      AGENTES.filter(function (a) { return a.vps === 2; }).map(function (a) { return cartao(a, d2 || vazio); }).join("") + cartaoRotinas(d2 || vazio, ROTINAS2);
  }

  function ler(arq) {
    return fetch("dados/" + arq + "?t=" + Math.floor(Date.now() / 60000)).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }
  Promise.all([ler("agentes.json"), ler("agentes2.json")]).then(function (r) {
    if (!r[0] && !r[1]) { grade.innerHTML = '<p class="ag-vazio">A medição ainda não chegou (o cron escreve admin/dados/agentes.json a cada 5 min).</p>'; return; }
    desenhar(r[0], r[1]);
  });
})();
