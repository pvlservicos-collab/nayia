/* As fotos do Unsplash para os artigos do blog (Pedro, 22/10/2026: "prepara uma tela rápida lá no blog para eu
   passar nessa autorização"). As regras de produção do Unsplash, que esta tela cumpre:
   - a foto aparece direto da URL do Unsplash (hotlink): nunca é baixada para o nosso servidor;
   - usar a foto dispara o download_location dela (POST /admin/api/blog/unsplash/usar);
   - o crédito leva o nome do fotógrafo com link para o perfil dele e link para o Unsplash (utm do aplicativo).
   "Usar no artigo" copia o markdown (a imagem + o crédito em itálico), que o artigo do blog mostra como legenda. */
(function () {
  "use strict";
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok || j.ok === false) throw new Error(j.erro || ("HTTP " + r.status)); return j; }); });
  }

  var fotos = [], pagina = 1, paginas = 0, busca = "";

  function credito(f) {
    return 'Foto de <a href="' + esc(f.perfil) + '" target="_blank" rel="noopener">' + esc(f.autor) + '</a> no ' +
      '<a href="' + esc(f.unsplash) + '" target="_blank" rel="noopener">Unsplash</a>';
  }
  function markdown(f) {
    var alt = (f.alt || "foto").replace(/[\[\]]/g, "");
    return "![" + alt + "](" + f.url + ")\n*Foto de [" + f.autor.replace(/[\[\]]/g, "") + "](" + f.perfil + ") no [Unsplash](" + f.unsplash + ")*";
  }
  function cartao(f, i) {
    return '<article class="bf-foto" data-i="' + i + '">' +
      '<img src="' + esc(f.thumb) + '" alt="' + esc(f.alt) + '" loading="lazy" style="background:' + esc(f.cor || "#ddd") + '">' +
      '<div class="bf-corpo"><p class="bf-credito">' + credito(f) + "</p>" +
      '<button class="btn-azul" type="button" data-usar="' + i + '">Usar no artigo</button></div></article>';
  }
  function desenhar() {
    $("bf-grade").innerHTML = fotos.length ? fotos.map(cartao).join("")
      : '<p class="bg-vazio">Nenhuma foto para “' + esc(busca) + '”. Tente outras palavras (em inglês costuma dar mais resultado).</p>';
    $("bf-mais").hidden = pagina >= paginas;
  }
  function procurar(nova) {
    if (nova) { pagina = 1; fotos = []; busca = $("bf-q").value.trim(); }
    if (!busca) return;
    if (nova) $("bf-grade").innerHTML = '<p class="bg-vazio">Procurando…</p>';
    var o = $("bf-orientacao").value;
    pedir("/admin/api/blog/unsplash?q=" + encodeURIComponent(busca) + "&pagina=" + pagina + (o ? "&orientacao=" + o : ""))
      .then(function (d) { fotos = fotos.concat(d.fotos || []); paginas = d.paginas || 0; desenhar(); })
      .catch(function (e) { $("bf-grade").innerHTML = '<p class="bg-vazio">Não consegui procurar: ' + esc(e.message) + "</p>"; });
  }
  function usar(i, botao) {
    var f = fotos[i];
    if (!f) return;
    botao.disabled = true;
    botao.textContent = "Registrando…";
    pedir("/admin/api/blog/unsplash/usar", { method: "POST", body: JSON.stringify({ download: f.download }) })
      .then(function () {
        var md = markdown(f);
        var copiou = navigator.clipboard ? navigator.clipboard.writeText(md).then(function () { return true; }, function () { return false; }) : Promise.resolve(false);
        return copiou.then(function (ok) {
          botao.textContent = "Usada ✓";
          botao.closest(".bf-foto").classList.add("bf-usada");
          var caixa = $("bf-copiado");
          caixa.hidden = false;
          caixa.innerHTML = "<b>" + (ok ? "Copiado." : "Copie o texto abaixo.") + "</b> Cole no texto do artigo, onde a foto deve aparecer:" +
            "<pre>" + esc(md) + "</pre>" +
            '<div class="bf-previa"><span style="font-size:var(--fs-sm);color:var(--texto-fraco)">Assim fica no artigo:</span>' +
            '<figure><img src="' + esc(f.url) + '" alt="' + esc(f.alt) + '"><figcaption>' + credito(f) + "</figcaption></figure></div>";
          caixa.scrollIntoView({ behavior: "smooth", block: "start" });
        });
      })
      .catch(function (e) { botao.disabled = false; botao.textContent = "Usar no artigo"; alert("Não deu: " + e.message); });
  }

  $("bf-form").addEventListener("submit", function (e) { e.preventDefault(); procurar(true); });
  $("bf-mais").addEventListener("click", function () { pagina += 1; procurar(false); });
  $("bf-grade").addEventListener("click", function (e) {
    var b = e.target.closest ? e.target.closest("[data-usar]") : null;
    if (b) usar(Number(b.getAttribute("data-usar")), b);
  });
})();
