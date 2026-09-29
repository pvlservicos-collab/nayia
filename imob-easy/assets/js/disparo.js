/* ==========================================================================
   Imob Easy — Enviar imóvel (28/09/2026, pedido do Tel)
   "lá em cima o número, embaixo um campo de pesquisar imóvel, digita uma
   parte e desce uma lista de imóveis, eu seleciono e clico em enviar... eu
   seleciono também qual número quero enviar, por padrão fica o de parceria."

   POR FAIXA (mesmo dia): "enviar intervalo de imóveis, aí eu posso selecionar
   uma faixa de renda, bairro ou imobiliário e o sistema vai achar e marcar os
   imóveis para mim confirmar visualmente e aí clico em enviar e ele envia".

   A busca um a um lê a lista aberta do site (/api/imoveis-lista), só o que é
   nosso e está disponível. A busca por faixa e o envio vão para
   /admin/api/disparo..., no PRÓPRIO domínio, atrás da senha do /admin; a API
   repassa ao CRM, que confere as paredes da Nay e manda. A mesma tela existe
   no CRM.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";
  var $ = function (id) { return document.getElementById(id); };
  var escolhidos = [];
  var resultados = [];
  var achados = null;
  var linhas = [];
  var teto = 10;
  var modo = "um";
  var espera = null;
  var enviando = false;

  /* POR FAIXA: vários bairros e tipos, com a lista do nosso banco descendo (28/09) */
  var msBairros = window.criarMultiSelecao($("f-bairros"), { dica: "digite e escolha: um ou vários" });
  var msTipos = window.criarMultiSelecao($("f-tipos"), { dica: "todos" });
  document.querySelectorAll(".dp-chip-op").forEach(function (b) {
    b.addEventListener("click", function () { b.setAttribute("aria-pressed", b.getAttribute("aria-pressed") === "true" ? "false" : "true"); });
  });
  function ligados(attr) {
    return [].slice.call(document.querySelectorAll(".dp-chip-op[" + attr + '][aria-pressed="true"]'))
      .map(function (b) { return b.getAttribute(attr); });
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function reais(v) {
    return Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
  }
  function digitos() { return $("dp-telefone").value.replace(/\D/g, ""); }
  function formatar(v) {
    var d = String(v).replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "");
    if (d.length === 11) return d.slice(0, 2) + " " + d.slice(2, 7) + "-" + d.slice(7);
    if (d.length === 10) return d.slice(0, 2) + " " + d.slice(2, 6) + "-" + d.slice(6);
    return v;
  }
  function marcado(cod) { return escolhidos.some(function (e) { return e.codigo === cod; }); }

  /* ---- as linhas de WhatsApp (a Parceria é o padrão) ---- */
  function avisoDaLinha() {
    var l = linhas.filter(function (x) { return x.id === $("dp-linha").value; })[0];
    $("dp-aviso").hidden = !(l && l.aviso);
    $("dp-aviso").textContent = (l && l.aviso) || "";
  }
  fetch("api/disparo/linhas", { credentials: "same-origin", cache: "no-store" })
    .then(function (r) { return r.json().then(function (j) { return r.ok ? j : Promise.reject(j.erro); }); })
    .then(function (j) {
      linhas = j.linhas || [];
      if (Number(j.teto) > 0) teto = Number(j.teto);
      $("dp-linha").innerHTML = linhas.map(function (l) {
        return '<option value="' + esc(l.id) + '"' + (l.padrao ? " selected" : "") + ">" +
               esc(l.nome) + (l.padrao ? " (padrão)" : "") + "</option>";
      }).join("") || '<option value="">nenhuma linha</option>';
      var op = j.opcoes || {};
      msBairros.opcoes(op.bairros || []);
      msTipos.opcoes(op.tipos || []);
      avisoDaLinha();
      atualizar();
    })
    .catch(function (e) {
      $("dp-linha").innerHTML = '<option value="">não consegui ler as linhas</option>';
      mostrar(false, "Não consegui ler as linhas de WhatsApp: " + (e || "erro"));
    });
  $("dp-linha").addEventListener("change", function () { avisoDaLinha(); limparResposta(); atualizar(); });

  /* ---- um a um: a lista desce enquanto ele digita ---- */
  function pintarLista(procurando) {
    var caixa = $("dp-lista");
    if ($("dp-q").value.trim().length < 2) { caixa.hidden = true; return; }
    caixa.hidden = false;
    if (procurando) { caixa.innerHTML = '<p class="dp-vazio">procurando…</p>'; return; }
    if (!resultados.length) { caixa.innerHTML = '<p class="dp-vazio">Nenhum imóvel nosso disponível com isso.</p>'; return; }
    caixa.innerHTML = resultados.map(function (i, n) {
      var sub = [i.bairro, i.quartos ? i.quartos + " quartos" : null, i.valor,
                 i.fotos ? i.fotos + " fotos" : "sem foto"].filter(Boolean).join(" · ");
      return item(i, "data-n", n, sub);
    }).join("");
  }
  function item(i, attr, n, sub) {
    return '<button type="button" class="dp-item' + (marcado(i.codigo) ? " dp-item--marcado" : "") + '" ' + attr + '="' + n + '">' +
      '<span class="dp-caixa">' + (marcado(i.codigo) ? "✓" : "") + "</span>" +
      (i.capa ? '<img class="dp-capa" src="' + esc(i.capa) + '" alt="" loading="lazy">' : '<span class="dp-capa"></span>') +
      '<span class="dp-texto"><b>#' + esc(i.codigo) + " · " + esc(i.condominio || i.tipo || "Imóvel") + "</b>" +
      "<span>" + esc(sub) + "</span></span></button>";
  }
  $("dp-q").addEventListener("input", function () {
    clearTimeout(espera);
    var q = $("dp-q").value.trim();
    if (q.length < 2) { resultados = []; pintarLista(); return; }
    pintarLista(true);
    espera = setTimeout(function () {
      var p = new URLSearchParams({ q: q, status: "Disponível", parceiro: "nao", per: "15", page: "1" });
      fetch(API + "/api/imoveis-lista?" + p.toString(), { cache: "no-store" })
        .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function (j) { if ($("dp-q").value.trim() === q) { resultados = j.itens || []; pintarLista(); } })
        .catch(function () { resultados = []; pintarLista(); });
    }, 300);
  });
  $("dp-q").addEventListener("focus", function () { if (resultados.length) pintarLista(); });
  $("dp-lista").addEventListener("click", function (e) {
    var b = e.target.closest(".dp-item");
    if (!b) return;
    alternar(resultados[Number(b.dataset.n)]);
    pintarLista();
  });
  document.addEventListener("mousedown", function (e) {
    if (!$("dp-busca").contains(e.target)) $("dp-lista").hidden = true;
  });

  /* ---- por faixa: acha e marca, ele confere ---- */
  function pintarAchados() {
    var caixa = $("dp-achados");
    if (!achados || !achados.length) { caixa.hidden = true; caixa.innerHTML = ""; return; }
    caixa.hidden = false;
    caixa.innerHTML =
      '<div class="dp-achados__topo"><span><b>' + escolhidos.length + "</b> de " + achados.length +
        " marcados (máximo " + teto + ")</span><span>" +
        '<button type="button" data-marcar="primeiros">marcar os ' + Math.min(teto, achados.length) + " primeiros</button> · " +
        '<button type="button" data-marcar="nenhum">desmarcar todos</button></span></div>' +
      achados.map(function (i, n) {
        var sub = [i.valor, i.bairro, i.quartos ? i.quartos + " quartos" : null, i.mobilia || null,
                   i.fotos ? i.fotos + " fotos" : "sem foto"].filter(Boolean).join(" · ");
        return item(i, "data-a", n, sub);
      }).join("");
  }
  function doAchado(a, fin) {
    var precos = [];
    if (a.valorAluguel) precos.push("Aluguel " + reais(a.valorAluguel));
    if (a.valorVenda) precos.push("Venda " + reais(a.valorVenda));
    if (fin === "venda") precos.reverse();
    return { codigo: String(a.codigo), tipo: a.tipo, valor: precos.join(" · "), condominio: a.titulo,
             bairro: a.bairro, quartos: a.quartos, fotos: a.fotos, capa: a.capa, mobilia: a.mobilia };
  }
  function avisoFaixa(txt) { $("dp-aviso-faixa").hidden = !txt; $("dp-aviso-faixa").textContent = txt || ""; }

  $("dp-buscar").addEventListener("click", function () {
    var p = new URLSearchParams();
    [["finalidade", "f-fin"], ["vmin", "f-vmin"], ["vmax", "f-vmax"]].forEach(function (par) {
      var v = $(par[1]).value.trim();
      if (v) p.set(par[0], v);
    });
    msBairros.valores().forEach(function (v) { p.append("bairro", v); });
    msTipos.valores().forEach(function (v) { p.append("tipo", v); });
    ligados("data-mob").forEach(function (v) { p.append("mobilia", v); });
    ligados("data-qt").forEach(function (v) { p.append("quartos", v); });
    var fin = $("f-fin").value;
    limparResposta(); avisoFaixa("procurando…");
    $("dp-buscar").disabled = true;
    fetch("api/disparo/buscar?" + p.toString(), { credentials: "same-origin", cache: "no-store" })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (x) {
        if (!x.ok) throw new Error(x.j.erro || "não consegui procurar");
        if (Number(x.j.teto) > 0) teto = Number(x.j.teto);
        achados = (x.j.itens || []).map(function (a) { return doAchado(a, fin); });
        // MARCA SOZINHO os primeiros (do mais barato), até o teto por envio
        escolhidos = achados.slice(0, teto);
        avisoFaixa(!achados.length ? "Nenhum imóvel nosso disponível nessa faixa. Afrouxe um filtro."
          : achados.length > teto ? "Achei " + achados.length + "; marquei os " + teto + " mais baratos (é o máximo por envio). Troque à vontade."
          : "Achei " + achados.length + " e marquei todos. Confira e desmarque o que não quiser.");
      })
      .catch(function (e) { achados = []; escolhidos = []; avisoFaixa(e.message || "não consegui procurar"); })
      .then(function () { $("dp-buscar").disabled = false; pintarAchados(); atualizar(); });
  });
  $("dp-achados").addEventListener("click", function (e) {
    var m = e.target.closest("[data-marcar]");
    if (m) {
      limparResposta();
      escolhidos = m.dataset.marcar === "primeiros" ? achados.slice(0, teto) : [];
      pintarAchados(); atualizar();
      return;
    }
    var b = e.target.closest(".dp-item");
    if (!b) return;
    alternar(achados[Number(b.dataset.a)]);
    pintarAchados();
  });

  /* ---- os dois modos ---- */
  document.querySelectorAll("[data-modo]").forEach(function (b) {
    b.addEventListener("click", function () {
      if (b.dataset.modo === modo) return;
      modo = b.dataset.modo;
      document.querySelectorAll("[data-modo]").forEach(function (x) {
        x.setAttribute("aria-selected", x.dataset.modo === modo ? "true" : "false");
      });
      $("dp-modo-um").hidden = modo !== "um";
      $("dp-modo-faixa").hidden = modo !== "faixa";
      escolhidos = []; resultados = []; achados = null; $("dp-q").value = "";
      limparResposta(); avisoFaixa(""); pintarLista(); pintarAchados(); atualizar();
    });
  });

  /* ---- os escolhidos ---- */
  function alternar(i) {
    if (!i) return;
    limparResposta();
    if (marcado(i.codigo)) {
      escolhidos = escolhidos.filter(function (e) { return e.codigo !== i.codigo; });
    } else if (escolhidos.length >= teto) {
      mostrar(false, "No máximo " + teto + " imóveis por envio. Desmarque um para marcar outro.");
    } else {
      escolhidos = escolhidos.concat([i]);
    }
    atualizar();
  }
  $("dp-escolhidos").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-cod]");
    if (!b) return;
    var cod = b.dataset.cod;
    alternar(escolhidos.filter(function (x) { return x.codigo === cod; })[0]);
    pintarLista();
  });

  function atualizar() {
    $("dp-escolhidos").innerHTML = modo !== "um" ? "" : escolhidos.map(function (i) {
      return '<span class="dp-chip">#' + esc(i.codigo) + " " + esc(i.condominio || i.tipo || "") +
             '<button type="button" data-cod="' + esc(i.codigo) + '" aria-label="tirar">×</button></span>';
    }).join("");
    var d = digitos();
    var pode = d.length >= 10 && escolhidos.length > 0 && !!$("dp-linha").value && !enviando;
    var b = $("dp-enviar");
    b.disabled = !pode;
    b.textContent = enviando ? "enviando…"
      : escolhidos.length
        ? "Enviar " + escolhidos.length + (escolhidos.length === 1 ? " imóvel" : " imóveis") +
          (d.length >= 10 ? " para " + formatar($("dp-telefone").value) : "")
        : "Enviar";
  }
  $("dp-telefone").addEventListener("input", function () { limparResposta(); atualizar(); });
  $("dp-telefone").addEventListener("blur", function () { this.value = formatar(this.value); atualizar(); });

  /* ---- a resposta ---- */
  function limparResposta() { $("dp-resposta").hidden = true; }
  function mostrar(ok, texto, canal) {
    var r = $("dp-resposta");
    r.hidden = false;
    r.className = "dp-resposta " + (ok ? "dp-resposta--ok" : "dp-resposta--erro");
    r.innerHTML = esc(texto) + (ok && canal === "parceria"
      ? "<small>Sai pela fila da Nay em alguns segundos, uma foto de cada vez (entre 6h e 22h; fora disso, às 6h).</small>"
      : "");
  }

  /* ---- enviar ---- */
  $("dp-enviar").addEventListener("click", function () {
    if ($("dp-enviar").disabled) return;
    enviando = true; limparResposta(); atualizar();
    fetch("api/disparo", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        telefone: $("dp-telefone").value,
        integrationId: $("dp-linha").value,
        codigos: escolhidos.map(function (e) { return Number(e.codigo); })
      })
    })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (x) {
        if (!x.ok) throw new Error(x.j.erro || "não consegui enviar");
        mostrar(true, x.j.resumo || "Enviado.", x.j.canal);
        escolhidos = []; resultados = []; achados = null; $("dp-q").value = "";
        avisoFaixa(""); pintarLista(); pintarAchados();
      })
      .catch(function (e) { mostrar(false, e.message || "não consegui enviar"); })
      .then(function () { enviando = false; atualizar(); });
  });
})();
