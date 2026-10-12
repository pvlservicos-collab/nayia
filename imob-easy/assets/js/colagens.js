/* Colagens de 4 fotos (pedido do Tel, 12/09/2026). Só leitura:
   a página mostra o que o gerador já montou, e o que ainda falta. */
(function () {
  "use strict";

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function dinheiro(v) {
    return v == null ? null : "R$ " + Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 0 });
  }
  function cartao(n, rotulo) {
    return '<div class="painel-cartao"><div class="painel-cartao__n">' + esc(n) +
           '</div><div class="painel-cartao__r">' + esc(rotulo) + "</div></div>";
  }

  function card(im) {
    var nome = im.condominio || im.tipo || ("Imóvel " + im.codigo);
    var valor = dinheiro(im.aluguel) || dinheiro(im.venda) || "";
    var topo = im.url
      ? '<a href="' + esc(im.url) + '" target="_blank" rel="noopener">' +
        '<img src="' + esc(im.url) + '" alt="Colagem do imóvel ' + esc(im.codigo) + '" loading="lazy"></a>'
      : '<div class="col-vazio">ainda não montada<br>(' + esc(im.fotos) + " fotos no cadastro)</div>";
    return '<div class="col-card">' + topo +
      '<div class="col-card__txt"><div class="col-card__nome">' + esc(nome) + "</div>" +
      '<div class="col-card__sub">' + esc(im.bairro || "") +
      (valor ? " · " + esc(valor) : "") + "</div>" +
      '<div class="col-card__sub">Código: ' + esc(im.codigo) +
      (im.kb ? " · " + esc(im.kb) + " KB" : "") + "</div></div></div>";
  }

  function carregar(faltando) {
    var grade = document.getElementById("grade");
    grade.innerHTML = '<p class="painel-nota">Carregando…</p>';
    fetch(window.API_BASE + "/api/colagens?limite=500" + (faltando ? "&faltando=1" : ""))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var r = d.resumo || {};
        document.getElementById("cartoes").innerHTML =
          cartao(r.com_4_fotos, "imóveis disponíveis com 4+ fotos") +
          cartao(r.com_colagem, "já têm colagem") +
          cartao(Math.max(0, r.com_4_fotos - r.com_colagem), "ainda faltam") +
          cartao(r.megabytes + " MB", "ocupados no site");
        document.getElementById("aviso").textContent =
          "mostrando " + (d.imoveis || []).length + " imóveis";
        grade.innerHTML = (d.imoveis || []).map(card).join("") ||
          '<p class="painel-nota">Nada para mostrar.</p>';
      })
      .catch(function () {
        grade.innerHTML = '<p class="painel-nota">Não foi possível carregar.</p>';
      });
  }

  if (!window.API_BASE) { return; }
  document.getElementById("btn-todos").addEventListener("click", function () { carregar(false); });
  document.getElementById("btn-faltando").addEventListener("click", function () { carregar(true); });
  carregar(false);
})();
