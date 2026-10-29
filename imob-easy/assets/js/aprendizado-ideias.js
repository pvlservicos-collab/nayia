/* Ideias refinadas (admin/aprendizado.html, aba 2). Pedro, 28/10/2026: "cada ideia vai ter a tua sugestão, como é hoje,
   onde isso pode nos ajudar, e se a execução é curto, médio ou longo prazo, e uma nota em formato de uma barrinha
   vertical que eu vou mexer ... no final posso filtrar lá em cima só as ideias acima de 90 para eu executar".
   As ideias vêm da rotina da noite (scripts/aprendizado.py gravar → aprendizado_gravar, 514). Aqui: ler por
   /admin/api/aprendizado/ideias e gravar a barrinha por /admin/api/aprendizado/ideias/<id>/nota.
   Também cuida das duas abas da página (Transcrições | Ideias refinadas); #ideias abre direto na segunda. */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var PRAZO = { curto: "Curto prazo", medio: "Médio prazo", longo: "Longo prazo" };
  var est = { ideias: [], videos: [], filtro: "todas", prazo: "", video: "", ordem: "nota", lido: false };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  // o texto das ideias é markdown curto: itens com "- ", parágrafos e **negrito**
  function md(t) {
    var h = "", lista = false;
    String(t || "").split("\n").forEach(function (l) {
      var item = /^\s*[-*]\s+/.test(l);
      if (item && !lista) { h += "<ul>"; lista = true; }
      if (!item && lista) { h += "</ul>"; lista = false; }
      var x = esc(l.replace(/^\s*[-*]\s+/, "")).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");
      if (!x.trim()) return;
      h += item ? "<li>" + x + "</li>" : "<p>" + x + "</p>";
    });
    return h + (lista ? "</ul>" : "");
  }
  function api(rota, corpo) {
    var o = { credentials: "same-origin", headers: {} };
    if (corpo !== undefined) { o.method = "POST"; o.headers["Content-Type"] = "application/json"; o.body = JSON.stringify(corpo); }
    return fetch("api/aprendizado/ideias" + (rota || ""), o).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.erro || ("erro " + r.status));
        return d;
      });
    });
  }

  /* ---- as abas */
  function abrirAba(qual) {
    [].forEach.call(document.querySelectorAll("#ap-abas [role=tab]"), function (b) {
      var sim = b.getAttribute("data-aba") === qual;
      b.setAttribute("aria-selected", String(sim));
      $(b.getAttribute("aria-controls")).hidden = !sim;
    });
    if (qual === "ideias" && !est.lido) ler();
  }
  [].forEach.call(document.querySelectorAll("#ap-abas [role=tab]"), function (b) {
    b.addEventListener("click", function () {
      var qual = b.getAttribute("data-aba");
      history.replaceState(null, "", qual === "ideias" ? "#ideias" : location.pathname + location.search);
      abrirAba(qual);
    });
  });

  /* ---- ler e desenhar */
  function ler() {
    est.lido = true;
    $("id-lista").innerHTML = '<p class="ap-vazio">Lendo…</p>';
    api("").then(function (d) {
      est.ideias = d.ideias || [];
      est.videos = d.videos || [];
      $("id-video").innerHTML = '<option value="">Todos os vídeos</option>' + est.videos.map(function (v) {
        return '<option value="' + esc(v.youtube_id) + '">' + esc(v.titulo) + " (" + v.ideias + ")</option>";
      }).join("");
      $("id-video").value = est.video;
      desenhar();
      desenharVideos();
    }).catch(function (e) { est.lido = false; $("id-lista").innerHTML = '<p class="ap-erro">' + esc(e.message) + "</p>"; });
  }
  function passa(i) {
    if (est.filtro === "acima" && i.nota < 90) return false;
    if (est.filtro === "novas" && i.nota_revisada) return false;
    if (est.prazo && i.prazo !== est.prazo) return false;
    if (est.video && i.youtube_id !== est.video) return false;
    return true;
  }
  function desenhar() {
    var lista = est.ideias.filter(passa).sort(est.ordem === "numero"
      ? function (a, b) { return a.numero - b.numero; }
      : function (a, b) { return b.nota - a.nota || a.numero - b.numero; });
    $("id-lista").innerHTML = !est.ideias.length
      ? '<p class="ap-vazio">Nenhuma ideia ainda. Depois de salvar as transcrições, peça ao Claude "analisa os vídeos novos".</p>'
      : lista.length ? lista.map(cartao).join("") : '<p class="ap-vazio">Nenhuma ideia neste filtro.</p>';
    desenharConta();
  }
  function cartao(i) {
    var mais = (i.porque_prazo ? "<h4>Por que esse prazo</h4>" + md(i.porque_prazo) : "") +
               (i.do_video ? "<h4>Do vídeo</h4>" + md(i.do_video) : "");
    return '<article class="id-cartao id-cartao--' + esc(i.prazo) + '" data-id="' + i.id + '">' +
      '<div class="id-corpo">' +
        '<p class="id-selos"><span class="id-num">#' + i.numero + '</span><span class="id-selo id-selo--' + esc(i.prazo) + '">' +
          esc(PRAZO[i.prazo] || i.prazo) + "</span>" + (i.area ? '<span class="id-selo">' + esc(i.area) + "</span>" : "") +
          '<span class="id-fonte">' + esc(i.video_quem ? i.video_quem.split(",")[0] : i.video || "") + "</span></p>" +
        '<h3 class="id-titulo">' + esc(i.titulo) + "</h3>" +
        '<div class="id-secoes">' +
          '<section><h4>Sugestão</h4>' + md(i.sugestao) + "</section>" +
          '<section><h4>Como é hoje</h4>' + md(i.como_hoje) + "</section>" +
          '<section><h4>Onde nos ajuda</h4>' + md(i.onde_ajuda) + "</section>" +
        "</div>" +
        (mais ? '<details class="id-mais"><summary>Prazo e trecho do vídeo</summary>' + mais + "</details>" : "") +
      "</div>" +
      '<div class="id-nota' + (i.nota >= 90 ? " id-nota--alta" : "") + '">' +
        '<output class="id-valor" for="id-r' + i.id + '">' + i.nota + "</output>" +
        '<input type="range" class="id-barra" id="id-r' + i.id + '" min="0" max="100" step="1" value="' + i.nota +
          '" aria-label="Nota da ideia ' + i.numero + '">' +
        '<span class="id-quem">' + (i.nota_revisada ? "sua nota" : "nota do Claude") + "</span>" +
        (i.nota_revisada && i.nota !== i.nota_claude ? '<span class="id-claude">Claude: ' + i.nota_claude + "</span>" : "") +
        '<span class="id-salvo" aria-live="polite"></span>' +
      "</div></article>";
  }
  function desenharVideos() {
    $("id-videos").innerHTML = est.videos.length ? est.videos.map(function (v) {
      var d = v.data ? v.data.split("-").reverse().join("/") : "";
      return "<li><details><summary><span class=\"ap-quando\">" + esc(d) + "</span><b>" + esc(v.titulo) + "</b> · " +
        esc(v.quem || "") + (v.duracao ? " · " + esc(v.duracao) : "") + " · " + v.ideias + " ideias</summary>" +
        (v.link ? '<p><a href="' + esc(v.link) + '" target="_blank" rel="noopener">Abrir no YouTube</a></p>' : "") +
        (v.defende ? "<h4>O que defende</h4>" + md(v.defende) : "") +
        (v.nao_serve ? "<h4>O que não serve para nós</h4>" + md(v.nao_serve) : "") + "</details></li>";
    }).join("") : '<li class="ap-vazio">Nenhum vídeo estudado ainda.</li>';
  }

  /* ---- a barrinha: o número acompanha enquanto arrasta; solta = grava */
  var lista = $("id-lista");
  lista.addEventListener("input", function (e) {
    if (!e.target.classList.contains("id-barra")) return;
    var caixa = e.target.closest(".id-nota");
    caixa.querySelector(".id-valor").textContent = e.target.value;
    caixa.classList.toggle("id-nota--alta", +e.target.value >= 90);
  });
  lista.addEventListener("change", function (e) {
    if (!e.target.classList.contains("id-barra")) return;
    var cart = e.target.closest(".id-cartao"), id = +cart.getAttribute("data-id"), nota = +e.target.value;
    var aviso = cart.querySelector(".id-salvo");
    aviso.textContent = "salvando…";
    api("/" + id + "/nota", { nota: nota }).then(function () {
      var i = est.ideias.filter(function (x) { return x.id === id; })[0];
      if (i) { i.nota = nota; i.nota_revisada = true; }
      aviso.textContent = "salvo";
      cart.querySelector(".id-quem").textContent = "sua nota";
      setTimeout(function () { aviso.textContent = ""; }, 1800);
      desenharConta();
    }).catch(function (er) { aviso.textContent = "não salvou"; alert(er.message); });
  });
  // a lista não se rearruma enquanto ele dá nota (a ideia não some do "Acima de 90" no meio); só a conta muda
  function desenharConta() {
    var vis = lista.querySelectorAll(".id-cartao").length;
    var acima = est.ideias.filter(function (i) { return i.nota >= 90; }).length;
    var novas = est.ideias.filter(function (i) { return !i.nota_revisada; }).length;
    $("id-conta").textContent = vis + " de " + est.ideias.length + " ideias · " + acima + " acima de 90 · " + novas + " sem a sua nota";
  }

  /* ---- os filtros do topo */
  function segmento(caixa, chave) {
    caixa.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-v]");
      if (!b) return;
      est[chave] = b.getAttribute("data-v");
      [].forEach.call(caixa.querySelectorAll("button"), function (x) { x.setAttribute("aria-pressed", String(x === b)); });
      desenhar();
    });
  }
  segmento($("id-filtro"), "filtro");
  segmento($("id-prazo"), "prazo");
  $("id-video").addEventListener("change", function () { est.video = this.value; desenhar(); });
  $("id-ordem").addEventListener("change", function () { est.ordem = this.value; desenhar(); });
  $("id-atualizar").addEventListener("click", ler);

  abrirAba(location.hash === "#ideias" ? "ideias" : "transcricoes");
})();
