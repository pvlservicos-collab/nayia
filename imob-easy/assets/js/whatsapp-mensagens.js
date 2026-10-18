/* WhatsApp › Mensagens (18/10/2026): o panorama de todos os modelos da Meta, em duas colunas de cards com o mockup,
   filtrável por situação, tipo, etiqueta e data; etiquetas e observação por modelo ficam no banco (410).
   Pedro: "um panorama geral de todas que foram aprovadas como uma lista filtrável por data e tipo, e aprovada ou não,
   e também tags, eu ponho tags nela, e nessa lista não são itens finos são 2 colunas de cards e no card tem o mockup". */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var CAT = { UTILITY: ["Utilidade", "mw-cat--util"], MARKETING: ["Marketing", "mw-cat--mkt"], AUTHENTICATION: ["Autenticação", "mw-cat--aut"] };
  var ST = { APPROVED: ["aprovado", "mw-st--ok"], PENDING: ["pendente", "mw-st--pend"], REJECTED: ["reprovado", "mw-st--rej"], PAUSED: ["pausado", "mw-st--rej"] };
  // os modelos da campanha de hoje (os mesmos de Captação › Modelos): ganham o selo "em uso"
  var EM_USO = ["situacao_imovel_cadastrado_1", "captacao_status_novo_numero_2", "captacao_status_novo_numero_3", "l1_util_16", "l1_util_12"];
  var modelos = [], notas = {}, etiquetasTodas = [], lidoEm = null, temporizador = null;

  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function wa(t) {
    return esc(t).replace(/\{\{1\}\}/g, '<i class="mw-var">Carlos</i>').replace(/\{\{(\d+|\w+)\}\}/g, '<i class="mw-var">{{$1}}</i>')
      .replace(/\*([^*\n]+)\*/g, "<b>$1</b>").replace(/_([^_\n]+)_/g, "<em>$1</em>").replace(/\n/g, "<br>");
  }
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status)); return j; }); });
  }
  function toast(msg, erro) { var t = $("wm-toast"); t.textContent = msg; t.classList.toggle("erro", !!erro); t.hidden = false; clearTimeout(t._t); t._t = setTimeout(function () { t.hidden = true; }, erro ? 5000 : 2200); }
  function chave(m) { return m.nome + "|" + (m.idioma || "pt_BR"); }
  function nota(m) { return notas[chave(m)] || { etiquetas: [], observacao: null }; }
  function dataDe(m) { return m.atualizado_em ? new Date(m.atualizado_em) : null; }
  function dm(d) { return d ? d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "2-digit" }) : "—"; }

  /* ---- carga ---- */
  function carregar() {
    var a = fetch("dados/modelos.json?t=" + Math.floor(Date.now() / 60000)).then(function (r) { return r.ok ? r.json() : null; });
    var b = pedir("api/whats/modelos/notas").catch(function () { return { notas: {}, etiquetas: [] }; });
    Promise.all([a, b]).then(function (r) {
      var d = r[0];
      if (!d || !d.modelos) { $("wm-grade").innerHTML = '<p class="mw-vazio">Não consegui ler os modelos (' + esc((d && d.erro) || "sem arquivo") + ").</p>"; return; }
      modelos = d.modelos; lidoEm = d.lido_em ? new Date(d.lido_em * 1000) : null;
      notas = r[1].notas || {}; etiquetasTodas = r[1].etiquetas || [];
      pintarEtiquetas(); pintarResumo(); pintar();
    }).catch(function (e) { $("wm-grade").innerHTML = '<p class="mw-vazio">' + esc(e.message) + "</p>"; });
  }
  function pintarEtiquetas() {
    var s = $("wm-etq"), v = s.value;
    s.innerHTML = '<option value="">Todas as etiquetas</option><option value="__em_uso">em uso (campanha)</option><option value="__sem">sem etiqueta</option>' +
      etiquetasTodas.map(function (e) { return '<option value="' + esc(e) + '">' + esc(e) + "</option>"; }).join("");
    s.value = (v === "__em_uso" || v === "__sem" || etiquetasTodas.indexOf(v) >= 0) ? v : "";
  }
  function pintarResumo() {
    var ap = modelos.filter(function (m) { return m.status === "APPROVED"; });
    var util = ap.filter(function (m) { return m.categoria === "UTILITY"; }).length, mkt = ap.filter(function (m) { return m.categoria === "MARKETING"; }).length;
    var pend = modelos.filter(function (m) { return m.status === "PENDING"; }).length, rej = modelos.filter(function (m) { return m.status === "REJECTED"; }).length;
    $("wm-resumo").innerHTML =
      "<div><span>Aprovados</span><strong>" + ap.length + "</strong></div>" +
      "<div><span>Utilidade</span><strong>" + util + "</strong></div>" +
      "<div><span>Marketing</span><strong>" + mkt + "</strong></div>" +
      "<div><span>Pendentes</span><strong>" + pend + "</strong></div>" +
      "<div><span>Reprovados</span><strong>" + rej + "</strong></div>" +
      "<div><span>Lido da Meta</span><strong>" + (lidoEm ? lidoEm.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : "—") + "</strong></div>";
  }

  /* ---- filtro e grade ---- */
  function filtrados() {
    var q = $("wm-busca").value.trim().toLowerCase(), st = $("wm-status").value, cat = $("wm-cat").value, et = $("wm-etq").value;
    var de = $("wm-de").value ? new Date($("wm-de").value + "T00:00:00") : null, ate = $("wm-ate").value ? new Date($("wm-ate").value + "T23:59:59") : null;
    var lista = modelos.filter(function (m) {
      if (st && m.status !== st) return false;
      if (cat && m.categoria !== cat) return false;
      var ets = nota(m).etiquetas || [];
      if (et === "__em_uso" && EM_USO.indexOf(m.nome) < 0) return false;
      if (et === "__sem" && ets.length) return false;
      if (et && et !== "__em_uso" && et !== "__sem" && ets.indexOf(et) < 0) return false;
      var d = dataDe(m);
      if (de && (!d || d < de)) return false;
      if (ate && (!d || d > ate)) return false;
      if (q) {
        var txt = (m.nome + " " + (m.corpo || "") + " " + (m.cabecalho || "") + " " + (m.rodape || "") + " " + (nota(m).observacao || "") + " " + ets.join(" ")).toLowerCase();
        if (txt.indexOf(q) < 0) return false;
      }
      return true;
    });
    var ordem = $("wm-ordem").value;
    lista.sort(function (a, b) {
      if (ordem === "nome") return a.nome.localeCompare(b.nome);
      var da = dataDe(a) ? dataDe(a).getTime() : 0, db = dataDe(b) ? dataDe(b).getTime() : 0;
      return ordem === "antigas" ? da - db : db - da;
    });
    return lista;
  }
  function card(m) {
    var cat = CAT[m.categoria] || [m.categoria, ""], st = ST[m.status] || [m.status, ""], nt = nota(m), emUso = EM_USO.indexOf(m.nome) >= 0;
    return '<article class="mw-item wm-card" data-chave="' + esc(chave(m)) + '">' +
      '<div class="mw-meta"><span class="mw-nome">' + esc(m.nome) + '</span><span class="mw-cat ' + cat[1] + '">' + esc(cat[0]) + "</span>" +
        '<span class="mw-st ' + st[1] + '">' + esc(st[0]) + "</span>" + (emUso ? '<span class="wm-uso">em uso</span>' : "") +
        (m.qualidade && m.qualidade !== "UNKNOWN" ? '<span class="mw-q">qualidade ' + esc(m.qualidade) + "</span>" : "") +
        '<span class="mw-idioma">' + esc(m.idioma) + "</span>" +
        '<span class="wm-data-chip" title="última mudança na Meta">' + dm(dataDe(m)) + "</span></div>" +
      '<div class="mw-fone"><div class="mw-balao">' +
        (m.cabecalho ? '<div class="mw-cab">' + wa(m.cabecalho) + "</div>" : "") +
        '<div class="mw-corpo">' + wa(m.corpo) + "</div>" +
        (m.rodape ? '<div class="mw-rodape">' + esc(m.rodape) + "</div>" : "") +
        '<div class="mw-hora">' + new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) + "</div></div>" +
      (m.botoes && m.botoes.length ? '<div class="mw-botoes">' + m.botoes.map(function (b) { return '<div class="mw-botao">' + (b.tipo === "URL" ? "🔗 " : b.tipo === "PHONE_NUMBER" ? "📞 " : "↩ ") + esc(b.texto) + "</div>"; }).join("") + "</div>" : "") +
      "</div>" + (m.motivo ? '<p class="mw-motivo">Motivo da Meta: ' + esc(m.motivo) + "</p>" : "") +
      '<div class="wm-etqs">' + (nt.etiquetas || []).map(function (e) { return '<span class="wm-etq">' + esc(e) + '<button type="button" data-tirar="' + esc(e) + '" title="tirar">×</button></span>'; }).join("") +
        '<button type="button" class="wm-etq-mais" data-etiqueta title="pôr etiqueta">+ etiqueta</button></div>' +
      '<div class="wm-obs" data-obs title="clique para anotar">' + esc(nt.observacao || "") + "</div>" +
    "</article>";
  }
  function pintar() {
    var lista = filtrados();
    $("wm-contagem").textContent = lista.length + " de " + modelos.length + " modelos";
    $("wm-grade").innerHTML = lista.length ? lista.map(card).join("") : '<p class="mw-vazio">Nenhum modelo com esse filtro.</p>';
  }
  function salvarNota(m, campos) {
    var corpo = Object.assign({ nome: m.nome, idioma: m.idioma || "pt_BR" }, campos);
    return pedir("api/whats/modelos/notas", { method: "POST", body: JSON.stringify(corpo) }).then(function (r) {
      var k = chave(m); notas[k] = notas[k] || { etiquetas: [], observacao: null };
      if (campos.etiquetas) notas[k].etiquetas = r.etiquetas || campos.etiquetas;
      if ("observacao" in campos) notas[k].observacao = campos.observacao || null;
      etiquetasTodas = Object.keys(notas).reduce(function (s, kk) { (notas[kk].etiquetas || []).forEach(function (e) { if (s.indexOf(e) < 0) s.push(e); }); return s; }, []).sort();
      pintarEtiquetas(); pintar();
    }).catch(function (e) { toast(e.message, true); });
  }
  function modeloDe(el) { var c = el.closest("[data-chave]"); if (!c) return null; return modelos.find(function (m) { return chave(m) === c.dataset.chave; }) || null; }

  $("wm-grade").addEventListener("click", function (e) {
    var t = e.target, m = modeloDe(t); if (!m) return;
    if (t.dataset.tirar) { salvarNota(m, { etiquetas: (nota(m).etiquetas || []).filter(function (x) { return x !== t.dataset.tirar; }) }); return; }
    if (t.hasAttribute("data-etiqueta")) {
      var v = prompt("Etiqueta para " + m.nome + ":" + (etiquetasTodas.length ? "\n(existentes: " + etiquetasTodas.join(", ") + ")" : ""));
      if (v && v.trim()) salvarNota(m, { etiquetas: (nota(m).etiquetas || []).concat([v.trim()]) });
      return;
    }
    var obs = t.closest("[data-obs]");
    if (obs) {
      var atual = nota(m).observacao || "", ta = document.createElement("textarea"); ta.className = "entrada wm-obs-edita"; ta.value = atual; ta.rows = 2;
      obs.replaceWith(ta); ta.focus();
      var feito = false;
      function fim(salva) { if (feito) return; feito = true; var v = ta.value.trim(); if (salva && v !== atual) salvarNota(m, { observacao: v }); else pintar(); }
      ta.addEventListener("blur", function () { fim(true); });
      ta.addEventListener("keydown", function (ev) { if (ev.key === "Escape") fim(false); if (ev.key === "Enter" && (ev.ctrlKey || ev.metaKey)) fim(true); });
    }
  });
  ["wm-status", "wm-cat", "wm-etq", "wm-de", "wm-ate", "wm-ordem"].forEach(function (id) { $(id).addEventListener("change", pintar); });
  $("wm-busca").addEventListener("input", function () { clearTimeout(temporizador); temporizador = setTimeout(pintar, 250); });

  carregar();
})();
