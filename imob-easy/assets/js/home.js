/* ==========================================================================
   Imob Easy — Home (13/10/2026): menu do celular, contadores, 6 destaques, o mapa dos imóveis, o comparativo da
   comissão e o mapa da expansão. Tudo que vem da API falha em silêncio: a página fica inteira sem ela.

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
    { nome: "Fortaleza", uf: "CE", lat: -3.732, lon: -38.527 },
    { nome: "Recife", uf: "PE", lat: -8.048, lon: -34.877 },
    { nome: "Salvador", uf: "BA", lat: -12.972, lon: -38.501 },
    { nome: "Brasília", uf: "DF", lat: -15.794, lon: -47.883 },
    { nome: "Goiânia", uf: "GO", lat: -16.687, lon: -49.265 },
    { nome: "Belo Horizonte", uf: "MG", lat: -19.917, lon: -43.935 },
    { nome: "Rio de Janeiro", uf: "RJ", lat: -22.907, lon: -43.173 },
    { nome: "São Paulo", uf: "SP", lat: -23.551, lon: -46.633 },
    { nome: "Curitiba", uf: "PR", lat: -25.429, lon: -49.267 },
    { nome: "Porto Alegre", uf: "RS", lat: -30.035, lon: -51.218 }
  ];

  function $(id) { return document.getElementById(id); }
  function esc(t) { return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function reais(v) { return "R$ " + Math.round(v).toLocaleString("pt-BR"); }
  function curto(v) {
    if (v >= 1e6) return "R$ " + (v / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) + " mi";
    if (v >= 1e3) return "R$ " + Math.round(v / 1e3) + " mil";
    return reais(v);
  }
  function buscar(caminho) {
    if (!API) return Promise.resolve(null);
    return fetch(API + caminho).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }

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

  /* ---- os números do hero e o mapa dos imóveis: a mesma leitura ---- */
  var imoveisDoMapa = [];
  buscar("/api/imoveis-para-enviar").then(function (d) {
    var lista = (d && d.imoveis) || [];
    imoveisDoMapa = lista.filter(function (m) { return (m.venda > 0 || m.aluguel > 0); });
    var bairros = {}, condos = {};
    imoveisDoMapa.forEach(function (m) { if (m.bairro) bairros[m.bairro] = 1; if (m.condominio) condos[m.condominio] = 1; });
    numero("imoveis", imoveisDoMapa.length);
    numero("bairros", Object.keys(bairros).length);
    numero("condominios", Object.keys(condos).length);
    mapaDosImoveis();
  });

  function numero(chave, valor) {
    var el = document.querySelector('[data-numero="' + chave + '"]');
    if (!el || !valor) return;
    var inicio = null, de = 0;
    function passo(t) {
      if (!inicio) inicio = t;
      var p = Math.min(1, (t - inicio) / 900);
      el.textContent = Math.round(de + (valor - de) * (1 - Math.pow(1 - p, 3))).toLocaleString("pt-BR");
      if (p < 1) requestAnimationFrame(passo);
    }
    requestAnimationFrame(passo);
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

  /* ---- o mapa dos imóveis (o mesmo desenho do /imoveis, mais leve) ---- */
  function mapaDosImoveis() {
    var alvo = $("mapa-imoveis");
    if (!alvo || !window.L) return;
    var toque = window.matchMedia("(pointer: coarse)").matches;
    var mapa = L.map(alvo, { scrollWheelZoom: false, zoomControl: true, dragging: !toque || true, tap: false }).setView([-3.08, -60.02], 12);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, subdomains: "abc", attribution: "&copy; OpenStreetMap" }).addTo(mapa);
    mapa.attributionControl.setPrefix(false);
    var pontos = imoveisDoMapa.filter(function (m) { return m.lat != null && m.lon != null; });
    if (!pontos.length) return;
    var grupo = L.featureGroup();
    pontos.forEach(function (m) {
      var aluguel = !(m.venda > 0) && m.aluguel > 0;
      var preco = aluguel ? curto(m.aluguel) + "/mês" : curto(m.venda);
      var html = '<button type="button" class="pino' + (aluguel ? " pino--aluguel" : "") + '" aria-label="' + esc(m.titulo || "imóvel") + '">' + esc(preco) + "</button>";
      var marcador = L.marker([m.lat, m.lon], { icon: L.divIcon({ className: "pino-caixa", iconSize: null, html: html }) });
      marcador.bindPopup(
        '<div class="pino-balao">' + (m.foto ? '<img src="' + esc(m.foto) + '" alt="" loading="lazy">' : "") +
        "<b>" + esc(m.titulo || m.condominio || "Imóvel") + "</b>" +
        "<small>" + esc([m.condominio, m.bairro].filter(Boolean).join(" · ")) + (m.quartos ? " · " + m.quartos + " quartos" : "") + "</small>" +
        '<a class="btn-roxo" href="/imovel/' + encodeURIComponent(m.codigo) + '">Ver imóvel · ' + esc(preco) + "</a></div>",
        { maxWidth: 240, closeButton: true });
      grupo.addLayer(marcador);
    });
    grupo.addTo(mapa);
    mapa.fitBounds(grupo.getBounds(), { padding: [30, 30], maxZoom: 13 });
  }

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

  /* ---- a expansão ---- */
  var listaCidades = $("expansao-lista");
  if (listaCidades) {
    listaCidades.innerHTML = CIDADES.map(function (c) {
      return '<li class="expansao__cidade' + (c.online ? " expansao__cidade--online" : "") + '"><div><b>' + esc(c.nome) + "</b><small>" + esc(c.uf) + "</small></div>" +
        '<span class="expansao__status ' + (c.online ? "expansao__status--online" : "expansao__status--obras") + '">' + (c.online ? "No ar" : "Em construção") + "</span></li>";
    }).join("");
  }
  var alvoExp = $("mapa-expansao");
  if (alvoExp && window.L) {
    var mapaExp = L.map(alvoExp, { scrollWheelZoom: false, zoomControl: true, dragging: true, tap: false, minZoom: 3, maxZoom: 7 }).setView([-14.5, -52], 4);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, subdomains: "abc", attribution: "&copy; OpenStreetMap" }).addTo(mapaExp);
    mapaExp.attributionControl.setPrefix(false);
    CIDADES.forEach(function (c) {
      var m = L.marker([c.lat, c.lon], {
        icon: L.divIcon({ className: "ponto-cidade", iconSize: null, html: '<span class="ponto ' + (c.online ? "ponto--online" : "ponto--obras") + '"></span>' })
      }).addTo(mapaExp);
      // o rótulo das capitais do litoral leste fica para a esquerda: para a direita sai da tela no celular
      var lado = c.lon > -45 ? "left" : "right";
      m.bindTooltip(c.nome + (c.online ? " · no ar" : ""), { permanent: true, direction: lado, offset: [lado === "right" ? 10 : -10, 0], className: "rotulo-cidade" + (c.online ? " rotulo-cidade--online" : "") });
    });
    // o mapa nasce escondido em cima do celular (abaixo da dobra): recalcula o tamanho quando aparece
    setTimeout(function () { mapaExp.invalidateSize(); }, 400);
  }
})();
