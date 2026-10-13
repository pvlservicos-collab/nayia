/* ==========================================================================
   Imob Easy — Campo de bairro da busca (home)

   Pedido do Tel (15/09/2026): "quando a pessoa clica no bairro para pesquisar
   imóveis na home, desce a lista com todos os bairros cadastrados, e conforme
   ela for digitando vai ficando só os que correspondem".

   A lista vem uma vez de /api/bairros e o filtro acontece na tela, sem ida ao
   servidor a cada tecla. Sem acento e sem diferenciar maiúscula: "pq dez" acha
   "Parque 10 de Novembro"? não -- acha quem contém o que foi digitado, então
   "parque" acha. Com a API fora do ar o campo continua sendo um campo de texto
   normal.

   12/10/2026 (Pedro: "não estou conseguindo procurar por condomínio ou bairro"):
   o campo diz "Bairro/Condomínio" e a lista só tinha bairro; e Enter não fazia
   nada (o formulário não tem botão de enviar, então o navegador não o envia
   sozinho). Agora a lista traz os CONDOMÍNIOS que têm imóvel disponível, embaixo
   dos bairros, e Enter escolhe o primeiro da lista e faz a busca.
   ========================================================================== */
(function () {
  "use strict";

  var input = document.getElementById("bairro");
  if (!input) return;

  function normalizar(txt) {
    return String(txt == null ? "" : txt)
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .toLowerCase().trim();
  }

  function escapar(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  var css = document.createElement("style");
  css.textContent =
    ".campo-bairro{position:relative}" +
    // 05/10 (Pedro): a lista não aparecia -- o painel da busca tem overflow:hidden e cortava a lista
    // que descia por dentro dele. Agora ela fica presa à tela (fixed), fora do painel, embaixo do campo.
    ".campo-bairro__lista{position:fixed;z-index:1000;background:#fff;" +
    "border:1px solid var(--borda,#d9dce3);border-radius:var(--raio-md,8px);" +
    "box-shadow:0 8px 24px rgba(20,30,60,.14);max-height:280px;overflow-y:auto;text-align:left}" +
    ".campo-bairro__lista[hidden]{display:none}" +
    ".campo-bairro__item{display:flex;justify-content:space-between;gap:10px;width:100%;text-align:left;border:0;" +
    "background:#fff;padding:9px 12px;cursor:pointer;font:inherit;font-size:var(--fs-sm,14px);color:var(--texto,#1c2533)}" +
    ".campo-bairro__item span{color:var(--texto-fraco,#6b7280);font-size:var(--fs-xs,12px)}" +
    ".campo-bairro__item[aria-selected=true],.campo-bairro__item:hover{background:var(--selecao,#e8eefc)}" +
    ".campo-bairro__vazio{padding:9px 12px;color:var(--texto-fraco,#6b7280);font-size:var(--fs-sm,14px)}" +
    ".campo-bairro__grupo{padding:7px 12px 3px;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;" +
    "color:var(--texto-fraco,#6b7280);background:#fff;position:sticky;top:0}";
  document.head.appendChild(css);

  var caixa = document.createElement("div");
  caixa.className = "campo-bairro";
  input.parentNode.insertBefore(caixa, input);
  caixa.appendChild(input);

  var lista = document.createElement("div");
  lista.className = "campo-bairro__lista";
  lista.setAttribute("role", "listbox");
  lista.hidden = true;
  document.body.appendChild(lista);

  function posicionar() {
    if (lista.hidden) return;
    var r = input.getBoundingClientRect();
    var largura = Math.max(r.width, 240);
    lista.style.left = Math.max(8, Math.min(r.left, window.innerWidth - largura - 8)) + "px";
    lista.style.top = (r.bottom + 4) + "px";
    lista.style.width = largura + "px";
    lista.style.maxHeight = Math.max(140, Math.min(280, window.innerHeight - r.bottom - 12)) + "px";
  }
  window.addEventListener("scroll", posicionar, true);
  window.addEventListener("resize", posicionar);

  input.setAttribute("autocomplete", "off");
  input.setAttribute("role", "combobox");
  input.setAttribute("aria-expanded", "false");
  input.setAttribute("aria-autocomplete", "list");

  var bairros = [];      // [{bairro, imoveis}]
  var condominios = [];  // [{nome, bairro, disponiveis}] -- só os que têm imóvel disponível
  var mostrados = [];    // [{tipo: "b" | "c", nome, quantos, onde}]
  var ativo = -1;
  var carregando = false;

  function carregar() {
    if (bairros.length || carregando || !window.API_BASE) return Promise.resolve();
    carregando = true;
    var osCondominios = fetch(window.API_BASE + "/api/condominios")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (dados) {
        condominios = (Array.isArray(dados) ? dados : []).filter(function (c) { return c.nome && c.disponiveis > 0; });
      })
      .catch(function () { condominios = []; });      // sem os condomínios o campo segue só com os bairros
    return fetch(window.API_BASE + "/api/bairros")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (dados) { bairros = Array.isArray(dados) ? dados : []; })
      .catch(function () { bairros = []; })   // API fora: campo de texto normal
      .then(function () { return osCondominios; })
      .then(function () { carregando = false; });
  }

  function desenhar() {
    var busca = normalizar(input.value);
    // "ao digitar as letras iniciais já filtre": primeiro quem COMEÇA com o que foi digitado,
    // depois quem tem uma palavra começando assim ("dez" acha "Parque Dez").
    function acha(itens, nomeDe) {
      var comeca = [], palavra = [];
      itens.forEach(function (x) {
        var nome = normalizar(nomeDe(x));
        if (!busca || nome.indexOf(busca) === 0) comeca.push(x);
        else if ((" " + nome).indexOf(" " + busca) >= 0) palavra.push(x);
      });
      return comeca.concat(palavra);
    }
    var osBairros = acha(bairros, function (b) { return b.bairro; }).map(function (b) {
      return { tipo: "b", nome: b.bairro, quantos: b.imoveis };
    });
    // os condomínios só entram quando ele digita (são centenas): com o campo vazio desce a lista dos bairros
    var osCondos = !busca ? [] : acha(condominios, function (c) { return c.nome; }).slice(0, 40).map(function (c) {
      return { tipo: "c", nome: c.nome, quantos: c.disponiveis, onde: c.bairro };
    });
    mostrados = osBairros.concat(osCondos);
    ativo = -1;

    if (!bairros.length && !condominios.length) { fechar(); return; }

    if (!mostrados.length) {
      lista.innerHTML = '<div class="campo-bairro__vazio">Nenhum bairro ou condomínio com esse nome</div>';
    } else {
      var grupo = "";
      lista.innerHTML = mostrados.map(function (x, i) {
        var quantos = x.quantos === 1 ? "1 imóvel" : x.quantos + " imóveis";
        var titulo = "";
        if (x.tipo !== grupo && osCondos.length) {
          grupo = x.tipo;
          titulo = '<div class="campo-bairro__grupo">' + (x.tipo === "b" ? "Bairros" : "Condomínios") + "</div>";
        }
        return titulo + '<button class="campo-bairro__item" type="button" role="option" aria-selected="false" data-i="' + i + '">' +
               escapar(x.nome) + "<span>" + (x.onde ? escapar(x.onde) + " · " : "") + quantos + "</span></button>";
      }).join("");
    }
    abrir();
  }

  function abrir() {
    lista.hidden = false;
    input.setAttribute("aria-expanded", "true");
    posicionar();
  }

  function fechar() {
    lista.hidden = true;
    input.setAttribute("aria-expanded", "false");
    ativo = -1;
  }

  function marcar(i) {
    var itens = lista.querySelectorAll(".campo-bairro__item");
    if (!itens.length) return;
    ativo = (i + itens.length) % itens.length;
    itens.forEach(function (el, n) { el.setAttribute("aria-selected", n === ativo ? "true" : "false"); });
    itens[ativo].scrollIntoView({ block: "nearest" });
  }

  function escolher(i) {
    if (!mostrados[i]) return;
    var escolhido = mostrados[i].nome;
    fechar();
    if (mostrados[i].tipo === "c") {
      var doCondominio = document.getElementById("f-condominio");
      if (doCondominio) {             // comprar/alugar: o campo do condomínio já existe e refaz a busca sozinho
        input.value = "";
        doCondominio.value = escolhido;
        doCondominio.dispatchEvent(new Event("input", { bubbles: true }));
      } else {                        // home: vai junto no Buscar (busca-filtros.js lê data-condominio)
        input.value = escolhido;
        input.dataset.condominio = escolhido;
      }
      return;
    }
    delete input.dataset.condominio;
    input.value = escolhido;
    input.dispatchEvent(new Event("change", { bubbles: true }));
    // comprar/alugar: o bairro escolhido vira marcador (busca-filtros.js)
    input.dispatchEvent(new CustomEvent("bairro-escolhido", { bubbles: true, detail: escolhido }));
  }

  function buscar() {
    // o formulário não tem botão de enviar: Enter não o envia sozinho. requestSubmit dispara o "submit" de sempre.
    var form = input.form;
    if (!form) return;
    if (form.requestSubmit) form.requestSubmit();
    else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  }

  // Clicou ou entrou no campo: desce a lista inteira.
  input.addEventListener("focus", function () { carregar().then(desenhar); });
  input.addEventListener("click", function () { carregar().then(desenhar); });
  // Digitando: fica só quem corresponde.
  input.addEventListener("input", function () { delete input.dataset.condominio; carregar().then(desenhar); });

  input.addEventListener("keydown", function (e) {
    if (lista.hidden && (e.key === "ArrowDown" || e.key === "Down")) { carregar().then(desenhar); return; }
    if (lista.hidden && e.key === "Enter") { e.preventDefault(); buscar(); return; }
    if (lista.hidden) return;
    if (e.key === "ArrowDown" || e.key === "Down") { e.preventDefault(); marcar(ativo + 1); }
    else if (e.key === "ArrowUp" || e.key === "Up") { e.preventDefault(); marcar(ativo - 1); }
    else if (e.key === "Enter") {
      // Enter vale o que está marcado; sem nada marcado, o primeiro da lista. Na home, depois de escolher já busca.
      e.preventDefault();
      var naHome = !document.getElementById("f-condominio");
      if (mostrados.length) escolher(ativo >= 0 ? ativo : 0);
      else fechar();
      if (naHome || !mostrados.length) buscar();
    }
    else if (e.key === "Escape" || e.key === "Esc") { fechar(); }
  });

  lista.addEventListener("mousedown", function (e) {
    var item = e.target.closest(".campo-bairro__item");
    if (!item) return;
    e.preventDefault();               // segura o foco no campo
    escolher(Number(item.dataset.i));
  });

  document.addEventListener("click", function (e) {
    if (!caixa.contains(e.target) && !lista.contains(e.target)) fechar();
  });

  // a lista já fica baixada: no primeiro toque ela desce na hora
  carregar();
})();
