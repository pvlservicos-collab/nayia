/* O Scrap (407, 18/10/2026): o gerenciador de listas de nome + telefone. As rotas são /admin/api/scrap/* (a API do
   site, atrás da senha do admin). Pedro: "focar nos dados, nome e telefone principalmente, faz uma limpa em duplicados
   e tire os sem número ... essa aba scrap vai ser um grande gerenciador de listas". */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var STATUS = { novo: "Novo", contatado: "Contatado", respondeu: "Respondeu", interessado: "Interessado", descartado: "Descartado" };
  var CORES = ["#6d28d9", "#2563eb", "#0e7490", "#059669", "#d97706", "#dc2626", "#db2777", "#4b5563"];
  var POR_PAGINA = 200;
  var listas = [], listaAtual = null, etiquetasTodas = [], pastas = [];
  var contatos = [], total = 0, bairros = [], marcados = {};
  var temporizador = null;

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function n(v) { return Number(v || 0).toLocaleString("pt-BR"); }
  function moeda(v) { if (v == null || v === "") return ""; v = Number(v); return v >= 1000000 ? (v / 1000000).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mi" : v >= 1000 ? Math.round(v / 1000) + " mil" : String(v); }
  function pedir(url, op) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, op || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página");
        if (!r.ok) throw new Error(j.erro || ("HTTP " + r.status)); return j; }); });
  }
  function post(url, corpo) { return pedir(url, { method: "POST", body: JSON.stringify(corpo || {}) }); }
  function toast(msg, erro) {
    var t = $("sc-toast"); t.textContent = msg; t.classList.toggle("erro", !!erro); t.hidden = false;
    clearTimeout(t._t); t._t = setTimeout(function () { t.hidden = true; }, erro ? 5000 : 2600);
  }
  function copiar(texto) {
    return (navigator.clipboard ? navigator.clipboard.writeText(texto) : Promise.reject()).catch(function () {
      var ta = document.createElement("textarea"); ta.value = texto; document.body.appendChild(ta); ta.select(); document.execCommand("copy"); ta.remove();
    });
  }

  /* ---------------- listas (lateral) ---------------- */
  function carregarListas() {
    return pedir("api/scrap/listas").then(function (j) {
      listas = j.listas || []; etiquetasTodas = j.etiquetas || []; pastas = j.pastas || [];
      var normaisN = listas.filter(function (l) { return l.tipo !== "blacklist"; }).length;
      $("sc-resumo-geral").innerHTML = "<strong>" + n(j.telefones_distintos) + "</strong> telefones distintos · <strong>" + n(j.total_contatos) + "</strong> contatos em <strong>" + normaisN + "</strong> lista" + (normaisN === 1 ? "" : "s") +
        (Number(j.na_blacklist) ? " · <strong>" + n(j.na_blacklist) + "</strong> na blacklist" : "");
      pintarListas();
      var sel = $("sc-lote-lista");
      sel.innerHTML = '<option value="">Copiar para a lista…</option>' + listas.map(function (l) { return '<option value="' + l.id + '">' + esc(l.nome) + "</option>"; }).join("");
      if (listaAtual && !listas.some(function (l) { return l.id === listaAtual; })) listaAtual = null;
      pintarCabeca();
    });
  }
  function barraStatus(ps, tot) {
    if (!tot) return "";
    return '<span class="sc-lista__barra">' + Object.keys(STATUS).map(function (s) { var v = Number(ps[s] || 0); return v ? '<i class="' + s + '" style="width:' + (100 * v / tot) + '%" title="' + STATUS[s] + ": " + v + '"></i>' : ""; }).join("") + "</span>";
  }
  var fechadas = {};
  try { fechadas = JSON.parse(localStorage.getItem("scrap.pastasFechadas") || "{}"); } catch (e) { fechadas = {}; }
  function guardarFechadas() { try { localStorage.setItem("scrap.pastasFechadas", JSON.stringify(fechadas)); } catch (e) {} }
  function botaoLista(l) {
    var sem = Number(l.anuncios_sem_telefone || 0), bl = l.tipo === "blacklist";
    var sub = bl ? "blacklist · ninguém daqui entra nas outras listas" :
      l.origem === "olx" ? n(l.anuncios) + " anúncios · " + n(l.anunciantes) + " anunciantes" + (sem ? " · " + n(sem) + " sem número" : "") + (Number(l.bloqueados) ? " · " + n(l.bloqueados) + " na blacklist" : "") :
      l.origem === "sistema" ? "base da casa" : l.origem === "csv" ? "importada" : "feita à mão";
    return '<button type="button" class="sc-lista' + (bl ? " sc-lista--bl" : "") + '" data-lista="' + l.id + '" aria-current="' + (l.id === listaAtual) + '" style="--cor:' + esc(l.cor) + '">' +
      '<span class="sc-lista__cor">' + (bl ? "⛔" : "") + '</span><span class="sc-lista__nome">' + esc(l.nome) + '<span class="sc-lista__sub">' + sub + "</span></span>" +
      '<span class="sc-lista__n">' + n(l.contatos) + "</span>" + (bl ? "" : barraStatus(l.por_status || {}, Number(l.contatos))) + "</button>";
  }
  function pintarListas() {
    var normais = listas.filter(function (l) { return l.tipo !== "blacklist"; });
    var totalC = normais.reduce(function (s, l) { return s + Number(l.contatos || 0); }, 0);
    var h = '<button type="button" class="sc-lista" data-lista="" aria-current="' + (listaAtual == null) + '"><span class="sc-lista__cor" style="--cor:#1f1b2e"></span>' +
      '<span class="sc-lista__nome">Todas as listas<span class="sc-lista__sub">um telefone só uma vez · sem as blacklists</span></span><span class="sc-lista__n">' + n(totalC) + "</span></button>";
    var grupos = {}; var ordem = [];
    listas.forEach(function (l) { var p = l.pasta || ""; if (!grupos[p]) { grupos[p] = []; ordem.push(p); } grupos[p].push(l); });
    ordem.sort(function (a, b) { if (!a) return 1; if (!b) return -1; if (a === "Blacklist") return 1; if (b === "Blacklist") return -1; return a.localeCompare(b); });
    ordem.forEach(function (p) {
      var ls = grupos[p], tot = ls.reduce(function (s, l) { return s + Number(l.contatos || 0); }, 0), fechada = !!fechadas[p];
      if (p) h += '<div class="sc-pasta' + (fechada ? " fechada" : "") + '" data-pasta="' + esc(p) + '"><span class="sc-pasta__seta">▾</span><span class="sc-pasta__nome">' + esc(p) + '</span><small>' + ls.length + " lista" + (ls.length === 1 ? "" : "s") + " · " + n(tot) + "</small></div>";
      else if (ordem.length > 1) h += '<div class="sc-pasta sc-pasta--solta"><span class="sc-pasta__nome">Sem pasta</span><small>' + ls.length + "</small></div>";
      if (!fechada) h += ls.map(botaoLista).join("");
    });
    $("sc-listas").innerHTML = h;
  }
  $("sc-listas").addEventListener("click", function (e) {
    var p = e.target.closest("[data-pasta]");
    if (p) { fechadas[p.dataset.pasta] = !fechadas[p.dataset.pasta]; guardarFechadas(); pintarListas(); return; }
    var b = e.target.closest("[data-lista]"); if (!b) return;
    listaAtual = b.dataset.lista ? Number(b.dataset.lista) : null;
    marcados = {}; pintarListas(); pintarCabeca(); carregarContatos(true);
  });
  function listaObj() { return listas.find(function (l) { return l.id === listaAtual; }) || null; }
  function pintarCabeca() {
    var l = listaObj(), h;
    if (!l) {
      h = "<div><h2><i style=\"--cor:#1f1b2e\"></i>Todas as listas</h2><p>Um telefone aparece uma vez só, com as listas em que ele está. Para editar a lista, escolha-a ao lado.</p></div>" +
        '<div class="sc-lista-acoes"><button type="button" class="btn-neutro" data-acao="exportar">Exportar CSV</button></div>';
    } else if (l.tipo === "blacklist") {
      h = '<div><h2><i style="--cor:' + esc(l.cor) + '"></i>⛔ ' + esc(l.nome) + "</h2>" +
        "<p>" + esc(l.descricao || "Quem está aqui não entra em nenhuma lista normal: a carga da raspagem e a importação de CSV pulam estes números.") + "</p>" +
        '<div class="sc-numeros"><span><b>' + n(l.contatos) + "</b> números bloqueados</span>" + (l.pasta ? "<span>pasta <b>" + esc(l.pasta) + "</b></span>" : "") + "</div></div>" +
        '<div class="sc-lista-acoes">' + (l.origem === "sistema" ? '<button type="button" class="btn-azul" data-acao="refazer-bl">Refazer (60 dias)</button>' : "") +
        '<button type="button" class="btn-neutro" data-acao="exportar">Exportar CSV</button>' +
        '<button type="button" class="btn-neutro" data-acao="editar-lista">Editar lista</button>' +
        '<button type="button" class="btn-neutro sc-perigo" data-acao="apagar-lista">Apagar lista</button></div>';
    } else {
      var ps = l.por_status || {};
      h = '<div><h2><i style="--cor:' + esc(l.cor) + '"></i>' + esc(l.nome) + (l.pasta ? ' <small class="sc-pasta-chip">' + esc(l.pasta) + "</small>" : "") + "</h2>" +
        (l.descricao || l.url_busca ? "<p>" + esc(l.descricao || "") + (l.url_busca ? (l.descricao ? " · " : "") + '<a href="' + esc(l.url_busca) + '" target="_blank" rel="noopener">abrir a busca na OLX</a>' : "") + "</p>" : "") +
        '<div class="sc-numeros"><span><b>' + n(l.contatos) + "</b> contatos</span>" +
        (l.origem === "olx" ? "<span><b>" + n(l.anuncios) + "</b> anúncios</span><span><b>" + n(l.anunciantes) + "</b> anunciantes</span><span><b>" + n(l.anuncios_sem_telefone) + "</b> anúncios sem número (fora)</span>" : "") +
        (Number(l.bloqueados) ? '<span title="números que estavam na blacklist e ficaram de fora"><b>' + n(l.bloqueados) + "</b> na blacklist (fora)</span>" : "") +
        Object.keys(STATUS).filter(function (s) { return ps[s]; }).map(function (s) { return "<span><b>" + n(ps[s]) + "</b> " + STATUS[s].toLowerCase() + "</span>"; }).join("") + "</div></div>" +
        '<div class="sc-lista-acoes"><button type="button" class="btn-neutro" data-acao="exportar">Exportar CSV</button>' +
        '<button type="button" class="btn-neutro" data-acao="copiar-todos">Copiar números</button>' +
        '<button type="button" class="btn-neutro" data-acao="editar-lista">Editar lista</button>' +
        '<button type="button" class="btn-neutro sc-perigo" data-acao="apagar-lista">Apagar lista</button></div>';
    }
    $("sc-lista-cabeca").innerHTML = h;
  }
  $("sc-lista-cabeca").addEventListener("click", function (e) {
    var b = e.target.closest("[data-acao]"); if (!b) return;
    var a = b.dataset.acao, l = listaObj();
    if (a === "exportar") { window.location.href = "api/scrap/exportar.csv?" + filtrosQuery(); }
    if (a === "editar-lista" && l) modalLista(l);
    if (a === "refazer-bl" && l) {
      var d = prompt("Refazer a blacklist com quem falou conosco nos últimos quantos dias?", "60");
      if (!d) return;
      b.disabled = true;
      post("api/scrap/listas/" + l.id + "/blacklist-60d", { dias: Number(d) }).then(function (r) { toast(n(r.na_blacklist) + " números na blacklist · " + n(r.bloqueados_total) + " tirados das listas"); return recarregarTudo(); }).catch(function (e) { toast(e.message, true); }).then(function () { b.disabled = false; });
    }
    if (a === "apagar-lista" && l) {
      if (!confirm("Apagar a lista \"" + l.nome + "\" com " + n(l.contatos) + " contatos? Não tem volta.")) return;
      pedir("api/scrap/listas/" + l.id, { method: "DELETE" }).then(function () { toast("Lista apagada"); listaAtual = null; return carregarListas(); }).then(function () { carregarContatos(true); }).catch(function (e) { toast(e.message, true); });
    }
    if (a === "copiar-todos") {
      pedir("api/scrap/contatos?" + filtrosQuery() + "&limite=100000").then(function (j) {
        var nums = (j.contatos || []).map(function (c) { return "55" + c.telefone; });
        return copiar(nums.join("\n")).then(function () { toast(n(nums.length) + " números copiados (com o 55)"); });
      }).catch(function (e) { toast(e.message, true); });
    }
  });

  /* ---------------- contatos ---------------- */
  function filtrosQuery() {
    var p = new URLSearchParams();
    if (listaAtual) p.set("lista", listaAtual);
    var q = $("sc-f-busca").value.trim(); if (q) p.set("q", q);
    if ($("sc-f-status").value) p.set("status", $("sc-f-status").value);
    if ($("sc-f-etiqueta").value) p.set("etiqueta", $("sc-f-etiqueta").value);
    if ($("sc-f-bairro").value) p.set("bairro", $("sc-f-bairro").value);
    p.set("ordem", $("sc-f-ordem").value);
    return p.toString();
  }
  function carregarContatos(doZero) {
    if (doZero) { contatos = []; $("sc-corpo").innerHTML = '<tr><td colspan="10" class="sc-vazio">Carregando…</td></tr>'; }
    return pedir("api/scrap/contatos?" + filtrosQuery() + "&limite=" + POR_PAGINA + "&desloc=" + contatos.length).then(function (j) {
      total = Number(j.total || 0); contatos = contatos.concat(j.contatos || []); bairros = j.bairros || [];
      pintarFiltros(); pintarTabela();
    }).catch(function (e) { $("sc-corpo").innerHTML = '<tr><td colspan="10" class="sc-vazio">' + esc(e.message) + "</td></tr>"; });
  }
  function pintarFiltros() {
    var l = listaObj(), ets = l ? (l.etiquetas || []) : etiquetasTodas;
    var se = $("sc-f-etiqueta"), v = se.value;
    se.innerHTML = '<option value="">Todas as etiquetas</option>' + ets.map(function (e) { return '<option value="' + esc(e) + '">' + esc(e) + "</option>"; }).join("");
    se.value = ets.indexOf(v) >= 0 ? v : "";
    var sb = $("sc-f-bairro"), vb = sb.value;
    sb.innerHTML = '<option value="">Todos os bairros</option>' + bairros.map(function (b) { return '<option value="' + esc(b.bairro) + '">' + esc(b.bairro) + " (" + n(b.n) + ")</option>"; }).join("");
    sb.value = bairros.some(function (b) { return b.bairro === vb; }) ? vb : "";
    $("sc-contagem").textContent = total ? n(contatos.length) + " de " + n(total) + " contatos" : "";
    $("sc-mais").hidden = contatos.length >= total;
  }
  function maisListas(ts) {
    if (!ts || !ts.length) return "";
    return '<span class="sc-tambem" title="também em: ' + esc(ts.join(", ")) + '">também em ' + (ts.length === 1 ? esc(ts[0].replace(/^OLX · /, "")) : ts.length + " listas") + "</span>";
  }
  function linha(c) {
    var marcado = !!marcados[c.id];
    var faixa = c.preco_min != null ? (c.preco_min === c.preco_max ? "R$ " + moeda(c.preco_min) : "R$ " + moeda(c.preco_min) + " – " + moeda(c.preco_max)) : "";
    return '<tr data-id="' + c.id + '" class="' + (marcado ? "marcado" : "") + '">' +
      '<td class="sel"><input type="checkbox" data-marcar="' + c.id + '"' + (marcado ? " checked" : "") + "></td>" +
      '<td><span class="sc-nome" data-edita="nome" title="clique para editar">' + (esc(c.nome) || '<span style="color:#b9b3c9">sem nome</span>') + "</span>" +
        (c.confirmado ? '<span class="sc-ok" title="o prefixo que a OLX mostra bate com este número">✓ OLX</span>' : "") +
        (c.na_blacklist ? '<span class="sc-bl" title="este número está numa blacklist (ficou porque foi posto à mão)">⛔ blacklist</span>' : "") +
        (c.empresa ? "<small>" + esc(c.empresa) + "</small>" : "") +
        (!listaAtual && c.lista_nome ? '<small><span class="sc-tambem" style="background:' + esc(c.lista_cor) + '22;color:' + esc(c.lista_cor) + '" title="' + esc(c.lista_nome) + '">' + esc(c.lista_nome.replace(/^OLX · /, "")) + "</span>" + maisListas(c.tambem_em) + "</small>" :
         (c.tambem_em && c.tambem_em.length ? "<small>" + maisListas(c.tambem_em) + "</small>" : "")) + "</td>" +
      '<td><span class="sc-tel"><a href="tel:+55' + c.telefone + '" data-edita="telefone" title="clique com o botão direito para editar">' + esc(c.telefone_fmt) + "</a>" +
        '<a class="sc-zap" href="https://wa.me/55' + c.telefone + '" target="_blank" rel="noopener" title="abrir no WhatsApp">W</a>' +
        '<button type="button" class="sc-copiar" data-copiar="55' + c.telefone + '" title="copiar o número">⧉</button></span></td>' +
      '<td class="num">' + (c.n_anuncios ? '<button type="button" class="sc-anuncios" data-anuncios="' + c.telefone + '">' + c.n_anuncios + "</button>" : "—") + "</td>" +
      '<td class="sc-bairros" title="' + esc((c.bairros || []).join(", ")) + '">' + esc((c.bairros || []).slice(0, 2).join(", ")) + ((c.bairros || []).length > 2 ? " +" + (c.bairros.length - 2) : "") + "</td>" +
      '<td class="sc-faixa">' + faixa + "</td>" +
      '<td><select class="sc-status sc-status--' + c.status + '" data-status="' + c.id + '">' + Object.keys(STATUS).map(function (s) { return '<option value="' + s + '"' + (s === c.status ? " selected" : "") + ">" + STATUS[s] + "</option>"; }).join("") + "</select></td>" +
      '<td><span class="sc-etqs">' + (c.etiquetas || []).map(function (e) { return '<span class="sc-etq">' + esc(e) + '<button type="button" data-tirar="' + esc(e) + '" title="tirar">×</button></span>'; }).join("") +
        '<button type="button" class="sc-etq-mais" data-etiqueta="' + c.id + '" title="pôr etiqueta">+</button></span></td>' +
      '<td><span class="sc-obs" data-edita="observacao">' + esc(c.observacao || "") + "</span></td>" +
      '<td class="sc-linha-acoes"><button type="button" data-apagar="' + c.id + '" title="tirar da lista">🗑</button></td></tr>';
  }
  function pintarTabela() {
    if (!contatos.length) { $("sc-corpo").innerHTML = '<tr><td colspan="10" class="sc-vazio">' + (total ? "" : (listaAtual ? "Nenhum contato com esse filtro." : "Nenhuma lista ainda. Crie uma ou importe um CSV.")) + "</td></tr>"; }
    else $("sc-corpo").innerHTML = contatos.map(linha).join("");
    $("sc-sel-todos").checked = contatos.length > 0 && contatos.every(function (c) { return marcados[c.id]; });
    pintarLote();
  }
  function contato(id) { return contatos.find(function (c) { return c.id === Number(id); }); }
  function atualizarLinha(c) { var tr = $("sc-corpo").querySelector('tr[data-id="' + c.id + '"]'); if (tr) tr.outerHTML = linha(c); }
  function salvarContato(c, campos) {
    return post("api/scrap/contatos", Object.assign({ id: c.id }, campos)).then(function () {
      Object.assign(c, campos); atualizarLinha(c); return carregarListas();
    }).catch(function (e) { toast(e.message, true); atualizarLinha(c); });
  }

  // edição inline: nome, telefone (botão direito), observação
  function editarInline(el, c, campo) {
    var atual = c[campo] || "", ta = campo === "observacao";
    var inp = document.createElement(ta ? "textarea" : "input"); inp.className = "sc-edita"; inp.value = atual;
    if (ta) inp.rows = 2;
    el.replaceWith(inp); inp.focus();
    var feito = false;
    function fim(salva) {
      if (feito) return; feito = true;
      var v = inp.value.trim();
      if (salva && v !== atual) { var o = {}; o[campo] = v; salvarContato(c, o); }
      else atualizarLinha(c);
    }
    inp.addEventListener("blur", function () { fim(true); });
    inp.addEventListener("keydown", function (e) { if (e.key === "Escape") fim(false); if (e.key === "Enter" && !ta) { e.preventDefault(); fim(true); } if (e.key === "Enter" && ta && (e.ctrlKey || e.metaKey)) fim(true); });
  }
  $("sc-corpo").addEventListener("click", function (e) {
    var t = e.target, tr = t.closest("tr[data-id]"); if (!tr) return;
    var c = contato(tr.dataset.id); if (!c) return;
    if (t.dataset.marcar) { if (t.checked) marcados[c.id] = true; else delete marcados[c.id]; tr.classList.toggle("marcado", t.checked); pintarLote(); return; }
    if (t.dataset.copiar) { copiar(t.dataset.copiar).then(function () { toast("Número copiado"); }); return; }
    if (t.dataset.anuncios) { abrirGaveta(c); return; }
    if (t.dataset.tirar) { salvarContato(c, { etiquetas: (c.etiquetas || []).filter(function (x) { return x !== t.dataset.tirar; }) }); return; }
    if (t.dataset.etiqueta) { var v = prompt("Etiqueta para " + (c.nome || c.telefone_fmt) + ":" + (etiquetasTodas.length ? "\n(existentes: " + etiquetasTodas.join(", ") + ")" : "")); if (v && v.trim()) salvarContato(c, { etiquetas: (c.etiquetas || []).concat([v.trim()]) }); return; }
    if (t.dataset.apagar) { if (confirm("Tirar " + (c.nome || c.telefone_fmt) + " desta lista?")) post("api/scrap/contatos/acao", { ids: [c.id], acao: "apagar" }).then(function () { toast("Tirado da lista"); delete marcados[c.id]; contatos = contatos.filter(function (x) { return x.id !== c.id; }); total--; pintarTabela(); pintarFiltros(); carregarListas(); }).catch(function (e) { toast(e.message, true); }); return; }
    var ed = t.closest("[data-edita]");
    if (ed && ed.dataset.edita !== "telefone") { e.preventDefault(); editarInline(ed, c, ed.dataset.edita); }
  });
  $("sc-corpo").addEventListener("contextmenu", function (e) {
    var a = e.target.closest('[data-edita="telefone"]'); if (!a) return;
    var tr = a.closest("tr[data-id]"), c = contato(tr.dataset.id); if (!c) return;
    e.preventDefault();
    var v = prompt("Telefone de " + (c.nome || "") + ":", c.telefone_fmt);
    if (v && v.trim() && v.trim() !== c.telefone_fmt) post("api/scrap/contatos", { id: c.id, telefone: v.trim() }).then(function () { toast("Telefone atualizado"); return recarregarTudo(); }).catch(function (e) { toast(e.message, true); });
  });
  $("sc-corpo").addEventListener("change", function (e) {
    var s = e.target.closest("[data-status]"); if (!s) return;
    var c = contato(s.dataset.status); if (!c) return;
    salvarContato(c, { status: s.value });
  });
  $("sc-sel-todos").addEventListener("change", function () {
    var on = this.checked; contatos.forEach(function (c) { if (on) marcados[c.id] = true; else delete marcados[c.id]; }); pintarTabela();
  });
  $("sc-mais").addEventListener("click", function () { carregarContatos(false); });
  ["sc-f-status", "sc-f-etiqueta", "sc-f-bairro", "sc-f-ordem"].forEach(function (id) { $(id).addEventListener("change", function () { carregarContatos(true); }); });
  $("sc-f-busca").addEventListener("input", function () { clearTimeout(temporizador); temporizador = setTimeout(function () { carregarContatos(true); }, 350); });
  function recarregarTudo() { return carregarListas().then(function () { return carregarContatos(true); }); }

  /* ---------------- lote ---------------- */
  function idsMarcados() { return Object.keys(marcados).map(Number); }
  function pintarLote() { var ids = idsMarcados(); $("sc-lote").hidden = !ids.length; $("sc-lote-n").textContent = ids.length; }
  function acaoLote(acao, valor) {
    var ids = idsMarcados(); if (!ids.length) return;
    return post("api/scrap/contatos/acao", { ids: ids, acao: acao, valor: valor }).then(function (r) {
      toast((r.n || 0) + " contato" + (r.n === 1 ? "" : "s") + (acao === "apagar" ? " tirados" : acao === "mover" ? " movidos" : acao === "copiar" ? " copiados" + (r.pulados ? " (" + r.pulados + " já estavam lá)" : "") : " atualizados"));
      if (acao === "apagar" || acao === "mover") marcados = {};
      return recarregarTudo();
    }).catch(function (e) { toast(e.message, true); });
  }
  $("sc-lote").addEventListener("click", function (e) {
    var b = e.target.closest("[data-lote]"); if (!b) return;
    var a = b.dataset.lote, ids = idsMarcados();
    if (a === "limpar") { marcados = {}; pintarTabela(); }
    if (a === "etiqueta_por") { var v = prompt("Etiqueta para pôr nos " + ids.length + " marcados:"); if (v && v.trim()) acaoLote("etiqueta_por", v.trim()); }
    if (a === "etiqueta_tirar") { var t = prompt("Etiqueta para tirar dos marcados:" + (etiquetasTodas.length ? "\n(" + etiquetasTodas.join(", ") + ")" : "")); if (t && t.trim()) acaoLote("etiqueta_tirar", t.trim()); }
    if (a === "apagar") { if (confirm("Tirar " + ids.length + " contatos da lista?")) acaoLote("apagar"); }
    if (a === "copiar_numeros") { copiar(ids.map(function (id) { var c = contato(id); return c ? "55" + c.telefone : ""; }).filter(Boolean).join("\n")).then(function () { toast(ids.length + " números copiados"); }); }
    if (a === "mover") {
      var opc = listas.filter(function (l) { return l.id !== listaAtual; });
      if (!opc.length) { toast("Crie outra lista primeiro", true); return; }
      var r = prompt("Mover os " + ids.length + " marcados para qual lista?\n" + opc.map(function (l, i) { return (i + 1) + ". " + l.nome; }).join("\n") + "\n\nDigite o número:");
      var l = opc[Number(r) - 1]; if (l) acaoLote("mover", String(l.id));
    }
  });
  $("sc-lote-status").addEventListener("change", function () { if (this.value) { acaoLote("status", this.value); this.value = ""; } });
  $("sc-lote-lista").addEventListener("change", function () { if (this.value) { acaoLote("copiar", this.value); this.value = ""; } });

  /* ---------------- gaveta: anúncios do contato ---------------- */
  function abrirGaveta(c) {
    $("sc-gaveta-titulo").textContent = c.nome || c.telefone_fmt;
    $("sc-gaveta-sub").textContent = c.telefone_fmt + " · " + c.n_anuncios + " anúncio" + (c.n_anuncios === 1 ? "" : "s") + (c.bairros && c.bairros.length ? " · " + c.bairros.join(", ") : "");
    $("sc-gaveta-corpo").innerHTML = '<p class="sc-vazio">Carregando…</p>';
    $("sc-gaveta").hidden = false;
    pedir("api/scrap/anuncios?telefone=" + c.telefone).then(function (j) {
      var an = j.anuncios || [];
      $("sc-gaveta-corpo").innerHTML = an.length ? an.map(function (a) {
        return '<article class="sc-an">' + (a.foto ? '<img src="' + esc(a.foto) + '" alt="" loading="lazy">' : '<div class="sc-an__semfoto"></div>') +
          "<div><h3><a href=\"" + esc(a.url) + '" target="_blank" rel="noopener">' + esc(a.titulo) + "</a></h3>" +
          '<div class="sc-an__meta"><span class="sc-an__preco">' + esc(a.preco_texto || "") + "</span> · " + esc(a.categoria || "") + (a.quartos ? " · " + a.quartos + " q" : "") + (a.area_m2 ? " · " + a.area_m2 + " m²" : "") + " · " + esc(a.bairro || "") + (a.cep ? " · CEP " + esc(a.cep) : "") +
          (a.lista ? " · <i>" + esc(a.lista) + "</i>" : "") + "</div>" +
          '<div class="sc-an__meta">anunciante: ' + esc(a.anunciante || "") + (a.telefones && a.telefones.length ? " · fones no texto: " + a.telefones.map(esc).join(", ") : "") + (a.telefone_mascarado ? " · OLX mostra " + esc(a.telefone_mascarado) : "") + "</div>" +
          (a.descricao ? "<details><summary>descrição</summary><pre>" + esc(a.descricao) + "</pre></details>" : "") + "</div></article>";
      }).join("") : '<p class="sc-vazio">Sem anúncio guardado para este número.</p>';
    }).catch(function (e) { $("sc-gaveta-corpo").innerHTML = '<p class="sc-vazio">' + esc(e.message) + "</p>"; });
  }
  $("sc-gaveta").addEventListener("click", function (e) { if (e.target.closest("[data-fechar]")) $("sc-gaveta").hidden = true; });

  /* ---------------- janelas ---------------- */
  var modalAoSalvar = null;
  function abrirModal(titulo, corpoHtml, aoSalvar, rotuloOk) {
    $("sc-modal-titulo").textContent = titulo; $("sc-modal-corpo").innerHTML = corpoHtml; $("sc-modal-aviso").textContent = "";
    $("sc-modal-ok").textContent = rotuloOk || "Salvar"; modalAoSalvar = aoSalvar; $("sc-modal").hidden = false;
    var p = $("sc-modal-corpo").querySelector("input, textarea, select"); if (p) p.focus();
  }
  function fecharModal() { $("sc-modal").hidden = true; modalAoSalvar = null; }
  $("sc-modal").addEventListener("click", function (e) { if (e.target.closest("[data-fechar]")) fecharModal(); });
  $("sc-modal-form").addEventListener("submit", function (e) {
    e.preventDefault(); if (!modalAoSalvar) return;
    var f = $("sc-modal-form"), dados = {};
    f.querySelectorAll("[name]").forEach(function (i) { if (i.type === "radio") { if (i.checked) dados[i.name] = i.value; } else dados[i.name] = i.value; });
    $("sc-modal-ok").disabled = true;
    Promise.resolve(modalAoSalvar(dados)).then(function () { fecharModal(); }).catch(function (err) { $("sc-modal-aviso").textContent = err.message; }).then(function () { $("sc-modal-ok").disabled = false; });
  });
  function campo(rotulo, html, dica) { return '<label class="sc-campo"><span>' + rotulo + (dica ? ' <span class="dica">' + dica + "</span>" : "") + "</span>" + html + "</label>"; }
  function selectListas(nome, atual) { return '<select class="selecao" name="' + nome + '" required>' + (listas.length ? "" : '<option value="">(crie uma lista primeiro)</option>') + listas.map(function (l) { return '<option value="' + l.id + '"' + (l.id === atual ? " selected" : "") + ">" + esc(l.nome) + "</option>"; }).join("") + "</select>"; }

  function modalLista(l) {
    l = l || {};
    abrirModal(l.id ? "Editar lista" : "Nova lista",
      campo("Nome", '<input class="entrada" name="nome" required value="' + esc(l.nome || "") + '" placeholder="ex.: Corretores de locação">') +
      '<div class="sc-duas">' +
      campo("Pasta", '<input class="entrada" name="pasta" list="sc-pastas" value="' + esc(l.pasta || "") + '" placeholder="ex.: OLX, Base, Campanhas"><datalist id="sc-pastas">' + pastas.map(function (p) { return '<option value="' + esc(p) + '">'; }).join("") + "</datalist>", "agrupa na lateral") +
      campo("Tipo", '<select class="selecao" name="tipo"><option value="lista"' + (l.tipo !== "blacklist" ? " selected" : "") + '>Lista normal</option><option value="blacklist"' + (l.tipo === "blacklist" ? " selected" : "") + ">Blacklist (quem está aqui não entra nas outras)</option></select>") +
      "</div>" +
      campo("Descrição", '<input class="entrada" name="descricao" value="' + esc(l.descricao || "") + '" placeholder="de onde veio, para que serve">', "opcional") +
      campo("Link da busca", '<input class="entrada" name="url_busca" value="' + esc(l.url_busca || "") + '" placeholder="https://www.olx.com.br/…">', "opcional") +
      '<div class="sc-campo"><span>Cor</span><div class="sc-cores">' + CORES.map(function (c, i) { return '<input type="radio" name="cor" id="cor' + i + '" value="' + c + '"' + ((l.cor || CORES[0]) === c ? " checked" : "") + '><label for="cor' + i + '" style="background:' + c + '"></label>'; }).join("") + "</div></div>",
      function (d) { return post("api/scrap/listas", Object.assign({ id: l.id || null }, d)).then(function (r) { toast(l.id ? "Lista salva" : "Lista criada"); if (!l.id) listaAtual = r.id; return recarregarTudo(); }); });
  }
  $("sc-b-nova-lista").addEventListener("click", function () { modalLista(null); });

  $("sc-b-contato").addEventListener("click", function () {
    if (!listas.length) { toast("Crie uma lista primeiro", true); return; }
    abrirModal("Novo contato",
      '<div class="sc-duas">' + campo("Nome", '<input class="entrada" name="nome" placeholder="nome ou empresa">') + campo("Telefone", '<input class="entrada" name="telefone" required placeholder="(92) 9xxxx-xxxx" inputmode="tel">') + "</div>" +
      '<div class="sc-duas">' + campo("Empresa", '<input class="entrada" name="empresa">', "opcional") + campo("Lista", selectListas("lista_id", listaAtual)) + "</div>" +
      campo("Etiquetas", '<input class="entrada" name="etiquetas" placeholder="separadas por vírgula">', "opcional") +
      campo("Observação", '<textarea class="entrada" name="observacao"></textarea>', "opcional"),
      function (d) {
        d.etiquetas = d.etiquetas.split(",").map(function (s) { return s.trim(); }).filter(Boolean); d.lista_id = Number(d.lista_id);
        return post("api/scrap/contatos", d).then(function () { toast("Contato criado"); listaAtual = d.lista_id; return recarregarTudo(); });
      }, "Criar");
  });

  $("sc-b-importar").addEventListener("click", function () {
    if (!listas.length) { toast("Crie uma lista primeiro", true); return; }
    abrirModal("Importar CSV",
      campo("Para a lista", selectListas("lista_id", listaAtual)) +
      campo("Arquivo", '<input type="file" name="arquivo" accept=".csv,.txt,.tsv" class="entrada">', "CSV, TSV ou colado do Excel. Colunas: nome;telefone (opcionais: empresa, observacao, etiquetas). Sem cabeçalho também vale.") +
      campo("Ou cole aqui", '<textarea class="entrada grande" name="csv" placeholder="Maria;92 99111-2222&#10;João da Imobiliária X;92988887777"></textarea>') +
      '<p class="dica" style="margin:0;font-size:var(--fs-xs);color:var(--texto-fraco)">Telefone repetido na lista não entra de novo; número inválido é pulado. O relatório sai no fim.</p>',
      function (d) {
        var arq = $("sc-modal-form").querySelector('[name="arquivo"]').files[0];
        var ler = arq ? arq.text() : Promise.resolve(d.csv);
        return ler.then(function (texto) {
          if (!texto || !texto.trim()) throw new Error("nada para importar");
          return post("api/scrap/importar-contatos", { lista_id: Number(d.lista_id), csv: texto });
        }).then(function (r) {
          toast("Importado: " + n(r.inseridos) + " novos · " + n(r.repetidos) + " já estavam · " + n(r.invalidos) + " sem telefone válido (de " + n(r.lidos) + " linhas)");
          listaAtual = Number(d.lista_id); return recarregarTudo();
        });
      }, "Importar");
  });

  document.addEventListener("keydown", function (e) { if (e.key === "Escape") { if (!$("sc-modal").hidden) fecharModal(); else if (!$("sc-gaveta").hidden) $("sc-gaveta").hidden = true; } });

  /* ---------------- início ---------------- */
  var inicial = new URLSearchParams(location.search).get("lista");
  if (inicial) listaAtual = Number(inicial) || null;
  carregarListas().then(function () { return carregarContatos(true); }).catch(function (e) { toast(e.message, true); });
})();
