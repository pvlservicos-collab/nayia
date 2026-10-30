/* ==========================================================================
   Imob Easy — Campo de bairro e condomínio da busca (home, comprar e alugar)

   Pedido do Tel (15/09/2026): "quando a pessoa clica no bairro para pesquisar imóveis na home, desce a lista com
   todos os bairros cadastrados, e conforme ela for digitando vai ficando só os que correspondem".
   12/10/2026: a lista traz também os CONDOMÍNIOS que têm imóvel disponível.

   16/10/2026 (Pedro: "não funciona a múltipla seleção de bairro já de início e nem aparece os condomínios em lista
   para selecionar vários também, nem na home nem dentro de ver imóveis"): o campo virou uma ESCOLHA DE VÁRIOS
   LUGARES. A lista já desce com os bairros e os condomínios (os com mais imóveis; digitando, acha qualquer um); cada
   clique marca ou desmarca e a lista continua aberta; o que foi escolhido vira marcador com ×. A busca traz os imóveis
   de qualquer um dos lugares escolhidos (bairros OU condomínios).

   Para os outros scripts (busca-filtros.js): `input.lugares.escolhidos()` -> [{tipo: "b"|"c", nome}],
   `input.lugares.definir(lista)` e o evento "lugares-mudaram" no campo (borbulha) a cada mudança.
   A lista vem uma vez de /api/bairros e /api/condominios e o filtro acontece na tela. Com a API fora do ar o campo
   continua sendo um campo de texto normal.
   ========================================================================== */
