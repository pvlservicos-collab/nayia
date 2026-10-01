/* ==========================================================================
   Imob Easy — Aba CADASTRO PENDENTE de Todos os imóveis

   Pedido do Pedro (01/10/2026): "cria a ferramenta completa de cadastro de
   imóveis importando tudo direitinho, e lá em imóveis cria uma aba CADASTRO
   PENDENTE e põe lá esses para cadastro por humano".

   O que cai aqui (migração 248, com o motivo escrito em cada linha):
     · pré-cadastro (Rascunho) — inclui o que entra pela OLX;
     · bloqueado: está Disponível mas a Nay não oferece;
     · no ar sem nenhuma foto;
     · no ar faltando campo ESSENCIAL (tipo, bairro, valor, foto, dono...);
     · foto em link de fora (o da Z-API expira e nem passa na conferência do envio);
     · a ficha que o dono ditou na captação e ninguém aplicou;
     · e a ficha de imóvel NOVO, que nem existe no cadastro ainda.

   "Importar tudo" não digita nada à mão: baixa a foto de fora para o nosso
   servidor e puxa a ficha da conversa, o condomínio, o endereço dele e o
   proprietário — só em campo VAZIO, nunca por cima do que uma pessoa escreveu.
   A situação do imóvel não é tocada: publicar continua sendo decisão de gente,
   no editor.
   ========================================================================== */
