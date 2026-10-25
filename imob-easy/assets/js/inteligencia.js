/* A PÁGINA INTELIGÊNCIA (Pedro, 25/10/2026): as abas, o fundo escuro, a análise da Nay Parceria (como ela acerta e o que
   foi levado para as outras) e a biblioteca de conversas (certo × erro, 498). As regras (1ª aba) são do inteligencias.js;
   o painel de estudos é do inteligencia-estudos.js. As abas ficam no endereço (#analise, #biblioteca, #estudos). */
(function () {
  "use strict";

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; });
  }
  function pedir(url) {
    return fetch(url, { credentials: "same-origin" }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status));
        return j;
      });
    });
  }
  window.IE = { esc: esc, pedir: pedir };

  /* ---------- o fundo escuro ---------- */
  var botaoTema = document.getElementById("ie-tema");
  function tema(escuro) {
    if (escuro) document.documentElement.setAttribute("data-tema", "escuro");
    else document.documentElement.removeAttribute("data-tema");
    botaoTema.setAttribute("aria-pressed", escuro ? "true" : "false");
    document.getElementById("ie-tema-rotulo").textContent = escuro ? "Fundo claro" : "Fundo escuro";
    try { localStorage.setItem("ie-tema", escuro ? "escuro" : "claro"); } catch (e) { /* sem armazenamento: vale só agora */ }
  }
  tema(document.documentElement.getAttribute("data-tema") === "escuro");
  botaoTema.addEventListener("click", function () { tema(document.documentElement.getAttribute("data-tema") !== "escuro"); });

  /* ---------- as abas ---------- */
  var abas = document.querySelectorAll(".ie-abas [data-aba]");
  var carregadas = {};
  function abrir(nome) {
    var achou = false;
    abas.forEach(function (b) { var s = b.getAttribute("data-aba") === nome; achou = achou || s; b.setAttribute("aria-selected", s ? "true" : "false"); });
    if (!achou) { nome = "regras"; abas[0].setAttribute("aria-selected", "true"); }
    document.querySelectorAll(".ie-painel").forEach(function (p) { p.hidden = p.getAttribute("data-painel") !== nome; });
    if (!carregadas[nome]) {
      carregadas[nome] = true;
      if (nome === "analise") analise();
      if (nome === "biblioteca") biblioteca();
      if (nome === "estudos" && window.IEstudos) window.IEstudos.abrir();
    }
  }
  abas.forEach(function (b) {
    b.addEventListener("click", function () {
      var nome = b.getAttribute("data-aba");
      history.replaceState(null, "", nome === "regras" ? location.pathname : "#" + nome);
      abrir(nome);
    });
  });
  abrir((location.hash || "").replace("#", "") || "regras");

  /* ---------- a análise ---------- */
  var SEL = { tem: "tem", parcial: "parcial", "não": "nao", nao: "nao", "não se aplica": "na" };
  function selo(v) {
    var k = SEL[v] || (String(v).indexOf("tem") === 0 ? "tem" : "parcial");
    return '<span class="ie-sel ie-sel--' + k + '">' + esc(v) + "</span>";
  }
  function analise() {
    var alvo = document.getElementById("ie-analise");
    pedir("dados/inteligencia/analise.json?v=" + Date.now()).then(function (a) {
      var nomes = {}; (a.nays || []).forEach(function (n) { nomes[n.chave] = n.nome; });
      var h = '<div class="ie-cartao"><h2>' + esc(a.titulo) + '</h2><ul class="ie-resumo">' +
        (a.resumo || []).map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul></div>";
      var t = a.numeros || {};
      h += '<div class="ie-cartao"><h2>Os números de outubro</h2><div class="ie-rolar"><table class="ie-tabela"><thead><tr><th></th>' +
        (t.colunas || []).map(function (c) { return "<th>" + esc(c) + "</th>"; }).join("") + "</tr></thead><tbody>" +
        (t.linhas || []).map(function (l) { return "<tr>" + l.map(function (c, i) { return i ? "<td>" + esc(c) + "</td>" : "<th>" + esc(c) + "</th>"; }).join("") + "</tr>"; }).join("") +
        "</tbody></table></div></div>";
      h += '<div class="ie-cartao"><h2>As 14 camadas da Parceria, e quem mais tem cada uma</h2>' +
        '<p>Verde cheio = tem; tracejado laranja = tem em parte; vermelho = não tem. As camadas com "redundância" pegam o mesmo erro que outra já pegaria: é isso que faz ela errar menos.</p>' +
        (a.camadas || []).map(function (c) {
          return '<div class="ie-camada"><h3>' + esc(c.nome) + "</h3><p>" + esc(c.explicacao) + "</p>" +
            (c.redundancia ? '<p class="ie-camada__red"><b>Redundância:</b> ' + esc(c.redundancia) + "</p>" : "") +
            '<p class="ie-camada__onde">' + esc(c.onde) + "</p>" +
            '<div class="ie-nays">' + Object.keys(c.nays || {}).map(function (k) { return '<span title="' + esc(nomes[k] || k) + '">' + esc(nomes[k] || k) + ": " + selo(c.nays[k]) + "</span>"; }).join("") + "</div></div>";
        }).join("") + "</div>";
      h += '<div class="ie-cartao"><h2>Como ela rodou e acertou (o ciclo de correção)</h2><div class="ie-ciclo">' +
        (a.ciclo || []).map(function (c) { return "<div><b>" + esc(c.passo) + "</b>" + esc(c.detalhe) + "</div>"; }).join("") + "</div></div>";
      h += '<div class="ie-cartao"><h2>O que já foi levado para as outras</h2>' + (a.aplicado_agora || []).map(function (x) {
        return '<div class="ie-camada"><h3>' + esc(x.o_que) + " · " + (x.nays || []).map(function (k) { return esc(nomes[k] || k); }).join(", ") + "</h3><p>" + esc(x.detalhe) + '</p><p class="ie-camada__onde">' + esc(x.onde) + "</p></div>";
      }).join("") + "</div>";
      h += '<div class="ie-cartao"><h2>O que falta levar (na ordem do que mais ajuda)</h2><div class="ie-rolar"><table class="ie-tabela"><thead><tr><th>O quê</th><th>Por quê</th><th>Para</th><th>Esforço</th></tr></thead><tbody>' +
        (a.falta || []).map(function (x) { return "<tr><td><b>" + esc(x.o_que) + "</b></td><td>" + esc(x.por_que) + "</td><td>" + (x.para || []).map(function (k) { return esc(nomes[k] || k); }).join(", ") + "</td><td>" + esc(x.esforco) + "</td></tr>"; }).join("") +
        "</tbody></table></div></div>";
      alvo.innerHTML = h;
    }).catch(function (e) { alvo.innerHTML = '<p class="ag-vazio">Não li a análise: ' + esc(e.message) + "</p>"; });
  }

  /* ---------- a biblioteca ---------- */
  var NOME_NAY = { parceria: "Parceria", leads: "Leads", olx: "OLX", corretores: "Corretores", captacao: "Captação", cadastro: "Cadastro", velha: "Nay velha" };
  var FONTE = { pedro_chat: "Pedro (chat do Claude)", pedido_ao_agente: "Pedro/Tel no agente de revisão", treino_pedro: "Pedro (tela de treino)",
    agente_revisao: "agente de revisão (VPS2)", commit_core: "correção no código (commit)", revisao_gemini: "Gemini (revisão da semana)",
    nota_automatica: "nota automática (notas_nay.py)" };
  var pagina = 0, filtros = {};
  function dia(d) { if (!d) return ""; var p = String(d).slice(0, 10).split("-"); return p[2] + "/" + p[1]; }
  function biblioteca(maisUma) {
    var lista = document.getElementById("ie-bib-lista");
    if (!maisUma) { pagina = 0; lista.innerHTML = '<p class="ag-vazio">Lendo…</p>'; }
    var q = new URLSearchParams(Object.assign({}, filtros, { pagina: String(pagina), limite: "60" }));
    pedir("api/biblioteca?" + q.toString()).then(function (j) {
      if (!maisUma) resumo(j);
      var h = (j.linhas || []).map(function (x) {
        return '<button type="button" class="ie-linha ie-linha--' + esc(x.resultado) + '" data-bib-id="' + x.id + '">' +
          '<span class="ie-linha__cab"><b>' + esc(NOME_NAY[x.nay] || x.nay) + "</b>" + esc(dia(x.dia)) +
          (x.tel4 ? " · …" + esc(x.tel4) : "") + (x.pessoa ? " · " + esc(x.pessoa) : "") +
          '<span class="ie-linha__res">' + (x.resultado === "certo" ? "deu certo" : "com erro") + "</span></span>" +
          "<p>" + esc(x.resumo || (x.resultado === "certo" ? "Sem erro apontado." : "")) + "</p>" +
          '<span class="ie-linha__cab">' + esc(x.confianca) + (x.nota != null ? " · nota " + esc(x.nota) : "") +
          ((x.tipos || []).length ? " · " + esc(x.tipos.join(", ")) : "") + "</span></button>";
      }).join("");
      var antes = maisUma ? lista.querySelector(".ie-mais") : null;
      if (antes) antes.remove();
      if (maisUma) lista.insertAdjacentHTML("beforeend", h); else lista.innerHTML = h || '<p class="ag-vazio">Nada com esses filtros.</p>';
      if ((pagina + 1) * 60 < (j.total || 0)) lista.insertAdjacentHTML("beforeend", '<button type="button" class="ie-mais">Mostrar mais (' + (j.total - (pagina + 1) * 60) + ")</button>");
    }).catch(function (e) { lista.innerHTML = '<p class="ag-vazio">Não li a biblioteca: ' + esc(e.message) + "</p>"; });
  }
  function resumo(j) {
    var por = j.por_nay || {}, certo = 0, erro = 0;
    Object.keys(por).forEach(function (k) { certo += por[k].certo || 0; erro += por[k].erro || 0; });
    document.getElementById("ie-bib-resumo").innerHTML =
      '<div class="ie-num"><b>' + (certo + erro) + "</b><span>conversas de outubro</span></div>" +
      '<div class="ie-num"><b style="color:#16a34a">' + certo + '</b><span>deram certo</span></div>' +
      '<div class="ie-num"><b style="color:#dc2626">' + erro + "</b><span>com erro</span></div>" +
      Object.keys(por).map(function (k) { return '<div class="ie-num"><b>' + (por[k].certo + por[k].erro) + "</b><span>" + esc(NOME_NAY[k] || k) + ": " + por[k].certo + " certo · " + por[k].erro + " erro</span></div>"; }).join("") +
      '<div class="ie-num"><b>' + esc(j.total) + "</b><span>com estes filtros</span></div>";
    var sel = document.getElementById("ie-bib-tipo"), atual = sel.value;
    sel.innerHTML = '<option value="">Todo tipo de erro</option>' + Object.keys(j.por_tipo || {}).map(function (t) {
      return '<option value="' + esc(t) + '">' + esc(t.replace(/_/g, " ")) + " (" + j.por_tipo[t] + ")</option>"; }).join("");
    sel.value = atual;
  }
  function ler(id, botao) {
    var ver = document.getElementById("ie-bib-ver");
    document.querySelectorAll(".ie-linha[aria-current]").forEach(function (b) { b.removeAttribute("aria-current"); });
    if (botao) botao.setAttribute("aria-current", "true");
    ver.innerHTML = '<p class="ag-vazio">Lendo…</p>';
    pedir("api/biblioteca/" + id).then(function (x) {
      var marcas = (x.marcas || []).map(function (m) {
        var erros = (m.erros || []).filter(function (e) { return e && (e.o_que_aconteceu || e.o_que_devia); });
        return '<div class="ie-marca"><span class="ie-marca__quem">' + esc(FONTE[m.fonte] || m.quem || m.fonte) +
          "<small>" + (m.resultado === "certo" ? "deu certo" : "com erro") + (m.nota != null ? " · nota " + esc(m.nota) : "") + "</small></span>" +
          (m.resumo ? "<p>" + esc(m.resumo) + "</p>" : "") +
          (erros.length ? "<ul>" + erros.map(function (e) {
            return "<li>" + (e.tipo ? "<b>" + esc(String(e.tipo).replace(/_/g, " ")) + ":</b> " : "") + esc(e.o_que_aconteceu || "") +
              (e.o_que_devia ? "<br><i>Devia:</i> " + esc(e.o_que_devia) : "") + "</li>"; }).join("") + "</ul>" : "") +
          (m.correcao ? "<p><i>Correção:</i> " + esc(m.correcao) + "</p>" : "") + "</div>";
      }).join("");
      ver.innerHTML = "<h3>" + esc(NOME_NAY[x.nay] || x.nay) + " · " + esc(dia(x.dia)) + (x.tel4 ? " · …" + esc(x.tel4) : "") +
        " · " + (x.resultado === "certo" ? "deu certo" : "com erro") + "</h3>" +
        '<p class="ie-camada__onde">' + esc(x.ref) + " · julgado por: " + esc(x.confianca) + "</p>" + marcas +
        (x.texto ? '<div class="ie-conversa">' + esc(x.texto) + "</div>" : '<p class="ag-vazio">Sem o texto da conversa (o caso veio de uma fala ou de um commit).</p>');
    }).catch(function (e) { ver.innerHTML = '<p class="ag-vazio">Não li a conversa: ' + esc(e.message) + "</p>"; });
  }
  document.getElementById("ie-bib-filtros").addEventListener("submit", function (ev) {
    ev.preventDefault();
    filtros = {};
    new FormData(ev.target).forEach(function (v, k) { if (String(v).trim()) filtros[k] = String(v).trim(); });
    biblioteca();
  });
  document.getElementById("ie-bib-lista").addEventListener("click", function (ev) {
    var lista = ev.currentTarget;
    var b = ev.target.closest("[data-bib-id]");
    if (b && lista.contains(b)) return ler(b.getAttribute("data-bib-id"), b);
    var mais = ev.target.closest(".ie-mais");
    if (mais && lista.contains(mais)) { pagina += 1; biblioteca(true); }
  });
})();
