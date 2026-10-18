/* O EDITOR DE ARTIGO DO BLOG (406, 17/10/2026): criar e editar, a prévia, a capa, a FAQ, o imóvel do post e o
   verificador de SEO ao lado (blog-seo.js). Salva em /admin/api/blog/artigos; a nota de SEO vai junto. */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var BLOG = "https://blog.imobeasy.online";
  var id = new URLSearchParams(location.search).get("id");
  var artigo = { tipo: "post", faq: [] }, imovelNoAr = null, slugMexido = false, sujo = false;

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin" }, op || {})).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status)); return j; });
    });
  }
  function json(op) { return Object.assign({ headers: { "Content-Type": "application/json" } }, op); }
  function slugDe(t) {
    return String(t || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/-{2,}/g, "-").replace(/^-|-$/g, "").slice(0, 80);
  }
  function status(txt, tipo) { var s = $("ed-status"); s.textContent = txt || ""; s.className = "status" + (tipo ? " " + tipo : ""); }

  /* ---- os contadores dos campos ---- */
  document.querySelectorAll("[data-conta]").forEach(function (c) {
    var campo = $(c.dataset.conta), faixa = c.dataset.faixa.split("-").map(Number);
    var at = function () { var n = campo.value.trim().length; c.textContent = n + " / " + faixa[0] + "–" + faixa[1]; c.classList.toggle("alerta", n > 0 && (n < faixa[0] || n > faixa[1])); };
    campo.addEventListener("input", at); at();
  });

  /* ---- o que está na tela ---- */
  function ler() {
    return {
      id: id ? Number(id) : null, titulo: $("f-titulo").value, slug: $("f-slug").value, categoria: $("f-categoria").value, tipo: artigo.tipo,
      codigo: $("f-codigo").value.replace(/\D/g, "") || null, bairro: $("f-bairro").value, resumo: $("f-resumo").value,
      palavra_chave: $("f-palavra").value, capa_url: $("f-capa").value.trim(), capa_alt: $("f-capa-alt").value, corpo: $("f-corpo").value,
      faq: Array.prototype.map.call(document.querySelectorAll(".ed-faq__item"), function (it) {
        return { pergunta: it.querySelector("[data-p]").value.trim(), resposta: it.querySelector("[data-r]").value.trim() };
      }).filter(function (f) { return f.pergunta || f.resposta; }),
      imoveis_relacionados: $("f-relacionados").value.split(/[,;\s]+/).map(function (x) { return x.replace(/\D/g, ""); }).filter(Boolean).map(Number),
      autor: $("f-autor").value, publicado: $("f-publicado").checked,
      publicado_em: $("f-data").value ? new Date($("f-data").value).toISOString() : null, imovel_no_ar: imovelNoAr
    };
  }
  function preencher(a) {
    artigo = a;
    $("f-titulo").value = a.titulo || ""; $("f-slug").value = a.slug || ""; slugMexido = !!a.slug;
    $("f-categoria").value = a.categoria || ""; $("f-codigo").value = a.codigo || ""; $("f-bairro").value = a.bairro || "";
    $("f-resumo").value = a.resumo || ""; $("f-palavra").value = a.palavra_chave || ""; $("f-capa").value = a.capa_url || ""; $("f-capa-alt").value = a.capa_alt || "";
    $("f-corpo").value = a.corpo || ""; $("f-relacionados").value = (a.imoveis_relacionados || []).join(", "); $("f-autor").value = a.autor || "Equipe Imob Easy";
    $("f-publicado").checked = !!a.publicado;
    if (a.publicado_em) { var d = new Date(a.publicado_em); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); $("f-data").value = d.toISOString().slice(0, 16); }
    tipo(a.tipo || "post"); faqPintar(a.faq || []); capaPintar();
    document.querySelectorAll("[data-conta]").forEach(function (c) { $(c.dataset.conta).dispatchEvent(new Event("input")); });
    $("ed-titulo-pagina").textContent = a.id ? "Editar artigo" : "Novo artigo";
    $("ed-apagar").hidden = !a.id;
    $("ed-ver").hidden = !(a.id && a.publicado); $("ed-ver").href = BLOG + "/artigo/" + (a.slug || "");
    if (a.codigo) imovelBuscar(a.codigo, a.imovel);
    seo(); previa();
  }

  /* ---- tipo ---- */
  function tipo(t) {
    artigo.tipo = t;
    document.querySelectorAll("[data-tipo]").forEach(function (b) { b.setAttribute("aria-selected", String(b.dataset.tipo === t)); });
    $("ed-bloco-imovel").style.opacity = t === "imovel" ? "1" : ".85";
  }
  document.querySelectorAll("[data-tipo]").forEach(function (b) { b.addEventListener("click", function () { tipo(b.dataset.tipo); sujo = true; seo(); }); });

  /* ---- o imóvel do post ---- */
  var esperaImovel = null;
  function imovelBuscar(codigo, pronto) {
    var caixa = $("ed-imovel"), aviso = $("ed-imovel-aviso");
    if (!codigo) { caixa.hidden = true; aviso.textContent = ""; imovelNoAr = null; seo(); return; }
    var mostrar = function (im) {
      imovelNoAr = !!im.no_ar;
      caixa.hidden = false; caixa.className = "ed-imovel" + (im.no_ar ? "" : " fora");
      caixa.innerHTML = (im.capa ? '<img src="' + esc(im.capa) + '" alt="">' : "") + "<div><b>#" + esc(im.codigo) + " · " + esc(im.condominio || im.tipo || "") + "</b><br>" +
        esc([im.tipo, im.bairro].filter(Boolean).join(" · ")) + (im.valor_aluguel ? " · R$ " + Number(im.valor_aluguel).toLocaleString("pt-BR") + "/mês" : "") +
        (im.valor_venda ? " · R$ " + Number(im.valor_venda).toLocaleString("pt-BR") : "") +
        (im.no_ar ? "" : '<br><span style="color:#a8672f">Não está no ar (' + esc(im.motivo || "") + "): o card não aparece no artigo.</span>") + "</div>";
      aviso.textContent = im.no_ar ? "no ar" : "fora do ar";
      if (!$("f-bairro").value && im.bairro) $("f-bairro").value = im.bairro;
      seo();
    };
    if (pronto && pronto.codigo) { mostrar(Object.assign({ no_ar: true }, pronto)); return; }
    aviso.textContent = "procurando…";
    pedir("api/blog/imovel/" + codigo).then(mostrar).catch(function (e) {
      imovelNoAr = false; caixa.hidden = false; caixa.className = "ed-imovel fora"; caixa.textContent = e.message; aviso.textContent = "não achei"; seo();
    });
  }
  $("f-codigo").addEventListener("input", function () {
    clearTimeout(esperaImovel); sujo = true;
    var c = this.value.replace(/\D/g, "");
    esperaImovel = setTimeout(function () { imovelBuscar(c); }, 400);
  });

  /* ---- slug ---- */
  $("f-titulo").addEventListener("input", function () { if (!slugMexido) $("f-slug").value = slugDe(this.value); slugAt(); });
  $("f-slug").addEventListener("input", function () { slugMexido = !!this.value; this.value = slugDe(this.value) || this.value; slugAt(); });
  function slugAt() { var s = $("f-slug").value || slugDe($("f-titulo").value); $("ed-slug-previa").textContent = s || "…"; $("ed-slug-conta").textContent = s.length + " caracteres"; }

  /* ---- capa ---- */
  function capaPintar() {
    var u = $("f-capa").value.trim(), el = $("ed-capa-img");
    el.style.backgroundImage = u ? "url('" + u.replace(/'/g, "%27") + "')" : ""; el.textContent = u ? "" : "sem capa";
  }
  $("f-capa").addEventListener("input", function () { capaPintar(); sujo = true; seo(); });
  function subirImagem(arquivo) {
    var fd = new FormData(); fd.append("arquivo", arquivo);
    status("Subindo a imagem…");
    return pedir("api/blog/imagem", { method: "POST", body: fd }).then(function (j) { status("Imagem no ar.", "ok"); return j.url; })
      .catch(function (e) { status("Não subiu a imagem: " + e.message, "erro"); throw e; });
  }
  $("f-capa-arquivo").addEventListener("change", function () {
    if (!this.files[0]) return;
    subirImagem(this.files[0]).then(function (url) { $("f-capa").value = url; capaPintar(); sujo = true; seo(); }).catch(function () {});
  });

  /* ---- a barra do markdown ---- */
  var ta = $("f-corpo");
  function envolver(antes, depois, padrao) {
    var i = ta.selectionStart, f = ta.selectionEnd, sel = ta.value.slice(i, f) || padrao || "";
    ta.setRangeText(antes + sel + depois, i, f, "end"); ta.focus(); mudouCorpo();
  }
  function linha(prefixo) {
    var i = ta.selectionStart, ini = ta.value.lastIndexOf("\n", i - 1) + 1;
    var quebra = ini > 0 && ta.value[ini - 1] !== "\n" && ta.value.slice(Math.max(0, ini - 2), ini) !== "\n\n" ? "\n" : "";
    ta.setRangeText(quebra + prefixo, ini, ini, "end"); ta.focus(); mudouCorpo();
  }
  $("ed-barra").addEventListener("click", function (e) {
    var b = e.target.closest("[data-md]"); if (!b) return;
    var m = b.dataset.md, url;
    if (m === "h2") linha("## "); else if (m === "h3") linha("### ");
    else if (m === "b") envolver("**", "**", "texto"); else if (m === "i") envolver("*", "*", "texto");
    else if (m === "ul") linha("- "); else if (m === "ol") linha("1. "); else if (m === "quote") linha("> ");
    else if (m === "link") { url = prompt("Endereço do link (https://…):", "https://"); if (url) envolver("[", "](" + url + ")", "texto do link"); }
    else if (m === "imovel") { var c = prompt("Código do imóvel:"); if (c && /^\d+$/.test(c.trim())) envolver("[", "](https://imobeasy.online/imovel/" + c.trim() + ")", "veja o imóvel " + c.trim()); }
    else if (m === "img") $("f-img-arquivo").click();
  });
  $("f-img-arquivo").addEventListener("change", function () {
    if (!this.files[0]) return;
    subirImagem(this.files[0]).then(function (url) { var d = prompt("Descreva a imagem (texto alternativo):", "") || ""; envolver("\n![" + d + "](" + url + ")\n", "", ""); }).catch(function () {});
    this.value = "";
  });
  document.querySelectorAll("[data-modo]").forEach(function (b) {
    b.addEventListener("click", function () {
      document.querySelectorAll("[data-modo]").forEach(function (x) { x.setAttribute("aria-selected", String(x === b)); });
      var pv = b.dataset.modo === "previa"; ta.hidden = pv; $("ed-previa").hidden = !pv; if (pv) previa(true);
    });
  });

  /* ---- prévia e contagem ---- */
  var esperaPrevia = null;
  function previa(agora) {
    clearTimeout(esperaPrevia);
    var faz = function () {
      pedir("api/blog/previa", json({ method: "POST", body: JSON.stringify({ corpo: ta.value }) })).then(function (j) {
        $("ed-previa").innerHTML = j.html || '<p style="color:var(--texto-fraco)">Nada escrito ainda.</p>';
        $("ed-palavras").textContent = (j.palavras || 0).toLocaleString("pt-BR") + " palavras · " + Math.max(1, Math.round((j.palavras || 0) / 200)) + " min de leitura";
      }).catch(function () {});
    };
    if (agora) faz(); else esperaPrevia = setTimeout(faz, 700);
  }
  function mudouCorpo() { sujo = true; seo(); if (!$("ed-previa").hidden) previa(); else { clearTimeout(esperaPrevia); esperaPrevia = setTimeout(function () { previa(true); }, 1200); } }
  ta.addEventListener("input", mudouCorpo);

  /* ---- FAQ ---- */
  function faqPintar(lista) {
    $("ed-faq").innerHTML = (lista.length ? lista : [{ pergunta: "", resposta: "" }]).map(function (f) {
      return '<div class="ed-faq__item"><input class="entrada" data-p placeholder="Pergunta (como a pessoa perguntaria)" value="' + esc(f.pergunta) + '">' +
        '<textarea class="entrada" data-r placeholder="Resposta curta e direta (40 a 400 caracteres)">' + esc(f.resposta) + "</textarea>" +
        '<button class="btn-mini" type="button" data-faq-x aria-label="Tirar pergunta">×</button></div>';
    }).join("");
  }
  $("ed-faq-add").addEventListener("click", function () { faqPintar(ler().faq.concat([{ pergunta: "", resposta: "" }])); });
  $("ed-faq").addEventListener("click", function (e) { var b = e.target.closest("[data-faq-x]"); if (!b) return; b.closest(".ed-faq__item").remove(); sujo = true; seo(); });
  $("ed-faq").addEventListener("input", function () { sujo = true; seo(); });

  /* ---- SEO ao vivo ---- */
  var esperaSeo = null, ultimaNota = null;
  function seo() {
    clearTimeout(esperaSeo);
    esperaSeo = setTimeout(function () {
      var r = window.BlogSEO.avaliar(ler());
      ultimaNota = r.nota;
      window.BlogSEO.pintar(r, $("seo-lista"), $("seo-nota"), $("seo-anel"), $("seo-frase"));
    }, 250);
  }
  ["f-titulo", "f-resumo", "f-palavra", "f-slug", "f-capa-alt", "f-categoria", "f-relacionados", "f-bairro"].forEach(function (i) {
    $(i).addEventListener("input", function () { sujo = true; seo(); }); $(i).addEventListener("change", seo);
  });

  /* ---- salvar, apagar ---- */
  $("ed-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var d = ler(); d.seo_nota = ultimaNota;
    if (!d.titulo.trim()) { status("Dê um título ao artigo.", "erro"); $("f-titulo").focus(); return; }
    if (!d.categoria) { status("Escolha a categoria.", "erro"); $("f-categoria").focus(); return; }
    if (d.tipo === "imovel" && !d.codigo) { status("Post de imóvel precisa do código do imóvel.", "erro"); $("f-codigo").focus(); return; }
    if (d.publicado && ultimaNota != null && ultimaNota < 50 && !confirm("A nota de SEO está em " + ultimaNota + ". Publicar assim mesmo?")) return;
    $("ed-salvar").disabled = true; status("Salvando…");
    pedir("api/blog/artigos", json({ method: "POST", body: JSON.stringify(d) })).then(function (j) {
      sujo = false;
      status(d.publicado ? "Salvo e no ar: " + j.url : "Rascunho salvo.", "ok");
      if (!id) { id = String(j.id); history.replaceState(null, "", "blog-editar.html?id=" + j.id); }
      $("f-slug").value = j.slug; slugAt();
      $("ed-ver").hidden = !d.publicado; $("ed-ver").href = j.url; $("ed-apagar").hidden = false; $("ed-titulo-pagina").textContent = "Editar artigo";
    }).catch(function (e) { status(e.message, "erro"); }).then(function () { $("ed-salvar").disabled = false; });
  });
  $("ed-apagar").addEventListener("click", function () {
    if (!id || !confirm("Apagar este artigo? Ele some do blog e das métricas.")) return;
    pedir("api/blog/artigos/" + id, { method: "DELETE" }).then(function () { sujo = false; location.href = "blog.html"; }).catch(function (e) { status(e.message, "erro"); });
  });
  window.addEventListener("beforeunload", function (e) { if (sujo) { e.preventDefault(); e.returnValue = ""; } });

  /* ---- começa ---- */
  if (id) {
    pedir("api/blog/artigos/" + id).then(preencher).catch(function (e) { status("Não achei o artigo: " + e.message, "erro"); });
  } else {
    preencher({ tipo: "post", faq: [], autor: "Equipe Imob Easy" });
    var cat = new URLSearchParams(location.search).get("categoria"); if (cat) $("f-categoria").value = cat;
  }
})();
