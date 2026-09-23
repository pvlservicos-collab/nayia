/* ==========================================================================
   Imob Easy — Tela Vagas do painel
   Lê de /admin/api/vagas/candidaturas, no PRÓPRIO domínio: o Traefik manda
   esse caminho para a API atrás da mesma senha do /admin, e o navegador
   reaproveita a senha já digitada. A API confere a senha de novo lá dentro.
   ========================================================================== */
(function () {
  "use strict";

  var ROTULOS = {
    experiencia_vendas: {
      nenhuma: "Nenhuma", menos_de_1_ano: "Menos de 1 ano",
      "1_a_3_anos": "1 a 3 anos", mais_de_3_anos: "Mais de 3 anos"
    },
    disponibilidade: { imediata: "Imediatamente", "15_dias": "Em 15 dias", "30_dias": "Em 30 dias" }
  };

  var ICONE_BAIXAR =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M12 4v12"/><path d="m7 11 5 5 5-5"/><path d="M4 20h16"/></svg>';

  var corpo = document.getElementById("vg-corpo");
  var aviso = document.getElementById("vg-aviso");

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  var fmtData = new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Manaus", day: "2-digit", month: "2-digit", year: "2-digit",
    hour: "2-digit", minute: "2-digit"
  });
  var fmtDia = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Manaus" });

  function telefoneBonito(d) {
    d = String(d || "");
    var n = d.indexOf("55") === 0 && d.length > 11 ? d.slice(2) : d;
    if (n.length === 11) return "(" + n.slice(0, 2) + ") " + n.slice(2, 3) + " " + n.slice(3, 7) + "-" + n.slice(7);
    if (n.length === 10) return "(" + n.slice(0, 2) + ") " + n.slice(2, 6) + "-" + n.slice(6);
    return d;
  }

  function tamanho(b) {
    b = Number(b) || 0;
    return b >= 1048576 ? (b / 1048576).toFixed(1).replace(".", ",") + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
  }

  function linkProfissional(v) {
    if (!v) return "";
    var s = String(v).trim();
    if (/^https?:\/\//i.test(s)) {
      return '<a class="vg-link" href="' + esc(s) + '" target="_blank" rel="noopener noreferrer">' + esc(s) + "</a>";
    }
    return esc(s);
  }

  function cartoes(lista) {
    var hoje = fmtDia.format(new Date());
    var semana = Date.now() - 7 * 864e5;
    document.getElementById("vg-total").textContent = lista.length;
    document.getElementById("vg-semana").textContent =
      lista.filter(function (c) { return new Date(c.criada_em).getTime() >= semana; }).length;
    document.getElementById("vg-hoje").textContent =
      lista.filter(function (c) { return fmtDia.format(new Date(c.criada_em)) === hoje; }).length;
    document.getElementById("vg-imob").textContent =
      lista.filter(function (c) { return c.experiencia_imobiliaria === "sim"; }).length;
  }

  function desenhar(lista) {
    cartoes(lista);
    if (!lista.length) {
      corpo.innerHTML =
        '<tr><td colspan="10" class="vg-vazio"><strong>Nenhuma candidatura ainda</strong>' +
        "Assim que alguém se candidatar em imobeasy.online/vagas-manaus, aparece aqui.</td></tr>";
      return;
    }
    corpo.innerHTML = lista.map(function (c) {
      var zap = String(c.whatsapp || "");
      var imob = c.experiencia_imobiliaria === "sim"
        ? '<span class="vg-tag vg-tag--sim">Sim</span>'
        : '<span class="vg-tag vg-tag--nao">Não</span>';
      var detalhe =
        '<tr class="vg-detalhe" id="vg-det-' + c.id + '" hidden><td colspan="10"><dl class="vg-detalhe__grade">' +
          "<div><dt>Bairro</dt><dd>" + (esc(c.bairro) || "—") + "</dd></div>" +
          "<div><dt>Por que seria um bom SDR</dt><dd>" + (esc(c.por_que) || "—") + "</dd></div>" +
          "<div><dt>LinkedIn / Instagram</dt><dd>" + (linkProfissional(c.linkedin) || "—") + "</dd></div>" +
          "<div><dt>Arquivo do currículo</dt><dd>" + esc(c.curriculo_nome) + " · " + tamanho(c.curriculo_bytes) + "</dd></div>" +
        "</dl></td></tr>";
      return (
        "<tr>" +
          "<td class=\"num\">" + esc(fmtData.format(new Date(c.criada_em))) + "</td>" +
          '<td><span class="vg-nome">' + esc(c.nome) + "</span>" +
            (c.bairro ? '<span class="vg-sub">' + esc(c.bairro) + "</span>" : "") + "</td>" +
          '<td><a class="vg-link" href="https://wa.me/' + esc(zap) + '" target="_blank" rel="noopener">' +
            esc(telefoneBonito(zap)) + "</a></td>" +
          '<td><a class="vg-link" href="mailto:' + esc(c.email) + '">' + esc(c.email) + "</a></td>" +
          '<td><span class="vg-tag">' + esc(ROTULOS.experiencia_vendas[c.experiencia_vendas] || c.experiencia_vendas) + "</span></td>" +
          "<td>" + imob + "</td>" +
          "<td>" + esc(ROTULOS.disponibilidade[c.disponibilidade] || c.disponibilidade) + "</td>" +
          "<td>" + (esc(c.pretensao_salarial) || "—") + "</td>" +
          '<td><a class="btn-azul-vazado vg-baixar" href="api/vagas/candidaturas/' + encodeURIComponent(c.id) +
            '/curriculo">' + ICONE_BAIXAR + "Baixar</a></td>" +
          '<td><button class="vg-mais" type="button" aria-expanded="false" aria-controls="vg-det-' + c.id +
            '" data-abre="' + c.id + '">Ver mais</button></td>' +
        "</tr>" + detalhe
      );
    }).join("");
  }

  corpo.addEventListener("click", function (e) {
    var b = e.target.closest("[data-abre]");
    if (!b) return;
    var linha = document.getElementById("vg-det-" + b.getAttribute("data-abre"));
    var abrir = linha.hidden;
    linha.hidden = !abrir;
    b.setAttribute("aria-expanded", String(abrir));
    b.textContent = abrir ? "Ver menos" : "Ver mais";
  });

  fetch("api/vagas/candidaturas", { credentials: "same-origin", cache: "no-store" })
    .then(function (r) {
      if (r.status === 401) throw new Error("401");
      if (!r.ok) throw new Error(String(r.status));
      return r.json();
    })
    .then(function (j) { desenhar(j.candidaturas || []); })
    .catch(function (err) {
      corpo.innerHTML = '<tr><td colspan="10" class="vg-vazio">Não foi possível carregar as candidaturas.</td></tr>';
      aviso.hidden = false;
      aviso.textContent = err.message === "401"
        ? "A senha do painel não foi aceita. Recarregue a página e entre de novo."
        : "Não consegui falar com o servidor (" + err.message + "). Tente recarregar a página.";
    });
})();
