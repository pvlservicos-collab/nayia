/* ==========================================================================
   Imob Easy — Home (13/10/2026): as abas do cartão da primeira dobra (buscar / anunciar; alugar / comprar), o menu
   do celular, os números do catálogo, os 6 destaques, o comparativo da comissão e o mapa da expansão (o Brasil
   recortado, sem mapa do mundo: a malha das UFs do IBGE em assets/dados/brasil-uf.json). O mapa dos imóveis é a
   própria página /imoveis, embutida. Tudo que vem da API falha em silêncio: a página fica inteira sem ela.

   O COMPARATIVO DA COMISSÃO é editável aqui embaixo (COMPARATIVO): o número da Imob Easy é 50%; os outros dois são
   a prática usual do mercado e devem ser conferidos pelo Tel/Pedro antes de mudar.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";

  /* ---- o comparativo (edite aqui) ---- */
  var COMPARATIVO = [
    { chave: "easy", nome: "Imob Easy", valor: "50%", barra: 50, obs: "Metade da comissão para o corretor parceiro, em venda e locação." },
    { chave: "tradicional", nome: "Imobiliárias tradicionais", valor: "até 40%", barra: 40, obs: "Em geral entre 30% e 40% para quem fecha." },
    { chave: "azul", nome: "Plataforma azul", valor: "menos", barra: 25, obs: "Paga ao corretor uma parte menor do que a nossa." }
  ];

  /* ---- a expansão (edite aqui): a primeira é a que está no ar ---- */
  var CIDADES = [
    { nome: "Manaus", uf: "AM", lat: -3.119, lon: -60.021, online: true },
    { nome: "Belém", uf: "PA", lat: -1.456, lon: -48.504 },
    { nome: "Boa Vista", uf: "RR", lat: 2.82, lon: -60.672 },
    { nome: "Porto Velho", uf: "RO", lat: -8.762, lon: -63.904 },
    { nome: "Fortaleza", uf: "CE", lat: -3.732, lon: -38.527, rotulo: "top" },
    { nome: "Recife", uf: "PE", lat: -8.048, lon: -34.877 },
    { nome: "Salvador", uf: "BA", lat: -12.972, lon: -38.501, rotulo: "top" },
    { nome: "Brasília", uf: "DF", lat: -15.794, lon: -47.883, rotulo: "right" },
    { nome: "Goiânia", uf: "GO", lat: -16.687, lon: -49.265, rotulo: "left" },
    { nome: "Belo Horizonte", uf: "MG", lat: -19.917, lon: -43.935, rotulo: "left" },
    { nome: "Rio de Janeiro", uf: "RJ", lat: -22.907, lon: -43.173, rotulo: "top" },
    { nome: "São Paulo", uf: "SP", lat: -23.551, lon: -46.633, rotulo: "bottom" },
    { nome: "Curitiba", uf: "PR", lat: -25.429, lon: -49.267, rotulo: "left" },
    { nome: "Porto Alegre", uf: "RS", lat: -30.035, lon: -51.218 }
  ];

  function $(id) { return document.getElementById(id); }
  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function buscar(caminho, absoluto) {
    var url = absoluto ? caminho : API + caminho;
    if (!absoluto && !API) return Promise.resolve(null);
    return fetch(url).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }

  /* ---- o cartão da primeira dobra: buscar / anunciar, alugar / comprar ---- */
  var abas = document.querySelectorAll(".hero__aba"), paineis = document.querySelectorAll(".hero__painel");
  abas.forEach(function (aba) {
    aba.addEventListener("click", function () {
      abas.forEach(function (a) { a.setAttribute("aria-selected", a === aba ? "true" : "false"); });
      paineis.forEach(function (p) { p.hidden = p.dataset.painel !== aba.dataset.painel; });
    });
  });
  var form = document.querySelector("form.hero__form"), botao = document.querySelector(".hero__botao[href]");
  document.querySelectorAll(".hero__neg-aba").forEach(function (aba) {
    aba.addEventListener("click", function () {
      document.querySelectorAll(".hero__neg-aba").forEach(function (a) { a.setAttribute("aria-selected", a === aba ? "true" : "false"); });
      // busca-filtros.js monta o endereço a partir do action do formulário: trocar a aba troca o destino
      if (form) form.setAttribute("action", aba.dataset.neg);
      if (botao) botao.setAttribute("href", aba.dataset.neg);
    });
  });

  /* ---- menu do celular ---- */
  var botaoMenu = document.querySelector(".topo__menu"), nav = $("nav-principal");
  if (botaoMenu && nav) {
    botaoMenu.addEventListener("click", function () {
      var aberto = nav.classList.toggle("aberto");
      botaoMenu.setAttribute("aria-expanded", aberto ? "true" : "false");
      botaoMenu.setAttribute("aria-label", aberto ? "Fechar o menu" : "Abrir o menu");
    });
    nav.addEventListener("click", function (e) {
      if (e.target.closest("a")) { nav.classList.remove("aberto"); botaoMenu.setAttribute("aria-expanded", "false"); }
    });
  }

  /* ---- os números do catálogo ---- */
  buscar("/api/imoveis-para-enviar").then(function (d) {
    var lista = ((d && d.imoveis) || []).filter(function (m) { return m.venda > 0 || m.aluguel > 0; });
    if (!lista.length) return;
    var bairros = {}, condos = {};
    lista.forEach(function (m) { if (m.bairro) bairros[m.bairro] = 1; if (m.condominio) condos[m.condominio] = 1; });
    numero("imoveis", lista.length);
    numero("bairros", Object.keys(bairros).length);
    numero("condominios", Object.keys(condos).length);
  });

  function numero(chave, valor) {
    document.querySelectorAll('[data-numero="' + chave + '"]').forEach(function (el) {
      var inicio = null;
      function passo(t) {
        if (!inicio) inicio = t;
        var p = Math.min(1, (t - inicio) / 900);
        el.textContent = Math.round(valor * (1 - Math.pow(1 - p, 3))).toLocaleString("pt-BR");
        if (p < 1) requestAnimationFrame(passo);
      }
      requestAnimationFrame(passo);
    });
  }

  /* ---- 6 destaques: 3 para comprar e 3 para alugar, os com mais fotos ---- */
  var jaAjustei = false;
  document.addEventListener("dados-site-atualizados", function () {
    if (jaAjustei) return;
    var D = window.DADOS_SITE || {};
    function top(lista, n) {
      return (lista || []).filter(function (x) { return x.codigo && x.foto; })
        .sort(function (a, b) { return (b.pontos || 0) - (a.pontos || 0); }).slice(0, n);
    }
    var escolhidos = top(D.comprar, 3).concat(top(D.alugar, 3));
    if (escolhidos.length < 6) escolhidos = escolhidos.concat(top(D.comprar, 9).slice(3, 3 + (6 - escolhidos.length)));
    if (!escolhidos.length) return;
    jaAjustei = true;
    D.destaques = escolhidos;
    document.dispatchEvent(new CustomEvent("dados-site-atualizados"));
  });

  /* ---- o comparativo da comissão ---- */
  var lista = $("comparativo");
  if (lista) {
    lista.innerHTML = COMPARATIVO.map(function (c) {
      return '<li class="comparativo__item comparativo__item--' + c.chave + '">' +
        '<span class="comparativo__nome"><i></i>' + esc(c.nome) + "</span>" +
        '<span class="comparativo__valor">' + esc(c.valor) + "</span>" +
        '<span class="comparativo__barra"><i data-largura="' + c.barra + '"></i></span>' +
        '<span class="comparativo__obs">' + esc(c.obs) + "</span></li>";
    }).join("");
    var animar = function () { lista.querySelectorAll("[data-largura]").forEach(function (b) { b.style.width = b.dataset.largura + "%"; }); };
    if ("IntersectionObserver" in window) {
      var obs = new IntersectionObserver(function (es) { if (es.some(function (e) { return e.isIntersecting; })) { animar(); obs.disconnect(); } }, { threshold: .3 });
      obs.observe(lista);
      setTimeout(animar, 2500);      // garantia: a barra enche mesmo se o observador não disparar
    } else animar();
  }

  /* ---- a expansão: só o Brasil, recortado, em fundo sólido ---- */
  var listaCidades = $("expansao-lista");
  if (listaCidades) {
    listaCidades.innerHTML = CIDADES.map(function (c) {
      return '<li class="expansao__cidade' + (c.online ? " expansao__cidade--online" : "") + '"><i></i><b>' + esc(c.nome) + "</b><small>" + esc(c.uf) + "</small>" +
        (c.online ? "<em>No ar</em>" : "") + "</li>";
    }).join("");
  }
  var alvoExp = $("mapa-expansao");
  if (alvoExp && window.L) {
    var mapaExp = L.map(alvoExp, {
      zoomControl: false, dragging: false, scrollWheelZoom: false, doubleClickZoom: false, touchZoom: false,
      boxZoom: false, keyboard: false, tap: false, attributionControl: false, zoomSnap: 0.1
    });
    buscar("assets/dados/brasil-uf.json", true).then(function (geo) {
      if (!geo) return;
      var brasil = L.geoJSON(geo, {
        style: function () { return { color: "#8b5cf6", weight: 1, opacity: .9, fillColor: "#ffffff", fillOpacity: .13 }; },
        interactive: false
      }).addTo(mapaExp);
      var encaixar = function () { mapaExp.invalidateSize(); mapaExp.fitBounds(brasil.getBounds(), { padding: [18, 18] }); };
      encaixar();
      CIDADES.forEach(function (c) {
        var m = L.marker([c.lat, c.lon], { interactive: false,
          icon: L.divIcon({ className: "ponto-cidade", iconSize: null, html: '<span class="ponto' + (c.online ? " ponto--online" : "") + '"></span>' }) }).addTo(mapaExp);
        // o rótulo das capitais do litoral leste fica para a esquerda: para a direita sai do desenho
        var lado = c.rotulo || (c.lon > -45 ? "left" : "right");
        var desloca = { right: [10, 0], left: [-10, 0], top: [0, -10], bottom: [0, 10] }[lado];
        m.bindTooltip(c.nome + (c.online ? " · no ar" : ""), { permanent: true, direction: lado, offset: desloca,
          className: "rotulo-cidade" + (c.online ? " rotulo-cidade--online" : "") });
      });
      window.addEventListener("resize", encaixar);
      setTimeout(encaixar, 600);
    });
  }
})();
