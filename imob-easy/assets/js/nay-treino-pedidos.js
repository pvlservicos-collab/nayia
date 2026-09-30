/* =====================================================================
 * TREINAMENTO POR PEDIDO — Cérebro da Nay (30/09/2026)
 *
 * Pedro: "salve todas as solicitações do jeito que os corretores pedem e que
 * a Nay não teve 100% de certeza do que ele queria ... o pedido na esquerda e
 * um campo na direita para eu explicar; assim que eu explicar todos, clico em
 * salvar". Lê /admin/api/nai/treino-pedidos (senha do admin) e grava as
 * explicações de uma vez. Quem implementa depois é o Claude, lendo o estado
 * 'explicado'.
 * ===================================================================== */
(function () {
  "use strict";

  var lista = document.getElementById("tp-lista");
  if (!lista) return;

  var filtro = "novo";
  var itens = [];
  var NOME = { novo: "Para explicar", explicado: "Explicados", implementado: "Implementados", ignorado: "Ignorados", todos: "Todos" };

  function esc(v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pedir(qs, opcoes) {
    return fetch("/admin/api/nai/treino-pedidos" + (qs || ""), Object.assign({
      credentials: "same-origin", headers: { "Content-Type": "application/json" },
    }, opcoes || {})).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.erro || ("HTTP " + r.status));
        return d;
      });
    });
  }

  function desenharEstados(novos) {
    document.getElementById("tp-estados").innerHTML = ["novo", "explicado", "implementado", "ignorado", "todos"].map(function (e) {
      return '<button type="button" class="rs__estado" data-tp-estado="' + e + '" aria-pressed="' + (filtro === e) + '">' +
        NOME[e] + (e === "novo" && novos != null ? " <b>" + novos + "</b>" : "") + "</button>";
    }).join("");
  }

  function desenhar() {
    desenharEstados(itens.length && itens[0].novos != null ? itens[0].novos : null);
    if (!itens.length) {
      lista.innerHTML = '<p class="painel-nota">' + (filtro === "novo" ? "Nenhum pedido esperando explicação." : "Nada aqui.") + "</p>";
      return;
    }
    lista.innerHTML = itens.map(function (p) {
      var soLeitura = p.estado === "implementado" || p.estado === "ignorado";
      return '<div class="tp__linha" data-id="' + p.id + '">' +
        '<div class="tp__pedido">' +
          '<div class="tp__topo"><b>' + esc(p.quem || "corretor") + "</b> · " + esc(p.quando) +
            (p.motivos || []).map(function (m) { return ' <span class="rs__selo">' + esc(m) + "</span>"; }).join("") + "</div>" +
          '<div class="rs__balao rs__balao--ele">' + esc(p.texto) + "</div>" +
          (p.resposta ? '<div class="rs__balao rs__balao--ela">' + esc(p.resposta) + "</div>"
                      : '<div class="rs__sem-resposta">a Nay não respondeu</div>') +
        "</div>" +
        '<div class="tp__explica">' +
          '<textarea class="entrada" rows="5" data-tp-explicacao placeholder="Explique o que ela deveria ter entendido e respondido"' +
            (soLeitura ? " readonly" : "") + ">" + esc(p.explicacao || "") + "</textarea>" +
          (p.explicado_quando ? '<span class="ed__dica">Explicado por ' + esc(p.explicado_por || "") + " em " + esc(p.explicado_quando) + "</span>" : "") +
        "</div>" +
      "</div>";
    }).join("");
  }

  function carregar() {
    lista.innerHTML = '<p class="painel-nota">carregando…</p>';
    return pedir("?estado=" + encodeURIComponent(filtro)).then(function (d) {
      itens = Array.isArray(d) ? d : [];
      desenhar();
    }).catch(function (e) {
      lista.innerHTML = '<p class="painel-nota">Não consegui carregar (' + esc(e.message) + ").</p>";
    });
  }

  function salvar() {
    var recado = document.getElementById("tp-recado");
    var enviar = [];
    lista.querySelectorAll(".tp__linha").forEach(function (l) {
      var ta = l.querySelector("[data-tp-explicacao]");
      if (ta && !ta.readOnly && ta.value.trim()) enviar.push({ id: Number(l.dataset.id), explicacao: ta.value.trim() });
    });
    if (!enviar.length) { recado.textContent = "Nada para salvar: escreva ao menos uma explicação."; return; }
    recado.textContent = "Salvando…";
    pedir("", { method: "POST", body: JSON.stringify({ itens: enviar, por: (window.ADMIN_USUARIO || "painel") }) })
      .then(function (d) {
        recado.textContent = "Salvei " + d.gravados + " explicaç" + (d.gravados === 1 ? "ão" : "ões") + ". Agora é só me avisar para eu revisar e implementar.";
        return carregar();
      })
      .catch(function (e) { recado.textContent = "Não salvou: " + e.message; });
  }

  document.getElementById("tp-estados").addEventListener("click", function (e) {
    var b = e.target.closest("[data-tp-estado]");
    if (!b) return;
    filtro = b.dataset.tpEstado;
    carregar();
  });
  document.getElementById("tp-salvar").addEventListener("click", salvar);
  document.getElementById("tp-recarregar").addEventListener("click", carregar);

  carregar();
})();