(function () {
  "use strict";

  var aba = document.querySelector('[data-painel-abre="pendentes"]');
  var painel = document.querySelector('[data-painel="pendentes"]');
  if (!aba || !painel) return;

  var corpo = document.getElementById("cp-corpo");
  var busca = document.getElementById("cp-busca");
  var filtro = document.getElementById("cp-filtro");
  var resumo = document.getElementById("cp-resumo");
  var itens = null;

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function semAcento(t) {
    return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }
  function cor(p) { return p >= 90 ? "#3f9c6d" : p >= 50 ? "#c4762f" : "#b42323"; }

  var css = document.createElement("style");
  css.textContent =
    ".cp-barra{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:0 0 10px}" +
    ".cp-barra input,.cp-barra select{height:34px;padding:0 8px;border:1px solid var(--borda,#d8dae0);border-radius:8px;font:inherit}" +
    ".cp-barra input{min-width:260px}" +
    ".cp-resumo{color:var(--texto-fraco,#6b7280);font-size:13px}" +
    ".cp-motivo{display:block;font-size:12.5px;line-height:1.35;color:#8a4b00}" +
    ".cp-motivo--grave{color:#b42323}" +
    ".cp-barrinha{display:inline-block;width:70px;height:6px;border-radius:4px;background:#e7e9ee;overflow:hidden;vertical-align:middle;margin-right:6px}" +
    ".cp-barrinha>i{display:block;height:100%;border-radius:4px}" +
    ".cp-acoes{display:flex;gap:6px;flex-wrap:wrap}" +
    ".cp-btn{height:30px;padding:0 10px;border-radius:999px;border:1px solid var(--borda,#d8dae0);background:#fff;font:inherit;font-size:12.5px;cursor:pointer}" +
    ".cp-btn--azul{border-color:#2563eb;color:#2563eb;font-weight:600}" +
    ".cp-btn[disabled]{opacity:.55;cursor:default}" +
    ".cp-feito{font-size:12.5px;color:#1d7a46;display:block;margin-top:4px}" +
    ".cp-erro{font-size:12.5px;color:#b42323;display:block;margin-top:4px}" +
    ".cp-ficha{font-size:12.5px;color:var(--texto-fraco,#6b7280)}";
  document.head.appendChild(css);

  var ROTULO = { ficha: "Ficha da conversa (imóvel não cadastrado)" };

  function resumoDaFicha(d) {
    if (!d) return "";
    return Object.keys(d).filter(function (k) {
      return d[k] !== null && d[k] !== undefined && String(d[k]).trim() !== "";
    }).slice(0, 8).map(function (k) { return k + ": " + String(d[k]).slice(0, 40); }).join(" · ");
  }

  function linha(it) {
    var id = it.fonte === "ficha" ? "f" + it.fichaId : "i" + it.codigo;
    var grave = it.motivos.some(function (m) { return /essencial|sem nenhuma foto|bloqueado/.test(m); });
    var pct = it.pct == null ? null : Number(it.pct);
    return '<tr data-id="' + id + '">' +
      "<td>" +
        "<b>" + esc(it.titulo) + "</b><br>" +
        '<span class="sub">' +
          (it.codigo ? "#" + it.codigo + " · " : ROTULO.ficha + " · ") +
          esc([it.tipo, it.bairro, it.status, it.origem && "origem " + it.origem].filter(Boolean).join(" · ")) +
          (it.dono ? " · dono: " + esc(it.dono) : "") +
        "</span>" +
        (it.fonte === "ficha" ? '<div class="cp-ficha">' + esc(resumoDaFicha(it.dados)) + "</div>" : "") +
      "</td>" +
      "<td>" + (pct == null ? '<span class="sub">—</span>'
        : '<span class="cp-barrinha"><i style="width:' + pct + "%;background:" + cor(pct) + '"></i></span>' +
          '<b style="color:' + cor(pct) + '">' + pct + "%</b>" +
          (it.falta.length ? '<div class="sub">falta ' + esc(it.falta.slice(0, 3).join(", ")) +
            (it.falta.length > 3 ? " +" + (it.falta.length - 3) : "") + "</div>" : "")) +
      "</td>" +
      "<td>" + it.motivos.map(function (m) {
        return '<span class="cp-motivo' + (grave ? " cp-motivo--grave" : "") + '">• ' + esc(m) + "</span>";
      }).join("") + "</td>" +
      '<td><div class="cp-acoes">' +
        (it.codigo
          ? '<button class="cp-btn cp-btn--azul" type="button" data-importar="' + it.codigo + '">Importar tudo</button>' +
            '<a class="cp-btn" href="imovel-editar.html?codigo=' + it.codigo + '">Abrir no editor</a>'
          : '<span class="sub">Cadastre pelo card da captação no CRM: ele já leva a ficha e as fotos da conversa.</span>') +
      '</div><span class="cp-estado"></span></td>' +
      "</tr>";
  }

  function pintar() {
    if (!itens) return;
    var q = semAcento(busca.value.trim());
    var f = filtro.value;
    var vistos = itens.filter(function (it) {
      if (f === "ficha" && it.fonte !== "ficha") return false;
      if (f === "rascunho" && !it.motivos.some(function (m) { return /Rascunho/.test(m); })) return false;
      if (f === "essencial" && !it.motivos.some(function (m) { return /essencial/.test(m); })) return false;
      if (f === "foto" && !it.motivos.some(function (m) { return /foto/.test(m); })) return false;
      if (f === "bloqueado" && !it.motivos.some(function (m) { return /bloqueado/.test(m); })) return false;
      if (!q) return true;
      return semAcento([it.titulo, it.codigo, it.bairro, it.tipo, it.origem, it.dono,
                        it.motivos.join(" ")].join(" ")).indexOf(q) >= 0;
    });
    resumo.textContent = vistos.length + " de " + itens.length + " esperando gente";
    corpo.innerHTML = vistos.length
      ? vistos.map(linha).join("")
      : '<tr><td colspan="4">Nada aqui — o cadastro está em dia.</td></tr>';
  }

  function importar(codigo, botao) {
    var tr = botao.closest("tr");
    var estado = tr.querySelector(".cp-estado");
    botao.disabled = true;
    botao.textContent = "Importando…";
    estado.innerHTML = "";
    fetch("/admin/api/imoveis/" + codigo + "/importar", { method: "POST", credentials: "same-origin" })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok) throw new Error(d.detalhe || d.erro || "HTTP " + r.status);
          return d;
        });
      })
      .then(function (d) {
        var entrou = (d.entraram || []);
        var partes = [];
        if (d.fotosImportadas) partes.push(d.fotosImportadas + " foto(s) trazida(s) para o nosso servidor");
        if (entrou.length) partes.push("entrou: " + entrou.join(", "));
        if (d.pct_antes !== d.pct_depois) partes.push(d.pct_antes + "% → " + d.pct_depois + "%");
        estado.innerHTML = '<span class="cp-feito">' +
          (partes.length ? esc(partes.join(" · ")) : "não havia nada para puxar: o resto é digitar no editor") +
          "</span>" +
          ((d.fotosErro || []).length ? '<span class="cp-erro">foto que não veio: ' + esc(d.fotosErro.join("; ")) + "</span>" : "");
        botao.textContent = "Importar de novo";
        botao.disabled = false;
        itens = null;                      // a lista muda: recarrega ao trocar de filtro
      })
      .catch(function (e) {
        estado.innerHTML = '<span class="cp-erro">' + esc(e.message || "não deu") + "</span>";
        botao.textContent = "Importar tudo";
        botao.disabled = false;
      });
  }

  function carregar() {
    if (itens) return;
    corpo.innerHTML = '<tr><td colspan="4">Carregando…</td></tr>';
    fetch("/admin/api/imoveis/cadastro-pendente", { credentials: "same-origin" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) { itens = d.itens || []; pintar(); })
      .catch(function () {
        corpo.innerHTML = '<tr><td colspan="4">Não foi possível carregar a lista (a senha do /admin é necessária).</td></tr>';
      });
  }

  aba.addEventListener("click", carregar);
  busca.addEventListener("input", function () { if (!itens) carregar(); else pintar(); });
  filtro.addEventListener("change", function () { if (!itens) carregar(); else pintar(); });
  corpo.addEventListener("click", function (e) {
    var b = e.target.closest("[data-importar]");
    if (b) importar(b.getAttribute("data-importar"), b);
  });
})();
