/* ==========================================================================
   Captação › Oportunidades (11/10/2026, Pedro: "pega a aba Oportunidades e põe como uma tab dentro da aba
   Captação"). Era a página oportunidades.html; o conteúdo é o mesmo (contratos vencidos, vencendo e os
   corretores mais ativos), lido das mesmas rotas. Desenha só quando a aba abre.
   ========================================================================== */
(function () {
  "use strict";
  var painel = document.getElementById("painel-oportunidades");
  if (!painel || !window.API_BASE) return;

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function buscar(caminho) {
    return fetch(window.API_BASE + caminho).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }

  function listaAvisos(itens, vazio) {
    if (!itens || !itens.length) return '<li class="painel__vazio">' + esc(vazio) + "</li>";
    return itens.map(function (item) {
      var quando = item.vencimento ? new Date(item.vencimento + "T00:00:00").toLocaleDateString("pt-BR") : "—";
      var contato = item.proprietario_nome || item.proprietario_telefone
        ? esc(item.proprietario_nome || "—") + (item.proprietario_telefone ? " · " + esc(item.proprietario_telefone) : "")
        : "sem proprietário cadastrado";
      return '<li class="painel__item"><strong>#' + esc(item.codigo) + " — " + esc(item.condominio) + "</strong>" +
        "<span>Vencimento: " + esc(quando) + " · " + contato + "</span></li>";
    }).join("");
  }
  function corretoresAtivos(itens) {
    if (!itens || !itens.length) return '<tr><td colspan="3" class="painel__vazio">Sem mensagens nos últimos 30 dias.</td></tr>';
    return itens.map(function (item, i) {
      return "<tr><td class=\"num\">" + (i + 1) + "</td><td>" + esc(item.telefone) + '</td><td class="num">' + esc(item.mensagens) + "</td></tr>";
    }).join("");
  }

  var carregou = false;
  function carregar() {
    if (carregou) return;
    carregou = true;
    Promise.all([buscar("/api/avisos"), buscar("/api/corretores-ativos")]).then(function (r) {
      var avisos = r[0] || { vencidos: [], vencendo: [] };
      document.getElementById("op-vencidos").innerHTML = listaAvisos(avisos.vencidos, "Nenhum contrato vencido.");
      document.getElementById("op-vencendo").innerHTML = listaAvisos(avisos.vencendo, "Nenhum contrato vencendo nos próximos 30 dias.");
      document.getElementById("op-corretores").innerHTML = corretoresAtivos(r[1] || []);
    });
  }
  document.addEventListener("oportunidades:mostrar", carregar);
  if (!painel.hidden) carregar();
})();
