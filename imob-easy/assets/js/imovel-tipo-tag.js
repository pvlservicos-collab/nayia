/* ==========================================================================
   Imob Easy — Editar imóvel: a etiqueta do TIPO, com o (i) dos campos

   Tel (11/10/2026):
     "na aba imoveis editar imovel quero uma tag colorida no topo dizendo o
      tipo do imovel... pode até ser mais preciso Apartamento em condomínio,
      casa em condomínio, ou casa em via pública, e vai ter um (i) um izinho
      do lado e quando eu passar o mouse encima desse tipo vai abrir uma
      janelinha mostrando quais campos vem para esse tipo de imovel"

   POR QUE ARQUIVO SEPARADO: imovel-editar.js tem 72 KB e está sendo mexido
   por outra frente hoje mesmo (11/10 21:30). Mexer nos dois ao mesmo tempo é
   conflito garantido. Aqui nada do que existe é tocado — só se acrescenta.

   TRÊS COISAS DA TELA QUE DITARAM O CÓDIGO (olhadas, não supostas):

   1. #ed-titulo é REESCRITO quando o imóvel carrega (imovel-editar.js:998 faz
      $("ed-titulo").innerHTML = "Imóvel <span>..."). Uma etiqueta pendurada
      antes disso é apagada sem aviso. Daí o observer no próprio h1.

   2. O condomínio NÃO é um campo de formulário: é o widget
      criarSeletorCondominio sobre #ed-condominio, e o escolhido vive no
      fechamento dele. O que dá para ler de fora é a etiqueta que ele pinta
      (.sel-condo__etiqueta, seletor-condominio.js:120). É esse o sinal.

   3. A lista do (i) tem dois grupos, e só um deles depende de eu saber as
      regras: "não aparecem" sai 100% da tela ([data-envolve][hidden], que é o
      que aplicarRegrasDoTipo marca). Só o grupo "campos deste tipo" precisa
      saber QUAIS campos são governados pelo tipo — por isso o ESPELHO abaixo,
      que copia só as CHAVES de POR_TIPO. Cópia é dívida: se divergir, o aviso
      em campos() reclama no console em vez de mostrar dica errada calado.
   ========================================================================== */
