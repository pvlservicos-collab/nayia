/* Links orgânicos (559, 02/11/2026). Pedro: "organize todos os leads que possam vir de nossas redes sociais ou blogs em uma
   página ... variações de links de WhatsApp com UTM para o número 92 8595-6408 para eu saber de onde está vindo o lead
   baseado em uma mensagem automática também, ex.: Vim do blog, Vim do site".
   Lê e grava /admin/api/links-organicos (links_api.py); cada card tem o link com UTM (o curto, que conta o clique), o link
   direto do WhatsApp, a mensagem pronta, os cliques e os leads (7 dias, 30 dias e total) e os últimos leads. */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var links = [];
  var ETAPA = { nova: "nova", filtrar: "filtrando", feito_busca: "busca feita", imoveis_enviados: "imóveis enviados",
                visita: "visita", proprietarios: "visita (dono)", fechamento: "fechamento", finalizado: "finalizado" };

  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok && !j.erro) throw new Error("HTTP " + r.status);
        return j; }); });
  }
  function toast(msg, erro) { var t = $("lo-toast"); t.textContent = msg; t.classList.toggle("erro", !!erro); t.hidden = false; clearTimeout(t._t); t._t = setTimeout(function () { t.hidden = true; }, erro ? 5000 : 2000); }
  function data(iso) { var d = iso ? new Date(iso) : null; return d ? d.toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : ""; }
  function n(v) { return Number(v || 0).toLocaleString("pt-BR"); }
  function comMarca(l) {
    var i = l.mensagem.toLowerCase().indexOf(l.marca.toLowerCase());
    if (i < 0) return esc(l.mensagem);
    return esc(l.mensagem.slice(0, i)) + "<b>" + esc(l.mensagem.slice(i, i + l.marca.length)) + "</b>" + esc(l.mensagem.slice(i + l.marca.length));
  }

  function resumo() {
    var s = function (k) { return links.reduce(function (a, l) { return a + (l[k] || 0); }, 0); };
    var melhor = links.slice().sort(function (a, b) { return (b.leads_30d || 0) - (a.leads_30d || 0); })[0];
    $("lo-resumo").innerHTML = [
      [n(links.filter(function (l) { return l.ativo; }).length), "links ativos"],
      [n(s("cliques_30d")), "cliques em 30 dias"],
      [n(s("leads_30d")), "leads em 30 dias"],
      [n(s("leads")), "leads no total"],
      [melhor && melhor.leads_30d ? esc(melhor.canal) : "—", "canal com mais leads (30 dias)"]
    ].map(function (x) { return '<div class="lo-resumo__item"><div class="lo-resumo__n">' + x[0] + '</div><div class="lo-resumo__r">' + x[1] + "</div></div>"; }).join("");
  }

  function linha(rot, url, id) {
    return '<div class="lo-link"><span class="lo-link__rot">' + rot + '</span><input readonly value="' + esc(url) + '" aria-label="' + rot + '">' +
      '<button type="button" class="btn-neutro btn-mini" data-lo-copiar="' + id + '">Copiar</button></div>';
  }

  function card(l, i) {
    var ultimos = (l.ultimos || []).map(function (u) {
      return "<li>" + esc(data(u.em)) + " · " + (u.nome ? esc(u.nome) + " · " : "") + "…" + esc(u.final) + (u.etapa ? " · " + esc(ETAPA[u.etapa] || u.etapa) : "") + "</li>";
    }).join("");
    return '<article class="lo-card' + (l.ativo ? "" : " lo-card--desligado") + '">' +
      '<div class="lo-card__topo"><div><div class="lo-card__canal">' + esc(l.canal) + (l.ativo ? "" : " · desligado") + '</div>' +
        '<div class="lo-card__nome">' + esc(l.nome) + "</div></div>" +
        '<button type="button" class="btn-neutro btn-mini" data-lo-editar="' + i + '">Editar</button></div>' +
      '<div class="lo-card__msg">' + comMarca(l) + "</div>" +
      '<div class="lo-nums">' +
        '<div class="lo-num"><b>' + n(l.cliques_30d) + "</b><span>cliques 30d</span></div>" +
        '<div class="lo-num"><b>' + n(l.leads_7d) + "</b><span>leads 7d</span></div>" +
        '<div class="lo-num"><b>' + n(l.leads_30d) + "</b><span>leads 30d</span></div>" +
      "</div>" +
      linha("Link com UTM", l.link_curto, "c" + i) + linha("Direto WhatsApp", l.link_direto, "d" + i) +
      (ultimos ? '<details class="lo-leads"><summary>Últimos leads (' + n(l.leads) + " no total)</summary><ul>" + ultimos + "</ul></details>"
               : '<div class="lo-leads">Nenhum lead por este link ainda.</div>') +
      '<div class="lo-card__pe"><span>código <b>' + esc(l.codigo) + "</b> · utm " + esc(l.utm_source) + " / " + esc(l.utm_medium) + "</span>" +
        "<span>" + n(l.cliques) + " cliques no total</span></div>" +
    "</article>";
  }

  function desenhar() {
    resumo();
    $("lo-grade").innerHTML = links.length ? links.map(card).join("") : '<p class="lo-vazio">Nenhum link ainda.</p>';
  }

  function carregar() {
    pedir("api/links-organicos").then(function (j) {
      if (j.erro) throw new Error(j.erro);
      links = j.links || [];
      desenhar();
    }).catch(function (e) { $("lo-grade").innerHTML = '<p class="lo-vazio">Não consegui ler os links: ' + esc(e.message) + "</p>"; });
  }

  /* ---- criar e editar ---- */
  function abrirForm(l) {
    var f = $("lo-form");
    f.reset();
    $("lo-erro").hidden = true;
    $("lo-form-titulo").textContent = l ? "Editar link" : "Novo link";
    if (l) {
      ["codigo", "canal", "nome", "mensagem", "marca", "utm_source", "utm_medium", "utm_campaign"].forEach(function (k) { f.elements[k].value = l[k] || ""; });
      f.elements.ativo.checked = !!l.ativo;
    }
    f.elements.codigo.readOnly = !!l;
    f.hidden = false;
    f.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  $("lo-novo").addEventListener("click", function () { abrirForm(null); });
  $("lo-cancelar").addEventListener("click", function () { $("lo-form").hidden = true; });
  $("lo-form").addEventListener("submit", function (ev) {
    ev.preventDefault();
    var f = ev.target, corpo = {};
    ["codigo", "canal", "nome", "mensagem", "marca", "utm_source", "utm_medium", "utm_campaign"].forEach(function (k) { corpo[k] = f.elements[k].value.trim(); });
    corpo.ativo = f.elements.ativo.checked;
    pedir("api/links-organicos", { method: "POST", body: JSON.stringify(corpo) }).then(function (r) {
      if (!r.ok) { $("lo-erro").textContent = r.erro || "Não salvou."; $("lo-erro").hidden = false; return; }
      f.hidden = true;
      toast("Link salvo.");
      carregar();
    }).catch(function (e) { $("lo-erro").textContent = e.message; $("lo-erro").hidden = false; });
  });

  $("lo-grade").addEventListener("click", function (ev) {
    var b = ev.target.closest("button[data-lo-copiar], button[data-lo-editar]");
    if (!b || !$("lo-grade").contains(b)) return;
    if (b.hasAttribute("data-lo-editar")) { abrirForm(links[Number(b.getAttribute("data-lo-editar"))]); return; }
    var campo = b.parentNode.querySelector("input");
    var copiar = navigator.clipboard ? navigator.clipboard.writeText(campo.value) : Promise.reject();
    copiar.then(function () { toast("Copiado."); }).catch(function () { campo.select(); document.execCommand("copy"); toast("Copiado."); });
  });

  carregar();
})();
