/* =====================================================================
 * REGRAS SUGERIDAS — Cérebro da Nay (28/09/2026)
 *
 * Tel (27/09): "vc vai analisar todas as regras de hoje, e ver as conversas
 * para ver o que a nay não entenderia hoje... e vai me sugerir regras
 * novas... ao clicar na regra aparece um popup com a conversa que ela veio".
 * Pedro (28/09): "não achei no site, se não tem põe lá".
 *
 * Fala com /admin/api (mesmo domínio): os casos são conversas de corretores
 * de verdade, e só passam com a senha do admin. Aceitar só MARCA a regra
 * para implementar -- a Nay muda quando ela entra no prompt ou nas funções.
 * ===================================================================== */
(function () {
  "use strict";

  var lista = document.getElementById("rs-lista");
  if (!lista) return;

  var popup = document.getElementById("rs-popup");
  var todas = [];
  var filtro = "sugerida";   // começa no que falta decidir
  var aberta = null;

  var NOME_ESTADO = { sugerida: "Para decidir", aceita: "Aceitas", recusada: "Recusadas", todas: "Todas" };
  var NOME_IMPORTANCIA = { alta: "Alta", media: "Média", baixa: "Baixa" };
  var NOME_TIPO = { parede: "Parede", fluxo: "Fluxo", ajuste: "Ajuste", defeito: "Defeito" };

  function esc(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function pedir(rota, opcoes) {
    return fetch("/admin/api/nai/regras-sugeridas" + (rota || ""), Object.assign({
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
    }, opcoes || {})).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (d) {
        if (!r.ok) throw new Error(d.erro || ("HTTP " + r.status));
        return d;
      });
    });
  }

  /* ---- a lista ------------------------------------------------------- */
  function desenharEstados() {
    var conta = { sugerida: 0, aceita: 0, recusada: 0, todas: todas.length };
    todas.forEach(function (s) { conta[s.estado] = (conta[s.estado] || 0) + 1; });
    document.getElementById("rs-estados").innerHTML = ["sugerida", "aceita", "recusada", "todas"].map(function (e) {
      return '<button type="button" class="rs__estado" data-rs-estado="' + e + '" aria-pressed="' +
        (filtro === e) + '">' + NOME_ESTADO[e] + " <b>" + conta[e] + "</b></button>";
    }).join("");
  }

  function selos(s) {
    return '<span class="rs__selo rs__selo--' + esc(s.importancia) + '">' + esc(NOME_IMPORTANCIA[s.importancia] || s.importancia) + "</span>" +
      '<span class="rs__selo">' + esc(NOME_TIPO[s.tipo] || s.tipo) + "</span>" +
      (s.estado !== "sugerida"
        ? '<span class="rs__selo rs__selo--' + esc(s.estado) + '">' + (s.estado === "aceita" ? "Aceita" : "Recusada") + "</span>"
        : "");
  }

  function desenharLista() {
    desenharEstados();
    var visiveis = todas.filter(function (s) { return filtro === "todas" || s.estado === filtro; });
    if (!visiveis.length) {
      lista.innerHTML = '<p class="painel-nota">' + (filtro === "sugerida"
        ? "Nenhuma sugestão esperando decisão."
        : "Nada aqui.") + "</p>";
      return;
    }
    var porCategoria = {};
    var ordem = [];
    visiveis.forEach(function (s) {
      if (!porCategoria[s.categoria]) { porCategoria[s.categoria] = []; ordem.push(s.categoria); }
      porCategoria[s.categoria].push(s);
    });
    lista.innerHTML = ordem.map(function (cat) {
      return '<section class="rs__grupo"><h3 class="secao-titulo">' + esc(cat) +
        ' <span class="rs__conta">' + porCategoria[cat].length + "</span></h3>" +
        '<div class="rs__cartoes">' + porCategoria[cat].map(function (s) {
          return '<button type="button" class="rs__cartao" data-rs-abrir="' + s.id + '">' +
            '<span class="rs__selos">' + selos(s) + "</span>" +
            '<span class="rs__titulo">' + esc(s.titulo) + "</span>" +
            '<span class="rs__regra">' + esc(s.regra) + "</span>" +
            '<span class="rs__rodape">' + s.casos + " conversa" + (s.casos === 1 ? "" : "s") +
              (s.janela_de ? " · de " + esc(s.janela_de) + " a " + esc(s.janela_ate) : "") +
              (s.decidido_em ? " · decidida em " + esc(s.decidido_em) : "") + "</span>" +
          "</button>";
        }).join("") + "</div></section>";
    }).join("");
  }

  function carregar() {
    return pedir("").then(function (d) {
      todas = Array.isArray(d) ? d : [];
      desenharLista();
    }).catch(function (e) {
      lista.innerHTML = '<p class="painel-nota">Não consegui carregar as sugestões (' + esc(e.message) + ").</p>";
    });
  }

  /* ---- o popup ------------------------------------------------------- */
  function bloco(titulo, texto) {
    return texto ? '<div class="rs__bloco"><h4>' + titulo + "</h4><p>" + esc(texto) + "</p></div>" : "";
  }

  function abrir(id) {
    var s = todas.filter(function (x) { return String(x.id) === String(id); })[0];
    if (!s) return;
    aberta = s;
    document.getElementById("rs-popup-titulo").textContent = s.titulo;
    document.getElementById("rs-popup-selos").innerHTML = selos(s);
    document.getElementById("rs-nota").value = s.nota_do_tel || "";
    document.getElementById("rs-recado").textContent = s.decidido_em
      ? (s.estado === "aceita" ? "Aceita" : "Recusada") + " em " + s.decidido_em : "";
    document.getElementById("rs-desfazer").hidden = s.estado === "sugerida";
    var corpo = document.getElementById("rs-popup-corpo");
    corpo.innerHTML =
      bloco("A regra", s.regra) +
      bloco("O que ela passa a fazer", s.o_que_faz) +
      bloco("Por que eu sugeri", s.porque) +
      '<div class="rs__bloco"><h4>As conversas (' + s.casos + ')</h4><div id="rs-casos" class="painel-nota">carregando…</div></div>';
    if (popup.showModal) popup.showModal(); else popup.setAttribute("open", "");

    pedir("/" + s.id + "/casos").then(function (casos) {
      if (!aberta || aberta.id !== s.id) return;
      document.getElementById("rs-casos").className = "rs__casos";
      document.getElementById("rs-casos").innerHTML = casos.length ? casos.map(function (c) {
        return '<div class="rs__caso">' +
          '<div class="rs__caso-topo"><b>' + esc(c.quem || "corretor") + "</b>" +
            (c.quando ? " · " + esc(c.quando) : "") + "</div>" +
          '<div class="rs__balao rs__balao--ele">' + esc(c.ele_disse || "—") + "</div>" +
          (c.ela_disse
            ? '<div class="rs__balao rs__balao--ela">' + esc(c.ela_disse) + "</div>"
            : '<div class="rs__sem-resposta">a Nay não respondeu</div>') +
          (c.o_ponto ? '<div class="rs__ponto">' + esc(c.o_ponto) + "</div>" : "") +
        "</div>";
      }).join("") : "Nenhuma conversa gravada para esta sugestão.";
    }).catch(function (e) {
      var alvo = document.getElementById("rs-casos");
      if (alvo) alvo.textContent = "Não consegui carregar as conversas (" + e.message + ").";
    });
  }

  function fechar() {
    aberta = null;
    if (popup.close) popup.close(); else popup.removeAttribute("open");
  }

  function decidir(estado) {
    if (!aberta) return;
    var recado = document.getElementById("rs-recado");
    recado.textContent = "gravando…";
    var s = aberta;
    pedir("/" + s.id, {
      method: "PUT",
      body: JSON.stringify({ estado: estado, nota: document.getElementById("rs-nota").value, por: "painel" }),
    }).then(function () {
      return carregar();
    }).then(function () {
      recado.textContent = estado === "aceita" ? "Aceita. Ela entra na Nay quando for implementada."
        : estado === "recusada" ? "Recusada." : "Voltou para sugerida.";
      var nova = todas.filter(function (x) { return x.id === s.id; })[0];
      if (nova) {
        aberta = nova;
        document.getElementById("rs-popup-selos").innerHTML = selos(nova);
        document.getElementById("rs-desfazer").hidden = nova.estado === "sugerida";
      }
    }).catch(function (e) {
      recado.textContent = "Não gravou: " + e.message;
    });
  }

  /* ---- cliques ------------------------------------------------------- */
  document.addEventListener("click", function (e) {
    var alvo = e.target.closest ? e.target : null;
    if (!alvo) return;
    var est = alvo.closest("[data-rs-estado]");
    if (est) { filtro = est.getAttribute("data-rs-estado"); desenharLista(); return; }
    var abre = alvo.closest("[data-rs-abrir]");
    if (abre) { abrir(abre.getAttribute("data-rs-abrir")); return; }
    var dec = alvo.closest("[data-rs-decidir]");
    if (dec) { decidir(dec.getAttribute("data-rs-decidir")); return; }
    if (alvo.closest("#rs-fechar")) { fechar(); return; }
    if (alvo.closest("#rs-recarregar")) { carregar(); return; }
    // clique no fundo escuro do popup fecha
    if (alvo === popup) fechar();
  });

  carregar();
})();