(function () {
  "use strict";

  /* O tipo preciso = família do tipo + estar num condomínio. "Casa" sozinho
     não diz nada: casa em condomínio e casa em via pública são negócios
     diferentes e têm campos diferentes (lote de um lado, logradouro do outro). */
  var FAMILIAS = [
    { chave: "vertical", re: /apartamento|flat|cobertura|studio|kitnet|loft/i,
      comCondo: "Apartamento em condomínio", semCondo: "Apartamento" },
    { chave: "sala", re: /sala|loja|ponto|conjunto|escrit[oó]rio/i,
      comCondo: "Sala / ponto em condomínio", semCondo: "Sala / ponto comercial" },
    { chave: "casa", re: /casa|ch[aá]cara|s[ií]tio|fazenda|sobrado/i,
      comCondo: "Casa em condomínio", semCondo: "Casa em via pública" },
    { chave: "terreno", re: /lote|terreno/i,
      comCondo: "Lote em condomínio", semCondo: "Terreno em via pública" }
  ];
  var CORES = {
    vertical: { fundo: "#e7f0ff", texto: "#1e40af", borda: "#bcd3ff" },
    casa:     { fundo: "#e8f7ee", texto: "#1b6b46", borda: "#bfe6cf" },
    sala:     { fundo: "#f3eaff", texto: "#5b21b6", borda: "#ddcaf7" },
    terreno:  { fundo: "#fdf3e3", texto: "#8a4b12", borda: "#f3dcb8" },
    outro:    { fundo: "#eceef2", texto: "#4b5563", borda: "#dcdfe6" }
  };

  /* ESPELHO das chaves de POR_TIPO (imovel-editar.js:278). Só as CHAVES —
     quais campos o tipo governa. Não copio para onde cada um vale: isso quem
     responde é a tela, pelo hidden. */
  var GOVERNADOS = ["area_total", "cobertura", "x:tipo de cobertura", "x:tamanho do terreno",
    "x:frente", "x:fundo", "x:pe direito", "x:andares", "andar", "x:lances de escada",
    "p:torre", "p:bloco", "p:unidade", "p:casa", "p:lote", "quartos", "suites",
    "x:salas", "mobilia"];

  function form() { return document.getElementById("ed-form"); }

  function textoDoTipo() {
    var f = form();
    var el = f && f.querySelector('[data-campo="tipo"]');
    if (!el) return "";
    if (el.tagName === "SELECT" && el.selectedIndex >= 0) {
      return String(el.options[el.selectedIndex].textContent || el.value || "");
    }
    return String(el.value || "");        // tipo e' `lista: true` = input + datalist
  }

  /* Tem condomínio? A etiqueta pintada pelo seletor é o sinal honesto; o
     #ed-condo-ficha aberto serve de reforço quando a ficha já desceu. */
  function temCondominio() {
    var f = form();
    if (!f) return false;
    if (f.querySelector(".sel-condo__etiqueta")) return true;
    var ficha = document.getElementById("ed-condo-ficha");
    return !!(ficha && !ficha.hidden && String(ficha.textContent || "").trim());
  }

  function classificar() {
    var t = textoDoTipo(), condo = temCondominio();
    for (var i = 0; i < FAMILIAS.length; i++) {
      if (FAMILIAS[i].re.test(t)) {
        return { chave: FAMILIAS[i].chave, condo: condo,
                 rotulo: condo ? FAMILIAS[i].comCondo : FAMILIAS[i].semCondo };
      }
    }
    return { chave: "outro", condo: condo, rotulo: t || "Tipo não definido" };
  }

  /* Pego o label DEPOIS que aplicarRegrasDoTipo renomeou (área útil -> área
     construída, bloco -> bloco/setor): a dica fala a língua do tipo. */
  function rotuloDoBloco(b) {
    var rot = b.querySelector("label");
    return rot ? String(rot.textContent || "").replace(/\s+/g, " ").trim() : "";
  }

  /* Dois grupos. `fora` é lido da tela e é sempre verdade. Só `vem` cruza a
     tela com o espelho das chaves. */
  function campos() {
    var f = form(), vem = [], fora = [], estranhos = [];
    if (!f) return { vem: vem, fora: fora };
    var blocos = f.querySelectorAll("[data-envolve]");
    for (var i = 0; i < blocos.length; i++) {
      var b = blocos[i], nome = b.getAttribute("data-envolve");
      if (!nome || nome === "condominio") continue;     // o widget, não um campo do tipo
      var rot = rotuloDoBloco(b);
      if (!rot) continue;
      if (b.hidden || b.closest("[hidden]")) {
        if (fora.indexOf(rot) < 0) fora.push(rot);
        if (GOVERNADOS.indexOf(nome) < 0) estranhos.push(nome);
      } else if (GOVERNADOS.indexOf(nome) >= 0 && vem.indexOf(rot) < 0) {
        vem.push(rot);
      }
    }
    // o espelho envelheceu: reclama alto em vez de mostrar dica errada calado
    if (estranhos.length && !campos._avisou) {
      campos._avisou = true;
      console.warn("[tipo-tag] escondidos fora do espelho GOVERNADOS (alinhe " +
        "imovel-tipo-tag.js com POR_TIPO): " + estranhos.join(", "));
    }
    return { vem: vem, fora: fora };
  }

  function estilo() {
    if (document.getElementById("tipo-tag-estilo")) return;
    var s = document.createElement("style");
    s.id = "tipo-tag-estilo";
    s.textContent = [
      "#tipo-tag { display:inline-flex; align-items:center; gap:7px; vertical-align:middle;",
      "   margin-left:12px; padding:4px 12px; border-radius:999px; border:1px solid;",
      "   font-size:13px; font-weight:700; line-height:1.5; white-space:nowrap }",
      ".tt__i { position:relative; display:inline-grid; place-items:center; width:17px;",
      "   height:17px; border-radius:50%; background:currentColor; cursor:help;",
      "   font-style:normal }",
      ".tt__i b { color:#fff; font-size:11px; font-weight:800; line-height:1 }",
      ".tt__cx { position:absolute; top:calc(100% + 9px); left:50%;",
      "   transform:translateX(-50%); width:min(340px,78vw); display:none; z-index:950;",
      "   padding:12px 14px; background:var(--superficie,#fff);",
      "   color:var(--texto,#2a2140); border:1px solid var(--borda,#e3e6ec);",
      "   border-radius:11px; box-shadow:0 10px 30px rgba(42,33,64,.17);",
      "   font-size:12.5px; font-weight:400; line-height:1.55; text-align:left;",
      "   white-space:normal; cursor:default }",
      ".tt__i:hover .tt__cx, .tt__i:focus .tt__cx, .tt__i:focus-within .tt__cx { display:block }",
      ".tt__cx h4 { margin:0 0 5px; font-size:11px; letter-spacing:.05em;",
      "   text-transform:uppercase; color:var(--texto-fraco,#6b7280) }",
      ".tt__cx h4 + h4, .tt__cx ul + h4 { margin-top:10px }",
      ".tt__cx ul { margin:0; padding-left:16px }",
      ".tt__cx li { margin:1px 0 }",
      ".tt__cx .tt__fora { color:var(--texto-fraco,#6b7280) }",
      ".tt__cx .tt__nota { margin:10px 0 0; padding-top:8px;",
      "   color:var(--texto-fraco,#6b7280); border-top:1px solid var(--borda,#e3e6ec) }",
      "@media (max-width:640px){ #tipo-tag { margin-left:0; margin-top:7px } }"
    ].join("\n");
    document.head.appendChild(s);
  }

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function lista(ns, cls) {
    return '<ul class="' + cls + '">' +
      ns.map(function (n) { return "<li>" + esc(n) + "</li>"; }).join("") + "</ul>";
  }

  var pintando = false;      // o observer dispara com a minha própria escrita

  function desenhar() {
    var h1 = document.getElementById("ed-titulo");
    if (!h1 || pintando) return;
    estilo();

    var c = classificar(), cor = CORES[c.chave] || CORES.outro, cps = campos();

    pintando = true;
    try {
      var tag = document.getElementById("tipo-tag");
      if (!tag || !h1.contains(tag)) {        // o h1 foi reescrito: replanta
        if (tag && tag.parentNode) tag.parentNode.removeChild(tag);
        tag = document.createElement("span");
        tag.id = "tipo-tag";
        h1.appendChild(tag);
      }
      tag.style.background = cor.fundo;
      tag.style.color = cor.texto;
      tag.style.borderColor = cor.borda;

      tag.innerHTML = esc(c.rotulo) +
        '<i class="tt__i" tabindex="0" role="button"' +
          ' aria-label="Quais campos valem para este tipo de imóvel"><b>i</b>' +
          '<span class="tt__cx" role="tooltip">' +
            "<h4>Campos deste tipo</h4>" +
            (cps.vem.length ? lista(cps.vem, "")
                            : '<div class="tt__fora">Escolha o tipo para ver os campos.</div>') +
            (cps.fora.length ? "<h4>Não aparecem aqui</h4>" + lista(cps.fora, "tt__fora") : "") +
            '<div class="tt__nota">' + (c.condo
              ? "Logradouro, bairro, cidade e CEP vêm da ficha do condomínio."
              : "O endereço é preenchido no próprio imóvel.") + "</div>" +
          "</span>" +
        "</i>";
    } finally {
      // solta no próximo quadro, quando as mutações da minha escrita já passaram
      setTimeout(function () { pintando = false; }, 0);
    }
  }

  var t;
  function logo() { clearTimeout(t); t = setTimeout(desenhar, 110); }

  function ligar() {
    desenhar();

    // o tipo e a cobertura mudam o conjunto de campos; o condomínio, o rótulo
    document.addEventListener("change", logo, true);
    document.addEventListener("input", function (e) {
      var d = e.target && e.target.dataset;
      if (d && (d.campo === "tipo" || d.campo === "cobertura")) logo();
    }, true);
    document.addEventListener("click", function (e) {
      var alvo = e.target;
      if (alvo && alvo.closest && alvo.closest(".sel-condo__item, [data-tirar]")) logo();
    }, true);

    if (!window.MutationObserver) return;
    var f = form();
    if (f) {   // o hidden dos blocos, e o formulário nascendo por JS
      new MutationObserver(logo).observe(f, {
        childList: true, subtree: true, attributes: true, attributeFilter: ["hidden"] });
    }
    var h1 = document.getElementById("ed-titulo");
    if (h1) {  // imovel-editar.js reescreve o h1 inteiro ao carregar o imóvel
      new MutationObserver(function () {
        if (!pintando && !document.getElementById("tipo-tag")) logo();
      }).observe(h1, { childList: true });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { setTimeout(ligar, 250); });
  } else {
    setTimeout(ligar, 250);
  }
})();
