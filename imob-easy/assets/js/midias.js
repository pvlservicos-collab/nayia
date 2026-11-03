/* Mídias (admin/midias.html, 579). Pedro, 03/11/2026: "trocar o menu lá gerador de post por uma aba Mídias ... organizar
   essas demandas ... criando um calendário de conteúdo bonitinho ... abas: Insta, Face, YouTube, Google SEO e IA GEO".
   Lê tudo de /admin/api/midias (site_midias): a DEMANDA (o que fazer, quem faz, status) e a PEÇA do calendário (com dia,
   presa à demanda). Clicar em qualquer uma abre o editor; salvar e excluir vão pelas rotas POST da mesma API. */
(function () {
  "use strict";
  var CANAIS = {
    insta:   { nome: "Insta",      sobre: "Instagram (Reels, carrossel, stories) e os status do WhatsApp, que usam o mesmo vídeo vertical." },
    face:    { nome: "Face",       sobre: "A página do Facebook e os anúncios da Meta (clique para o WhatsApp, formulário, públicos do CRM)." },
    youtube: { nome: "YouTube",    sobre: "Shorts com título de busca de Manaus e o editor de vídeo automático." },
    seo:     { nome: "Google SEO", sobre: "O site no Google: SEO da home, uma página para cada busca, Perfil da Empresa e Google Ads." },
    geo:     { nome: "IA GEO",     sobre: "Aparecer quando alguém pergunta ao ChatGPT, Gemini ou Perplexity: blog, FAQ, guias e dados da empresa." }
  };
  var STATUS = [["ideia", "Ideia"], ["a_fazer", "A fazer"], ["producao", "Em produção"], ["pronto", "Pronto"], ["publicado", "Publicado"], ["pausado", "Pausado"]];
  var NOME_STATUS = {}; STATUS.forEach(function (s) { NOME_STATUS[s[0]] = s[1]; });
  var DIAS = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];
  var MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
  var est = { itens: [], hoje: null, mes: null, ocultos: {}, aba: "calendario", aberto: null };
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function api(rota, corpo) {
    var o = { credentials: "same-origin", headers: {} };
    if (corpo !== undefined) {
      o.method = "POST";
      o.headers["Content-Type"] = "application/json";
      o.body = JSON.stringify(corpo);
    }
    return fetch("api/midias" + (rota || ""), o).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.erro || ("erro " + r.status));
        return d;
      });
    });
  }
  // as datas vêm como "AAAA-MM-DD": sem fuso, para o dia nunca andar
  function ymd(d) { return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2); }
  function dia(s) { var p = String(s).split("-"); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function curta(s) { var d = dia(s); return ("0" + d.getDate()).slice(-2) + "/" + ("0" + (d.getMonth() + 1)).slice(-2); }
  function semanaDe(s) { var d = dia(s), w = (d.getDay() + 6) % 7; d.setDate(d.getDate() - w); return d; }
  function porId(id) { return est.itens.filter(function (i) { return i.id === id; })[0]; }
  function pecas() { return est.itens.filter(function (i) { return i.tipo === "conteudo"; }); }
  function demandas(canal) { return est.itens.filter(function (i) { return i.tipo === "demanda" && (!canal || i.canal === canal); }); }

  /* ---- o resumo de cima: um quadrado por canal ---- */
  function resumo() {
    var hoje = est.hoje, fim = ymd(new Date(dia(hoje).getTime() + 7 * 864e5));
    $("md-resumo").innerHTML = Object.keys(CANAIS).map(function (c) {
      var ds = demandas(c), abertas = ds.filter(function (d) { return d.status !== "publicado"; }).length;
      var semana = pecas().filter(function (p) { return p.canal === c && p.data >= hoje && p.data < fim; }).length;
      return '<button type="button" class="md-resumo__item" data-canal="' + c + '" data-ir="' + c + '">' +
        '<span class="md-resumo__nome"><i class="md-bola" data-canal="' + c + '"></i>' + CANAIS[c].nome + '</span>' +
        '<span class="md-resumo__num">' + abertas + '<small> demanda' + (abertas === 1 ? "" : "s") + ' abertas</small></span>' +
        '<span class="md-resumo__sub">' + semana + ' peça' + (semana === 1 ? "" : "s") + ' nos próximos 7 dias</span></button>';
    }).join("");
  }

  /* ---- o calendário do mês ---- */
  function legenda() {
    $("md-legenda").innerHTML = Object.keys(CANAIS).map(function (c) {
      return '<button type="button" class="md-chave" data-canal="' + c + '" data-chave="' + c + '" aria-pressed="' + (!est.ocultos[c]) + '">' +
        '<i class="md-bola" data-canal="' + c + '"></i>' + CANAIS[c].nome + '</button>';
    }).join("");
  }
  function chip(p) {
    return '<button type="button" class="md-chip md-chip--' + p.status + '" data-canal="' + p.canal + '" data-abrir="' + p.id + '" title="' +
      esc(CANAIS[p.canal].nome + " · " + (p.formato || "") + " · " + NOME_STATUS[p.status] + (p.quem ? " · " + p.quem : "") + "\n" + p.titulo) + '">' +
      '<span class="md-chip__txt">' + esc(p.titulo) + '</span></button>';
  }
  function grade() {
    var m = est.mes, primeiro = new Date(m.getFullYear(), m.getMonth(), 1);
    var nm = MESES[m.getMonth()];
    $("md-mes-nome").textContent = nm.charAt(0).toUpperCase() + nm.slice(1) + " de " + m.getFullYear();
    var ini = new Date(primeiro); ini.setDate(1 - ((primeiro.getDay() + 6) % 7));
    var por = {};
    pecas().forEach(function (p) { if (p.data && !est.ocultos[p.canal]) (por[p.data] = por[p.data] || []).push(p); });
    var h = DIAS.map(function (d) { return '<div class="md-grade__dia-semana">' + d + "</div>"; }).join("");
    for (var k = 0; k < 42; k++) {
      var d = new Date(ini); d.setDate(ini.getDate() + k);
      if (k >= 35 && d.getMonth() !== m.getMonth()) break;
      var s = ymd(d), lista = (por[s] || []).sort(function (a, b) { return a.canal < b.canal ? -1 : a.canal > b.canal ? 1 : a.id - b.id; });
      var cls = "md-dia" + (d.getMonth() !== m.getMonth() ? " md-dia--fora" : "") + (s === est.hoje ? " md-dia--hoje" : "") + (s < est.hoje ? " md-dia--passou" : "");
      h += '<div class="' + cls + '" data-dia="' + s + '">' +
        '<div class="md-dia__topo"><span class="md-dia__num">' + d.getDate() + '</span>' +
        '<button type="button" class="md-dia__mais" data-novo-dia="' + s + '" aria-label="Nova peça em ' + curta(s) + '">+</button></div>' +
        '<div class="md-dia__lista">' + lista.map(chip).join("") + "</div></div>";
    }
    $("md-grade").innerHTML = h;
  }
  function agenda() {
    // a semana de hoje quando o mês mostrado é o de hoje; senão, a primeira semana do mês
    var ref = (est.mes.getMonth() === dia(est.hoje).getMonth() && est.mes.getFullYear() === dia(est.hoje).getFullYear())
      ? est.hoje : ymd(new Date(est.mes.getFullYear(), est.mes.getMonth(), 1));
    var ini = semanaDe(ref), h = "";
    $("md-semana-titulo").textContent = "Semana de " + curta(ymd(ini)) + " a " + curta(ymd(new Date(ini.getTime() + 6 * 864e5)));
    for (var k = 0; k < 7; k++) {
      var d = new Date(ini); d.setDate(ini.getDate() + k);
      var s = ymd(d), lista = pecas().filter(function (p) { return p.data === s && !est.ocultos[p.canal]; });
      h += '<div class="md-agenda__dia' + (s === est.hoje ? " md-agenda__dia--hoje" : "") + '"><h3>' + DIAS[k] + " <span>" + curta(s) + "</span></h3>" +
        (lista.length ? '<ul>' + lista.map(function (p) {
          return '<li><button type="button" class="md-linha-peca" data-canal="' + p.canal + '" data-abrir="' + p.id + '">' +
            '<i class="md-bola" data-canal="' + p.canal + '"></i><span class="md-linha-peca__t">' + esc(p.titulo) + '</span>' +
            '<span class="md-linha-peca__q">' + esc([p.formato, p.quem].filter(Boolean).join(" · ")) + '</span>' +
            '<span class="md-status md-status--' + p.status + '">' + NOME_STATUS[p.status] + "</span></button></li>";
        }).join("") + "</ul>" : '<p class="md-vazio">Nada marcado.</p>') + "</div>";
    }
    $("md-agenda").innerHTML = h;
  }

  /* ---- um canal: o quadro da produção (demandas por status) e as próximas peças ---- */
  function painel(canal) {
    var el = $("aba-" + canal), ds = demandas(canal);
    var colunas = STATUS.filter(function (s) { return s[0] !== "pausado" || ds.some(function (d) { return d.status === "pausado"; }); });
    var prox = pecas().filter(function (p) { return p.canal === canal && p.data >= est.hoje; })
      .sort(function (a, b) { return a.data < b.data ? -1 : a.data > b.data ? 1 : a.id - b.id; }).slice(0, 14);
    var nPecas = {};
    pecas().forEach(function (p) { if (p.demanda_id) nPecas[p.demanda_id] = (nPecas[p.demanda_id] || 0) + 1; });
    el.innerHTML =
      '<div class="cartao md-canal-topo" data-canal="' + canal + '"><div><h2><i class="md-bola" data-canal="' + canal + '"></i>' + CANAIS[canal].nome + "</h2>" +
      "<p>" + esc(CANAIS[canal].sobre) + "</p></div>" +
      '<div class="md-canal-topo__botoes"><button type="button" class="btn-neutro" data-novo-tipo="conteudo" data-novo-canal="' + canal + '">+ Peça no calendário</button>' +
      '<button type="button" class="btn-azul" data-novo-tipo="demanda" data-novo-canal="' + canal + '">+ Nova demanda</button></div></div>' +
      '<h2 class="md-secao">Produção</h2>' +
      '<div class="md-quadro" style="--colunas:' + colunas.length + '">' + colunas.map(function (s) {
        var cs = ds.filter(function (d) { return d.status === s[0]; })
          .sort(function (a, b) { return ({ alta: 0, media: 1, baixa: 2 }[a.prioridade] || 3) - ({ alta: 0, media: 1, baixa: 2 }[b.prioridade] || 3) || a.id - b.id; });
        return '<div class="md-coluna md-coluna--' + s[0] + '"><h3>' + s[1] + " <span>" + cs.length + "</span></h3>" + cs.map(function (d) {
          return '<button type="button" class="md-cartao" data-canal="' + canal + '" data-abrir="' + d.id + '">' +
            '<span class="md-cartao__titulo">' + esc(d.titulo) + "</span>" +
            (d.descricao ? '<span class="md-cartao__desc">' + esc(d.descricao) + "</span>" : "") +
            '<span class="md-cartao__pe">' +
              (d.quem ? '<span class="md-pessoa">' + esc(d.quem) + "</span>" : "") +
              (d.prioridade ? '<span class="md-prio md-prio--' + d.prioridade + '">' + ({ alta: "alta", media: "média", baixa: "baixa" }[d.prioridade]) + "</span>" : "") +
              (d.data ? '<span class="md-prazo' + (d.data < est.hoje && d.status !== "publicado" ? " md-prazo--atrasado" : "") + '">' + curta(d.data) + "</span>" : "") +
              (nPecas[d.id] ? '<span class="md-npecas">' + nPecas[d.id] + " no calendário</span>" : "") +
            "</span></button>";
        }).join("") + "</div>";
      }).join("") + "</div>" +
      '<h2 class="md-secao">Próximas peças no calendário</h2>' +
      (prox.length ? '<ul class="md-proximas">' + prox.map(function (p) {
        return '<li><button type="button" class="md-linha-peca" data-canal="' + p.canal + '" data-abrir="' + p.id + '">' +
          '<span class="md-linha-peca__d">' + DIAS[(dia(p.data).getDay() + 6) % 7] + " " + curta(p.data) + '</span>' +
          '<span class="md-linha-peca__t">' + esc(p.titulo) + '</span><span class="md-linha-peca__q">' + esc([p.formato, p.quem].filter(Boolean).join(" · ")) + "</span>" +
          '<span class="md-status md-status--' + p.status + '">' + NOME_STATUS[p.status] + "</span></button></li>";
      }).join("") + "</ul>" : '<p class="md-vazio">Nenhuma peça marcada daqui para a frente.</p>');
  }

  function tudo() {
    resumo(); legenda(); grade(); agenda();
    Object.keys(CANAIS).forEach(painel);
  }

  /* ---- as abas (o hash abre direto: midias.html#seo) ---- */
  function abrirAba(aba, semHash) {
    if (!$("aba-" + aba)) aba = "calendario";
    est.aba = aba;
    document.querySelectorAll("#md-abas [data-aba]").forEach(function (b) { b.setAttribute("aria-selected", String(b.dataset.aba === aba)); });
    document.querySelectorAll(".md-painel").forEach(function (p) { p.hidden = p.id !== "aba-" + aba; });
    if (aba === "gerador" && !$("md-gerador").getAttribute("src")) $("md-gerador").setAttribute("src", "gerador-posts.html");
    if (!semHash) history.replaceState(null, "", aba === "calendario" ? location.pathname : "#" + aba);
  }

  /* ---- o editor ---- */
  function opcoesDemanda(canal, atual) {
    var sel = document.querySelector('#md-form [name="demanda_id"]');
    sel.innerHTML = '<option value="">(nenhuma demanda)</option>' + demandas(canal).map(function (d) {
      return '<option value="' + d.id + '"' + (d.id === atual ? " selected" : "") + ">" + esc(d.titulo) + "</option>";
    }).join("");
  }
  function abrir(item) {
    var f = $("md-form");
    est.aberto = item.id || null;
    $("md-dialogo-titulo").textContent = item.id ? (item.tipo === "demanda" ? "Demanda" : "Peça do calendário") : (item.tipo === "demanda" ? "Nova demanda" : "Nova peça");
    ["titulo", "canal", "tipo", "status", "data", "quem", "formato", "prioridade", "descricao", "link"].forEach(function (k) {
      f.elements[k].value = item[k] == null ? "" : item[k];
    });
    opcoesDemanda(item.canal, item.demanda_id);
    $("md-origem").textContent = item.id ? ("Origem: " + (item.origem || "—") + (item.atualizado_por ? " · última mudança por " + item.atualizado_por : "")) : "";
    $("md-erro").textContent = "";
    $("md-excluir").hidden = !item.id;
    var dlg = $("md-dialogo");
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute("open", "");
    f.elements.titulo.focus();
  }
  function fechar() { var dlg = $("md-dialogo"); if (dlg.close) dlg.close(); else dlg.removeAttribute("open"); }
  function salvar(e) {
    e.preventDefault();
    var f = $("md-form"), corpo = { id: est.aberto };
    ["titulo", "canal", "tipo", "status", "data", "quem", "formato", "prioridade", "descricao", "link", "demanda_id"].forEach(function (k) { corpo[k] = f.elements[k].value; });
    $("md-salvar").disabled = true;
    api("", corpo).then(function () { fechar(); return carregar(); })
      .catch(function (err) { $("md-erro").textContent = err.message; })
      .then(function () { $("md-salvar").disabled = false; });
  }
  function excluir() {
    if (!est.aberto || !window.confirm("Excluir este item? Ele some da tela (fica guardado no banco).")) return;
    api("/" + est.aberto + "/excluir", {}).then(function () { fechar(); return carregar(); })
      .catch(function (err) { $("md-erro").textContent = err.message; });
  }

  function carregar() {
    return api("").then(function (d) {
      est.itens = d.itens || [];
      est.hoje = d.hoje || ymd(new Date());
      if (!est.mes) { var h = dia(est.hoje); est.mes = new Date(h.getFullYear(), h.getMonth(), 1); }
      tudo();
    }).catch(function (e) {
      $("md-resumo").innerHTML = '<p class="md-falha">Não consegui ler as mídias: ' + esc(e.message) + "</p>";
    });
  }

  /* ---- os cliques (atributos próprios: o body tem data-pagina, ver layout.js) ---- */
  document.addEventListener("click", function (e) {
    var t = e.target.closest ? e.target : null;
    if (!t) return;
    var b;
    if ((b = t.closest("#md-abas [data-aba]"))) { abrirAba(b.dataset.aba); return; }
    if ((b = t.closest("[data-ir]"))) { abrirAba(b.dataset.ir); window.scrollTo({ top: $("md-abas").offsetTop - 80, behavior: "smooth" }); return; }
    if ((b = t.closest("[data-abrir]"))) { var it = porId(+b.dataset.abrir); if (it) abrir(it); return; }
    if ((b = t.closest("[data-chave]"))) {
      e.preventDefault();
      est.ocultos[b.dataset.chave] = !est.ocultos[b.dataset.chave];
      legenda(); grade(); agenda();
      return;
    }
    if ((b = t.closest("[data-novo-dia]"))) { abrir({ tipo: "conteudo", canal: "insta", status: "ideia", data: b.dataset.novoDia }); return; }
    if ((b = t.closest("[data-novo-tipo]"))) { abrir({ tipo: b.dataset.novoTipo, canal: b.dataset.novoCanal, status: "ideia", data: b.dataset.novoTipo === "conteudo" ? est.hoje : "" }); return; }
  });
  $("md-nova-peca").addEventListener("click", function () { abrir({ tipo: "conteudo", canal: "insta", status: "ideia", data: est.hoje }); });
  $("md-antes").addEventListener("click", function () { est.mes = new Date(est.mes.getFullYear(), est.mes.getMonth() - 1, 1); grade(); agenda(); });
  $("md-depois").addEventListener("click", function () { est.mes = new Date(est.mes.getFullYear(), est.mes.getMonth() + 1, 1); grade(); agenda(); });
  $("md-hoje").addEventListener("click", function () { var h = dia(est.hoje); est.mes = new Date(h.getFullYear(), h.getMonth(), 1); grade(); agenda(); });
  $("md-form").addEventListener("submit", salvar);
  $("md-form").elements.canal.addEventListener("change", function (e) { opcoesDemanda(e.target.value, null); });
  $("md-fechar").addEventListener("click", fechar);
  $("md-cancelar").addEventListener("click", fechar);
  $("md-excluir").addEventListener("click", excluir);
  window.addEventListener("hashchange", function () { abrirAba(location.hash.slice(1) || "calendario", true); });

  abrirAba(location.hash.slice(1) || "calendario", true);
  carregar();
})();
