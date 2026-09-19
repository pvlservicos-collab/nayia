/* ==========================================================================
   Imob Easy — "Próximos passos" do Roadmap: lista simples + lápis + popup
   pra editar ou excluir. Grava na tabela site_proximos_passos via role
   dedicada (nay_site_conteudo -- CRUD só nessa tabela, nada mais).
   ========================================================================== */
(function () {
  "use strict";

  var lista = document.getElementById("lista-proximos-passos");
  if (!lista) return; // só existe em admin/inicio.html

  var formNovo = document.getElementById("form-novo-passo");
  var campoTitulo = document.getElementById("novo-passo-titulo");
  var campoDescricao = document.getElementById("novo-passo-descricao");
  var botaoAbrirNovo = document.getElementById("botao-abrir-novo-passo");
  var botaoCancelarNovo = document.getElementById("botao-cancelar-novo-passo");

  botaoAbrirNovo.addEventListener("click", function () {
    formNovo.hidden = false;
    botaoAbrirNovo.hidden = true;
    campoTitulo.focus();
  });

  function fecharFormNovo() {
    formNovo.hidden = true;
    botaoAbrirNovo.hidden = false;
    campoTitulo.value = "";
    campoDescricao.value = "";
  }
  botaoCancelarNovo.addEventListener("click", fecharFormNovo);

  var overlay = document.getElementById("popup-passo");
  var popupId = document.getElementById("popup-passo-id");
  var popupTitulo = document.getElementById("popup-passo-titulo");
  var popupDescricao = document.getElementById("popup-passo-descricao");
  var popupStatus = document.getElementById("popup-passo-status");
  var btnSalvar = document.getElementById("popup-passo-salvar");
  var btnExcluir = document.getElementById("popup-passo-excluir");
  var btnFechar = document.getElementById("popup-passo-fechar");

  function esc(txt) {
    return String(txt == null ? "" : txt)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function url(caminho) { return window.API_BASE + caminho; }

  function renderizarItem(item) {
    return (
      '<li class="lista-passos__item" data-item-id="' + item.id + '">' +
        '<div class="lista-passos__texto">' +
          "<strong>" + esc(item.titulo) + "</strong>" +
          "<p>" + esc(item.descricao || "") + "</p>" +
        "</div>" +
        '<button class="lista-passos__lapis" type="button" data-editar="' + item.id + '" aria-label="Editar ' + esc(item.titulo) + '">' +
          '<svg viewBox="0 0 16 16" width="15" height="15" fill="currentColor" aria-hidden="true"><path d="M11.3 1.3a1 1 0 0 1 1.4 0l2 2a1 1 0 0 1 0 1.4L5.4 14 1 15l1-4.4Z"/></svg>' +
        "</button>" +
      "</li>"
    );
  }

  function carregar() {
    fetch(url("/api/proximos-passos"))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (itens) {
        lista.innerHTML = itens.length
          ? itens.map(renderizarItem).join("")
          : '<li class="painel__vazio">Nenhum item ainda.</li>';
      })
      .catch(function () {
        lista.innerHTML = '<li class="painel__vazio">Não foi possível carregar os próximos passos.</li>';
      });
  }

  function abrirPopup(id, titulo, descricao) {
    popupId.value = id;
    popupTitulo.value = titulo;
    popupDescricao.value = descricao || "";
    popupStatus.textContent = "";
    popupStatus.className = "form-imovel__status";
    overlay.hidden = false;
  }

  function fecharPopup() { overlay.hidden = true; }

  lista.addEventListener("click", function (evento) {
    var botao = evento.target.closest("[data-editar]");
    if (!botao) return;
    var li = botao.closest(".lista-passos__item");
    var textoEl = li.querySelector(".lista-passos__texto");
    abrirPopup(botao.dataset.editar, textoEl.querySelector("strong").textContent, textoEl.querySelector("p").textContent);
  });

  overlay.addEventListener("click", function (evento) {
    if (evento.target === overlay) fecharPopup();
  });
  btnFechar.addEventListener("click", fecharPopup);
  document.addEventListener("keydown", function (evento) {
    if (evento.key === "Escape" && !overlay.hidden) fecharPopup();
  });

  btnSalvar.addEventListener("click", function () {
    var titulo = popupTitulo.value.trim();
    if (!titulo) {
      popupStatus.textContent = "Título não pode ficar vazio.";
      popupStatus.className = "form-imovel__status form-imovel__status--erro";
      return;
    }
    popupStatus.textContent = "Salvando...";
    popupStatus.className = "form-imovel__status";
    fetch(url("/api/proximos-passos/" + popupId.value), {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ titulo: titulo, descricao: popupDescricao.value.trim() }),
    })
      .then(function (r) { return r.ok ? r.json() : r.json().then(function (d) { return Promise.reject(d); }); })
      .then(function () {
        popupStatus.textContent = "Salvo.";
        popupStatus.className = "form-imovel__status form-imovel__status--ok";
        carregar();
        setTimeout(fecharPopup, 500);
      })
      .catch(function (erro) {
        popupStatus.textContent = "Erro: " + (erro && (erro.detalhes || erro.erro) || "não salvou");
        popupStatus.className = "form-imovel__status form-imovel__status--erro";
      });
  });

  btnExcluir.addEventListener("click", function () {
    if (!confirm('Apagar o item "' + popupTitulo.value + '"?')) return;
    fetch(url("/api/proximos-passos/" + popupId.value), { method: "DELETE" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function () { fecharPopup(); carregar(); })
      .catch(function () {
        popupStatus.textContent = "Não consegui apagar. Tenta de novo.";
        popupStatus.className = "form-imovel__status form-imovel__status--erro";
      });
  });

  formNovo.addEventListener("submit", function (evento) {
    evento.preventDefault();
    var titulo = campoTitulo.value.trim();
    if (!titulo) return;
    fetch(url("/api/proximos-passos"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ titulo: titulo, descricao: campoDescricao.value.trim() }),
    })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function () {
        fecharFormNovo();
        carregar();
      })
      .catch(function () { alert("Não consegui adicionar. Tenta de novo."); });
  });

  if (!window.API_BASE) {
    lista.textContent = "config.js não define API_BASE.";
    return;
  }
  carregar();
})();
