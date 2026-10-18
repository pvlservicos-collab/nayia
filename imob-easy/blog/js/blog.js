/* O JavaScript do blog (406, 17/10/2026). O artigo já vem pronto no HTML (SEO); aqui é só o que é de gente:
   o menu do celular, o Alugar/Comprar da busca lateral, o contador de visitas e a newsletter. */
(function () {
  "use strict";
  var API = window.API_BASE || "https://api.imobeasy.online";
  var $ = function (s, r) { return (r || document).querySelector(s); };

  /* ---- menu do celular (o mesmo da home) ---- */
  var botaoMenu = $(".topo__menu"), nav = document.getElementById("nav-principal");
  if (botaoMenu && nav) {
    botaoMenu.addEventListener("click", function () {
      var aberto = nav.classList.toggle("aberto");
      botaoMenu.setAttribute("aria-expanded", aberto ? "true" : "false");
    });
  }

  /* ---- Alugar / Comprar da busca lateral: troca o destino do formulário (busca-filtros.js monta o endereço) ---- */
  var form = $("form.painel-busca"), botaoBusca = $(".busca__enviar a");
  document.querySelectorAll(".hero__neg-aba").forEach(function (aba) {
    aba.addEventListener("click", function () {
      document.querySelectorAll(".hero__neg-aba").forEach(function (a) { a.setAttribute("aria-selected", a === aba ? "true" : "false"); });
      if (form) form.setAttribute("action", aba.dataset.neg);
      if (botaoBusca) botaoBusca.setAttribute("href", aba.dataset.neg);
    });
  });

  /* ---- a visita (gente; o robô é contado no servidor) ---- */
  var artigo = $(".artigo[data-slug]");
  if (artigo && !navigator.webdriver) {
    var slug = artigo.dataset.slug, chave = "blog-visita:" + slug, ja = false;
    try { ja = sessionStorage.getItem(chave) === "1"; } catch (e) { /* sem armazenamento */ }
    if (!ja) {
      try { sessionStorage.setItem(chave, "1"); } catch (e) { /* tanto faz */ }
      setTimeout(function () {
        fetch(API + "/api/blog/visita", {
          method: "POST", keepalive: true, headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ slug: slug, referer: document.referrer || "" })
        }).catch(function () {});
      }, 1500);
    }
  }

  /* ---- a newsletter de corretores ---- */
  function ligarFormulario(id, caminho, ok) {
    var f = document.getElementById(id);
    if (!f) return;
    var status = $(".news-form__status", f), botao = $("button[type=submit]", f);
    f.addEventListener("submit", function (e) {
      e.preventDefault();
      var dados = {};
      Array.prototype.forEach.call(f.elements, function (el) { if (el.name) dados[el.name] = el.value; });
      if (!String(dados.telefone || "").replace(/\D/g, "").match(/^(55)?\d{10,11}$/)) {
        status.className = "news-form__status erro"; status.textContent = "Confira o WhatsApp: DDD + número, ex.: 92 99999-9999."; return;
      }
      if ("nome" in dados && !dados.nome.trim()) { status.className = "news-form__status erro"; status.textContent = "Diga o seu nome."; return; }
      botao.disabled = true; status.className = "news-form__status"; status.textContent = "Enviando…";
      fetch(API + caminho, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(dados) })
        .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok && j.ok, j: j }; }); })
        .then(function (x) {
          if (!x.ok) throw new Error(x.j.erro || "não deu certo agora");
          status.className = "news-form__status ok"; status.textContent = ok(x.j);
          f.reset();
        })
        .catch(function (err) { status.className = "news-form__status erro"; status.textContent = err.message; })
        .then(function () { botao.disabled = false; });
    });
  }
  ligarFormulario("news-form", "/api/blog/newsletter", function (j) {
    return j.novo ? "Pronto! A Nay já te mandou uma mensagem no WhatsApp. Os imóveis novos chegam por lá."
                  : "Você já estava na lista: continua recebendo os imóveis novos.";
  });
  ligarFormulario("news-sair", "/api/blog/newsletter/sair", function () { return "Pronto, você saiu da lista."; });
})();
