/* ==========================================================================
   Imob Easy — MUDANÇAS RECENTES (aba de Imóveis) e ÚLTIMA ATUALIZAÇÃO (editar imóvel)

   Pedro, 13/10/2026: "quero que quando o proprietário afirme que o valor é o
   mesmo ou que está vendido, ela mude lá no nosso banco de dados mas de forma
   resetável ... vai surgir um campo lá na aba editar imóvel Última atualização
   e vai mostrar um mockup da mensagem que o proprietário mandou, e o que foi
   mudado, como um histórico do imóvel, ex De disponível para alugado ... na
   aba imóveis mais uma tab no final, Mudanças recentes, lá vai ter listado em
   cards horizontais todas as alterações, elas já são aprovadas e
   disponibilizadas à Nay automaticamente, mas nessa tela eu posso clicar em
   voltar atrás em cada mudança e organizar: já revisada, ou a revisar".

   A mudança já está valendo quando aparece aqui (quem aplica é o banco,
   captacao_aplicar_ao_cadastro, migração 361). Esta tela só mostra, volta
   atrás (e refaz) e separa o que já foi olhado. Nada é apagado.

   O mesmo arquivo serve as duas telas:
     · imoveis.html        -> a aba [data-painel="mudancas"]
     · imovel-editar.html  -> o bloco "Última atualização" + o histórico do imóvel
   ========================================================================== */
