/* ==========================================================================
   Imob Easy — Tela de Imóveis (UX nova, 26/09/2026)

   Tel: "quero refazer a parte de imoveis no site para deixar mais
   profissional... eu tb pedi para uma ia refazer a ux da página de imoveis é
   um html dentro de site antigo tb acha la e implementa no site online".

   O QUE MUDA EM RELAÇÃO AO `imoveis-lista.js` QUE ESTAVA AQUI

   1. A CONTAGEM AO LADO DE CADA OPÇÃO. O filtro passou a ser mapa do acervo:
      antes de clicar em "Alugado" você já vê que são 793. Vem de `facetas`,
      contado no banco, e cada grupo é contado ignorando ele mesmo -- senão o
      número do lado de "Alugado" viraria 0 no instante em que você marca
      "Disponível".

   2. SITUAÇÃO E ANÚNCIO SEPARADOS. Antes um imóvel disponível e fora do site
      aparecia como "Fora do site" e perdia a situação. São duas perguntas
      diferentes: o que acontece com o imóvel (disponível, alugado, vendido) e
      se nós o anunciamos.

   3. O FILTRO DE DATA EM DOIS PASSOS -- qual data, depois qual período. Com as
      duas datas que existem de verdade: fim do contrato de aluguel e cadastro.

   4. OS ATALHOS. Três perguntas que o Tel faz toda semana, cada uma com o seu
      número na cara: contratos terminando, disponível sem foto, disponível
      fora do site.

   O que veio de antes e continua: o popup de proprietário pela rota COM SENHA
   (telefone de dono não sai pela API aberta), o seletor de condomínio, o
   filtro de parceiro e o CSV.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE;
  var POR_PAGINA = 50;
  var form = document.getElementById("filtros-imoveis");
  var corpo = document.getElementById("corpo-imoveis");
  var paginacao = document.getElementById("paginacao-imoveis");

  /* Onde termina o menu de cima NA TELA (0 quando ele ja saiu de vista). Ele
     muda de altura conforme a largura e, nesta pagina, rola junto -- entao e
     medido, nao chutado. A lateral fixa e a volta ao topo da lista usam isto. */
  function alturaDoMenu() {
    var nav = document.querySelector(".nav-principal");
    return nav ? Math.max(0, Math.round(nav.getBoundingClientRect().bottom)) : 0;
  }
  var medindo = false;
  function medirTopo() {
    if (medindo) return;
    medindo = true;
    requestAnimationFrame(function () {
      medindo = false;
      document.documentElement.style.setProperty("--ux-topo", (alturaDoMenu() + 12) + "px");
    });
  }
  medirTopo();
  window.addEventListener("resize", medirTopo);
  window.addEventListener("scroll", medirTopo, { passive: true });

  /* ---- o estado da tela -------------------------------------------- */
  var st = {
    page: 1, grupo: "", status: [],
    quartos: "", vagas: "", fin: "", financia: "", anuncio: "", foto: "",
    dono: "", parceiro: "", confirmar: "",
    dataCampo: "", dataPer: "", dataMeses: "",
    vista: "tabela"   // "tabela" | "mapa" (a aba Mapa, 28/09)
  };
  var ultimo = { itens: [], total: 0, facetas: {} };
  var pedido = 0;

  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function $(id) { return document.getElementById(id); }
  function brl(v) {
    return (v || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
  }
  function soDigitos(s) { return String(s || "").replace(/\D/g, ""); }
  function dt(iso) { return iso ? new Date(iso + "T00:00:00").toLocaleDateString("pt-BR") : ""; }
  function dias(iso) {
    if (!iso) return null;
    return Math.round((new Date(iso + "T00:00:00") - new Date(new Date().toDateString())) / 864e5);
  }

  /* BAIRROS, TIPOS E CONDOMÍNIOS: VÁRIOS DE UMA VEZ (Pedro, 28/09: "não
     consigo selecionar vários bairros, quero os filtros dos imóveis igual os
     filtros daquele enviar"). O mesmo campo do Enviar imóvel: digita, a lista
     do banco desce com a conta de cada um, escolhe quantos quiser. As opções
     vêm de /api/imoveis/opcoes, lá embaixo. */
  function aoMudarFiltro() { recomecar(); }
  var msBairrosL = window.criarMultiSelecao($("f-bairros"), { dica: "todos os bairros", aoMudar: aoMudarFiltro });
  var msTiposL = window.criarMultiSelecao($("f-tipos"), { dica: "todos os tipos", aoMudar: aoMudarFiltro });
  var msCondosL = window.criarMultiSelecao($("f-condominios"), { dica: "todos os condomínios", aoMudar: aoMudarFiltro });
  /* CONJUNTO E AVENIDA (Pedro, 30/09: "quero essas listas de filtros lá no nosso
     site, para pesquisar por conjunto ou avenida"). As mesmas listas da Nay
     (nai_lugar_conjunto / nai_lugar_avenida): o conjunto traz o bairro dele, a
     avenida traz os bairros por onde passa. Somam com os bairros marcados. */
  // HTML antigo no cache (sem os dois campos) não pode derrubar a tela
  function msSeTiver(el, cfg) {
    return el ? window.criarMultiSelecao(el, cfg)
      : { valores: function () { return []; }, definir: function () {}, opcoes: function () {}, limpar: function () {} };
  }
  var msConjuntosL = msSeTiver($("f-conjuntos"), { dica: "digite o conjunto", aoMudar: aoMudarFiltro });
  var msAvenidasL = msSeTiver($("f-avenidas"), { dica: "digite a avenida", aoMudar: aoMudarFiltro });
  // ZONA (229): leste, norte, oeste, sul, centro-sul, centro-oeste -- os bairros dela
  var msZonasL = msSeTiver($("f-zonas"), { dica: "todas as zonas", aoMudar: aoMudarFiltro });
  var MS_DA_LISTA = { bairros: [msBairrosL, "Bairro"], zonas: [msZonasL, "Zona"], conjuntos: [msConjuntosL, "Conjunto"],
                      avenidas: [msAvenidasL, "Avenida"], tipos: [msTiposL, "Tipo"], condominios: [msCondosL, "Condomínio"] };
  // o link de outra tela (?condo=ID) continua filtrando pelo id do condomínio
  var condoDoLink = null;

  /* ---- os grupos de opção, do jeito que a lateral desenha ----------
     `multi` = dá pra marcar mais de um (só a situação é assim).
     `faceta` = de onde sai o número do lado.                          */
  var GRUPOS = {
    status: {
      chave: "status", multi: true, faceta: "status", grupo: "sit",
      itens: [["Disponível", "Disponível", "#3f9c6d"], ["Alugado", "Alugado", "#7c3aed"],
              ["Vendido", "Vendido", "#8a8296"], ["Rascunho", "Rascunho", "#8a8296"],
              ["Em revisão", "Em revisão", "#c4762f"], ["Arquivado", "Arquivado", "#8a8296"],
              ["Removido", "Removido", "#b42323"], ["Indisponível", "Indisponível", "#b42323"],
              // o excluído some da lista; só aparece marcando aqui (e daqui volta)
              ["Excluído", "Excluído", "#5d566a"]]
    },
    confirmar: { chave: "confirmar", faceta: "confirmar", grupo: "sit", itens: [["sim", "Precisa confirmar"]] },
    quartos: { chave: "quartos", faceta: "quartos", grupo: "imovel",
               itens: [["1", "1+"], ["2", "2+"], ["3", "3+"], ["4", "4+"]] },
    vagas: { chave: "vagas", faceta: "vagas", grupo: "imovel",
             itens: [["1", "1+"], ["2", "2+"], ["3", "3+"], ["4", "4+"]] },
    anuncio: { chave: "anuncio", faceta: "anuncio", grupo: "anuncio",
               itens: [["sim", "No site"], ["nao", "Fora do site"]] },
    foto: { chave: "foto", faceta: "foto", grupo: "anuncio",
            itens: [["sim", "Com foto"], ["nao", "Sem foto"]] },
    /* 244 (Pedro, 30/09): "uma pontuação de 0 a 100% de quantas informações temos
       sobre o imóvel, quem tá completo 100% e os que faltarem menos". A régua é do
       banco (nai_imovel_pontos): o essencial para a Nay oferecer pesa mais. */
    cadastro: { chave: "cadastro", faceta: "cadastro", grupo: "anuncio",
                itens: [["100", "100% completo", "#3f9c6d"], ["90", "90 a 99%", "#3f9c6d"],
                        ["75", "75 a 89%", "#c4762f"], ["50", "50 a 74%", "#c4762f"],
                        ["baixo", "abaixo de 50%", "#b42323"]] },
    fin: { chave: "fin", faceta: "fin", grupo: "valor",
           itens: [["aluguel", "Aluguel"], ["venda", "Venda"]] },
    financia: { chave: "financia", faceta: "financia", grupo: "valor",
                itens: [["Sim", "Sim"], ["Não", "Não"]] },
    dono: { chave: "dono", faceta: "dono", grupo: "dono",
            itens: [["com", "Com proprietário"], ["sem", "Sem proprietário"]] },
    parceiro: { chave: "parceiro", faceta: "parceiro", grupo: "dono",
                itens: [["nao", "Nosso (proprietário)"], ["sim", "De parceiro"]] }
  };
  var NOME = {
    status: "Situação", confirmar: "Situação", quartos: "Quartos", vagas: "Vagas",
    anuncio: "Anúncio", foto: "Fotos", cadastro: "Cadastro", fin: "Finalidade", financia: "Financia",
    dono: "Proprietário", parceiro: "De quem é"
  };

  /* As duas datas que existem no banco. "Disponível desde" e "última
     confirmação do proprietário" ficaram de fora porque não existem em coluna
     nenhuma -- virariam filtro que mente. */
  var QUAL_DATA = [
    ["vencimento", "Fim do contrato de aluguel", "futuro"],
    ["criado", "Data de cadastro", "passado"]
  ];
  var PERIODO = {
    futuro: [["vencido", "Já venceu"], ["semana", "Esta semana"], ["15", "Próximos 15 dias"],
             ["30", "Próximos 30 dias"], ["90", "Próximos 90 dias"], ["semdata", "Sem data cadastrada"]],
    passado: [["semana", "Últimos 7 dias"], ["15", "Há mais de 15 dias"],
              ["30", "Há mais de 30 dias"], ["90", "Há mais de 90 dias"]]
  };

  /* ---- os atalhos: as perguntas que ele faz toda semana ------------ */
  var ATALHOS = [
    { t: "contratos terminando em 90 dias", cor: "atalho--morno",
      aplicar: function () { limparFiltros(); st.dataCampo = "vencimento"; st.dataPer = "90"; } },
    { t: "disponíveis sem foto", cor: "atalho--alerta",
      aplicar: function () { limparFiltros(); st.status = ["Disponível"]; st.foto = "nao"; st.parceiro = "nao"; } },
    { t: "disponíveis fora do site", cor: "atalho--morno",
      aplicar: function () { limparFiltros(); st.status = ["Disponível"]; st.anuncio = "nao"; st.parceiro = "nao"; } },
    { t: "precisam confirmar com o dono", cor: "",
      aplicar: function () { limparFiltros(); st.confirmar = "sim"; } }
  ];
  /* Quanto dá cada atalho. Vem de uma consulta só, sem filtro, na primeira
     carga -- é número de acervo, não muda com o que está filtrado. */
  var contaAtalho = [null, null, null, null];

  function limparFiltros() {
    st.status = []; st.quartos = ""; st.vagas = ""; st.fin = ""; st.financia = "";
    st.anuncio = ""; st.foto = ""; st.dono = ""; st.parceiro = ""; st.confirmar = "";
    st.dataCampo = ""; st.dataPer = ""; st.dataMeses = "";
    $("busca-imovel").value = "";
    form.elements.vmin.value = ""; form.elements.vmax.value = "";
    Object.keys(MS_DA_LISTA).forEach(function (k) { MS_DA_LISTA[k][0].limpar(); });
    condoDoLink = null;
  }

  /* ---- o endereço da consulta -------------------------------------- */
  function parametros(extra) {
    var p = new URLSearchParams();
    function pos(k, v) { if (v !== null && v !== undefined && String(v).trim() !== "") p.set(k, String(v).trim()); }
    pos("q", $("busca-imovel").value);
    pos("status", st.status.join(","));
    pos("grupo", st.grupo);
    Object.keys(MS_DA_LISTA).forEach(function (k) {
      MS_DA_LISTA[k][0].valores().forEach(function (v) { p.append(k, v); });
    });
    if (condoDoLink) p.set("condo_ids", String(condoDoLink.id));
    pos("finalidade", st.fin);
    pos("vmin", soDigitos(form.elements.vmin.value));
    pos("vmax", soDigitos(form.elements.vmax.value));
    if (st.quartos) p.set("quartos", st.quartos + "+");
    if (st.vagas) p.set("vagas", st.vagas + "+");
    if (st.financia) p.set("financia", st.financia);
    if (st.anuncio) p.set("anunciado", st.anuncio);
    if (st.foto) p.set("com_foto", st.foto);
    if (st.confirmar) p.set("confirmar", "1");
    if (st.dono === "sem") p.set("sem_dono", "1");
    if (st.dono === "com") p.set("com_dono", "1");
    if (st.parceiro) p.set("parceiro", st.parceiro);
    pos("data_campo", st.dataCampo);
    pos("data_per", st.dataPer);
    pos("data_meses", st.dataMeses);
    pos("ordem", $("f-ordenar").value);
    Object.keys(extra || {}).forEach(function (k) { p.set(k, extra[k]); });
    return p;
  }

  /* ---- desenhar a lateral ------------------------------------------ */
  function n(faceta, valor) {
    var f = ultimo.facetas[faceta];
    var v = f ? f[valor] : null;
    return v === undefined || v === null ? "" : '<span class="n">' + v + "</span>";
  }

  function desenharOpcoes() {
    // A lateral e redesenhada inteira; sem isto o botao clicado some debaixo do
    // foco (quem usa teclado perde o lugar).
    var focado = document.activeElement && document.activeElement.dataset
      ? [document.activeElement.dataset.grupoOp, document.activeElement.dataset.v] : null;
    Object.keys(GRUPOS).forEach(function (k) {
      var alvo = form.querySelector('.ux-ops[data-f="' + k + '"]');
      if (!alvo) return;
      var g = GRUPOS[k];
      var escolhido = st[g.chave];
      alvo.innerHTML = g.itens.map(function (it) {
        var marcado = g.multi ? escolhido.indexOf(it[0]) >= 0 : escolhido === it[0];
        var conta = ultimo.facetas[g.faceta] ? ultimo.facetas[g.faceta][it[0]] : null;
        // opção que não daria nenhum imóvel fica apagada, mas clicável nunca
        // some da tela -- some o número é que confunde.
        return '<button type="button" class="op" data-grupo-op="' + k + '" data-v="' + esc(it[0]) + '"' +
          ' aria-pressed="' + (marcado ? "true" : "false") + '"' + (conta === 0 && !marcado ? " disabled" : "") + ">" +
          (it[2] ? '<span class="bol" style="background:' + it[2] + '"></span>' : "") +
          esc(it[1]) + n(g.faceta, it[0]) + "</button>";
      }).join("");
    });

    if (focado && focado[0]) {
      var volta = form.querySelector('[data-grupo-op="' + focado[0] + '"][data-v="' + focado[1] + '"]');
      if (volta && !volta.disabled) volta.focus({ preventScroll: true });
    }

    // o contador de cada grupo do acordeão
    var porGrupo = { sit: 0, imovel: 0, anuncio: 0, onde: 0, valor: 0, dono: 0 };
    Object.keys(GRUPOS).forEach(function (k) {
      var g = GRUPOS[k], v = st[g.chave];
      porGrupo[g.grupo] += g.multi ? v.length : (v ? 1 : 0);
    });
    porGrupo.imovel += msTiposL.valores().length;
    porGrupo.onde += msBairrosL.valores().length + msZonasL.valores().length + msConjuntosL.valores().length + msAvenidasL.valores().length +
                     msCondosL.valores().length + (condoDoLink ? 1 : 0);
    if (form.elements.vmin.value || form.elements.vmax.value) porGrupo.valor++;
    form.querySelectorAll(".ux-qtd[data-g]").forEach(function (e) {
      var q = porGrupo[e.dataset.g] || 0;
      e.hidden = !q; e.textContent = q;
    });

    // as abas de tipo
    document.querySelectorAll("[data-conta-tipo]").forEach(function (e) {
      var v = (ultimo.facetas.tipo || {})[e.dataset.contaTipo];
      e.textContent = v === undefined ? "—" : v.toLocaleString("pt-BR");
    });
  }

  function desenharData() {
    /* O cartão "Filtro por data" saiu da tela em 01/10/2026 (pedido do Pedro).
       O filtro em si continua (o atalho dos contratos usa); sem o cartão não
       há o que desenhar. */
    if (!$("qual-data")) return;
    $("qual-data").innerHTML = QUAL_DATA.map(function (q) {
      return '<button type="button" class="op" data-qual="' + q[0] + '" aria-pressed="' +
        (st.dataCampo === q[0] ? "true" : "false") + '">' + q[1] + "</button>";
    }).join("");

    var q = QUAL_DATA.filter(function (x) { return x[0] === st.dataCampo; })[0];
    if (!q) {
      $("periodo-data").innerHTML = '<span class="ux-dica">Escolha uma data no passo 1.</span>';
      $("explica-periodo").textContent = "";
      $("resumo-data").textContent = "Nenhum filtro de data ativo.";
      return;
    }
    $("explica-periodo").textContent = q[2] === "futuro" ? "— contando de hoje para frente" : "— quanto tempo faz";
    $("periodo-data").innerHTML = PERIODO[q[2]].map(function (p) {
      return '<button type="button" class="op" data-per="' + p[0] + '" aria-pressed="' +
        (st.dataPer === p[0] ? "true" : "false") + '">' + p[1] + "</button>";
    }).join("") +
      '<span style="display:inline-flex;gap:5px;align-items:center">' +
      '<input class="ux-meses" id="f-meses" placeholder="nº de meses" value="' + esc(st.dataMeses) + '">' +
      '<button type="button" class="op" data-per="meses" aria-pressed="' + (st.dataPer === "meses" ? "true" : "false") +
      '">' + (q[2] === "futuro" ? "Nos próximos X meses" : "Há mais de X meses") + "</button></span>";

    var frase = {
      semdata: "sem data cadastrada", vencido: "que já venceu",
      semana: q[2] === "futuro" ? "nos próximos 7 dias" : "nos últimos 7 dias",
      meses: (q[2] === "futuro" ? "nos próximos " : "há mais de ") + (st.dataMeses || "?") + " meses"
    }[st.dataPer] || (st.dataPer ? (q[2] === "futuro" ? "nos próximos " : "há mais de ") + st.dataPer + " dias" : "");
    $("resumo-data").innerHTML = st.dataPer
      ? "Mostrando: <b>" + q[1] + "</b> " + frase
      : "Escolha o período no passo 2.";
  }

  function desenharAtivos() {
    var c = [];
    if (st.grupo) {
      var rot = { apartamento: "Apartamentos", casa: "Casas", outros: "Outros" }[st.grupo];
      c.push('<button class="ativo" type="button" data-limpa="grupo">Tipo: ' + rot + "</button>");
    }
    Object.keys(GRUPOS).forEach(function (k) {
      var g = GRUPOS[k], v = st[g.chave];
      (g.multi ? v : (v ? [v] : [])).forEach(function (x) {
        var it = g.itens.filter(function (a) { return a[0] === x; })[0];
        c.push('<button class="ativo" type="button" data-limpa-op="' + k + '" data-v="' + esc(x) + '">' +
          NOME[k] + ": " + esc(it ? it[1] : x) + "</button>");
      });
    });
    if ($("busca-imovel").value) {
      c.push('<button class="ativo" type="button" data-limpa-campo="busca-imovel">Busca: ' +
        esc($("busca-imovel").value) + "</button>");
    }
    Object.keys(MS_DA_LISTA).forEach(function (k) {
      MS_DA_LISTA[k][0].valores().forEach(function (v) {
        c.push('<button class="ativo" type="button" data-limpa-ms="' + k + '" data-v="' + esc(v) + '">' +
          MS_DA_LISTA[k][1] + ": " + esc(v) + "</button>");
      });
    });
    if (condoDoLink) {
      c.push('<button class="ativo" type="button" data-limpa="condo">Condomínio: ' + esc(condoDoLink.nome) + "</button>");
    }
    if (form.elements.vmin.value) c.push('<button class="ativo" type="button" data-limpa="vmin">Mínimo: ' + brl(+soDigitos(form.elements.vmin.value)) + "</button>");
    if (form.elements.vmax.value) c.push('<button class="ativo" type="button" data-limpa="vmax">Máximo: ' + brl(+soDigitos(form.elements.vmax.value)) + "</button>");
    if (st.dataCampo && st.dataPer) {
      var q = QUAL_DATA.filter(function (x) { return x[0] === st.dataCampo; })[0];
      c.push('<button class="ativo" type="button" data-limpa="data">Data: ' + q[1] + "</button>");
    }
    $("ativos").innerHTML = c.join("");
  }

  function desenharAtalhos() {
    $("atalhos").innerHTML = ATALHOS.map(function (a, k) {
      var q = contaAtalho[k];
      return '<button type="button" class="atalho ' + a.cor + '" data-atalho="' + k + '">' +
        "<b>" + (q === null ? "…" : q.toLocaleString("pt-BR")) + "</b>" + a.t + "</button>";
    }).join("");
  }

  /* ---- a linha da tabela ------------------------------------------- */
  var COR_STATUS = {
    "Disponível": "etiqueta--verde", "Alugado": "etiqueta--azul", "Vendido": "etiqueta--cinza-ux",
    "Arquivado": "etiqueta--cinza-ux", "Removido": "etiqueta--vermelha-ux", "Rascunho": "etiqueta--cinza-ux",
    "Em revisão": "etiqueta--laranja", "Indisponível": "etiqueta--vermelha-ux", "Fora do site": "etiqueta--cinza-ux"
  };

  /* OS DOIS PRECOS (28/09). A API manda um "valor" so, e prefere o de venda:
     filtrando por Aluguel, o imovel que tem os dois aparecia com o preco de
     venda. Agora sai cada preco com o seu rotulo, o da finalidade escolhida
     primeiro. */
  function reais(v) {
    return Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  }
  function precos(i) {
    var v = [];
    if (i.valorVenda) v.push(["Venda", i.valorVenda]);
    if (i.valorAluguel) v.push(["Aluguel", i.valorAluguel]);
    if (st.fin === "aluguel" && v.length === 2) v.reverse();
    return v;
  }

  function celulaDatas(i) {
    if (i.vencimento) {
      var r = dias(i.vencimento);
      return '<div class="sub">Contrato até</div>' + dt(i.vencimento) +
        '<div class="sub">' + (r >= 0 ? "faltam " + r + " dias" : "venceu há " + (-r) + " dias") + "</div>";
    }
    if (i.criado) return '<div class="sub">Cadastrado em</div>' + dt(i.criado);
    return '<span class="sub">sem data</span>';
  }

  /* A SITUAÇÃO NA PRÓPRIA LISTA (Pedro, 28/09: "quero poder editar o status lá
     pela lista, ele fica em uma lista suspensa, eu só clico e seleciono o
     status novo"). Grava na hora pela rota do admin (com senha). A situação
     leva junto o anúncio: nosso e Disponível fica no site e na Nay; qualquer
     outra sai dos dois (regra do Tel de 27/09, aplicada no servidor). */
  var SITUACOES = ["Disponível", "Alugado", "Vendido", "Rascunho", "Em revisão", "Arquivado", "Removido", "Indisponível"];
  var COR_SITUACAO = {
    "Disponível": ["#2f7d58", "#e8f7f0"], "Alugado": ["#6d28d9", "#f1eaff"], "Vendido": ["#5d566a", "#efedf3"],
    "Rascunho": ["#5d566a", "#efedf3"], "Em revisão": ["#a8662f", "#fdf2ea"], "Arquivado": ["#5d566a", "#efedf3"],
    "Removido": ["#b42323", "#fdeef1"], "Indisponível": ["#b42323", "#fdeef1"],
    "Excluído": ["#5d566a", "#efedf3"]
  };
  function corDaSituacao(s) {
    var c = COR_SITUACAO[s] || ["#5d566a", "#efedf3"];
    return "--sc:" + c[0] + ";--sb:" + c[1];
  }
  function seletorDeSituacao(i) {
    if (!i.noCatalogo) {
      // imóvel só do admin antigo: não está no catálogo, não dá para gravar
      return '<span class="etiqueta ' + (COR_STATUS[i.status] || "etiqueta--cinza-ux") + '">' + esc(i.status) + "</span>";
    }
    var opcoes = SITUACOES.slice();
    if (opcoes.indexOf(i.status) < 0) opcoes.unshift(i.status);
    return '<select class="ux-situacao" data-situacao-de="' + esc(i.codigo) + '" style="' + corDaSituacao(i.status) +
      '" aria-label="Situação do imóvel ' + esc(i.codigo) + '" title="Mudar a situação">' +
      opcoes.map(function (s) {
        return "<option" + (s === i.status ? " selected" : "") + ">" + esc(s) + "</option>";
      }).join("") + "</select>";
  }

  function mudarSituacao(sel) {
    var cod = sel.getAttribute("data-situacao-de");
    var imovel = (window.IMOVEIS_NA_TELA || {})[cod];
    var antes = imovel ? imovel.status : null;
    var nova = sel.value;
    if (!imovel || nova === antes) return;
    sel.disabled = true;
    fetch("/admin/api/imoveis/" + encodeURIComponent(cod), {
      method: "PUT", credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: nova })
    })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok) throw new Error((d.detalhes && d.detalhes.join("; ")) || d.erro || ("HTTP " + r.status));
          return d;
        });
      })
      .then(function () {
        imovel.status = nova;
        imovel.anunciado = nova === "Disponível" && !imovel.parceiro;
        var tr = sel.closest("tr");
        if (tr) tr.outerHTML = linha(imovel);
        avisar("Imóvel " + cod + ": " + nova + (imovel.anunciado ? " — no site e na Nay." : " — fora do site e da Nay."));
      })
      .catch(function (e) {
        sel.value = antes;
        sel.disabled = false;
        avisar("Não consegui mudar a situação do " + cod + ": " + e.message, true);
      });
  }

  /* EXCLUIR IMÓVEL (Pedro, 01/10/2026: "e também uma opção de excluir imóvel").
     Linha de imóvel nunca se apaga do banco (regra da casa): excluir é a situação
     "Excluído", que tira do site, da Nay e DESTA LISTA. Quem marca "Excluído" no
     filtro de situação vê os excluídos e traz de volta trocando a situação. */
  function excluirImovel(cod) {
    var imovel = (window.IMOVEIS_NA_TELA || {})[cod];
    if (!imovel) return;
    var nome = [imovel.condominio || imovel.tipo, imovel.bairro].filter(Boolean).join(", ");
    if (!window.confirm("Excluir o imóvel " + cod + (nome ? " (" + nome + ")" : "") + "?\n\n" +
        "Ele sai do site, da Nay e desta lista.\n" +
        "Fica guardado em Situação > Excluído, de onde dá para trazer de volta.")) return;
    var botao = document.querySelector('[data-excluir="' + cod + '"]');
    if (botao) botao.disabled = true;
    fetch("/admin/api/imoveis/" + encodeURIComponent(cod), {
      method: "PUT", credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "Excluído" })
    })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok) throw new Error((d.detalhes && d.detalhes.join("; ")) || d.erro || ("HTTP " + r.status));
          return d;
        });
      })
      .then(function () {
        fecharFicha();
        avisar("Imóvel " + cod + " excluído. Está em Situação > Excluído, se precisar voltar.");
        carregar();   // a lista e as contagens, já sem ele
      })
      .catch(function (e) {
        if (botao) botao.disabled = false;
        avisar("Não consegui excluir o " + cod + ": " + e.message, true);
      });
  }

  /* um recado curto no canto, que some sozinho */
  function avisar(texto, erro) {
    var t = document.getElementById("ux-recado");
    if (!t) {
      t = document.createElement("div");
      t.id = "ux-recado";
      t.setAttribute("role", "status");
      document.body.appendChild(t);
    }
    t.textContent = texto;
    t.className = "ux-recado" + (erro ? " ux-recado--erro" : "");
    t.hidden = false;
    clearTimeout(avisar.t);
    avisar.t = setTimeout(function () { t.hidden = true; }, erro ? 7000 : 4000);
  }

  /* 244: o quanto o cadastro está preenchido, com o que falta na dica. Verde do 90
     para cima, âmbar até 50, vermelho abaixo -- a mesma escala do filtro. */
  function selo(i) {
    if (i.cadastroPct == null) return '<span class="sub">—</span>';
    var p = Number(i.cadastroPct);
    var cor = p >= 90 ? "#3f9c6d" : p >= 50 ? "#c4762f" : "#b42323";
    var falta = (i.cadastroFalta || []);
    var dica = falta.length ? "Falta: " + falta.join(", ") : "Cadastro completo";
    return '<span class="pontuacao" title="' + esc(dica) + '">' +
      '<span class="pontuacao__barra"><i style="width:' + p + '%;background:' + cor + '"></i></span>' +
      '<b style="color:' + cor + '">' + p + '%</b></span>' +
      (falta.length ? '<div class="sub">falta ' + esc(falta.slice(0, 2).join(", ")) +
        (falta.length > 2 ? " +" + (falta.length - 2) : "") + "</div>" : "");
  }

  function linha(i) {
    var acoes = i.noCatalogo
      ? '<a class="btn-mini" href="imovel-editar.html?codigo=' + esc(i.codigo) + '">Editar</a>' +
        (i.status === "Excluído" ? "" :
          '<button class="btn-mini btn-mini--perigo" type="button" data-excluir="' + esc(i.codigo) + '">Excluir</button>')
      : '<span class="btn-mini" title="Imóvel só do admin antigo: não está no catálogo, então não abre no editor">só consulta</span>';
    return '<tr data-codigo="' + esc(i.codigo) + '" tabindex="0" class="' + (i.noCatalogo ? "" : "fora-catalogo") + '">' +
      '<td><span class="cod">' + esc(i.codigo) + "</span>" +
        (i.parceiro ? '<div><span class="etiqueta etiqueta--laranja">parceiro</span></div>' : "") +
        (i.capa ? '<img class="miniatura" loading="lazy" src="' + esc(i.capa) + '" alt="">' : "") +
        '<div class="sub">' + (i.fotos ? i.fotos + " foto" + (i.fotos > 1 ? "s" : "") : "sem foto") + "</div></td>" +
      "<td>" + seletorDeSituacao(i) +
        '<div class="sub" style="margin-top:5px">' + (i.anunciado ? "no site" : "fora do site") + "</div>" +
        /* a Nay atende? (Pedro, 02/10: "se tá disponível para mim é para estar para a Nay"): só o
           nosso, Disponível, no site e sem bloqueio chega nela -- o que foge disso fica escrito */
        (i.status === "Disponível" && !i.parceiro
          ? (i.anunciado && !i.bloqueado
              ? '<div class="sub" style="color:#2f7d58">a Nay oferece</div>'
              : '<div><span class="etiqueta etiqueta--laranja" title="Abra o imóvel e ' +
                (i.bloqueado ? "tire o bloqueio" : "ligue o No site") + ' para a Nay voltar a oferecer">a Nay NÃO oferece: ' +
                (i.bloqueado ? "bloqueado" : "fora do site") + "</span></div>")
          : "") +
        (i.precisaConfirmar ? '<div class="sub">precisa confirmar</div>' : "") + "</td>" +
      "<td>" + (precos(i).length
          ? precos(i).map(function (x) {
              return '<div class="sub">' + x[0] + '</div><span class="val">' + reais(x[1]) + "</span>";
            }).join("")
          : '<span class="val">' + esc(i.valor || "Consulte") + "</span>") +
        (i.financia === "Sim" ? '<div class="sub">aceita financiamento</div>' : "") + "</td>" +
      "<td><b>" + esc(i.condominio || "—") + "</b>" +
        '<div class="sub">' + esc([i.tipo, i.quartos ? i.quartos + " quartos" : "",
                                   i.area ? Math.round(i.area) + " m²" : ""].filter(Boolean).join(", ")) + "</div></td>" +
      "<td>" + esc(i.endereco || "—") + '<div class="sub">' + esc(i.bairro || "") + "</div></td>" +
      "<td>" + celulaDatas(i) + "</td>" +
      "<td>" + selo(i) + "</td>" +
      "<td>" + (i.proprietario
        ? '<button type="button" class="btn-mini" data-dono="' + esc(i.codigo) + '">' + esc(i.proprietario) + "</button>"
        : '<span class="sub">sem proprietário</span>') + "</td>" +
      '<td class="col-acoes"><span class="acoes-celula">' +
        '<button class="btn-mini" type="button" data-ver="' + esc(i.codigo) + '">Ver</button>' + acoes +
      "</span></td></tr>";
  }

  function pintarPaginacao(total) {
    var paginas = Math.max(1, Math.ceil(total / POR_PAGINA));
    var p = st.page, nums = [];
    for (var k = Math.max(1, p - 2); k <= Math.min(paginas, p + 2); k++) nums.push(k);
    if (nums[0] > 1) nums = [1].concat(nums[0] > 2 ? ["…"] : []).concat(nums);
    if (nums[nums.length - 1] < paginas) nums = nums.concat(nums[nums.length - 1] < paginas - 1 ? ["…"] : []).concat([paginas]);
    paginacao.innerHTML =
      '<button type="button" data-ir-pagina="' + (p - 1) + '"' + (p <= 1 ? " disabled" : "") + ' aria-label="Página anterior">&laquo;</button>' +
      nums.map(function (x) {
        if (x === "…") return '<span class="reticencias" aria-hidden="true">…</span>';
        return x === p ? '<span class="ativo" aria-current="page">' + x + "</span>"
          : '<button type="button" data-ir-pagina="' + x + '">' + x + "</button>";
      }).join("") +
      '<button type="button" data-ir-pagina="' + (p + 1) + '"' + (p >= paginas ? " disabled" : "") + ' aria-label="Próxima página">&raquo;</button>';
  }

  /* ---- carregar ---------------------------------------------------- */
  function carregar() {
    var meu = ++pedido;
    // AS LINHAS ANTIGAS FICAM ATE CHEGAR A RESPOSTA. Trocar a tabela por uma
    // linha "Carregando..." encolhia a pagina de uma vez, e o navegador puxava
    // a rolagem para cima a cada clique de filtro.
    if (corpo.querySelector("tr[data-codigo]")) corpo.classList.add("ux-carregando");
    else corpo.innerHTML = '<tr><td colspan="8">Carregando…</td></tr>';
    if (st.vista === "mapa") return carregarMapa();   // o mapa tem os filtros dele, em cima
    return fetch(API + "/api/imoveis-lista?" + parametros({ page: st.page, per: POR_PAGINA }).toString())
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        if (meu !== pedido) return;
        corpo.classList.remove("ux-carregando");
        ultimo = d;
        window.IMOVEIS_NA_TELA = {};
        d.itens.forEach(function (i) { window.IMOVEIS_NA_TELA[i.codigo] = i; });
        corpo.innerHTML = d.itens.length ? d.itens.map(linha).join("")
          : '<tr><td colspan="8" style="text-align:center;color:var(--texto-fraco);padding:26px">' +
            "Nenhum imóvel com esses filtros. Tire um filtro acima.</td></tr>";
        var ini = d.total ? (st.page - 1) * POR_PAGINA + 1 : 0;
        $("contagem-imoveis").innerHTML = "<b>" + d.total.toLocaleString("pt-BR") + "</b> imóve" +
          (d.total === 1 ? "l" : "is") +
          (d.total ? " · mostrando " + ini + "–" + Math.min(d.total, st.page * POR_PAGINA) : "");
        $("resumo-imoveis").textContent = "No acervo: " + d.resumo.todos.toLocaleString("pt-BR") +
          " imóveis · " + d.resumo.com_foto.toLocaleString("pt-BR") + " com foto · " +
          d.resumo.parceiros.toLocaleString("pt-BR") + " de parceiro · disponíveis para aluguel " +
          d.resumo.aluguel + ", para venda " + d.resumo.venda;
        desenharOpcoes(); desenharAtivos(); desenharData();
        pintarPaginacao(d.total);
      })
      .catch(function () {
        if (meu !== pedido) return;
        corpo.classList.remove("ux-carregando");
        corpo.innerHTML = '<tr><td colspan="8">Não foi possível carregar os imóveis. ' +
          '<button type="button" class="btn-mini" data-tentar-de-novo>Tentar de novo</button></td></tr>';
      });
  }
  function recomecar() { st.page = 1; return carregar(); }

  /* ---- sugestões por perto (Tel, 28/09) ------------------------------
     "agora que tem o mapa quero implementar sugestões de imóveis próximos (no
     mesmo bairro) e em outros bairros, aí listar o bairro e embaixo os imóveis
     disponíveis (nome, status, se é locação ou venda, e preço)".
     O mesmo bairro primeiro, depois os bairros a até 2 km (os de "Bairros ao
     redor"); em cada um, os disponíveis nossos, do mais perto ao mais longe.
     Parceria fica de fora: está fora de tudo. */
  function precoDaSugestao(s) {
    // um preço só: o valor puro (a finalidade já está escrita ao lado);
    // os dois: cada um com o nome, senão não dá pra saber qual é qual
    if (s.valor_aluguel && s.valor_venda) {
      return "Aluguel " + reais(s.valor_aluguel) + " · Venda " + reais(s.valor_venda);
    }
    if (s.valor_aluguel || s.valor_venda) return reais(s.valor_aluguel || s.valor_venda);
    return esc(s.valor_texto || "Consulte");
  }

  function carregarSugestoes(codigo) {
    fetch(API + "/api/imoveis/" + encodeURIComponent(codigo) + "/sugestoes")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var alvo = $("ux-sugestoes");
        if (!alvo || $("ux-ficha").dataset.codigo !== String(codigo)) return;
        if (!d.ponto) { alvo.textContent = "Este imóvel ainda não tem localização no mapa."; return; }
        // o bairro do imóvel aparece sempre; os outros, só se têm o que sugerir
        var grupos = d.bairros.filter(function (b) { return b.mesmo_bairro || b.imoveis.length; });
        alvo.className = "ux-sugestoes";
        alvo.innerHTML = grupos.map(function (b) {
          var onde = b.mesmo_bairro ? "mesmo bairro"
            : (b.km != null ? b.km.toLocaleString("pt-BR") + " km" : "perto");
          return '<div class="ux-sug">' +
            '<div class="ux-sug__bairro"><b>' + esc(b.bairro) + '</b><span class="ux-dica">' + onde +
              " · " + b.total + " disponíve" + (b.total === 1 ? "l" : "is") + "</span></div>" +
            (b.imoveis.length
              ? '<ul class="ux-sug__lista">' + b.imoveis.map(function (s) {
                  return '<li><button type="button" class="ux-sug__item" data-sugestao="' + esc(s.codigo) + '">' +
                    '<span class="ux-sug__nome">' + esc(s.nome) + "</span>" +
                    '<span class="etiqueta ' + (COR_STATUS[s.status] || "etiqueta--cinza-ux") + '">' + esc(s.status) + "</span>" +
                    '<span class="ux-sug__fin">' + esc(s.finalidade) + " · cód. " + esc(s.codigo) + "</span>" +
                    '<span class="ux-sug__preco">' + precoDaSugestao(s) + "</span>" +
                  "</button></li>";
                }).join("") + "</ul>"
              : '<div class="ux-dica">Nenhum outro disponível nosso neste bairro.</div>') +
            (b.total > b.imoveis.length
              ? '<div class="ux-dica">e mais ' + (b.total - b.imoveis.length) + " neste bairro</div>" : "") +
          "</div>";
        }).join("") || '<span class="ux-dica">Nada disponível por perto.</span>';
      })
      .catch(function () {
        var alvo = $("ux-sugestoes");
        if (alvo && $("ux-ficha").dataset.codigo === String(codigo)) alvo.textContent = "não consegui ler as sugestões";
      });
  }

  /* A sugestão abre a ficha dela. No mapa todos os disponíveis já estão na
     memória; na tabela só a página aberta -- aí busca o imóvel pelo código. */
  function abrirSugestao(codigo) {
    if ((window.IMOVEIS_NA_TELA || {})[codigo]) return abrirFicha(codigo);
    fetch(API + "/api/imoveis-lista?" + new URLSearchParams({ q: String(codigo), per: "50", page: "1" }).toString())
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var achado = (d.itens || []).filter(function (x) { return String(x.codigo) === String(codigo); })[0];
        if (!achado) return;
        window.IMOVEIS_NA_TELA = window.IMOVEIS_NA_TELA || {};
        window.IMOVEIS_NA_TELA[achado.codigo] = achado;
        abrirFicha(achado.codigo);
      })
      .catch(function () {});
  }

  /* ---- a gaveta do imóvel ------------------------------------------ */
  function abrirFicha(codigo) {
    var i = window.IMOVEIS_NA_TELA[codigo];
    if (!i) return;
    var f = $("ux-ficha");
    f.innerHTML =
      '<div class="ux-ficha__topo"><div>' +
        '<span class="etiqueta ' + (COR_STATUS[i.status] || "etiqueta--cinza-ux") + '">' + esc(i.status) + "</span> " +
        '<span class="etiqueta etiqueta--azul-suave">Cód. ' + esc(i.codigo) + "</span>" +
        "<h2>" + esc(i.condominio || i.tipo || ("Imóvel " + i.codigo)) + "</h2>" +
        '<div class="ux-dica">' + esc([i.tipo, i.endereco, i.bairro].filter(Boolean).join(" · ")) + "</div>" +
      '</div><button class="btn-neutro" type="button" id="ux-fechar" aria-label="Fechar">✕</button></div>' +

      '<div class="ux-bloco"><h3>Oferta</h3><div class="ux-dois">' +
        "<div><b>Finalidade</b>" + (i.valorVenda && i.valorAluguel ? "Venda e aluguel"
                                     : i.valorVenda ? "Venda" : i.valorAluguel ? "Aluguel" : "—") + "</div>" +
        "<div><b>Valor</b>" + (precos(i).length
          ? precos(i).map(function (x) { return x[0] + ": " + reais(x[1]); }).join("<br>")
          : esc(i.valor || "Consulte")) + "</div>" +
        "<div><b>Anúncio</b>" + (i.anunciado ? "No site" : "Fora do site") + "</div>" +
        "<div><b>Financiamento</b>" + esc(i.financia) + "</div>" +
        "<div><b>De quem é</b>" + (i.parceiro ? "Parceiro" : "Nosso (proprietário)") + "</div>" +
        "<div><b>Chega na Nay</b>" + (i.anunciado && !i.parceiro && !i.bloqueado && i.status === "Disponível" ? "Sim"
          : "Não" + (i.parceiro ? " (parceiro)" : i.status !== "Disponível" ? " (não está Disponível)"
                     : i.bloqueado ? " (bloqueado)" : " (fora do site)")) + "</div>" +
      "</div></div>" +

      '<div class="ux-bloco"><h3>Características</h3><div class="ux-dois">' +
        "<div><b>Tipo</b>" + esc(i.tipo || "—") + "</div>" +
        "<div><b>Área</b>" + (i.area ? Math.round(i.area) + " m²" : "—") + "</div>" +
        "<div><b>Quartos</b>" + (i.quartos != null ? i.quartos : "—") + "</div>" +
        "<div><b>Suítes</b>" + (i.suites != null ? i.suites : "—") + "</div>" +
        "<div><b>Banheiros</b>" + (i.banheiros != null ? i.banheiros : "—") + "</div>" +
        "<div><b>Vagas</b>" + (i.vagas != null ? i.vagas : "—") + "</div>" +
      "</div></div>" +

      '<div class="ux-bloco"><h3>Datas</h3>' + celulaDatas(i) +
        (i.precisaConfirmar ? '<div class="ux-dica">Marcado como “precisa confirmar com o proprietário”.</div>' : "") +
      "</div>" +

      '<div class="ux-bloco"><h3>Proprietário</h3>' +
        (i.proprietario
          ? "<p style=\"margin:0\">" + esc(i.proprietario) + '</p><button class="btn-mini" type="button" data-dono="' +
            esc(i.codigo) + '" style="margin-top:8px">Ver contato</button>'
          : '<p class="ux-dica" style="margin:0">Sem proprietário cadastrado.</p>') +
        '<p class="ux-dica">Uso interno. Contato de proprietário nunca vai para corretor.</p>' +
      "</div>" +

      '<div class="ux-bloco"><h3>Bairros ao redor</h3><div id="ux-ao-redor" class="ux-dica">carregando…</div></div>' +

      '<div class="ux-bloco"><h3>Sugestões por perto</h3><div id="ux-sugestoes" class="ux-dica">carregando…</div></div>' +

      '<div class="ux-bloco"><h3>Fotos (' + (i.fotos || 0) + ")</h3>" +
        '<div class="ux-fotos" id="ux-fotos">' +
        (i.fotos ? '<span class="ux-dica">carregando…</span>' : '<span class="ux-dica">Este imóvel não tem foto nossa.</span>') +
      "</div></div>" +

      /* a página nova do imóvel (02/10): endereço inteiro, porque esta tela também abre dentro do CRM */
      (i.anunciado && i.status === "Disponível"
        ? '<a class="btn-neutro btn-bloco" style="margin-top:12px;text-align:center" target="_blank" rel="noopener" ' +
          'href="https://imobeasy.online/imovel/' + encodeURIComponent(i.codigo) + '">Ver como o corretor vê (página do imóvel)</a>'
        : '<p class="ux-dica" style="margin-top:12px">Sem página pública: só imóvel disponível e anunciado no site tem.</p>') +

      (i.noCatalogo
        ? '<a class="btn-azul btn-bloco" style="margin-top:12px" href="imovel-editar.html?codigo=' + esc(i.codigo) + '">Abrir / editar imóvel</a>'
        : '<p class="ux-dica" style="margin-top:12px">Imóvel só do admin antigo: não abre no editor.</p>');

    quemAbriu = document.activeElement;
    // de quem é a gaveta agora: resposta que chega atrasada de outro imóvel
    // (clicar numa sugestão abre outra ficha) não escreve nesta
    f.dataset.codigo = String(i.codigo);
    f.hidden = false; $("ux-veu").hidden = false;
    f.scrollTop = 0;
    $("ux-fechar").focus({ preventScroll: true });
    $("ux-fechar").onclick = fecharFicha;

    fetch(API + "/api/imoveis/" + encodeURIComponent(i.codigo) + "/ao-redor")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var alvo = $("ux-ao-redor");
        if (!alvo) return;
        if (!d.ponto) { alvo.textContent = "Este imóvel ainda não tem localização no mapa."; return; }
        var dentro = d.bairros.filter(function (b) { return b.dentro; }).map(function (b) { return b.bairro; });
        var perto = d.bairros.filter(function (b) { return !b.dentro; });
        alvo.innerHTML = (dentro.length ? "Fica em <b>" + esc(dentro.join(", ")) + "</b>. " : "") +
          (perto.length ? "Perto: " + perto.map(function (b) { return esc(b.bairro) + " (" + b.km.toLocaleString("pt-BR") + " km)"; }).join(", ") + "."
                        : "Nenhum outro bairro a até 2 km.") +
          '<br><span class="ux-dica">' + esc(PRECISAO[d.ponto.precisao] || "") + "</span>";
      })
      .catch(function () { var alvo = $("ux-ao-redor"); if (alvo) alvo.textContent = "não consegui ler os bairros ao redor"; });

    carregarSugestoes(i.codigo);

    if (i.fotos) {
      fetch(API + "/api/imoveis/" + encodeURIComponent(i.codigo) + "/fotos")
        .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function (d) {
          var fotos = (d.fotos || []).slice(0, 9);
          $("ux-fotos").innerHTML = fotos.length
            ? fotos.map(function (u) {
                var url = typeof u === "string" ? u : (u.url || u.arquivo);
                return '<img loading="lazy" src="' + esc(url) + '" alt="">';
              }).join("")
            : (i.capa ? '<img loading="lazy" src="' + esc(i.capa) + '" alt="">' : '<span class="ux-dica">não consegui abrir as fotos</span>');
        })
        .catch(function () {
          $("ux-fotos").innerHTML = i.capa ? '<img loading="lazy" src="' + esc(i.capa) + '" alt="">'
            : '<span class="ux-dica">não consegui abrir as fotos</span>';
        });
    }
  }
  var quemAbriu = null;
  function fecharFicha() {
    if ($("ux-ficha").hidden) return;
    $("ux-ficha").hidden = true; $("ux-veu").hidden = true;
    if (quemAbriu && quemAbriu.focus && document.body.contains(quemAbriu)) quemAbriu.focus({ preventScroll: true });
  }

  /* ---- o popup do proprietário (rota COM SENHA) --------------------
     Dado pessoal não sai pela API aberta: vem de /admin/api/..., que confere
     a senha do /admin no Flask. O navegador já mandou essa senha nesta
     página, então o popup abre sem pedir de novo. */
  function popupDono(codigo) {
    var fundo = document.createElement("div");
    fundo.style.cssText = "position:fixed;inset:0;background:rgba(15,20,30,.55);display:flex;" +
      "align-items:center;justify-content:center;z-index:900;padding:16px";
    fundo.innerHTML = '<div style="background:var(--superficie,#fff);border-radius:14px;max-width:460px;' +
      'width:100%;padding:20px 22px;max-height:80vh;overflow:auto"><p style="margin:0">carregando…</p></div>';
    fundo.addEventListener("click", function (e) { if (e.target === fundo) fundo.remove(); });
    document.body.appendChild(fundo);
    var caixa = fundo.firstChild;

    function ligarFechar() {
      var b = caixa.querySelector("button");
      if (b) b.addEventListener("click", function () { fundo.remove(); });
    }

    // NO PROPRIO DOMINIO (imobeasy.online/admin/api/...): o navegador ja tem a
    // senha do /admin e manda sozinho. Pelo api.imobeasy.online a senha nao ia
    // (outro dominio) e o popup ficava em "carregando" para sempre.
    fetch("api/imoveis/" + encodeURIComponent(codigo) + "/proprietario", { credentials: "same-origin", cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        var p = d.proprietario;
        var h = '<h2 style="margin:0 0 8px;font-size:var(--fs-lg)">Proprietário do ' + esc(codigo) + "</h2>";
        if (!p) {
          h += '<p style="color:var(--texto-fraco)">' + esc(d.aviso || "sem proprietário cadastrado") + "</p>";
        } else {
          h += '<p style="margin:0 0 10px"><strong>' + esc(p.nome) + "</strong>" +
               (p.e_parceiro ? ' <span class="etiqueta etiqueta--laranja">parceiro</span>' : "") + "</p>";
          if (!p.contatos.length) {
            h += '<p style="color:var(--texto-fraco);font-size:var(--fs-xs)">' + esc(d.aviso || "") + "</p>";
          } else {
            h += p.contatos.map(function (c) {
              return '<p style="margin:0 0 8px">' + esc(c.telefone || "sem telefone") +
                '<br><span style="color:var(--texto-fraco);font-size:var(--fs-xs)">' +
                esc(c.email || "sem e-mail") + " · " + esc(c.fonte) + "</span></p>";
            }).join("");
          }
        }
        h += '<p style="margin:14px 0 0;font-size:var(--fs-xs);color:var(--texto-fraco)">' +
             esc([d.imovel.condominio, d.imovel.endereco].filter(Boolean).join(" — ")) + "</p>" +
             '<button type="button" class="btn-mini" style="margin-top:14px">Fechar</button>';
        caixa.innerHTML = h;
        ligarFechar();
      })
      .catch(function (e) {
        caixa.innerHTML = "<p>não consegui ler o proprietário (" + esc(e) + ")</p>" +
          '<button type="button" class="btn-mini">Fechar</button>';
        ligarFechar();
      });
  }

  /* ---- os cliques -------------------------------------------------- */
  document.addEventListener("click", function (e) {
    function achar(sel) { return e.target.closest ? e.target.closest(sel) : null; }

    var dono = achar("[data-dono]");
    if (dono) { e.stopPropagation(); popupDono(dono.dataset.dono); return; }

    var op = achar("[data-grupo-op]");
    if (op) {
      var g = GRUPOS[op.dataset.grupoOp], v = op.dataset.v;
      if (g.multi) {
        var lista = st[g.chave];
        st[g.chave] = lista.indexOf(v) >= 0 ? lista.filter(function (x) { return x !== v; }) : lista.concat([v]);
      } else {
        st[g.chave] = st[g.chave] === v ? "" : v;
      }
      return recomecar();
    }

    var qual = achar("[data-qual]");
    if (qual) { st.dataCampo = st.dataCampo === qual.dataset.qual ? "" : qual.dataset.qual; st.dataPer = ""; return recomecar(); }

    var per = achar("[data-per]");
    if (per) {
      if (per.dataset.per === "meses") {
        st.dataMeses = soDigitos($("f-meses").value);
        st.dataPer = st.dataMeses ? "meses" : "";
      } else {
        st.dataPer = st.dataPer === per.dataset.per ? "" : per.dataset.per;
      }
      return recomecar();
    }

    var at = achar("[data-atalho]");
    if (at) { ATALHOS[+at.dataset.atalho].aplicar(); return recomecar(); }

    var limpaOp = achar("[data-limpa-op]");
    if (limpaOp) {
      var gg = GRUPOS[limpaOp.dataset.limpaOp];
      if (gg.multi) st[gg.chave] = st[gg.chave].filter(function (x) { return x !== limpaOp.dataset.v; });
      else st[gg.chave] = "";
      return recomecar();
    }
    var limpaCampo = achar("[data-limpa-campo]");
    if (limpaCampo) { $(limpaCampo.dataset.limpaCampo).value = ""; return recomecar(); }
    var limpaMs = achar("[data-limpa-ms]");
    if (limpaMs) {
      var ms = MS_DA_LISTA[limpaMs.dataset.limpaMs][0];
      var tirar = limpaMs.dataset.v;
      ms.definir(ms.valores().filter(function (v) { return v !== tirar; }));
      return recomecar();
    }
    var limpa = achar("[data-limpa]");
    if (limpa) {
      var q = limpa.dataset.limpa;
      if (q === "grupo") {
        st.grupo = "";
        document.querySelectorAll("[data-grupo]").forEach(function (a) {
          a.setAttribute("aria-selected", a.dataset.grupo === "" ? "true" : "false");
        });
      } else if (q === "condo") condoDoLink = null;
      else if (q === "data") { st.dataCampo = ""; st.dataPer = ""; st.dataMeses = ""; }
      else form.elements[q].value = "";
      return recomecar();
    }

    // PAGINACAO: so o que esta dentro dela. Antes o seletor era "[data-pagina]",
    // e o <body> tem data-pagina="imoveis" -- TODO clique fora dos filtros
    // (o "Ver", a linha, o campo de bairro, abrir um grupo) virava "ir para a
    // pagina NaN": a tela subia ao topo, a lista dava erro e a gaveta nao abria.
    var pag = achar("#paginacao-imoveis [data-ir-pagina]");
    if (pag) {
      if (pag.disabled) return;
      st.page = Number(pag.dataset.irPagina) || 1;
      carregar().then(function () {
        // leva ao comeco da LISTA (nao ao topo da pagina), e so se ele sumiu de vista
        var topo = $("contagem-imoveis").getBoundingClientRect().top - alturaDoMenu() - 12;
        if (topo < 0) window.scrollBy({ top: topo, behavior: "smooth" });
      });
      return;
    }
    if (achar("[data-tentar-de-novo]")) return carregar();

    if (achar("#ux-veu")) return fecharFicha();
    var sugestao = achar("[data-sugestao]");
    if (sugestao) return abrirSugestao(sugestao.dataset.sugestao);
    var excluir = achar("[data-excluir]");
    if (excluir) return excluirImovel(excluir.dataset.excluir);
    var ver = achar("[data-ver]");
    if (ver) return abrirFicha(ver.dataset.ver);
    var linhaTab = achar("#corpo-imoveis tr[data-codigo]");
    // a lista suspensa da situação fica dentro da linha: clicar nela não abre a ficha
    if (linhaTab && !achar("a, button, select, option")) return abrirFicha(linhaTab.dataset.codigo);
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") fecharFicha();
    if (e.key === "Enter" && e.target.matches && e.target.matches("#corpo-imoveis tr[data-codigo]")) abrirFicha(e.target.dataset.codigo);
  });

  /* digitar: espera parar de digitar pra não disparar consulta por tecla */
  var espera = null;
  form.addEventListener("input", function (e) {
    if (e.target.id === "f-meses") { st.dataMeses = soDigitos(e.target.value); return; }
    if (["busca-imovel", "vmin", "vmax"].indexOf(e.target.id || e.target.name) < 0) return;
    clearTimeout(espera);
    espera = setTimeout(recomecar, 350);
  });
  form.addEventListener("change", function (e) {
    if (e.target.id === "f-ordenar") recomecar();
  });
  // a lista suspensa da situação, em cada linha da tabela
  corpo.addEventListener("change", function (e) {
    var sel = e.target && e.target.closest ? e.target.closest("select[data-situacao-de]") : null;
    if (sel) mudarSituacao(sel);
  });
  $("f-ordenar").addEventListener("change", recomecar);
  form.addEventListener("submit", function (e) { e.preventDefault(); recomecar(); });
  form.addEventListener("reset", function (e) {
    e.preventDefault();
    limparFiltros();
    recomecar();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && e.target.id === "f-meses") {
      e.preventDefault();
      st.dataMeses = soDigitos(e.target.value);
      st.dataPer = st.dataMeses ? "meses" : "";
      recomecar();
    }
  });
  if ($("limpar-data")) $("limpar-data").addEventListener("click", function () {
    st.dataCampo = ""; st.dataPer = ""; st.dataMeses = ""; recomecar();
  });

  document.querySelectorAll("[data-grupo]").forEach(function (aba) {
    aba.addEventListener("click", function () { st.grupo = aba.dataset.grupo; trocarVista("tabela"); recomecar(); });
  });
  document.querySelectorAll('[data-vista="mapa"]').forEach(function (aba) {
    aba.addEventListener("click", function () { st.grupo = ""; trocarVista("mapa"); carregarMapa(); });
  });

  $("btn-exportar").addEventListener("click", function () {
    window.location.href = API + "/api/imoveis-lista?" + parametros({ formato: "csv", per: 6000 }).toString();
  });
  $("btn-copiar").addEventListener("click", function () {
    var txt = (ultimo.itens || []).map(function (i) {
      return [i.codigo, i.status, i.valor, i.condominio, i.endereco, i.bairro].filter(Boolean).join(" | ");
    }).join("\n");
    var s = $("copiar-status");
    if (!txt) { s.textContent = "Nada na tela para copiar."; return; }
    (navigator.clipboard ? navigator.clipboard.writeText(txt) : Promise.reject())
      .then(function () { s.textContent = ultimo.itens.length + " linha(s) copiadas."; })
      .catch(function () { s.textContent = "O navegador não deixou copiar."; });
  });

  /* ==================================================================
     O MAPA (Tel, 28/09): "um mapa focado na cidade de Manaus... todos os
     nossos imóveis, todos divididinhos por bairro... cada imóvel vai ser um
     card point no mapa clicável".
     E depois, no mesmo dia: "quero um overlay cinza ou outra opção escura...
     pontos tipo pins... um ícone para quando tem 1 e um ícone para quando tem
     vários e ao clicar abre uma lista de imóveis em um popup... filtros no
     mapa, inicialmente só os disponíveis... por bairro, por tipo de imóvel"
     e "pode sumir a barra lateral de imóveis quando clico no mapa e o mapa
     ocupar a tela toda".

     Leaflet + OpenStreetMap (gratuitos), carregados só quando a aba abre. Os
     imóveis nossos com ponto (`imovel_geo`, migração 149) vêm UMA vez e os
     filtros de cima do mapa trabalham no navegador, na hora. O fundo é o
     mapa do OpenStreetMap com filtro de cor (escuro ou cinza).
     ================================================================== */
  var mapa = null, camadaPins = null, camadaBairros = null, camadaRotulos = null;
  var dadosMapa = null;
  var CDN = "https://cdnjs.cloudflare.com/ajax/libs/";
  var PRECISAO = {
    condominio: "Localização: o condomínio",
    rua: "Localização aproximada: a rua, no bairro",
    bairro: "Localização aproximada: o centro do bairro"
  };
  // o que está escolhido nos filtros de cima do mapa (começa só com os disponíveis)
  var mf = { sit: ["Disponível"], bairros: [], condos: [], tipos: [], fin: [], qt: [], vmin: "", vmax: "", busca: "" };
  var msSit = null, msBairros = null, msCondos = null, msTipos = null;
  var estiloMapa = "escuro";
  try { estiloMapa = localStorage.getItem("imoveis.mapa.estilo") || "escuro"; } catch (e) { /* sem armazenamento */ }

  function carregarArquivo(tag, url) {
    return new Promise(function (ok, erro) {
      var e = document.createElement(tag);
      if (tag === "link") { e.rel = "stylesheet"; e.href = url; } else { e.src = url; }
      e.onload = ok; e.onerror = erro;
      document.head.appendChild(e);
    });
  }
  var leafletPronto = null;
  function prepararLeaflet() {
    if (!leafletPronto) {
      leafletPronto = Promise.all([
        carregarArquivo("link", CDN + "leaflet/1.9.4/leaflet.min.css"),
        carregarArquivo("script", CDN + "leaflet/1.9.4/leaflet.min.js")
      ]);
    }
    return leafletPronto;
  }

  /* ---- a vista: tabela ou mapa (a lateral some no mapa) ---- */
  function trocarVista(v) {
    st.vista = v;
    var noMapa = v === "mapa";
    // A ABA FICA NO ENDERECO (Tel, 28/09: "quando estou na aba mapa e atualizo
    // a tela ele volta para todos"): imoveis.html#mapa volta direto no mapa.
    try { history.replaceState(null, "", location.pathname + location.search + (noMapa ? "#mapa" : "")); } catch (e) { /* sem historico */ }
    document.querySelector(".ux-grid").classList.toggle("ux-grid--mapa", noMapa);
    $("ux-mapa").hidden = !noMapa;
    $("envolucro-tabela").hidden = noMapa;
    paginacao.hidden = noMapa;
    esticarMapa();
    if (noMapa) {
      prepararLeaflet().then(function () { iniciarMapa(); esticarMapa(); })
        .catch(function () { $("mapa-resumo").textContent = "Não consegui carregar o mapa (sem internet para a biblioteca?)."; });
    }
  }

  /* o mapa fica mais largo que a coluna do conteúdo, centralizado na tela, com
     uma margem dos lados ("pode diminuir um pouco o tamanho do mapa horizontal") */
  function esticarMapa() {
    var m = $("ux-mapa");
    m.style.width = ""; m.style.marginLeft = "";
    if (st.vista !== "mapa") return;
    var tela = document.documentElement.clientWidth;
    var larg = Math.min(tela - 112, 1560);
    m.style.width = larg + "px";
    m.style.marginLeft = ((tela - larg) / 2 - m.getBoundingClientRect().left) + "px";
    if (mapa) mapa.invalidateSize();
  }
  window.addEventListener("resize", esticarMapa);

  /* O PIN E ROXO, a cor da casa, com o miolo roxo claro e sem contorno branco
     (Tel, 28/09: "tira o círculo verde ao redor do círculo branco... troca o
     branco de dentro do ícone por roxo claro, e tira o branco de fora"). A
     situação fica nos filtros e no balão de cada imóvel. */
  var ROXO_PIN = "#6d28d9";
  var ROXO_CLARO = "#ddd6fe";

  /* ---- os pins: um imóvel, ou vários no mesmo ponto ----
     COM ASPECTO 3D (Tel, 28/09: "tenta dar um aspecto 3d ao ícone do mapa"):
     o corpo num degradê de roxo (a luz vem de cima, à esquerda), um brilho no
     alto, o miolo roxo claro em cúpula e uma sombrinha no chão. Os degradês
     ficam definidos UMA vez na página e todos os pins usam os mesmos. */
  (function () {
    if (document.getElementById("ux-pin-defs")) return;
    var d = document.createElement("div");
    d.innerHTML = '<svg id="ux-pin-defs" width="0" height="0" style="position:absolute" aria-hidden="true"><defs>' +
      '<linearGradient id="uxPinCorpo" x1="0.15" y1="0" x2="0.85" y2="1">' +
        '<stop offset="0" stop-color="#a78bfa"/><stop offset="0.45" stop-color="#7c3aed"/><stop offset="1" stop-color="#4c1d95"/></linearGradient>' +
      '<radialGradient id="uxPinMiolo" cx="0.38" cy="0.32" r="0.8">' +
        '<stop offset="0" stop-color="#ffffff"/><stop offset="0.5" stop-color="' + ROXO_CLARO + '"/><stop offset="1" stop-color="#b9a4f6"/></radialGradient>' +
      '<radialGradient id="uxPinBrilho" cx="0.5" cy="0.5" r="0.5">' +
        '<stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>' +
      "</defs></svg>";
    document.body.appendChild(d.firstChild);
  })();

  function pinDeUm() {
    var corpo = "M13 35C13 35 0 21.4 0 13a13 13 0 0 1 26 0c0 8.4-13 22-13 22z";
    return '<svg class="ux-pin ux-pin--um" width="26" height="38" viewBox="0 0 26 38" aria-hidden="true">' +
      '<ellipse cx="13" cy="35.6" rx="5" ry="1.7" fill="#000" opacity="0.38"/>' +
      '<path d="' + corpo + '" fill="url(#uxPinCorpo)"/>' +
      '<path d="' + corpo + '" fill="none" stroke="#2e1065" stroke-opacity="0.35" stroke-width="0.9"/>' +
      '<ellipse cx="8.4" cy="6.6" rx="5.6" ry="3.4" fill="url(#uxPinBrilho)" transform="rotate(-32 8.4 6.6)"/>' +
      '<circle cx="13" cy="13" r="5.6" fill="url(#uxPinMiolo)" stroke="#4c1d95" stroke-opacity="0.4" stroke-width="0.8"/></svg>';
  }
  function pinDeVarios(n) {
    var corpo = "M17 45C17 45 0 27.8 0 17a17 17 0 0 1 34 0c0 10.8-17 28-17 28z";
    return '<svg class="ux-pin ux-pin--varios" width="34" height="48" viewBox="0 0 34 48" aria-hidden="true">' +
      '<ellipse cx="17" cy="45.7" rx="6.5" ry="2" fill="#000" opacity="0.38"/>' +
      '<path d="' + corpo + '" fill="url(#uxPinCorpo)"/>' +
      '<path d="' + corpo + '" fill="none" stroke="#2e1065" stroke-opacity="0.35" stroke-width="0.9"/>' +
      '<ellipse cx="10.5" cy="8.2" rx="7.2" ry="4.2" fill="url(#uxPinBrilho)" transform="rotate(-32 10.5 8.2)"/>' +
      '<circle cx="17" cy="17" r="11" fill="url(#uxPinMiolo)" stroke="#4c1d95" stroke-opacity="0.4" stroke-width="0.8"/>' +
      '<text x="17" y="21.3" text-anchor="middle" font-size="' + (n > 99 ? 9.5 : 12) + '" font-weight="800" ' +
      'font-family="Rubik,Arial,sans-serif" fill="#4c1d95">' + n + "</text></svg>";
  }

  /* O PREÇO DENTRO DO PINO (Pedro, 02/10/2026: "implementa o preço no nosso mapa atual em todo lugar mas
     dentro do pin do mapa, porém sem crescer junto com a tela e deixa pequeno para facilitar a visualização").
     O pino continua roxo, agora com o valor escrito: pequeno e de tamanho FIXO (não segue o zoom). Vários
     imóveis no mesmo ponto mostram o menor preço e "+N"; o balão lista todos. Com o filtro em só aluguel ou
     só venda, o preço é o desse negócio. O mesmo pino está na tela pública /imoveis (imoveis-enviar.js). */
  function precoCurto(n) {
    return n >= 1e6 ? (n / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) + " mi"
      : n >= 1e4 ? Math.round(n / 1e3).toLocaleString("pt-BR") + " mil"
      : (n / 1e3).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mil";
  }
  function valorNoMapa(i) {
    var so = mf.fin.length === 1 ? mf.fin[0] : null;
    return so === "aluguel" ? i.valorAluguel : so === "venda" ? i.valorVenda : (i.valorAluguel || i.valorVenda);
  }
  function pinDePreco(g) {
    var vs = g.map(valorNoMapa).filter(function (v) { return v > 0; }).sort(function (a, b) { return a - b; });
    return '<span class="ux-preco-pin">' + (vs.length ? precoCurto(vs[0]) : "s/ valor") +
      (g.length > 1 ? "<i>+" + (g.length - 1) + "</i>" : "") + "</span>";
  }

  /* O TAMANHO DO PIN SEGUE O ZOOM DO MAPA: afastado, a cidade inteira na tela,
     o pin é menor -- senão, do mesmo tamanho com o mapa encolhido, ele cobre a
     cidade ("não precisa os ícones crescerem quando eu diminuo o zoom"). Perto,
     o tamanho normal. A ponta do pin continua no lugar (escala a partir dela). */
  function escalaDosPins() {
    if (!mapa) return;
    var z = mapa.getZoom();
    var f = z >= 16 ? 1 : z >= 15 ? 0.9 : z >= 14 ? 0.8 : z >= 13 ? 0.68 : z >= 12 ? 0.56 : 0.46;
    // e tudo 25% menor (Tel, 28/09: "diminui 25% o tamanho dos ícones de imóveis")
    mapa.getContainer().style.setProperty("--pin-escala", (f * 0.75).toFixed(3));
  }

  function iniciarMapa() {
    if (mapa || !window.L) return;
    mapa = L.map("mapa-area", { zoomControl: true, minZoom: 10 }).setView([-3.075, -60.02], 12);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, subdomains: "abc",
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(mapa);
    camadaBairros = L.layerGroup().addTo(mapa);
    // os nomes dos bairros ficam ABAIXO dos pins (a camada padrao de rotulo fica por cima)
    mapa.createPane("rotulosBairro");
    mapa.getPane("rotulosBairro").style.zIndex = 450;
    mapa.getPane("rotulosBairro").style.pointerEvents = "none";
    camadaRotulos = L.layerGroup();
    camadaPins = L.layerGroup().addTo(mapa);
    mapa.on("zoomend", mostrarRotulos);
    mapa.on("zoomend", escalaDosPins);
    escalaDosPins();
    // A RODINHA NUNCA ROLA A PAGINA dentro do mapa (Tel, 28/09: "às vezes
    // quando mexo a rodinha dentro do mapa ele rola a tela para cima"). O
    // Leaflet segura a rodinha no mapa, mas em cima de um balão ele solta -- e
    // a página rolava. Só a lista de um balão rola (e sem vazar para a página).
    mapa.getContainer().addEventListener("wheel", function (e) {
      var lista = e.target.closest && e.target.closest(".ux-lugar__lista");
      if (lista && lista.scrollHeight > lista.clientHeight) return;
      e.preventDefault();
    }, { passive: false, capture: true });   // captura: o balão do Leaflet corta o evento antes de subir
    // os botões dos balões: ligados direto (o Leaflet pode segurar o clique no balão)
    mapa.on("popupopen", function (e) {
      var el = e.popup.getElement();
      if (!el) return;
      [].forEach.call(el.querySelectorAll("[data-ver]"), function (b) {
        b.onclick = function (ev) { ev.stopPropagation(); abrirFicha(b.dataset.ver); };
      });
    });
    $("mapa-contornos").addEventListener("change", function () {
      if (this.checked) { camadaBairros.addTo(mapa); mostrarRotulos(); }
      else { mapa.removeLayer(camadaBairros); mapa.removeLayer(camadaRotulos); }
    });
    aplicarEstilo(estiloMapa);
    carregarBairros();
  }

  /* ---- o fundo: escuro ou cinza ---- */
  function aplicarEstilo(v) {
    estiloMapa = v === "cinza" ? "cinza" : "escuro";
    try { localStorage.setItem("imoveis.mapa.estilo", estiloMapa); } catch (e) { /* sem armazenamento */ }
    var area = $("mapa-area");
    area.classList.toggle("mapa--escuro", estiloMapa === "escuro");
    area.classList.toggle("mapa--cinza", estiloMapa === "cinza");
    document.querySelectorAll("[data-estilo-mapa]").forEach(function (b) {
      b.setAttribute("aria-pressed", b.dataset.estiloMapa === estiloMapa ? "true" : "false");
    });
    if (camadaBairros) {
      var cor = estiloMapa === "escuro" ? "#c4b5fd" : "#6d28d9";
      camadaBairros.eachLayer(function (l) { if (l.setStyle) l.setStyle({ color: cor, fillColor: cor }); });
    }
  }

  function mostrarRotulos() {
    if (!mapa || !$("mapa-contornos").checked) return;
    if (mapa.getZoom() >= 13) camadaRotulos.addTo(mapa); else mapa.removeLayer(camadaRotulos);
  }

  function carregarBairros() {
    fetch(API + "/api/mapa/bairros")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (bs) {
        var cor = estiloMapa === "escuro" ? "#c4b5fd" : "#6d28d9";
        bs.forEach(function (b) {
          var divisa = b.vizinhos.filter(function (v) { return v.divisa; }).map(function (v) { return v.bairro; });
          var perto = b.vizinhos.filter(function (v) { return !v.divisa; }).map(function (v) { return v.bairro + " (" + v.km.toLocaleString("pt-BR") + " km)"; });
          var html = "<b>" + esc(b.bairro) + "</b><div class=\"ux-card__sub\">" + b.imoveis + " imóve" + (b.imoveis === 1 ? "l" : "is") +
            " nosso" + (b.imoveis === 1 ? "" : "s") + " no mapa" + (b.area_km2 ? " · " + b.area_km2.toLocaleString("pt-BR") + " km²" : "") + "</div>" +
            (divisa.length ? "<div class=\"ux-card__sub\" style=\"margin-top:6px\"><b>Faz divisa com</b></div><ul class=\"ux-vizinhos\"><li>" +
              divisa.map(esc).join("</li><li>") + "</li></ul>" : "") +
            (perto.length ? "<div class=\"ux-card__sub\" style=\"margin-top:6px\"><b>Perto</b>: " + perto.map(esc).join(", ") + "</div>" : "");
          if (b.poligono) {
            var contorno = L.geoJSON(b.poligono, { style: { color: cor, weight: 1.2, opacity: .6, fillColor: cor, fillOpacity: .04 } })
              .bindPopup(html)
              .bindTooltip(esc(b.bairro), { sticky: true, direction: "top", offset: [0, -8], className: "ux-dica-bairro" })
              .addTo(camadaBairros);
            // O BAIRRO SOB O MOUSE fica marcado de roxo, 30% (Tel, 28/09: "um leve
            // overlay roxo quando passo o mouse pelo bairro... tipo 30% de opacidade")
            contorno.on("mouseover", function (e) {
              e.layer.setStyle({ fillColor: "#7c3aed", fillOpacity: .3, weight: 2, opacity: .95 });
            });
            contorno.on("mouseout", function (e) {
              var c = estiloMapa === "escuro" ? "#c4b5fd" : "#6d28d9";
              e.layer.setStyle({ color: c, fillColor: c, fillOpacity: .04, weight: 1.2, opacity: .6 });
            });
          }
          L.tooltip({ permanent: true, direction: "center", className: "ux-rotulo-bairro", interactive: false, pane: "rotulosBairro" })
            .setLatLng([b.lat, b.lon]).setContent(esc(b.bairro)).addTo(camadaRotulos);
        });
        mostrarRotulos();
      })
      .catch(function () {});
  }

  /* ---- os balões ---- */
  function cardDoImovel(i) {
    var pv = precos(i);
    return '<div class="ux-card">' +
      (i.capa ? '<img src="' + esc(i.capa) + '" alt="" loading="lazy">' : "") +
      '<div><span class="ux-card__cod">#' + esc(i.codigo) + '</span> <span class="etiqueta ' +
        (COR_STATUS[i.status] || "etiqueta--cinza-ux") + '">' + esc(i.status) + "</span></div>" +
      '<div class="ux-card__tit">' + esc(i.condominio || i.tipo || "Imóvel") + "</div>" +
      '<div class="ux-card__sub">' + esc([i.tipo, i.quartos ? i.quartos + " quartos" : "", i.area ? Math.round(i.area) + " m²" : ""]
                                          .filter(Boolean).join(" · ")) + "</div>" +
      '<div class="ux-card__val">' + (pv.length ? pv.map(function (x) { return x[0] + " " + reais(x[1]); }).join("<br>") : esc(i.valor || "")) + "</div>" +
      '<div class="ux-card__sub">' + esc(bairroDe(i)) + " · " + esc(PRECISAO[i.precisao] || "") + "</div>" +
      '<div class="ux-card__acoes"><button type="button" class="btn-mini" data-ver="' + esc(i.codigo) + '">Ver ficha</button>' +
        (i.noCatalogo ? '<a class="btn-mini" href="imovel-editar.html?codigo=' + esc(i.codigo) + '">Editar</a>' : "") +
      "</div></div>";
  }

  function listaDoLugar(g) {
    var condos = g.map(function (i) { return i.condominio || ""; });
    var mesmo = condos.every(function (c) { return c && c === condos[0]; });
    var ordem = g.slice().sort(function (a, b) {
      return (a.status === "Disponível" ? 0 : 1) - (b.status === "Disponível" ? 0 : 1) ||
             ((a.valorAluguel || a.valorVenda || 0) - (b.valorAluguel || b.valorVenda || 0));
    });
    return '<div class="ux-lugar">' +
      '<div class="ux-lugar__tit">' + esc(mesmo ? condos[0] : "Vários imóveis neste ponto") + "</div>" +
      '<div class="ux-card__sub">' + g.length + " imóveis · " + esc(bairroDe(g[0])) + " · " + esc(PRECISAO[g[0].precisao] || "") + "</div>" +
      '<div class="ux-lugar__lista">' + ordem.map(function (i) {
        var pv = precos(i);
        return '<div class="ux-lugar__item">' +
          (i.capa ? '<img src="' + esc(i.capa) + '" alt="" loading="lazy">' : '<span class="ux-lugar__semfoto"></span>') +
          '<div class="ux-lugar__txt"><div><b>#' + esc(i.codigo) + '</b> <span class="etiqueta ' +
            (COR_STATUS[i.status] || "etiqueta--cinza-ux") + '">' + esc(i.status) + "</span></div>" +
            (mesmo ? "" : '<div class="ux-lugar__nome">' + esc(i.condominio || i.tipo || "") + "</div>") +
            '<div class="ux-card__sub">' + esc([pv.length ? pv.map(function (x) { return x[0] + " " + reais(x[1]); }).join(" · ") : i.valor,
                                                  i.quartos ? i.quartos + " quartos" : ""].filter(Boolean).join(" · ")) + "</div></div>" +
          '<button type="button" class="btn-mini" data-ver="' + esc(i.codigo) + '">Ver</button></div>';
      }).join("") + "</div></div>";
  }

  /* ---- os dados e os filtros de cima do mapa ---- */
  function bairroDe(i) { return i.bairroMapa || i.bairro || "(sem bairro)"; }
  function tipoDe(i) { return (i.tipo || "").trim() || "(sem tipo)"; }
  function condoDe(i) { return (i.condominio || "").trim() || "(sem condomínio)"; }

  function carregarMapa() {
    $("mapa-resumo").textContent = "carregando os imóveis…";
    var p = new URLSearchParams({ mapa: "1", per: "6000", page: "1", parceiro: "nao" });
    return fetch(API + "/api/imoveis-lista?" + p.toString())
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        dadosMapa = d.itens || [];
        window.IMOVEIS_NA_TELA = {};
        dadosMapa.forEach(function (i) { window.IMOVEIS_NA_TELA[i.codigo] = i; });
        return prepararLeaflet();
      })
      .then(function () {
        iniciarMapa(); esticarMapa();
        // o mapa inteiro na tela: rola ate os filtros de cima dele
        var topo = document.querySelector(".mapa-filtros").getBoundingClientRect().top + window.pageYOffset - 10;
        window.scrollTo({ top: Math.max(0, topo), behavior: "smooth" });
        filtrarMapa(true);
      })
      .catch(function () { $("mapa-resumo").textContent = "Não consegui carregar os imóveis do mapa."; });
  }

  function passa(i, sem) {
    if (sem !== "sit" && mf.sit.length && mf.sit.indexOf(i.status) < 0) return false;
    if (sem !== "bairro" && mf.bairros.length && mf.bairros.indexOf(bairroDe(i)) < 0) return false;
    if (sem !== "tipo" && mf.tipos.length && mf.tipos.indexOf(tipoDe(i)) < 0) return false;
    if (sem !== "condo" && mf.condos.length && mf.condos.indexOf(condoDe(i)) < 0) return false;
    if (mf.fin.length && !mf.fin.some(function (f) { return f === "aluguel" ? i.valorAluguel : i.valorVenda; })) return false;
    if (mf.qt.length && !mf.qt.some(function (q) { return q === "4" ? (i.quartos || 0) >= 4 : (i.quartos || 0) === Number(q); })) return false;
    var vmin = Number(soDigitos(String(mf.vmin).split(",")[0])) || 0;
    var vmax = Number(soDigitos(String(mf.vmax).split(",")[0])) || 0;
    if (vmin || vmax) {
      var cols = mf.fin.length === 1 ? [mf.fin[0] === "aluguel" ? i.valorAluguel : i.valorVenda] : [i.valorAluguel, i.valorVenda];
      if (!cols.some(function (v) { return v && (!vmin || v >= vmin) && (!vmax || v <= vmax); })) return false;
    }
    if (mf.busca) {
      var b = mf.busca.trim().toLowerCase();
      var alvo = (i.codigo + " " + (i.condominio || "") + " " + (i.endereco || "")).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
      if (alvo.indexOf(b.normalize("NFD").replace(/[̀-ͯ]/g, "")) < 0) return false;
    }
    return true;
  }

  function contar(sem, chave) {
    var c = {};
    dadosMapa.forEach(function (i) { if (passa(i, sem)) { var k = chave(i); c[k] = (c[k] || 0) + 1; } });
    return Object.keys(c).sort(function (a, b) { return c[b] - c[a] || a.localeCompare(b); })
      .map(function (k) { return { valor: k, n: c[k] }; });
  }

  function filtrarMapa(enquadrar) {
    try { sessionStorage.setItem("imoveis.mapa.filtros", JSON.stringify(mf)); } catch (e) { /* sem armazenamento */ }
    if (!dadosMapa || !mapa) return;
    // a contagem de cada lista ignora o próprio filtro -- é mapa do acervo
    msSit.opcoes(contar("sit", function (i) { return i.status; }));
    msBairros.opcoes(contar("bairro", bairroDe));
    msTipos.opcoes(contar("tipo", tipoDe));
    msCondos.opcoes(contar("condo", condoDe));

    var ok = dadosMapa.filter(function (i) { return passa(i); });
    var comPonto = ok.filter(function (i) { return i.lat != null && i.lon != null; });
    var lugares = {};
    comPonto.forEach(function (i) {
      var k = i.lat.toFixed(5) + "," + i.lon.toFixed(5);
      (lugares[k] = lugares[k] || []).push(i);
    });
    camadaPins.clearLayers();
    var nLugares = 0;
    Object.keys(lugares).forEach(function (k) {
      var g = lugares[k];
      nLugares++;
      var um = g.length === 1;
      var m = L.marker([g[0].lat, g[0].lon], {
        icon: L.divIcon({ className: "ux-pin-icone", html: pinDePreco(g),
                          iconSize: [0, 0], iconAnchor: [0, 0], popupAnchor: [0, -24] }),
        title: um ? "#" + g[0].codigo + " · " + (g[0].condominio || g[0].tipo || "") : g.length + " imóveis neste ponto",
        riseOnHover: true
      });
      m.bindPopup(function () { return um ? cardDoImovel(g[0]) : listaDoLugar(g); }, { maxWidth: um ? 260 : 340 });
      camadaPins.addLayer(m);
    });

    var sem = ok.length - comPonto.length;
    $("mapa-resumo").innerHTML = "<b>" + comPonto.length.toLocaleString("pt-BR") + "</b> imóve" + (comPonto.length === 1 ? "l" : "is") +
      " no mapa, em " + nLugares.toLocaleString("pt-BR") + " ponto" + (nLugares === 1 ? "" : "s") +
      (sem ? " · " + sem.toLocaleString("pt-BR") + " ainda sem localização" : "");
    var porSit = {};
    comPonto.forEach(function (i) { porSit[i.status] = (porSit[i.status] || 0) + 1; });
    $("mapa-legenda").innerHTML =
      '<span class="ux-leg-pin"><span class="ux-preco-pin ux-preco-pin--leg">480 mil</span>o preço do imóvel</span>' +
      '<span class="ux-leg-pin"><span class="ux-preco-pin ux-preco-pin--leg">350 mil<i>+2</i></span>' +
        "vários no mesmo ponto: o menor preço (clique para a lista)</span>" +
      "<span>" + Object.keys(porSit).sort(function (a, b) { return porSit[b] - porSit[a]; }).map(function (s) {
        return esc(s) + " " + porSit[s];
      }).join(" · ") + "</span>";

    if (enquadrar && comPonto.length) {
      // o zoom e CALCULADO antes e aplicado sem animacao: com animacao o
      // getZoom() ainda devolve o antigo, e a trava "nunca mais longe que a
      // cidade" nao pegava -- o mapa abria com Manaus pequena no meio.
      mapa.invalidateSize();
      var caixaPins = L.latLngBounds(comPonto.map(function (i) { return [i.lat, i.lon]; })).pad(0.15);
      var z = Math.max(12, Math.min(16, mapa.getBoundsZoom(caixaPins)));
      mapa.setView(caixaPins.getCenter(), z, { animate: false });
    }
  }

  /* os controles de cima do mapa */
  (function () {
    msSit = window.criarMultiSelecao($("mf-situacao"), { dica: "situação",
      aoMudar: function (v) { mf.sit = v; filtrarMapa(true); } });
    msBairros = window.criarMultiSelecao($("mf-bairros"), { dica: "bairros",
      aoMudar: function (v) { mf.bairros = v; filtrarMapa(true); } });
    msTipos = window.criarMultiSelecao($("mf-tipos"), { dica: "tipos",
      aoMudar: function (v) { mf.tipos = v; filtrarMapa(true); } });
    msCondos = window.criarMultiSelecao($("mf-condominios"), { dica: "condomínios",
      aoMudar: function (v) { mf.condos = v; filtrarMapa(true); } });
    // os filtros de antes do F5, se houver
    try {
      var salvo = JSON.parse(sessionStorage.getItem("imoveis.mapa.filtros") || "null");
      if (salvo && Array.isArray(salvo.sit)) {
        ["sit", "bairros", "condos", "tipos", "fin", "qt"].forEach(function (k) { if (Array.isArray(salvo[k])) mf[k] = salvo[k]; });
        ["vmin", "vmax", "busca"].forEach(function (k) { mf[k] = String(salvo[k] || ""); $("mf-" + k).value = mf[k]; });
      }
    } catch (e) { /* sem armazenamento: comeca so com os disponiveis */ }
    msSit.definir(mf.sit); msBairros.definir(mf.bairros); msCondos.definir(mf.condos); msTipos.definir(mf.tipos);
    document.querySelectorAll("[data-mf-fin]").forEach(function (b) { b.setAttribute("aria-pressed", mf.fin.indexOf(b.dataset.mfFin) >= 0 ? "true" : "false"); });
    document.querySelectorAll("[data-mf-qt]").forEach(function (b) { b.setAttribute("aria-pressed", mf.qt.indexOf(b.dataset.mfQt) >= 0 ? "true" : "false"); });
    document.querySelectorAll("[data-mf-fin], [data-mf-qt]").forEach(function (b) {
      b.addEventListener("click", function () {
        var liga = b.getAttribute("aria-pressed") !== "true";
        b.setAttribute("aria-pressed", liga ? "true" : "false");
        var chave = b.dataset.mfFin ? "fin" : "qt", v = b.dataset.mfFin || b.dataset.mfQt;
        mf[chave] = liga ? mf[chave].concat([v]) : mf[chave].filter(function (x) { return x !== v; });
        filtrarMapa(true);
      });
    });
    var esperaMapa = null;
    ["mf-vmin", "mf-vmax", "mf-busca"].forEach(function (id) {
      $(id).addEventListener("input", function () {
        mf[id.slice(3)] = $(id).value;
        clearTimeout(esperaMapa);
        esperaMapa = setTimeout(function () { filtrarMapa(true); }, 300);
      });
    });
    $("mf-limpar").addEventListener("click", function () {
      mf = { sit: ["Disponível"], bairros: [], condos: [], tipos: [], fin: [], qt: [], vmin: "", vmax: "", busca: "" };
      msSit.definir(mf.sit); msBairros.limpar(); msCondos.limpar(); msTipos.limpar();
      ["mf-vmin", "mf-vmax", "mf-busca"].forEach(function (id) { $(id).value = ""; });
      document.querySelectorAll("[data-mf-fin], [data-mf-qt]").forEach(function (b) { b.setAttribute("aria-pressed", "false"); });
      filtrarMapa(true);
    });
    $("mf-atualizar").addEventListener("click", carregarMapa);
    document.querySelectorAll("[data-estilo-mapa]").forEach(function (b) {
      b.addEventListener("click", function () { aplicarEstilo(b.dataset.estiloMapa); });
    });
  })();

  /* ---- o que vem de fora (link de outra tela) ----------------------- */
  var qs = new URLSearchParams(location.search);
  if (qs.get("condo")) {
    condoDoLink = { id: Number(qs.get("condo")), nome: qs.get("condo_nome") || "Condomínio " + qs.get("condo") };
  }

  /* as opções dos três campos de várias escolhas, com a conta de cada uma */
  fetch(API + "/api/imoveis/opcoes")
    .then(function (r) { return r.ok ? r.json() : { bairros: [], tipos: [], condominios: [] }; })
    .then(function (d) {
      function op(lista) { return (lista || []).map(function (x) { return { valor: x.valor, n: x.n }; }); }
      msBairrosL.opcoes(op(d.bairros));
      msTiposL.opcoes(op(d.tipos));
      msCondosL.opcoes(op(d.condominios));
      // o bairro vai no rótulo: digitar "parque 10" também acha os conjuntos de lá
      msConjuntosL.opcoes((d.conjuntos || []).map(function (x) {
        return { valor: x.valor, rotulo: x.valor + " · " + x.bairro + (x.zona ? " · zona " + x.zona : ""), n: x.n };
      }));
      // a zona mostra os bairros dela: digitar "coroado" também acha a zona leste
      msZonasL.opcoes((d.zonas || []).map(function (x) {
        return { valor: x.valor, rotulo: "Zona " + x.valor + " · " + (x.bairros || []).join(", "), n: x.n };
      }));
      msAvenidasL.opcoes((d.avenidas || []).map(function (x) {
        return { valor: x.valor, rotulo: x.valor + " · " + (x.bairros || []).join(", "), n: x.n };
      }));
    })
    .catch(function () {});
  if (qs.get("status")) st.status = [qs.get("status")];
  if (qs.get("sem_foto") === "1") { st.status = ["Disponível"]; st.foto = "nao"; st.parceiro = "nao"; }

  /* ---- a lista de bairros e a conta dos atalhos --------------------- */
  fetch(API + "/api/bairros?todos=1")
    .then(function (r) { return r.ok ? r.json() : []; })
    .then(function (bs) {
      $("lista-bairros").innerHTML = bs.map(function (b) {
        return '<option value="' + esc(b.bairro) + '">' + esc(b.bairro) + " (" + b.imoveis + ")</option>";
      }).join("");
    })
    .catch(function () {});

  var CONTAS = [
    "data_campo=vencimento&data_per=90",
    "status=" + encodeURIComponent("Disponível") + "&com_foto=nao&parceiro=nao",
    "status=" + encodeURIComponent("Disponível") + "&anunciado=nao&parceiro=nao",
    "confirmar=1"
  ];
  CONTAS.forEach(function (u, k) {
    fetch(API + "/api/imoveis-lista?per=1&" + u)
      .then(function (r) { return r.ok ? r.json() : { total: 0 }; })
      .then(function (d) { contaAtalho[k] = d.total; desenharAtalhos(); })
      .catch(function () {});
  });

  // desenha o que dá pra desenhar antes da primeira resposta -- a lateral
  // aparece montada, só sem os números, em vez de piscar vazia.
  desenharOpcoes();
  desenharAtalhos();
  desenharData();
  if (location.hash === "#mapa") {
    // o clique na aba faz o que um clique de verdade faz: acende a aba e abre o mapa
    document.querySelector('.abas [data-vista="mapa"]').click();
  } else {
    carregar();
  }

  /* ---- a aba Anúncios (o que está no catálogo, publicado ou não) ---- */
  fetch(API + "/api/anuncios")
    .then(function (r) { return r.json(); })
    .then(function (itens) {
      $("corpo-anuncios").innerHTML = itens.map(function (a) {
        return "<tr>" +
          '<td><span class="etiqueta ' + (a.status === "Rascunho" ? "etiqueta--laranja" : "etiqueta--verde") + '">' +
            esc(a.status === "Rascunho" ? "Fora do site" : "Publicado") + "</span></td>" +
          "<td><strong>" + esc(a.codigo) + "</strong> (" + esc(a.referencia) + ")</td>" +
          "<td>" + esc(a.tipo) + "</td><td>" + esc(a.financia) + "</td><td>" + esc(a.valor) + "</td>" +
          '<td class="col-acoes"><a class="btn-mini" href="imovel-editar.html?codigo=' + esc(a.codigo) + '">Editar</a></td></tr>';
      }).join("") || '<tr><td colspan="6">Nenhum anúncio.</td></tr>';
    })
    .catch(function () { $("corpo-anuncios").innerHTML = '<tr><td colspan="6">Não foi possível carregar.</td></tr>'; });
})();
