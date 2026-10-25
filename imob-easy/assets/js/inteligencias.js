/* INTELIGÊNCIAS GERAIS DOS AGENTES (495, Pedro 25/10/2026): a aba de baixo da página Agentes.
   "comparar a Nay Parceria ... ver o que ela tem que as outras Nay não têm mas poderiam ... e salvar em uma aba lá no
   site Agentes ... e vai salvar lá essas regras para futuramente".
   Cada regra diz para quem vale (Parceria, Leads, Captação, OLX) e onde já está aplicada: o quadradinho cheio é
   "já aplicada", o tracejado é "falta aplicar". Clicar troca. Os dados: /admin/api/inteligencias (nay_inteligencia_geral). */
(function () {
  var NAYS = [["parceria", "Parceria"], ["leads", "Leads"], ["captacao", "Captação"], ["olx", "OLX"]];
  var lista = document.getElementById("ag-intel");
  if (!lista) return;
  var regras = [];

  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status)); return j; }); });
  }
  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; });
  }

  function chips(r) {
    return NAYS.filter(function (n) { return r.vale_para.indexOf(n[0]) >= 0; }).map(function (n) {
      var ok = r.aplicada_em.indexOf(n[0]) >= 0;
      return '<button type="button" class="in-chip' + (ok ? " in-chip--ok" : "") + '" data-id="' + r.id + '" data-nay="' + n[0] + '" title="' +
        (ok ? "Já aplicada na Nay " + n[1] + " (clique para marcar que falta)" : "Falta aplicar na Nay " + n[1] + " (clique quando aplicar)") + '">' +
        (ok ? "✓ " : "") + n[1] + "</button>";
    }).join("");
  }
  function desenhar() {
    if (!regras.length) { lista.innerHTML = '<p class="ag-vazio">Nenhuma inteligência salva ainda.</p>'; return; }
    var grupos = {};
    regras.forEach(function (r) { var k = r.assunto || "geral"; (grupos[k] = grupos[k] || []).push(r); });
    lista.innerHTML = Object.keys(grupos).map(function (k) {
      return '<div class="in-grupo"><h3 class="in-assunto">' + esc(k) + "</h3>" + grupos[k].map(function (r) {
        var faltam = r.vale_para.filter(function (n) { return r.aplicada_em.indexOf(n) < 0; }).length;
        return '<div class="in-regra' + (r.ativa ? "" : " in-regra--off") + '">' +
          '<p class="in-texto">' + esc(r.regra) + "</p>" +
          (r.porque ? '<p class="in-porque">' + esc(r.porque) + "</p>" : "") +
          '<div class="in-pe"><span class="in-origem">de ' + esc(r.origem === "tel" ? "Tel" : "Nay " + r.origem) + "</span>" + chips(r) +
          (faltam ? '<span class="in-falta">falta em ' + faltam + "</span>" : '<span class="in-tudo">aplicada em todas</span>') + "</div></div>";
      }).join("") + "</div>";
    }).join("");
  }
  function carregar() {
    return pedir("api/inteligencias").then(function (j) { regras = j.regras || []; desenhar(); })
      .catch(function (er) { lista.innerHTML = '<p class="ag-vazio">' + esc(er.message) + "</p>"; });
  }

  lista.addEventListener("click", function (e) {
    var b = e.target.closest(".in-chip");
    if (!b) return;
    var r = regras.filter(function (x) { return String(x.id) === b.dataset.id; })[0];
    if (!r) return;
    var nay = b.dataset.nay, apl = r.aplicada_em.slice();
    apl = apl.indexOf(nay) >= 0 ? apl.filter(function (n) { return n !== nay; }) : apl.concat([nay]);
    b.disabled = true;
    pedir("api/inteligencias", { method: "POST", body: JSON.stringify(Object.assign({}, r, { aplicada_em: apl })) })
      .then(carregar).catch(function (er) { alert(er.message); b.disabled = false; });
  });

  var form = document.getElementById("in-nova");
  if (form) form.addEventListener("submit", function (e) {
    e.preventDefault();
    var vale = NAYS.map(function (n) { return n[0]; }).filter(function (n) { return form.elements["vale_" + n].checked; });
    var corpo = { regra: form.elements.regra.value, porque: form.elements.porque.value, assunto: form.elements.assunto.value,
                  vale_para: vale, origem: "tel" };
    if (!corpo.regra.trim()) return;
    var botao = form.querySelector("button");
    botao.disabled = true;
    pedir("api/inteligencias", { method: "POST", body: JSON.stringify(corpo) })
      .then(function () { form.reset(); return carregar(); })
      .catch(function (er) { alert(er.message); })
      .then(function () { botao.disabled = false; });
  });

  carregar();
})();