(function () {
  "use strict";

  var ROTA = "/admin/api/imoveis/mudancas";

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function semAcento(t) { return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  function quando(iso, comHora) {
    if (!iso) return "";
    var d = new Date(iso);
    if (isNaN(d)) return String(iso);
    var o = { timeZone: "America/Manaus", day: "2-digit", month: "2-digit" };
    if (comHora) { o.hour = "2-digit"; o.minute = "2-digit"; } else { o.year = "numeric"; }
    return d.toLocaleString("pt-BR", o).replace(",", " às");
  }
  function hora(iso) {
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleTimeString("pt-BR", { timeZone: "America/Manaus", hour: "2-digit", minute: "2-digit" });
  }
  function dia(iso) {
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR", { timeZone: "America/Manaus", day: "2-digit", month: "2-digit", year: "numeric" });
  }
  function dinheiro(v) {
    if (v == null || v === "") return "sem valor";
    var n = Number(v);
    return isNaN(n) ? String(v) : "R$ " + n.toLocaleString("pt-BR", { maximumFractionDigits: 0 });
  }
  function dataBr(v) {
    if (!v) return "sem data";
    var m = String(v).match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? m[3] + "/" + m[2] + "/" + m[1] : String(v);
  }

  /* ---- cada campo: o nome que a pessoa lê e como o valor aparece ---------- */
  var CAMPOS = {
    status: { nome: "Situação", ver: function (v) { return v == null || v === "" ? "sem situação" : String(v); }, atual: function (im) { return im.status; } },
    valor_aluguel: { nome: "Valor do aluguel", ver: dinheiro, atual: function (im) { return im.valor_aluguel; }, numero: true },
    valor_venda: { nome: "Valor de venda", ver: dinheiro, atual: function (im) { return im.valor_venda; }, numero: true },
    vencimento: { nome: "Contrato de locação até", ver: dataBr, atual: function (im) { return im.vencimento; } },
    publicado_no_site: { nome: "No site", ver: function (v) { return v === true || v === "true" ? "aparece no site" : "fora do site"; }, atual: function (im) { return im.publicado_no_site; } }
  };
  var ORDEM = ["status", "valor_aluguel", "valor_venda", "vencimento", "publicado_no_site"];
  function igual(def, a, b) {
    if (def.numero) return (a == null && b == null) || Number(a) === Number(b);
    return String(a == null ? "" : a) === String(b == null ? "" : b);
  }
  function corDaSituacao(s) {
    var t = semAcento(s);
    if (t.indexOf("dispon") === 0) return "mu-p--verde";
    if (t.indexOf("alugad") === 0) return "mu-p--azul";
    if (t.indexOf("vendid") === 0) return "mu-p--cinza";
    return "mu-p--neutro";
  }
  function pastilha(k, v) {
    var def = CAMPOS[k];
    var cls = k === "status" ? corDaSituacao(v) : "mu-p--neutro";
    return '<span class="mu-p ' + cls + '">' + esc(def.ver(v)) + "</span>";
  }

  /* ---- o estilo (variáveis do site: acompanha o tema dentro do CRM) ------- */
  var css = document.createElement("style");
  css.textContent =
    ".mu-topo{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:0 0 6px}" +
    ".mu-chip{height:34px;padding:0 14px;border-radius:999px;border:1px solid var(--borda-forte,#cabbe4);background:var(--superficie,#fff);color:var(--texto,#241d33);font:inherit;font-size:13.5px;font-weight:600;cursor:pointer}" +
    ".mu-chip b{margin-left:6px;font-weight:800}" +
    ".mu-chip[aria-pressed=true]{background:var(--roxo,#6d28d9);border-color:var(--roxo,#6d28d9);color:#fff}" +
    ".mu-busca{flex:1 1 220px;max-width:340px;height:34px;padding:0 12px;border:1px solid var(--borda-forte,#cabbe4);border-radius:999px;font:inherit;font-size:13.5px;background:var(--superficie,#fff);color:var(--texto,#241d33)}" +
    ".mu-todas{margin-left:auto;height:34px;padding:0 14px;border-radius:999px;border:1px solid var(--borda-forte,#cabbe4);background:var(--superficie,#fff);color:var(--texto,#241d33);font:inherit;font-size:13px;font-weight:600;cursor:pointer}" +
    ".mu-nota{font-size:12.5px;color:var(--texto-fraco,#5f5775);line-height:1.45;margin:0 0 14px}" +
    ".mu-vazio{padding:28px 16px;text-align:center;color:var(--texto-fraco,#5f5775);border:1px dashed var(--borda-forte,#cabbe4);border-radius:14px;background:var(--superficie,#fff)}" +
    ".mu-lista{display:flex;flex-direction:column;gap:12px}" +
    /* o card horizontal: imóvel | conversa | o que mudou */
    ".mu-card{display:grid;grid-template-columns:minmax(190px,230px) minmax(260px,1fr) minmax(280px,1.1fr);gap:0;border:1px solid var(--borda,#e3daf2);border-radius:14px;background:var(--superficie,#fff);color:var(--texto,#241d33);overflow:hidden}" +
    ".mu-card--desfeita{opacity:.82}" +
    ".mu-card--nao{border-style:dashed}" +
    ".mu-col{padding:14px 16px;min-width:0}" +
    ".mu-col+.mu-col{border-left:1px solid var(--borda,#e3daf2)}" +
    ".mu-cod{font-size:18px;font-weight:800;line-height:1.1}" +
    ".mu-cod a{color:inherit;text-decoration:none}" +
    ".mu-cod a:hover{text-decoration:underline}" +
    ".mu-onde{font-size:13px;color:var(--texto-medio,#4a4360);margin-top:4px;line-height:1.35}" +
    ".mu-dono{font-size:13px;font-weight:600;margin-top:10px}" +
    ".mu-quando{font-size:12px;color:var(--texto-fraco,#5f5775);margin-top:2px}" +
    ".mu-abrir{display:inline-block;margin-top:10px;font-size:12.5px;font-weight:600;color:var(--roxo,#6d28d9);text-decoration:none}" +
    /* a conversa, no desenho do WhatsApp (cores fixas: é um retrato da conversa) */
    ".mu-zap{background:#efeae2;border-radius:10px;padding:10px;max-height:210px;overflow-y:auto;display:flex;flex-direction:column;gap:4px}" +
    ".mu-b{max-width:86%;padding:6px 9px 4px;border-radius:8px;font-size:13px;line-height:1.35;color:#111b21;white-space:pre-wrap;overflow-wrap:anywhere;box-shadow:0 1px .5px rgba(11,20,26,.13)}" +
    ".mu-b--dono{align-self:flex-start;background:#fff;border-top-left-radius:2px}" +
    ".mu-b--nos{align-self:flex-end;background:#d9fdd3;border-top-right-radius:2px}" +
    ".mu-b small{display:block;text-align:right;font-size:10.5px;color:#667781;margin-top:1px}" +
    ".mu-b em{font-style:normal;font-weight:700;font-size:11px;color:#667781;display:block}" +
    ".mu-dia{align-self:center;font-size:11px;color:#54656f;background:#fff;border-radius:7px;padding:3px 9px;margin:2px 0;box-shadow:0 1px .5px rgba(11,20,26,.13)}" +
    ".mu-semzap{font-size:12.5px;color:var(--texto-fraco,#5f5775);font-style:italic}" +
    /* o que mudou */
    ".mu-tit{font-size:11px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:var(--texto-fraco,#5f5775);margin:0 0 8px}" +
    ".mu-linha{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin:0 0 7px;font-size:13.5px}" +
    ".mu-linha>b{flex:0 0 100%;font-size:12px;font-weight:700;color:var(--texto-medio,#4a4360)}" +
    ".mu-seta{color:var(--texto-fraco,#5f5775);font-weight:700}" +
    ".mu-p{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12.5px;font-weight:700;white-space:nowrap}" +
    ".mu-p--verde{background:#dcf5e7;color:#1c6b43}.mu-p--azul{background:#dfe9fb;color:#1f4fa3}.mu-p--cinza{background:#e6e3ea;color:#4a4360}.mu-p--neutro{background:#f1eaff;color:#4c1d95}" +
    ".mu-de{opacity:.72;text-decoration:line-through;text-decoration-thickness:1px}" +
    ".mu-depois{flex:0 0 100%;font-size:12px;color:#9a5b00;background:#fff4dc;border-radius:8px;padding:4px 8px}" +
    ".mu-obs{font-size:12.5px;line-height:1.4;color:var(--texto-medio,#4a4360);background:var(--superficie-2,#faf8fe);border:1px solid var(--borda,#e3daf2);border-radius:8px;padding:6px 9px;margin:0 0 6px}" +
    ".mu-selo{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:800;margin:0 0 8px}" +
    ".mu-selo--desfeita{background:#fde8e8;color:#a11d1d}.mu-selo--nao{background:#fff4dc;color:#8a5200}.mu-selo--ok{background:#dcf5e7;color:#1c6b43}.mu-selo--conf{background:#e6e3ea;color:#4a4360}" +
    ".mu-acoes{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}" +
    ".mu-bt{height:34px;padding:0 14px;border-radius:999px;border:1px solid var(--borda-forte,#cabbe4);background:var(--superficie,#fff);color:var(--texto,#241d33);font:inherit;font-size:13px;font-weight:700;cursor:pointer}" +
    ".mu-bt[disabled]{opacity:.5;cursor:default}" +
    ".mu-bt--voltar{border-color:#d97a7a;color:#a11d1d}" +
    ".mu-bt--ok{background:#16a34a;border-color:#16a34a;color:#fff}" +
    ".mu-erro{flex:0 0 100%;font-size:12.5px;color:#a11d1d}" +
    /* elemento com display proprio nao some so com hidden */
    ".mu-lista[hidden],.mu-erro[hidden],.mu-todas[hidden]{display:none!important}" +
    /* o bloco do editar */
    ".mu-ultima{margin:0 0 18px;padding:16px;border:1px solid var(--borda,#e3daf2);border-radius:16px;background:var(--superficie,#fff);color:var(--texto,#241d33)}" +
    ".mu-ultima h2{margin:0 0 4px;font-size:17px}" +
    ".mu-ultima .mu-card{grid-template-columns:minmax(240px,1fr) minmax(260px,1fr);border-radius:12px}" +
    ".mu-ultima .mu-lista{margin-top:10px}" +
    ".mu-mais{margin-top:10px;background:none;border:0;padding:0;font:inherit;font-size:13px;font-weight:700;color:var(--roxo,#6d28d9);cursor:pointer}" +
    "@media (max-width:900px){.mu-card,.mu-ultima .mu-card{grid-template-columns:1fr}.mu-col+.mu-col{border-left:0;border-top:1px solid var(--borda,#e3daf2)}.mu-todas{margin-left:0}}";
  document.head.appendChild(css);

  /* ---- o card ------------------------------------------------------------- */
  function conversa(it) {
    var ms = it.mensagens || [];
    if (!ms.length) return '<div class="mu-semzap">Sem conversa guardada para esta mudança.</div>';
    var h = '<div class="mu-zap" data-mu-zap>', ultimoDia = "";
    ms.forEach(function (m) {
      var d = dia(m.q);
      if (d && d !== ultimoDia) { h += '<div class="mu-dia">' + esc(d) + "</div>"; ultimoDia = d; }
      var doDono = m.d === "dono";
      var rotulo = doDono ? "" : (m.o === "humano" ? "<em>Equipe</em>" : "<em>Nay</em>");
      var midia = doDono && m.o && m.o !== "texto" ? "<em>" + esc(m.o === "audio" ? "áudio (transcrito)" : m.o) + "</em>" : "";
      h += '<div class="mu-b ' + (doDono ? "mu-b--dono" : "mu-b--nos") + '">' + rotulo + midia + esc(m.t) + "<small>" + esc(hora(m.q)) + "</small></div>";
    });
    return h + "</div>";
  }

  function oQueMudou(it) {
    var im = it.imovel || {}, h = "", desfeitos = it.desfeito_campos || [];
    if (it.tipo === "mudanca") {
      h += it.desfeito_em
        ? '<span class="mu-selo mu-selo--desfeita">Desfeita em ' + esc(quando(it.desfeito_em, true)) + (it.desfeito_por ? " · " + esc(it.desfeito_por) : "") + "</span>"
        : '<span class="mu-selo mu-selo--ok">Já está valendo</span>';
    } else if (it.tipo === "nao_aplicado") {
      h += '<span class="mu-selo mu-selo--nao">Não apliquei: precisa de gente</span>';
    } else {
      h += '<span class="mu-selo mu-selo--conf">Confirmou, nada mudou</span>';
    }
    ORDEM.forEach(function (k) {
      var c = (it.campos || {})[k], def = CAMPOS[k];
      if (!c) return;
      h += '<div class="mu-linha"><b>' + esc(def.nome) + '</b><span class="mu-de">' + pastilha(k, c.de) + '</span><span class="mu-seta">→</span>' + pastilha(k, c.para);
      var agora = def.atual(im);
      if (!it.desfeito_em && !igual(def, agora, c.para)) {
        h += '<span class="mu-depois">Mudado depois por outra pessoa: hoje está ' + esc(def.ver(agora)) + ". O voltar atrás não mexe neste campo.</span>";
      } else if (it.desfeito_em && desfeitos.indexOf(k) < 0) {
        h += '<span class="mu-depois">Este campo não voltou: já tinha sido mudado depois.</span>';
      }
      h += "</div>";
    });
    if (it.tipo === "confirmacao") {
      h += '<div class="mu-obs">O proprietário respondeu e o cadastro já estava igual ao que ele disse (situação ' +
        esc(CAMPOS.status.ver(im.status)) + ").</div>";
    }
    (it.notas || []).forEach(function (n) { h += '<div class="mu-obs">' + esc(n.charAt(0).toUpperCase() + n.slice(1)) + "</div>"; });
    return h;
  }

  function botoes(it) {
    var h = '<div class="mu-acoes">';
    if (it.tipo === "mudanca") {
      h += it.desfeito_em
        ? '<button type="button" class="mu-bt" data-mu-acao="refazer" data-mu-id="' + it.id + '">Refazer a mudança</button>'
        : '<button type="button" class="mu-bt mu-bt--voltar" data-mu-acao="voltar" data-mu-id="' + it.id + '">Voltar atrás</button>';
    }
    if (it.tipo !== "confirmacao") {
      h += it.revisado_em
        ? '<button type="button" class="mu-bt" data-mu-acao="a-revisar" data-mu-id="' + it.id + '">Devolver para "A revisar"</button>'
        : '<button type="button" class="mu-bt mu-bt--ok" data-mu-acao="revisada" data-mu-id="' + it.id + '">Já revisei</button>';
    }
    return h + '<span class="mu-erro" data-mu-erro hidden></span></div>';
  }

  function card(it, comImovel) {
    var im = it.imovel || {};
    var onde = [im.tipo, im.condominio, im.bairro].filter(Boolean).join(" · ");
    var cls = "mu-card" + (it.desfeito_em ? " mu-card--desfeita" : "") + (it.tipo === "nao_aplicado" ? " mu-card--nao" : "");
    var h = '<article class="' + cls + '" data-mu-card="' + it.id + '">';
    if (comImovel) {
      h += '<div class="mu-col"><div class="mu-cod"><a href="imovel-editar.html?codigo=' + it.codigo + '" target="_blank" rel="noopener">#' + it.codigo + "</a></div>" +
        '<div class="mu-onde">' + esc(onde || "imóvel sem descrição") + "</div>" +
        '<div class="mu-dono">' + esc(it.dono || "proprietário") + "</div>" +
        '<div class="mu-quando">' + (it.dito_em ? "disse em " + esc(quando(it.dito_em, true)) : "registrado em " + esc(quando(it.criado_em, true))) + "</div>" +
        '<a class="mu-abrir" href="imovel-editar.html?codigo=' + it.codigo + '" target="_blank" rel="noopener">Abrir o cadastro ↗</a></div>';
    }
    h += '<div class="mu-col">' + (comImovel ? "" : '<div class="mu-quando" style="margin:0 0 8px">' + esc(it.dono || "Proprietário") + " · " +
      esc(quando(it.dito_em || it.criado_em, true)) + "</div>") + conversa(it) + "</div>";
    h += '<div class="mu-col"><p class="mu-tit">O que mudou</p>' + oQueMudou(it) + botoes(it) + "</div>";
    return h + "</article>";
  }

  function rolarConversas(raiz) {
    raiz.querySelectorAll("[data-mu-zap]").forEach(function (z) { z.scrollTop = z.scrollHeight; });
  }

  function buscar(q) {
    return fetch(ROTA + (q ? "?" + q : ""), { credentials: "same-origin" }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    });
  }
  function agir(id, acao) {
    return fetch(ROTA + "/" + id + "/" + acao, { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: "{}" })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (d) { d.__ok = r.ok; return d; }); });
  }
  /* o clique dos botões, igual nas duas telas; `depois` recarrega a lista */
  function ligarBotoes(raiz, depois) {
    raiz.addEventListener("click", function (e) {
      var b = e.target.closest("[data-mu-acao]");
      if (!b || b.disabled) return;
      var acao = b.dataset.muAcao, id = b.dataset.muId;
      if (acao === "voltar" && !window.confirm("Voltar atrás nesta mudança? O cadastro volta a ficar como estava antes (dá para refazer depois).")) return;
      var cardEl = b.closest("[data-mu-card]"), erro = cardEl && cardEl.querySelector("[data-mu-erro]");
      b.disabled = true;
      agir(id, acao).then(function (d) {
        if (!d.__ok || d.ok === false) {
          var msg = d.erro || "Não consegui agora. Tente de novo.";
          if (d.pulado && d.pulado.length) msg += " (" + d.pulado.join("; ") + ")";
          if (erro) { erro.textContent = msg; erro.hidden = false; }
          b.disabled = false;
          return;
        }
        depois(acao);
      }).catch(function () {
        if (erro) { erro.textContent = "Sem resposta do servidor. Tente de novo."; erro.hidden = false; }
        b.disabled = false;
      });
    });
  }

  /* ========================================================================
     1. A ABA "MUDANÇAS RECENTES" (imoveis.html)
     ======================================================================== */
  var aba = document.querySelector('[data-painel-abre="mudancas"]');
  var painel = document.querySelector('[data-painel="mudancas"]');
  if (aba && painel) {
    var estado = "revisar", itens = [], filtro = "";
    painel.innerHTML =
      '<div class="mu-topo">' +
      '<button type="button" class="mu-chip" data-mu-estado="revisar" aria-pressed="true">A revisar <b data-mu-n="revisar">—</b></button>' +
      '<button type="button" class="mu-chip" data-mu-estado="revisadas" aria-pressed="false">Já revisadas <b data-mu-n="revisadas">—</b></button>' +
      '<input class="mu-busca" type="search" placeholder="Buscar código, condomínio ou proprietário" aria-label="Buscar nas mudanças">' +
      '<button type="button" class="mu-todas" data-mu-todas>Marcar todas da tela como revisadas</button>' +
      "</div>" +
      '<p class="mu-nota">O que o proprietário respondeu à Nay e que já mudou o cadastro. A mudança entra sozinha e já vale para a Nay; aqui dá para voltar atrás em cada uma (e refazer). Nada é apagado.</p>' +
      '<div class="mu-lista" data-mu-lista><div class="mu-vazio">Carregando…</div></div>';
    var lista = painel.querySelector("[data-mu-lista]");
    var campoBusca = painel.querySelector(".mu-busca");
    var btTodas = painel.querySelector("[data-mu-todas]");

    function visiveis() {
      var f = semAcento(filtro).trim();
      if (!f) return itens;
      return itens.filter(function (it) {
        var im = it.imovel || {};
        return semAcento([it.codigo, it.dono, im.condominio, im.bairro, im.tipo].join(" ")).indexOf(f) >= 0;
      });
    }
    function desenhar() {
      var v = visiveis();
      btTodas.hidden = estado !== "revisar" || !v.length;
      if (!v.length) {
        lista.innerHTML = '<div class="mu-vazio">' + (filtro ? "Nada com essa busca." :
          estado === "revisar" ? "Nada para revisar: tudo o que os proprietários responderam já foi olhado." : "Nenhuma mudança revisada ainda.") + "</div>";
        return;
      }
      lista.innerHTML = v.map(function (it) { return card(it, true); }).join("");
      rolarConversas(lista);
    }
    function contar(c) {
      c = c || {};
      ["revisar", "revisadas"].forEach(function (k) {
        painel.querySelectorAll('[data-mu-n="' + k + '"]').forEach(function (b) { b.textContent = c[k] == null ? "—" : c[k]; });
      });
      var n = aba.querySelector("[data-mu-conta]");
      if (n) n.textContent = c.revisar == null ? "—" : c.revisar;
    }
    function carregar() {
      return buscar("estado=" + estado).then(function (d) {
        itens = d.itens || [];
        contar(d.contagem);
        desenhar();
      }).catch(function () {
        lista.innerHTML = '<div class="mu-vazio">Não consegui carregar as mudanças. Atualize a página.</div>';
      });
    }

    painel.addEventListener("click", function (e) {
      var c = e.target.closest("[data-mu-estado]");
      if (c) {
        estado = c.dataset.muEstado;
        painel.querySelectorAll("[data-mu-estado]").forEach(function (x) { x.setAttribute("aria-pressed", String(x === c)); });
        lista.innerHTML = '<div class="mu-vazio">Carregando…</div>';
        carregar();
        return;
      }
      if (e.target.closest("[data-mu-todas]")) {
        var ids = visiveis().map(function (it) { return it.id; });
        if (!ids.length || !window.confirm("Marcar as " + ids.length + " mudanças da tela como revisadas?")) return;
        btTodas.disabled = true;
        fetch(ROTA + "/revisar-todas", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ids: ids }) })
          .then(function () { btTodas.disabled = false; carregar(); })
          .catch(function () { btTodas.disabled = false; });
      }
    });
    campoBusca.addEventListener("input", function () { filtro = campoBusca.value; desenhar(); });
    ligarBotoes(lista, carregar);
    aba.addEventListener("click", carregar);
    carregar();   // a bolinha da aba já mostra quantas esperam
  }

  /* ========================================================================
     2. "ÚLTIMA ATUALIZAÇÃO" (imovel-editar.html)
     ======================================================================== */
  var cartoes = document.getElementById("ed-cartoes");
  var codigo = Number(new URLSearchParams(location.search).get("codigo"));
  if (cartoes && codigo) {
    var bloco = document.createElement("section");
    bloco.className = "mu-ultima";
    bloco.id = "ed-ultima-atualizacao";
    bloco.innerHTML = '<h2>Última atualização</h2><p class="mu-nota" style="margin:0">Carregando…</p>';
    cartoes.parentNode.insertBefore(bloco, cartoes);
    var aberto = false;

    var carregarHistorico = function () {
      return buscar("codigo=" + codigo).then(function (d) {
        var its = d.itens || [];
        if (!its.length) {
          bloco.innerHTML = '<h2>Última atualização</h2><p class="mu-nota" style="margin:0">Nenhuma resposta do proprietário mudou este cadastro até agora. Quando ele responder à Nay (situação, valor, fim do contrato), a mudança aparece aqui com a conversa.</p>';
          return;
        }
        var resto = its.slice(1);
        bloco.innerHTML = '<h2>Última atualização</h2>' +
          '<p class="mu-nota" style="margin:0">O que o proprietário respondeu à Nay e o que mudou neste cadastro. Dá para voltar atrás; nada é apagado.</p>' +
          '<div class="mu-lista">' + card(its[0], false) + "</div>" +
          (resto.length
            ? '<button type="button" class="mu-mais" data-mu-mais>' + (aberto ? "Esconder o histórico" : "Ver o histórico do imóvel (" + resto.length + " anterior" + (resto.length > 1 ? "es" : "") + ")") + "</button>" +
              '<div class="mu-lista" data-mu-resto' + (aberto ? "" : " hidden") + ">" + resto.map(function (it) { return card(it, false); }).join("") + "</div>"
            : "");
        rolarConversas(bloco);
      }).catch(function () {
        bloco.innerHTML = '<h2>Última atualização</h2><p class="mu-nota" style="margin:0">Não consegui carregar o histórico deste imóvel.</p>';
      });
    };
    bloco.addEventListener("click", function (e) {
      var m = e.target.closest("[data-mu-mais]");
      if (!m) return;
      aberto = !aberto;
      var r = bloco.querySelector("[data-mu-resto]");
      if (r) { r.hidden = !aberto; if (aberto) rolarConversas(r); }
      m.textContent = aberto ? "Esconder o histórico" : "Ver o histórico do imóvel";
    });
    /* depois de voltar atrás o cadastro mudou por baixo do formulário: recarrega a página para ele mostrar o valor certo */
    ligarBotoes(bloco, function (acao) { if (acao === "voltar" || acao === "refazer") location.reload(); else carregarHistorico(); });
    carregarHistorico();
  }
})();
