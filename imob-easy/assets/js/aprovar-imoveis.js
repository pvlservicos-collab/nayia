/* ==========================================================================
   IMÓVEIS › APROVAR IMÓVEIS (419; Pedro, 19/10/2026)
   "liste todos os imóveis que os proprietários mandaram pelo WhatsApp ou confirmaram a autorização pela OLX e hoje
   ainda não estão disponíveis para a gente ... põe lá a origem, todos os dados que temos, igual no cadastro rápido,
   mas esse quero só esses da lista, com uma opção de editar cada campo".

   A lista: GET /admin/api/imoveis/aprovar (site_aprovar_imoveis). Três fontes:
     ficha   o dono ditou na conversa do WhatsApp (campos que a IA preparou)
     bot     o bot da OLX mandou com a autorização do dono
     imovel  já é cadastro e não está Disponível (pré-cadastro, atualização do dono, dono disse "disponível")
   Editar um campo = PUT /admin/api/imoveis/<código> {campo}. A ficha e o envio do bot ainda não são imóvel: no
   primeiro editar (ou no aprovar) viram PRÉ-CADASTRO (Rascunho, fora do site e da Nay) pelas rotas de sempre:
     ficha -> GET da-ficha/<id> -> POST /admin/api/imoveis -> POST /admin/api/imoveis/juntar (fotos e dono da ficha)
     bot   -> POST /admin/api/imoveis/olx-bot/<id>/aprovar -> o dono pelo PUT e as fotos por /imoveis/olx/<cód>/foto
   Aprovar = PUT {status: "Disponível"} (sem foto, o servidor deixa fora do site até ganhar foto).
   Tirar da lista = POST /admin/api/imoveis/aprovar/tirar (não muda a origem; volta pelo "Mostrar os tirados").
   ========================================================================== */
