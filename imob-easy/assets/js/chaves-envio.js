/* ==========================================================================
   Envio para Chaves na Mão (admin/envio-chaves-na-mao.html, 30/10/2026)

   Duas abas: "Escolher para envio" (filtros, escolha dos imóveis do plano -- 400 no ar, 20 em destaque -- e a geração do
   XML do portal ou da planilha XML) e "Métricas de imóveis" (o que mais foi buscado, mandado e visitado nos últimos
   meses, para decidir os destaques). Os dados vêm de /admin/api/chavesnamao/painel; o arquivo, de .../exportar.
   A escolha fica neste navegador (localStorage) até gerar o arquivo ou limpar.
   ========================================================================== */
(function () {
  "use strict";

  var POR_PAGINA = 50;
  var CHAVE = "cnm:escolha";

  var d = null;                                  // a resposta do painel
  var lim = { no_ar: 400, destaques: 20 };
  var escolha = { ar: {}, dest: {} };            // codigo -> true
  var pagina = 1;
  var lista = [];                                // os filtrados, na ordem da tela
  var ordemMetricas = { campo: "buscados", sentido: -1, q: "" };

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function reais(v) { return v ? "R$ " + Math.round(Number(v)).toLocaleString("pt-BR") : ""; }
  function inteiro(v) { return Number(v || 0).toLocaleString("pt-BR"); }
  function sem(t) { return String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  function nCh(o) { return Object.keys(o).length; }

  /* ---------- a escolha guardada ---------- */
  function ler() {
    try {
      var g = JSON.parse(localStorage.getItem(CHAVE) || "{}");
      (g.ar || []).forEach(function (c) { escolha.ar[c] = true; });
      (g.dest || []).forEach(function (c) { escolha.dest[c] = true; });
    } catch (e) { /* sem armazenamento: começa vazio */ }
  }
  function guardar() {
    try { localStorage.setItem(CHAVE, JSON.stringify({ ar: Object.keys(escolha.ar).map(Number), dest: Object.keys(escolha.dest).map(Number) })); }
    catch (e) { /* vale até recarregar */ }
  }

  function aviso(texto, ruim) {
    var p = $("ce-aviso");
    if (!texto) { p.hidden = true; return; }
    p.textContent = texto;
    p.className = "ce-aviso" + (ruim ? " ce-aviso--ruim" : "");
    p.hidden = false;
    clearTimeout(aviso.t);
    aviso.t = setTimeout(function () { p.hidden = true; }, ruim ? 9000 : 5000);
  }

  /* ---------- escolher / destacar ---------- */
  function podeEscolher(r) { return r && r.ok; }

  function alternarAr(codigo) {
    var r = porCodigo(codigo);
    if (escolha.ar[codigo]) { delete escolha.ar[codigo]; delete escolha.dest[codigo]; return true; }
    if (!podeEscolher(r)) { aviso("O " + codigo + " não entra no portal: " + faltaDe(r), true); return false; }
    if (nCh(escolha.ar) >= lim.no_ar) { aviso("O plano leva " + lim.no_ar + " imóveis; tire algum antes de escolher outro.", true); return false; }
    escolha.ar[codigo] = true;
    return true;
  }
  function alternarDest(codigo) {
    if (escolha.dest[codigo]) { delete escolha.dest[codigo]; return true; }
    if (nCh(escolha.dest) >= lim.destaques) { aviso("O plano leva " + lim.destaques + " destaques; tire algum antes.", true); return false; }
    if (!escolha.ar[codigo] && !alternarAr(codigo)) return false;   // destacar também põe no ar
    escolha.dest[codigo] = true;
    return true;
  }
  function mudou() { guardar(); contas(); renderLista(); if (!$("aba-metricas").hidden) renderMetricas(); }

  /* ---------- os dados ---------- */
  function porCodigo(c) { return (d && d.imoveis || []).filter(function (r) { return Number(r.codigo) === Number(c); })[0]; }
  function faltaDe(r) {
    if (!r) return "não achei o imóvel";
    if (r.ok) return "";
    if (!r.candidato) return r.parceiro ? "é de parceiro" : "não está Disponível no site (" + (r.status || "sem situação") + ")";
    var f = r.falta; try { if (typeof f === "string") f = JSON.parse(f); } catch (e) { /* fica como veio */ }
    return Array.isArray(f) && f.length ? f.join("; ") : "falta dado";
  }

  function carregar(dias) {
    $("ce-contagem").textContent = "Carregando…";
    return fetch("api/chavesnamao/painel?dias=" + dias, { credentials: "same-origin", cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("A API respondeu " + r.status); return r.json(); })
      .then(function (j) {
        d = j; lim = j.limites || lim;
        document.querySelectorAll(".ce-lim-ar, #ce-lim-ar").forEach(function (e) { e.textContent = lim.no_ar; });
        document.querySelectorAll(".ce-lim-dest, #ce-lim-dest").forEach(function (e) { e.textContent = lim.destaques; });
        document.querySelectorAll(".ce-dias").forEach(function (e) { e.textContent = j.dias; });
        // a escolha guardada vale só para o que ainda entra no portal
        Object.keys(escolha.ar).forEach(function (c) { var r = porCodigo(c); if (!r || !r.ok) { delete escolha.ar[c]; delete escolha.dest[c]; } });
        Object.keys(escolha.dest).forEach(function (c) { if (!escolha.ar[c]) delete escolha.dest[c]; });
        guardar();
        opcoes();
        contas();
        filtrar();
        if (!$("aba-metricas").hidden) renderMetricas();
        $("ce-gerado").textContent = "dados de " + new Date(j.gerado_em).toLocaleString("pt-BR");
      })
      .catch(function (e) { $("ce-contagem").textContent = "Não consegui carregar: " + e.message; });
  }

  function opcoes() {
    function preencher(id, valores) {
      var s = $(id), atual = s.value;
      s.innerHTML = '<option value="">Todos</option>' + valores.map(function (v) { return '<option>' + esc(v) + "</option>"; }).join("");
      s.value = atual;
    }
    function unicos(campo) {
      var m = {};
      d.imoveis.forEach(function (r) { if (r[campo]) m[r[campo]] = (m[r[campo]] || 0) + 1; });
      return Object.keys(m).sort(function (a, b) { return a.localeCompare(b, "pt-BR"); });
    }
    preencher("ce-tipo", unicos("tipo"));
    preencher("ce-bairro", unicos("bairro"));
  }

  function contas() {
    var ar = nCh(escolha.ar), de = nCh(escolha.dest);
    $("ce-n-ar").textContent = ar; $("ce-n-dest").textContent = de;
    $("ce-n-ar").closest(".ce-conta").classList.toggle("ce-conta--cheia", ar >= lim.no_ar);
    $("ce-n-dest").closest(".ce-conta").classList.toggle("ce-conta--cheia", de >= lim.destaques);
  }

  /* ---------- filtros ---------- */
  function valores() {
    return {
      q: sem($("ce-q").value).trim(), fin: $("ce-fin").value, tipo: $("ce-tipo").value, bairro: $("ce-bairro").value,
      quartos: $("ce-quartos").value, pmin: Number(String($("ce-pmin").value).replace(/\D/g, "")) || 0,
      pmax: Number(String($("ce-pmax").value).replace(/\D/g, "")) || 0, recente: $("ce-recente").value, mov: $("ce-mov").value,
      escolha: $("ce-escolha").value, soOk: $("ce-so-ok").checked, ordem: $("ce-ordem").value,
    };
  }
  function passa(r, v) {
    if (v.soOk && !r.ok) return false;
    if (v.q && sem([r.codigo, r.condominio, r.bairro, r.tipo].join(" ")).indexOf(v.q) < 0) return false;
    if (v.fin && r.finalidade !== v.fin) return false;
    if (v.tipo && r.tipo !== v.tipo) return false;
    if (v.bairro && r.bairro !== v.bairro) return false;
    if (v.quartos && (v.quartos === "4" ? !(r.quartos >= 4) : Number(r.quartos) !== Number(v.quartos))) return false;
    if (v.pmin && !(r.preco >= v.pmin)) return false;
    if (v.pmax && !(r.preco && r.preco <= v.pmax)) return false;
    if (v.recente === "sim" && !r.condo_recente) return false;
    if (v.recente === "nao" && r.condo_recente) return false;
    if (v.mov === "buscados" && !(r.buscados > 0)) return false;
    if (v.mov === "enviados" && !(r.enviados > 0)) return false;
    if (v.mov === "visitas" && !(r.visitas > 0)) return false;
    if (v.mov === "nada" && (r.buscados || r.enviados || r.visitas)) return false;
    if (v.escolha === "no_ar" && !escolha.ar[r.codigo]) return false;
    if (v.escolha === "dest" && !escolha.dest[r.codigo]) return false;
    if (v.escolha === "fora" && escolha.ar[r.codigo]) return false;
    return true;
  }
  var ORDENS = {
    codigo: function (a, b) { return a.codigo - b.codigo; },
    buscados: function (a, b) { return b.buscados - a.buscados || b.enviados - a.enviados || a.codigo - b.codigo; },
    enviados: function (a, b) { return b.enviados - a.enviados || b.buscados - a.buscados || a.codigo - b.codigo; },
    visitas: function (a, b) { return b.visitas - a.visitas || b.buscados - a.buscados || a.codigo - b.codigo; },
    preco_desc: function (a, b) { return (b.preco || 0) - (a.preco || 0); },
    preco_asc: function (a, b) { return (a.preco || 1e12) - (b.preco || 1e12); },
  };
  function filtrar() {
    if (!d) return;
    var v = valores();
    lista = d.imoveis.filter(function (r) { return passa(r, v); }).sort(ORDENS[v.ordem] || ORDENS.codigo);
    pagina = 1;
    renderLista();
  }

  /* ---------- as linhas ---------- */
  function onde(r) {
    return esc(r.condominio || r.bairro || "") + '<span class="ce-sub">' + esc(r.condominio ? r.bairro : "") + "</span>" +
      (r.condominio ? '<span class="ce-pilula' + (r.condo_recente ? " ce-pilula--novo" : "") + '">' + (r.condo_recente ? "recente" + (r.condo_ano ? " " + r.condo_ano : "") : "antigo") + "</span>" : "");
  }
  function detalhes(r) {
    return [r.quartos != null ? r.quartos + " qts" : "", r.suites ? r.suites + " suíte" + (r.suites > 1 ? "s" : "") : "",
      r.vagas ? r.vagas + " vaga" + (r.vagas > 1 ? "s" : "") : "", r.area ? Math.round(r.area) + " m²" : ""].filter(Boolean).join(" · ");
  }
  function preco(r) {
    if (r.valor_venda && r.valor_aluguel) return reais(r.valor_venda) + '<span class="ce-sub">aluguel ' + reais(r.valor_aluguel) + "</span>";
    return r.valor_venda ? reais(r.valor_venda) + '<span class="ce-sub">venda</span>' : reais(r.valor_aluguel) + '<span class="ce-sub">aluguel</span>';
  }
  function num(n, titulo) { return '<td class="ce-dir"><span class="ce-num' + (n ? "" : " ce-num--zero") + '" title="' + esc(titulo || "") + '">' + inteiro(n) + "</span></td>"; }
  function capa(r) { return r.capa ? '<img class="ce-capa" loading="lazy" src="' + esc(r.capa) + '" alt="">' : '<span class="ce-capa ce-capa--vazia"></span>'; }

  function linha(r) {
    var ar = !!escolha.ar[r.codigo], de = !!escolha.dest[r.codigo];
    var portal = r.ok ? '<span class="ce-pilula ce-pilula--ok">entra</span>' : '<span class="ce-pilula ce-pilula--ruim" title="' + esc(faltaDe(r)) + '">fora</span><span class="ce-sub">' + esc(faltaDe(r)).slice(0, 60) + "</span>";
    return '<tr class="' + (de ? "ce-destacado" : ar ? "ce-escolhido" : "") + '" data-cod="' + r.codigo + '">' +
      '<td><input type="checkbox" data-ar="' + r.codigo + '"' + (ar ? " checked" : "") + (r.ok ? "" : " disabled") + ' aria-label="Enviar o ' + r.codigo + '"></td>' +
      '<td><input type="checkbox" data-dest="' + r.codigo + '"' + (de ? " checked" : "") + (r.ok ? "" : " disabled") + ' aria-label="Destacar o ' + r.codigo + '"></td>' +
      '<td><div class="ce-imovel">' + capa(r) + '<span><span class="ce-cod"><a href="' + esc(r.pagina) + '" target="_blank" rel="noopener">#' + r.codigo + "</a></span>" +
      '<span class="ce-sub">' + esc(r.tipo || "") + "</span></span></div></td>" +
      "<td>" + onde(r) + '<span class="ce-sub">' + esc(detalhes(r)) + "</span></td>" + '<td class="ce-dir">' + preco(r) + "</td>" +
      num(r.enviados, "pessoas que receberam o imóvel pela Nay") + num(r.visitas, "visitas pedidas ou feitas") + num(r.buscados, "pessoas que pediram esse imóvel") +
      "<td>" + portal + "</td></tr>";
  }

  function renderLista() {
    if (!d) return;
    var total = lista.length, paginas = Math.max(1, Math.ceil(total / POR_PAGINA));
    pagina = Math.min(pagina, paginas);
    var fatia = lista.slice((pagina - 1) * POR_PAGINA, pagina * POR_PAGINA);
    $("ce-corpo").innerHTML = fatia.length ? fatia.map(linha).join("") : '<tr><td colspan="9">Nenhum imóvel com esses filtros.</td></tr>';
    $("ce-contagem").textContent = inteiro(total) + " imóve" + (total === 1 ? "l" : "is") + " (de " + inteiro(d.imoveis.length) + ")";
    $("ce-paginacao").innerHTML = paginas > 1 ?
      '<button type="button" class="btn-neutro" data-pag="-1"' + (pagina <= 1 ? " disabled" : "") + '>Anterior</button><span>' + pagina + " de " + paginas +
      '</span><button type="button" class="btn-neutro" data-pag="1"' + (pagina >= paginas ? " disabled" : "") + ">Próxima</button>" : "";
  }

  /* ---------- ações em massa ---------- */
  function escolherLista(itens, destacar) {
    var feitos = 0, parou = "";
    itens.forEach(function (r) {
      if (parou || !r.ok) return;
      if (destacar) {
        if (escolha.dest[r.codigo]) return;
        if (nCh(escolha.dest) >= lim.destaques) { parou = "Parei: o plano leva " + lim.destaques + " destaques."; return; }
        if (!escolha.ar[r.codigo] && nCh(escolha.ar) >= lim.no_ar) { parou = "Parei: o plano leva " + lim.no_ar + " imóveis."; return; }
        escolha.ar[r.codigo] = true; escolha.dest[r.codigo] = true; feitos++;
      } else {
        if (escolha.ar[r.codigo]) return;
        if (nCh(escolha.ar) >= lim.no_ar) { parou = "Parei: o plano leva " + lim.no_ar + " imóveis."; return; }
        escolha.ar[r.codigo] = true; feitos++;
      }
    });
    mudou();
    aviso((destacar ? "Destacados: " : "Escolhidos: ") + feitos + (parou ? ". " + parou : "."), !!parou);
  }

  /* ---------- gerar o arquivo ---------- */
  function gerar(formato) {
    var ids = Object.keys(escolha.ar).map(Number), dest = Object.keys(escolha.dest).map(Number);
    if (!ids.length) { aviso("Escolha ao menos um imóvel.", true); return; }
    var botoes = [$("ce-gerar-xml"), $("ce-gerar-planilha")];
    botoes.forEach(function (b) { b.disabled = true; });
    aviso("Gerando o arquivo…");
    fetch("api/chavesnamao/exportar", {
      method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ids: ids, destaques: dest, formato: formato, fotos: $("ce-fotos-reais").checked ? "reais" : "pagina" }),
    }).then(function (r) {
      if (!r.ok) return r.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.erro || "A API respondeu " + r.status); });
      var nome = (/filename="([^"]+)"/.exec(r.headers.get("Content-Disposition") || "") || [])[1] || "chaves-na-mao.xml";
      return r.blob().then(function (b) {
        var a = document.createElement("a");
        a.href = URL.createObjectURL(b); a.download = nome; document.body.appendChild(a); a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
        aviso("Pronto: " + nome + " (" + ids.length + " imóveis, " + dest.length + " em destaque).");
      });
    }).catch(function (e) { aviso(e.message, true); })
      .then(function () { botoes.forEach(function (b) { b.disabled = false; }); });
  }

  /* ---------- as métricas ---------- */
  function barras(titulo, itens, classe) {
    var max = Math.max.apply(null, itens.map(function (i) { return i.n; }).concat([1]));
    return '<div class="cartao ce-barras"><h3>' + esc(titulo) + "</h3>" + (itens.length ? itens.map(function (i) {
      return '<div class="ce-barra-linha"><span title="' + esc(i.nome) + '">' + esc(i.nome) + (i.extra || "") + '</span><span class="ce-trilho ' + (classe || "") + '"><i style="width:' +
        Math.max(2, Math.round(i.n * 100 / max)) + '%"></i></span><b>' + inteiro(i.n) + "</b></div>";
    }).join("") : '<p class="ce-vazio">Sem dados no período.</p>') + "</div>";
  }
  function card(n, r, s) { return '<div class="cartao ce-card"><div class="ce-card__n">' + n + '</div><div class="ce-card__r">' + esc(r) + "</div>" + (s ? '<div class="ce-card__s">' + esc(s) + "</div>" : "") + "</div>"; }

  function ranking(titulo, campo, unidade) {
    var topo = d.imoveis.filter(function (r) { return r[campo] > 0; }).sort(function (a, b) { return b[campo] - a[campo] || a.codigo - b.codigo; }).slice(0, 10);
    return '<div class="cartao ce-rank"><h3>' + esc(titulo) + "</h3>" + (topo.length ? "<ol>" + topo.map(function (r, i) {
      var ar = !!escolha.ar[r.codigo], de = !!escolha.dest[r.codigo];
      return "<li><span class=\"ce-rank__pos\">" + (i + 1) + "</span>" + capa(r) + "<span><b><a href=\"" + esc(r.pagina) + "\" target=\"_blank\" rel=\"noopener\">#" + r.codigo + "</a></b> " +
        esc(r.tipo || "") + " · " + esc(r.condominio || r.bairro || "") + '<span class="ce-sub">' + esc((r.preco ? reais(r.preco) + (r.finalidade === "aluguel" ? "/mês" : "") : "") + (r.condo_recente ? " · condomínio recente" : "")) + "</span>" +
        (r.ok ? '<span class="ce-rank__acoes"><button type="button" class="ce-mini' + (ar ? " ce-mini--on" : "") + '" data-ar="' + r.codigo + '">' + (ar ? "no ar ✓" : "+ no ar") + "</button>" +
          '<button type="button" class="ce-mini ce-mini--dest' + (de ? " ce-mini--on" : "") + '" data-dest="' + r.codigo + '">' + (de ? "destaque ✓" : "+ destaque") + "</button></span>" : "") +
        '</span><span class="ce-rank__n" title="' + esc(unidade) + '">' + inteiro(r[campo]) + "</span></li>";
    }).join("") + "</ol>" : '<p class="ce-vazio">Sem dados no período.</p>') + "</div>";
  }

  function renderMetricas() {
    if (!d) return;
    var s = d.resumo, dm = d.demanda || {};
    var html = '<div class="ce-grade">' +
      card(inteiro(dm.pedidos), "pedidos de clientes", "leads que disseram o que procuram") +
      card(inteiro(s.imoveis_buscados), "imóveis buscados", inteiro(s.buscas) + " buscas no total") +
      card(inteiro(s.enviados), "envios a clientes", "pessoas × dia que receberam um imóvel") +
      card(inteiro(s.em_grupos), "envios em grupos", "ofertas nos grupos de corretores") +
      card(inteiro(s.visitas), "visitas", "pedidas ou feitas") + "</div>";

    html += '<h2 class="ce-titulo">O que os clientes procuram</h2><div class="ce-dois">' +
      barras("Aluguel × venda (pedidos dos clientes)", [{ nome: "Aluguel", n: dm.locacao || 0 }, { nome: "Venda", n: dm.venda || 0 }]) +
      barras("Aluguel × venda (imóveis buscados, por busca)", [{ nome: "Aluguel", n: s.buscas_aluguel }, { nome: "Venda", n: s.buscas_venda }, { nome: "Venda e aluguel", n: s.buscas_ambos }], "ce-trilho--b") +
      barras("Condomínio recente × antigo (imóveis buscados, por busca)", [{ nome: "Condomínio recente", n: s.buscas_em_recentes }, { nome: "Antigo ou sem condomínio", n: s.buscas_em_antigos }], "ce-trilho--c") +
      ((dm.em_condominio_recente || 0) + (dm.em_condominio_antigo || 0) >= 5
        ? barras("Condomínio recente × antigo (pedidos que citam condomínio)", [{ nome: "Recente", n: dm.em_condominio_recente || 0 }, { nome: "Antigo", n: dm.em_condominio_antigo || 0 }], "ce-trilho--c") : "") +
      "</div>" +
      ((dm.em_condominio_recente || 0) + (dm.em_condominio_antigo || 0) < 5
        ? '<p class="ce-nota">Poucos pedidos citam um condomínio pelo nome (' + ((dm.em_condominio_recente || 0) + (dm.em_condominio_antigo || 0)) + " de " + inteiro(dm.pedidos) +
          "): a maioria chega pelo anúncio do imóvel. Por isso o recente × antigo vale pelos imóveis buscados, no gráfico ao lado.</p>" : "");

    html += '<div class="ce-grade">' +
      card(reais(s.preco_medio_venda) || "—", "preço médio dos imóveis de venda buscados", "teto médio pedido: " + (reais(dm.teto_medio_venda) || "—")) +
      card(reais(s.preco_medio_aluguel) || "—", "preço médio dos imóveis de aluguel buscados", "teto médio pedido: " + (reais(dm.teto_medio_locacao) || "—")) + "</div>";

    html += '<div class="ce-dois">' +
      barras("Tipos pedidos", (dm.tipos || []).map(function (t) { return { nome: t.tipo.replace("_", " "), n: t.n }; })) +
      barras("Bairros mais pedidos", (dm.bairros || []).map(function (b) { return { nome: b.bairro, n: b.n }; }), "ce-trilho--b") +
      barras("Condomínios mais pedidos", (dm.condominios || []).map(function (c) { return { nome: c.nome, n: c.n, extra: c.recente === true ? " · recente" : c.recente === false ? " · antigo" : "" }; }), "ce-trilho--c") + "</div>";

    html += '<h2 class="ce-titulo">Os melhores por categoria <span class="ce-fonte">(use “+ destaque” para levar direto à escolha)</span></h2><div class="ce-rankings">' +
      ranking("Mais mandados a clientes", "enviados", "pessoas × dia") + ranking("Mais visitados", "visitas", "visitas") + ranking("Mais buscados", "buscados", "pessoas que pediram") + "</div>";

    html += '<h2 class="ce-titulo">Todos os imóveis com movimento</h2><p class="ce-nota">Mesma lista do /imoveis, com os números do período. Buscas = pessoas que chegaram por esse imóvel, citaram o código ou o link ou pediram na página “me envia”. Clique no título de uma coluna para ordenar.</p>' +
      '<div class="ce-acoes"><input class="entrada" id="ce-m-q" type="search" placeholder="Filtrar por código, condomínio, bairro" value="' + esc(ordemMetricas.q) + '" style="max-width:340px"></div>' +
      '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela ce-tabela"><thead><tr>' +
      '<th>Enviar</th><th>Destaque</th><th>Imóvel</th><th>Onde</th>' +
      cab("preco", "Preço") + cab("enviados", "Enviados") + cab("visitas", "Visitas") + cab("buscados", "Buscas") + "<th>Portal</th></tr></thead><tbody id=\"ce-m-corpo\"></tbody></table></div></div>";
    $("ce-metricas").innerHTML = html;
    corpoMetricas();
  }
  function cab(campo, rotulo) {
    var on = ordemMetricas.campo === campo;
    return '<th class="ce-dir ce-ordem" data-ord="' + campo + '">' + rotulo + (on ? (ordemMetricas.sentido < 0 ? " ▾" : " ▴") : "") + "</th>";
  }
  function corpoMetricas() {
    var q = sem(ordemMetricas.q).trim(), c = ordemMetricas.campo, sg = ordemMetricas.sentido;
    var itens = d.imoveis.filter(function (r) { return (r.buscados + r.enviados + r.visitas + r.em_grupos > 0) && (!q || sem([r.codigo, r.condominio, r.bairro, r.tipo].join(" ")).indexOf(q) >= 0); })
      .sort(function (a, b) { return sg * ((a[c] || 0) - (b[c] || 0)) || a.codigo - b.codigo; });
    $("ce-m-corpo").innerHTML = itens.length ? itens.map(linha).join("") : '<tr><td colspan="9">Nenhum imóvel.</td></tr>';
  }

  /* ---------- as abas e os eventos ---------- */
  function aba(nome) {
    ["escolher", "metricas"].forEach(function (a) { $("aba-" + a).hidden = a !== nome; });
    document.querySelectorAll("#ce-abas .abas__item").forEach(function (b) { b.setAttribute("aria-selected", String(b.dataset.aba === nome)); });
    if (nome === "metricas") renderMetricas();
    try { history.replaceState(null, "", nome === "metricas" ? "#metricas" : location.pathname + location.search); } catch (e) { /* endereço fica */ }
  }

  document.addEventListener("click", function (e) {
    var t = e.target.closest ? e.target.closest("[data-aba],[data-ar],[data-dest],[data-pag],[data-ord],button[id]") : null;
    if (!t) return;
    if (t.dataset.aba && t.closest("#ce-abas")) return aba(t.dataset.aba);
    if (t.dataset.pag) { pagina += Number(t.dataset.pag); renderLista(); return window.scrollTo({ top: 0, behavior: "smooth" }); }
    if (t.dataset.ord) {
      ordemMetricas = { campo: t.dataset.ord, sentido: ordemMetricas.campo === t.dataset.ord ? -ordemMetricas.sentido : -1, q: ordemMetricas.q };
      return renderMetricas();
    }
    if (t.dataset.ar && t.matches("input, button")) { alternarAr(t.dataset.ar); mudou(); return; }
    if (t.dataset.dest && t.matches("input, button")) { alternarDest(t.dataset.dest); mudou(); return; }
    switch (t.id) {
      case "ce-gerar-xml": return gerar("xml");
      case "ce-gerar-planilha": return gerar("planilha");
      case "ce-limpar":
        if (window.confirm("Tirar todos os imóveis da escolha?")) { escolha = { ar: {}, dest: {} }; mudou(); }
        return;
      case "ce-marcar-filtrados": return escolherLista(lista, false);
      case "ce-desmarcar-filtrados":
        lista.forEach(function (r) { delete escolha.ar[r.codigo]; delete escolha.dest[r.codigo]; }); return mudou();
      case "ce-top-escolher": return escolherLista(lista.slice(0, Math.max(1, Number($("ce-n-top").value) || 20)), false);
      case "ce-top-destacar": return escolherLista(lista.slice(0, Math.max(1, Number($("ce-n-top").value) || 20)), true);
      case "ce-atualizar": return carregar(Number($("ce-janela").value) || 60);
      default:
    }
  });
  // checkbox: o clique já mudou o estado do campo; refazemos a tela pela escolha
  document.addEventListener("change", function (e) {
    var t = e.target;
    if (t.id === "ce-janela") return carregar(Number(t.value) || 60);
    if (t.closest && t.closest("#ce-filtros")) filtrar();
  });
  document.addEventListener("input", function (e) {
    var t = e.target;
    if (t.id === "ce-m-q") { ordemMetricas.q = t.value; corpoMetricas(); return; }
    if (t.closest && t.closest("#ce-filtros") && (t.type === "search" || t.type === "text")) { clearTimeout(input.t); input.t = setTimeout(filtrar, 200); }
  });
  function input() {}
  $("ce-filtros").addEventListener("reset", function () { setTimeout(filtrar, 0); });
  $("ce-filtros").addEventListener("submit", function (e) { e.preventDefault(); });

  ler();
  if (location.hash === "#metricas") aba("metricas");
  carregar(60);
})();
