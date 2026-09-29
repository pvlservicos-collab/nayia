/* ==========================================================================
   Imob Easy — campo de várias escolhas com a lista que desce (28/09/2026)

   Tel: "eu quero poder selecionar mais de um bairro, mais de uma informação
   de tudo, e quando eu começo a digitar desce a lista também do nosso banco
   para só selecionar sem precisar digitar certinho".

   criarMultiSelecao(elemento, { opcoes: [{valor, rotulo?, n?}], dica, aoMudar })
     -> { valores(), definir([...]), opcoes([...]), limpar() }

   A lista filtra sem acento ("taruma" acha Tarumã); setas e Enter escolhem,
   Backspace no campo vazio tira a última escolha, Esc fecha.
   ========================================================================== */
(function () {
  "use strict";

  function semAcento(s) {
    return String(s == null ? "" : s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  if (!document.getElementById("estilo-multiselecao")) {
    var st = document.createElement("style");
    st.id = "estilo-multiselecao";
    st.textContent =
      ".ms{position:relative;min-width:0}" +
      ".ms__caixa{display:flex;flex-wrap:wrap;gap:4px;align-items:center;min-height:40px;padding:4px 6px;cursor:text;" +
        "background:var(--superficie,#fff);border:1px solid var(--borda,#e3daf2);border-radius:var(--raio,10px)}" +
      ".ms__caixa:focus-within{border-color:var(--azul,#6d28d9);box-shadow:var(--foco,0 0 0 3px rgba(109,40,217,.15))}" +
      ".ms__chips{display:contents}" +
      ".ms__chip{display:inline-flex;align-items:center;gap:2px;padding:2px 2px 2px 9px;border-radius:999px;font-size:12px;" +
        "background:var(--azul-claro,#f1eaff);border:1px solid var(--azul-borda,#d3c1f4);color:var(--texto,#1f1633);white-space:nowrap}" +
      ".ms__chip button{border:0;background:none;cursor:pointer;font-size:14px;line-height:1;padding:0 6px;color:var(--texto-medio,#555)}" +
      ".ms__texto{flex:1;min-width:90px;border:0;outline:0;background:transparent;font:inherit;font-size:14px;padding:4px}" +
      ".ms__lista{position:absolute;z-index:1000;left:0;right:0;top:calc(100% + 4px);max-height:260px;overflow-y:auto;" +
        "background:var(--superficie,#fff);border:1px solid var(--borda,#e3daf2);border-radius:var(--raio,10px);box-shadow:0 10px 30px rgba(40,20,80,.18)}" +
      ".ms__op{display:flex;justify-content:space-between;gap:10px;width:100%;padding:7px 12px;border:0;background:none;" +
        "text-align:left;font:inherit;font-size:14px;cursor:pointer;color:inherit}" +
      ".ms__op small{color:var(--texto-fraco,#888)}" +
      ".ms__op:hover,.ms__op--ativo{background:var(--azul-claro,#f1eaff)}" +
      ".ms__vazio{padding:8px 12px;font-size:12px;color:var(--texto-fraco,#888)}";
    document.head.appendChild(st);
  }

  window.criarMultiSelecao = function (alvo, cfg) {
    cfg = cfg || {};
    var opcoes = cfg.opcoes || [];
    var valores = [];
    var ativo = 0;
    var aberto = false;

    alvo.classList.add("ms");
    alvo.innerHTML = '<div class="ms__caixa"><span class="ms__chips"></span>' +
      '<input class="ms__texto" type="text" autocomplete="off" aria-label="' + esc(cfg.dica || "escolher") + '"></div>' +
      '<div class="ms__lista" role="listbox" hidden></div>';
    var caixa = alvo.querySelector(".ms__caixa");
    var chips = alvo.querySelector(".ms__chips");
    var input = alvo.querySelector(".ms__texto");
    var lista = alvo.querySelector(".ms__lista");

    function rotuloDe(v) {
      var o = opcoes.filter(function (x) { return x.valor === v; })[0];
      return o && o.rotulo ? o.rotulo : v;
    }
    function filtradas() {
      var b = semAcento(input.value.trim());
      return opcoes.filter(function (o) {
        return valores.indexOf(o.valor) < 0 && semAcento(o.rotulo || o.valor).indexOf(b) >= 0;
      }).slice(0, 80);
    }
    function pintarChips() {
      chips.innerHTML = valores.map(function (v) {
        return '<span class="ms__chip">' + esc(rotuloDe(v)) +
          '<button type="button" data-tira="' + esc(v) + '" aria-label="tirar ' + esc(rotuloDe(v)) + '">×</button></span>';
      }).join("");
      input.placeholder = valores.length ? "" : (cfg.dica || "");
    }
    function pintarLista() {
      if (!aberto) { lista.hidden = true; return; }
      var fs = filtradas();
      if (!fs.length) {
        lista.hidden = !input.value.trim();
        lista.innerHTML = '<div class="ms__vazio">nada com isso no nosso banco</div>';
        return;
      }
      ativo = Math.max(0, Math.min(ativo, fs.length - 1));
      lista.hidden = false;
      lista.innerHTML = fs.map(function (o, k) {
        return '<button type="button" role="option" class="ms__op' + (k === ativo ? " ms__op--ativo" : "") +
          '" data-v="' + esc(o.valor) + '"><span>' + esc(o.rotulo || o.valor) + "</span>" +
          (o.n != null ? "<small>" + o.n + "</small>" : "") + "</button>";
      }).join("");
      var marcado = lista.querySelector(".ms__op--ativo");
      if (marcado && marcado.scrollIntoView) marcado.scrollIntoView({ block: "nearest" });
    }
    function abrir() { aberto = true; pintarLista(); }
    function fechar() { aberto = false; lista.hidden = true; }
    function mudou() {
      pintarChips(); pintarLista();
      if (cfg.aoMudar) cfg.aoMudar(valores.slice());
    }
    function pegar(v) {
      if (valores.indexOf(v) < 0) valores.push(v);
      input.value = ""; ativo = 0;
      // a lista FECHA a cada escolha: aberta, ela cobria o que vem embaixo e o
      // proximo clique caia nela. Volta ao digitar ou ao clicar no campo.
      aberto = false;
      mudou();
      input.focus();
    }

    caixa.addEventListener("click", function (e) {
      var t = e.target.closest("[data-tira]");
      if (t) {
        valores = valores.filter(function (x) { return x !== t.dataset.tira; });
        mudou();
        return;
      }
      input.focus(); abrir();
    });
    input.addEventListener("focus", function () { if (!input.value) abrir(); });
    input.addEventListener("input", function () { ativo = 0; abrir(); });
    input.addEventListener("keydown", function (e) {
      var fs = filtradas();
      if (e.key === "ArrowDown") { e.preventDefault(); ativo = Math.min(ativo + 1, fs.length - 1); abrir(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); ativo = Math.max(ativo - 1, 0); pintarLista(); }
      else if (e.key === "Enter") { e.preventDefault(); if (fs[ativo]) pegar(fs[ativo].valor); }
      else if (e.key === "Backspace" && !input.value && valores.length) { valores.pop(); mudou(); }
      else if (e.key === "Escape") { fechar(); }
    });
    lista.addEventListener("mousedown", function (e) { e.preventDefault(); });
    lista.addEventListener("click", function (e) {
      var b = e.target.closest("[data-v]");
      if (b) pegar(b.dataset.v);
    });
    document.addEventListener("mousedown", function (e) { if (!alvo.contains(e.target)) fechar(); });
    pintarChips();

    return {
      valores: function () { return valores.slice(); },
      definir: function (vs) { valores = (vs || []).slice(); pintarChips(); pintarLista(); },
      opcoes: function (os) { opcoes = os || []; pintarChips(); pintarLista(); },
      limpar: function () { valores = []; pintarChips(); pintarLista(); }
    };
  };
})();