(function () {
  "use strict";
  var aba = document.querySelector('[data-painel-abre="aprovar"]');
  var painel = document.querySelector('[data-painel="aprovar"]');
  if (!aba || !painel) return;

  var CAMPOS = [
    ["tipo", "Tipo", "texto"], ["negocio", "Negócio", "so_ler"], ["bairro", "Bairro", "texto"],
    ["condominio", "Condomínio", "so_ler"], ["logradouro", "Endereço", "texto"], ["numero", "Número", "texto"],
    ["complemento", "Complemento", "texto"], ["quartos", "Quartos", "inteiro"], ["suites", "Suítes", "inteiro"],
    ["banheiros", "Banheiros", "inteiro"], ["vagas", "Vagas", "inteiro"], ["area_util", "Área útil (m²)", "numero"],
    ["area_total", "Área total (m²)", "numero"], ["andar", "Andar", "texto"], ["mobilia", "Mobília", "texto"],
    ["valor_aluguel", "Aluguel (R$)", "dinheiro"], ["valor_venda", "Venda (R$)", "dinheiro"],
    ["taxa_condominio", "Condomínio (R$)", "dinheiro"], ["iptu", "IPTU (R$)", "dinheiro"],
    ["caracteristicas", "Características", "lista"], ["descricao", "Descrição", "longo"]
  ];
  var DO_CADASTRO = ["tipo", "bairro", "logradouro", "numero", "complemento", "quartos", "suites", "banheiros", "vagas",
                     "area_util", "area_total", "andar", "mobilia", "valor_aluguel", "valor_venda", "taxa_condominio",
                     "iptu", "caracteristicas", "descricao"];
  var itens = [], tirados = [], carregou = false, filtro = "todos", ocupado = {};

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function quando(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", timeZone: "America/Manaus" }) + " " +
      d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Manaus" });
  }
  function fone(t) {
    var d = String(t || "").replace(/\D/g, "");
    if (d.length >= 12 && d.indexOf("55") === 0) d = d.slice(2);
    return d.length === 11 ? "(" + d.slice(0, 2) + ") " + d.slice(2, 7) + "-" + d.slice(7) : (t || "");
  }
  function mostra(v, tipo) {
    if (v == null || v === "" || (Array.isArray(v) && !v.length)) return '<span class="ap-vazio">—</span>';
    if (tipo === "dinheiro") { var n = Number(v); return isNaN(n) ? esc(v) : "R$ " + n.toLocaleString("pt-BR", { maximumFractionDigits: 2 }); }
    if (tipo === "lista") return esc([].concat(v).join(", "));
    return esc(v);
  }
  function json(r) {
    return r.json().catch(function () { return {}; }).then(function (d) {
      if (!r.ok || d.ok === false) throw new Error((d.detalhes && [].concat(d.detalhes).join("; ")) || d.detalhe || d.erro || ("HTTP " + r.status));
      return d;
    });
  }
  function chamar(metodo, url, corpo) {
    return fetch(url, { method: metodo, credentials: "same-origin", headers: corpo ? { "Content-Type": "application/json" } : {},
                        body: corpo ? JSON.stringify(corpo) : undefined }).then(json);
  }

  /* ── estilo (só desta aba) ── */
  if (!document.getElementById("ap-estilo")) {
    var s = document.createElement("style");
    s.id = "ap-estilo";
    s.textContent =
      ".ap-topo{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:4px 0 14px}" +
      ".ap-topo p{flex:1 1 100%;margin:0 0 4px;color:var(--texto-fraco);font-size:var(--fs-sm)}" +
      ".ap-chip{border:1px solid var(--borda,#d6d9de);background:transparent;border-radius:999px;padding:5px 12px;cursor:pointer;font-size:13px;color:inherit}" +
      ".ap-chip[aria-pressed=true]{background:#1f6feb;border-color:#1f6feb;color:#fff}" +
      ".ap-lista{display:grid;gap:14px}" +
      ".ap-card{border:1px solid var(--borda,#d6d9de);border-radius:12px;padding:14px 16px;background:var(--superficie,#fff)}" +
      ".ap-cab{display:flex;flex-wrap:wrap;gap:8px;align-items:baseline}" +
      ".ap-cab h3{margin:0;font-size:17px}" +
      ".ap-selo{font-size:11.5px;font-weight:600;border-radius:999px;padding:2px 9px;background:#eef2f7;color:#334}" +
      ".ap-selo--zap{background:#e3f6ea;color:#11663a}.ap-selo--olx{background:#f3e8ff;color:#6b21a8}.ap-selo--st{background:#fff4e0;color:#8a4b00}" +
      ".ap-orig{color:var(--texto-fraco);font-size:13px;margin:6px 0 2px}" +
      ".ap-motivo{font-size:13.5px;margin:2px 0 8px}" +
      ".ap-dono{font-size:13.5px;margin-bottom:8px}.ap-dono button{border:0;background:none;cursor:pointer;color:#1f6feb;font-size:13px}" +
      ".ap-fotos{display:flex;gap:6px;margin:6px 0 10px}.ap-fotos img{width:78px;height:58px;object-fit:cover;border-radius:6px}" +
      ".ap-grade{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:6px 14px;margin:6px 0 10px}" +
      ".ap-campo{font-size:13.5px;min-width:0}.ap-campo--longo{grid-column:1/-1}" +
      ".ap-campo b{display:block;font-size:11.5px;font-weight:600;color:var(--texto-fraco);text-transform:uppercase;letter-spacing:.03em}" +
      ".ap-valor{display:flex;gap:6px;align-items:flex-start;word-break:break-word;white-space:pre-wrap}" +
      ".ap-lapis{border:0;background:none;cursor:pointer;color:#1f6feb;font-size:13px;padding:0 2px;flex-shrink:0}" +
      ".ap-vazio{color:var(--texto-fraco)}" +
      ".ap-campo input,.ap-campo textarea{width:100%;font:inherit;padding:4px 6px;border:1px solid #1f6feb;border-radius:6px}" +
      ".ap-campo textarea{min-height:90px}" +
      ".ap-acoes{display:flex;flex-wrap:wrap;gap:8px;align-items:center;border-top:1px solid var(--borda,#e3e6ea);padding-top:10px}" +
      ".ap-acoes button,.ap-acoes a{font-size:13.5px}" +
      ".ap-recado{font-size:13px;color:var(--texto-fraco)}.ap-recado--ok{color:#11663a}.ap-recado--erro{color:#b42323}" +
      ".ap-disse{font-size:12.5px;color:var(--texto-fraco);margin:0 0 8px}" +
      ".ap-veu{position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:1000;display:flex;align-items:center;justify-content:center;padding:16px}" +
      ".ap-veu[hidden]{display:none!important}" +
      ".ap-caixa{background:var(--superficie,#fff);border-radius:12px;max-width:640px;width:100%;max-height:85vh;overflow:auto;padding:16px}" +
      ".ap-msg{margin:6px 0;padding:7px 10px;border-radius:8px;background:#f1f3f5;font-size:13.5px;white-space:pre-wrap}" +
      ".ap-msg--nos{background:#e3f6ea;margin-left:40px}.ap-msg small{display:block;color:#667;font-size:11px}";
    document.head.appendChild(s);
  }

  painel.innerHTML =
    '<div class="ap-topo"><p>Os imóveis que o proprietário mandou pelo WhatsApp ou autorizou pela OLX e ainda não estão ' +
    "disponíveis para a gente. Clique no lápis para mudar um campo; a ficha e o envio da OLX viram pré-cadastro " +
    "(Rascunho, fora do site e da Nay) na primeira mudança. <b>Aprovar</b> deixa Disponível.</p>" +
    '<span id="ap-filtros"></span><span class="ap-recado" id="ap-recado"></span></div>' +
    '<div class="ap-lista" id="ap-lista"><p class="ap-recado">Carregando…</p></div>' +
    '<div class="ap-veu" id="ap-veu" hidden><div class="ap-caixa" id="ap-caixa"></div></div>';
  var lista = document.getElementById("ap-lista");
  var veu = document.getElementById("ap-veu");

  function recado(t, tipo) {
    var r = document.getElementById("ap-recado");
    r.className = "ap-recado" + (tipo ? " ap-recado--" + tipo : "");
    r.textContent = t || "";
  }

  function contar() {
    var n = { todos: itens.length, zap: 0, olx: 0 };
    itens.forEach(function (it) { if (/WhatsApp/.test(it.origem)) n.zap++; else n.olx++; });
    var conta = document.querySelector("[data-ap-conta]");
    if (conta) conta.textContent = itens.length;
    document.getElementById("ap-filtros").innerHTML = [["todos", "Todos"], ["zap", "Pelo WhatsApp"], ["olx", "Autorizados pela OLX"]]
      .map(function (f) {
        return '<button type="button" class="ap-chip" data-ap-filtro="' + f[0] + '" aria-pressed="' + (filtro === f[0]) + '">' +
          f[1] + " " + n[f[0]] + "</button> ";
      }).join("") + ' <button type="button" class="ap-chip" data-ap-tirados>Mostrar os tirados</button>';
  }

  function titulo(it) {
    var c = it.campos || {};
    return [c.condominio || c.tipo || "Imóvel", c.bairro].filter(Boolean).join(" · ") + (it.codigo ? " (#" + it.codigo + ")" : "");
  }

  function card(it) {
    var c = it.campos || {};
    var zap = /WhatsApp/.test(it.origem);
    var h = '<article class="ap-card" data-ap-chave="' + esc(it.chave) + '">';
    h += '<div class="ap-cab"><h3>' + esc(titulo(it)) + "</h3>" +
      '<span class="ap-selo ' + (zap ? "ap-selo--zap" : "ap-selo--olx") + '">' + esc(it.origem) + "</span>" +
      '<span class="ap-selo ap-selo--st">' + esc(it.status) + "</span>" +
      (it.palpite ? '<span class="ap-selo" title="' + esc(it.palpite_porque || "") + '">IA: ' + esc(it.palpite) + "</span>" : "") +
      '<span class="ap-selo">' + (it.fotos ? it.fotos + " foto" + (it.fotos > 1 ? "s" : "") : "SEM FOTO") + "</span></div>";
    h += '<div class="ap-orig">' + esc(it.origem_detalhe || "") + (it.quando ? " · " + esc(quando(it.quando)) : "") + "</div>";
    if (it.motivo) h += '<div class="ap-motivo">' + esc(it.motivo) + "</div>";
    var d = it.dono || {};
    if (d.nome || d.telefone) {
      h += '<div class="ap-dono">Proprietário: <b>' + esc(d.nome || "sem nome") + "</b>" + (d.telefone ? " · " + esc(fone(d.telefone)) +
        ' <button type="button" data-ap-copiar="' + esc(String(d.telefone).replace(/\D/g, "")) + '" title="Copiar o telefone">⧉</button>' : "") + "</div>";
    }
    if (it.observacao) h += '<p class="ap-disse">Observação: ' + esc(it.observacao) + "</p>";
    if ((it.primeiras || []).length) {
      h += '<div class="ap-fotos">' + it.primeiras.map(function (u) {
        return '<a href="' + esc(u) + '" target="_blank" rel="noopener noreferrer"><img loading="lazy" src="' + esc(u) + '" alt=""></a>';
      }).join("") + "</div>";
    }
    h += '<div class="ap-grade">' + CAMPOS.map(function (f) {
      var k = f[0], tipo = f[2];
      var pode = tipo !== "so_ler";
      return '<div class="ap-campo' + (tipo === "longo" ? " ap-campo--longo" : "") + '" data-ap-campo="' + k + '"><b>' + esc(f[1]) + "</b>" +
        '<div class="ap-valor"><span>' + mostra(c[k], tipo) + "</span>" +
        (pode ? '<button type="button" class="ap-lapis" data-ap-editar="' + k + '" title="Mudar ' + esc(f[1]) + '">✎</button>' : "") +
        "</div></div>";
    }).join("") + "</div>";
    h += '<div class="ap-acoes">' +
      '<button type="button" class="btn-azul" data-ap-aprovar>Aprovar: deixar Disponível</button>' +
      (it.codigo ? '<a class="btn-neutro" href="imovel-editar.html?codigo=' + encodeURIComponent(it.codigo) + '" target="_blank" rel="noopener">Abrir no editor</a>' : "") +
      (it.fonte !== "bot" ? '<button type="button" class="btn-neutro" data-ap-conversa>Ver conversa</button>' : "") +
      (it.link ? '<a class="btn-neutro" href="' + esc(it.link) + '" target="_blank" rel="noopener noreferrer">Anúncio na OLX ↗</a>' : "") +
      '<button type="button" class="btn-neutro" data-ap-tirar>Tirar da lista</button>' +
      '<span class="ap-recado" data-ap-recado></span></div>';
    return h + "</article>";
  }

  function desenhar() {
    contar();
    var vis = itens.filter(function (it) {
      return filtro === "todos" || (filtro === "zap" ? /WhatsApp/.test(it.origem) : !/WhatsApp/.test(it.origem));
    });
    lista.innerHTML = vis.length ? vis.map(card).join("") : '<p class="ap-recado">Nada para aprovar aqui.</p>';
  }

  function carregar() {
    recado("Carregando…");
    return fetch("/admin/api/imoveis/aprovar", { credentials: "same-origin" }).then(json).then(function (d) {
      itens = d.itens || [];
      tirados = d.tirados || [];
      carregou = true;
      recado(d.fora ? d.fora + " tirado(s) da lista" : "");
      desenhar();
    }).catch(function (e) { recado("Não carregou: " + e.message, "erro"); });
  }

  function achar(el) {
    var a = el.closest("[data-ap-chave]");
    if (!a) return {};
    var chave = a.getAttribute("data-ap-chave");
    for (var i = 0; i < itens.length; i++) if (itens[i].chave === chave) return { it: itens[i], el: a };
    return { el: a };
  }
  function avisoNoCard(el, t, tipo) {
    var r = el.querySelector("[data-ap-recado]");
    if (r) { r.className = "ap-recado" + (tipo ? " ap-recado--" + tipo : ""); r.textContent = t || ""; }
  }

  /* a ficha e o envio do bot viram pré-cadastro (Rascunho) antes de mudar ou aprovar */
  function garantirCadastro(it, avisar) {
    if (it.codigo) return Promise.resolve(it.codigo);
    if (it.fonte === "ficha") {
      avisar("Criando o pré-cadastro com o que o dono mandou…");
      return chamar("GET", "/admin/api/imoveis/da-ficha/" + encodeURIComponent(it.item)).then(function (f) {
        var campos = f.campos || {}, corpo = { status: "Rascunho" };
        DO_CADASTRO.forEach(function (k) { if (campos[k] != null && campos[k] !== "") corpo[k] = campos[k]; });
        if (f.condominio && f.condominio.id) corpo.condo_id = f.condominio.id;
        var dono = f.dono || {};
        if (dono.nome || dono.telefone) corpo.proprietario = { nome: dono.nome || null, telefone: dono.telefone || null };
        return chamar("POST", "/admin/api/imoveis", corpo).then(function (r) {
          var cod = r.codigo;
          return chamar("POST", "/admin/api/imoveis/juntar", { de_ficha: it.item, em: cod, fotos: true })
            .catch(function () { return {}; }).then(function () { return cod; });
        });
      }).then(function (cod) { virouImovel(it, cod); return cod; });
    }
    if (it.fonte === "bot") {
      avisar("Criando o pré-cadastro do anúncio da OLX…");
      return chamar("POST", "/admin/api/imoveis/olx-bot/" + encodeURIComponent(it.item) + "/aprovar", {}).then(function (r) {
        var cod = r.codigo, passo = Promise.resolve(), dono = r.proprietario || {};
        if (dono.nome || dono.telefone) {
          passo = passo.then(function () {
            return chamar("PUT", "/admin/api/imoveis/" + cod, { proprietario: { nome: dono.nome || null, telefone: dono.telefone || null } }).catch(function () {});
          });
        }
        (r.fotos || []).forEach(function (url, k) {
          passo = passo.then(function () {
            avisar("Baixando as fotos do anúncio: " + (k + 1) + " de " + r.fotos.length + "…");
            return chamar("POST", "/admin/api/imoveis/olx/" + cod + "/foto", { url: url, ordem: k + 1 }).catch(function () {});
          });
        });
        return passo.then(function () { virouImovel(it, cod); return cod; });
      });
    }
    return Promise.reject(new Error("item sem código"));
  }
  function virouImovel(it, cod) {
    it.codigo = cod;
    it.fonte = "imovel";
    it.chave = "imovel:" + cod;
    it.status = "Rascunho";
  }

  function valorDoCampo(k, tipo, bruto) {
    var t = String(bruto == null ? "" : bruto).trim();
    if (t === "") return null;
    if (tipo === "lista") return t.split(/\s*[,;\n]\s*/).filter(Boolean);
    if (tipo === "inteiro") return parseInt(t.replace(/\D/g, ""), 10);
    return t;            // número e dinheiro vão como texto: o servidor entende "2.500,00"
  }

  function editar(botao) {
    var a = achar(botao), it = a.it;
    if (!it) return;
    var k = botao.getAttribute("data-ap-editar");
    var def = CAMPOS.filter(function (f) { return f[0] === k; })[0];
    var caixa = botao.closest(".ap-campo").querySelector(".ap-valor");
    var atual = (it.campos || {})[k];
    var texto = Array.isArray(atual) ? atual.join(", ") : (atual == null ? "" : String(atual));
    caixa.innerHTML = def[2] === "longo" ? '<textarea data-ap-entrada></textarea>' : '<input data-ap-entrada>';
    var entrada = caixa.querySelector("[data-ap-entrada]");
    entrada.value = texto;
    entrada.focus();
    var feito = false;
    function voltar() { desenharCard(it, a.el); }
    function salvar() {
      if (feito) return;
      feito = true;
      var novo = valorDoCampo(k, def[2], entrada.value);
      if (String(novo == null ? "" : novo) === String(texto === "" ? "" : (def[2] === "lista" ? valorDoCampo(k, "lista", texto) : texto))) { voltar(); return; }
      if (ocupado[it.chave]) return;
      ocupado[it.chave] = true;
      var avisar = function (t) { avisoNoCard(a.el, t); };
      garantirCadastro(it, avisar).then(function (cod) {
        avisar("Salvando " + def[1].toLowerCase() + "…");
        var corpo = {};
        corpo[k] = novo;
        return chamar("PUT", "/admin/api/imoveis/" + cod, corpo);
      }).then(function () {
        it.campos = it.campos || {};
        it.campos[k] = novo;
        ocupado[it.chave] = false;
        desenharCard(it, a.el);
        avisoNoCard(a.el, def[1] + " salvo.", "ok");
      }).catch(function (e) {
        ocupado[it.chave] = false;
        desenharCard(it, a.el);
        avisoNoCard(a.el, "Não salvou: " + e.message, "erro");
      });
    }
    entrada.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { feito = true; voltar(); }
      if (e.key === "Enter" && def[2] !== "longo") { e.preventDefault(); salvar(); }
    });
    entrada.addEventListener("blur", salvar);
  }

  function desenharCard(it, el) {
    var novo = document.createElement("div");
    novo.innerHTML = card(it);
    el.replaceWith(novo.firstChild);
  }

  function aprovar(botao) {
    var a = achar(botao), it = a.it;
    if (!it || ocupado[it.chave]) return;
    if (!window.confirm("Aprovar " + titulo(it) + "? Ele fica Disponível para a Nay" + (it.fotos ? " e no site." : " (sem foto fica fora do site até ganhar foto)."))) return;
    ocupado[it.chave] = true;
    var avisar = function (t, tipo) { avisoNoCard(a.el, t, tipo); };
    garantirCadastro(it, avisar).then(function (cod) {
      avisar("Aprovando…");
      return chamar("PUT", "/admin/api/imoveis/" + cod, { status: "Disponível" }).then(function () { return cod; });
    }).then(function (cod) {
      ocupado[it.chave] = false;
      itens = itens.filter(function (x) { return x !== it; });
      a.el.outerHTML = '<p class="ap-recado ap-recado--ok">Aprovado: o imóvel ' + esc(cod) + ' está Disponível. <a href="imovel-editar.html?codigo=' +
        encodeURIComponent(cod) + '" target="_blank" rel="noopener">Abrir no editor</a></p>';
      contar();
    }).catch(function (e) {
      ocupado[it.chave] = false;
      avisar("Não aprovou: " + e.message, "erro");
    });
  }

  function tirar(botao) {
    var a = achar(botao), it = a.it;
    if (!it) return;
    var motivo = window.prompt("Tirar " + titulo(it) + " da lista? Diga o motivo (opcional). A ficha, o anúncio e o cadastro não mudam.", "");
    if (motivo === null) return;
    chamar("POST", "/admin/api/imoveis/aprovar/tirar", { chave: it.chave, tirar: true, motivo: motivo }).then(function () {
      itens = itens.filter(function (x) { return x !== it; });
      tirados.unshift({ chave: it.chave, motivo: motivo, quem: "", quando: new Date().toISOString() });
      a.el.remove();
      contar();
      recado("Tirado da lista. Volta por \"Mostrar os tirados\".", "ok");
    }).catch(function (e) { avisoNoCard(a.el, "Não tirou: " + e.message, "erro"); });
  }

  function verConversa(botao) {
    var it = achar(botao).it;
    if (!it) return;
    var q = it.fonte === "ficha" ? "ficha=" + encodeURIComponent(it.item) : "codigo=" + encodeURIComponent(it.codigo);
    var caixa = document.getElementById("ap-caixa");
    caixa.innerHTML = '<p class="ap-recado">Carregando a conversa…</p>';
    veu.hidden = false;
    fetch("/admin/api/imoveis/conversa?" + q, { credentials: "same-origin" }).then(json).then(function (d) {
      var h = '<div style="display:flex;justify-content:space-between;align-items:center"><h3 style="margin:0">' + esc(d.nome || "Conversa") +
        " · " + esc(fone(d.telefone)) + '</h3><button type="button" class="btn-neutro" data-ap-fechar>Fechar</button></div>';
      if (d.aviso) h += '<p class="ap-disse">' + esc(d.aviso) + "</p>";
      (d.conversas || []).forEach(function (cv) {
        h += '<p class="ap-disse"><b>' + esc(cv.rotulo || cv.linha || "") + "</b></p>";
        (cv.mensagens || []).forEach(function (m) {
          h += '<div class="ap-msg' + (m.saida ? " ap-msg--nos" : "") + '"><small>' + esc(m.autor || "") + " · " + esc(quando(m.quando)) + "</small>" +
            esc(m.texto || (m.midia ? "[mídia]" : "")) + (m.midia && m.midia.url ? ' <a href="' + esc(m.midia.url) + '" target="_blank" rel="noopener">abrir</a>' : "") + "</div>";
        });
      });
      caixa.innerHTML = h;
    }).catch(function (e) {
      caixa.innerHTML = '<p class="ap-recado ap-recado--erro">Não abriu: ' + esc(e.message) + '</p><button type="button" class="btn-neutro" data-ap-fechar>Fechar</button>';
    });
  }

  function mostrarTirados() {
    var caixa = document.getElementById("ap-caixa");
    caixa.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center"><h3 style="margin:0">Tirados da lista</h3>' +
      '<button type="button" class="btn-neutro" data-ap-fechar>Fechar</button></div>' +
      (tirados.length ? tirados.map(function (t) {
        return '<div class="ap-msg" style="display:flex;gap:10px;align-items:center"><span style="flex:1"><b>' + esc(t.chave) + "</b>" +
          (t.motivo ? " · " + esc(t.motivo) : "") + "<small>" + esc(t.quem || "") + " · " + esc(quando(t.quando)) + "</small></span>" +
          '<button type="button" class="btn-neutro" data-ap-voltar="' + esc(t.chave) + '">Pôr de volta</button></div>';
      }).join("") : '<p class="ap-recado">Nenhum.</p>');
    veu.hidden = false;
  }

  painel.addEventListener("click", function (e) {
    var t = e.target;
    var f = t.closest("[data-ap-filtro]");
    if (f) { filtro = f.getAttribute("data-ap-filtro"); desenhar(); return; }
    if (t.closest("[data-ap-tirados]")) { mostrarTirados(); return; }
    if (t.closest("[data-ap-editar]")) { editar(t.closest("[data-ap-editar]")); return; }
    if (t.closest("[data-ap-aprovar]")) { aprovar(t.closest("[data-ap-aprovar]")); return; }
    if (t.closest("[data-ap-tirar]")) { tirar(t.closest("[data-ap-tirar]")); return; }
    if (t.closest("[data-ap-conversa]")) { verConversa(t.closest("[data-ap-conversa]")); return; }
    var cp = t.closest("[data-ap-copiar]");
    if (cp && navigator.clipboard) {
      navigator.clipboard.writeText(cp.getAttribute("data-ap-copiar")).then(function () { cp.textContent = "✓"; setTimeout(function () { cp.textContent = "⧉"; }, 1200); });
      return;
    }
    if (t.closest("[data-ap-fechar]") || t === veu) { veu.hidden = true; return; }
    if (t.closest("[data-ap-voltar]")) {
      var chave = t.closest("[data-ap-voltar]").getAttribute("data-ap-voltar");
      chamar("POST", "/admin/api/imoveis/aprovar/tirar", { chave: chave, tirar: false }).then(function () {
        veu.hidden = true;
        carregar();
      }).catch(function (er) { recado("Não voltou: " + er.message, "erro"); });
    }
  });

  aba.addEventListener("click", function () { if (!carregou) carregar(); });
  if (location.hash === "#aprovar") { aba.click(); }
  // a contagem na aba logo de cara
  fetch("/admin/api/imoveis/aprovar", { credentials: "same-origin" }).then(json).then(function (d) {
    if (!carregou) { itens = d.itens || []; tirados = d.tirados || []; carregou = true; desenhar(); }
  }).catch(function () {});
})();
