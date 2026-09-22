/* =====================================================================
   ESTRUTURA DA NAY -- os numeros que enchem o fluxograma.

   Tel (22/09/2026): "implementa visualmente la no nay ia, la no site como
   vai ficar essa estrutura nova em fluxograma".

   O desenho e estatico no HTML (ele nao muda por execucao). O que muda --
   para onde a mente mandou, o que ela aprendeu, o que esta esperando --
   vem de /api/nai/estrutura, que e so leitura.

   Sem API configurada a pagina continua de pe: o desenho aparece igual e
   os numeros ficam em "—". Nunca quebra a tela.
   ===================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";

  function $(id) { return document.getElementById(id); }

  function texto(el, v) { if (el) { el.firstChild ? (el.firstChild.nodeValue = v) : (el.textContent = v); } }

  function escapar(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function quando(iso) {
    if (!iso) { return "—"; }
    /* O banco ja esta em Manaus: mostrar como veio, sem converter de novo. */
    var m = String(iso).match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
    return m ? (m[3] + "/" + m[2] + " " + m[4] + ":" + m[5]) : String(iso).slice(0, 16);
  }

  function dinheiro(v) {
    if (v == null) { return "—"; }
    return "R$ " + Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 0 });
  }

  function tabela(colunas, linhas, montar) {
    if (!linhas || !linhas.length) { return '<p class="es-vazio">Nada por aqui ainda.</p>'; }
    var h = '<table class="es-tabela"><thead><tr>';
    colunas.forEach(function (c) { h += "<th>" + escapar(c) + "</th>"; });
    h += "</tr></thead><tbody>";
    linhas.forEach(function (l) { h += "<tr>" + montar(l) + "</tr>"; });
    return h + "</tbody></table>";
  }

  function desenhar(d) {
    /* ---- o selo de ligada/desligada ---- */
    var selo = $("es-selo-sec");
    if (selo) {
      selo.textContent = d.secretaria_ligada ? "secretária no ar" : "secretária desligada";
      selo.className = "es-selo " + (d.secretaria_ligada ? "es-selo--on" : "es-selo--off");
    }

    /* ---- para onde a mente mandou ---- */
    var loc = 0, sec = 0;
    (d.decisoes || []).forEach(function (x) {
      if (x.atendente === "secretaria") { sec += Number(x.quantas || 0); }
      else { loc += Number(x.quantas || 0); }
    });
    texto($("es-total"), String(loc + sec));
    texto($("es-loc"), String(loc));
    texto($("es-sec"), String(sec));

    /* ---- os cartoes ---- */
    var fichas = d.fichas || [];
    texto($("es-c-saber"), String((d.saber || []).length));
    texto($("es-c-esperando"), String((d.esperando || []).length));
    texto($("es-c-fichas"), String(fichas.filter(function (f) { return f.situacao === "colhendo"; }).length));
    texto($("es-c-subidos"), String(fichas.filter(function (f) { return f.situacao === "subido"; }).length));

    /* ---- as ultimas decisoes ---- */
    $("es-decisoes").innerHTML = tabela(
      ["Quando", "Foi para", "Por quê", "O que ele escreveu"],
      d.ultimas_decisoes,
      function (l) {
        var eti = l.atendente === "secretaria"
          ? '<span class="es-eti es-eti--sec">secretária</span>'
          : '<span class="es-eti es-eti--loc">locação</span>';
        return "<td>" + quando(l.criado_em) + "</td><td>" + eti + "</td>" +
               "<td>" + escapar(l.motivo || "—") + "</td>" +
               "<td>" + escapar(l.escreveu || "—") + "</td>";
      });

    /* ---- o que ela aprendeu ---- */
    $("es-saber").innerHTML = tabela(
      ["Quando", "A pergunta", "O que o Tel respondeu", "Usada"],
      d.saber,
      function (l) {
        return "<td>" + quando(l.criado_em) + "</td>" +
               "<td>" + escapar(l.pergunta) + "</td>" +
               "<td>" + escapar(l.resposta) + "</td>" +
               "<td>" + (l.vezes_usada || 0) + "x</td>";
      });

    /* ---- as fichas de imovel ---- */
    $("es-fichas").innerHTML = tabela(
      ["Quando", "Situação", "Código", "O que é", "Onde", "Valor", "Fotos", "Falta"],
      fichas,
      function (l) {
        return "<td>" + quando(l.criado_em) + "</td>" +
               "<td>" + escapar(l.situacao) + "</td>" +
               "<td>" + (l.codigo || "—") + "</td>" +
               "<td>" + escapar([l.tipo, l.quartos ? l.quartos + " qts" : null, l.finalidade]
                                 .filter(Boolean).join(" · ") || "—") + "</td>" +
               "<td>" + escapar([l.condominio, l.bairro].filter(Boolean).join(" — ") || "—") + "</td>" +
               "<td>" + dinheiro(l.valor) + "</td>" +
               "<td>" + (l.fotos || 0) + "</td>" +
               "<td>" + escapar(l.falta || "nada") + "</td>";
      });
  }

  function erro(msg) {
    ["es-decisoes", "es-saber", "es-fichas"].forEach(function (id) {
      var el = $(id);
      if (el) { el.innerHTML = '<p class="es-vazio">' + escapar(msg) + "</p>"; }
    });
  }

  if (!API) { erro("API não configurada — o desenho acima continua valendo."); return; }

  fetch(API + "/api/nai/estrutura")
    .then(function (r) {
      if (!r.ok) { throw new Error("a API respondeu " + r.status); }
      return r.json();
    })
    .then(desenhar)
    .catch(function (e) { erro("Não consegui ler os números: " + e.message); });
}());
