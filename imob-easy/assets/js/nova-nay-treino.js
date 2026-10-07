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
  function hora(iso) { return iso ? new Date(iso).toLocaleTimeString("pt-BR", { timeZone: "America/Manaus", hour: "2-digit", minute: "2-digit" }) : "—"; }
  function dia(iso) { return iso ? new Date(iso + (iso.length === 10 ? "T12:00:00" : "")).toLocaleDateString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit" }) : "—"; }
  function dataHora(iso) { return iso ? new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—"; }
  function fim4(chave) { var d = String(chave || "").replace(/\D/g, ""); return "…" + d.slice(-4); }
  function usd(v) { return "US$ " + Number(v || 0).toFixed(2); }
  function hojeManaus(desloca) { var d = new Date(Date.now() - 4 * 3600 * 1000 - (desloca || 0) * 86400000); return d.toISOString().slice(0, 10); }

  /* ---- escolher ---- */
  var CONVERSAS = [], ESCOLHIDAS = {};
  $("#tr-de").value = hojeManaus(0); $("#tr-ate").value = hojeManaus(0);   /* começa no dia de hoje */
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
      ATUAL = r.id; $("#tr-resultado").hidden = false; $("#tr-resultado").innerHTML = '<p class="painel__vazio">Rodando a rodada #' + r.id + "… ela abre sozinha quando terminar.</p>"; delete $("#tr-resultado").dataset.pronta;
      carregarExecucoes(); ligarRelogio(); $("#tr-rodar").disabled = false;
    }).catch(function (x) { alert("Não deu para criar a execução: " + x.message); $("#tr-rodar").disabled = false; });
  });

  /* ---- execuções ---- */
  var EXECS = [], ATUAL = null, relogio = null;
  function rotuloDaRodada(e) {
    var r = e.resumo || {};
    return "#" + e.id + " · " + dataHora(e.criada_em) + " · " + (e.conversas || 0) + " conversas" +
      (e.estado === "pronta" ? " · mesmo imóvel " + (r.iguais || 0) + "/" + (r.comparaveis || 0) + (e.versao_codigo ? " · versão " + e.versao_codigo : "")
        : e.estado === "rodando" ? " · rodando " + (e.feitos || 0) + "/" + (e.total_turnos || 0)
        : " · " + e.estado);
  }
  function carregarExecucoes() {
    return pega("execucoes").then(function (lista) {
      EXECS = lista;
      var sel = $("#tr-rodada");
      sel.innerHTML = lista.length ? lista.map(function (e, i) {
        return '<option value="' + e.id + '"' + (e.id === ATUAL ? " selected" : "") + ">" + esc(rotuloDaRodada(e)) + (i === 0 ? " (a mais nova)" : "") + "</option>";
      }).join("") : "<option value=\"\">nenhuma rodada ainda</option>";
      sel.disabled = !lista.length; $("#tr-de-novo").disabled = !lista.length;
      var viva = lista.filter(function (e) { return e.estado === "rodando" || e.estado === "fila"; })[0], and = $("#tr-andamento");
      if (viva) {
        var pct = viva.total_turnos ? Math.round(100 * (viva.feitos || 0) / viva.total_turnos) : 0;
        and.hidden = false;
        and.innerHTML = "<span>Rodada #" + viva.id + (viva.estado === "fila" ? " na fila…" : " rodando: " + (viva.feitos || 0) + " de " + (viva.total_turnos || 0) + " mensagens") + '</span><div class="barra"><i style="width:' + pct + '%"></i></div>';
      } else { and.hidden = true; clearInterval(relogio); relogio = null; }
    });
  }
  function ligarRelogio() {
    if (relogio) return;
    relogio = setInterval(function () {
      carregarExecucoes().then(function () {
        var e = EXECS.filter(function (x) { return x.id === ATUAL; })[0];
        if (e && e.estado === "pronta" && !$("#tr-resultado").dataset.pronta) abrirExecucao(ATUAL, true);
      });
    }, 2500);
  }
  $("#tr-rodada").addEventListener("change", function () { if ($("#tr-rodada").value) abrirExecucao(Number($("#tr-rodada").value), true); });
  /* a mesma seleção de conversas, com o código de agora: é como se confere uma correção */
  $("#tr-de-novo").addEventListener("click", function () {
    if (!EXEC || !EXEC.selecao) return;
    $("#tr-de-novo").disabled = true;
    pega("execucoes", { conversas: EXEC.selecao.conversas, opcoes: { classificacao: "reusar" }, criada_por: "painel (de novo #" + EXEC.id + ")" }).then(function (r) {
      ATUAL = r.id; $("#tr-resultado").innerHTML = '<p class="painel__vazio">Rodando a rodada #' + r.id + "… ela abre sozinha quando terminar.</p>"; delete $("#tr-resultado").dataset.pronta;
      carregarExecucoes(); ligarRelogio();
    }).catch(function (x) { alert("Não deu para rodar de novo: " + x.message); $("#tr-de-novo").disabled = false; });
  });

  /* ---- resultado ---- */
  /* O desenho é o da rodada de treino antiga (Cérebro › Conversa): à esquerda a lista das conversas, à direita a
     conversa em balões de WhatsApp, as setas para ir de uma à outra e, embaixo, a ficha: conversou corretamente,
     o erro e a solução. O julgamento é DA CONVERSA e fica preso à primeira mensagem real dela. */
  var EXEC = null, CONVS = [], IDX = -1, TURNOS = null, JULG = {}, FILTRO = "todas", VER_ANTES = true;
  function iniciais(nome) { var p = String(nome || "?").trim().split(/\s+/); return ((p[0] || "?").charAt(0) + (p.length > 1 ? p[p.length - 1].charAt(0) : "")).toUpperCase(); }
  function julgada(c) { return c.veredito_conversa || ""; }
  function visiveis() {
    return CONVS.map(function (c, i) { return i; }).filter(function (i) {
      var c = CONVS[i], v = julgada(c);
      return FILTRO === "todas" || (FILTRO === "julgar" && !v) || (FILTRO === "erro" && v === "errado") || (FILTRO === "certo" && v === "certo") || (FILTRO === "dif" && c.diferentes > 0);
    });
  }
  function abrirExecucao(id, semRolar) {
    ATUAL = id; carregarExecucoes();
    var box = $("#tr-resultado"); box.hidden = false; delete box.dataset.pronta; box.innerHTML = '<p class="painel__vazio">Carregando…</p>';
    pega("execucoes/" + id).then(function (e) {
      EXEC = e; CONVS = e.conversas || []; IDX = -1; TURNOS = null;
      var r = e.resumo || {};
      if (e.estado === "pronta") box.dataset.pronta = "1"; else if (e.estado !== "erro") ligarRelogio();
      var outras = EXECS.filter(function (x) { return x.id !== id && x.estado === "pronta"; });
      box.innerHTML = '<div class="nn-resumo"><span>Execução <b>#' + id + '</b> <span class="estado ' + esc(e.estado) + '">' + esc(e.estado) + "</span></span><span><b>" + CONVS.length + "</b> conversas · <b>" + (e.feitos || 0) + "</b>/" + e.total_turnos + " mensagens</span><span>mesmo imóvel que antes <b>" + (r.iguais || 0) + "/" + (r.comparaveis || 0) + "</b></span><span>erros de código <b>" + (r.erros || 0) + "</b></span>" + (r.segundos ? "<span>rodou em <b>" + Math.round(r.segundos) + " s</b></span>" : "") + "<span>custo <b>" + usd(e.custo_real) + "</b></span>" + (e.erro ? '<span style="color:#b53232">' + esc(e.erro) + "</span>" : "") +
        (outras.length ? '<span class="nn-comparar">comparar com <select class="selecao" id="tr-outra"><option value="">—</option>' + outras.map(function (x) { return '<option value="' + x.id + '">#' + x.id + " · " + esc(dataHora(x.criada_em)) + "</option>"; }).join("") + "</select></span>" : "") + '</div><div id="tr-comp"></div>' +
        '<div class="nw-palco"><div class="nw-indice"><div class="nw-indice-topo" id="nw-filtros"></div><div class="nw-itens" id="nw-itens"></div></div><div class="nw-conversa" id="nw-conversa"><p class="nw-vazio">Escolha uma conversa na lista ao lado.</p></div></div>';
      var sel = $("#tr-outra"); if (sel) sel.addEventListener("change", function () { if (sel.value) comparar(id, Number(sel.value)); });
      desenharIndice();
      var v = visiveis(); if (v.length) abrirConversa(v[0]);
      if (!semRolar) box.scrollIntoView({ behavior: "smooth", block: "start" });
    }).catch(function (x) { box.innerHTML = '<p class="painel__vazio">' + esc(x.message) + "</p>"; });
  }
  function desenharIndice() {
    var n = { todas: CONVS.length, julgar: 0, erro: 0, certo: 0, dif: 0 };
    CONVS.forEach(function (c) { var v = julgada(c); if (!v) n.julgar++; if (v === "errado") n.erro++; if (v === "certo") n.certo++; if (c.diferentes > 0) n.dif++; });
    $("#nw-filtros").innerHTML = [["todas", "Todas"], ["julgar", "Por julgar"], ["erro", "Erro"], ["certo", "Certo"], ["dif", "Imóvel diferente"]].map(function (f) {
      return '<button type="button" class="nw-filtro" data-filtro="' + f[0] + '" aria-pressed="' + (FILTRO === f[0]) + '">' + f[1] + " <b>" + n[f[0]] + "</b></button>";
    }).join("");
    var v = visiveis();
    $("#nw-itens").innerHTML = v.length ? v.map(function (i, pos) {
      var c = CONVS[i], jg = julgada(c);
      var selo = jg === "certo" ? '<span class="nw-selo ok">certo</span>' : jg === "errado" ? '<span class="nw-selo erro">erro</span>' : '<span class="nw-selo">por julgar</span>';
      return '<button type="button" class="nw-item" data-conv="' + i + '" aria-selected="' + (i === IDX) + '"><span class="nw-item-topo"><span class="nw-n">' + (pos + 1) + "</span>" + selo + (c.diferentes > 0 ? '<span class="nw-selo dif">≠ imóvel</span>' : "") + (c.erros ? '<span class="nw-selo erro">falhou</span>' : "") + (c.turnos_errado ? '<span class="nw-selo erro">✗ ' + c.turnos_errado + "</span>" : "") + (c.turnos_certo ? '<span class="nw-selo ok">✓ ' + c.turnos_certo + "</span>" : "") + '<span class="nw-n" style="margin-left:auto">' + esc(hora(c.inicio)) + '</span></span><span class="nw-item-nome">' + esc(c.nome || "(sem nome)") + " <small>" + esc(fim4(c.chave)) + '</small></span><span class="nw-item-t">' + c.turnos + (c.turnos === 1 ? " mensagem" : " mensagens") + "</span></button>";
    }).join("") : '<p class="nw-vazio">Nada com esse filtro.</p>';
  }
  function abrirConversa(i) {
    IDX = i; TURNOS = null; desenharIndice();
    var alvo = $("#nw-conversa"); alvo.innerHTML = '<p class="nw-vazio">Carregando…</p>';
    var sel = document.querySelector('.nw-item[aria-selected="true"]'); if (sel && sel.scrollIntoView) sel.scrollIntoView({ block: "nearest" });
    pega("execucoes/" + ATUAL + "/conversas/" + encodeURIComponent(CONVS[i].chave)).then(function (c) {
      if (IDX !== i) return;
      TURNOS = c.turnos; JULG = c.julgamento || {}; desenharConversa();
    }).catch(function (x) { alvo.innerHTML = '<p class="nw-vazio">' + esc(x.message) + "</p>"; });
  }
  function balao(lado, texto, carimbo, extra) {
    return '<div class="nw-b nw-b--' + lado + (extra ? " " + extra : "") + '">' + esc(texto) + (carimbo ? "<time>" + esc(carimbo) + "</time>" : "") + "</div>";
  }
  /* as peças de um lado viram balões na ordem em que saíram; fotos seguidas do mesmo imóvel, um balão "(12 fotos)" */
  function baloes(lista, classe, carimbo) {
    var saida = [], fotos = null;
    function fecha() { if (fotos) { saida.push(balao("dela", "(" + fotos.n + (fotos.n === 1 ? " foto" : " fotos") + " do " + fotos.codigo + ")", carimbo, classe + " nw-b--fotos")); fotos = null; } }
    (lista || []).forEach(function (p) {
      if (p.tipo === "imagem") { if (fotos && fotos.codigo === p.codigo) fotos.n++; else { fecha(); fotos = { codigo: p.codigo, n: 1 }; } return; }
      fecha();
      var fora = p.para && p.para !== "turno" && p.para !== "corretor";
      saida.push(balao("dela", (fora ? "[para " + p.para + "] " : "") + (p.texto || ""), carimbo, classe + (fora ? " nw-b--aviso" : "")));
    });
    fecha();
    return saida.join("");
  }
  function turnoHTML(t) {
    var antes = t.enviado_antes || [], nova = t.resposta_nova || [], h = hora(t.horario_original);
    var selo = t.igual_imovel === false ? '<b class="dif">imóvel diferente</b> · ' : t.igual_imovel === true ? '<b class="ok">mesmo imóvel</b> · ' : "";
    var colNova = t.erro ? balao("dela", t.erro, "", "nw-b--agora nw-b--alerta") : nova.length ? baloes(nova, "nw-b--agora", h) : '<div class="nw-calou">fica calada</div>';
    return '<div class="nw-turno" data-turno="' + t.turno_origem + '">' + balao("dele", t.texto, h) +
      '<div class="nw-par' + (VER_ANTES ? "" : " nw-par--so-nova") + '">' +
        (VER_ANTES ? '<div class="nw-col nw-col--antes"><div class="nw-rot">Nay antiga · o que foi respondido</div>' + (antes.length ? baloes(antes, "", h) : '<div class="nw-calou">ninguém respondeu</div>') + "</div>" : "") +
        '<div class="nw-col nw-col--nova' + (t.igual_imovel === false ? " dif" : "") + '"><div class="nw-rot nova">Nay nova · o que ela responde</div>' + colNova +
          '<div class="nw-acao">' + selo + esc(t.acao || "—") + (t.template ? " · " + esc(t.template) : "") + ((t.imovel || []).length ? " · imóvel " + esc(t.imovel.join(", ")) : "") + ' · <button type="button" data-caminho="' + esc((t.caminho_nos || []).join(",")) + '">ver nos nós</button></div></div>' +
      "</div>" +
      '<div class="nw-julga"><button type="button" class="certo" data-turno-veredito="certo" aria-pressed="' + (t.veredito === "certo") + '">✓ certo</button><button type="button" class="errado" data-turno-veredito="errado" aria-pressed="' + (t.veredito === "errado") + '">✗ errado</button><input type="text" placeholder="Neste turno ela deveria ter… (Enter grava)" value="' + esc(t.nota || "") + '"><span class="gravou" hidden>gravado</span></div></div>';
  }
  /* o certo/errado de UM turno (o que ele gostou na primeira versão): grava na hora, a nota vai junto */
  function julgarTurno(caixa, veredito) {
    var id = Number(caixa.dataset.turno), nota = caixa.querySelector(".nw-julga input").value.trim();
    pega("marcacoes", { execucao_id: ATUAL, turno_origem: id, veredito: veredito, nota: nota || null, marcado_por: "painel" }).then(function () {
      var t = (TURNOS || []).filter(function (x) { return x.turno_origem === id; })[0];
      if (t) { t.veredito = veredito; t.nota = nota; }
      caixa.querySelector(".certo").setAttribute("aria-pressed", veredito === "certo");
      caixa.querySelector(".errado").setAttribute("aria-pressed", veredito === "errado");
      var g = caixa.querySelector(".gravou"); g.hidden = false; setTimeout(function () { g.hidden = true; }, 1600);
      var c = CONVS[IDX]; c.turnos_errado = TURNOS.filter(function (x) { return x.veredito === "errado"; }).length; c.turnos_certo = TURNOS.filter(function (x) { return x.veredito === "certo"; }).length;
      desenharIndice();
    }).catch(function (x) { alert("Não gravou: " + x.message); });
  }
  function desenharConversa() {
    var c = CONVS[IDX], alvo = $("#nw-conversa"), v = visiveis(), pos = v.indexOf(IDX);
    var t0 = { nota: JULG.nota }, certo = JULG.veredito === "certo", errado = JULG.veredito === "errado";
    var sol = (JULG.esperado && JULG.esperado.solucao) || "";
    alvo.innerHTML =
      '<div class="nw-topo"><span class="nw-ini">' + esc(iniciais(c.nome)) + "</span><span class=\"nw-quem\"><h4>" + esc(c.nome || "(sem nome)") + " <small>" + esc(fim4(c.chave)) + "</small></h4><small>" + esc(dia(c.inicio)) + " · " + c.turnos + (c.turnos === 1 ? " mensagem" : " mensagens") + "</small></span>" +
        '<label class="nw-ver"><input type="checkbox" id="nw-ver-antes"' + (VER_ANTES ? " checked" : "") + "> comparar com a Nay antiga</label>" +
        '<span class="nw-nav"><button type="button" class="nw-seta" data-ir="-1" title="Conversa anterior (←)"' + (pos <= 0 ? " disabled" : "") + '>‹</button><span class="nw-pos">' + (pos + 1) + " / " + v.length + '</span><button type="button" class="nw-seta" data-ir="1" title="Próxima conversa (→)"' + (pos >= v.length - 1 ? " disabled" : "") + ">›</button></span></div>" +
      '<div class="nw-baloes" id="nw-baloes"><div class="nw-dia">' + esc(dia(c.inicio)) + "</div>" + TURNOS.map(turnoHTML).join("") + "</div>" +
      '<div class="nw-ficha"><div class="nw-ficha-linha"><b class="nw-ficha-t">A conversa inteira:</b><button type="button" class="nw-ok" data-veredito="certo" aria-pressed="' + certo + '">✓ Conversou corretamente</button><button type="button" class="nw-ruim" data-veredito="errado" aria-pressed="' + errado + '">✗ Errou</button><span class="nw-marca" id="nw-marca">' + (certo ? "julgada como <b>certa</b>" : errado ? "julgada como <b>errada</b>" : "ainda não julgada") + '</span><button type="button" class="nw-seta nw-seta--grande" data-ir="1"' + (pos >= v.length - 1 ? " disabled" : "") + ">Próxima ›</button></div>" +
        '<div class="nw-campos"><div class="nw-cx nw-cx--erro"><label for="nw-erro">O erro</label><textarea id="nw-erro" placeholder="O que ela fez de errado nesta conversa?">' + esc(t0.nota || "") + '</textarea></div><div class="nw-cx nw-cx--sol"><label for="nw-sol">A solução</label><textarea id="nw-sol" placeholder="O que ela deveria ter feito? É só uma regra? Precisa mudar alguma coisa?">' + esc(sol) + "</textarea></div></div>" +
        '<button type="button" class="nw-salvar" id="nw-salvar">Salvar</button><span class="nw-estado" id="nw-estado"></span></div>';
    var b = $("#nw-baloes"); b.scrollTop = 0;
  }
  function julgar(veredito, avancar) {
    if (!TURNOS || !TURNOS.length) return;
    var erro = $("#nw-erro").value.trim(), sol = $("#nw-sol").value.trim(), c = CONVS[IDX], t0 = TURNOS[0];
    $("#nw-estado").textContent = "gravando…";
    pega("marcacoes", { execucao_id: ATUAL, turno_origem: -t0.turno_origem, veredito: veredito, nota: erro || null, esperado: { escopo: "conversa", solucao: sol || null }, marcado_por: "painel" }).then(function () {
      JULG = { veredito: veredito, nota: erro, esperado: { escopo: "conversa", solucao: sol } };
      c.veredito_conversa = veredito;
      var v = visiveis(), pos = v.indexOf(IDX);
      if (avancar && pos >= 0 && pos < v.length - 1) return abrirConversa(v[pos + 1]);
      desenharIndice(); desenharConversa(); $("#nw-estado").textContent = "salvo";
    }).catch(function (x) { $("#nw-estado").textContent = "não gravou: " + x.message; });
  }
  function ir(passo) {
    var v = visiveis(), pos = v.indexOf(IDX), alvo = v[pos + passo];
    if (alvo !== undefined) abrirConversa(alvo);
  }
  $("#tr-resultado").addEventListener("click", function (e) {
    var cam = e.target.closest("[data-caminho]");
    if (cam) { if (window.NN) window.NN.acender(cam.dataset.caminho ? cam.dataset.caminho.split(",") : []); return; }
    var f = e.target.closest("[data-filtro]"); if (f) { FILTRO = f.dataset.filtro; desenharIndice(); var v = visiveis(); if (v.length && v.indexOf(IDX) < 0) abrirConversa(v[0]); else if (TURNOS) desenharConversa(); return; }
    var it = e.target.closest("[data-conv]"); if (it) return abrirConversa(Number(it.dataset.conv));
    var s = e.target.closest("[data-ir]"); if (s) return ir(Number(s.dataset.ir));
    var tv = e.target.closest("[data-turno-veredito]"); if (tv) return julgarTurno(tv.closest("[data-turno]"), tv.dataset.turnoVeredito);
    var vd = e.target.closest("[data-veredito]"); if (vd) return julgar(vd.dataset.veredito, vd.dataset.veredito === "certo");
    if (e.target.closest("#nw-salvar")) {
      var marcado = JULG.veredito;
      return julgar($("#nw-erro").value.trim() ? "errado" : (marcado || "errado"), false);
    }
  });
  $("#tr-resultado").addEventListener("change", function (e) { if (e.target.id === "nw-ver-antes") { VER_ANTES = e.target.checked; desenharConversa(); } });
  $("#tr-resultado").addEventListener("keydown", function (e) {
    var i = e.target.closest && e.target.closest(".nw-julga input"); if (!i || e.key !== "Enter") return;
    var cx = i.closest("[data-turno]"); julgarTurno(cx, cx.querySelector(".certo").getAttribute("aria-pressed") === "true" ? "certo" : "errado");
  });
  document.addEventListener("keydown", function (e) {
    if ($("[data-painel='treino']").hidden || !TURNOS || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
    if (e.key === "ArrowRight") ir(1); else if (e.key === "ArrowLeft") ir(-1);
  });
  function comparar(id, outra) {
    $("#tr-comp").textContent = "comparando…";
    pega("execucoes/" + id + "/comparar/" + outra).then(function (d) {
      var c = d.contagem;
      $("#tr-comp").innerHTML = '<div class="nn-comp"><span class="nn-dif melhorou">melhorou ' + (c.melhorou || 0) + '</span> <span class="nn-dif piorou">piorou ' + (c.piorou || 0) + '</span> <span class="nn-dif mudou">mudou ' + (c.mudou || 0) + "</span> igual " + (c.igual || 0) +
        (d.turnos.length ? '<div style="margin-top:6px">' + d.turnos.slice(0, 40).map(function (t) { return '<div><span class="nn-dif ' + t.diferenca + '">' + t.diferenca + "</span> " + esc(fim4(t.chave)) + " “" + esc((t.texto || "").slice(0, 80)) + "” — nova: " + esc(t.nova.acao || "—") + (t.nova.imovel ? " " + esc(t.nova.imovel.join(",")) : "") + " · antes: " + esc(t.antiga.acao || "—") + (t.antiga.imovel ? " " + esc(t.antiga.imovel.join(",")) : "") + "</div>"; }).join("") + "</div>" : "") + "</div>";
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
    if (b && b.dataset.painelAbre === "treino" && !carregou) { carregou = true; buscar(); carregarExecucoes().then(function () { if (EXECS.some(function (x) { return x.estado === "rodando" || x.estado === "fila"; })) ligarRelogio(); if (EXECS.length) abrirExecucao(EXECS[0].id, true); else $("#tr-escolha").open = true; }); }
  });
})();
