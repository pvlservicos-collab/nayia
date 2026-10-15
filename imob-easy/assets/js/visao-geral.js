/* VISÃO GERAL (Pedro, 15/10/2026): "organize todo o meu projeto e recursos na VPS em um fluxograma conectado, todas
   as Nays e onde elas estão ... bonito e com cores por etapas ... com (i) que explicam o que é cada etapa, só uma
   descriçãozinha ... tudo das 2 VPS em questão de ESTRUTURA e não funções: a Nay Parceria é só uma bolinha ... clean,
   glass".

   Uma bolinha por peça (pessoas, números, Nays, envio, banco, telas, infraestrutura), nas duas VPS. A posição é fixa
   (um mapa, não um gráfico calculado): mudou a estrutura, mexe aqui nas listas NOS e LIGACOES. A mesma página aparece
   no CRM (aba Visão geral), servida pelo proxy do site (crm/src/lib/painelDoSite.ts). */
(function () {
  "use strict";

  var ETAPAS = {
    pessoas: { nome: "Pessoas",  cor: "#8e1e4b", info: "Quem conversa com a gente." },
    canais:  { nome: "Canais",   cor: "#1d9bd7", info: "Por onde as mensagens entram e saem." },
    nays:    { nome: "Nays",     cor: "#e8475f", info: "Os agentes que leem, entendem e respondem." },
    envio:   { nome: "Envio",    cor: "#f39c12", info: "Quem entrega as mensagens no WhatsApp." },
    dados:   { nome: "Dados",    cor: "#1f4e79", info: "Onde tudo fica guardado." },
    telas:   { nome: "Telas",    cor: "#2bb5b8", info: "O que a equipe abre no navegador." },
    infra:   { nome: "Infra",    cor: "#7d8597", info: "Portas, rotinas e ligações entre as máquinas." },
    ia:      { nome: "IA",       cor: "#7b61ff", info: "O modelo de linguagem que as Nays usam." }
  };

  /* x, y no desenho de 1640 x 1010. icone: pessoa, chat, robo, envio, banco, tela, engrenagem, porta, cerebro, grupo */
  var NOS = [
    // ── fora das VPS
    { id: "corretores",  etapa: "pessoas", x: 90,  y: 200, nome: "Corretores",    sub: "parceiros",            icone: "grupo",  info: "Pedem e oferecem imóveis nos grupos e no privado." },
    { id: "donos",       etapa: "pessoas", x: 90,  y: 390, nome: "Proprietários", sub: "donos dos imóveis",    icone: "pessoa", info: "Confirmam situação, valor e os dados do imóvel." },
    { id: "clientes",    etapa: "pessoas", x: 90,  y: 580, nome: "Clientes OLX",  sub: "anúncios",             icone: "pessoa", info: "Quem chama nos nossos anúncios da OLX." },
    { id: "equipe",      etapa: "pessoas", x: 90,  y: 770, nome: "Equipe",        sub: "Tel · Pedro · Rayssa", icone: "grupo",  info: "Comanda a Nay e atende pelo CRM." },

    { id: "grupos",      etapa: "canais",  x: 300, y: 120, nome: "Grupos",        sub: "WhatsApp",             icone: "grupo",  info: "Grupos de corretores: onde postamos e lemos pedidos." },
    { id: "parceria",    etapa: "canais",  x: 300, y: 285, nome: "Parceria",      sub: "Z-API · 9445-3618",    icone: "chat",   info: "Número da Nay com os corretores e os donos da OLX." },
    { id: "imobeasy",    etapa: "canais",  x: 300, y: 450, nome: "Imob Easy",     sub: "Z-API · 8595-6408",    icone: "chat",   info: "WhatsApp da equipe e da captação antiga." },
    { id: "oficial",     etapa: "canais",  x: 300, y: 615, nome: "Oficial",       sub: "Meta · 8456-0874",     icone: "chat",   info: "Número oficial: captação com modelos aprovados." },
    { id: "olx",         etapa: "canais",  x: 300, y: 780, nome: "OLX",           sub: "API da OLX",           icone: "chat",   info: "Anúncios, chat e contatos dos anúncios." },
    { id: "ia",          etapa: "ia",      x: 300, y: 935, nome: "IA",            sub: "OpenAI · luna",        icone: "cerebro", info: "O modelo que todas as Nays usam para entender e responder." },

    // ── VPS1
    { id: "nay-grupos",  etapa: "nays",  vps: 1, x: 525,  y: 120, nome: "Nay dos grupos",  sub: "nay-grupos",          icone: "robo",  info: "Lê os pedidos dos grupos e cruza com o catálogo." },
    { id: "n8n",         etapa: "nays",  vps: 1, x: 525,  y: 300, nome: "Nay velha",       sub: "n8n",                 icone: "robo",  info: "Fluxos antigos: recebe a Parceria, comandos do Tel e alarmes." },
    { id: "nay-olx",     etapa: "nays",  vps: 1, x: 525,  y: 780, nome: "Nay OLX",         sub: "nay-olx",             icone: "robo",  info: "Responde o chat da OLX e publica os anúncios." },
    { id: "treino",      etapa: "nays",  vps: 1, x: 525,  y: 920, nome: "Treino",          sub: "nay-core-treino",     icone: "robo",  info: "Refaz conversas reais em sombra para medir a Nay." },

    { id: "publicador",  etapa: "nays",  vps: 1, x: 725,  y: 120, nome: "Publicador",      sub: "nay-publicador",      icone: "robo",  info: "Posta imóveis e listas nos grupos, na grade." },
    { id: "nay-nova",    etapa: "nays",  vps: 1, x: 725,  y: 300, nome: "Nay Parceria",    sub: "nay-core",            icone: "robo",  info: "Atende os corretores: pedido, busca, card e fotos." },
    { id: "olx-prop",    etapa: "nays",  vps: 1, x: 725,  y: 460, nome: "Nay donos OLX",   sub: "nay-captacao",        icone: "robo",  info: "Confirma os dados de quem deixou o contato na OLX." },
    { id: "captacao",    etapa: "nays",  vps: 1, x: 725,  y: 620, nome: "Nay captação",    sub: "nay-captacao",        icone: "robo",  info: "Fala com os proprietários pelo número oficial." },

    { id: "rotinas",     etapa: "infra", vps: 1, x: 925,  y: 120, nome: "Rotinas",         sub: "cron",                icone: "engrenagem", info: "Espelho do CRM, funis, follow-ups e medidas, a cada minuto." },
    { id: "envio-nay",   etapa: "envio", vps: 1, x: 925,  y: 300, nome: "Envio da Nay",    sub: "nay-core-enviador",   icone: "envio", info: "Entrega as respostas da Nay Parceria." },
    { id: "enviador",    etapa: "envio", vps: 1, x: 925,  y: 460, nome: "Enviador",        sub: "nay-enviador-manual", icone: "envio", info: "Entrega pela Parceria o que a equipe e as Nays pedem." },
    { id: "traefik",     etapa: "infra", vps: 1, x: 925,  y: 920, nome: "Traefik",         sub: "HTTPS",               icone: "porta", info: "A porta de entrada dos sites da VPS1." },

    { id: "painel",      etapa: "telas", vps: 1, x: 1130, y: 120, nome: "Painel",          sub: "painel.imobeasy",     icone: "tela",  info: "Painel da Nay." },
    { id: "banco",       etapa: "dados", vps: 1, x: 1130, y: 390, nome: "Banco",           sub: "naydb · crmdb",       icone: "banco", grande: true, info: "PostgreSQL: imóveis, conversas, leads e regras." },
    { id: "crm",         etapa: "telas", vps: 1, x: 1130, y: 620, nome: "CRM",             sub: "crm.imobeasy",        icone: "tela",  info: "As três linhas de WhatsApp, pipeline, visitas e OLX." },
    { id: "site",        etapa: "telas", vps: 1, x: 1130, y: 790, nome: "Site",            sub: "imobeasy.online",     icone: "tela",  info: "Catálogo público, API e este admin." },

    // ── VPS2
    { id: "lembretes",   etapa: "nays",  vps: 2, x: 1460, y: 120, nome: "Lembretes",       sub: "agente",              icone: "robo",  info: "Agente de lembretes pelo WhatsApp." },
    { id: "evolution",   etapa: "canais", vps: 2, x: 1460, y: 285, nome: "Evolution",      sub: "WhatsApp nº 2",       icone: "chat",  info: "API de WhatsApp alternativa à Z-API." },
    { id: "n8n-capt",    etapa: "nays",  vps: 2, x: 1460, y: 450, nome: "Captação Z-API",  sub: "n8n-captacao",        icone: "robo",  info: "Captação antiga pelo WhatsApp da Imob Easy." },
    { id: "hermes",      etapa: "nays",  vps: 2, x: 1460, y: 615, nome: "Agente OLX",      sub: "Hermes",              icone: "robo",  info: "Agente de navegador na OLX; o navegador roda no PC do Pedro." },
    { id: "portal",      etapa: "telas", vps: 2, x: 1460, y: 780, nome: "Portal",          sub: "app.imobeasy",        icone: "tela",  info: "Portal do corretor." },
    { id: "financas",    etapa: "telas", vps: 2, x: 1460, y: 920, nome: "Finanças",        sub: "financas.imobeasy",   icone: "tela",  info: "Controle financeiro." }
  ];

  /* [de, para, opções]. via: altura por onde a linha passa (para não cortar bolinhas); tracejada: ligação lógica */
  var LIGACOES = [
    ["corretores", "grupos"], ["corretores", "parceria"],
    ["donos", "oficial"], ["donos", "imobeasy"], ["donos", "parceria"],
    ["clientes", "olx"],
    ["equipe", "parceria"], ["equipe", "imobeasy"], ["equipe", "crm", { via: 996 }],

    ["grupos", "nay-grupos"], ["publicador", "grupos", { via: 66 }],
    ["parceria", "n8n"], ["n8n", "nay-nova"], ["n8n", "olx-prop"],
    ["oficial", "crm", { via: 700 }], ["captacao", "crm"],
    ["imobeasy", "n8n-capt", { via: 1002 }],
    ["olx", "nay-olx"], ["olx", "hermes", { via: 990 }],

    ["treino", "nay-nova", { tracejada: true }],
    ["nay-nova", "envio-nay"], ["olx-prop", "enviador"],

    // para o Banco pelos corredores entre as linhas, sem cortar as bolinhas do meio
    ["nay-grupos", "banco", { via: 205 }], ["publicador", "banco", { via: 215 }], ["nay-nova", "banco", { via: 385 }],
    ["captacao", "banco", { via: 548 }], ["nay-olx", "banco", { via: 712 }],
    ["envio-nay", "banco"], ["enviador", "banco"],
    ["banco", "crm"], ["banco", "site"], ["banco", "painel"],
    ["rotinas", "banco"], ["rotinas", "crm", { tracejada: true }],
    ["traefik", "site"], ["traefik", "crm"],

    ["n8n-capt", "banco", { tracejada: true, rotulo: "Tailscale" }],
    ["evolution", "crm", { tracejada: true }], ["lembretes", "evolution"],

    ["ia", "nay-nova", { ia: true }], ["ia", "captacao", { ia: true }], ["ia", "nay-grupos", { ia: true }],
    ["ia", "nay-olx", { ia: true }], ["ia", "olx-prop", { ia: true }], ["ia", "n8n-capt", { ia: true, via: 1006 }]
  ];

  var PAINEIS = [
    { id: "fora", x: 20,   y: 8, w: 370, h: 984, titulo: "Fora das VPS", sub: "pessoas e números" },
    { id: "vps1", x: 420,  y: 8, w: 830, h: 984, titulo: "VPS1", sub: "srv1894338 · Docker + systemd" },
    { id: "vps2", x: 1300, y: 8, w: 320, h: 984, titulo: "VPS2", sub: "srv1877774 · Docker + Caddy" }
  ];

  var ICONES = {
    pessoa: '<circle cx="0" cy="-5" r="5"/><path d="M-9 9c1.5-5 5-7 9-7s7.5 2 9 7"/>',
    grupo: '<circle cx="-5" cy="-4" r="4"/><circle cx="6" cy="-3" r="3.2"/><path d="M-13 9c1-4.5 4.2-6.5 8-6.5s7 2 8 6.5M4 3.5c3.5 0 6.4 1.8 7.4 5.5"/>',
    chat: '<path d="M-10-7h20a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3H-3l-6 5v-5h-1a3 3 0 0 1-3-3v-9a3 3 0 0 1 3-3z"/>',
    robo: '<rect x="-9" y="-6" width="18" height="14" rx="4"/><path d="M0-6v-4M-4 1h.01M4 1h.01M-12 0v3M12 0v3"/>',
    envio: '<path d="M11-10-12-1l9 3 3 9z"/><path d="M11-10-3 2"/>',
    banco: '<ellipse cx="0" cy="-7" rx="10" ry="3.5"/><path d="M-10-7v14c0 2 4.5 3.5 10 3.5s10-1.5 10-3.5V-7M-10 0c0 2 4.5 3.5 10 3.5S10 2 10 0"/>',
    tela: '<rect x="-11" y="-9" width="22" height="15" rx="2.5"/><path d="M-5 11h10M0 6v5"/>',
    engrenagem: '<circle cx="0" cy="0" r="3.5"/><path d="M0-11v4M0 7v4M-11 0h4M7 0h4M-7.8-7.8l2.8 2.8M5 5l2.8 2.8M-7.8 7.8 5-5M5 -5l2.8-2.8"/>',
    porta: '<rect x="-8" y="-11" width="16" height="22" rx="2"/><path d="M3 0h.01"/>',
    cerebro: '<path d="M-2-10c-4 0-7 3-7 6-2 1-3 3-3 5 0 3 2 5 5 5 1 2 3 3 5 3V-10zM2-10c4 0 7 3 7 6 2 1 3 3 3 5 0 3-2 5-5 5-1 2-3 3-5 3V-10z"/>'
  };

  var NS = "http://www.w3.org/2000/svg";
  var porId = {};
  NOS.forEach(function (n) { porId[n.id] = n; });

  function el(nome, attrs, pai) {
    var e = document.createElementNS(NS, nome);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (pai) pai.appendChild(e);
    return e;
  }
  function raio(n) { return n.grande ? 38 : 29; }

  function caminho(a, b, op) {
    var ra = raio(a), rb = raio(b);
    var dir = b.x >= a.x ? 1 : -1;
    var x1 = a.x + ra * dir, y1 = a.y, x2 = b.x - rb * dir, y2 = b.y;
    if (op && op.via != null) {
      var v = op.via, k = 70 * dir;
      return "M" + x1 + "," + y1 + " C" + (x1 + k) + "," + y1 + " " + (x1 + k) + "," + v + " " + (x1 + 2 * k) + "," + v +
             " L" + (x2 - 2 * k) + "," + v + " C" + (x2 - k) + "," + v + " " + (x2 - k) + "," + y2 + " " + x2 + "," + y2;
    }
    if (a.x === b.x) {   // mesma coluna: um arco para o lado
      var lado = a.x + 70;
      x1 = a.x + ra; x2 = b.x + rb;
      return "M" + x1 + "," + y1 + " C" + lado + "," + y1 + " " + lado + "," + y2 + " " + x2 + "," + y2;
    }
    var m = (x2 - x1) * 0.5;
    return "M" + x1 + "," + y1 + " C" + (x1 + m) + "," + y1 + " " + (x2 - m) + "," + y2 + " " + x2 + "," + y2;
  }

  function desenhar() {
    var svg = document.getElementById("vg-mapa");
    var defs = el("defs", {}, svg);
    // as cores de cada etapa em degradê (o brilho de vidro de cada bolinha)
    Object.keys(ETAPAS).forEach(function (k) {
      var g = el("radialGradient", { id: "vg-g-" + k, cx: "35%", cy: "30%", r: "75%" }, defs);
      el("stop", { offset: "0%", "stop-color": "#ffffff", "stop-opacity": "0.55" }, g);
      el("stop", { offset: "38%", "stop-color": ETAPAS[k].cor, "stop-opacity": "0.92" }, g);
      el("stop", { offset: "100%", "stop-color": ETAPAS[k].cor, "stop-opacity": "1" }, g);
    });
    var sombra = el("filter", { id: "vg-sombra", x: "-50%", y: "-50%", width: "200%", height: "200%" }, defs);
    el("feDropShadow", { dx: "0", dy: "6", stdDeviation: "7", "flood-color": "#1b1f3b", "flood-opacity": "0.18" }, sombra);

    var gPaineis = el("g", { class: "vg-paineis" }, svg);
    PAINEIS.forEach(function (p) {
      el("rect", { x: p.x, y: p.y, width: p.w, height: p.h, rx: 30, class: "vg-painel vg-painel--" + p.id }, gPaineis);
      var t = el("text", { x: p.x + 24, y: p.y + 30, class: "vg-painel__titulo" }, gPaineis);
      t.textContent = p.titulo;
      var s = el("text", { x: p.x + 24, y: p.y + 49, class: "vg-painel__sub" }, gPaineis);
      s.textContent = p.sub;
    });

    var gLig = el("g", { class: "vg-ligacoes" }, svg);
    LIGACOES.forEach(function (l, i) {
      var a = porId[l[0]], b = porId[l[1]], op = l[2] || {};
      var d = caminho(a, b, op);
      var cor = ETAPAS[a.etapa].cor;
      var classe = "vg-lig" + (op.tracejada ? " vg-lig--tracejada" : "") + (op.ia ? " vg-lig--ia" : "");
      var p = el("path", { d: d, class: classe, stroke: cor, "data-de": a.id, "data-para": b.id }, gLig);
      p.style.animationDelay = (-(i * 0.37) % 3) + "s";
      if (op.rotulo) {
        var t = el("text", { class: "vg-lig__rotulo" }, gLig);
        t.setAttribute("x", (a.x + b.x) / 2);
        t.setAttribute("y", (a.y + b.y) / 2 - 10);
        t.textContent = op.rotulo;
      }
    });

    var gNos = el("g", { class: "vg-nos" }, svg);
    NOS.forEach(function (n) {
      var r = raio(n);
      var g = el("g", { class: "vg-no", transform: "translate(" + n.x + "," + n.y + ")", "data-id": n.id, "data-etapa": n.etapa,
                        tabindex: "0", role: "button", "aria-label": n.nome + ": " + n.info }, gNos);
      el("circle", { r: r + 7, class: "vg-no__halo", fill: ETAPAS[n.etapa].cor }, g);
      el("circle", { r: r, fill: "url(#vg-g-" + n.etapa + ")", filter: "url(#vg-sombra)", class: "vg-no__bola" }, g);
      el("circle", { r: r - 1.5, class: "vg-no__vidro" }, g);
      var ic = el("g", { class: "vg-no__icone", transform: n.grande ? "scale(1.25)" : "" }, g);
      ic.innerHTML = ICONES[n.icone] || "";
      var nome = el("text", { y: r + 20, class: "vg-no__nome" }, g);
      nome.textContent = n.nome;
      var sub = el("text", { y: r + 36, class: "vg-no__sub" }, g);
      sub.textContent = n.sub;
      // o (i)
      var i = el("g", { class: "vg-no__info", transform: "translate(" + (r * 0.72) + "," + (-r * 0.72) + ")", "data-info": n.id }, g);
      el("circle", { r: 9 }, i);
      var ti = el("text", { y: 3.6 }, i);
      ti.textContent = "i";
    });
  }

  /* ── o (i): uma frase, perto da bolinha ── */
  var balao, aberto = null;
  function posicaoNaTela(n) {
    var svg = document.getElementById("vg-mapa");
    var pt = svg.createSVGPoint();
    pt.x = n.x; pt.y = n.y;
    var t = pt.matrixTransform(svg.getScreenCTM());
    var caixa = document.getElementById("vg-palco").getBoundingClientRect();
    var esc = svg.getScreenCTM().a;
    return { x: t.x - caixa.left + document.getElementById("vg-palco").scrollLeft, y: t.y - caixa.top, r: raio(n) * esc };
  }
  function abrirInfo(id) {
    var n = porId[id];
    if (!n) return;
    if (aberto === id) { fecharInfo(); return; }
    aberto = id;
    var e = ETAPAS[n.etapa];
    balao.innerHTML = '<span class="vg-balao__etapa" style="--c:' + e.cor + '">' + e.nome + "</span>" +
      "<strong>" + n.nome + "</strong><p>" + n.info + "</p>" +
      '<span class="vg-balao__onde">' + (n.vps ? "VPS" + n.vps + " · " : "") + n.sub + "</span>";
    balao.hidden = false;
    var p = posicaoNaTela(n);
    var largura = balao.offsetWidth, palco = document.getElementById("vg-palco");
    var x = Math.min(Math.max(p.x - largura / 2, palco.scrollLeft + 8), palco.scrollLeft + palco.clientWidth - largura - 8);
    var y = p.y - p.r - balao.offsetHeight - 12;
    if (y < 8) y = p.y + p.r + 48;
    balao.style.left = x + "px";
    balao.style.top = y + "px";
  }
  function fecharInfo() { aberto = null; if (balao) balao.hidden = true; }

  /* ── foco: a bolinha clicada acende ela e as ligações dela; a legenda acende uma etapa ── */
  var focoAtual = null;
  function focar(id, etapa) {
    var svg = document.getElementById("vg-mapa");
    var chave = id || (etapa ? "etapa:" + etapa : null);
    if (focoAtual === chave) chave = null;
    focoAtual = chave;
    svg.classList.toggle("vg-com-foco", !!chave);
    var vizinhos = {};
    if (id) {
      vizinhos[id] = true;
      LIGACOES.forEach(function (l) { if (l[0] === id) vizinhos[l[1]] = true; if (l[1] === id) vizinhos[l[0]] = true; });
    }
    Array.prototype.forEach.call(svg.querySelectorAll(".vg-no"), function (g) {
      var on = !chave ? false : id ? !!vizinhos[g.getAttribute("data-id")] : g.getAttribute("data-etapa") === etapa;
      g.classList.toggle("vg-aceso", on);
    });
    Array.prototype.forEach.call(svg.querySelectorAll(".vg-lig"), function (p) {
      var de = p.getAttribute("data-de"), para = p.getAttribute("data-para");
      var on = !chave ? false : id ? (de === id || para === id)
             : (porId[de].etapa === etapa || porId[para].etapa === etapa);
      p.classList.toggle("vg-aceso", on);
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-vg-etapa]"), function (b) {
      b.setAttribute("aria-pressed", etapa && b.getAttribute("data-vg-etapa") === etapa && chave ? "true" : "false");
    });
  }

  function legenda() {
    var cont = {};
    NOS.forEach(function (n) { cont[n.etapa] = (cont[n.etapa] || 0) + 1; });
    document.getElementById("vg-legenda").innerHTML = Object.keys(ETAPAS).map(function (k) {
      var e = ETAPAS[k];
      return '<button type="button" class="vg-chip" data-vg-etapa="' + k + '" aria-pressed="false" style="--c:' + e.cor + '" title="' + e.info + '">' +
             '<i></i>' + e.nome + "<b>" + (cont[k] || 0) + "</b></button>";
    }).join("");
    // os números grandes, como anel (o estilo dos componentes de infográfico)
    var nays = NOS.filter(function (n) { return n.etapa === "nays"; }).length;
    var canais = NOS.filter(function (n) { return n.etapa === "canais"; }).length;
    var telas = NOS.filter(function (n) { return n.etapa === "telas"; }).length;
    var aneis = [
      { n: 2, rot: "VPS", cor: ETAPAS.dados.cor, p: 100 },
      { n: nays, rot: "Nays e agentes", cor: ETAPAS.nays.cor, p: 82 },
      { n: canais, rot: "canais", cor: ETAPAS.canais.cor, p: 64 },
      { n: telas, rot: "telas", cor: ETAPAS.telas.cor, p: 47 },
      { n: 1, rot: "banco central", cor: ETAPAS.envio.cor, p: 32 }
    ];
    document.getElementById("vg-numeros").innerHTML = aneis.map(function (a) {
      return '<div class="vg-anel" style="--c:' + a.cor + ";--p:" + a.p + '"><span>' + a.n + "</span><small>" + a.rot + "</small></div>";
    }).join("");
  }

  function ligar() {
    balao = document.getElementById("vg-balao");
    var svg = document.getElementById("vg-mapa");
    svg.addEventListener("click", function (ev) {
      var info = ev.target.closest("[data-info]");
      if (info) { ev.stopPropagation(); abrirInfo(info.getAttribute("data-info")); return; }
      var no = ev.target.closest(".vg-no");
      if (no) { focar(no.getAttribute("data-id")); abrirInfo(no.getAttribute("data-id")); return; }
      focar(null); fecharInfo();
    });
    svg.addEventListener("keydown", function (ev) {
      var no = ev.target.closest && ev.target.closest(".vg-no");
      if (no && (ev.key === "Enter" || ev.key === " ")) { ev.preventDefault(); focar(no.getAttribute("data-id")); abrirInfo(no.getAttribute("data-id")); }
      if (ev.key === "Escape") { focar(null); fecharInfo(); }
    });
    document.getElementById("vg-legenda").addEventListener("click", function (ev) {
      var b = ev.target.closest("[data-vg-etapa]");
      if (!b) return;
      fecharInfo();
      focar(null, b.getAttribute("data-vg-etapa"));
    });
    document.getElementById("vg-palco").addEventListener("scroll", fecharInfo, { passive: true });
    window.addEventListener("resize", fecharInfo);
  }

  // dentro do CRM a página vem num quadro: o CRM põe crm-escuro / crm-claro no <html> (painelDoSiteTema.ts)
  // ?escuro mostra o tema do CRM escuro fora do CRM (para conferir)
  if (/[?&]escuro/.test(location.search)) document.documentElement.classList.add("crm-escuro");
  desenhar();
  legenda();
  ligar();
  // #banco (ou outro id) no endereço já abre com aquela bolinha acesa
  var pedido = decodeURIComponent((location.hash || "").slice(1));
  if (porId[pedido]) {
    focar(pedido);
    requestAnimationFrame(function () { try { abrirInfo(pedido); } catch (e) { /* sem layout ainda: fica só o foco */ } });
  }
})();
