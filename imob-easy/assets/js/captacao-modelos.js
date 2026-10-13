/* ==========================================================================
   Captação › Modelos WhatsApp (12/10/2026, Pedro: "quero todos os modelos da minha API oficial que foram aprovados,
   e em qual categoria, já em um mockup de mensagem, num balãozinho com os botões que ele tem, sem precisar clicar").
   Lê admin/dados/modelos.json, que o cron nay-agentes escreve a cada 10 min lendo a Graph API de dentro do CRM.
   ========================================================================== */
(function () {
  "use strict";
  var painel = document.getElementById("painel-modelos");
  if (!painel) return;
  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  // o texto do WhatsApp: *negrito*, _itálico_, {{1}} vira um exemplo
  function wa(t) {
    return esc(t).replace(/\{\{1\}\}/g, "<i class=\"mw-var\">Carlos</i>").replace(/\{\{(\d+|\w+)\}\}/g, "<i class=\"mw-var\">{{$1}}</i>")
      .replace(/\*([^*\n]+)\*/g, "<b>$1</b>").replace(/_([^_\n]+)_/g, "<em>$1</em>").replace(/\n/g, "<br>");
  }
  // os modelos da campanha de hoje (Pedro, 12/10): a aba "Em uso"; todo o resto fica em "Outros"
  var EM_USO = ["situacao_imovel_cadastrado_1", "captacao_status_novo_numero_2", "captacao_status_novo_numero_3", "l1_util_16", "l1_util_12"];
  // 13/10 (Pedro: "coloca lá na aba modelos já se foram aprovadas as mensagens novas, cria um título novas"): os modelos
  // recadastrados em 12/10 (rodapé Imobeasy e botões), que voltaram para a revisão da Meta. Ficam num título próprio,
  // em cima, com a contagem de quantos já foram aprovados. Modelo novo que entrar em revisão: acrescente o nome aqui.
  var NOVAS = ["captacao_status_novo_numero_2", "captacao_status_novo_numero_3", "l1_util_16", "l1_util_12"];
  var CAT = { UTILITY: ["Utilidade", "mw-cat--util"], MARKETING: ["Marketing", "mw-cat--mkt"], AUTHENTICATION: ["Autenticação", "mw-cat--aut"] };
  var ST = { APPROVED: ["aprovado", "mw-st--ok"], PENDING: ["pendente", "mw-st--pend"], REJECTED: ["reprovado", "mw-st--rej"], PAUSED: ["pausado", "mw-st--rej"] };
  function balao(m) {
    var cat = CAT[m.categoria] || [m.categoria, ""], st = ST[m.status] || [m.status, ""];
    return '<article class="mw-item">' +
      '<div class="mw-meta"><span class="mw-nome">' + esc(m.nome) + '</span><span class="mw-cat ' + cat[1] + '">' + esc(cat[0]) + "</span>" +
        '<span class="mw-st ' + st[1] + '">' + esc(st[0]) + "</span>" + (m.qualidade ? '<span class="mw-q">qualidade ' + esc(m.qualidade) + "</span>" : "") +
        '<span class="mw-idioma">' + esc(m.idioma) + "</span></div>" +
      '<div class="mw-fone"><div class="mw-balao">' +
        (m.cabecalho ? '<div class="mw-cab">' + wa(m.cabecalho) + "</div>" : "") +
        '<div class="mw-corpo">' + wa(m.corpo) + "</div>" +
        (m.rodape ? '<div class="mw-rodape">' + esc(m.rodape) + "</div>" : "") +
        '<div class="mw-hora">' + new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) + "</div>" +
      "</div>" +
      (m.botoes && m.botoes.length ? '<div class="mw-botoes">' + m.botoes.map(function (b) {
        return '<div class="mw-botao">' + (b.tipo === "URL" ? "🔗 " : b.tipo === "PHONE_NUMBER" ? "📞 " : "↩ ") + esc(b.texto) + "</div>";
      }).join("") + "</div>" : "") +
      "</div>" + (m.motivo ? '<p class="mw-motivo">Motivo da Meta: ' + esc(m.motivo) + "</p>" : "") +
    "</article>";
  }
  function num(n) { return Number(n || 0).toLocaleString("pt-BR"); }
  function listas() {
    fetch("api/captacao/publicos", { credentials: "same-origin" }).then(function (r) { return r.ok ? r.json() : null; }).then(function (d) {
      var lado = document.getElementById("mw-lado");
      if (!d || !d.listas) { lado.innerHTML = '<p class="mw-vazio">Não consegui ler as listas.</p>'; return; }
      // 12/10 (Pedro): "separa para corretores e para donos, já removendo quem falou conosco nos últimos 2 meses"
      function bloco(titulo, lista) {
        return '<h3 class="mw-lado__grupo">' + titulo + "</h3>" + lista.map(function (l) {
          var pct = l.total ? Math.round(l.disparados * 100 / l.total) : 0;
          return '<div class="mw-publico"><div class="mw-publico__n">' + l.n + '</div><div class="mw-publico__corpo">' +
            '<div class="mw-publico__nome">' + esc(l.nome) + "</div>" +
            '<div class="mw-publico__desc">' + esc(l.descricao) + "</div>" +
            '<div class="mw-publico__num"><b>' + num(l.total) + "</b> para falar · <b>" + num(l.disparados) + "</b> já receberam (" + pct + "%)" +
              (l.falaram ? '<span class="mw-publico__fora"> · ' + num(l.falaram) + " falaram conosco (fora)</span>" : "") + "</div>" +
            '<div class="mw-publico__barra"><i style="width:' + pct + '%"></i></div></div></div>';
        }).join("");
      }
      var corr = d.listas.filter(function (l) { return l.grupo === "corretores"; }), donos = d.listas.filter(function (l) { return l.grupo !== "corretores"; });
      lado.innerHTML = '<h2 class="mw-lado__titulo">Listas do disparo</h2>' + bloco("Para corretores", corr) + bloco("Para donos", donos) +
        '<p class="mw-lado__nota">Quem escreveu para a gente nos últimos 60 dias (por qualquer número) já saiu das listas. "Já receberam" = recebeu disparo nosso.</p>';
    }).catch(function () {});
  }
  var carregou = false;
  function carregar() {
    if (carregou) return;
    carregou = true;
    listas();
    fetch("dados/modelos.json?t=" + Math.floor(Date.now() / 60000)).then(function (r) { return r.ok ? r.json() : null; }).then(function (d) {
      var alvo = document.getElementById("mw-lista");
      if (!d || !d.modelos) { alvo.innerHTML = '<p class="mw-vazio">A leitura dos modelos ainda não chegou (o cron escreve admin/dados/modelos.json a cada 10 min).</p>'; return; }
      if (d.erro) { alvo.innerHTML = '<p class="mw-vazio">Não deu para ler os modelos: ' + esc(d.erro) + "</p>"; return; }
      var aprov = d.modelos.filter(function (m) { return m.status === "APPROVED"; }), resto = d.modelos.filter(function (m) { return m.status !== "APPROVED"; });
      var util = aprov.filter(function (m) { return m.categoria === "UTILITY"; }), mkt = aprov.filter(function (m) { return m.categoria !== "UTILITY"; });
      document.getElementById("mw-resumo").textContent = aprov.length + " aprovados (" + util.length + " utilidade, " + mkt.length + " marketing)" +
        (resto.length ? " · " + resto.length + " pendentes ou reprovados" : "") + " · lido " + new Date(d.lido_em * 1000).toLocaleString("pt-BR", { timeZone: "America/Manaus" });
      function secao(titulo, lista) { return lista.length ? '<h2 class="mw-secao">' + titulo + " <small>" + lista.length + "</small></h2>" + '<div class="mw-grade">' + lista.map(balao).join("") + "</div>" : ""; }
      // 12/10 (Pedro): duas abas, EM USO (os modelos da campanha) e OUTROS (o resto), a de outros fechada por padrão
      var emUso = d.modelos.filter(function (m) { return EM_USO.indexOf(m.nome) >= 0; }).sort(function (a, b) { return EM_USO.indexOf(a.nome) - EM_USO.indexOf(b.nome); });
      var novas = d.modelos.filter(function (m) { return NOVAS.indexOf(m.nome) >= 0; }).sort(function (x, y) { return NOVAS.indexOf(x.nome) - NOVAS.indexOf(y.nome); });
      // 13/10, logo depois (Pedro: "você tirou das de em uso, deixa as antigas e deixa as novas lá também"): o título
      // Em uso continua com os cinco, como era; as novas aparecem nos dois lugares
      var jaEmUso = emUso;
      var nAprov = novas.filter(function (m) { return m.status === "APPROVED"; }).length, nRej = novas.filter(function (m) { return m.status === "REJECTED"; }).length;
      var nPend = novas.length - nAprov - nRej;
      var blocoNovas = novas.length ? '<h2 class="mw-secao">Novas <small>' + nAprov + " de " + novas.length + " aprovadas" +
        (nPend ? " · " + nPend + " em análise na Meta" : "") + (nRej ? " · " + nRej + " reprovada" + (nRej > 1 ? "s" : "") : "") + "</small></h2>" +
        '<div class="mw-grade">' + novas.map(balao).join("") + "</div>" : "";
      // 13/10 (Pedro: "vê se tem alguma que se apresenta como novo número, pergunta se o imóvel da pessoa está
      // disponível mas sem os botões, se tiver coloca lá para eu ver"): com as três coisas não existe nenhuma. As que
      // PERGUNTAM se está disponível e NÃO têm botão ganham um título próprio; o subtítulo diz se alguma fala de
      // número novo. A regra é pelo texto: modelo novo que couber nela aparece sozinho.
      var semBotao = d.modelos.filter(function (m) { return !(m.botoes && m.botoes.length) && /dispon[ií]vel\s*\?/i.test(m.corpo || ""); });
      var comNumero = semBotao.filter(function (m) { return /novo n[uú]mero|n[uú]mero novo/i.test(m.corpo || ""); }).length;
      var blocoSemBotao = semBotao.length ? '<h2 class="mw-secao">Sem botões, perguntando se está disponível <small>' + semBotao.length + " · " +
        (comNumero ? comNumero + (comNumero > 1 ? " se apresentam" : " se apresenta") + " como novo número" : "nenhuma se apresenta como novo número") + "</small></h2>" +
        '<div class="mw-grade">' + semBotao.map(balao).join("") + "</div>" : "";
      function fora(l) { return l.filter(function (m) { return EM_USO.indexOf(m.nome) < 0; }); }
      var outros = secao("Utilidade", fora(util)) + secao("Marketing", fora(mkt)) + secao("Pendentes e reprovados", fora(resto));
      alvo.innerHTML = '<div class="mw-abas"><button type="button" class="mw-aba mw-aba--ativa" data-aba="uso">Em uso <small>' + emUso.length + "</small></button>" +
        '<button type="button" class="mw-aba" data-aba="outros">Outros <small>' + (d.modelos.length - emUso.length) + "</small></button></div>" +
        '<section class="mw-painel" data-painel="uso">' + blocoNovas + (jaEmUso.length ? (novas.length ? '<h2 class="mw-secao">Em uso <small>' + jaEmUso.length + "</small></h2>" : "") + '<div class="mw-grade">' + jaEmUso.map(balao).join("") + "</div>" : (novas.length ? "" : '<p class="mw-vazio">Nenhum dos modelos em uso foi lido ainda.</p>')) + blocoSemBotao + "</section>" +
        '<section class="mw-painel" data-painel="outros" hidden>' + outros + "</section>";
      alvo.querySelectorAll(".mw-aba").forEach(function (b) {
        b.addEventListener("click", function () {
          alvo.querySelectorAll(".mw-aba").forEach(function (x) { x.classList.toggle("mw-aba--ativa", x === b); });
          alvo.querySelectorAll(".mw-painel").forEach(function (p) { p.hidden = p.getAttribute("data-painel") !== b.getAttribute("data-aba"); });
        });
      });
    }).catch(function () { document.getElementById("mw-lista").innerHTML = '<p class="mw-vazio">Não consegui ler os modelos.</p>'; });
  }
  document.addEventListener("modelos:mostrar", carregar);
  if (!painel.hidden) carregar();
})();
