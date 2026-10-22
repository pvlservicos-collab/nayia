/* ==========================================================================
   Imob Easy — Modelos de IA (22/10/2026, 470)
   Pedro: "uma conexão grande de nós, mostrando onde estão todos os modelos de IA e dando a opção de substituirmos esses
   modelos por lá, e um contador de quanto estamos gastando em cada modelo, por nó de modelo ... navegável com o mouse
   dentro, tipo eu clico com o botão direito e arrasto ... e uma sidebar na esquerda com os modelos como atalho e vista
   rápida".
   O DESENHO (quem fala com quem) mora aqui, em ECOSSISTEMA; os GASTOS vêm de /admin/api/modelos (site_ia_modelos):
   por nó, por período. Trocar o modelo: /admin/api/modelos/trocar, só nos nós que leem o modelo do banco (trocavel).
   ========================================================================== */
(function () {
  "use strict";

  function $(id) { return document.getElementById(id); }
  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }

  /* ---- os símbolos das empresas (só nos nós de modelo) ---- */
  var LOGO = {
    openai: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><g>' +
      [0, 60, 120].map(function (a) { return '<ellipse cx="12" cy="12" rx="3.4" ry="8.4" transform="rotate(' + a + ' 12 12)"/>'; }).join("") +
      '</g></svg>',
    anthropic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round">' +
      [0, 45, 90, 135].map(function (a) { return '<path d="M12 3.5v17" transform="rotate(' + a + ' 12 12)"/>'; }).join("") + '</svg>',
    deepseek: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M2.5 13.2c1.6-4.6 6.6-6.9 11.3-5.6 1.9.5 3.4 1.8 4.9 1.6.8-.1 1.7-.6 2.8-1.6-.3 2.9-1.9 4.6-4.2 5-.7 3.2-3.9 5.7-8 5.3-3.4-.3-5.9-2.1-6.8-4.7Z"/><circle cx="8.3" cy="12.4" r="1" fill="#fff"/></svg>',
    typesafe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M14.5 4.5v10a4 4 0 0 1-7.5 2"/></svg>'
  };
  function logo(p) { return '<span class="md-logo md-logo-' + p + '" aria-hidden="true">' + (LOGO[p] || "") + "</span>"; }

  /* ---- o ecossistema: colunas x; linhas y. Cada modelo é um nó próprio (o mesmo modelo em dois lugares = dois nós) ---- */
  // duas faixas lado a lado (a Nay nova, a captação e a OLX | a Nay velha, o CRM e os agentes): o mapa fica largo, não alto
  var X = { canal: 0, servico: 330, funcao: 680, modelo: 1040 }, FAIXA = [0, 1460];
  var PASSO = 118, Y0 = 70;
  function y(linha) { return Y0 + linha * PASSO; }
  function x(col, f) { return X[col] + FAIXA[f || 0]; }

  var COMO_CORE = "Mora no núcleo da Nay nova (nay-core, config/modelos.yaml). A troca é um deploy do núcleo: peça no chat que eu faço.";
  var COMO_N8N = "Mora no fluxo do n8n (Nay velha). A troca é import de fluxo, só de madrugada, pelo procedimento do espelho (scripts/madrugada/modelo_madrugada.sh).";

  var MODELOS = [
    { no: "core.classificador", modelo: "gpt-6-luna", prov: "openai", servico: "s.core", funcao: "Entender a mensagem do corretor", linha: 0,
      faz: "Lê cada mensagem de corretor e diz a intenção, a finalidade, o tipo, o bairro, o valor e os códigos citados. É a primeira coisa que roda em todo turno da Nay nova.",
      como: COMO_CORE },
    { no: "core.reserva", modelo: "deepseek-v4.1-flash", prov: "deepseek", servico: "s.core", funcao: "Reserva quando a Luna falha", linha: 1, de: ["f.core.classificador", "f.core.duvida"],
      faz: "Só entra quando a Luna cai ou passa do tempo (8 s): o mesmo prompt pela OpenRouter, raciocínio desligado. Se a reserva também cair, a regex classifica.",
      como: COMO_CORE },
    { no: "core.jev", modelo: "jev-1.13", prov: "typesafe", servico: "s.core", funcao: "Conferir se o imóvel bate (veto)", linha: 2,
      faz: "O portão de coerência: antes de mandar um imóvel que não veio pelo código, pergunta se ele responde ao pedido do corretor. Abaixo do limiar vira \"É este imóvel?\".",
      como: COMO_CORE },
    { no: "core.duvida", modelo: "gpt-6-luna", prov: "openai", servico: "s.core", funcao: "Responder dúvida do imóvel", linha: 3,
      faz: "Responde perguntas sobre o imóvel (taxa, IPTU, andar, pet...) só com o que a ficha diz; o que a ficha não tem vira pendência para o Tel.",
      como: COMO_CORE },
    { no: "core.instrucao", modelo: "gpt-6-luna", prov: "openai", servico: "s.core", funcao: "Ler a instrução do Tel (CRM)", linha: 4,
      faz: "Traduz a instrução que a equipe escreve no CRM num plano: um pedido de imóvel, um recado na voz da Nay, ou só liberar a conversa.",
      como: COMO_CORE },
    { no: "core.transcricao", modelo: "gpt-4o-mini-transcribe", prov: "openai", servico: "s.core", funcao: "Transcrever áudio do corretor", linha: 5,
      faz: "Transforma o áudio do corretor em texto antes do classificador (US$ 0,003 por minuto).",
      como: COMO_CORE },
    { no: "captacao.atender", modelo: "gpt-6-luna", prov: "openai", servico: "s.captacao", funcao: "Conversar com o proprietário", linha: 6.4, trocavel: true,
      faz: "A Nay de captação no número oficial: conversa com o dono depois do disparo, atualiza a situação do imóvel, pergunta do contrato, cadastra o imóvel novo e a indicação." },
    { no: "olx.chat", modelo: "gpt-6-luna", prov: "openai", servico: "s.olx", funcao: "Responder no chat da OLX", linha: 7.8, trocavel: true,
      faz: "Responde quem escreve nos nossos anúncios da OLX e chama a pessoa para o WhatsApp." },
    { no: "olx.whatsapp", modelo: "gpt-6-luna", prov: "openai", servico: "s.olx", funcao: "Atender o lead no WhatsApp", linha: 8.8, trocavel: true,
      faz: "A Nay do WhatsApp dos leads (92 8595-6408): segue o roteiro (valor, bairros, quartos, mobília), manda os imóveis e marca a visita." },
    { no: "olx.parceiro", modelo: "gpt-6-luna", prov: "openai", servico: "s.olx", funcao: "Ler a resposta do parceiro", linha: 9.8, trocavel: true,
      faz: "Lê a resposta do corretor parceiro à pergunta \"o imóvel do seu anúncio ainda está disponível?\" (sim, não ou dúvida)." },
    { no: "n8n.secretaria", modelo: "gpt-6-luna", prov: "openai", servico: "s.n8n", funcao: "Secretária (triagem do turno)", f: 1, linha: 0,
      faz: "Na Nay velha, decide para qual agente vai o turno. Roda em todo turno que a Nay velha atende.", como: COMO_N8N, semMedicao: true },
    { no: "n8n.corretor", modelo: "gpt-6-luna", prov: "openai", servico: "s.n8n", funcao: "Agente do corretor", f: 1, linha: 1,
      faz: "O agente da Nay velha que atende o corretor (hoje a Nay nova atende quase tudo).", como: COMO_N8N, semMedicao: true },
    { no: "n8n.proprietario", modelo: "gpt-6-luna", prov: "openai", servico: "s.n8n", funcao: "Agente do proprietário", f: 1, linha: 2,
      faz: "O agente da Nay velha que fala com o proprietário na visita.", como: COMO_N8N, semMedicao: true },
    { no: "n8n.fernando", modelo: "gpt-6-luna", prov: "openai", servico: "s.n8n", funcao: "Agente do acompanhante", f: 1, linha: 3,
      faz: "O agente da Nay velha que fala com o acompanhante da visita (o nome no fluxo ainda é Fernando).", como: COMO_N8N, semMedicao: true },
    { no: "n8n.imagem", modelo: "gpt-4o-mini", prov: "openai", servico: "s.n8n", funcao: "Ler imagem", f: 1, linha: 4,
      faz: "Descreve a foto ou o print que chega na conversa (nó Detectar imagem do fluxo NAI).", como: COMO_N8N, semMedicao: true },
    { no: "n8n.transcricao", modelo: "gpt-4o-mini-transcribe", prov: "openai", servico: "s.n8n", funcao: "Transcrever áudio", f: 1, linha: 5,
      faz: "Transforma o áudio em texto na Nay velha.", como: COMO_N8N, semMedicao: true },
    { no: "n8n.recebe", modelo: "gpt-6-luna", prov: "openai", servico: "s.n8n", funcao: "Agente do \"recebe mensagem\"", f: 1, linha: 6,
      faz: "O AI Agent do fluxo \"Nay- recebe mensagem\".", como: COMO_N8N, semMedicao: true },
    { no: "crm.transcricao", modelo: "gpt-4o-transcribe", prov: "openai", servico: "s.crm", funcao: "Transcrever áudio das conversas", f: 1, linha: 7.6,
      faz: "Transcreve o áudio que chega no CRM (a conversa mostra o texto e a Nay de captação lê).",
      como: "Mora no CRM (src/lib/transcricao.ts). A troca é um deploy do CRM: peça no chat.", semMedicao: true },
    { no: "agentes.claude", modelo: "Claude Sonnet", prov: "anthropic", servico: "s.agentes", funcao: "Chats de projeto (Visitas, Métricas...)", f: 1, linha: 9,
      faz: "Os chats de projeto do agentes.imobeasy.online: Visitas, Métricas, Estratégia, Financeiro, Respostas e a revisão da Nay. Leem o banco e o código das duas VPS.",
      como: "Claude Code com a assinatura da conta: não há custo por token. Cada projeto escolhe o modelo no seu projeto.json.", assinatura: true }
  ];

  var SERVICOS = [
    { id: "s.core", rotulo: "Nay nova", sub: "nay-core · atende os corretores", linha: 2.5 },
    { id: "s.captacao", rotulo: "Nay de captação", sub: "nay-captacao · número oficial", linha: 6.4 },
    { id: "s.olx", rotulo: "Nay da OLX", sub: "nay-olx · chat e WhatsApp dos leads", linha: 8.8 },
    { id: "s.n8n", rotulo: "Nay velha", sub: "n8n · NAI atendimento", f: 1, linha: 3 },
    { id: "s.crm", rotulo: "CRM", sub: "crm.imobeasy.online", f: 1, linha: 7.6 },
    { id: "s.agentes", rotulo: "Agente Claude", sub: "VPS2 · agentes.imobeasy.online", f: 1, linha: 9 }
  ];
  var CANAIS = [
    { id: "c.parceria", rotulo: "WhatsApp Parceria", sub: "92 9445-3618 · Z-API", linha: 1.4, para: ["s.core"] },
    { id: "c.instrucao", rotulo: "Instrução da equipe", sub: "o que o Tel escreve no CRM", linha: 4.4, para: ["s.core"] },
    { id: "c.parceria2", rotulo: "WhatsApp Parceria", sub: "92 9445-3618 · conversas antigas", f: 1, linha: 3, para: ["s.n8n"] },
    { id: "c.grupos", rotulo: "Grupos de corretores", sub: "pedidos e imóveis", linha: 3.4, para: ["s.core"] },
    { id: "c.oficial", rotulo: "WhatsApp oficial", sub: "92 8456-0874 · Meta", linha: 6.4, para: ["s.captacao"] },
    { id: "c.olx", rotulo: "Chat da OLX", sub: "anúncios na OLX", linha: 7.8, para: ["s.olx"] },
    { id: "c.leads", rotulo: "WhatsApp dos leads", sub: "92 8595-6408 · Z-API", linha: 9.8, para: ["s.olx"] },
    { id: "c.equipe", rotulo: "Equipe no CRM", sub: "Tel, Rayssa, Pedro", f: 1, linha: 7.6, para: ["s.crm"] },
    { id: "c.painel", rotulo: "Painel dos agentes", sub: "agentes.imobeasy.online", f: 1, linha: 9, para: ["s.agentes"] }
  ];
  var DADOS = [
    { id: "d.naydb", rotulo: "Banco naydb", sub: "imóveis, conversas, visitas, ia_uso", x: 1270, linha: 11.4,
      de: ["s.core", "s.captacao", "s.olx", "s.n8n", "s.agentes", "s.crm"] },
    { id: "d.crmdb", rotulo: "Banco crmdb", sub: "leads e mensagens do CRM", x: 2140, linha: 11.4, de: ["s.crm"] }
  ];

  /* ---- os nós montados ---- */
  var NOS = {}, LIGACOES = [];
  function no(id, tipo, x, yy, html, extra) { NOS[id] = Object.assign({ id: id, tipo: tipo, x: x, y: yy, html: html }, extra || {}); }
  function liga(de, para, modelo) { LIGACOES.push({ de: de, para: para, modelo: !!modelo }); }
  [0, 1].forEach(function (f) {
    ["Canais", "Serviços", "Funções", "Modelos de IA"].forEach(function (t, i) {
      no("col." + f + "." + i, "coluna", x(["canal", "servico", "funcao", "modelo"][i], f), 14, esc(t));
    });
  });
  CANAIS.forEach(function (c) {
    no(c.id, "comum", x("canal", c.f), y(c.linha), esc(c.rotulo) + "<small>" + esc(c.sub) + "</small>");
    c.para.forEach(function (s) { liga(c.id, s); });
  });
  SERVICOS.forEach(function (s) { no(s.id, "comum", x("servico", s.f), y(s.linha), esc(s.rotulo) + "<small>" + esc(s.sub) + "</small>"); });
  MODELOS.forEach(function (m) {
    var f = "f." + m.no;
    if (!m.de) {
      no(f, "comum", x("funcao", m.f), y(m.linha), esc(m.funcao));
      liga(m.servico, f);
    }
    no(m.no, "modelo", x("modelo", m.f), y(m.linha), "", { m: m });
    (m.de || [f]).forEach(function (d) { liga(d, m.no, true); });
  });
  DADOS.forEach(function (d) {
    no(d.id, "dado", d.x, y(d.linha), esc(d.rotulo) + "<small>" + esc(d.sub) + "</small>");
    d.de.forEach(function (s) { liga(s, d.id); });
  });

  /* ---- dados da API ---- */
  var dados = { nos: {}, totais: {}, escolhidos: {}, precos: {}, serie: [] };
  var PERIODOS = [["hoje", "Hoje"], ["ontem", "Ontem"], ["d7", "7 dias"], ["d30", "30 dias"], ["mes", "Este mês"]];
  var periodo = "d7";
  try { periodo = localStorage.getItem("md-periodo") || "d7"; } catch (e) { /* sem armazenamento */ }
  var selecionado = null;

  function dinheiro(v) {
    var n = Number(v || 0);
    var casas = n === 0 ? 2 : n < 1 ? 4 : 2;
    return "US$ " + n.toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });
  }
  function inteiro(v) { return Number(v || 0).toLocaleString("pt-BR"); }
  function doNo(id) { return dados.nos[id] || { gasto: {}, chamadas: {} }; }
  function modeloAtual(m) { return (dados.escolhidos[m.no] && dados.escolhidos[m.no].modelo) || m.modelo; }
  function nomePeriodo() { return (PERIODOS.filter(function (p) { return p[0] === periodo; })[0] || ["", ""])[1].toLowerCase(); }

  function contador(m) {
    var d = doNo(m.no), ch = (d.chamadas || {})[periodo] || 0;
    if (m.assinatura) return '<div class="md-contador sem">assinatura<small>sem custo por token</small></div>';
    if (m.semMedicao) return '<div class="md-contador sem">sem medição<small>' + inteiro(ch) + " chamada" + (ch === 1 ? "" : "s") + " · " + nomePeriodo() + "</small></div>";
    return '<div class="md-contador">' + dinheiro((d.gasto || {})[periodo]) + "<small>" + inteiro(ch) + " chamada" + (ch === 1 ? "" : "s") + " · " + nomePeriodo() + "</small></div>";
  }

  /* ---- desenho ---- */
  var mundo = $("md-mundo"), camadaNos = $("md-nos"), linhas = $("md-linhas"), palco = $("md-palco");

  function desenharNos() {
    camadaNos.innerHTML = Object.keys(NOS).map(function (id) {
      var n = NOS[id], estilo = "left:" + n.x + "px;top:" + n.y + "px";
      if (n.tipo === "modelo") {
        var m = n.m, ch = (doNo(m.no).chamadas || {})[periodo] || 0;
        return '<div class="md-no modelo' + (ch || m.assinatura ? "" : " parado") + (selecionado === m.no ? " ativo" : "") +
          '" data-no="' + esc(id) + '" data-modelo="' + esc(m.no) + '" style="' + estilo + '" role="button" tabindex="0" aria-label="' +
          esc(modeloAtual(m) + ", " + m.funcao) + '">' + contador(m) + logo(m.prov) +
          '<span><span class="md-no-nome">' + esc(modeloAtual(m)) + '</span><span class="md-no-funcao">' + esc(m.funcao) + "</span></span></div>";
      }
      return '<div class="md-no ' + (n.tipo === "coluna" ? "coluna" : n.tipo === "dado" ? "dado" : "") + '" data-no="' + esc(id) + '" style="' + estilo + '">' + n.html + "</div>";
    }).join("");
    desenharLinhas();
    acender();
  }

  function caixa(id) {
    var el = camadaNos.querySelector('[data-no="' + id.replace(/"/g, "") + '"]');
    var n = NOS[id];
    return { x: n.x, y: n.y, w: el ? el.offsetWidth : 210, h: el ? el.offsetHeight : 40 };
  }
  function desenharLinhas() {
    var maxX = 0, maxY = 0;
    var paths = LIGACOES.map(function (l, i) {
      var a = caixa(l.de), b = caixa(l.para);
      var x1 = a.x + a.w, y1 = a.y + a.h / 2, x2 = b.x, y2 = b.y + b.h / 2;
      if (l.para.indexOf("d.") === 0) { x1 = a.x + a.w / 2; y1 = a.y + a.h; x2 = b.x + b.w / 2; y2 = b.y; }
      maxX = Math.max(maxX, b.x + b.w, a.x + a.w); maxY = Math.max(maxY, b.y + b.h, a.y + a.h);
      var d = l.para.indexOf("d.") === 0
        ? "M" + x1 + "," + y1 + " C" + x1 + "," + (y1 + 80) + " " + x2 + "," + (y2 - 80) + " " + x2 + "," + y2
        : "M" + x1 + "," + y1 + " C" + (x1 + 70) + "," + y1 + " " + (x2 - 70) + "," + y2 + " " + x2 + "," + y2;
      return '<path data-l="' + i + '" class="' + (l.modelo ? "modelo" : "") + '" d="' + d + '"/>';
    });
    linhas.setAttribute("width", maxX + 40); linhas.setAttribute("height", maxY + 40);
    linhas.innerHTML = paths.join("");
    limites = { w: maxX + 40, h: maxY + 40 };
  }

  /* o caminho do modelo escolhido: o canal, o serviço, a função e ele mesmo acendem; o resto esmaece */
  function caminhoDe(idModelo) {
    var aceso = {}, fila = [idModelo];
    aceso[idModelo] = true;
    while (fila.length) {
      var atual = fila.shift();
      LIGACOES.forEach(function (l) { if (l.para === atual && !aceso[l.de]) { aceso[l.de] = true; fila.push(l.de); } });
    }
    return aceso;
  }
  function acender() {
    var aceso = selecionado ? caminhoDe(selecionado) : null;
    camadaNos.querySelectorAll(".md-no").forEach(function (el) {
      var id = el.getAttribute("data-no");
      if (NOS[id] && NOS[id].tipo === "coluna") return;
      el.classList.toggle("esmaecido", !!aceso && !aceso[id]);
      el.classList.toggle("aceso", !!aceso && !!aceso[id] && NOS[id].tipo !== "modelo");
      el.classList.toggle("ativo", id === selecionado);
    });
    linhas.querySelectorAll("path").forEach(function (p) {
      var l = LIGACOES[Number(p.getAttribute("data-l"))];
      p.classList.toggle("acesa", !!(aceso && aceso[l.de] && aceso[l.para]));
    });
  }

  /* ---- o painel de gastos ---- */
  function desenharGastos() {
    $("md-periodos").innerHTML = PERIODOS.map(function (p) {
      return '<button type="button" class="md-periodo" role="tab" data-periodo="' + p[0] + '" aria-selected="' + (p[0] === periodo) + '">' +
        "<span>" + p[1] + "</span><b>" + dinheiro((dados.totais || {})[p[0]]) + "</b></button>";
    }).join("");
    var s = dados.serie || [], max = Math.max.apply(null, s.map(function (d) { return Number(d.custo) || 0; }).concat([0.000001]));
    var w = 280, h = 46, passo = s.length > 1 ? w / (s.length - 1) : w;
    var pts = s.map(function (d, i) { return (i * passo).toFixed(1) + "," + (h - 4 - (Number(d.custo) || 0) / max * (h - 10)).toFixed(1); });
    $("md-serie").innerHTML = s.length ? '<svg viewBox="0 0 ' + w + " " + h + '" preserveAspectRatio="none">' +
      '<polyline points="0,' + h + " " + pts.join(" ") + " " + w + "," + h + '" fill="#efe8fd" stroke="none"/>' +
      '<polyline points="' + pts.join(" ") + '" fill="none" stroke="#6d28d9" stroke-width="1.8" vector-effect="non-scaling-stroke"/></svg>' +
      "<small>gasto por dia · últimos 30 dias</small>" : "";
    $("md-atualizado").textContent = "Gasto medido em dólar (US$) · atualizado às " +
      (dados.gerado_em ? dados.gerado_em.slice(11, 16) : "--:--") + " · a Nay velha, o CRM e os agentes não medem tokens";
  }

  /* ---- a barra dos modelos (atalho e vista rápida) ---- */
  var GRUPOS = [["s.core", "Nay nova"], ["s.captacao", "Nay de captação"], ["s.olx", "Nay da OLX"], ["s.n8n", "Nay velha (n8n)"], ["s.crm", "CRM"], ["s.agentes", "Agente Claude"]];
  function valorCurto(m) {
    var d = doNo(m.no);
    if (m.assinatura) return "assinatura";
    if (m.semMedicao) return inteiro((d.chamadas || {})[periodo]) + " cham.";
    return dinheiro((d.gasto || {})[periodo]);
  }
  function desenharLista() {
    $("md-lista").innerHTML = GRUPOS.map(function (g) {
      var itens = MODELOS.filter(function (m) { return m.servico === g[0]; });
      return '<p class="md-grupo">' + esc(g[1]) + "</p>" + itens.map(function (m) {
        return '<button type="button" class="md-item' + (selecionado === m.no ? " ativo" : "") + '" data-modelo="' + esc(m.no) + '">' + logo(m.prov) +
          '<span><span class="md-item-nome">' + esc(modeloAtual(m)) + '</span><span class="md-item-onde">' + esc(m.funcao) + "</span></span>" +
          '<span class="md-item-valor">' + esc(valorCurto(m)) + "</span></button>";
      }).join("");
    }).join("");
  }

  function desenharDetalhe() {
    var caixaDet = $("md-detalhe");
    var m = MODELOS.filter(function (x) { return x.no === selecionado; })[0];
    if (!m) { caixaDet.hidden = true; return; }
    var d = doNo(m.no), s = SERVICOS.filter(function (x) { return x.id === m.servico; })[0];
    var canais = CANAIS.filter(function (c) { return c.para.indexOf(m.servico) >= 0; }).map(function (c) { return c.rotulo; });
    var preco = (dados.precos || {})[modeloAtual(m)];
    var linhasTab = PERIODOS.map(function (p) {
      var ch = (d.chamadas || {})[p[0]] || 0;
      return '<tr class="' + (p[0] === periodo ? "sel" : "") + '"><td>' + p[1] + " · " + inteiro(ch) + " chamada" + (ch === 1 ? "" : "s") + "</td><td>" +
        (m.assinatura ? "assinatura" : m.semMedicao ? "—" : dinheiro((d.gasto || {})[p[0]])) + "</td></tr>";
    }).join("");
    var escolhido = dados.escolhidos[m.no];
    caixaDet.innerHTML =
      '<button type="button" class="md-voltar" data-voltar>← Todos os modelos</button>' +
      '<div class="md-det-topo">' + logo(m.prov) + "<div><h2>" + esc(modeloAtual(m)) + "</h2><p>" + esc(m.funcao) + "</p></div></div>" +
      '<div class="md-det-sec"><h3>Onde ele está</h3><div class="md-caminho">' +
        '<div class="md-passo"><i></i><div>' + esc(canais.join(" · ") || "—") + "<small>de onde chega a conversa</small></div></div>" +
        '<div class="md-passo"><i></i><div>' + esc(s ? s.rotulo : "") + "<small>" + esc(s ? s.sub : "") + "</small></div></div>" +
        '<div class="md-passo"><i></i><div>' + esc(m.funcao) + "<small>a função</small></div></div>" +
        '<div class="md-passo"><i></i><div>' + esc(modeloAtual(m)) + "<small>o modelo de IA</small></div></div>" +
      "</div></div>" +
      '<div class="md-det-sec"><h3>O que ele faz</h3><p class="md-det-texto">' + esc(m.faz) + "</p></div>" +
      '<div class="md-det-sec"><h3>Gastos</h3><table class="md-tabela">' + linhasTab + "</table>" +
        (preco && preco.entrada != null ? '<p class="md-aviso">Preço por milhão de tokens: entrada ' + dinheiro(preco.entrada) + ", em cache " + dinheiro(preco.entrada_cache) +
          ", saída " + dinheiro(preco.saida) + ".</p>" : preco && preco.por_minuto ? '<p class="md-aviso">Preço: ' + dinheiro(preco.por_minuto) + " por minuto de áudio.</p>" : "") +
        (m.semMedicao ? '<p class="md-aviso">Aqui não há registro de tokens: as chamadas são contadas pelos turnos que passaram por este nó.</p>' : "") +
        (!m.semMedicao && !m.assinatura && m.no.indexOf("core.") !== 0 ? '<p class="md-aviso">A medição deste nó começou em 22/10/2026.</p>' : "") +
      "</div>" +
      '<div class="md-det-sec"><h3>Trocar o modelo</h3>' +
        (m.trocavel
          ? '<form class="md-trocar" data-trocar="' + esc(m.no) + '"><input name="modelo" list="md-sugestoes" value="' + esc(modeloAtual(m)) +
            '" aria-label="Nome do modelo" autocomplete="off" spellcheck="false"><button type="submit">Trocar</button></form>' +
            '<datalist id="md-sugestoes"><option value="gpt-6-luna"><option value="gpt-6-sol"><option value="gpt-5.6-luna"><option value="gpt-5.6-sol"></datalist>' +
            '<p class="md-aviso">Use o nome exato da API da OpenAI. O serviço usa o modelo novo na próxima chamada (até 1 minuto).' +
            (escolhido && escolhido.por ? " Última troca: " + esc(escolhido.por) + " em " + esc(escolhido.em) + "." : "") + "</p>"
          : '<p class="md-aviso">' + esc(m.como || "") + "</p>") +
      "</div>";
    caixaDet.hidden = false;
  }

  function selecionar(idModelo, centrar) {
    selecionado = idModelo;
    desenharLista(); desenharDetalhe(); acender();
    if (idModelo && centrar) focar(idModelo);
  }

  /* ---- a câmera: arrastar (botão direito em qualquer lugar, esquerdo no fundo), rodinha, pinça ---- */
  var cam = { x: 24, y: 44, k: 0.78 }, limites = { w: 1400, h: 2800 };
  function aplicar(suave) {
    mundo.style.transition = suave ? "transform .35s ease" : "none";
    mundo.style.transform = "translate(" + cam.x + "px," + cam.y + "px) scale(" + cam.k + ")";
  }
  function zoomEm(px, py, fator) {
    var k = Math.min(1.8, Math.max(0.25, cam.k * fator));
    cam.x = px - (px - cam.x) * (k / cam.k); cam.y = py - (py - cam.y) * (k / cam.k); cam.k = k;
    aplicar(false);
  }
  function ajustar() {
    var r = palco.getBoundingClientRect();
    var k = Math.min((r.width - 60) / limites.w, (r.height - 60) / limites.h, 1);
    cam.k = Math.max(0.25, k); cam.x = (r.width - limites.w * cam.k) / 2; cam.y = 44;
    aplicar(true);
  }
  function focar(id) {
    var r = palco.getBoundingClientRect(), c = caixa(id);
    cam.k = Math.max(cam.k, 0.85);
    cam.x = r.width / 2 - (c.x + c.w / 2) * cam.k; cam.y = r.height / 2 - (c.y + c.h / 2) * cam.k;
    aplicar(true);
  }

  var arrasto = null, toques = {};
  palco.addEventListener("contextmenu", function (e) { e.preventDefault(); });
  palco.addEventListener("pointerdown", function (e) {
    if (e.pointerType === "touch") {
      toques[e.pointerId] = { x: e.clientX, y: e.clientY };
    }
    var noFundo = !e.target.closest(".md-no.modelo") && !e.target.closest(".md-controles");
    if (e.button === 2 || (e.button === 0 && noFundo) || e.pointerType === "touch") {
      arrasto = { x: e.clientX, y: e.clientY, cx: cam.x, cy: cam.y, moveu: false };
      palco.setPointerCapture(e.pointerId);
      palco.classList.add("arrastando");
    }
  });
  palco.addEventListener("pointermove", function (e) {
    if (e.pointerType === "touch" && toques[e.pointerId]) {
      var antes = Object.keys(toques).map(function (k) { return toques[k]; });
      toques[e.pointerId] = { x: e.clientX, y: e.clientY };
      var ids = Object.keys(toques);
      if (ids.length === 2 && antes.length === 2) {          // pinça
        var a = toques[ids[0]], b = toques[ids[1]];
        var d0 = Math.hypot(antes[0].x - antes[1].x, antes[0].y - antes[1].y), d1 = Math.hypot(a.x - b.x, a.y - b.y);
        var r = palco.getBoundingClientRect();
        if (d0 > 0) zoomEm((a.x + b.x) / 2 - r.left, (a.y + b.y) / 2 - r.top, d1 / d0);
        return;
      }
    }
    if (!arrasto) return;
    var dx = e.clientX - arrasto.x, dy = e.clientY - arrasto.y;
    if (Math.abs(dx) + Math.abs(dy) > 3) arrasto.moveu = true;
    cam.x = arrasto.cx + dx; cam.y = arrasto.cy + dy;
    aplicar(false);
  });
  function soltar(e) {
    delete toques[e.pointerId];
    if (!arrasto) return;
    var moveu = arrasto.moveu;
    arrasto = null;
    palco.classList.remove("arrastando");
    if (!moveu && e.button === 0) {                          // clique sem arrastar no fundo: limpa a seleção
      if (!e.target.closest(".md-no.modelo")) selecionar(null);
    }
  }
  palco.addEventListener("pointerup", soltar);
  palco.addEventListener("pointercancel", soltar);
  palco.addEventListener("wheel", function (e) {
    e.preventDefault();
    var r = palco.getBoundingClientRect();
    zoomEm(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.12 : 1 / 1.12);
  }, { passive: false });
  $("md-mais").addEventListener("click", function () { var r = palco.getBoundingClientRect(); zoomEm(r.width / 2, r.height / 2, 1.2); });
  $("md-menos").addEventListener("click", function () { var r = palco.getBoundingClientRect(); zoomEm(r.width / 2, r.height / 2, 1 / 1.2); });
  $("md-ajustar").addEventListener("click", ajustar);

  /* cliques: nó de modelo no mapa, item da barra, voltar, período, trocar */
  camadaNos.addEventListener("click", function (e) {
    var el = e.target.closest(".md-no.modelo");
    if (el) selecionar(el.getAttribute("data-modelo"), false);
  });
  camadaNos.addEventListener("keydown", function (e) {
    var el = e.target.closest(".md-no.modelo");
    if (el && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); selecionar(el.getAttribute("data-modelo"), true); }
  });
  $("md-lista").addEventListener("click", function (e) {
    var b = e.target.closest(".md-item");
    if (b) selecionar(b.getAttribute("data-modelo"), true);
  });
  $("md-detalhe").addEventListener("click", function (e) { if (e.target.closest("[data-voltar]")) selecionar(null); });
  $("md-periodos").addEventListener("click", function (e) {
    var b = e.target.closest(".md-periodo");
    if (!b) return;
    periodo = b.getAttribute("data-periodo");
    try { localStorage.setItem("md-periodo", periodo); } catch (er) { /* sem armazenamento */ }
    tudo();
  });
  $("md-detalhe").addEventListener("submit", function (e) {
    var f = e.target.closest("[data-trocar]");
    if (!f) return;
    e.preventDefault();
    var no = f.getAttribute("data-trocar"), novo = f.modelo.value.trim(), botao = f.querySelector("button");
    var m = MODELOS.filter(function (x) { return x.no === no; })[0];
    if (!novo || novo === modeloAtual(m)) return;
    if (!window.confirm("Trocar o modelo de \"" + m.funcao + "\" de " + modeloAtual(m) + " para " + novo + "?")) return;
    botao.disabled = true;
    pedir("api/modelos/trocar", { method: "POST", body: JSON.stringify({ no: no, modelo: novo }) })
      .then(function (r) { toast("Trocado: " + r.antes + " → " + r.modelo + ". " + (r.aviso || "")); return carregar(); })
      .catch(function (er) { toast(er.message, true); })
      .then(function () { botao.disabled = false; });
  });

  /* ---- carga ---- */
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status)); return j; }); });
  }
  function toast(msg, erro) { var t = $("md-toast"); t.textContent = msg; t.classList.toggle("erro", !!erro); t.hidden = false; clearTimeout(t._t); t._t = setTimeout(function () { t.hidden = true; }, erro ? 6000 : 3200); }
  function tudo() { desenharGastos(); desenharNos(); desenharLista(); desenharDetalhe(); }
  function carregar() {
    return pedir("api/modelos").then(function (j) {
      dados = Object.assign({ nos: {}, totais: {}, escolhidos: {}, precos: {}, serie: [] }, j || {});
      tudo();
    }).catch(function (er) { $("md-atualizado").textContent = "Não li os gastos: " + er.message; });
  }
  function medirTopo() {
    var area = document.querySelector(".md-palco-area");
    if (area) document.querySelector(".md-conteudo").style.setProperty("--md-topo", Math.round(area.getBoundingClientRect().top + window.scrollY) + "px");
  }

  medirTopo();
  tudo();
  aplicar(false);            // abre legível, no canto de cima (a Nay nova); "Ver tudo" mostra o conjunto
  carregar().then(function () { requestAnimationFrame(function () { desenharLinhas(); acender(); }); });
  setInterval(carregar, 60000);
  window.addEventListener("resize", function () { medirTopo(); });
})();
