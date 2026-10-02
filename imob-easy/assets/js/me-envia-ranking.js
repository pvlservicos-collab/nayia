/* =====================================================================
 * QUEM MAIS SE ENVIA IMÓVEL (02/10/2026)
 *
 * Pedro: "o corretor vai digitar seu whatsapp lá e nosso sistema vai saber
 * os corretores que mais se enviam imoveis".
 *
 * Na página pública do imóvel (/imovel/<código>) o corretor digita o próprio
 * WhatsApp e a Nay manda o card e as fotos. Cada pedido fica guardado, e aqui
 * sai a lista de quem mais pediu no período.
 *
 * Tem nome e telefone: lê de /admin/api (mesmo domínio), que só responde com
 * a senha do admin.
 * ===================================================================== */
(function () {
  "use strict";

  var alvo = document.getElementById("me-envia-ranking");
  if (!alvo) return;

  var dias = 30;
  var PERIODOS = [[7, "7 dias"], [30, "30 dias"], [90, "90 dias"], [365, "1 ano"]];

  function esc(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function telefone(t) {
    var d = String(t || "").replace(/\D/g, "").replace(/^55/, "");
    if (d.length === 11) return "(" + d.slice(0, 2) + ") " + d.slice(2, 7) + "-" + d.slice(7);
    if (d.length === 10) return "(" + d.slice(0, 2) + ") " + d.slice(2, 6) + "-" + d.slice(6);
    return t || "";
  }

  function quando(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" }) + " " +
      d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  }

  function botoes() {
    return '<div class="mer__periodos" data-estado-proprio>' + PERIODOS.map(function (p) {
      return '<button type="button" class="btn-mini" data-mer-dias="' + p[0] + '" aria-pressed="' + (dias === p[0]) + '"' +
        (dias === p[0] ? ' style="font-weight:700;border-color:var(--azul)"' : "") + ">" + p[1] + "</button>";
    }).join(" ") + "</div>";
  }

  function desenhar(lista) {
    var total = lista.reduce(function (s, l) { return s + Number(l.imoveis_enviados || 0); }, 0);
    var corpo = lista.length
      ? '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela" style="min-width:560px"><thead><tr>' +
          "<th>#</th><th>Quem</th><th>WhatsApp</th><th class=\"num\">Imóveis recebidos</th>" +
          "<th class=\"num\">Imóveis diferentes</th><th class=\"num\">Pedidos</th><th>Último pedido</th></tr></thead><tbody>" +
          lista.map(function (l, n) {
            return "<tr><td class=\"num\">" + (n + 1) + "</td>" +
              "<td><strong>" + esc(l.nome || "Sem nome") + "</strong>" +
                (l.e_corretor ? "" : ' <span class="etiqueta etiqueta--cinza-ux" title="O número não está na lista de corretores">novo</span>') + "</td>" +
              "<td>" + esc(telefone(l.telefone)) + "</td>" +
              '<td class="num"><strong>' + Number(l.imoveis_enviados || 0) + "</strong></td>" +
              '<td class="num">' + Number(l.imoveis_distintos || 0) + "</td>" +
              '<td class="num">' + Number(l.pedidos || 0) + "</td>" +
              "<td>" + esc(quando(l.ultimo)) + "</td></tr>";
          }).join("") + "</tbody></table></div></div>"
      : '<p class="painel__vazio">Ninguém pediu imóvel pela página nesse período.</p>';

    alvo.innerHTML =
      '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:10px">' +
        '<div><h2 style="margin:0;font-size:var(--fs-lg)">Quem mais se envia imóvel</h2>' +
        '<p style="margin:2px 0 0;font-size:var(--fs-sm);color:var(--texto-fraco)">Pedidos feitos na página do imóvel ' +
        "(o corretor digita o próprio WhatsApp). " + lista.length + " pessoa(s), " + total + " imóvel(is) enviados.</p></div>" +
        botoes() +
      "</div>" + corpo;
  }

  function carregar() {
    alvo.innerHTML = '<p class="painel__vazio">Carregando quem mais se envia imóvel…</p>';
    fetch("/admin/api/me-envia/ranking?dias=" + dias, { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) { desenhar(d.ranking || []); })
      .catch(function () {
        alvo.innerHTML = '<p class="painel__vazio">Não consegui carregar a lista de quem se envia imóvel. ' +
          '<button type="button" class="btn-mini" data-mer-de-novo>Tentar de novo</button></p>';
      });
  }

  alvo.addEventListener("click", function (e) {
    var b = e.target.closest("[data-mer-dias]");
    if (b) { dias = Number(b.dataset.merDias) || 30; return carregar(); }
    if (e.target.closest("[data-mer-de-novo]")) carregar();
  });

  carregar();
})();
