/* As fotos do Unsplash para os artigos do blog, numa tela só (Pedro, 22/10/2026: "uma página contendo todas as coisas
   que ele pede ... quando eu passe o mouse pela foto apareça um alertzinho com o link da foto ... caiba tudo em 1 tela").
   As regras de produção do Unsplash que a tela cumpre e mostra no painel da direita:
   - a foto aparece direto da URL do Unsplash (hotlink): nunca é baixada para o nosso servidor;
   - usar a foto dispara o download_location dela (POST /admin/api/blog/unsplash/usar);
   - o crédito leva o nome do fotógrafo com link para o perfil e link para o Unsplash (utm do aplicativo), na foto ao
     passar o mouse e na legenda do artigo.
   "Usar no artigo" também copia o markdown (a imagem + o crédito em itálico) para colar no texto do artigo. */
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
  function link(url, texto) { return '<a href="' + esc(url) + '" target="_blank" rel="noopener">' + esc(texto) + "</a>"; }
  function credito(f) { return "Foto de " + link(f.perfil, f.autor) + " no " + link(f.unsplash, "Unsplash"); }
  function markdown(f) {
    var limpo = function (s) { return String(s || "").replace(/[\[\]]/g, ""); };
    return "![" + limpo(f.alt || "foto") + "](" + f.url + ")\n*Foto de [" + limpo(f.autor) + "](" + f.perfil + ") no [Unsplash](" + f.unsplash + ")*";
  }

  var fotos = [], escolhida = -1;

  function cartao(f, i) {
    return '<div class="bf-foto" tabindex="0" data-i="' + i + '" title="Foto de ' + esc(f.autor) + ' no Unsplash">' +
      '<img src="' + esc(f.thumb) + '" alt="' + esc(f.alt) + '" loading="lazy" style="background:' + esc(f.cor || "#ddd") + '">' +
      '<div class="bf-dica">' + credito(f) + '<br><a class="bf-ver" href="' + esc(f.pagina) + '" target="_blank" rel="noopener">Ver a foto no Unsplash ↗</a></div></div>';
  }
  function escolher(i) {
    var f = fotos[i];
    if (!f) return;
    escolhida = i;
    document.querySelectorAll(".bf-foto").forEach(function (el) { el.classList.toggle("ativa", Number(el.dataset.i) === i); });
    var fig = $("bf-previa");
    fig.querySelector("img").src = f.url;
    fig.querySelector("img").alt = f.alt || "";
    fig.querySelector("figcaption").innerHTML = credito(f);
    $("bf-r-url").textContent = f.url.split("?")[0];
    var usada = !!f.usadaEm;
    $("bf-usar").disabled = usada;
    $("bf-usar").textContent = usada ? "Usada ✓" : "Usar no artigo";
    $("bf-r-dl-ok").classList.toggle("espera", !usada);
    $("bf-r-dl").textContent = usada ? "registrado às " + f.usadaEm + " · " + f.download.split("?")[0] : "ainda não usada";
    $("bf-copiado").textContent = "";
  }
  function procurar() {
    var q = $("bf-q").value.trim(), o = $("bf-orientacao").value;
    if (!q) return;
    $("bf-grade").innerHTML = '<p class="bf-vazio">Procurando…</p>';
    pedir("/admin/api/blog/unsplash?q=" + encodeURIComponent(q) + (o ? "&orientacao=" + o : ""))
      .then(function (d) {
        fotos = d.fotos || [];
        $("bf-grade").innerHTML = fotos.length ? fotos.map(cartao).join("")
          : '<p class="bf-vazio">Nenhuma foto para “' + esc(q) + '”. Tente outras palavras (em inglês costuma dar mais resultado).</p>';
        if (fotos.length) escolher(0);
      })
      .catch(function (e) { $("bf-grade").innerHTML = '<p class="bf-vazio">Não consegui procurar: ' + esc(e.message) + "</p>"; });
  }
  function usar() {
    var i = escolhida, f = fotos[i], b = $("bf-usar");
    if (!f) return;
    b.disabled = true;
    b.textContent = "Registrando…";
    pedir("/admin/api/blog/unsplash/usar", { method: "POST", body: JSON.stringify({ download: f.download }) })
      .then(function () {
        f.usadaEm = new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
        var el = document.querySelector('.bf-foto[data-i="' + i + '"]');
        if (el) el.classList.add("usada");
        escolher(i);
        var md = markdown(f);
        return (navigator.clipboard ? navigator.clipboard.writeText(md) : Promise.reject()).then(
          function () { $("bf-copiado").textContent = "Copiado: cole no texto do artigo."; },
          function () { window.prompt("Copie e cole no texto do artigo:", md); });
      })
      .catch(function (e) { b.disabled = false; b.textContent = "Usar no artigo"; alert("Não deu: " + e.message); });
  }

  $("bf-form").addEventListener("submit", function (e) { e.preventDefault(); procurar(); });
  $("bf-usar").addEventListener("click", usar);
  $("bf-grade").addEventListener("click", function (e) {
    if (e.target.closest("a")) return;   // o link do crédito abre o Unsplash, não escolhe
    var c = e.target.closest(".bf-foto");
    if (c) escolher(Number(c.dataset.i));
  });
  $("bf-grade").addEventListener("keydown", function (e) {
    var c = e.target.closest ? e.target.closest(".bf-foto") : null;
    if (c && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); escolher(Number(c.dataset.i)); }
  });
  procurar();
})();
