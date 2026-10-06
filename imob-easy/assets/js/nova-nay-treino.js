/* A aba Treinamento do painel Nova Nay (admin/nova-nay.html). Escolhe conversas reais, põe uma execução na fila
   (quem roda é o processo nay-treino, sem enviar nada), acompanha o progresso e mostra o lado a lado: o que o velho
   mandou ("ANTES") e o que a Nay nova mandaria ("NOVA"), com ✓/✗ por turno, comparação entre execuções e os
   rascunhos de caso de teste dos ✗. Tudo pela ponte /admin/api/nova-nay/treino/... */
(function () {
  "use strict";
  var API = "/admin/api/nova-nay/treino/";
  var $ = function (s) { return document.querySelector(s); };
  function esc(t) { return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function pega(rota, corpo) {
    var op = { credentials: "same-origin" };
    if (corpo) { op.method = "POST"; op.headers = { "Content-Type": "application/json" }; op.body = JSON.stringify(corpo); }
    return fetch(API + rota, op).then(function (r) {
      if (!r.ok) return r.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.detail && j.detail[0] && j.detail[0].msg || j.detail || j.erro || ("HTTP " + r.status)); });
      return r.json();
    });
  }
  function hora(iso) { return iso ? new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : "—"; }
  function dia(iso) { return iso ? new Date(iso + (iso.length === 10 ? "T12:00:00" : "")).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" }) : "—"; }
  function dataHora(iso) { return iso ? new Date(iso).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—"; }
  function fim4(chave) { var d = String(chave || "").replace(/\D/g, ""); return "…" + d.slice(-4); }
  function usd(v) { return "US$ " + Number(v || 0).toFixed(2); }
  function hojeManaus(desloca) { var d = new Date(Date.now() - 4 * 3600 * 1000 - (desloca || 0) * 86400000); return d.toISOString().slice(0, 10); }

  /* ---- escolher ---- */
  var CONVERSAS = [], ESCOLHIDAS = {};
  $("#tr-de").value = hojeManaus(6); $("#tr-ate").value = hojeManaus(0);
  function buscar() {
    var q = new URLSearchParams({ de: $("#tr-de").value, ate: $("#tr-ate").value });
    if ($("#tr-corretor").value.trim()) q.set("corretor", $("#tr-corretor").value.trim());
    if ($("#tr-q").value.trim()) q.set("q", $("#tr-q").value.trim());
    if ($("#tr-so-imovel").checked) q.set("so_com_imovel", "true");
    $("#tr-conversas").innerHTML = '<tr><td colspan="6"><p class="painel__vazio">Carregando…</p></td></tr>';
    pega("conversas?" + q.toString()).then(function (d) {
      CONVERSAS = d.conversas; ESCOLHIDAS = {};
      $("#tr-conversas").innerHTML = CONVERSAS.length ? CONVERSAS.map(function (c, i) {
        return '<tr><td><input type="checkbox" data-conv="' + i + '"></td><td>' + esc(dia(c.dia)) + " " + esc(hora(c.inicio)) + "</td><td>" + esc(c.nome || "") + " <small>" + esc(fim4(c.chave)) + "</small></td><td class=\"num\">" + c.turnos + '</td><td class="txt">' + esc(c.primeiro_texto || "") + "</td><td>" + esc((c.imoveis || []).join(", ") || "—") + "</td></tr>";
      }).join("") : '<tr><td colspan="6"><p class="painel__vazio">Nenhuma conversa de corretor nesse período.</p></td></tr>';
      $("#tr-todas").checked = false; totais();
    }).catch(function (x) { $("#tr-conversas").innerHTML = '<tr><td colspan="6"><p class="painel__vazio">' + esc(x.message) + "</p></td></tr>"; });
  }
  function totais() {
    var n = 0, t = 0, c = 0;
    Object.keys(ESCOLHIDAS).forEach(function (i) { var k = CONVERSAS[i]; n++; t += k.turnos; c += k.custo_estimado || 0; });
    $("#tr-totais").textContent = n ? n + " conversas · " + t + " turnos · ~" + Math.round(t * 0.75) + " precisam do modelo · custo estimado " + usd(c) : CONVERSAS.length + " conversas no período · marque as que quer rodar";
    $("#tr-rodar").disabled = !n;
  }
  $("#tr-conversas").addEventListener("change", function (e) {
    var cb = e.target.closest("[data-conv]"); if (!cb) return;
    if (cb.checked) ESCOLHIDAS[cb.dataset.conv] = 1; else delete ESCOLHIDAS[cb.dataset.conv];
    totais();
  });
  $("#tr-todas").addEventListener("change", function () {
    var on = $("#tr-todas").checked; ESCOLHIDAS = {};
    document.querySelectorAll("[data-conv]").forEach(function (cb) { cb.checked = on; if (on) ESCOLHIDAS[cb.dataset.conv] = 1; });
    totais();
  });
  $("#tr-buscar").addEventListener("click", buscar);
  ["tr-de", "tr-ate", "tr-so-imovel"].forEach(function (id) { $("#" + id).addEventListener("change", buscar); });
  [$("#tr-corretor"), $("#tr-q")].forEach(function (el) { el.addEventListener("keydown", function (e) { if (e.key === "Enter") buscar(); }); });
  $("#tr-rodar").addEventListener("click", function () {
    var convs = Object.keys(ESCOLHIDAS).map(function (i) { var c = CONVERSAS[i]; return { chave: c.chave, dia: c.dia, turno_ids: c.turno_ids }; });
    var cl = (document.querySelector("[name=tr-class]:checked") || {}).value || "reusar";
    $("#tr-rodar").disabled = true;
    pega("execucoes", { conversas: convs, opcoes: { classificacao: cl }, criada_por: "painel" }).then(function (r) {
      ATUAL = r.id; carregarExecucoes(); ligarRelogio();
    }).catch(function (x) { alert("Não deu para criar a execução: " + x.message); $("#tr-rodar").disabled = false; });
  });

  /* ---- execuções ---- */
  var EXECS = [], ATUAL = null, relogio = null;
  function carregarExecucoes() {
    return pega("execucoes").then(function (lista) {
      EXECS = lista;
      $("#tr-execucoes").innerHTML = lista.length ? lista.map(function (e) {
        var r = e.resumo || {}, pct = e.total_turnos ? Math.round(100 * (e.feitos || 0) / e.total_turnos) : 0;
        return '<div class="nn-exec" data-exec="' + e.id + '"' + (e.id === ATUAL ? ' aria-current="true"' : "") + "><b>#" + e.id + "</b><div>" + esc(dataHora(e.criada_em)) + " · " + (e.conversas || 0) + " conversas · " + (e.feitos || 0) + "/" + (e.total_turnos || 0) + " turnos" + (e.versao_codigo ? " · versão " + esc(e.versao_codigo) : "") +
          (e.estado === "rodando" || e.estado === "fila" ? '<div class="barra"><i style="width:' + pct + '%"></i></div>' : "") +
          (e.estado === "pronta" ? "<br><small>mesmo imóvel que o velho " + (r.iguais || 0) + "/" + (r.comparaveis || 0) + " · erros de código " + (r.erros || 0) + " · modelo " + (r.modelo_chamadas || 0) + "× (" + (r.modelo_reusadas || 0) + " reusadas)</small>" : "") +
          (e.erro ? '<br><small style="color:#b53232">' + esc(e.erro) + "</small>" : "") +
          '</div><span>' + usd(e.custo_real) + '</span><span class="estado ' + esc(e.estado) + '">' + esc(e.estado) + "</span></div>";
      }).join("") : '<p class="painel__vazio">Nenhuma execução ainda.</p>';
      if (!lista.some(function (e) { return e.estado === "rodando" || e.estado === "fila"; })) { clearInterval(relogio); relogio = null; }
    });
  }
  function ligarRelogio() {
    if (relogio) return;
    relogio = setInterval(function () { carregarExecucoes(); if (ATUAL) { var e = EXECS.filter(function (x) { return x.id === ATUAL; })[0]; if (e && e.estado === "pronta" && !$("#tr-resultado").dataset.pronta) abrirExecucao(ATUAL); } }, 3000);
  }
  $("#tr-execucoes").addEventListener("click", function (e) { var x = e.target.closest("[data-exec]"); if (x) abrirExecucao(Number(x.dataset.exec)); });

  /* ---- resultado ---- */
  function abrirExecucao(id) {
    ATUAL = id; carregarExecucoes();
    var box = $("#tr-resultado"); box.hidden = false; delete box.dataset.pronta; box.innerHTML = '<p class="painel__vazio">Carregando…</p>';
    pega("execucoes/" + id).then(function (e) {
      var r = e.resumo || {};
      if (e.estado === "pronta") box.dataset.pronta = "1";
      var acoes = Object.keys(r.acoes || {}).sort(function (a, b) { return r.acoes[b] - r.acoes[a]; }).map(function (a) { return esc(a) + " " + r.acoes[a]; }).join(" · ");
      var outras = EXECS.filter(function (x) { return x.id !== id && x.estado === "pronta"; });
      box.innerHTML = '<h2 class="nn-h2">Execução #' + id + ' <span class="estado ' + esc(e.estado) + '">' + esc(e.estado) + "</span></h2>" +
        '<div class="nn-resumo"><span>versão <b>' + esc(e.versao_codigo || "—") + "</b></span><span><b>" + (e.feitos || 0) + "</b>/" + e.total_turnos + " turnos</span><span>mesmo imóvel que o velho <b>" + (r.iguais || 0) + "/" + (r.comparaveis || 0) + "</b></span><span>erros de código <b>" + (r.erros || 0) + "</b></span><span>custo <b>" + usd(e.custo_real) + "</b> (estimado " + usd(e.custo_estimado) + ")</span>" + (acoes ? "<span>ações: " + acoes + "</span>" : "") + (e.erro ? '<span style="color:#b53232">' + esc(e.erro) + "</span>" : "") + "</div>" +
        (outras.length ? '<div class="nn-comparar">Comparar com a execução <select class="selecao" id="tr-outra"><option value="">—</option>' + outras.map(function (x) { return '<option value="' + x.id + '">#' + x.id + " · " + esc(dataHora(x.criada_em)) + "</option>"; }).join("") + '</select><span id="tr-comp"></span></div>' : "") +
        '<div class="nn-convs">' + (e.conversas || []).map(function (c) {
          return '<details class="nn-conv" data-chave="' + esc(c.chave) + '"><summary><b>' + esc(c.nome || "") + " <small>" + esc(fim4(c.chave)) + "</small></b><span>" + esc(dia(c.inicio)) + " " + esc(hora(c.inicio)) + "</span><span>" + c.turnos + " turnos</span><span>igual " + c.iguais + " · diferente " + c.diferentes + (c.erros ? ' · <span style="color:#b53232">' + c.erros + " erro(s)</span>" : "") + (c.marcados_errado ? " · ✗ " + c.marcados_errado : "") + (c.marcados_certo ? " · ✓ " + c.marcados_certo : "") + '</span></summary><div class="nn-turnos"><p class="painel__vazio">Carregando…</p></div></details>';
        }).join("") + "</div>";
      var sel = $("#tr-outra"); if (sel) sel.addEventListener("change", function () { if (sel.value) comparar(id, Number(sel.value)); });
      box.scrollIntoView({ behavior: "smooth", block: "start" });
    }).catch(function (x) { box.innerHTML = '<p class="painel__vazio">' + esc(x.message) + "</p>"; });
  }
  function pecaHTML(p, cls) {
    if (p.tipo === "imagem") return '<span class="peca foto">[foto do ' + p.codigo + "]</span>";
    var para = p.para && p.para !== "turno" && p.para !== "corretor" ? '<span class="peca ' + (p.para === "tel" ? "tel" : "aviso") + '">→ ' + esc(p.para) + ": " + esc(p.texto) + "</span>" : '<span class="peca">' + esc(p.texto) + "</span>";
    return para;
  }
  function turnoHTML(t, divergiuAntes) {
    var antes = t.enviado_antes || [], nova = t.resposta_nova || [];
    var classe = t.igual_imovel === true ? "igual" : t.igual_imovel === false ? "diferente" : "";
    return '<div class="nn-t" data-turno="' + t.turno_origem + '">' +
      (divergiuAntes ? '<div class="nn-aviso-divergiu">A partir daqui a conversa pode não fazer sentido: a mensagem seguinte do corretor respondeu ao "ANTES", não à Nay nova.</div>' : "") +
      '<span class="h">' + esc(hora(t.horario_original)) + '</span><span class="quem">corretor</span><div class="fala">' + esc(t.texto) + "</div>" +
      '<span></span><span class="quem">antes</span><div class="fala antes">' + (antes.length ? antes.map(pecaHTML).join("") : "<i>calou</i>") + "</div>" +
      '<span></span><span class="quem">nova</span><div class="fala nova ' + classe + '">' + (t.erro ? '<span class="selo erro">erro de código</span> ' + esc(t.erro) : (nova.length ? nova.map(pecaHTML).join("") : "<i>calou</i>")) +
      '<div><span class="selo">' + esc(t.acao || "—") + (t.template ? " · " + esc(t.template) : "") + "</span>" + ((t.imovel || []).length ? '<span class="selo">' + esc(t.imovel.join(", ")) + "</span>" : "") + (t.estado_depois ? '<span class="selo">' + esc(t.estado_depois) + "</span>" : "") + (t.modelo_chamadas ? '<span class="selo">modelo</span>' : "") + "</div></div>" +
      '<span></span><div class="acoes"><button type="button" class="certo" aria-pressed="' + (t.veredito === "certo") + '">✓ certo</button><button type="button" class="errado" aria-pressed="' + (t.veredito === "errado") + '">✗ errado</button><input type="text" placeholder="O que deveria ter feito" value="' + esc(t.nota || "") + '"><button type="button" class="caminho" data-caminho="' + esc((t.caminho_nos || []).join(",")) + '">caminho</button></div></div>';
  }
  document.addEventListener("toggle", function (e) {
    var d = e.target; if (!d.classList || !d.classList.contains("nn-conv") || !d.open || d.dataset.carregada) return;
    d.dataset.carregada = "1";
    pega("execucoes/" + ATUAL + "/conversas/" + encodeURIComponent(d.dataset.chave)).then(function (c) {
      var divergiu = false;
      d.querySelector(".nn-turnos").innerHTML = c.turnos.map(function (t) { var h = turnoHTML(t, divergiu); if (t.igual_imovel === false) divergiu = true; return h; }).join("");
    }).catch(function (x) { d.querySelector(".nn-turnos").innerHTML = '<p class="painel__vazio">' + esc(x.message) + "</p>"; });
  }, true);
  $("#tr-resultado").addEventListener("click", function (e) {
    var cam = e.target.closest("[data-caminho]");
    if (cam) { if (window.NN) window.NN.acender(cam.dataset.caminho ? cam.dataset.caminho.split(",") : []); return; }
    var b = e.target.closest(".acoes button.certo, .acoes button.errado"); if (!b) return;
    var t = b.closest("[data-turno]"), nota = t.querySelector("input").value.trim();
    var veredito = b.classList.contains("certo") ? "certo" : "errado";
    pega("marcacoes", { turno_origem: Number(t.dataset.turno), veredito: veredito, nota: nota || null, marcado_por: "painel" }).then(function () {
      t.querySelector(".certo").setAttribute("aria-pressed", veredito === "certo");
      t.querySelector(".errado").setAttribute("aria-pressed", veredito === "errado");
    }).catch(function (x) { alert("Não gravou a marcação: " + x.message); });
  });
  function comparar(id, outra) {
    $("#tr-comp").textContent = "comparando…";
    pega("execucoes/" + id + "/comparar/" + outra).then(function (d) {
      var c = d.contagem;
      $("#tr-comp").innerHTML = '<span class="nn-dif melhorou">melhorou ' + (c.melhorou || 0) + '</span> <span class="nn-dif piorou">piorou ' + (c.piorou || 0) + '</span> <span class="nn-dif mudou">mudou ' + (c.mudou || 0) + "</span> igual " + (c.igual || 0) +
        (d.turnos.length ? '<div style="margin-top:6px">' + d.turnos.slice(0, 40).map(function (t) { return '<div><span class="nn-dif ' + t.diferenca + '">' + t.diferenca + "</span> " + esc(fim4(t.chave)) + " “" + esc((t.texto || "").slice(0, 80)) + "” — nova: " + esc(t.nova.acao || "—") + (t.nova.imovel ? " " + esc(t.nova.imovel.join(",")) : "") + " · antes: " + esc(t.antiga.acao || "—") + (t.antiga.imovel ? " " + esc(t.antiga.imovel.join(",")) : "") + "</div>"; }).join("") + "</div>" : "");
    }).catch(function (x) { $("#tr-comp").textContent = x.message; });
  }

  /* ---- casos ---- */
  $("#tr-casos").addEventListener("click", function () {
    var box = $("#tr-casos-caixa"); box.hidden = false; box.innerHTML = '<p class="painel__vazio">Gerando…</p>';
    pega("casos").then(function (lista) {
      box.innerHTML = '<h2 class="nn-h2">Rascunhos de caso (' + lista.length + ") <button type=\"button\" class=\"btn-neutro\" data-fechar-casos>Fechar</button></h2>" +
        (lista.length ? '<p class="pagina-subtitulo">Cada ✗ vira um caso no formato de <code>tests/casos/</code>. Quem conserta ajusta o <code>esperado</code> e move para a pasta. Também saem por <code>make casos-do-painel</code> no nay-core.</p><pre>' + esc(lista.map(function (c) { return "# --- " + c.nome + ".yaml\n" + c.yaml; }).join("\n")) + "</pre>" : '<p class="painel__vazio">Nenhum turno marcado como errado ainda.</p>');
      box.scrollIntoView({ behavior: "smooth", block: "start" });
    }).catch(function (x) { box.innerHTML = '<p class="painel__vazio">' + esc(x.message) + "</p>"; });
  });
  document.addEventListener("click", function (e) { if (e.target.closest("[data-fechar-casos]")) $("#tr-casos-caixa").hidden = true; });

  var carregou = false;
  document.querySelector("[data-abas-funcionais]").addEventListener("click", function (e) {
    var b = e.target.closest("[data-painel-abre]");
    if (b && b.dataset.painelAbre === "treino" && !carregou) { carregou = true; buscar(); carregarExecucoes().then(function () { if (EXECS.some(function (x) { return x.estado === "rodando" || x.estado === "fila"; })) ligarRelogio(); }); }
  });
})();