(function () {
  "use strict";

  var input = document.getElementById("bairro");
  if (!input) return;

  var CONDOS_DE_INICIO = 30;     // com o campo vazio, os condomínios com mais imóveis (são centenas)

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
    "box-shadow:0 8px 24px rgba(20,30,60,.14);max-height:320px;overflow-y:auto;text-align:left}" +
    ".campo-bairro__lista[hidden]{display:none}" +
    ".campo-bairro__item{display:flex;align-items:center;gap:10px;width:100%;text-align:left;border:0;" +
    "background:#fff;padding:9px 12px;cursor:pointer;font:inherit;font-size:var(--fs-sm,14px);color:var(--texto,#1c2533)}" +
    ".campo-bairro__marca{flex:0 0 18px;height:18px;border:1.5px solid var(--borda-forte,#b8bdc9);border-radius:4px;" +
    "display:inline-flex;align-items:center;justify-content:center;font-size:12px;line-height:1;color:#fff;background:#fff}" +
    ".campo-bairro__item--escolhido .campo-bairro__marca{background:var(--azul,#1E5FD9);border-color:var(--azul,#1E5FD9)}" +
    ".campo-bairro__nome{flex:1 1 auto;min-width:0}" +
    ".campo-bairro__item span.campo-bairro__qt{color:var(--texto-fraco,#6b7280);font-size:var(--fs-xs,12px);white-space:nowrap}" +
    ".campo-bairro__item[aria-selected=true],.campo-bairro__item:hover{background:var(--selecao,#e8eefc)}" +
    ".campo-bairro__vazio{padding:9px 12px;color:var(--texto-fraco,#6b7280);font-size:var(--fs-sm,14px)}" +
    ".campo-bairro__grupo{padding:7px 12px 3px;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;" +
    "color:var(--texto-fraco,#6b7280);background:#fff;position:sticky;top:0;z-index:1}" +
    ".campo-bairro__dica{padding:6px 12px 9px;font-size:12px;color:var(--texto-fraco,#6b7280)}" +
    ".campo-bairro__pronto{position:sticky;bottom:0;display:flex;justify-content:space-between;align-items:center;gap:8px;" +
    "padding:8px 12px;background:#fff;border-top:1px solid var(--borda,#e3e6ec);font-size:12px;color:var(--texto-fraco,#6b7280)}" +
    ".campo-bairro__pronto button{border:0;background:var(--azul,#1E5FD9);color:#fff;font:inherit;font-size:13px;" +
    "font-weight:600;padding:6px 14px;border-radius:999px;cursor:pointer}" +
    // os marcadores da home (em comprar/alugar valem os .marcador do site.css, na caixa #f-bairros)
    ".campo-bairro__chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}" +
    ".campo-bairro__chips[hidden]{display:none}" +
    ".campo-bairro__chip{display:inline-flex;align-items:center;gap:6px;max-width:100%;background:var(--selecao,#e8eefc);" +
    "color:var(--texto,#1c2533);border-radius:999px;padding:4px 6px 4px 11px;font-size:13px;line-height:1.2}" +
    ".campo-bairro__chip small{color:var(--texto-fraco,#6b7280);font-size:11px}" +
    ".campo-bairro__chip button{border:0;background:transparent;cursor:pointer;font-size:16px;line-height:1;" +
    "color:var(--texto-fraco,#6b7280);padding:0 3px}";
  document.head.appendChild(css);

  var caixa = document.createElement("div");
  caixa.className = "campo-bairro";
  input.parentNode.insertBefore(caixa, input);
  caixa.appendChild(input);

  // onde ficam os marcadores: a caixa que comprar/alugar já tem (#f-bairros), ou uma nossa embaixo do campo (home)
  var marcadores = document.getElementById("f-bairros");
  var naCaixaDoSite = !!marcadores;
  if (!marcadores) {
    marcadores = document.createElement("div");
    marcadores.className = "campo-bairro__chips";
    marcadores.hidden = true;
    caixa.appendChild(marcadores);
  }

  var lista = document.createElement("div");
  lista.className = "campo-bairro__lista";
  lista.setAttribute("role", "listbox");
  lista.setAttribute("aria-multiselectable", "true");
  lista.hidden = true;
  document.body.appendChild(lista);

  function posicionar() {
    if (lista.hidden) return;
    var r = input.getBoundingClientRect();
    var largura = Math.max(r.width, 260);
    lista.style.left = Math.max(8, Math.min(r.left, window.innerWidth - largura - 8)) + "px";
    lista.style.top = (r.bottom + 4) + "px";
    lista.style.width = largura + "px";
    lista.style.maxHeight = Math.max(160, Math.min(320, window.innerHeight - r.bottom - 12)) + "px";
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
  var escolhidos = [];   // [{tipo: "b" | "c", nome}]
  var ativo = -1;
  var carregando = null;

  function chave(tipo, nome) { return tipo + ":" + normalizar(nome); }
  function escolhido(tipo, nome) {
    var k = chave(tipo, nome);
    return escolhidos.some(function (x) { return chave(x.tipo, x.nome) === k; });
  }

  /* 30/10 (Pedro: "dizia que tinha 4 imóveis mas quando selecionei Turim não apareceu nenhum"): o número ao lado de
     cada bairro e condomínio é o que a busca DESTA página acha -- no ar, de aluguel em Alugar e de venda em Comprar;
     o que daria zero não aparece. Na home, tudo o que está no ar. */
  var FIN = /alugar/i.test(window.location.pathname) ? "aluguel" : /comprar/i.test(window.location.pathname) ? "venda" : null;
  function quantosNoCondominio(c) {
    if (c.no_site === undefined) return c.disponiveis || 0;          // a API de antes
    return (FIN === "aluguel" ? c.no_site_aluguel : FIN === "venda" ? c.no_site_venda : c.no_site) || 0;
  }
  function quantosNoBairro(b) {
    return (FIN && b[FIN] !== undefined ? b[FIN] : b.imoveis) || 0;
  }

  function carregar() {
    if (bairros.length || condominios.length || !window.API_BASE) return Promise.resolve();
    if (carregando) return carregando;
    var osCondominios = fetch(window.API_BASE + "/api/condominios")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (dados) {
        condominios = (Array.isArray(dados) ? dados : [])
          .filter(function (c) { return c.nome && quantosNoCondominio(c) > 0; })
          .sort(function (a, b) { return quantosNoCondominio(b) - quantosNoCondominio(a) || String(a.nome).localeCompare(b.nome, "pt-BR"); });
      })
      .catch(function () { condominios = []; });      // sem os condomínios o campo segue só com os bairros
    carregando = fetch(window.API_BASE + "/api/bairros")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (dados) { bairros = (Array.isArray(dados) ? dados : []).filter(function (b) { return quantosNoBairro(b) > 0; }); })
      .catch(function () { bairros = []; })   // API fora: campo de texto normal
      .then(function () { return osCondominios; });
    return carregando;
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
      return { tipo: "b", nome: b.bairro, quantos: quantosNoBairro(b) };
    });
    // os condomínios já descem com o campo vazio (os com mais imóveis); digitando, qualquer um
    var achados = acha(condominios, function (c) { return c.nome; });
    var osCondos = achados.slice(0, busca ? 60 : CONDOS_DE_INICIO).map(function (c) {
      return { tipo: "c", nome: c.nome, quantos: quantosNoCondominio(c), onde: c.bairro };
    });
    mostrados = osBairros.concat(osCondos);
    ativo = -1;

    if (!bairros.length && !condominios.length) { fechar(); return; }

    var html = "";
    if (!mostrados.length) {
      html = '<div class="campo-bairro__vazio">Nenhum bairro ou condomínio com esse nome</div>';
    } else {
      var grupo = "";
      html = mostrados.map(function (x, i) {
        var quantos = x.quantos === 1 ? "1 imóvel" : x.quantos + " imóveis";
        var titulo = "";
        if (x.tipo !== grupo) {
          grupo = x.tipo;
          titulo = '<div class="campo-bairro__grupo">' + (x.tipo === "b" ? "Bairros" : "Condomínios") + "</div>";
        }
        var marcado = escolhido(x.tipo, x.nome);
        return titulo + '<button class="campo-bairro__item' + (marcado ? " campo-bairro__item--escolhido" : "") +
               '" type="button" role="option" aria-selected="false" aria-checked="' + marcado + '" data-i="' + i + '">' +
               '<span class="campo-bairro__marca" aria-hidden="true">' + (marcado ? "✓" : "") + "</span>" +
               '<span class="campo-bairro__nome">' + escapar(x.nome) + "</span>" +
               '<span class="campo-bairro__qt">' + (x.onde ? escapar(x.onde) + " · " : "") + quantos + "</span></button>";
      }).join("");
      if (!busca && achados.length > CONDOS_DE_INICIO) {
        html += '<div class="campo-bairro__dica">Digite o nome para achar os outros ' + (achados.length - CONDOS_DE_INICIO) +
                " condomínios.</div>";
      }
    }
    html += '<div class="campo-bairro__pronto"><span>' +
            (escolhidos.length ? escolhidos.length + (escolhidos.length === 1 ? " escolhido" : " escolhidos") : "Escolha um ou vários") +
            '</span><button type="button" data-pronto>Pronto</button></div>';
    var rolagem = lista.scrollTop;
    lista.innerHTML = html;
    lista.scrollTop = rolagem;
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

  function pintarMarcadores() {
    if (naCaixaDoSite) marcadores.style.display = escolhidos.length ? "" : "none";   // [hidden] perde para o display:flex
    else marcadores.hidden = !escolhidos.length;
    marcadores.innerHTML = escolhidos.map(function (x, i) {
      var tipo = x.tipo === "c" ? "condomínio" : "bairro";
      return naCaixaDoSite
        ? '<span class="marcador">' + escapar(x.nome) + '<button type="button" data-tirar="' + i +
          '" aria-label="Remover ' + tipo + " " + escapar(x.nome) + '">&times;</button></span>'
        : '<span class="campo-bairro__chip">' + escapar(x.nome) + (x.tipo === "c" ? " <small>condomínio</small>" : "") +
          '<button type="button" data-tirar="' + i + '" aria-label="Remover ' + tipo + " " + escapar(x.nome) + '">&times;</button></span>';
    }).join("");
  }

  function avisar() {
    pintarMarcadores();
    var detalhe = {
      bairros: escolhidos.filter(function (x) { return x.tipo === "b"; }).map(function (x) { return x.nome; }),
      condominios: escolhidos.filter(function (x) { return x.tipo === "c"; }).map(function (x) { return x.nome; })
    };
    input.dispatchEvent(new CustomEvent("lugares-mudaram", { bubbles: true, detail: detalhe }));
  }

  function alternar(i) {
    var x = mostrados[i];
    if (!x) return;
    var k = chave(x.tipo, x.nome);
    var antes = escolhidos.length;
    escolhidos = escolhidos.filter(function (e) { return chave(e.tipo, e.nome) !== k; });
    if (escolhidos.length === antes) escolhidos.push({ tipo: x.tipo, nome: x.nome });
    desenhar();
    avisar();
  }

  function buscar() {
    // o formulário não tem botão de enviar: Enter não o envia sozinho. requestSubmit dispara o "submit" de sempre.
    var form = input.form;
    if (!form) return;
    if (form.requestSubmit) form.requestSubmit();
    else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  }

  // para busca-filtros.js
  input.lugares = {
    escolhidos: function () { return escolhidos.slice(); },
    definir: function (itens) {
      var vistos = {};
      escolhidos = (itens || []).filter(function (x) {
        var k = x && x.nome && chave(x.tipo === "c" ? "c" : "b", x.nome);
        if (!k || vistos[k]) return false;
        vistos[k] = 1;
        return true;
      }).map(function (x) { return { tipo: x.tipo === "c" ? "c" : "b", nome: String(x.nome).trim() }; });
      pintarMarcadores();
      if (!lista.hidden) desenhar();
    },
    // o que ficou digitado sem escolher na lista: vale como bairro (Enter, ou Buscar)
    somarDigitado: function () {
      var t = input.value.trim();
      input.value = "";
      if (!t || escolhido("b", t) || escolhido("c", t)) return false;
      var c = condominios.filter(function (x) { return normalizar(x.nome) === normalizar(t); })[0];
      escolhidos.push({ tipo: c ? "c" : "b", nome: c ? c.nome : t });
      avisar();
      return true;
    }
  };

  // Clicou ou entrou no campo: desce a lista inteira.
  input.addEventListener("focus", function () { carregar().then(desenhar); });
  input.addEventListener("click", function () { carregar().then(desenhar); });
  // Digitando: fica só quem corresponde.
  input.addEventListener("input", function () { lista.scrollTop = 0; carregar().then(desenhar); });

  input.addEventListener("keydown", function (e) {
    if (lista.hidden && (e.key === "ArrowDown" || e.key === "Down")) { carregar().then(desenhar); return; }
    if (lista.hidden && e.key === "Enter") { e.preventDefault(); buscar(); return; }
    if (lista.hidden) return;
    if (e.key === "ArrowDown" || e.key === "Down") { e.preventDefault(); marcar(ativo + 1); }
    else if (e.key === "ArrowUp" || e.key === "Up") { e.preventDefault(); marcar(ativo - 1); }
    else if (e.key === "Enter") {
      // Enter marca o que está em destaque (ou o primeiro achado do que foi digitado) e limpa o texto para o próximo;
      // com o campo vazio e nada em destaque, fecha a lista e busca.
      e.preventDefault();
      if (ativo >= 0) { alternar(ativo); return; }
      if (input.value.trim() && mostrados.length) {
        if (!escolhido(mostrados[0].tipo, mostrados[0].nome)) alternar(0);
        input.value = "";
        desenhar();
        return;
      }
      fechar();
      buscar();
    }
    else if (e.key === "Escape" || e.key === "Esc") { fechar(); }
  });

  lista.addEventListener("mousedown", function (e) {
    e.preventDefault();               // segura o foco no campo (a lista não fecha)
    if (e.target.closest("[data-pronto]")) { fechar(); input.value = ""; return; }
    var item = e.target.closest(".campo-bairro__item");
    if (item) alternar(Number(item.dataset.i));
  });

  marcadores.addEventListener("click", function (e) {
    var b = e.target.closest("[data-tirar]");
    if (!b) return;
    e.preventDefault();
    e.stopPropagation();              // o site.js antigo apagava o marcador da tela sem refazer a busca
    escolhidos.splice(Number(b.dataset.tirar), 1);
    if (!lista.hidden) desenhar();
    avisar();
  });

  document.addEventListener("click", function (e) {
    if (!caixa.contains(e.target) && !lista.contains(e.target)) fechar();
  });

  // a lista já fica baixada: no primeiro toque ela desce na hora
  carregar();
})();
