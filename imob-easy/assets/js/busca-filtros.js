/* ==========================================================================
   Imob Easy — Filtros da busca (home, comprar e alugar)

   Pedido do Pedro (05/10/2026): "tipo de imóvel não dá para selecionar no
   site ... bairro só aparece o nome e não tem como selecionar. põe o de bairro
   igual lá na home". Os filtros de comprar/alugar eram só desenho: nada ia à
   API. Agora cada um vira parâmetro de /api/imoveis e a lista é a de verdade,
   com paginação. Na home, o PESQUISAR leva os mesmos filtros para a lista.

   O campo de bairro é o de busca-bairro.js (lista suspensa, filtra pelas
   iniciais); aqui cada bairro escolhido vira um marcador, e dá para ter vários.
   ========================================================================== */
(function () {
  "use strict";
  var API = window.API_BASE;
  if (!API) return;

  function escapar(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  // "500.000,00" -> "500000"; vazio continua vazio
  function numero(txt) { return String(txt || "").split(",")[0].replace(/\D/g, ""); }
  function pressionado(grupo) {
    var b = grupo && grupo.querySelector('[aria-pressed="true"]');
    return b ? b.textContent.trim() : "";
  }
  function pressionar(grupo, valor) {
    if (!grupo) return;
    grupo.querySelectorAll("[aria-pressed]").forEach(function (b) {
      b.setAttribute("aria-pressed", valor && b.textContent.trim() === valor ? "true" : "false");
    });
  }
  function carregarTipos(selecao, finalidade, atual) {
    if (!selecao) return;
    fetch(API + "/api/tipos")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (lista) {
        var opcoes = lista.filter(function (t) { return !finalidade || t[finalidade] > 0; });
        if (!opcoes.length) return;
        selecao.innerHTML = '<option value="">Todos</option>' + opcoes.map(function (t) {
          return '<option value="' + escapar(t.tipo) + '">' + escapar(t.tipo) + "</option>";
        }).join("");
        selecao.value = atual || "";
      })
      .catch(function () {});
  }

  /* ---------------- Home: o PESQUISAR leva os filtros para a lista ---------------- */
  var home = document.querySelector("form.painel-busca");
  if (home) {
    carregarTipos(home.querySelector("#tipo"), "", "");
    var botao = document.querySelector(".busca__enviar a"), codigo = document.getElementById("codigo");
    var ir = function (e) {
      e.preventDefault();
      // código preenchido: vai direto para a página do imóvel
      var cod = codigo ? codigo.value.replace(/\D/g, "") : "";
      if (cod) { window.location.href = "/imovel/" + cod; return; }
      var q = new URLSearchParams(), v;
      if ((v = home.querySelector("#bairro").value.trim())) q.append("bairros", v);
      if ((v = home.querySelector("#tipo").value) && v !== "Todos") q.set("tipo", v);
      if ((v = pressionado(home.querySelector('[aria-labelledby="rot-quartos"]')))) q.set("quartos", v);
      if ((v = pressionado(home.querySelector('[aria-labelledby="rot-garagem"]')))) q.set("garagem", v);
      if ((v = numero((home.querySelector('[aria-label="Valor mínimo"]') || {}).value))) q.set("valor_min", v);
      if ((v = numero((home.querySelector('[aria-label="Valor máximo"]') || {}).value))) q.set("valor_max", v);
      var s = q.toString();
      window.location.href = (home.getAttribute("action") || "comprar.html") + (s ? "?" + s : "");
    };
    home.addEventListener("submit", ir);
    if (botao) botao.addEventListener("click", ir);
    if (codigo) codigo.addEventListener("keydown", function (e) { if (e.key === "Enter") ir(e); });
    return;
  }

  /* ---------------- Comprar / Alugar ---------------- */
  var form = document.querySelector("form.filtros"), alvo = document.querySelector("[data-lista]");
  if (!form || !alvo) return;

  var POR = 24, pagina = 1, pedido = 0, bairros = [];
  var finalidade = alvo.dataset.lista === "alugar" ? "aluguel" : "venda";
  var campo = {
    bairro: form.querySelector("#bairro"), marcadores: form.querySelector("#f-bairros"),
    condominio: form.querySelector("#f-condominio"), tipo: form.querySelector("#f-tipo"),
    vmin: form.querySelector("#f-vmin"), vmax: form.querySelector("#f-vmax"),
    quartos: form.querySelector('[aria-labelledby="rot-f-quartos"]'),
    garagem: form.querySelector('[aria-labelledby="rot-f-garagem"]'),
    banheiros: form.querySelector("#f-banheiros")
  };
  var contagem = document.getElementById("res-contagem"), nav = document.querySelector("nav.paginacao");

  function filtros() {
    var q = new URLSearchParams(), v;
    bairros.forEach(function (b) { q.append("bairros", b); });
    if ((v = campo.condominio.value.trim())) q.set("condominio", v);
    if ((v = pressionado(campo.tipo))) q.set("tipo", v);
    if ((v = pressionado(campo.quartos))) q.set("quartos", v);
    if ((v = pressionado(campo.garagem))) q.set("garagem", v);
    if ((v = numero(campo.banheiros.value))) q.set("banheiros", v);
    if ((v = numero(campo.vmin.value))) q.set("valor_min", v);
    if ((v = numero(campo.vmax.value))) q.set("valor_max", v);
    return q;
  }

  function pintarMarcadores() {
    campo.marcadores.style.display = bairros.length ? "" : "none";   // [hidden] perde para o display:flex da caixa
    campo.marcadores.innerHTML = bairros.map(function (b, i) {
      return '<span class="marcador">' + escapar(b) + '<button type="button" data-tirar="' + i +
        '" aria-label="Remover filtro ' + escapar(b) + '">&times;</button></span>';
    }).join("");
  }
  function somarBairro(nome) {
    nome = String(nome || "").trim();
    campo.bairro.value = "";
    if (!nome) return false;
    var ja = bairros.some(function (b) { return b.toLowerCase() === nome.toLowerCase(); });
    if (!ja) bairros.push(nome);
    pintarMarcadores();
    return !ja;
  }

  function pintarPaginas(total) {
    var paginas = Math.max(1, Math.ceil(total / POR)), html = "";
    function item(n, rotulo, aria) {
      return n === pagina && !aria
        ? '<span class="ativo" aria-current="page">' + n + "</span>"
        : '<a href="#" data-p="' + n + '"' + (aria ? ' aria-label="' + aria + '"' : "") + ">" + rotulo + "</a>";
    }
    if (paginas > 1) {
      if (pagina > 1) html += item(pagina - 1, "&laquo;", "Página anterior");
      for (var n = 1; n <= paginas; n++) {
        if (n === 1 || n === paginas || Math.abs(n - pagina) <= 2) html += item(n, n);
        else if (Math.abs(n - pagina) === 3) html += '<span class="reticencias">…</span>';
      }
      if (pagina < paginas) html += item(pagina + 1, "&raquo;", "Próxima página");
    }
    nav.innerHTML = html;
    nav.hidden = paginas < 2;
  }

  function mostrar(itens) {
    window.DADOS_SITE = window.DADOS_SITE || {};
    window.DADOS_SITE[alvo.dataset.lista] = itens;
    document.dispatchEvent(new CustomEvent("dados-site-atualizados"));   // site.js desenha os cartões
  }

  function buscar() {
    var meu = ++pedido, q = filtros();
    var s = q.toString();
    try { window.history.replaceState(null, "", window.location.pathname + (s ? "?" + s : "")); } catch (e) { /* segue */ }
    q.set("finalidade", finalidade);
    q.set("pagina", pagina);
    q.set("por", POR);
    contagem.textContent = "Buscando…";
    fetch(API + "/api/imoveis?" + q.toString())
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        if (meu !== pedido) return;
        mostrar(d.itens);
        contagem.textContent = d.total === 1 ? "1 imóvel encontrado" : d.total.toLocaleString("pt-BR") + " imóveis encontrados";
        if (!d.itens.length) alvo.innerHTML = '<p class="resultados__vazio">Nenhum imóvel com esses filtros. Tire um filtro e tente de novo.</p>';
        pintarPaginas(d.total);
      })
      .catch(function () { if (meu === pedido) contagem.textContent = "Não foi possível buscar agora. Tente de novo."; });
  }
  function recomecar() { pagina = 1; buscar(); }

  // o que veio no endereço (da home, ou de um link guardado)
  var url = new URLSearchParams(window.location.search);
  url.getAll("bairros").concat(url.getAll("bairro")).forEach(function (b) { if (b.trim()) bairros.push(b.trim()); });
  campo.condominio.value = url.get("condominio") || "";
  campo.vmin.value = url.get("valor_min") || "";
  campo.vmax.value = url.get("valor_max") || "";
  campo.banheiros.value = url.get("banheiros") || "";
  pressionar(campo.quartos, url.get("quartos"));
  pressionar(campo.garagem, url.get("garagem"));
  // TIPO EM BOTÕES (05/10, Pedro: "deixa selecionável mesmo os principais, o resto no +")
  var PRINCIPAIS = ["Apartamento", "Casa", "Casa de condomínio"];
  var tipoPrincipais = form.querySelector("#f-tipo-principais"), tipoMais = form.querySelector("#f-tipo-mais");
  function botaoTipo(nome, atual) {
    return '<button class="opcoes__botao" type="button" aria-pressed="' + (nome === atual ? "true" : "false") + '">' + escapar(nome) + "</button>";
  }
  function pintarTipos(nomes, atual) {
    if (atual && nomes.indexOf(atual) < 0) nomes = nomes.concat([atual]);
    var frente = PRINCIPAIS.filter(function (n) { return nomes.indexOf(n) >= 0; });
    var resto = nomes.filter(function (n) { return frente.indexOf(n) < 0; });
    tipoPrincipais.innerHTML = frente.map(function (n) { return botaoTipo(n, atual); }).join("") +
      (resto.length ? '<button class="opcoes__botao" type="button" id="f-tipo-abrir" aria-expanded="false" aria-controls="f-tipo-mais" title="Mais tipos">+</button>' : "");
    tipoMais.innerHTML = resto.map(function (n) { return botaoTipo(n, atual); }).join("");
    abrirMais(resto.indexOf(atual) >= 0);   // o escolhido está no resto: já vem aberto
  }
  function abrirMais(aberto) {
    var b = form.querySelector("#f-tipo-abrir");
    tipoMais.hidden = !aberto;
    if (b) { b.setAttribute("aria-expanded", aberto ? "true" : "false"); b.textContent = aberto ? "−" : "+"; }
  }
  pintarTipos(PRINCIPAIS.slice(), url.get("tipo") || "");   // até a lista do banco chegar
  fetch(API + "/api/tipos")
    .then(function (r) { return r.ok ? r.json() : []; })
    .then(function (lista) {
      var nomes = lista.filter(function (t) { return t[finalidade] > 0; }).map(function (t) { return t.tipo; });
      if (nomes.length) pintarTipos(nomes, pressionado(campo.tipo));
    })
    .catch(function () {});
  pintarMarcadores();

  // os links Comprar/Alugar levam os filtros junto
  form.querySelectorAll("[data-destino]").forEach(function (aba) {
    aba.addEventListener("click", function (e) {
      e.stopPropagation();
      var s = filtros().toString();
      window.location.href = aba.dataset.destino + (s ? "?" + s : "");
    });
  });

  form.addEventListener("bairro-escolhido", function (e) { if (somarBairro(e.detail)) recomecar(); });
  campo.marcadores.addEventListener("click", function (e) {
    var b = e.target.closest("[data-tirar]");
    if (!b) return;
    e.stopPropagation();               // o site.js antigo apagava o marcador da tela sem refazer a busca
    bairros.splice(Number(b.dataset.tirar), 1);
    pintarMarcadores();
    recomecar();
  });
  form.addEventListener("submit", function (e) {
    e.preventDefault();
    somarBairro(campo.bairro.value);   // digitou e apertou Enter sem clicar na lista: vale o que digitou
    recomecar();
  });
  campo.tipo.addEventListener("click", function (e) {
    if (e.target.closest("#f-tipo-abrir")) abrirMais(tipoMais.hidden);
  });
  [campo.tipo, campo.quartos, campo.garagem].forEach(function (g) {
    g.addEventListener("click", function (e) {
      if (e.target.closest("[aria-pressed]")) setTimeout(recomecar, 0);   // depois do site.js trocar o botão
    });
  });
  var espera;
  [campo.condominio, campo.vmin, campo.vmax, campo.banheiros].forEach(function (c) {
    c.addEventListener("input", function () { clearTimeout(espera); espera = setTimeout(recomecar, 600); });
  });
  nav.addEventListener("click", function (e) {
    var a = e.target.closest("[data-p]");
    if (!a) return;
    e.preventDefault();
    pagina = Number(a.dataset.p);
    buscar();
    alvo.scrollIntoView({ behavior: "smooth", block: "start" });
  });

  mostrar([]);     // tira os imóveis de exemplo enquanto a busca de verdade não chega
  nav.innerHTML = "";
  buscar();
})();
