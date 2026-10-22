/* ==========================================================================
   Imob Easy — Modelos de IA (22/10/2026, 470)
   Pedro: "uma conexão grande de nós, mostrando onde estão todos os modelos de IA e dando a opção de substituirmos esses
   modelos por lá, e um contador de quanto estamos gastando em cada modelo ... navegável com o mouse dentro ... uma
   sidebar na esquerda com os modelos como atalho e vista rápida".
   2ª versão, no mesmo dia: "está meio sem qualidade a borda e sem nitidez, e os modelos estão todos um em cima do outro
   ... pode dividir por funil ... no card do modelo quero as funções dele em tags ... só os modelos que rodam hoje".
   - O DESENHO mora aqui, em FUNIS: cada funil é uma faixa (canais -> serviço -> os modelos, lado a lado); um card por
     modelo em cada funil, com as funções em tags. Só o que roda hoje (a Nay velha do n8n saiu).
   - Os GASTOS vêm de /admin/api/modelos (site_ia_modelos), por função (o "nó" do banco); o card soma as suas funções.
   - O zoom é o `zoom` do CSS na cena (redesenha no tamanho novo), não o scale do transform: assim nada borra.
   ========================================================================== */
(function () {
  "use strict";

  function $(id) { return document.getElementById(id); }
  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }

  /* ---- os símbolos das empresas (só nos cards de modelo) ---- */
  var LOGO = {
    openai: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><g>' +
      [0, 60, 120].map(function (a) { return '<ellipse cx="12" cy="12" rx="3.4" ry="8.4" transform="rotate(' + a + ' 12 12)"/>'; }).join("") + "</g></svg>",
    anthropic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round">' +
      [0, 45, 90, 135].map(function (a) { return '<path d="M12 3.5v17" transform="rotate(' + a + ' 12 12)"/>'; }).join("") + "</svg>",
    deepseek: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M2.5 13.2c1.6-4.6 6.6-6.9 11.3-5.6 1.9.5 3.4 1.8 4.9 1.6.8-.1 1.7-.6 2.8-1.6-.3 2.9-1.9 4.6-4.2 5-.7 3.2-3.9 5.7-8 5.3-3.4-.3-5.9-2.1-6.8-4.7Z"/><circle cx="8.3" cy="12.4" r="1" fill="#fff"/></svg>',
    typesafe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M14.5 4.5v10a4 4 0 0 1-7.5 2"/></svg>'
  };
  var EMPRESA = { openai: "OpenAI", anthropic: "Anthropic", deepseek: "DeepSeek", typesafe: "Typesafe" };
  function logo(p) { return '<span class="md-logo md-logo-' + p + '" aria-hidden="true">' + (LOGO[p] || "") + "</span>"; }

  var COMO_CORE = "Mora no núcleo da Nay nova (nay-core, config/modelos.yaml). A troca é um deploy do núcleo: peça no chat que eu faço.";

  /* ---- os funis: só o que roda hoje ---- */
  var FUNIS = [
    { id: "corretores", titulo: "Atendimento aos corretores", sub: "Nay nova",
      canais: [["WhatsApp Parceria", "92 9445-3618"], ["Grupos de corretores", "pedidos e imóveis"], ["Instrução da equipe", "o que o Tel escreve no CRM"]],
      servico: ["Nay nova", "nay-core"],
      funcoes: [
        { no: "core.classificador", nome: "Entender a mensagem", modelo: "gpt-6-luna", prov: "openai", como: COMO_CORE,
          faz: "Lê cada mensagem do corretor: intenção, finalidade, tipo, bairro, valor e códigos citados. Roda em todo turno." },
        { no: "core.duvida", nome: "Responder dúvida do imóvel", modelo: "gpt-6-luna", prov: "openai", como: COMO_CORE,
          faz: "Responde taxa, IPTU, andar, pet... só com o que a ficha diz; o que falta vira pendência para o Tel." },
        { no: "core.instrucao", nome: "Ler instrução do Tel", modelo: "gpt-6-luna", prov: "openai", como: COMO_CORE,
          faz: "Traduz a instrução escrita no CRM num pedido de imóvel, num recado na voz da Nay ou em liberar a conversa." },
        { no: "core.reserva", nome: "Reserva quando a Luna falha", modelo: "deepseek-v4.1-flash", prov: "deepseek", como: COMO_CORE,
          faz: "Só entra quando a Luna cai ou passa de 8 s: o mesmo prompt pela OpenRouter. Serve ao classificador e à dúvida." },
        { no: "core.jev", nome: "Veto de coerência", modelo: "jev-1.13", prov: "typesafe", como: COMO_CORE,
          faz: "Antes de mandar um imóvel que não veio pelo código, confere se ele responde ao pedido; senão pergunta \"É este imóvel?\"." },
        { no: "core.transcricao", nome: "Transcrever áudio", modelo: "gpt-4o-mini-transcribe", prov: "openai", como: COMO_CORE,
          faz: "Transforma o áudio do corretor em texto antes do classificador (US$ 0,003 por minuto)." }
      ] },
    { id: "captacao", titulo: "Captação de proprietários", sub: "número oficial",
      canais: [["WhatsApp oficial", "92 8456-0874 · Meta"]],
      servico: ["Nay de captação", "nay-captacao"],
      funcoes: [
        { no: "captacao.atender", nome: "Conversar com o proprietário", modelo: "gpt-6-luna", prov: "openai", trocavel: true,
          faz: "Depois do disparo: atualiza a situação do imóvel, pergunta do contrato, cadastra o imóvel novo e a indicação." }
      ] },
    { id: "olx", titulo: "Leads da OLX", sub: "chat da OLX e WhatsApp dos leads",
      canais: [["Chat da OLX", "anúncios na OLX"], ["WhatsApp dos leads", "92 8595-6408"]],
      servico: ["Nay da OLX", "nay-olx"],
      funcoes: [
        { no: "olx.chat", nome: "Responder no chat da OLX", modelo: "gpt-6-luna", prov: "openai", trocavel: true,
          faz: "Responde quem escreve nos nossos anúncios da OLX e chama a pessoa para o WhatsApp." },
        { no: "olx.whatsapp", nome: "Atender no WhatsApp", modelo: "gpt-6-luna", prov: "openai", trocavel: true,
          faz: "Segue o roteiro (valor, bairros, quartos, mobília), manda os imóveis e marca a visita." },
        { no: "olx.parceiro", nome: "Ler a resposta do parceiro", modelo: "gpt-6-luna", prov: "openai", trocavel: true,
          faz: "Lê se o corretor parceiro disse que o imóvel do anúncio ainda está disponível." }
      ] },
    { id: "equipe", titulo: "Equipe no CRM", sub: "conversas da equipe",
      canais: [["Áudios das conversas", "WhatsApp no CRM"]],
      servico: ["CRM", "crm.imobeasy.online"],
      funcoes: [
        { no: "crm.transcricao", nome: "Transcrever áudio", modelo: "gpt-4o-transcribe", prov: "openai", semMedicao: true,
          como: "Mora no CRM (src/lib/transcricao.ts). A troca é um deploy do CRM: peça no chat.",
          faz: "Transcreve o áudio que chega no CRM: a conversa mostra o texto e a Nay de captação lê." }
      ] },
    { id: "gestao", titulo: "Gestão com agentes", sub: "agentes.imobeasy.online",
      canais: [["Painel dos agentes", "agentes.imobeasy.online"]],
      servico: ["Agente Claude", "VPS2"],
      funcoes: ["Visitas", "Métricas", "Estratégia", "Financeiro", "Respostas", "Revisão da Nay"].map(function (n) {
        return { no: "agentes.claude", nome: n, modelo: "Claude Sonnet", prov: "anthropic", assinatura: true,
          como: "Claude Code com a assinatura da conta: não há custo por token. Cada projeto escolhe o modelo no seu projeto.json.",
          faz: "Os chats de projeto: leem o banco e o código das duas VPS e respondem a equipe." };
      }) }
  ];

  /* ---- dados da API ---- */
  var dados = { nos: {}, totais: {}, escolhidos: {}, precos: {}, serie: [] };
  var PERIODOS = [["hoje", "Hoje"], ["ontem", "Ontem"], ["d7", "7 dias"], ["d30", "30 dias"], ["mes", "Este mês"]];
  var periodo = "d7", selecionado = null;
  try { periodo = localStorage.getItem("md-periodo") || "d7"; } catch (e) { /* sem armazenamento */ }

  function numero(n, prefixo) {
    var casas = n === 0 || n >= 0.01 ? 2 : 4;
    return prefixo + n.toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });
  }
  function dolar(v) { return numero(Number(v || 0), "US$ "); }
  /* 22/10 (Pedro: "em reais principalmente, e dólar pequenininho em cinza"): o custo vem em dólar (é como a OpenAI
     cobra) e sai em reais pela cotação do dia (474), com o dólar embaixo, pequeno. Sem cotação, só o dólar. */
  function dinheiro(v) {
    var usd = Number(v || 0), cot = Number((dados.cotacao || {}).usd_brl || 0);
    if (!cot) return '<span class="md-brl">' + dolar(usd) + "</span>";
    return '<span class="md-brl">' + numero(usd * cot, "R$ ") + '</span><span class="md-usd">' + dolar(usd) + "</span>";
  }
  function inteiro(v) { return Number(v || 0).toLocaleString("pt-BR"); }
  function doNo(no) { return dados.nos[no] || { gasto: {}, chamadas: {} }; }
  function modeloDe(f) { return (dados.escolhidos[f.no] && dados.escolhidos[f.no].modelo) || f.modelo; }
  function nomePeriodo() { return (PERIODOS.filter(function (p) { return p[0] === periodo; })[0] || ["", ""])[1].toLowerCase(); }

  /* os cards: as funções de cada funil agrupadas pelo modelo que usam agora */
  function cards() {
    var lista = [];
    FUNIS.forEach(function (fu) {
      var porModelo = {};
      fu.funcoes.forEach(function (f) {
        var m = modeloDe(f);
        if (!porModelo[m]) { porModelo[m] = { id: fu.id + ":" + m, funil: fu, modelo: m, prov: f.prov, funcoes: [] }; lista.push(porModelo[m]); }
        porModelo[m].funcoes.push(f);
      });
    });
    return lista;
  }
  function nosDo(card) { var vistos = {}; return card.funcoes.map(function (f) { return f.no; }).filter(function (n) { return vistos[n] ? false : (vistos[n] = true); }); }
  function soma(card, campo, p) { return nosDo(card).reduce(function (t, n) { return t + Number(((doNo(n)[campo] || {})[p]) || 0); }, 0); }
  function tipoCard(card) { var f = card.funcoes[0]; return f.assinatura ? "assinatura" : f.semMedicao ? "sem" : "medido"; }

  /* ---- o desenho: uma faixa por funil ---- */
  // no máximo 2 cards por linha (a Nay nova vira 2x2): o mapa cabe na largura da tela
  var L = { canalX: 26, servicoX: 286, cardX: 560, cardW: 250, cardPasso: 286, porLinha: 2, cardPassoY: 196, topoFaixa: 46,
            espacoContador: 44, canalPasso: 62, gap: 30 };
  var GEO = { faixas: [], nos: {}, ligacoes: [], w: 1200, h: 900 };
  function montarGeometria(lista) {
    GEO = { faixas: [], nos: {}, ligacoes: [] };
    var y = 16, larguraMax = 0;
    FUNIS.forEach(function (fu) {
      var meus = lista.filter(function (c) { return c.funil === fu; });
      var alturaCanais = fu.canais.length * L.canalPasso;
      var colunas = Math.min(L.porLinha, Math.max(meus.length, 1)), filas = Math.ceil(meus.length / L.porLinha) || 1;
      var alturaCards = L.espacoContador + (filas - 1) * L.cardPassoY + 140;
      var miolo = Math.max(alturaCanais, alturaCards);
      var h = L.topoFaixa + miolo + 18;
      larguraMax = Math.max(larguraMax, L.cardX + colunas * L.cardPasso - (L.cardPasso - L.cardW) + 26);
      GEO.faixas.push({ funil: fu, y: y, h: h });
      var meio = y + L.topoFaixa + miolo / 2;
      fu.canais.forEach(function (c, i) {
        var id = "c." + fu.id + "." + i;
        GEO.nos[id] = { tipo: "comum", x: L.canalX, y: Math.round(meio - alturaCanais / 2 + i * L.canalPasso + 6), html: esc(c[0]) + "<small>" + esc(c[1]) + "</small>" };
        GEO.ligacoes.push({ de: id, para: "s." + fu.id });
      });
      GEO.nos["s." + fu.id] = { tipo: "comum", x: L.servicoX, y: Math.round(meio - 24), html: esc(fu.servico[0]) + "<small>" + esc(fu.servico[1]) + "</small>" };
      var topoCards = Math.round(meio - alturaCards / 2 + L.espacoContador);
      meus.forEach(function (c, i) {
        var col = i % L.porLinha, fila = Math.floor(i / L.porLinha);
        GEO.nos[c.id] = { tipo: "modelo", x: L.cardX + col * L.cardPasso, y: topoCards + fila * L.cardPassoY, card: c };
        GEO.ligacoes.push({ de: "s." + fu.id, para: c.id, modelo: true, ordem: col });
      });
      y += h + L.gap;
    });
    GEO.w = larguraMax + 20; GEO.h = y;
  }

  var palco = $("md-palco"), mundo = $("md-mundo"), cena = $("md-cena");
  var camadaFaixas = $("md-faixas"), camadaNos = $("md-nos"), linhas = $("md-linhas");

  function contador(card) {
    var t = tipoCard(card), ch = soma(card, "chamadas", periodo);
    var rodape = "<small>" + inteiro(ch) + " chamada" + (ch === 1 ? "" : "s") + " · " + nomePeriodo() + "</small>";
    if (t === "assinatura") return '<div class="md-contador sem">assinatura<small>sem custo por token</small></div>';
    if (t === "sem") return '<div class="md-contador sem">sem medição' + rodape + "</div>";
    return '<div class="md-contador">' + dinheiro(soma(card, "gasto", periodo)) + rodape + "</div>";
  }
  function tags(card, max) {
    var nomes = card.funcoes.map(function (f) { return f.nome; });
    var mostra = max ? nomes.slice(0, max) : nomes;
    return mostra.map(function (n) { return '<span class="md-tag">' + esc(n) + "</span>"; }).join("") +
      (max && nomes.length > max ? '<span class="md-tag md-tag-mais">+' + (nomes.length - max) + "</span>" : "");
  }

  function desenhar() {
    var lista = cards();
    montarGeometria(lista);
    camadaFaixas.innerHTML = GEO.faixas.map(function (f) {
      return '<div class="md-faixa" style="top:' + f.y + "px;width:" + GEO.w + "px;height:" + f.h + 'px">' +
        '<p class="md-faixa-titulo">' + esc(f.funil.titulo) + " <span>· " + esc(f.funil.sub) + "</span></p></div>";
    }).join("");
    camadaNos.innerHTML = Object.keys(GEO.nos).map(function (id) {
      var n = GEO.nos[id], estilo = "left:" + n.x + "px;top:" + n.y + "px";
      if (n.tipo !== "modelo") return '<div class="md-no" data-no="' + esc(id) + '" style="' + estilo + '">' + n.html + "</div>";
      var c = n.card, parado = tipoCard(c) !== "assinatura" && !soma(c, "chamadas", periodo);
      return '<div class="md-no modelo' + (parado ? " parado" : "") + (selecionado === c.id ? " ativo" : "") + '" data-no="' + esc(id) +
        '" style="' + estilo + '" role="button" tabindex="0" aria-label="' + esc(c.modelo + " em " + c.funil.titulo) + '">' + contador(c) +
        '<div class="md-card-topo">' + logo(c.prov) + '<span><span class="md-no-nome">' + esc(c.modelo) + '</span><span class="md-no-empresa">' +
        esc(EMPRESA[c.prov] || "") + "</span></span></div>" +
        '<div class="md-tags">' + tags(c, 4) + "</div></div>";
    }).join("");
    desenharLinhas();
    acender();
  }

  function caixa(id) {
    var el = camadaNos.querySelector('[data-no="' + id.replace(/"/g, "") + '"]'), n = GEO.nos[id];
    return { x: n.x, y: n.y, w: el ? el.offsetWidth : 200, h: el ? el.offsetHeight : 44 };
  }
  function desenharLinhas() {
    linhas.setAttribute("width", GEO.w); linhas.setAttribute("height", GEO.h);
    linhas.innerHTML = GEO.ligacoes.map(function (l, i) {
      var a = caixa(l.de), b = caixa(l.para);
      var x1 = a.x + a.w, y1 = a.y + a.h / 2, x2 = b.x, y2 = b.y + b.h / 2, d;
      if (l.modelo && l.ordem > 0) {
        // os cards depois do primeiro: a linha sobe por cima do contador e desce no meio do card
        var yAlto = b.y - 52;
        d = "M" + x1 + "," + y1 + " C" + (x1 + 60) + "," + y1 + " " + (x1 + 60) + "," + yAlto + " " + (x1 + 120) + "," + yAlto +
            " L" + (b.x + b.w / 2 - 40) + "," + yAlto + " Q" + (b.x + b.w / 2) + "," + yAlto + " " + (b.x + b.w / 2) + "," + (b.y - 40);
      } else {
        d = "M" + x1 + "," + y1 + " C" + (x1 + 60) + "," + y1 + " " + (x2 - 60) + "," + y2 + " " + x2 + "," + y2;
      }
      return '<path data-l="' + i + '" class="' + (l.modelo ? "modelo" : "") + '" d="' + d + '"/>';
    }).join("");
  }

  function caminhoDe(id) {
    var aceso = {}, fila = [id];
    aceso[id] = true;
    while (fila.length) {
      var at = fila.shift();
      GEO.ligacoes.forEach(function (l) { if (l.para === at && !aceso[l.de]) { aceso[l.de] = true; fila.push(l.de); } });
    }
    return aceso;
  }
  function acender() {
    var aceso = selecionado && GEO.nos[selecionado] ? caminhoDe(selecionado) : null;
    camadaNos.querySelectorAll(".md-no").forEach(function (el) {
      var id = el.getAttribute("data-no");
      el.classList.toggle("esmaecido", !!aceso && !aceso[id]);
      el.classList.toggle("aceso", !!(aceso && aceso[id]) && GEO.nos[id].tipo !== "modelo");
      el.classList.toggle("ativo", id === selecionado);
    });
    linhas.querySelectorAll("path").forEach(function (p) {
      var l = GEO.ligacoes[Number(p.getAttribute("data-l"))];
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
    var w = 240, h = 42, passo = s.length > 1 ? w / (s.length - 1) : w;
    var pts = s.map(function (d, i) { return (i * passo).toFixed(1) + "," + (h - 4 - (Number(d.custo) || 0) / max * (h - 10)).toFixed(1); });
    $("md-serie").innerHTML = s.length ? '<svg viewBox="0 0 ' + w + " " + h + '" preserveAspectRatio="none">' +
      '<polyline points="0,' + h + " " + pts.join(" ") + " " + w + "," + h + '" fill="#efe8fd" stroke="none"/>' +
      '<polyline points="' + pts.join(" ") + '" fill="none" stroke="#6d28d9" stroke-width="1.8" vector-effect="non-scaling-stroke"/></svg>' +
      "<small>gasto por dia · 30 dias</small>" : "";
    var cot = dados.cotacao || {};
    $("md-atualizado").textContent = (cot.usd_brl ? "Em reais · dólar a R$ " + Number(cot.usd_brl).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 4 }) + " (" + (cot.atualizado_em || "") + ")" : "Em dólar (US$)") +
      " · atualizado às " + (dados.gerado_em ? dados.gerado_em.slice(11, 16) : "--:--");
  }

  /* ---- a barra (atalho e vista rápida) ---- */
  function valorCurto(c) {
    var t = tipoCard(c);
    return t === "assinatura" ? "assinatura" : t === "sem" ? inteiro(soma(c, "chamadas", periodo)) + " cham." : dinheiro(soma(c, "gasto", periodo));
  }
  function desenharLista() {
    var lista = cards();
    $("md-lista").innerHTML = FUNIS.map(function (fu) {
      return '<p class="md-grupo">' + esc(fu.titulo) + "</p>" + lista.filter(function (c) { return c.funil === fu; }).map(function (c) {
        return '<button type="button" class="md-item' + (selecionado === c.id ? " ativo" : "") + '" data-card="' + esc(c.id) + '">' + logo(c.prov) +
          '<span class="md-item-texto"><span class="md-item-nome">' + esc(c.modelo) + '</span><span class="md-item-onde">' +
          esc(c.funcoes.length + (c.funcoes.length === 1 ? " função" : " funções")) + "</span></span>" +
          '<span class="md-item-valor">' + valorCurto(c) + "</span></button>";
      }).join("");
    }).join("");
  }

  function desenharDetalhe() {
    var caixaDet = $("md-detalhe"), c = cards().filter(function (x) { return x.id === selecionado; })[0];
    if (!c) { caixaDet.hidden = true; return; }
    var t = tipoCard(c), preco = (dados.precos || {})[c.modelo];
    var linhasFn = c.funcoes.map(function (f) {
      var d = doNo(f.no), ch = (d.chamadas || {})[periodo] || 0;
      var valor = f.assinatura ? "" : f.semMedicao ? inteiro(ch) + " cham." : dinheiro((d.gasto || {})[periodo]);
      return '<div class="md-fn"><div class="md-fn-topo"><span class="md-tag">' + esc(f.nome) + "</span><b>" + valor + "</b></div>" +
        '<p class="md-det-texto">' + esc(f.faz) + "</p>" +
        (f.trocavel
          ? '<form class="md-trocar" data-trocar="' + esc(f.no) + '"><input name="modelo" list="md-sugestoes" value="' + esc(modeloDe(f)) +
            '" aria-label="Modelo de ' + esc(f.nome) + '" autocomplete="off" spellcheck="false"><button type="submit">Trocar</button></form>'
          : "") + "</div>";
    }).join("");
    var tabela = PERIODOS.map(function (p) {
      var ch = soma(c, "chamadas", p[0]);
      return '<tr class="' + (p[0] === periodo ? "sel" : "") + '"><td>' + p[1] + " · " + inteiro(ch) + " chamada" + (ch === 1 ? "" : "s") + "</td><td>" +
        (t === "assinatura" ? "assinatura" : t === "sem" ? "—" : dinheiro(soma(c, "gasto", p[0]))) + "</td></tr>";
    }).join("");
    var trocavel = !!c.funcoes[0].trocavel;
    caixaDet.innerHTML =
      '<button type="button" class="md-voltar" data-voltar>← Todos os modelos</button>' +
      '<div class="md-det-topo">' + logo(c.prov) + "<div><h2>" + esc(c.modelo) + "</h2><p>" + esc((EMPRESA[c.prov] || "") + " · " + c.funil.titulo) + "</p></div></div>" +
      '<div class="md-det-sec"><h3>Onde ele está</h3><div class="md-caminho">' +
        '<div class="md-passo"><i></i><div>' + esc(c.funil.canais.map(function (x) { return x[0]; }).join(" · ")) + "<small>de onde chega</small></div></div>" +
        '<div class="md-passo"><i></i><div>' + esc(c.funil.servico[0]) + "<small>" + esc(c.funil.servico[1]) + "</small></div></div>" +
        '<div class="md-passo"><i></i><div>' + esc(c.modelo) + "<small>" + esc(c.funcoes.length + (c.funcoes.length === 1 ? " função" : " funções")) + "</small></div></div>" +
      "</div></div>" +
      '<div class="md-det-sec"><h3>Gastos</h3><table class="md-tabela">' + tabela + "</table>" +
        (preco && preco.entrada != null ? '<p class="md-aviso">Por milhão de tokens (a OpenAI cobra em dólar): entrada ' + dolar(preco.entrada) + ", em cache " + dolar(preco.entrada_cache) + ", saída " + dolar(preco.saida) + ".</p>"
          : preco && preco.por_minuto ? '<p class="md-aviso">' + dolar(preco.por_minuto) + " por minuto de áudio.</p>" : "") +
        (t === "sem" ? '<p class="md-aviso">Este lugar não registra tokens: só as chamadas.</p>' : "") +
        (t === "medido" && c.funil.id !== "corretores" ? '<p class="md-aviso">A medição aqui começou em 22/10/2026.</p>' : "") +
      "</div>" +
      '<div class="md-det-sec"><h3>Funções</h3>' + linhasFn +
        '<datalist id="md-sugestoes"><option value="gpt-6-luna"><option value="gpt-6-sol"><option value="gpt-5.6-luna"><option value="gpt-5.6-sol"></datalist>' +
        '<p class="md-aviso">' + (trocavel ? "Cada função troca sozinha: use o nome exato da API da OpenAI. Vale na próxima chamada (até 1 minuto)."
          : esc(c.funcoes[0].como || "")) + "</p>" +
      "</div>";
    caixaDet.hidden = false;
  }

  function selecionar(id, centrar) {
    selecionado = id;
    desenharLista(); desenharDetalhe(); acender();
    if (id && centrar) focar(id);
  }

  /* ---- a câmera: translate inteiro no mundo + zoom do CSS na cena (nítido em qualquer zoom) ---- */
  var cam = { x: 16, y: 14, k: 0.92 };
  function aplicar() {
    mundo.style.transform = "translate(" + Math.round(cam.x) + "px," + Math.round(cam.y) + "px)";
    cena.style.zoom = cam.k;
  }
  function zoomEm(px, py, fator) {
    var k = Math.min(1.6, Math.max(0.35, cam.k * fator));
    cam.x = px - (px - cam.x) * (k / cam.k); cam.y = py - (py - cam.y) * (k / cam.k); cam.k = k;
    aplicar();
  }
  function ajustar() {
    var r = palco.getBoundingClientRect();
    cam.k = Math.max(0.35, Math.min((r.width - 32) / GEO.w, (r.height - 32) / GEO.h, 1.2));
    cam.x = (r.width - GEO.w * cam.k) / 2; cam.y = 14;
    aplicar();
  }
  function focar(id) {
    var r = palco.getBoundingClientRect(), c = caixa(id);
    cam.k = Math.max(cam.k, 0.9);
    cam.x = r.width / 2 - (c.x + c.w / 2) * cam.k; cam.y = r.height / 2 - (c.y + c.h / 2) * cam.k;
    aplicar();
  }

  var arrasto = null, toques = {};
  palco.addEventListener("contextmenu", function (e) { e.preventDefault(); });
  palco.addEventListener("pointerdown", function (e) {
    if (e.pointerType === "touch") toques[e.pointerId] = { x: e.clientX, y: e.clientY };
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
      if (ids.length === 2 && antes.length === 2) {
        var a = toques[ids[0]], b = toques[ids[1]], r = palco.getBoundingClientRect();
        var d0 = Math.hypot(antes[0].x - antes[1].x, antes[0].y - antes[1].y), d1 = Math.hypot(a.x - b.x, a.y - b.y);
        if (d0 > 0) zoomEm((a.x + b.x) / 2 - r.left, (a.y + b.y) / 2 - r.top, d1 / d0);
        return;
      }
    }
    if (!arrasto) return;
    var dx = e.clientX - arrasto.x, dy = e.clientY - arrasto.y;
    if (Math.abs(dx) + Math.abs(dy) > 3) arrasto.moveu = true;
    cam.x = arrasto.cx + dx; cam.y = arrasto.cy + dy;
    aplicar();
  });
  function soltar(e) {
    delete toques[e.pointerId];
    if (!arrasto) return;
    var moveu = arrasto.moveu;
    arrasto = null;
    palco.classList.remove("arrastando");
    if (!moveu && e.button === 0 && !e.target.closest(".md-no.modelo")) selecionar(null);
  }
  palco.addEventListener("pointerup", soltar);
  palco.addEventListener("pointercancel", soltar);
  palco.addEventListener("wheel", function (e) {
    e.preventDefault();
    var r = palco.getBoundingClientRect();
    zoomEm(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.1 : 1 / 1.1);
  }, { passive: false });
  $("md-mais").addEventListener("click", function () { var r = palco.getBoundingClientRect(); zoomEm(r.width / 2, r.height / 2, 1.15); });
  $("md-menos").addEventListener("click", function () { var r = palco.getBoundingClientRect(); zoomEm(r.width / 2, r.height / 2, 1 / 1.15); });
  $("md-ajustar").addEventListener("click", ajustar);

  camadaNos.addEventListener("click", function (e) {
    var el = e.target.closest(".md-no.modelo");
    if (el) selecionar(el.getAttribute("data-no"), false);
  });
  camadaNos.addEventListener("keydown", function (e) {
    var el = e.target.closest(".md-no.modelo");
    if (el && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); selecionar(el.getAttribute("data-no"), true); }
  });
  $("md-lista").addEventListener("click", function (e) {
    var b = e.target.closest(".md-item");
    if (b) selecionar(b.getAttribute("data-card"), true);
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
    var fn = null, funil = null;
    FUNIS.forEach(function (fu) { fu.funcoes.forEach(function (x) { if (x.no === no) { fn = x; funil = fu; } }); });
    if (!fn || !novo || novo === modeloDe(fn)) return;
    if (!window.confirm("Trocar o modelo de \"" + fn.nome + "\" de " + modeloDe(fn) + " para " + novo + "?")) return;
    botao.disabled = true;
    pedir("api/modelos/trocar", { method: "POST", body: JSON.stringify({ no: no, modelo: novo }) })
      .then(function (r) { toast("Trocado: " + r.antes + " → " + r.modelo + ". " + (r.aviso || "")); selecionado = funil.id + ":" + novo; return carregar(); })
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
  function tudo() { desenharGastos(); desenhar(); desenharLista(); desenharDetalhe(); }
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

  function abrirNaLargura() {
    var r = palco.getBoundingClientRect();
    cam.k = Math.max(0.6, Math.min((r.width - 32) / GEO.w, 1));
    cam.x = Math.max(16, (r.width - GEO.w * cam.k) / 2); cam.y = 14;
    aplicar();
  }

  medirTopo();
  tudo();
  abrirNaLargura();
  carregar().then(function () { requestAnimationFrame(function () { desenharLinhas(); acender(); }); });
  setInterval(carregar, 60000);
  window.addEventListener("resize", medirTopo);
})();
