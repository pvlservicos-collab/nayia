/* ==========================================================================
   RELATÓRIOS › AS ETIQUETAS DO WHATSAPP LEADS (426; Pedro, 20/10/2026)
   "salve todos esses leads lá no site na aba relatório, vai ser uma tabela com cada contato em cada uma das etapas que
   tem aí no de captação (leads)". A foto guardada de quem estava em cada etiqueta (Não respondeu, Alugado, Disponível,
   ...) quando as abas do CRM viraram as etapas. Rota com senha (tem telefone): /admin/api/relatorio/etiquetas-leads.
   ========================================================================== */
(function () {
  "use strict";
  var caixa = document.getElementById("relatorio-etiquetas");
  if (!caixa) return;
  var dados = null;

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function fone(t) {
    var d = String(t || "").replace(/\D/g, "");
    if (d.length >= 12 && d.indexOf("55") === 0) d = d.slice(2);
    return d.length === 11 ? "(" + d.slice(0, 2) + ") " + d.slice(2, 7) + "-" + d.slice(7) : (t || "");
  }
  function quando(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return isNaN(d) ? "—" : d.toLocaleDateString("pt-BR", { timeZone: "America/Manaus" }) + " " +
      d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Manaus" });
  }

  function desenhar() {
    var d = dados || {};
    var f = d.foto;
    if (!f) { caixa.innerHTML = '<p class="painel-nota">Nenhuma foto guardada ainda.</p>'; return; }
    var h = '<p class="painel-nota">Foto de <b>' + esc(quando(f.tirada_em)) + "</b>: " + esc(d.contatos) +
      " contatos do WhatsApp Leads em " + (d.etiquetas || []).length + " etiquetas. " + esc(f.observacao || "") +
      ". Quem tem duas etiquetas aparece nas duas. No CRM nada foi apagado: as etiquetas continuam nos contatos.</p>";
    if ((d.fotos || []).length > 1) {
      h += '<label class="painel-nota">Outra foto: <select class="selecao" id="re-foto">' + d.fotos.map(function (x) {
        return '<option value="' + x.id + '"' + (x.id === f.id ? " selected" : "") + ">" + esc(quando(x.tirada_em)) + "</option>";
      }).join("") + "</select></label>";
    }
    h += '<p><button type="button" class="btn-azul-vazado" id="re-csv">Baixar tudo (CSV)</button></p>';
    (d.etiquetas || []).forEach(function (e) {
      h += '<details class="re-etiqueta" style="margin:8px 0;border:1px solid var(--borda,#e3e6ea);border-radius:10px;padding:8px 12px">' +
        '<summary style="cursor:pointer;font-weight:600">' + esc(e.etiqueta) + " <span style=\"color:var(--texto-fraco);font-weight:400\">(" + e.n + ")</span></summary>" +
        '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela"><thead><tr>' +
        '<th scope="col">Contato</th><th scope="col">Telefone</th><th scope="col">Última atividade</th><th scope="col">No CRM desde</th>' +
        "</tr></thead><tbody>" + (e.contatos || []).map(function (c) {
          return "<tr><td>" + esc(c.nome || "(sem nome)") + "</td><td>" + esc(fone(c.telefone)) + "</td><td>" + esc(quando(c.ultima)) +
            "</td><td>" + esc(quando(c.criado)) + "</td></tr>";
        }).join("") + "</tbody></table></div></div></details>";
    });
    caixa.innerHTML = h;
  }

  function csv() {
    var linhas = [["etiqueta", "contato", "telefone", "ultima_atividade", "no_crm_desde"]];
    ((dados || {}).etiquetas || []).forEach(function (e) {
      (e.contatos || []).forEach(function (c) { linhas.push([e.etiqueta, c.nome || "", fone(c.telefone), quando(c.ultima), quando(c.criado)]); });
    });
    var texto = linhas.map(function (l) {
      return l.map(function (v) { return '"' + String(v).replace(/"/g, '""') + '"'; }).join(";");
    }).join("\r\n");
    var a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob(["﻿" + texto], { type: "text/csv;charset=utf-8" }));
    a.download = "etiquetas-whatsapp-leads.csv";
    document.body.appendChild(a); a.click(); a.remove();
  }

  function carregar(foto) {
    caixa.innerHTML = '<p class="painel-nota">Carregando…</p>';
    fetch("/admin/api/relatorio/etiquetas-leads" + (foto ? "?foto=" + encodeURIComponent(foto) : ""), { credentials: "same-origin" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (d) { dados = d; desenhar(); })
      .catch(function (e) { caixa.innerHTML = '<p class="painel-nota">Não carregou: ' + esc(e.message) + "</p>"; });
  }

  caixa.addEventListener("click", function (e) { if (e.target.closest("#re-csv")) csv(); });
  caixa.addEventListener("change", function (e) { if (e.target.id === "re-foto") carregar(e.target.value); });
  carregar();
})();
