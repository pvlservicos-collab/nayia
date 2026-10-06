/* O painel Nova Nay (admin/nova-nay.html). Só mostra o que a API do nay-core devolve pela ponte
   /admin/api/nova-nay/<rota> (a senha do /admin vai pelo navegador; o segredo fica no servidor).
   Aba Nós: o grafo (cada nó é uma função do código) e o detalhe do nó clicado, com o código.
   Aba Logs: tudo o que a Nay fez no dia, uma linha por turno, e o detalhe do turno com o caminho pelos nós. */
(function () {
  "use strict";
  var API = "/admin/api/nova-nay/";
  var $ = function (s) { return document.querySelector(s); };
  function esc(t) { return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function pega(rota) {
    return fetch(API + rota, { credentials: "same-origin" }).then(function (r) {
      if (!r.ok) return r.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.detail || j.erro || ("HTTP " + r.status)); });
      return r.json();
    });
  }
  function hora(iso) { return iso ? new Date(iso).toLocaleTimeString("pt-BR", { timeZone: "America/Manaus", hour: "2-digit", minute: "2-digit" }) : "—"; }
  function dataHora(iso) { return iso ? new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—"; }
  function hojeManaus() { return new Date(Date.now() - 4 * 3600 * 1000).toISOString().slice(0, 10); }

  /* ---- versão e modo ---- */
  pega("estado").then(function (e) {
    $("#nn-versao").innerHTML = "versão <b>" + esc(e.versao_codigo) + "</b><span class=\"modo" + (e.modo === "real" ? " modo--real" : "") + "\">" + esc(e.modo) + "</span>" +
      (e.banco !== "ok" ? ' <span class="etiqueta etiqueta--contorno-quente">banco: ' + esc(e.banco) + "</span>" : "");
  }).catch(function (x) { $("#nn-versao").textContent = "painel: " + x.message; });

  /* ---- Nós ---- */
  var MAPA = null, ESCALA = 0.8, atual = null, ACESOS = null;   /* ACESOS: os nós de um turno do treino, acesos no grafo */
  function corDa(etapa) { return (MAPA.etapas[etapa] || {}).cor || "#7c5cff"; }
  function desenharGrafo() {
    var g = $("#nn-grafo"), nos = MAPA.nos, pos = {}, maxX = 0, maxY = 0, busca = ($("#nn-busca").value || "").trim().toLowerCase();
    nos.forEach(function (n) {
      var p = n.posicao || { x: 0, y: 0 }; pos[n.id] = p;
      maxX = Math.max(maxX, p.x + 260); maxY = Math.max(maxY, p.y + 120);
    });
    var W = maxX + 60, H = maxY + 60;
    var svg = '<svg width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + " " + H + '"><defs><marker id="seta" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#b9a9dc"/></marker></defs>' +
      MAPA.setas.map(function (s) {
        var a = pos[s.de], b = pos[s.para]; if (!a || !b) return "";
        var x1 = a.x + 230, y1 = a.y + 36, x2 = b.x, y2 = b.y + 36;
        if (b.x <= a.x) { x1 = a.x + 115; y1 = a.y + 72; x2 = b.x + 115; y2 = b.y; }
        var cx = (x1 + x2) / 2;
        var d = b.x <= a.x ? "M" + x1 + "," + y1 + " C" + x1 + "," + (y1 + 60) + " " + x2 + "," + (y2 - 60) + " " + x2 + "," + y2
                           : "M" + x1 + "," + y1 + " C" + cx + "," + y1 + " " + cx + "," + y2 + " " + x2 + "," + y2;
        return '<path d="' + d + '" marker-end="url(#seta)"/>' + (s.rotulo ? '<text x="' + ((x1 + x2) / 2) + '" y="' + ((y1 + y2) / 2 - 6) + '" text-anchor="middle">' + esc(s.rotulo) + "</text>" : "");
      }).join("") + "</svg>";
    g.style.width = W + "px"; g.style.height = H + "px";
    g.innerHTML = svg + nos.map(function (n) {
      var p = pos[n.id], h = n.hoje || {}, some = busca && (n.nome + " " + n.id + " " + n.descricao).toLowerCase().indexOf(busca) < 0;
      var aceso = ACESOS ? ACESOS.indexOf(n.id) >= 0 : null;
      return '<button type="button" class="nn-no' + (h.erros ? " com-erro" : "") + (aceso === false || (aceso === null && (!h.vezes || some)) ? " parado" : "") + (aceso ? " aceso" : "") + '" data-no="' + esc(n.id) + '" style="left:' + p.x + "px;top:" + p.y + "px;--cor:" + corDa(n.etapa) + '"' + (n.id === atual ? ' aria-current="true"' : "") + ">" +
        "<b>" + esc(n.nome) + "</b><small>" + esc(n.id) + "</small>" +
        '<span class="nn-num">' + (h.vezes ? "hoje " + h.vezes + "×" : "sem uso hoje") + (h.erros ? ' <span class="erro">' + h.erros + " erro(s)</span>" : "") + (h.ms_medio != null ? " · " + h.ms_medio + " ms" : "") + "</span></button>";
    }).join("");
    g.style.transform = "scale(" + ESCALA + ")";
    $("#nn-rolagem").style.setProperty("--w", W * ESCALA + "px");
  }
  function desenharLista() {
    var por = {};
    MAPA.nos.forEach(function (n) { (por[n.etapa] = por[n.etapa] || []).push(n); });
    $("#nn-etapas").innerHTML = Object.keys(MAPA.etapas).map(function (e) {
      var lista = por[e] || [];
      return '<div class="nn-etapa"><i style="background:' + corDa(e) + '"></i>' + esc(MAPA.etapas[e].nome) + "<small>" + lista.length + "</small></div>" +
        lista.map(function (n) { return '<button type="button" class="nn-no-item" data-no="' + esc(n.id) + '"' + (n.id === atual ? ' aria-current="true"' : "") + ">" + esc(n.nome) + (n.hoje && n.hoje.vezes ? "<small>" + n.hoje.vezes + "×</small>" : "") + "</button>"; }).join("");
    }).join("");
  }
  function abrirNo(id) {
    atual = id; desenharGrafo(); desenharLista();
    var d = $("#nn-detalhe"); d.innerHTML = '<p class="painel__vazio">Carregando…</p>';
    pega("nos/" + encodeURIComponent(id)).then(function (n) {
      var h = n.hoje || {}, u = n.ultima_alteracao;
      d.innerHTML = "<h2>" + esc(n.nome) + "</h2><div class=\"id\">" + esc((MAPA.etapas[n.etapa] || {}).nome || n.etapa) + " · " + esc(n.id) + "</div>" +
        "<h3>O que faz</h3><p>" + esc(n.descricao) + "</p>" +
        "<dl class=\"kv\"><dt>Entra</dt><dd>" + esc(n.entra || "—") + "</dd><dt>Sai</dt><dd>" + esc(n.sai || "—") + "</dd>" +
        "<dt>Função</dt><dd><code>" + esc(n.arquivo) + ":" + esc(n.funcao) + "</code> (linhas " + n.linha_inicial + "–" + n.linha_final + ")</dd>" +
        "<dt>Hoje</dt><dd>" + (h.vezes ? "rodou " + h.vezes + "× · " + (h.erros || 0) + " erro(s) · " + (h.ms_medio || 0) + " ms em média" : "não rodou") + "</dd>" +
        "<dt>Usa</dt><dd>" + ((n.configs || []).concat(n.templates || []).map(function (x) { return "<code>" + esc(x) + "</code>"; }).join(" ") || "—") + "</dd>" +
        "<dt>Inventário</dt><dd>" + (n.inventario || []).map(function (x) { return '<span class="etiqueta etiqueta--azul-suave">' + esc(x) + "</span>"; }).join("") + "</dd>" +
        "<dt>Testes</dt><dd>" + ((n.testes || []).map(function (t) { return "<code>" + esc(t.replace(/^tests\//, "")) + "</code>"; }).join(" ") || "—") + "</dd></dl>" +
        "<h3>Última alteração</h3>" + (u ? "<p>" + esc(dataHora(u.quando)) + " · " + esc(u.autor) + ' · <code><a href="https://github.com/pvlservicos-collab/nay-core/commit/' + esc(u.hash) + '" target="_blank" rel="noopener">' + esc(u.hash) + "</a></code><br>" + esc(u.mensagem) + "</p>" : "<p>sem histórico neste mapa (gerado fora do deploy)</p>") +
        ((n.alteracoes_anteriores || []).length ? "<h3>Anteriores</h3><ul class=\"nn-hist\">" + n.alteracoes_anteriores.map(function (a) { return "<li>" + esc(dataHora(a.quando)) + " <code>" + esc(a.hash) + "</code> " + esc(a.mensagem) + "</li>"; }).join("") + "</ul>" : "") +
        '<div class="nn-botoes"><button type="button" class="btn-neutro" data-ver-codigo>Ver código</button><button type="button" class="btn-neutro" data-ver-turnos>Últimos turnos que passaram</button></div>' +
        '<div id="nn-codigo" hidden><h3>Código</h3><pre><code class="language-python">' + esc(n.codigo) + "</code></pre></div>" +
        '<div id="nn-turnos-no" hidden><h3>Turnos de hoje por este nó</h3><ul class="nn-turnos-no"></ul></div>';
      d.querySelector("[data-ver-codigo]").addEventListener("click", function () {
        var c = $("#nn-codigo"); c.hidden = !c.hidden;
        if (!c.hidden && window.hljs) { try { hljs.highlightElement(c.querySelector("code")); } catch (e) { /* sem cor, com código */ } }
      });
      d.querySelector("[data-ver-turnos]").addEventListener("click", function () {
        var c = $("#nn-turnos-no"); c.hidden = !c.hidden; if (c.hidden) return;
        pega("nos/" + encodeURIComponent(id) + "/turnos").then(function (ts) {
          c.querySelector("ul").innerHTML = ts.length ? ts.map(function (t) { return '<li><button type="button" data-abre-turno="' + t.id + '">' + esc(hora(t.criado_em)) + " · " + esc(t.chave) + " · " + esc(t.texto) + (t.erro ? ' <span style="color:#b53232">erro</span>' : "") + "</button></li>"; }).join("") : "<li>nenhum turno hoje</li>";
        });
      });
    }).catch(function (x) { d.innerHTML = '<p class="painel__vazio">' + esc(x.message) + "</p>"; });
  }
  function carregarNos() {
    pega("nos").then(function (m) {
      MAPA = m; desenharLista(); desenharGrafo(); ajustar();
    }).catch(function (x) { $("#nn-grafo").innerHTML = '<p class="painel__vazio" style="padding:20px">' + esc(x.message) + "</p>"; });
  }
  function ajustar() {
    var r = $("#nn-rolagem"), g = $("#nn-grafo");
    var w = parseFloat(g.style.width) || 1, h = parseFloat(g.style.height) || 1;
    ESCALA = Math.max(0.55, Math.min(1, (r.clientWidth - 20) / w));   /* cabe na largura; nó sempre legível */
    g.style.transform = "scale(" + ESCALA + ")";
  }
  document.addEventListener("click", function (e) {
    if (e.target.closest("[data-apagar]")) { window.NN.acender(null); return; }
    var z = e.target.closest("[data-zoom]");
    if (z) { if (z.dataset.zoom === "0") return ajustar(); ESCALA = Math.max(0.3, Math.min(1.6, ESCALA + (z.dataset.zoom === "+" ? 0.1 : -0.1))); $("#nn-grafo").style.transform = "scale(" + ESCALA + ")"; return; }
    var n = e.target.closest("[data-no]"); if (n && MAPA) return abrirNo(n.dataset.no);
    var t = e.target.closest("[data-abre-turno]"); if (t) { abrirAba("logs"); abrirTurno(t.dataset.abreTurno); }
  });
  $("#nn-busca").addEventListener("input", function () { if (MAPA) desenharGrafo(); });
  (function arrastar() {
    var r = $("#nn-rolagem"), ini = null;
    r.addEventListener("mousedown", function (e) { if (e.target.closest(".nn-no")) return; ini = { x: e.clientX, y: e.clientY, sl: r.scrollLeft, st: r.scrollTop }; r.classList.add("arrastando"); });
    window.addEventListener("mousemove", function (e) { if (!ini) return; r.scrollLeft = ini.sl - (e.clientX - ini.x); r.scrollTop = ini.st - (e.clientY - ini.y); });
    window.addEventListener("mouseup", function () { ini = null; r.classList.remove("arrastando"); });
  })();
  /* o treino acende no grafo o caminho de um turno */
  window.NN = {
    abrirAba: function (n) { abrirAba(n); },
    acender: function (ids) { ACESOS = ids && ids.length ? ids : null; $("[data-apagar]").hidden = !ACESOS; abrirAba("nos"); if (MAPA) { desenharGrafo(); setTimeout(ajustar, 0); } window.scrollTo({ top: 0, behavior: "smooth" }); }
  };
  function abrirAba(nome) {
    document.querySelectorAll("[data-painel-abre]").forEach(function (b) { b.setAttribute("aria-selected", b.dataset.painelAbre === nome ? "true" : "false"); });
    document.querySelectorAll("[data-painel]").forEach(function (p) { p.hidden = p.dataset.painel !== nome; });
  }

  /* ---- Logs ---- */
  var ACOES = {}, relogio = null;
  $("#nn-dia").value = hojeManaus();
  function tagAcao(l) {
    if (l.erro) return '<span class="tag erro">erro</span>';
    if (l.estado_depois === "ESCALADO" && l.estado_antes !== "ESCALADO") return '<span class="tag escalou">escalou</span>';
    if (!l.textos && !l.fotos) return '<span class="tag calou">calou' + (l.acao ? ": " + esc(l.acao) : "") + "</span>";
    return '<span class="tag">' + esc(l.acao || l.intencao || "respondeu") + "</span>";
  }
  function saiu(l) {
    var p = [];
    if (l.textos) p.push(l.textos + (l.textos === 1 ? " texto" : " textos"));
    if (l.fotos) p.push(l.fotos + (l.fotos === 1 ? " foto" : " fotos"));
    if (l.avisos_tel) p.push("aviso ao Tel");
    return p.join(" + ") || "—";
  }
  function carregarLogs() {
    var q = new URLSearchParams({ data: $("#nn-dia").value });
    if ($("#nn-papel").value) q.set("papel", $("#nn-papel").value);
    if ($("#nn-acao").value) q.set("acao", $("#nn-acao").value);
    if ($("#nn-so-erros").checked) q.set("so_erros", "true");
    if ($("#nn-so-escalados").checked) q.set("so_escalados", "true");
    if ($("#nn-q").value.trim()) q.set("q", $("#nn-q").value.trim());
    pega("logs?" + q.toString()).then(function (d) {
      var r = d.resumo;
      $("#nn-logs-resumo").textContent = "turnos " + r.turnos + " · responderam " + r.responderam + " · calaram " + r.calaram + " · escalaram " + r.escalaram + " · erros " + r.erros + " · modelo " + r.modelo + "× · US$ " + Number(r.custo || 0).toFixed(2);
      d.linhas.forEach(function (l) { if (l.acao) ACOES[l.acao] = 1; });
      var sel = $("#nn-acao"), v = sel.value;
      sel.innerHTML = '<option value="">Todas as ações</option>' + Object.keys(ACOES).sort().map(function (a) { return "<option" + (a === v ? " selected" : "") + ">" + esc(a) + "</option>"; }).join("");
      $("#nn-logs").innerHTML = d.linhas.length ? d.linhas.map(function (l) {
        return '<tr data-turno="' + l.id + '"><td class="num">' + esc(hora(l.criado_em)) + "</td><td>" + esc(l.nome || "") + " <small>" + esc(l.chave) + "</small></td><td>" + esc(l.papel || "") + '</td><td class="txt">' + esc(l.texto) + "</td><td>" + saiu(l) + "</td><td>" + tagAcao(l) + "</td><td>" + esc((l.codigos || []).join(", ") || l.codigo_acao || "") + '</td><td class="env-' + esc((l.envio || "").split(",")[0]) + '">' + esc(l.envio || "—") + "</td><td>" + (l.chamadas_modelo || 0) + (l.custo ? " · US$ " + Number(l.custo).toFixed(3) : "") + "</td><td>" + (l.ms_total != null ? (l.ms_total / 1000).toFixed(1) + " s" : "") + "</td></tr>";
      }).join("") : '<tr><td colspan="10"><p class="painel__vazio">Nenhum turno nesse dia com esses filtros.</p></td></tr>';
    }).catch(function (x) { $("#nn-logs").innerHTML = '<tr><td colspan="10"><p class="painel__vazio">' + esc(x.message) + "</p></td></tr>"; });
  }
  function abrirTurno(id) {
    var box = $("#nn-turno"); box.hidden = false; box.innerHTML = '<p class="painel__vazio">Carregando…</p>';
    pega("logs/turno/" + id).then(function (d) {
      var t = d.turno, cores = MAPA ? MAPA.etapas : {};
      var caminho = d.trace.filter(function (x) { return x.no_id; });
      box.innerHTML = '<button type="button" class="btn-neutro fechar" data-fechar-turno>Fechar</button>' +
        "<div><h3>Conversa do dia · " + esc(t.nome || "") + " " + esc(t.chave) + "</h3><div class=\"nn-conversa\">" +
        d.conversa_do_dia.map(function (c) { return '<div class="nn-fala ele' + (c.id === t.id ? " atual" : "") + '"><small>' + esc(hora(c.criado_em)) + " · ele</small>" + esc(c.texto) + "</div>" + (c.resposta ? '<div class="nn-fala nay' + (c.id === t.id ? " atual" : "") + '"><small>Nay</small>' + esc(c.resposta) + "</div>" : ""); }).join("") + "</div>" +
        "<h3>Peças da caixa</h3><ul class=\"nn-pecas\">" + (d.pecas.map(function (p) { return "<li>#" + p.ordem + " " + esc(p.tipo) + " → " + esc(p.papel_destino) + " · <b class=\"env-" + esc(p.estado) + "\">" + esc(p.estado) + "</b>" + (p.message_id ? " · id " + esc(p.message_id) : "") + (p.codigo ? " · cód. " + p.codigo : "") + (p.erro ? ' · <span style="color:#b53232">' + esc(p.erro) + "</span>" : "") + (p.tipo === "texto" ? "<br><span style=\"color:var(--texto-medio)\">" + esc(p.texto) + "</span>" : "") + "</li>"; }).join("") || "<li>nenhuma</li>") + "</ul></div>" +
        "<div><h3>Turno #" + t.id + " · " + esc(t.caminho || "") + " · " + (t.usou_modelo ? "com modelo" : "sem modelo") + " · " + (t.ms_total || 0) + " ms" + (t.erro ? ' · <span style="color:#b53232">' + esc(t.erro) + "</span>" : "") + "</h3>" +
        "<h3>Caminho pelos nós</h3><div class=\"nn-caminho\">" + caminho.map(function (x) { var n = MAPA && MAPA.nos.filter(function (k) { return k.id === x.no_id; })[0]; return '<span class="' + (x.erro ? "erro" : "") + '" style="--cor:' + ((n && cores[n.etapa] || {}).cor || "#7c5cff") + '" title="' + esc(x.no_id) + '">' + esc(n ? n.nome : x.no_id) + (x.ms != null ? " · " + x.ms + " ms" : "") + "</span>"; }).join("") + "</div>" +
        "<h3>Entrada e saída de cada etapa</h3><ul class=\"nn-trace\">" + d.trace.map(function (x) { return "<li><details><summary>" + x.seq + ". " + esc(x.no_id || (x.setor + " › " + x.etapa)) + (x.ms != null ? " · " + x.ms + " ms" : "") + (x.modelo ? " · " + esc(x.modelo) : "") + (x.erro ? ' · <span style="color:#b53232">' + esc(x.erro) + "</span>" : "") + "</summary><b>entra</b><pre>" + esc(JSON.stringify(x.entrada, null, 1)) + "</pre><b>sai</b><pre>" + esc(JSON.stringify(x.saida, null, 1)) + "</pre></details></li>"; }).join("") + "</ul>" +
        "<h3>Imóveis já enviados a essa pessoa</h3><ul class=\"nn-fila\">" + (d.fila_enviados.map(function (f) { return "<li>cód. " + f.codigo + " · " + esc(dataHora(f.enviado_em)) + " · " + (f.vezes || 1) + "× · <i>" + esc(f.origem) + "</i></li>"; }).join("") || "<li>nenhum</li>") + "</ul></div>";
      box.scrollIntoView({ behavior: "smooth", block: "start" });
    }).catch(function (x) { box.innerHTML = '<p class="painel__vazio">' + esc(x.message) + "</p>"; });
  }
  document.addEventListener("click", function (e) {
    if (e.target.closest("[data-fechar-turno]")) { $("#nn-turno").hidden = true; return; }
    var tr = e.target.closest("tr[data-turno]"); if (tr) abrirTurno(tr.dataset.turno);
  });
  ["nn-dia", "nn-papel", "nn-acao", "nn-so-erros", "nn-so-escalados"].forEach(function (id) { $("#" + id).addEventListener("change", carregarLogs); });
  var espera; $("#nn-q").addEventListener("input", function () { clearTimeout(espera); espera = setTimeout(carregarLogs, 400); });
  function ligarRelogio() {
    clearInterval(relogio);
    relogio = setInterval(function () { if (!$("[data-painel='logs']").hidden && $("#nn-dia").value === hojeManaus()) carregarLogs(); }, 15000);
  }

  carregarNos(); carregarLogs(); ligarRelogio();
  document.querySelector("[data-abas-funcionais]").addEventListener("click", function (e) {
    var b = e.target.closest("[data-painel-abre]"); if (!b) return;
    if (b.dataset.painelAbre === "nos" && MAPA) setTimeout(ajustar, 0);
  });
})();
