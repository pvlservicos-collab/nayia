/* ==========================================================================
   Imob Easy — Listas criadas a partir dos filtros de vencimento
   "Ver" leva pra lista-detalhe.html (tela cheia -- ver esse arquivo pras
   ações de Pegar links / Disparo automático / Baixar CSV).
   ========================================================================== */
(function () {
  "use strict";

  var corpo = document.getElementById("corpo-listas");

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function formatarData(iso) {
    var d = new Date(iso);
    return d.toLocaleDateString("pt-BR") + " " + d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  }

  function linha(item) {
    return (
      "<tr>" +
      "<td><a href=\"lista-detalhe.html?id=" + item.id + "\">" + esc(item.nome) + "</a></td>" +
      "<td>" + esc(item.area) + "</td>" +
      "<td>" + esc(item.filtro) + "</td>" +
      '<td class="num">' + esc(item.quantidade) + "</td>" +
      "<td>" + esc(formatarData(item.criado_em)) + "</td>" +
      "<td>" + esc(item.exportado_por) + "</td>" +
      '<td class="col-acoes"><span class="acoes-celula">' +
        '<a class="btn-mini" href="lista-detalhe.html?id=' + item.id + '">Ver</a>' +
        '<button class="btn-mini" type="button" data-apagar="' + item.id + '">Apagar</button>' +
      "</span></td>" +
      "</tr>"
    );
  }

  function carregar() {
    fetch(window.API_BASE + "/api/listas")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (itens) {
        corpo.innerHTML = itens.length
          ? itens.map(linha).join("")
          : '<tr><td colspan="7" style="text-align:center;color:var(--texto-fraco);padding:24px">Nenhuma lista criada ainda -- crie uma nos filtros de vencimento (Imóveis, Proprietários, Corretores ou Locação).</td></tr>';
      })
      .catch(function () {
        corpo.innerHTML = '<tr><td colspan="7">Não foi possível carregar as listas.</td></tr>';
      });
  }

  corpo.addEventListener("click", function (evento) {
    var apagarBtn = evento.target.closest("[data-apagar]");
    if (!apagarBtn) return;
    if (!confirm("Apagar esta lista? Isso não pode ser desfeito.")) return;
    fetch(window.API_BASE + "/api/listas/" + apagarBtn.dataset.apagar, { method: "DELETE" })
      .then(carregar);
  });

  if (!window.API_BASE) { corpo.innerHTML = "<tr><td>config.js não define API_BASE.</td></tr>"; return; }
  carregar();
})();
