/* VISÃO GERAL (Pedro, 15/10/2026). Três versões no mesmo dia:
   1ª "organize todo o meu projeto e recursos na VPS em um fluxograma conectado ... (i) ... clean, glass".
   2ª "não quero os bancos ou rotinas ou funções, só os locais humanamente acessíveis em que humanos ou IA usam ... um
      fluxo horizontal ... o CRM uma bolona e essas partes dentro ... nada antigo ... a captação na frente, como a jornada
      do lead ... formas geométricas diferentes ... títulos com mais destaque".
   3ª, a de agora: "ficou em ordem, mas deixou de ser um fluxograma: quero as coisas divididas em formas geométricas
      menores, ligadas uma à outra; por exemplo a etapa 3 na verdade é um extra da etapa 1, ambas se ligam ao CRM direto".

   Cada coisa é uma forma pequena: canal = hexágono, grupos e anúncios = losango, site = quadrado, aba do CRM = pílula
   dentro da bolona, Nay = hexagoninho roxo colado ao lugar onde trabalha, pessoa = círculo. A linha sai de cada forma e
   entra na aba do CRM que recebe aquilo. Mudou a estrutura: mexe em BLOCOS, NOS e LIGACOES (x, y no desenho de 1640 x 930). */
(function () {
  "use strict";

  var COR = { captacao: "#8e1e4b", divulgacao: "#1d9bd7", site: "#1f4e79", crm: "#f39c12", fechamento: "#e8475f",
              pessoas: "#64748b", ia: "#7b61ff", extra: "#2bb5b8" };

  // as áreas de fundo, cada uma com o título grande
  var BLOCOS = [
    { x: 160, y: 24,  w: 420, h: 392, cor: COR.captacao,   kicker: "Etapa 1",           titulo: "Captação" },
    { x: 160, y: 436, w: 420, h: 290, cor: COR.divulgacao, kicker: "Extra da captação", titulo: "Divulgação" },
    { x: 160, y: 746, w: 420, h: 170, cor: COR.site,       kicker: "Cadastro",          titulo: "Site" }
  ];

  var NOS = [
    // pessoas
    { id: "donos",      tipo: "pessoa", x: 78, y: 236, nome: "Proprietários", cor: COR.pessoas, info: "Donos dos imóveis: confirmam situação, valor e dados." },
    { id: "corretores", tipo: "pessoa", x: 78, y: 540, nome: "Corretores",    cor: COR.pessoas, info: "Parceiros que pedem e oferecem imóveis." },
    { id: "clientes",   tipo: "pessoa", x: 78, y: 656, nome: "Clientes",      cor: COR.pessoas, info: "Quem chama nos nossos anúncios da OLX." },
    { id: "equipe",     tipo: "pessoa", x: 78, y: 856, nome: "Equipe",        cor: COR.pessoas, info: "Tel, Pedro e Rayssa." },

    // 1 · captação
    { id: "oficial",  tipo: "hex", x: 350, y: 130, w: 200, h: 54, nome: "Número oficial",     sub: "Meta · 8456-0874",  cor: COR.captacao, info: "Número oficial da Meta: a captação com modelos aprovados." },
    { id: "imobeasy", tipo: "hex", x: 350, y: 236, w: 200, h: 54, nome: "WhatsApp Imob Easy", sub: "Z-API · 8595-6408", cor: COR.captacao, info: "O WhatsApp da equipe; a Rayssa atende por ele." },
    { id: "donosolx", tipo: "hex", x: 350, y: 336, w: 200, h: 54, nome: "Donos da OLX",       sub: "pela Parceria",     cor: COR.captacao, info: "Quem deixou o contato na OLX, chamado no WhatsApp da Parceria." },
    { id: "ia-capt",  tipo: "ia", junto: "oficial",  x: 270, y: 176, nome: "Nay captação",  info: "Pergunta ao dono a situação, o valor e as fotos do imóvel." },
    { id: "ia-dolx",  tipo: "ia", junto: "donosolx",  x: 270, y: 380, nome: "Nay donos OLX", info: "Confirma os dados de quem deixou o contato na OLX." },

    // extra · divulgação
    { id: "grupos",   tipo: "losango", x: 350, y: 540, w: 210, h: 66, nome: "Grupos",       sub: "WhatsApp", cor: COR.divulgacao, info: "Grupos de corretores: onde postamos e lemos pedidos." },
    { id: "anuncios", tipo: "losango", x: 350, y: 656, w: 210, h: 66, nome: "Anúncios OLX", sub: "OLX",      cor: COR.divulgacao, info: "Os nossos anúncios na OLX." },
    { id: "ia-pub",   tipo: "ia", junto: "grupos", x: 196, y: 592, nome: "Publicador",     info: "Posta os imóveis e as listas nos grupos, na grade." },
    { id: "ia-grp",   tipo: "ia", junto: "grupos", x: 345, y: 592, nome: "Nay dos grupos", info: "Lê os pedidos dos corretores e acha imóvel nosso que serve." },
    { id: "ia-aolx",  tipo: "ia", junto: "anuncios", x: 290, y: 702, nome: "Agente OLX",     info: "Trabalha no site da OLX pelo navegador." },

    // cadastro · site
    { id: "site", tipo: "quadrado", x: 350, y: 856, w: 200, h: 64, nome: "Admin do site", sub: "imóveis e donos", cor: COR.site, info: "Onde a equipe cadastra e cuida dos imóveis e proprietários." },

    // o CRM: a bolona e as abas dentro
    { id: "crm", tipo: "bolona", x: 1010, y: 470, r: 390, nome: "CRM", sub: "crm.imobeasy.online · VPS1", cor: COR.crm, info: "Todas as conversas e o funil, do primeiro contato até a visita." },
    { id: "t-oficial",  tipo: "pilula", x: 880,  y: 150, w: 120, h: 38, nome: "Oficial",    cor: COR.crm, info: "As conversas do número oficial." },
    { id: "t-captacao", tipo: "pilula", x: 790,  y: 248, w: 120, h: 38, nome: "Captação",   cor: COR.crm, info: "As conversas do WhatsApp da Imob Easy." },
    { id: "t-parceria", tipo: "pilula", x: 740,  y: 352, w: 120, h: 38, nome: "Parceria",   cor: COR.crm, info: "Os corretores e os donos da OLX, no número da Parceria." },
    { id: "t-grupos",   tipo: "pilula", x: 712,  y: 540, w: 120, h: 38, nome: "Grupos",     cor: COR.crm, info: "As mensagens dos grupos." },
    { id: "t-olx",      tipo: "pilula", x: 740,  y: 656, w: 120, h: 38, nome: "Chat OLX",   cor: COR.crm, info: "O chat dos anúncios da OLX." },
    { id: "t-imoveis",  tipo: "pilula", x: 850,  y: 790, w: 120, h: 38, nome: "Imóveis",    cor: COR.crm, info: "O acervo do site, aqui dentro." },
    { id: "t-pipeline", tipo: "pilula", x: 1248, y: 470, w: 130, h: 42, nome: "Pipeline",   cor: COR.crm, info: "O funil de cada lead, até a visita." },
    { id: "t-corret",   tipo: "pilula", x: 1180, y: 240, w: 130, h: 38, nome: "Corretores", cor: COR.crm, info: "Os corretores parceiros e as métricas." },
    { id: "ia-parc",    tipo: "ia", junto: "t-parceria", x: 860, y: 400, nome: "Nay Parceria", info: "Atende os corretores: entende o pedido, manda card e fotos, marca visita." },
    { id: "ia-olx",     tipo: "ia", junto: "t-olx", x: 878, y: 702, nome: "Nay OLX",      info: "Responde quem chama no chat dos anúncios." },
    { id: "rayssa",     tipo: "pessoa", x: 1010, y: 560, nome: "Rayssa", pequena: true, cor: COR.pessoas, info: "Atende, marca as visitas e fecha." },
    { id: "tel",        tipo: "pessoa", x: 1100, y: 560, nome: "Tel",    pequena: true, cor: COR.pessoas, info: "Dono da imobiliária; comanda a Nay." },

    // depois do CRM
    { id: "financas", tipo: "pilula", x: 1510, y: 470, w: 190, h: 66, nome: "Finanças", sub: "fechamento · VPS2", cor: COR.fechamento, grande: true, info: "O controle financeiro depois do fechamento." },
    { id: "portal",   tipo: "pilula", x: 1510, y: 210, w: 190, h: 54, nome: "Portal do corretor", sub: "VPS2", cor: COR.extra, info: "A área do corretor parceiro." },
    { id: "lembretes", tipo: "ia", x: 1440, y: 770, nome: "Lembretes · VPS2", info: "Agente que guarda e manda os lembretes da equipe, pelo WhatsApp." }
  ];

  var LIGACOES = [
    ["donos", "oficial"], ["donos", "imobeasy"], ["donos", "donosolx"],
    ["corretores", "grupos"], ["clientes", "anuncios"], ["equipe", "site"],
    ["oficial", "t-oficial"], ["imobeasy", "t-captacao"], ["donosolx", "t-parceria"],
    ["grupos", "t-grupos"], ["grupos", "t-parceria", { rotulo: "chamam no privado" }], ["anuncios", "t-olx"],
    ["site", "t-imoveis"],
    ["t-pipeline", "financas"], ["t-corret", "portal", { tracejada: true }]
  ];
  // as ligações entre blocos (pontos soltos): a divulgação é extra da captação, e o site alimenta a divulgação
  var ENTRE_BLOCOS = [
    { de: [540, 416], para: [540, 436], rotulo: "extra", cor: COR.captacao },
    { de: [540, 746], para: [540, 726], rotulo: "imóveis para divulgar", cor: COR.site }
  ];

  var NS = "http://www.w3.org/2000/svg";
  var porId = {};
  NOS.forEach(function (n) { porId[n.id] = n; });
  function el(nome, attrs, pai, texto) {
    var e = document.createElementNS(NS, nome);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (texto != null) e.textContent = texto;
    if (pai) pai.appendChild(e);
    return e;
  }
  function meiaLargura(n) {
    if (n.tipo === "pessoa") return n.pequena ? 16 : 22;
    if (n.tipo === "ia") return 13;
    if (n.tipo === "bolona") return n.r;
    return n.w / 2;
  }
  function caminho(a, b) {
    var dir = b.x >= a.x ? 1 : -1;
    var x1 = a.x + meiaLargura(a) * dir, x2 = b.x - meiaLargura(b) * dir;
    var m = (x2 - x1) * 0.5;
    return "M" + x1 + "," + a.y + " C" + (x1 + m) + "," + a.y + " " + (x2 - m) + "," + b.y + " " + (x2 - 6 * dir) + "," + b.y;
  }
  var PESSOA = '<circle cx="0" cy="-4" r="4.5"/><path d="M-8 9c1.3-4.2 4.4-6 8-6s6.7 1.8 8 6"/>';
  var ROBO = '<rect x="-6.5" y="-3.5" width="13" height="10" rx="2.6"/><path d="M0-3.5v-3.2M-2.6 1.5h.01M2.6 1.5h.01"/>';

  function hexPontos(w, h) {
    var c = Math.min(18, h / 2);
    return [[-w / 2, 0], [-w / 2 + c, -h / 2], [w / 2 - c, -h / 2], [w / 2, 0], [w / 2 - c, h / 2], [-w / 2 + c, h / 2]].map(function (p) { return p.join(","); }).join(" ");
  }
  function botaoInfo(g, n, dx, dy) {
    var i = el("g", { class: "vg-i", transform: "translate(" + dx + "," + dy + ")", "data-info": n.id }, g);
    el("circle", { r: 8.5 }, i);
    el("text", { y: 3.4 }, i, "i");
  }

  function forma(gNos, n) {
    var g = el("g", { class: "vg-no vg-no--" + n.tipo, transform: "translate(" + n.x + "," + n.y + ")", "data-id": n.id,
                      tabindex: "0", role: "button", "aria-label": n.nome + ": " + n.info, style: "--c:" + (n.cor || COR.ia) }, gNos);
    if (n.tipo === "bolona") {
      el("circle", { r: n.r, class: "vg-bolona" }, g);
      el("text", { y: -n.r + 92, class: "vg-bolona__titulo" }, g, n.nome);
      el("text", { y: -n.r + 118, class: "vg-bolona__sub" }, g, n.sub);
      botaoInfo(g, n, 72, -n.r + 74);
      return;
    }
    if (n.tipo === "pessoa") {
      var r = n.pequena ? 16 : 22;
      el("circle", { r: r, class: "vg-forma" }, g);
      el("g", { class: "vg-icone", transform: n.pequena ? "scale(.8)" : "" }, g).innerHTML = PESSOA;
      el("text", { y: r + 17, class: "vg-rotulo vg-rotulo--fora" }, g, n.nome);
      if (!n.pequena) botaoInfo(g, n, r * .75, -r * .75);
      return;
    }
    if (n.tipo === "ia") {
      el("polygon", { points: "0,-14 12.1,-7 12.1,7 0,14 -12.1,7 -12.1,-7", class: "vg-ia" }, g);
      el("g", { class: "vg-icone" }, g).innerHTML = ROBO;
      el("text", { x: 20, y: 4.5, class: "vg-ia__nome" }, g, n.nome);
      return;
    }
    if (n.tipo === "hex") el("polygon", { points: hexPontos(n.w, n.h), class: "vg-forma" }, g);
    if (n.tipo === "losango") el("polygon", { points: [[-n.w / 2, 0], [0, -n.h / 2], [n.w / 2, 0], [0, n.h / 2]].map(function (p) { return p.join(","); }).join(" "), class: "vg-forma" }, g);
    if (n.tipo === "quadrado") el("rect", { x: -n.w / 2, y: -n.h / 2, width: n.w, height: n.h, rx: 14, class: "vg-forma" }, g);
    if (n.tipo === "pilula") el("rect", { x: -n.w / 2, y: -n.h / 2, width: n.w, height: n.h, rx: n.h / 2, class: "vg-forma" + (n.grande ? " vg-forma--cheia" : "") }, g);
    var dy = n.sub ? -2 : 5;
    el("text", { y: dy, class: "vg-rotulo" + (n.grande ? " vg-rotulo--grande" : "") }, g, n.nome);
    if (n.sub) el("text", { y: dy + 15, class: "vg-rotulo__sub" }, g, n.sub);
    if (n.tipo !== "pilula" || n.grande || n.id === "portal") botaoInfo(g, n, n.w / 2 - (n.tipo === "losango" ? 40 : 10), -n.h / 2 + (n.tipo === "losango" ? 14 : 4));
  }

  function desenhar() {
    var svg = document.getElementById("vg-mapa");
    var defs = el("defs", {}, svg);
    Object.keys(COR).forEach(function (k) {
      var m = el("marker", { id: "vg-seta-" + k, viewBox: "0 0 10 10", refX: "8", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto-start-reverse" }, defs);
      el("path", { d: "M0,1 L9,5 L0,9 z", fill: COR[k] }, m);
    });
    var corDe = function (cor) { return Object.keys(COR).filter(function (k) { return COR[k] === cor; })[0] || "pessoas"; };

    var gBlocos = el("g", {}, svg);
    BLOCOS.forEach(function (b) {
      el("rect", { x: b.x, y: b.y, width: b.w, height: b.h, rx: 26, class: "vg-bloco", style: "--c:" + b.cor }, gBlocos);
      el("text", { x: b.x + 22, y: b.y + 26, class: "vg-bloco__kicker", style: "--c:" + b.cor }, gBlocos, b.kicker.toUpperCase());
      el("text", { x: b.x + 22, y: b.y + 56, class: "vg-bloco__titulo", style: "--c:" + b.cor }, gBlocos, b.titulo);
    });

    var gLig = el("g", {}, svg);
    // o CRM vem antes das linhas, para as linhas entrarem por cima da bolona
    var gCrm = el("g", {}, svg);
    forma(gCrm, porId.crm);
    var gLig2 = el("g", {}, svg);
    LIGACOES.forEach(function (l) {
      var a = porId[l[0]], b = porId[l[1]], op = l[2] || {};
      var k = corDe(a.cor);
      var p = el("path", { d: caminho(a, b), class: "vg-lig" + (op.tracejada ? " vg-lig--tracejada" : ""), stroke: a.cor,
                           "marker-end": "url(#vg-seta-" + k + ")", "data-de": a.id, "data-para": b.id }, gLig2);
      if (op.rotulo) {
        var meio = p.getPointAtLength(p.getTotalLength() * 0.62);
        el("text", { x: meio.x, y: meio.y - 7, class: "vg-lig__rotulo" }, gLig2, op.rotulo);
      }
    });
    ENTRE_BLOCOS.forEach(function (e) {
      el("path", { d: "M" + e.de.join(",") + " L" + e.para.join(","), class: "vg-lig vg-lig--tracejada vg-lig--bloco", stroke: e.cor,
                   "marker-end": "url(#vg-seta-" + corDe(e.cor) + ")" }, gLig);
      el("text", { x: e.de[0] - 8, y: (e.de[1] + e.para[1]) / 2 + 4, class: "vg-lig__rotulo vg-lig__rotulo--dir" }, gLig, e.rotulo);
    });

    var gNos = el("g", {}, svg);
    NOS.forEach(function (n) { if (n.id !== "crm") forma(gNos, n); });
  }

  /* ── o (i) e o foco ── */
  var balao, aberto = null, focoAtual = null;
  function abrirInfo(id) {
    var n = porId[id];
    if (!n) return;
    if (aberto === id) { fecharInfo(); return; }
    aberto = id;
    balao.innerHTML = "<strong>" + n.nome + "</strong><p>" + n.info + "</p>";
    balao.hidden = false;
    var svg = document.getElementById("vg-mapa"), palco = document.getElementById("vg-palco");
    var pt = svg.createSVGPoint(); pt.x = n.x; pt.y = n.y;
    var t = pt.matrixTransform(svg.getScreenCTM()), caixa = palco.getBoundingClientRect(), esc = svg.getScreenCTM().a;
    var meia = (n.tipo === "bolona" ? n.r - 60 : (n.h || 40) / 2) * esc;
    var x = t.x - caixa.left + palco.scrollLeft - balao.offsetWidth / 2;
    x = Math.max(palco.scrollLeft + 8, Math.min(x, palco.scrollLeft + palco.clientWidth - balao.offsetWidth - 8));
    var y = t.y - caixa.top - meia - balao.offsetHeight - 10;
    if (n.tipo === "bolona") y = t.y - caixa.top - n.r * esc + 130 * esc;
    if (y < 6) y = t.y - caixa.top + meia + 12;
    balao.style.left = x + "px";
    balao.style.top = y + "px";
  }
  function fecharInfo() { aberto = null; balao.hidden = true; }
  function focar(id) {
    var svg = document.getElementById("vg-mapa");
    if (focoAtual === id || id === "crm") id = null;
    focoAtual = id;
    svg.classList.toggle("vg-com-foco", !!id);
    var viz = {};
    if (id) {
      viz[id] = true;
      LIGACOES.forEach(function (l) { if (l[0] === id) viz[l[1]] = true; if (l[1] === id) viz[l[0]] = true; });
      // a Nay acende junto com o lugar onde trabalha (e o lugar, com as Nays dele)
      if (porId[id].junto) viz[porId[id].junto] = true;
      NOS.forEach(function (n) { if (n.junto && viz[n.junto]) viz[n.id] = true; });
    }
    Array.prototype.forEach.call(svg.querySelectorAll(".vg-no"), function (g) { g.classList.toggle("vg-aceso", !!viz[g.getAttribute("data-id")]); });
    Array.prototype.forEach.call(svg.querySelectorAll(".vg-lig[data-de]"), function (p) {
      p.classList.toggle("vg-aceso", !!id && (p.getAttribute("data-de") === id || p.getAttribute("data-para") === id));
    });
  }

  if (/[?&]escuro/.test(location.search)) document.documentElement.classList.add("crm-escuro");
  desenhar();
  balao = document.getElementById("vg-balao");
  var svg = document.getElementById("vg-mapa");
  svg.addEventListener("click", function (ev) {
    var i = ev.target.closest("[data-info]");
    if (i) { ev.stopPropagation(); abrirInfo(i.getAttribute("data-info")); return; }
    var no = ev.target.closest(".vg-no");
    if (no) { focar(no.getAttribute("data-id")); abrirInfo(no.getAttribute("data-id")); return; }
    focar(null); fecharInfo();
  });
  svg.addEventListener("keydown", function (ev) {
    var no = ev.target.closest && ev.target.closest(".vg-no");
    if (no && (ev.key === "Enter" || ev.key === " ")) { ev.preventDefault(); focar(no.getAttribute("data-id")); abrirInfo(no.getAttribute("data-id")); }
    if (ev.key === "Escape") { focar(null); fecharInfo(); }
  });
  document.getElementById("vg-palco").addEventListener("scroll", fecharInfo, { passive: true });
  window.addEventListener("resize", fecharInfo);
  var pedido = decodeURIComponent((location.hash || "").slice(1));
  if (porId[pedido]) { focar(pedido); requestAnimationFrame(function () { try { abrirInfo(pedido); } catch (e) { /* sem layout */ } }); }
})();
