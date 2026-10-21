/* USO DE RECURSOS da VPS (aba Início). Pedro, 20/10/2026: "um painel Uso de recursos, que separa todos os recursos da
   vps por função em porcentagem de uso da minha vps atual da hostinger".
   Lê admin/dados/recursos.json, escrito a cada 5 min por nay-agentes/medir_recursos.py na VPS1: CPU e memória por
   função (agora = últimos 5 min; média das últimas 24 h) e o disco por função (medido de hora em hora).
   Cada lista fecha 100% da VPS: as funções, "Sistema" (o que não é de nenhuma) e o que está livre. */
(function () {
  "use strict";
  var raiz = document.getElementById("uso-recursos");
  if (!raiz) return;
  var dados = null, quando = "agora", serie = "cpu", grafico = null;

  function pct(v) {
    if (v == null) return "–";
    if (v > 0 && v < 0.1) return "<0,1%";
    return v.toLocaleString("pt-BR", { maximumFractionDigits: v < 10 ? 1 : 0 }) + "%";
  }
  function gb(b) {
    if (b == null) return "";
    var g = b / 1073741824;
    return g >= 1 ? g.toLocaleString("pt-BR", { maximumFractionDigits: g < 10 ? 1 : 0 }) + " GB"
                  : Math.round(b / 1048576).toLocaleString("pt-BR") + " MB";
  }
  function horaManaus(seg) {
    return new Date(seg * 1000).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Manaus" });
  }
  function el(tag, attrs, filhos) {
    var e = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "texto") e.textContent = attrs[k];
      else if (k === "estilo") e.setAttribute("style", attrs[k]);
      else e.setAttribute(k, attrs[k]);
    });
    (filhos || []).forEach(function (f) { if (f) e.appendChild(f); });
    return e;
  }

  /* as linhas de um recurso: funções com valor, Sistema e Livre, da maior para a menor */
  function linhas(recurso) {
    var valores, total, bytes = {};
    if (recurso === "disco") {
      var d = dados.disco || {};
      valores = d.pct || {};
      bytes = d.bytes || {};
      total = d.total ? d.usado * 100 / d.total : null;
    } else {
      var fonte = quando === "media" ? (dados.media24h || {})[recurso] : (dados.agora || {})[recurso];
      if (!fonte) return null;
      valores = fonte;
      total = fonte._total;
      if (recurso === "mem" && quando === "agora") bytes = (dados.agora || {}).mem_bytes || {};
    }
    var lista = dados.funcoes.filter(function (f) { return recurso === "disco" || !f.so_disco; }).map(function (f) {
      return { f: f, v: valores[f.id] || 0, b: bytes[f.id] };
    }).filter(function (x) { return x.v > 0 || x.f.id === "sistema"; });
    lista.sort(function (a, b) { return b.v - a.v; });
    return { total: total, lista: lista, livre: total == null ? null : Math.max(0, 100 - total) };
  }

  function desenharCartao(cartao) {
    var recurso = cartao.getAttribute("data-recurso");
    var r = linhas(recurso);
    var total = cartao.querySelector("[data-total]"), barra = cartao.querySelector("[data-barra]"), lista = cartao.querySelector("[data-lista]");
    barra.innerHTML = ""; lista.innerHTML = "";
    if (!r) { total.textContent = "–"; lista.appendChild(el("li", {}, [el("span", { texto: "A primeira medida sai nos próximos 5 minutos." })])); return; }
    total.textContent = pct(r.total);
    r.lista.forEach(function (x) {
      if (x.v >= 0.2) barra.appendChild(el("i", { estilo: "--cor:" + x.f.cor + ";width:" + x.v + "%", title: x.f.nome + " · " + pct(x.v) }));
      var dica = x.f.faz + (x.f.itens && x.f.itens.length ? " (" + x.f.itens.join(", ") + ")" : "");
      lista.appendChild(el("li", { title: dica, class: x.v < 0.1 ? "ur-pouco" : "", estilo: "--cor:" + x.f.cor + ";--w:" + Math.min(100, x.v) + "%" }, [
        el("i"), el("span", { texto: x.f.nome }),
        el("b", { texto: pct(x.v) }, x.b ? [el("small", { texto: gb(x.b) })] : []),
        el("em")
      ]));
    });
    if (r.livre != null) {
      barra.appendChild(el("i", { class: "ur-livre", estilo: "width:" + r.livre + "%", title: "Livre · " + pct(r.livre) }));
      var livreB = recurso === "disco" ? (dados.disco || {}).livre : null;
      lista.appendChild(el("li", { class: "ur-livre", estilo: "--cor:transparent;--w:0%" }, [
        el("i"), el("span", { texto: "Livre" }), el("b", { texto: pct(r.livre) }, livreB ? [el("small", { texto: gb(livreB) })] : [])
      ]));
    }
    if (recurso === "disco") {
      var nota = cartao.querySelector("[data-nota]"), liberavel = (dados.disco || {}).liberavel_cache;
      var cache = ((dados.disco || {}).bytes || {}).docker_cache;
      nota.hidden = !(liberavel > 1073741824);
      if (!nota.hidden) nota.textContent = "O cache de build do Docker ocupa " + gb(cache) + "; " + gb(liberavel) +
        " disso o próprio Docker diz que dá para liberar (medido às " + horaManaus(dados.disco.medido_em) + ").";
    }
  }

  function desenharGrafico() {
    var canvas = document.getElementById("ur-grafico"), vazio = document.getElementById("ur-grafico-vazio");
    var hist = dados.historia || [];
    vazio.hidden = hist.length >= 2;
    if (typeof Chart === "undefined") return;
    var funcoes = dados.funcoes.filter(function (f) { return !f.so_disco; });
    var conjuntos = funcoes.map(function (f) {
      return {
        label: f.nome, data: hist.map(function (h) { return (h[serie] || {})[f.id] || 0; }),
        borderColor: f.cor, backgroundColor: f.cor + "b3", fill: true, pointRadius: 0, borderWidth: 1, tension: 0.25, stack: "s"
      };
    }).filter(function (c) { return c.data.some(function (v) { return v >= 0.05; }); });
    var rotulos = hist.map(function (h) { return horaManaus(h.t); });
    if (grafico) grafico.destroy();
    grafico = new Chart(canvas, {
      type: "line",
      data: { labels: rotulos, datasets: conjuntos },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false, interaction: { mode: "index", intersect: false },
        scales: {
          x: { ticks: { color: "#8e8ea0", maxTicksLimit: 12, autoSkip: true }, grid: { color: "rgba(204,204,220,.06)" } },
          y: { stacked: true, min: 0, suggestedMax: serie === "cpu" ? 60 : 100, ticks: { color: "#8e8ea0", callback: function (v) { return v + "%"; } }, grid: { color: "rgba(204,204,220,.08)" } }
        },
        plugins: {
          legend: { position: "bottom", labels: { color: "#ccccdc", boxWidth: 10, boxHeight: 10, font: { size: 11 } } },
          tooltip: {
            itemSort: function (a, b) { return b.raw - a.raw; },
            callbacks: { label: function (c) { return " " + c.dataset.label + ": " + pct(c.raw); } }
          }
        }
      }
    });
  }

  function desenhar() {
    var s = dados.servidor || {};
    document.getElementById("ur-servidor").textContent = [
      s.nome, s.provedor, s.cpus + " núcleos", gb(s.memoria) + " de memória", gb(s.disco) + " de disco",
      "medido às " + horaManaus(dados.medido_em) + " (Manaus)"
    ].filter(Boolean).join(" · ");
    raiz.querySelector('[data-recurso="mem"] [data-cap]').textContent = gb(s.memoria);
    raiz.querySelector('[data-recurso="disco"] [data-cap]').textContent = gb(s.disco) + " · de hora em hora";
    var aviso = document.getElementById("ur-aviso");
    var atraso = Date.now() / 1000 - dados.medido_em;
    aviso.hidden = atraso < 20 * 60;
    if (!aviso.hidden) aviso.textContent = "A última medida é de " + horaManaus(dados.medido_em) + ": o medidor da VPS pode estar parado.";
    if (quando === "media" && !(dados.media24h || {}).cpu) {
      aviso.hidden = false;
      aviso.textContent = "A média de 24 h ainda está se formando: ela junta as medidas que já existem.";
    }
    raiz.querySelectorAll(".ur-cartao").forEach(desenharCartao);
    desenharGrafico();
  }

  function carregar() {
    fetch("dados/recursos.json?t=" + Date.now(), { cache: "no-store" }).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.json();
    }).then(function (d) { dados = d; desenhar(); }).catch(function () {
      document.getElementById("ur-servidor").textContent = "a medição ainda não chegou";
      var aviso = document.getElementById("ur-aviso");
      aviso.hidden = false;
      aviso.textContent = "O medidor da VPS escreve admin/dados/recursos.json a cada 5 minutos; assim que a primeira medida sair, o painel aparece.";
    });
  }

  function seg(id, aoMudar) {
    var grupo = document.getElementById(id);
    grupo.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-v]");
      if (!b) return;
      grupo.querySelectorAll("button").forEach(function (x) { x.setAttribute("aria-pressed", x === b ? "true" : "false"); });
      aoMudar(b.getAttribute("data-v"));
      if (dados) desenhar();
    });
  }
  seg("ur-quando", function (v) { quando = v; });
  seg("ur-serie", function (v) { serie = v; });
  carregar();
  setInterval(function () { if (document.visibilityState === "visible") carregar(); }, 5 * 60 * 1000);
})();
