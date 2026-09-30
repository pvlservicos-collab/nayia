/* ==========================================================================
   Imob Easy — Aba Condomínios de Todos os imóveis

   Pedido do Pedro (30/09/2026): "atualiza também a lista de condomínios com a
   lista de características de condomínios, e lá em todos os imóveis põe a aba
   condomínios listando tudo, também com as características que pegamos do site
   antigo".

   Uma leitura só de /api/condominios/aba quando a aba abre; a busca e o filtro
   acontecem na tela. Por condomínio: os imóveis (disponíveis / total, com o link
   para a lista filtrada), a ficha (migração 210: ano, construtora, torres,
   andares, lazer...) e as características que os anúncios do site antigo dão
   (imovel_ficha), com quantos imóveis citam cada uma. Clicar na linha abre o
   resto da ficha.
   ========================================================================== */
(function () {
  "use strict";

  var aba = document.querySelector('[data-painel-abre="condominios"]');
  var painel = document.querySelector('[data-painel="condominios"]');
  if (!aba || !painel) return;

  var API = window.API_BASE || "";
  var corpo = document.getElementById("cd-corpo");
  var busca = document.getElementById("cd-busca");
  var mostrar = document.getElementById("cd-mostrar");
  var resumo = document.getElementById("cd-resumo");
  var todos = null;
  var aberto = {};

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function semAcento(t) {
    return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }

  var css = document.createElement("style");
  css.textContent =
    ".cd-barra{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:0 0 12px}" +
    ".cd-barra input,.cd-barra select{font:inherit;padding:7px 10px;border:1px solid var(--borda,#d9dce3);border-radius:8px;background:#fff}" +
    ".cd-barra input{flex:1 1 260px;min-width:0}" +
    ".cd-resumo{color:var(--texto-fraco,#6b7280);font-size:13px}" +
    ".cd-nome{font-weight:600}.cd-sub{display:block;color:var(--texto-fraco,#6b7280);font-size:12px}" +
    ".cd-fichas{font-size:13px;line-height:1.45}" +
    ".cd-chips{display:flex;flex-wrap:wrap;gap:4px}" +
    ".cd-chip{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px;background:#e8eefc;color:#1f3f7a}" +
    ".cd-chip--antigo{background:#f1f2f5;color:#4b5563}" +
    ".cd-chip small{opacity:.7;margin-left:3px}" +
    ".cd-linha{cursor:pointer}" +
    ".cd-detalhe td{background:#fafbfd;font-size:13px}" +
    ".cd-detalhe dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:0 0 10px}" +
    ".cd-detalhe dt{color:var(--texto-fraco,#6b7280)}.cd-detalhe dd{margin:0}" +
    ".cd-vazio{color:var(--texto-fraco,#6b7280)}";
  document.head.appendChild(css);

  function linhaDaFicha(f) {
    if (!f) return '<span class="cd-vazio">—</span>';
    var partes = [];
    if (f.ano) partes.push("lançado em " + f.ano);
    if (f.construtora) partes.push(f.construtora);
    if (f.tipo === "casas_lotes") {
      if (f.unidades) partes.push(f.unidades);
    } else {
      if (f.torres) partes.push(f.torres);
      if (f.andares) partes.push(f.andares);
      if (f.aptos_por_andar) partes.push(f.aptos_por_andar);
      if (f.elevador) partes.push("elevador: " + f.elevador);
    }
    return '<div class="cd-fichas">' + esc(partes.join(" · ")) + "</div>";
  }

  function chips(c, limite) {
    var lazer = (c.ficha && c.ficha.lazer) || [];
    var antigo = c.antigo || [];
    var html = lazer.slice(0, limite).map(function (x) { return '<span class="cd-chip">' + esc(x) + "</span>"; });
    var resto = Math.max(0, limite - html.length);
    html = html.concat(antigo.slice(0, resto).map(function (x) {
      return '<span class="cd-chip cd-chip--antigo" title="citado em ' + x.n + ' anúncio(s) do site antigo">' +
        esc(x.item) + "<small>" + x.n + "</small></span>";
    }));
    var sobra = lazer.length + antigo.length - html.length;
    if (sobra > 0) html.push('<span class="cd-chip cd-chip--antigo">+' + sobra + "</span>");
    return html.length ? '<div class="cd-chips">' + html.join("") + "</div>" : '<span class="cd-vazio">—</span>';
  }

  function detalhe(c) {
    var f = c.ficha || {};
    var itens = [
      ["Endereço", f.endereco], ["Lançamento", f.ano], ["Construtora", f.construtora],
      ["Revestimento", f.revestimento], ["Torres", f.torres], ["Andares", f.andares],
      ["Apartamentos por andar", f.aptos_por_andar], ["Elevador", f.elevador], ["Unidades", f.unidades],
      ["Fonte da ficha", f.fonte]
    ].filter(function (x) { return x[1] != null && x[1] !== ""; });
    var dl = itens.length
      ? "<dl>" + itens.map(function (x) { return "<dt>" + esc(x[0]) + "</dt><dd>" + esc(x[1]) + "</dd>"; }).join("") + "</dl>"
      : '<p class="cd-vazio">Sem ficha cadastrada.</p>';
    var lazer = (f.lazer || []).length
      ? "<p><b>Lazer (ficha)</b></p>" + '<div class="cd-chips">' +
        f.lazer.map(function (x) { return '<span class="cd-chip">' + esc(x) + "</span>"; }).join("") + "</div>"
      : "";
    var antigo = (c.antigo || []).length
      ? "<p><b>Do site antigo</b> (dos anúncios dos imóveis deste condomínio)</p>" + '<div class="cd-chips">' +
        c.antigo.map(function (x) {
          return '<span class="cd-chip cd-chip--antigo">' + esc(x.item) + "<small>" + x.n + "</small></span>";
        }).join("") + "</div>"
      : "";
    return '<tr class="cd-detalhe"><td colspan="4">' + dl + lazer + antigo + "</td></tr>";
  }

  function filtrados() {
    var q = semAcento(busca.value.trim());
    var m = mostrar.value;
    return todos.filter(function (c) {
      if (q && semAcento(c.nome + " " + (c.bairro || "") + " " + ((c.ficha && c.ficha.construtora) || "")).indexOf(q) < 0) return false;
      if (m === "ficha" && !c.ficha) return false;
      if (m === "antigo" && !(c.antigo || []).length) return false;
      if (m === "disponivel" && !c.disponiveis) return false;
      return true;
    });
  }

  function pintar() {
    var lista = filtrados();
    resumo.textContent = lista.length + " de " + todos.length + " condomínios";
    corpo.innerHTML = lista.map(function (c) {
      var link = c.id != null
        ? '<a href="imoveis.html?condo=' + c.id + "&condo_nome=" + encodeURIComponent(c.nome) + '">' +
          c.disponiveis + " / " + c.imoveis + "</a>"
        : c.disponiveis + " / " + c.imoveis;
      return '<tr class="cd-linha" data-chave="' + esc(c.chave) + '">' +
        '<td><span class="cd-nome">' + esc(c.nome) + '</span><span class="cd-sub">' + esc(c.bairro || "—") + "</span></td>" +
        "<td>" + link + "</td>" +
        "<td>" + linhaDaFicha(c.ficha) + "</td>" +
        "<td>" + chips(c, 6) + "</td></tr>" +
        (aberto[c.chave] ? detalhe(c) : "");
    }).join("") || '<tr><td colspan="4">Nenhum condomínio com esse filtro.</td></tr>';
  }

  corpo.addEventListener("click", function (e) {
    if (e.target.closest("a")) return;
    var tr = e.target.closest(".cd-linha");
    if (!tr) return;
    aberto[tr.dataset.chave] = !aberto[tr.dataset.chave];
    pintar();
  });
  busca.addEventListener("input", function () { if (todos) pintar(); });
  mostrar.addEventListener("change", function () { if (todos) pintar(); });

  function carregar() {
    if (todos) return;
    fetch(API + "/api/condominios/aba")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) { todos = d; pintar(); })
      .catch(function () {
        corpo.innerHTML = '<tr><td colspan="4">Não foi possível carregar os condomínios.</td></tr>';
      });
  }
  aba.addEventListener("click", carregar);
})();
