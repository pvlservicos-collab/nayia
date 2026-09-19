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
    ".campo-bairro__lista{position:absolute;left:0;right:0;top:100%;z-index:60;background:#fff;" +
    "border:1px solid var(--borda,#d9dce3);border-radius:var(--raio-md,8px);" +
    "box-shadow:0 8px 24px rgba(20,30,60,.14);max-height:280px;overflow-y:auto;margin-top:4px;text-align:left}" +
    ".campo-bairro__lista[hidden]{display:none}" +
    ".campo-bairro__item{display:flex;justify-content:space-between;gap:10px;width:100%;text-align:left;border:0;" +
    "background:#fff;padding:9px 12px;cursor:pointer;font:inherit;font-size:var(--fs-sm,14px);color:var(--texto,#1c2533)}" +
    ".campo-bairro__item span{color:var(--texto-fraco,#6b7280);font-size:var(--fs-xs,12px)}" +
    ".campo-bairro__item[aria-selected=true],.campo-bairro__item:hover{background:var(--selecao,#e8eefc)}" +
    ".campo-bairro__vazio{padding:9px 12px;color:var(--texto-fraco,#6b7280);font-size:var(--fs-sm,14px)}";
  document.head.appendChild(css);

  var caixa = document.createElement("div");
  caixa.className = "campo-bairro";
  input.parentNode.insertBefore(caixa, input);
  caixa.appendChild(input);

  var lista = document.createElement("div");
  lista.className = "campo-bairro__lista";
  lista.setAttribute("role", "listbox");
  lista.hidden = true;
  caixa.appendChild(lista);

  input.setAttribute("autocomplete", "off");
  input.setAttribute("role", "combobox");
  input.setAttribute("aria-expanded", "false");
  input.setAttribute("aria-autocomplete", "list");

  var bairros = [];      // [{bairro, imoveis}]
  var mostrados = [];
  var ativo = -1;
  var carregando = false;

  function carregar() {
    if (bairros.length || carregando || !window.API_BASE) return Promise.resolve();
    carregando = true;
    return fetch(window.API_BASE + "/api/bairros")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (dados) { bairros = Array.isArray(dados) ? dados : []; })
      .catch(function () { bairros = []; })   // API fora: campo de texto normal
      .then(function () { carregando = false; });
  }

  function desenhar() {
    var busca = normalizar(input.value);
    mostrados = bairros.filter(function (b) {
      return !busca || normalizar(b.bairro).indexOf(busca) >= 0;
    });
    ativo = -1;

    if (!bairros.length) { fechar(); return; }

    if (!mostrados.length) {
      lista.innerHTML = '<div class="campo-bairro__vazio">Nenhum bairro com esse nome</div>';
    } else {
      lista.innerHTML = mostrados.map(function (b, i) {
        var quantos = b.imoveis === 1 ? "1 imóvel" : b.imoveis + " imóveis";
        return '<button class="campo-bairro__item" type="button" role="option" aria-selected="false" data-i="' + i + '">' +
               escapar(b.bairro) + "<span>" + quantos + "</span></button>";
      }).join("");
    }
    abrir();
  }

  function abrir() {
    lista.hidden = false;
    input.setAttribute("aria-expanded", "true");
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
    input.value = mostrados[i].bairro;
    fechar();
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  // Clicou ou entrou no campo: desce a lista inteira.
  input.addEventListener("focus", function () { carregar().then(desenhar); });
  input.addEventListener("click", function () { carregar().then(desenhar); });
  // Digitando: fica só quem corresponde.
  input.addEventListener("input", function () { carregar().then(desenhar); });

  input.addEventListener("keydown", function (e) {
    if (lista.hidden && (e.key === "ArrowDown" || e.key === "Down")) { carregar().then(desenhar); return; }
    if (lista.hidden) return;
    if (e.key === "ArrowDown" || e.key === "Down") { e.preventDefault(); marcar(ativo + 1); }
    else if (e.key === "ArrowUp" || e.key === "Up") { e.preventDefault(); marcar(ativo - 1); }
    else if (e.key === "Enter") { if (ativo >= 0) { e.preventDefault(); escolher(ativo); } }
    else if (e.key === "Escape" || e.key === "Esc") { fechar(); }
  });

  lista.addEventListener("mousedown", function (e) {
    var item = e.target.closest(".campo-bairro__item");
    if (!item) return;
    e.preventDefault();               // segura o foco no campo
    escolher(Number(item.dataset.i));
  });

  document.addEventListener("click", function (e) {
    if (!caixa.contains(e.target)) fechar();
  });
})();
