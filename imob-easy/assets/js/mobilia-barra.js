/* ==========================================================================
   A barrinha de mobília — um lugar só, usado pelo editar e pelo ver imóvel

   Tel (11/10): "la na sessão onde aparece se o imovel é mobiliado, tinha
   pedido estados, faz uma barrinha colorida que se completa com estágios,
   quanto mais mobilia tem mais ela se preenche; mobiliado tem [4]
   quadradnhos os 4 pintados, e se for pelada é só 1 quadradinho"
   Tel (12/10): "kd a barrinha que eu pedi la encima de mobiliado ou não?"
   -- estava só no popup de ver imóvel. Aqui ela entra no EDITAR também,
   logo acima da lista de Mobília, que é onde ele olha.

   POR QUE UM MÓDULO, E NÃO MAIS UMA CÓPIA: os 4 níveis são uma regra de
   negócio (imovel-editar.js:118) que já tem três leitores -- o formulário, o
   popup e esta barra. Copiar a escala em cada tela é garantir que um dia elas
   discordem sobre o que é "semimobiliado". Quem precisa da barra chama
   `MobiliaBarra.html(valor)`; quem não tiver este arquivo carregado continua
   funcionando (o popup tem um desenho de reserva).

   "SEM NADA" ACENDE UM, NÃO ZERO (foi o pedido, e é melhor assim): zero
   quadradinho se confunde com "ninguém preencheu". Campo vazio tem desenho
   próprio -- 4 apagados e "não informado" --, e isso importa: 4.557 dos 5.705
   imóveis estão sem este campo, e a barra apagada é o que faz esse buraco
   aparecer na tela em vez de passar batido.
   ========================================================================== */
(function () {
  "use strict";

  /* a escala, do menos para o mais mobiliado. As expressões reconhecem também
     como o cadastro antigo escrevia (`caracteristicas`: "Semi-Mobiliado",
     "Climatizado"), senão imóvel importado ficaria sem barra. */
  var NIVEIS = [
    { nivel: 1, rotulo: "Sem nada", cor: "#d1604a", re: /^(sem nada|pelad|sem mob|nada)/i },
    { nivel: 2, rotulo: "Só climatizado", cor: "#d99a3c", re: /^(s[óo] climatizado|climatizado)/i },
    { nivel: 3, rotulo: "Com modulados e ar", cor: "#8fb43f", re: /(modulados|semi.?mobiliad)/i },
    { nivel: 4, rotulo: "Mobiliado", cor: "#3f9e6b", re: /^mobiliad/i }
  ];

  function nivelDe(v) {
    var s = String(v == null ? "" : v).trim();
    if (!s) return null;
    for (var i = 0; i < NIVEIS.length; i++) if (NIVEIS[i].re.test(s)) return NIVEIS[i];
    return null;
  }

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function estilo() {
    if (document.getElementById("mb-estilo")) return;
    var s = document.createElement("style");
    s.id = "mb-estilo";
    s.textContent = [
      ".mb { display: inline-flex; align-items: center; gap: 7px; vertical-align: -1px }",
      ".mb__q { display: inline-flex; gap: 3px }",
      ".mb__q i {",
      "  width: 13px; height: 7px; border-radius: 2px;",
      "  background: var(--borda, #e3daf2); transition: background .15s }",
      ".mb__q i.on { background: var(--mb-cor, #3f9e6b) }",
      ".mb__t { font-size: var(--fs-xs, 11px); color: var(--texto-fraco, #5f5775) }",
      ".mb--vazio .mb__t { font-style: italic }",
      /* no formulário a barra fica acima da lista, encostada no rótulo */
      ".mb--campo { display: flex; margin: 0 0 5px }"
    ].join("\n");
    document.head.appendChild(s);
  }

  /* o HTML da barra. `vazio` decide o desenho de quem não tem valor. */
  function html(valor, opcoes) {
    estilo();
    var o = opcoes || {};
    var n = nivelDe(valor);
    var q = "";
    for (var i = 1; i <= 4; i++) {
      q += "<i" + (n && i <= n.nivel ? ' class="on"' : "") + "></i>";
    }
    var titulo = n ? n.rotulo + " (" + n.nivel + " de 4)" : "Ninguém preencheu a mobília deste imóvel";
    return '<span class="mb' + (n ? "" : " mb--vazio") + (o.campo ? " mb--campo" : "") + '"' +
        (n ? ' style="--mb-cor:' + n.cor + '"' : "") +
        ' data-nivel="' + (n ? n.nivel : 0) + '" title="' + esc(titulo) + '">' +
        '<span class="mb__q" role="img" aria-label="' + esc(titulo) + '">' + q + "</span>" +
        (o.semTexto ? "" : '<span class="mb__t">' + esc(n ? n.rotulo : "não informado") + "</span>") +
      "</span>";
  }

  window.MobiliaBarra = { html: html, nivelDe: nivelDe, niveis: NIVEIS };

  /* ---- no formulário de editar imóvel ----------------------------------
     A barra nasce DENTRO do bloco `[data-envolve="mobilia"]`, entre o rótulo e
     a lista -- "lá encima", como ele pediu -- e acompanha a escolha na hora.
     O observer existe porque `imovel-editar.js` monta o formulário por JS
     depois de buscar o imóvel: sem ele a barra nasceria antes do campo. */
  function pintar() {
    var sel = document.querySelector('#ed-form [data-campo="mobilia"]');
    if (!sel) return;
    var bloco = sel.closest("[data-envolve]") || sel.parentNode;
    var barra = bloco.querySelector(".mb");
    var novo = html(sel.value, { campo: true });
    if (barra) {
      if (barra.outerHTML !== novo) barra.outerHTML = novo;
      return;
    }
    var rot = bloco.querySelector("label");
    var temp = document.createElement("div");
    temp.innerHTML = novo;
    var el = temp.firstElementChild;
    if (rot && rot.nextSibling) bloco.insertBefore(el, rot.nextSibling);
    else bloco.insertBefore(el, sel);
  }

  var t;
  function logo() { clearTimeout(t); t = setTimeout(pintar, 60); }

  function ligar() {
    var form = document.getElementById("ed-form");
    if (!form) return;        // esta página não é o editar imóvel
    if (window.MutationObserver) {
      // o observer PRIMEIRO: se `pintar` estourar, ele já está instalado
      new MutationObserver(function (ms) {
        // a minha própria escrita não precisa de outra passada
        for (var i = 0; i < ms.length; i++) {
          var alvo = ms[i].target;
          if (alvo && alvo.closest && alvo.closest(".mb")) return;
        }
        logo();
      }).observe(form, { childList: true, subtree: true });
    }
    form.addEventListener("change", function (e) {
      if (e.target && e.target.dataset && e.target.dataset.campo === "mobilia") pintar();
    });
    pintar();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { setTimeout(ligar, 250); });
  } else {
    setTimeout(ligar, 250);
  }
})();
