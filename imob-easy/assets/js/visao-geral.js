/* VISÃO GERAL (Pedro, 15/10/2026).
   1ª versão: "organize todo o meu projeto e recursos na VPS em um fluxograma conectado, todas as Nays e onde elas
   estão ... bonito e com cores por etapas ... com (i) ... clean, glass".
   2ª versão, a de agora (o mesmo dia): "tá muito confuso, não quero os bancos ou rotinas ou funções, só os locais
   humanamente acessíveis em que humanos ou IA usam, e que não fique cheio de cabos, e sim um fluxo horizontal: parceria,
   grupos, isso tudo fica no CRM, pode ser o CRM uma bolona e essas partes dentro ... nem a Nay velha ... não deixa nada
   antigo ... a captação deve ficar na frente, como a jornada do lead da esquerda para a direita ... as bolinhas muito
   chamativas, diminui o brilho, usa formas geométricas diferentes para recursos diferentes, e os títulos com mais
   destaque".

   Uma estação por LUGAR, na ordem da jornada; dentro dela, as partes (etiquetas), as Nays (hexágonos) e as pessoas
   (círculos). Uma seta entre as estações e mais nada. Mudou a estrutura: mexe em ESTACOES e TAMBEM. */
(function () {
  "use strict";

  var ESTACOES = [
    { id: "captacao", passo: "Captação", titulo: "Captação", forma: "hexagono", cor: "#8e1e4b", onde: ["VPS1", "VPS2"],
      sub: "WhatsApp e OLX", info: "Onde o dono do imóvel chega e a Nay confirma os dados do imóvel.",
      partes: ["Número oficial", "WhatsApp Imob Easy", "Donos da OLX"],
      ias: [{ nome: "Nay captação", info: "Pergunta ao dono a situação, o valor e as fotos do imóvel." },
            { nome: "Nay donos OLX", info: "Confirma os dados de quem deixou o contato na OLX, pela Parceria." }],
      pessoas: ["Proprietários", "Rayssa"] },
    { id: "site", passo: "Cadastro", titulo: "Site", forma: "quadrado", cor: "#1f4e79", onde: ["VPS1"],
      sub: "imobeasy.online", info: "O catálogo público e o admin onde a equipe cadastra e cuida dos imóveis.",
      partes: ["Catálogo", "Imóveis", "Proprietários", "Captação", "Grupos", "Agentes"],
      ias: [], pessoas: ["Tel", "Pedro"] },
    { id: "divulgacao", passo: "Divulgação", titulo: "Divulgação", forma: "octogono", cor: "#1d9bd7", onde: ["VPS1", "VPS2"],
      sub: "grupos e anúncios", info: "Onde os imóveis aparecem para corretores e clientes.",
      partes: ["Grupos de WhatsApp", "Anúncios na OLX"],
      ias: [{ nome: "Publicador", info: "Posta os imóveis e as listas nos grupos, nos horários da grade." },
            { nome: "Nay dos grupos", info: "Lê os pedidos dos corretores nos grupos e acha imóvel nosso que serve." },
            { nome: "Agente OLX", info: "Trabalha no site da OLX pelo navegador." }],
      pessoas: ["Corretores"] },
    { id: "crm", passo: "Atendimento e visita", titulo: "CRM", forma: "bolona", cor: "#f39c12", onde: ["VPS1"],
      sub: "crm.imobeasy.online", info: "Todas as conversas e o funil, do primeiro contato até a visita.",
      partes: ["Parceria", "Oficial", "Captação", "Grupos", "Chat OLX", "Pipeline", "Imóveis", "Corretores"],
      ias: [{ nome: "Nay Parceria", info: "Atende os corretores: entende o pedido, manda card e fotos, marca visita." },
            { nome: "Nay OLX", info: "Responde quem chama no chat dos anúncios da OLX." }],
      pessoas: ["Rayssa", "Tel", "Corretores", "Clientes"] },
    { id: "financas", passo: "Fechamento", titulo: "Finanças", forma: "pilula", cor: "#e8475f", onde: ["VPS2"],
      sub: "financas.imobeasy.online", info: "O controle financeiro depois do fechamento.",
      partes: ["Controle financeiro"], ias: [], pessoas: ["Tel"] }
  ];

  // os lugares que existem e não estão na jornada do lead
  var TAMBEM = [
    { titulo: "Portal do corretor", sub: "app.imobeasy.online", onde: "VPS2", forma: "pilula", cor: "#2bb5b8", info: "A área do corretor parceiro." },
    { titulo: "Lembretes", sub: "pelo WhatsApp", onde: "VPS2", forma: "hexagono", cor: "#7b61ff", ia: true, info: "Agente que guarda e manda os lembretes da equipe." }
  ];

  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function iniciais(nome) {
    var p = String(nome).split(/\s+/);
    return (p.length > 1 ? p[0][0] + p[1][0] : p[0].slice(0, 2)).toUpperCase();
  }
  var EQUIPE = ["Tel", "Pedro", "Rayssa"];
  var PESSOA = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="9" r="3.5"/><path d="M5.5 19c1.2-3.3 3.6-5 6.5-5s5.3 1.7 6.5 5"/></svg>';
  var ROBO = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="8" width="14" height="10" rx="3"/><path d="M12 8V5M9 13h.01M15 13h.01"/></svg>';
  function info(texto, rotulo) {
    return '<button type="button" class="vg-i" data-vg-info="' + esc(texto) + '" data-vg-titulo="' + esc(rotulo) + '" aria-label="O que é ' + esc(rotulo) + '">i</button>';
  }

  function estacao(e, n) {
    return '<article class="vg-estacao vg-forma--' + e.forma + '" style="--c:' + e.cor + '" data-id="' + e.id + '">' +
      '<div class="vg-estacao__corpo">' +
        '<span class="vg-estacao__passo">Etapa ' + (n + 1) + "</span>" +
        '<h2 class="vg-estacao__titulo">' + esc(e.titulo) + info(e.info, e.titulo) + "</h2>" +
        '<p class="vg-estacao__sub">' + esc(e.sub) + " " + e.onde.map(function (v) { return '<span class="vg-vps">' + v + "</span>"; }).join("") + "</p>" +
        '<div class="vg-partes">' + e.partes.map(function (p) { return '<span class="vg-parte">' + esc(p) + "</span>"; }).join("") + "</div>" +
        (e.ias.length ? '<div class="vg-ias">' + e.ias.map(function (a) {
          return '<button type="button" class="vg-ia" data-vg-info="' + esc(a.info) + '" data-vg-titulo="' + esc(a.nome) + '">' +
                 '<span class="vg-ia__hex">' + ROBO + "</span>" + esc(a.nome) + "</button>";
        }).join("") + "</div>" : "") +
        '<div class="vg-pessoas">' + e.pessoas.map(function (p) {
          // gente da equipe pelas iniciais; grupo de pessoas (corretores, clientes, donos) pelo ícone
          var marca = EQUIPE.indexOf(p) >= 0 ? esc(iniciais(p)) : PESSOA;
          return '<span class="vg-pessoa" title="' + esc(p) + '"><b>' + marca + "</b>" + esc(p) + "</span>";
        }).join("") + "</div>" +
      "</div></article>";
  }

  function desenhar() {
    // a jornada em setas, no alto (como a fileira de setas do infográfico)
    document.getElementById("vg-jornada").innerHTML = ESTACOES.map(function (e, n) {
      return '<li style="--c:' + e.cor + '"><b>' + (n + 1) + "</b>" + esc(e.passo) + "</li>";
    }).join("");
    var h = [];
    ESTACOES.forEach(function (e, n) {
      if (n) h.push('<div class="vg-seta" style="--de:' + ESTACOES[n - 1].cor + ";--para:" + e.cor + '" aria-hidden="true"><i></i></div>');
      h.push(estacao(e, n));
    });
    document.getElementById("vg-fluxo").innerHTML = h.join("");
    document.getElementById("vg-tambem").innerHTML = TAMBEM.map(function (t) {
      return '<div class="vg-satelite vg-mini--' + t.forma + '" style="--c:' + t.cor + '">' +
        '<span class="vg-satelite__forma">' + (t.ia ? ROBO : "") + "</span>" +
        "<div><strong>" + esc(t.titulo) + info(t.info, t.titulo) + "</strong><small>" + esc(t.sub) + ' <span class="vg-vps">' + t.onde + "</span></small></div></div>";
    }).join("");
  }

  /* ── o (i): uma frase, logo abaixo de quem foi tocado ── */
  var balao, aberto = null;
  function abrir(botao) {
    if (aberto === botao) { fechar(); return; }
    aberto = botao;
    balao.innerHTML = "<strong>" + esc(botao.getAttribute("data-vg-titulo")) + "</strong><p>" + esc(botao.getAttribute("data-vg-info")) + "</p>";
    balao.hidden = false;
    var caixa = document.getElementById("vg").getBoundingClientRect(), r = botao.getBoundingClientRect();
    var x = r.left - caixa.left + r.width / 2 - balao.offsetWidth / 2;
    x = Math.max(10, Math.min(x, caixa.width - balao.offsetWidth - 10));
    balao.style.left = x + "px";
    balao.style.top = (r.bottom - caixa.top + 10) + "px";
  }
  function fechar() { aberto = null; balao.hidden = true; }

  // ?escuro mostra o tema escuro do CRM fora do CRM (para conferir)
  if (/[?&]escuro/.test(location.search)) document.documentElement.classList.add("crm-escuro");
  desenhar();
  balao = document.getElementById("vg-balao");
  document.getElementById("vg").addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-vg-info]");
    if (b) { ev.stopPropagation(); abrir(b); return; }
    fechar();
  });
  document.addEventListener("keydown", function (ev) { if (ev.key === "Escape") fechar(); });
  window.addEventListener("resize", fechar);
})();
