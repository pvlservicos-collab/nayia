/* ==========================================================================
   Imob Easy — a AGENDA DOS GRUPOS (admin › Grupos)

   Pedro, 03/10/2026: "uma aba Grupos no site, onde eu vou criar e agendar
   mensagens, e o conteúdo da mensagem vou preencher com os imóveis... no
   formato de uma agenda geral lá em cima, e eu podendo filtrar por grupo;
   quero adicionar, excluir, editar, metrificar a mensagem; as métricas são
   quantas pessoas chegaram nas próximas 6 horas que enviei".

   E depois: "divide cada grupo uma cor, e a mensagem está muito grande; as que
   são vários grupos ficam com o card colorido por várias cores, como várias
   tachinhas; e o conteúdo aparece separado como na conversa do WhatsApp
   normal, com diferenciação de cor para ficar mais fácil entender".

   Cada "mensagem" é uma vaga da GRADE do publicador (tabela vagas): horário,
   repetição (todo dia, dias da semana, um dia só), os imóveis e o destino (um
   apelido de grupo, ou vazio = cada imóvel vai aos grupos que aceitam o tipo
   e o valor dele). Quem manda é o cron disparar_grade.sh, no minuto marcado;
   esta tela só cria, edita, apaga e mede. Tudo por /admin/api/grade (senha do
   painel). Os imóveis do seletor vêm de /api/imoveis-para-enviar: só o que a
   Nay oferece, e nunca de parceiro (parceria não sai nos grupos).

   A CONVERSA. O publicador manda, para cada imóvel, primeiro o TEXTO do card e
   depois a FOTO: a metadinha (4 fotos numa), ou todas as fotos nos grupos de
   "anunciar" (todas_fotos). Cada grupo só vê os valores que aceita (o Alto
   Padrão tem piso). A tela desenha isso com o card de hoje do imóvel
   (/api/imovel-card, o mesmo dos grupos) e as regras de cada grupo (280).

   A LISTA (03/10 à tarde, 285/286): "quero também que crie, no criar mensagem,
   lista de imóveis, e editar essa mensagem fisicamente: hoje tu só edita
   horários". A mensagem pode ser uma LISTA: um texto só, um imóvel por linha
   ("✅Conquista rio negro cod 5724 / 2 quartos / 2.6k"). AUTOMÁTICA, o
   publicador monta na hora do envio; ESCRITA À MÃO (vagas.texto_fixo), sai o
   texto daqui, e na hora do envio só cai a linha do imóvel que saiu do ar.
   A tela risca essa linha com a MESMA conta do publicador (_codigos_no_ar).

   AS MÉTRICAS (aba ao lado de Grupos): "quantas vezes saiu cada mensagem, e
   uma estimativa de pessoas que chegaram marcando ela ou perguntando de
   imóveis dela". Vem de site_grade_metricas (286): só contagem, sem telefone.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "https://api.imobeasy.online";
  var FUSO = "America/Manaus";
  var DIAS = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
  var DIAS_LONGOS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];
  var ORDEM_DIAS = [1, 2, 3, 4, 5, 6, 0];          // a semana começa na segunda
  var ROTULO_DESTINO = { alto_padrao: "Alto Padrão", alto_padrao_easy: "Alto Padrão Easy", comercial: "Comercial", easy: "Easy" };
  /* uma cor por grupo; os grupos com apelido (os destinos que dá para escolher) ficam com as primeiras */
  var PALETA = ["#1e88e5", "#43a047", "#fb8c00", "#8e24aa", "#00acc1", "#d81b60", "#7cb342", "#5e35b1", "#00897b", "#f4511e",
                "#3949ab", "#c0ca33", "#6d4c41", "#039be5", "#fdd835", "#546e7a", "#ab47bc", "#26a69a", "#ec407a", "#e53935"];
  /* a cor de cada imóvel dentro da conversa, como o nome de quem escreve num grupo do WhatsApp */
  var ACENTOS = ["#6d28d9", "#0e7490", "#c2410c", "#be185d", "#15803d", "#1d4ed8", "#a16207", "#9333ea", "#0f766e", "#b91c1c"];
  var SIMBOLOS = /[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}\u{20E3}\u{200D}]/gu;
  var ICONE_PESSOA = '<svg viewBox="0 0 16 16" width="11" height="11" aria-hidden="true"><path fill="currentColor" d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm0 1.4c-3 0-5.6 1.5-5.6 3.6V14h11.2v-1c0-2.1-2.6-3.6-5.6-3.6z"/></svg>';
  var ICONE_CASA = '<svg viewBox="0 0 16 16" width="11" height="11" aria-hidden="true"><path fill="currentColor" d="M8 1.5 1 7.6h2.1V14.5h3.8v-4h2.2v4h3.8V7.6H15z"/></svg>';
  var ICONE_RELOGIO = '<svg viewBox="0 0 16 16" width="10" height="10" aria-hidden="true"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M8 4.6V8l2.4 1.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></svg>';

  var $ = function (id) { return document.getElementById(id); };
  function esc(v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pedir(url, opcoes) {
    return fetch(url, Object.assign({ credentials: "same-origin", headers: { "Content-Type": "application/json" } }, opcoes || {}))
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (r.status === 401) throw new Error("a senha do painel não foi aceita: recarregue a página e entre de novo");
          if (!r.ok && !("ok" in d)) throw new Error(d.erro || ("HTTP " + r.status));
          return d;
        });
      });
  }
  function reais(n) { return "R$ " + Number(n).toLocaleString("pt-BR", { maximumFractionDigits: 0 }); }
  function curto(n) {
    return n >= 1e6 ? (n / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) + " mi"
      : n >= 1e4 ? Math.round(n / 1e3).toLocaleString("pt-BR") + " mil" : (n / 1e3).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mil";
  }
  function foto(url, tam) { return url ? String(url).replace("/huge/", "/" + tam + "/") : ""; }
  /* datas em Manaus, como "AAAA-MM-DD" */
  function diaDe(d) {
    return new Intl.DateTimeFormat("en-CA", { timeZone: FUSO, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
  }
  function horaDe(d) { return new Intl.DateTimeFormat("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" }).format(d); }
  function somaDias(iso, n) { var d = new Date(iso + "T12:00:00"); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); }
  function segundaDe(iso) { var d = new Date(iso + "T12:00:00"); var dow = d.getDay(); return somaDias(iso, dow === 0 ? -6 : 1 - dow); }
  function rotuloDia(iso) {
    var d = new Date(iso + "T12:00:00");
    return DIAS[d.getDay()] + " " + d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
  }

  var NEGOCIO = { locacao: "locação", venda: "venda" };
  var COD_NA_LINHA = /\bcod\.?\s*(\d{3,5})\b/gi;      // a mesma do publicador (CODIGO_NA_LISTA)
  var LIMITE_DO_WHATSAPP = 3500;                       // acima disso a lista sai em partes (_pedacos_da_lista)

  /* ---- estado ---- */
  var semana = segundaDe(diaDe(new Date()));
  var opcoes = { grupos: [], destinos: [], categorias: [], destinos_lista: [] };
  var listasAuto = {};             // "categoria|negocio" -> Promise da lista que o publicador montaria agora
  var catalogoP = null;            // Promise de /api/imoveis-para-enviar
  var noAr = null;                 // código -> imóvel do catálogo; só existe depois de o catálogo carregar
  var metricas = { dias: 30, de: "", ate: "", dados: null, pedido: 0, todos: false };
  var corDoGrupo = {}, grupoPorId = {}, grupoPorNome = {};
  var dados = null;                // a resposta de /admin/api/grade
  var vagasPorId = {};
  var grupoFiltro = "";
  var imoveisCatalogo = null;      // carregado na primeira vez que a janela de editar abre
  var edicao = null;               // { id, lista, escolhidos: [{codigo,titulo,foto,...}] }
  var detalhe = null;              // { o, v, gs, visto } a mensagem aberta
  var cards = {};                  // código -> Promise do card (o mesmo dos grupos)

  /* ---- os grupos e as cores ---- */
  function nomeCurto(n) {
    var s = String(n || "").replace(SIMBOLOS, "").replace(/\s+/g, " ").replace(/^[\s\-|·]+|[\s\-|·]+$/g, "").trim();
    return s || String(n || "");
  }
  function iniciais(n) {
    return nomeCurto(n).split(/[\s\-|]+/).filter(function (p) { return /^[A-Za-zÀ-ú0-9]/.test(p); }).slice(0, 2)
      .map(function (p) { return p.charAt(0).toUpperCase(); }).join("") || "G";
  }
  function prepararGrupos(lista) {
    var peso = function (g) { return g.lotado || !g.ativo ? 2 : g.apelido ? 0 : 1; };
    var ordem = (lista || []).slice().sort(function (a, b) {
      return peso(a) - peso(b) || String(a.apelido || "").localeCompare(String(b.apelido || "")) ||
        nomeCurto(a.nome).localeCompare(nomeCurto(b.nome), "pt-BR");
    });
    corDoGrupo = {}; grupoPorId = {}; grupoPorNome = {};
    ordem.forEach(function (g, k) { corDoGrupo[g.id] = PALETA[k % PALETA.length]; grupoPorId[g.id] = g; grupoPorNome[g.nome] = g; });
    return ordem;
  }
  function cor(g) { return (g && corDoGrupo[g.id]) || "#9aa0a6"; }
  function tacha(g, vazia) {
    return '<i class="ga-tacha' + (vazia ? " ga-tacha--vazia" : "") + '" style="--c:' + cor(g) + '" title="' + esc(nomeCurto(g.nome)) + '"></i>';
  }
  /* Pedro, 03/10: "quando tiver várias bolas não precisa ter todas, pode ser só uma, e uma atrás mais
     transparente, e um + no canto". Até 2 grupos vão as bolinhas; de 3 em diante, a pilha. O grupo do
     filtro fica na frente; os nomes de todos ficam no título (passar o mouse). */
  function tachinhas(gs, vazia) {
    if (gs.length <= 2) return gs.map(function (g) { return tacha(g, vazia); }).join("");
    var frente = (grupoFiltro && gs.find(function (g) { return g.id === grupoFiltro; })) || gs[0];
    var atras = gs.find(function (g) { return g !== frente; });
    return '<span class="ga-pilha" title="' + esc(gs.length + " grupos: " + gs.map(function (g) { return nomeCurto(g.nome); }).join(", ")) + '">' +
      tacha(frente, vazia).replace(/ title="[^"]*"/, "") +
      tacha(atras, vazia).replace('class="ga-tacha', 'class="ga-tacha ga-tacha--atras').replace(/ title="[^"]*"/, "") +
      '<b class="ga-pilha__mais">+' + (gs.length - 1) + "</b></span>";
  }
  /* a faixa da esquerda do cartão: uma cor só, ou as cores de todos os grupos, uma embaixo da outra */
  function faixa(gs) {
    if (!gs.length) return "transparent";
    if (gs.length === 1) return cor(gs[0]);
    return "linear-gradient(" + gs.map(function (g, k) {
      return cor(g) + " " + (k * 100 / gs.length).toFixed(2) + "% " + ((k + 1) * 100 / gs.length).toFixed(2) + "%";
    }).join(", ") + ")";
  }

  function nomeDaCategoria(c) {
    var x = (opcoes.categorias || []).find(function (k) { return k.chave === c; });
    return x ? x.nome : String(c || "").replace(/_/g, " ");
  }
  function nomeDaLista(v) { return "Lista de " + nomeDaCategoria(v.categoria).toLowerCase() + " para " + (NEGOCIO[v.negocio] || "locação"); }
  /* a lista tem texto escrito à mão? (na agenda vem o texto; nas métricas, só verdadeiro ou falso) */
  function aMao(v) { return !!v && (v.texto_fixo === true || (typeof v.texto_fixo === "string" && v.texto_fixo.trim() !== "")); }
  /* os grupos que recebem a lista: a mesma regra do publicador (_disparar_lista) e do `previstos` da agenda.
     Grupo LOTADO também recebe (lotado é não caber mais gente; a mensagem chega do mesmo jeito) */
  function gruposDaLista(destino, negocio, categoria) {
    var ativos = opcoes.grupos.filter(function (g) { return g.ativo; });
    if (destino === "easy" || destino === "comercial") return ativos.filter(function (g) { return g.apelido === destino; });
    return ativos.filter(function (g) {
      return !g.todas_fotos && (negocio === "venda" ? g.venda : g.locacao) && !(g.so_comercial && categoria !== "sala");
    });
  }
  function nomeDoDestino(v) {
    if (v.categoria) {
      var dl = (opcoes.destinos_lista || []).find(function (x) { return x.chave === (v.destino || "parceiros"); });
      return dl ? dl.nome : "Grupos de parceiros";
    }
    if (!v.destino) return "Todos os grupos que aceitam o imóvel";
    var d = opcoes.destinos.find(function (x) { return x.apelido === v.destino; });
    return (ROTULO_DESTINO[v.destino] || v.destino.replace(/_/g, " ")) + (d && d.grupos.length === 1 ? "" : d ? " (" + d.grupos.length + " grupos)" : "");
  }
  function descreverRepeticao(v) {
    if (v.recorrencia === "diaria") return "todo dia às " + v.horario;
    if (v.recorrencia === "unica") return "em " + new Date(v.data + "T12:00:00").toLocaleDateString("pt-BR") + " às " + v.horario;
    var dias = (v.dias || []).slice().sort(function (a, b) { return ORDEM_DIAS.indexOf(a) - ORDEM_DIAS.indexOf(b); });
    return dias.map(function (d) { return DIAS_LONGOS[d]; }).join(", ").replace(/, ([^,]*)$/, " e $1") + " às " + v.horario;
  }
  /* HORÁRIO LIVRE: vaga da grade sem imóvel (o publicador guarda de reserva e não posta nada) */
  function livre(v) { return !!v && !v.categoria && !(v.imoveis || []).length; }
  function tituloDaVaga(v) {
    if (v.categoria) return nomeDaLista(v) + (aMao(v) ? " (texto escrito à mão)" : "");
    var ims = v.imoveis || [];
    if (!ims.length) return "Horário livre (sem imóvel)";
    return ims.map(function (i) { return i.codigo + (i.titulo ? " · " + i.titulo : ""); }).join(" + ");
  }
  function tituloCurto(v) {
    if (v.categoria) return "Lista " + nomeDaCategoria(v.categoria).toLowerCase() + " · " + (NEGOCIO[v.negocio] || "locação");
    var ims = v.imoveis || [];
    if (ims.length === 1) return ims[0].codigo + (ims[0].titulo ? " " + ims[0].titulo : "");
    return ims.map(function (i) { return i.codigo; }).join(", ");
  }

  /* os grupos de uma ocorrência: o que JÁ saiu, pelos grupos que receberam; o resto, pelos previstos */
  function saiu(o) { return !!(o.passou && o.posts); }
  function gruposDe(o) {
    if (saiu(o)) return (o.grupos || []).map(function (n) { return grupoPorNome[n] || { id: n, nome: n }; });
    var v = vagasPorId[o.vaga] || {};
    return (v.previstos || []).map(function (id) { return grupoPorId[id]; }).filter(Boolean);
  }
  function passaNoFiltro(o) {
    if (!grupoFiltro) return true;
    return gruposDe(o).some(function (g) { return g.id === grupoFiltro; });
  }
  function estadoDe(o) {
    return livre(vagasPorId[o.vaga]) ? "livre" : !o.passou ? "futuro" : o.posts ? "saiu" : "falhou";
  }

  /* ---- carregar ---- */
  function carregar() {
    $("ga-periodo").textContent = rotuloDia(semana) + " a " + rotuloDia(somaDias(semana, 6));
    $("ga-agenda").innerHTML = '<p class="ga-carregando">Carregando a agenda…</p>';
    return pedir("/admin/api/grade?de=" + semana + "&ate=" + somaDias(semana, 6))
      .then(function (d) {
        dados = d; vagasPorId = {};
        (d.vagas || []).forEach(function (v) { vagasPorId[v.id] = v; });
        desenhar();
      })
      .catch(function (e) {
        $("ga-agenda").innerHTML = '<p class="ga-erro">Não consegui carregar a agenda: ' + esc(e.message) + "</p>";
      });
  }

  /* a legenda das cores É o filtro: clicar num grupo deixa só as mensagens dele */
  function desenharLegenda() {
    var conta = {};
    (dados.ocorrencias || []).forEach(function (o) {
      if (livre(vagasPorId[o.vaga])) return;
      gruposDe(o).forEach(function (g) { conta[g.id] = (conta[g.id] || 0) + 1; });
    });
    var visiveis = opcoes.grupos.filter(function (g) { return g.ativo && !g.lotado; });
    $("ga-legenda").innerHTML =
      '<button type="button" class="ga-chip" data-grupo="" aria-pressed="' + !grupoFiltro + '">Todos os grupos</button>' +
      visiveis.map(function (g) {
        return '<button type="button" class="ga-chip" data-grupo="' + esc(g.id) + '" aria-pressed="' + (grupoFiltro === g.id) +
          '" style="--c:' + cor(g) + '" title="' + esc(g.nome) + '">' + tacha(g) + "<span>" + esc(nomeCurto(g.nome)) + "</span>" +
          "<small>" + (conta[g.id] || 0) + "</small></button>";
      }).join("");
  }

  function desenhar() {
    desenharLegenda();
    var oc = (dados.ocorrencias || []).filter(passaNoFiltro).sort(function (a, b) { return a.quando < b.quando ? -1 : a.quando > b.quando ? 1 : 0; });
    // a agenda: uma coluna por dia, e dentro dela um bloco por horário
    var porDia = {};
    oc.forEach(function (o) { var d = diaDe(new Date(o.quando)); (porDia[d] = porDia[d] || []).push(o); });
    var hoje = diaDe(new Date());
    $("ga-agenda").innerHTML = '<div class="ga-semana">' + [0, 1, 2, 3, 4, 5, 6].map(function (k) {
      var dia = somaDias(semana, k), lista = porDia[dia] || [];
      var n = lista.filter(function (o) { return !livre(vagasPorId[o.vaga]); }).length;
      var horas = [], porHora = {};
      lista.forEach(function (o) {
        var h = horaDe(new Date(o.quando));
        if (!porHora[h]) { porHora[h] = []; horas.push(h); }
        porHora[h].push(o);
      });
      return '<div class="ga-dia' + (dia === hoje ? " ga-dia--hoje" : "") + (dia < hoje ? " ga-dia--passado" : "") + '">' +
        '<div class="ga-dia__topo">' + esc(rotuloDia(dia)) + (n ? ' <span class="ga-dia__n" title="mensagens com imóvel">' + n + "</span>" : "") + "</div>" +
        (horas.length ? horas.map(function (h) {
          var cheios = porHora[h].filter(function (o) { return !livre(vagasPorId[o.vaga]); });
          var livres = porHora[h].filter(function (o) { return livre(vagasPorId[o.vaga]); });
          return '<div class="ga-hora"><span class="ga-hora__h">' + h + "</span>" + cheios.map(cartao).join("") +
            (livres.length ? '<div class="ga-livres">' + livres.map(function (o) {
              return '<button type="button" class="ga-livre" data-ocorrencia="' + esc(o.vaga + "|" + o.quando) +
                '" title="Horário livre da grade: sem imóvel, nada sai. Clique para pôr imóveis.">livre</button>';
            }).join("") + "</div>" : "") + "</div>";
        }).join("") : '<p class="ga-dia__vazio">nada agendado</p>') + "</div>";
    }).join("") + "</div>";

    // o resumo da semana
    var saidas = oc.filter(saiu);
    var soma = function (k) { return saidas.reduce(function (s, o) { return s + (o[k] || 0); }, 0); };
    var comImovel = oc.filter(function (o) { return !livre(vagasPorId[o.vaga]); });
    $("ga-resumo").innerHTML =
      '<div class="ga-cartao-num"><b>' + comImovel.length + "</b><span>mensagens na semana" + (grupoFiltro ? " (neste grupo)" : "") + "</span></div>" +
      '<div class="ga-cartao-num"><b>' + saidas.length + "</b><span>já saíram</span></div>" +
      '<div class="ga-cartao-num"><b>' + comImovel.filter(function (o) { return o.passou && !o.posts; }).length + "</b><span>não saíram</span></div>" +
      '<div class="ga-cartao-num ga-cartao-num--destaque"><b>' + soma("pelo_imovel") + "</b><span>chegaram pelo imóvel (6 h)</span></div>" +
      '<div class="ga-cartao-num"><b>' + soma("novos") + "</b><span>pessoas novas (6 h)</span></div>";

    // a tabela: uma linha por mensagem (vaga), com a soma da semana
    var porVaga = {};
    oc.forEach(function (o) { (porVaga[o.vaga] = porVaga[o.vaga] || []).push(o); });
    var vagas = (dados.vagas || []).filter(function (v) { return porVaga[v.id] || !grupoFiltro; });
    $("ga-tabela").innerHTML = vagas.length ? vagas.map(function (v) {
      var os = (porVaga[v.id] || []).filter(saiu);
      var s = function (k) { return os.reduce(function (t, o) { return t + (o[k] || 0); }, 0); };
      var previstos = (v.previstos || []).map(function (id) { return grupoPorId[id]; }).filter(Boolean);
      return "<tr>" +
        "<td>" + esc(descreverRepeticao(v)) + "</td>" +
        '<td class="ga-tab-imoveis">' + imoveisMini(v) + "</td>" +
        '<td><span class="ga-tab-tachas">' + tachinhas(previstos) + "</span>" + esc(nomeDoDestino(v)) + "</td>" +
        '<td class="num">' + os.length + "</td>" +
        '<td class="num">' + s("pessoas") + "</td>" +
        '<td class="num">' + s("novos") + "</td>" +
        '<td class="num"><b>' + s("pelo_imovel") + "</b></td>" +
        '<td class="col-acoes"><button type="button" class="btn-mini" data-editar="' + v.id + '">Editar</button> ' +
          '<button type="button" class="btn-mini btn-mini--perigo" data-excluir="' + v.id + '">Excluir</button></td></tr>';
    }).join("") : '<tr><td colspan="8" class="ga-dica">Nenhuma mensagem para esse grupo.</td></tr>';
  }

  function listaMini(v) {
    return '<span class="ga-lista-mini"><b>' + esc(nomeDaLista(v)) + "</b><small>" +
      (aMao(v) ? "texto escrito à mão" : "montada na hora do envio") + "</small></span>";
  }
  function imoveisMini(v) {
    if (v.categoria) return listaMini(v);
    if (livre(v)) return '<span class="ga-dica">Horário livre (sem imóvel)</span>';
    return (v.imoveis || []).map(function (i) {
      var alerta = i.parceiro ? "de parceiro: não sai" : i.no_ar === false ? "fora do ar: não sai" : i.existe === false ? "não existe" : "";
      return '<span class="ga-im' + (alerta ? " ga-im--alerta" : "") + '" title="' + esc(alerta || i.titulo || "") + '">' +
        (i.foto ? '<img src="' + esc(foto(i.foto, "small")) + '" alt="" loading="lazy">' : "") + "<b>" + esc(i.codigo) + "</b>" +
        (i.titulo ? "<small>" + esc(i.titulo) + "</small>" : "") + (alerta ? "<em>" + esc(alerta) + "</em>" : "") + "</span>";
    }).join("");
  }

  /* o cartão da agenda: o imóvel numa linha, as tachinhas dos grupos embaixo */
  function cartao(o) {
    var v = vagasPorId[o.vaga] || {};
    var gs = gruposDe(o);
    var estado = estadoDe(o);
    var st = estado === "saiu" ? '<span class="ga-cartao__st ga-cartao__st--saiu" title="Saiu em ' + gs.length + (gs.length === 1 ? " grupo" : " grupos") + '">✓</span>'
      : estado === "falhou" ? '<span class="ga-cartao__st ga-cartao__st--falhou" title="Não saiu">!</span>'
      : '<span class="ga-cartao__st ga-cartao__st--futuro" title="Agendada">' + ICONE_RELOGIO + "</span>";
    var num = estado === "saiu"
      ? '<span class="ga-cartao__num" title="' + (o.pessoas || 0) + " chegaram nas 6 h" + (o.janela_completa ? "" : " (a janela ainda está aberta)") +
          " · " + (o.pelo_imovel || 0) + " pelo imóvel · " + (o.novos || 0) + ' novos">' + ICONE_PESSOA + (o.pessoas || 0) +
          (o.pelo_imovel ? '<b class="ga-cartao__im">' + ICONE_CASA + o.pelo_imovel + "</b>" : "") + "</span>"
      : "";
    return '<button type="button" class="ga-cartao ga-cartao--' + estado + '" style="--faixa:' + faixa(gs) + '" data-ocorrencia="' + esc(o.vaga + "|" + o.quando) +
        '" title="' + esc(tituloDaVaga(v) + " — " + nomeDoDestino(v)) + '">' +
      '<span class="ga-cartao__linha"><span class="ga-cartao__tit">' + esc(tituloCurto(v)) + "</span>" + st + "</span>" +
      '<span class="ga-cartao__tachas">' + tachinhas(gs, estado === "falhou") + num + "</span>" +
    "</button>";
  }

  /* ---- a conversa: o post como ele chega no grupo ---- */
  function card(codigo) {
    var c = String(codigo);
    if (!cards[c]) {
      cards[c] = fetch(API + "/api/imovel-card/" + encodeURIComponent(c))
        .then(function (r) { return r.ok ? r.json() : null; })
        .catch(function () { return null; });
    }
    return cards[c];
  }
  /* cada grupo só vê os valores que aceita (montar_destinos.py: aceita_venda/aceita_locacao e o piso) */
  function textoParaGrupo(d, g) {
    var t = d.card || "", im = d.imovel || {};
    if (!g || (im.valor_venda == null && im.valor_aluguel == null)) return t;
    var vendaOk = im.valor_venda != null && g.venda !== false && !(g.venda_minima != null && im.valor_venda < Number(g.venda_minima));
    var locOk = im.valor_aluguel != null && g.locacao !== false && !(g.aluguel_minimo != null && im.valor_aluguel < Number(g.aluguel_minimo));
    if (!vendaOk && !locOk) return null;
    var saida = [], tirouVenda = false;
    t.split("\n").forEach(function (l) {
      if (/^Venda:/i.test(l) && !vendaOk) { tirouVenda = true; return; }
      if (/^Loca[cç][aã]o:/i.test(l) && !locOk) return;
      if (tirouVenda && /financiamento/i.test(l)) { tirouVenda = false; return; }
      tirouVenda = false;
      saida.push(l);
    });
    return saida.join("\n");
  }
  /* o texto do card com cada parte numa cor: título, valores, OBS e código */
  function formatarCard(t) {
    return t.split("\n").map(function (l) {
      var c = /^📍/.test(l) ? "tit" : /^(Venda|Loca[cç][aã]o):/i.test(l) ? "valor" : /^C[óo]digo:/i.test(l) ? "cod"
        : /^OBS:/i.test(l) ? "obs" : /financiamento/i.test(l) ? "fin" : "";
      var h = esc(l).replace(/\*([^*\n]+)\*/g, "<b>$1</b>").replace(/(^|\s)_([^_\n]+)_/g, "$1<i>$2</i>");
      return '<span class="ga-l' + (c ? " ga-l--" + c : "") + '">' + (h || "&nbsp;") + "</span>";
    }).join("");
  }
  function baloesDoImovel(k, total, im, d, g, hora, estado) {
    var acento = ACENTOS[k % ACENTOS.length];
    var pilula = '<div class="ga-zap__pilula" style="--im:' + acento + '">' + (total > 1 ? (k + 1) + "º de " + total + " · " : "") +
      "Imóvel " + esc(im.codigo) + (im.titulo ? " · " + esc(im.titulo) : "") + "</div>";
    if (!d) return pilula + '<div class="ga-zap__nota ga-zap__nota--erro">Não achei o card do ' + esc(im.codigo) +
      ". Imóvel fora do ar não sai: o publicador pula e avisa o Tel.</div>";
    var texto = textoParaGrupo(d, g);
    if (texto === null) return pilula + '<div class="ga-zap__nota">Este imóvel não entra neste grupo: o grupo não aceita esse negócio ou esse valor.</div>';
    var tic = estado === "saiu" ? '<i class="ga-tic" title="Entregue">✓✓</i>' : estado === "futuro" ? '<i class="ga-tic ga-tic--relogio" title="Agendada">' + ICONE_RELOGIO + "</i>" : "";
    var rodape = '<span class="ga-balao__hora">' + esc(hora) + tic + "</span>";
    var todas = !!(g && g.todas_fotos);
    var fotos = todas ? (d.fotos || []) : [d.colagem || (d.fotos || [])[0]].filter(Boolean);
    var rotFoto = todas ? fotos.length + (fotos.length === 1 ? " foto" : " fotos, uma por mensagem") : d.colagem ? "a metadinha (4 fotos numa)" : "a capa (ainda sem metadinha)";
    var album = fotos.slice(0, 4).map(function (u, n) {
      var resto = n === 3 && fotos.length > 4 ? '<span class="ga-album__mais">+' + (fotos.length - 4) + "</span>" : "";
      return '<span class="ga-album__item"><img src="' + esc(foto(u, "medium")) + '" alt="" loading="lazy">' + resto + "</span>";
    }).join("");
    return pilula +
      '<div class="ga-balao ga-balao--texto" style="--im:' + acento + '"><span class="ga-balao__rot">1ª mensagem · texto</span>' +
        formatarCard(texto) + rodape + "</div>" +
      (fotos.length
        ? '<div class="ga-balao ga-balao--foto" style="--im:' + acento + '"><span class="ga-balao__rot">2ª mensagem · ' + esc(rotFoto) + "</span>" +
            '<div class="ga-album ga-album--' + Math.min(fotos.length, 4) + '">' + album + "</div>" + rodape + "</div>"
        : '<div class="ga-zap__nota">Sem foto: vai só o texto.</div>');
  }
  /* ---- a lista de imóveis: um texto só ---- */
  function listaDeAgora(categoria, negocio, deNovo) {
    var k = categoria + "|" + negocio;
    if (deNovo) delete listasAuto[k];
    if (!listasAuto[k]) {
      listasAuto[k] = pedir("/admin/api/grade/lista?categoria=" + encodeURIComponent(categoria) + "&negocio=" + encodeURIComponent(negocio))
        .then(function (r) { return r.ok ? { quantos: r.quantos || 0, texto: r.texto || "" } : { quantos: 0, texto: "", erro: r.erro || "Não consegui montar a lista." }; })
        .catch(function (e) { delete listasAuto[k]; return { quantos: 0, texto: "", erro: e.message }; });
    }
    return listasAuto[k];
  }
  /* o catálogo do que a Nay oferece: no mercado, nunca de parceiro, com valor. É a conta do publicador
     (_codigos_no_ar) e serve ao seletor de imóveis e ao risco das linhas da lista escrita à mão */
  function catalogo() {
    if (!catalogoP) {
      catalogoP = fetch(API + "/api/imoveis-para-enviar").then(function (r) { return r.json(); })
        .then(function (d) {
          imoveisCatalogo = d.imoveis || [];
          noAr = {};
          imoveisCatalogo.forEach(function (m) { noAr[String(m.codigo)] = m; });
          return imoveisCatalogo;
        })
        .catch(function () { catalogoP = null; return null; });
    }
    return catalogoP;
  }
  function saiNaLista(codigo, negocio) {
    if (!noAr) return true;        // sem o catálogo não dá para saber: não acusa ninguém
    var m = noAr[String(Number(codigo))];
    return !!m && (negocio === "venda" ? m.venda > 0 : m.aluguel > 0);
  }
  /* cada linha do texto, e se ela CAI na hora do envio (a conta de _lista_escrita_a_mao no publicador) */
  function linhasDaLista(texto, negocio, conferir) {
    return String(texto || "").split("\n").map(function (l) {
      var cods = [];
      l.replace(COD_NA_LINHA, function (tudo, c) { cods.push(c); return tudo; });
      return { l: l, cods: cods, fora: !!conferir && cods.length > 0 && !cods.every(function (c) { return saiNaLista(c, negocio); }) };
    });
  }
  function contaDaLista(linhas) {
    return { saem: linhas.filter(function (x) { return x.cods.length && !x.fora; }).length,
             fora: linhas.filter(function (x) { return x.fora; }).length };
  }
  function formatarLista(linhas) {
    var primeira = true;
    return linhas.map(function (x) {
      var h = esc(x.l).replace(/\*([^*\n]+)\*/g, "<b>$1</b>").replace(/\b(cod\.?\s*\d{3,5})\b/gi, '<b class="ga-l__cod">$1</b>');
      var c = x.fora ? "fora" : (!x.cods.length && x.l.trim() && primeira) ? "tit" : "";
      if (x.l.trim()) primeira = false;
      return '<span class="ga-l' + (c ? " ga-l--" + c : "") + '"' + (x.fora ? ' title="Fora do ar: esta linha é retirada na hora do envio"' : "") + ">" + (h || "&nbsp;") + "</span>";
    }).join("");
  }
  function plural(n, um, varios) { return n + " " + (n === 1 ? um : varios); }
  /* r: { texto, quantos, erro }; escrita: o texto é o escrito à mão (confere linha por linha) */
  function balaoDaLista(v, r, escrita, hora, estado) {
    if (!r || !String(r.texto || "").trim()) {
      return '<div class="ga-zap__nota' + (r && r.erro ? " ga-zap__nota--erro" : "") + '">' +
        esc((r && r.erro) || (escrita ? "Escreva o texto da lista: um imóvel por linha, com \"cod 1234\"." : "Hoje não há nenhum imóvel nessa lista: nada sairia.")) + "</div>";
    }
    var linhas = linhasDaLista(r.texto, v.negocio, escrita), n = contaDaLista(linhas);
    var tic = estado === "saiu" ? '<i class="ga-tic" title="Entregue">✓✓</i>' : estado === "futuro" ? '<i class="ga-tic ga-tic--relogio" title="Agendada">' + ICONE_RELOGIO + "</i>" : "";
    var nota = escrita
      ? "Texto escrito à mão: sai assim, com " + plural(n.saem, "imóvel", "imóveis") + ". Os valores não se atualizam sozinhos." +
        (n.fora ? " " + (n.fora === 1 ? "A linha riscada é de imóvel fora do ar e é retirada" : "As " + n.fora + " linhas riscadas são de imóveis fora do ar e são retiradas") + " na hora do envio." : "")
      : "A lista de agora, com " + plural(r.quantos, "imóvel", "imóveis") + ". O publicador monta de novo na hora do envio, com os imóveis e os valores daquele momento.";
    if (estado === "saiu") nota += " O que saiu naquele dia pode ter sido diferente do texto de hoje.";
    var partes = Math.ceil(String(r.texto).length / LIMITE_DO_WHATSAPP);
    return '<div class="ga-zap__nota' + (escrita && !n.saem ? " ga-zap__nota--erro" : "") + '">' +
        esc(escrita && !n.saem ? "Nenhuma linha tem um imóvel que está no ar (escreva \"cod 1234\"): assim nada sai." : nota) + "</div>" +
      '<div class="ga-balao ga-balao--texto ga-balao--lista" style="--im:#6d28d9">' + formatarLista(linhas) +
        '<span class="ga-balao__hora">' + esc(hora) + tic + "</span></div>" +
      (partes > 1 ? '<div class="ga-zap__nota">Texto longo: no WhatsApp sai em ' + partes + " mensagens seguidas.</div>" : "");
  }

  /* alvo: onde desenhar; v: a vaga (ou a edição); g: o grupo visto (ou nada); quando: Date ou nada */
  function desenharConversa(alvo, v, g, quando, estado, hora) {
    var ims = v.imoveis || [];
    var corpoDeAntes = alvo.querySelector(".ga-zap__corpo"), rolagem = corpoDeAntes ? corpoDeAntes.scrollTop : 0;
    var cabeca = '<div class="ga-zap__topo" style="--g:' + (g ? cor(g) : "#8696a0") + '">' +
      '<span class="ga-zap__avatar">' + (g ? esc(iniciais(g.nome)) : "G") + "</span>" +
      "<div><b>" + esc(g ? nomeCurto(g.nome) : v.categoria ? nomeDoDestino(v) : "Grupos que aceitam o imóvel") + "</b><small>" +
      (v.categoria ? (g && (g.aluguel_minimo != null || g.venda_minima != null || g.so_condominio)
          ? "grupo com regra de valor: recebe só os imóveis da lista que passam nela" : "a lista sai inteira, num texto só")
        : g ? (g.todas_fotos ? "grupo de anunciar: vão todas as fotos" : "Imob Easy · número da Parceria") : "cada um recebe só os valores que aceita") +
      "</small></div></div>";
    var dia = quando ? quando.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" })
      : estado === "previa" ? "como vai chegar" : "";
    var corpo;
    if (v.categoria) corpo = '<p class="ga-zap__carregando">Montando a lista…</p>';
    else if (!ims.length) corpo = '<div class="ga-zap__nota">' + (estado === "previa" ? "Escolha os imóveis: cada um vira um texto e uma foto aqui." : "Horário livre: sem imóvel, nada sai.") + "</div>";
    else corpo = '<p class="ga-zap__carregando">Montando a conversa…</p>';
    alvo.innerHTML = '<div class="ga-zap">' + cabeca + '<div class="ga-zap__corpo">' + (dia ? '<div class="ga-zap__dia">' + esc(dia) + "</div>" : "") + corpo + "</div></div>";
    if (!v.categoria && !ims.length) return;
    var marca = {};
    alvo.__marca = marca;          // se a conversa for redesenhada antes de chegar, esta resposta não vale mais
    if (v.categoria) {
      // `escrita` vem dito pelo editor (o texto pode estar vazio no meio da edição); na agenda, pelo texto da vaga
      var escrita = v.escrita != null ? !!v.escrita : aMao(v);
      Promise.all([escrita ? { texto: v.texto_fixo || "" } : listaDeAgora(v.categoria, v.negocio), escrita ? catalogo() : null]).then(function (r) {
        if (alvo.__marca !== marca) return;
        var c = alvo.querySelector(".ga-zap__carregando");
        if (c) c.outerHTML = balaoDaLista(v, r[0], escrita, hora, estado);
        // quem está escrevendo o fim da lista não pode ver a prévia pular para o começo a cada letra
        var corpoNovo = alvo.querySelector(".ga-zap__corpo");
        if (corpoNovo && rolagem) corpoNovo.scrollTop = rolagem;
      });
      return;
    }
    Promise.all(ims.map(function (i) { return card(i.codigo); })).then(function (lista) {
      if (alvo.__marca !== marca) return;
      var c = alvo.querySelector(".ga-zap__carregando");
      if (!c) return;
      c.outerHTML = lista.map(function (d, k) { return baloesDoImovel(k, ims.length, ims[k], d, g, hora, estado); }).join("");
    });
  }

  /* ---- detalhe de um envio ---- */
  function abrirDetalhe(chave) {
    var p = chave.split("|"), o = (dados.ocorrencias || []).find(function (x) { return String(x.vaga) === p[0] && x.quando === p[1]; });
    if (!o) return;
    var v = vagasPorId[o.vaga] || {}, gs = gruposDe(o);
    var noFiltro = grupoFiltro && gs.find(function (g) { return g.id === grupoFiltro; });
    detalhe = { o: o, v: v, gs: gs, visto: noFiltro || gs[0] || null };
    var q = new Date(o.quando);
    $("ga-det-tit").textContent = q.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "long", day: "2-digit", month: "2-digit" }) + " às " + horaDe(q);
    var estado = estadoDe(o);
    var situacao = {
      livre: '<p class="ga-situacao ga-situacao--livre">Horário livre da grade: sem imóvel, nada sai. Clique em Editar para pôr imóveis nele.</p>',
      futuro: '<p class="ga-situacao ga-situacao--futuro">' + ICONE_RELOGIO + " Agendada. As métricas aparecem depois do envio.</p>",
      falhou: '<p class="ga-situacao ga-situacao--falhou">' + (v.categoria
        ? "Não saiu. A lista não sai quando não tem imóvel no ar, ou quando a mesma lista já tinha saído pouco antes; o publicador avisa o motivo ao Tel no WhatsApp."
        : "Não saiu. O publicador recusa imóvel fora do ar, de parceiro ou abaixo da faixa do grupo, e avisa o motivo ao Tel no WhatsApp.") + "</p>",
      saiu: '<p class="ga-situacao ga-situacao--saiu">✓ Saiu em ' + gs.length + (gs.length === 1 ? " grupo" : " grupos") + ".</p>"
    }[estado];
    $("ga-det-corpo").innerHTML =
      '<div class="ga-det-grade">' +
        '<div class="ga-det-info">' + situacao +
          '<p class="ga-dica">' + esc(descreverRepeticao(v)) + " · " + esc(nomeDoDestino(v)) + "</p>" +
          (estado === "saiu"
            ? '<div class="ga-det-num"><div><b>' + (o.pessoas || 0) + "</b><span>chegaram em 6 h</span></div>" +
                "<div><b>" + (o.novos || 0) + "</b><span>pessoas novas</span></div>" +
                '<div class="ga-det-num__destaque"><b>' + (o.pelo_imovel || 0) + "</b><span>pelo imóvel</span></div></div>" +
                (o.janela_completa ? "" : '<p class="ga-dica">As 6 h ainda não acabaram: os números vão subir.</p>')
            : "") +
          (gs.length && estado !== "livre"
            ? "<h3>" + (estado === "saiu" ? "Os grupos que receberam" : "Os grupos previstos") + " <small>(clique para ver a conversa nele)</small></h3>" +
              '<div class="ga-det-grupos" data-estado-proprio>' + gs.map(function (g) {
                return '<button type="button" class="ga-chip" data-ver-grupo="' + esc(g.id) + '" aria-pressed="' + (detalhe.visto && detalhe.visto.id === g.id) +
                  '" style="--c:' + cor(g) + '">' + tacha(g, estado === "falhou") + "<span>" + esc(nomeCurto(g.nome)) + "</span></button>";
              }).join("") + "</div>" +
              (saiu(o) ? "" : v.categoria
                ? '<p class="ga-dica">A lista vai inteira para cada grupo; o grupo com valor mínimo (Alto Padrão) recebe só os imóveis que passam na regra dele.</p>'
                : '<p class="ga-dica">Sem destino, cada imóvel vai só aos grupos que aceitam o tipo e o valor dele: a lista exata sai na hora do envio.</p>')
            : "") +
          '<div class="ga-dialogo__acoes"><button type="button" class="btn-mini btn-mini--perigo" data-excluir="' + v.id + '">Excluir a mensagem</button>' +
            '<button type="button" class="btn-azul" data-editar="' + v.id + '">Editar</button></div>' +
        "</div>" +
        '<div class="ga-det-conversa" id="ga-det-zap"></div>' +
      "</div>";
    desenharConversa($("ga-det-zap"), v, detalhe.visto, q, estado, horaDe(q));
    abrirDialogo($("ga-detalhe"));
  }
  function verNoGrupo(id) {
    if (!detalhe) return;
    detalhe.visto = detalhe.gs.find(function (g) { return g.id === id; }) || detalhe.visto;
    document.querySelectorAll("#ga-det-corpo [data-ver-grupo]").forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.verGrupo === id)); });
    var q = new Date(detalhe.o.quando);
    desenharConversa($("ga-det-zap"), detalhe.v, detalhe.visto, q, estadoDe(detalhe.o), horaDe(q));
  }

  /* ---- criar e editar ---- */
  function abrirEditor(v) {
    var lista = !!(v && v.categoria);
    // tipo: "imoveis" (card e fotos de cada um) ou "lista" (um texto só). modo: a lista "auto" (montada na hora do
    // envio) ou "mao" (vagas.texto_fixo). `texto` é o escrito à mão; `textoAuto`, o que o publicador montaria agora.
    edicao = { id: v ? v.id : null, tipo: lista ? "lista" : "imoveis",
      modo: lista && aMao(v) ? "mao" : "auto", texto: lista && aMao(v) ? String(v.texto_fixo) : "",
      textoAuto: "", quantosAuto: null, erroAuto: "",
      escolhidos: v && !lista ? (v.imoveis || []).map(function (i) {
        return { codigo: String(i.codigo), titulo: i.titulo, foto: i.foto, bairro: i.bairro, venda: i.venda, aluguel: i.aluguel };
      }) : [] };
    $("ga-ed-tit").textContent = v ? (lista ? "Editar lista" : "Editar mensagem") : "Nova mensagem";
    $("ga-tipo").hidden = !!v || !(opcoes.categorias || []).length;       // o tipo se escolhe só ao criar
    document.querySelectorAll('#ga-form input[name="tipo"]').forEach(function (r) { r.checked = r.value === edicao.tipo; });
    $("ga-categoria").innerHTML = (opcoes.categorias || []).map(function (c) {
      return '<option value="' + esc(c.chave) + '">' + esc(c.nome) + "</option>";
    }).join("");
    $("ga-categoria").value = lista ? v.categoria : "apartamento";
    document.querySelectorAll('#ga-form input[name="neg"]').forEach(function (r) { r.checked = r.value === (lista && v.negocio === "venda" ? "venda" : "locacao"); });
    $("ga-destino-lista").innerHTML = (opcoes.destinos_lista || []).map(function (d) {
      return '<option value="' + esc(d.chave) + '">' + esc(d.nome) + "</option>";
    }).join("");
    $("ga-destino-lista").value = lista && v.destino ? v.destino : "parceiros";
    document.querySelectorAll('#ga-form input[name="modo"]').forEach(function (r) { r.checked = r.value === edicao.modo; });
    $("ga-hora").value = v ? v.horario : "08:00";
    var rec = v ? v.recorrencia : "diaria";
    document.querySelectorAll('#ga-form input[name="rec"]').forEach(function (r) { r.checked = r.value === rec; });
    $("ga-dias").innerHTML = ORDEM_DIAS.map(function (d) {
      var on = v && (v.dias || []).indexOf(d) >= 0;
      return '<label class="ga-dia-chip"><input type="checkbox" value="' + d + '"' + (on ? " checked" : "") + "><span>" + DIAS[d] + "</span></label>";
    }).join("");
    $("ga-data").value = v && v.data ? v.data : somaDias(diaDe(new Date()), 1);
    $("ga-data").min = diaDe(new Date());
    $("ga-destino").innerHTML = '<option value="">Todos os grupos que aceitam o imóvel</option>' + opcoes.destinos.map(function (d) {
      return '<option value="' + esc(d.apelido) + '">' + esc(ROTULO_DESTINO[d.apelido] || d.apelido) + " — " + esc(d.grupos.map(nomeCurto).join(", ")) + "</option>";
    }).join("");
    $("ga-destino").value = v && !lista && v.destino ? v.destino : "";
    $("ga-busca").value = ""; $("ga-achados").innerHTML = ""; $("ga-erro").textContent = "";
    mostrarRepeticao(); mostrarTipo(); desenharEscolhidos(); mostrarTexto(); resumoDoEditor();
    abrirDialogo($("ga-editor"));
    var dono = edicao;
    catalogo().then(function (l) {
      if (edicao !== dono) return;
      if (!l) {
        imoveisCatalogo = imoveisCatalogo || [];
        if (edicao.tipo === "imoveis") $("ga-achados").innerHTML = '<p class="ga-erro">Não consegui carregar os imóveis.</p>';
        return;
      }
      if (edicao.tipo === "lista") { contarTexto(); resumoDoEditor(); }     // agora dá para riscar as linhas fora do ar
    });
    if (lista) trazerLista(false);
    setTimeout(function () { (lista ? $("ga-hora") : $("ga-busca")).focus(); }, 50);
  }

  function tipoAtual() { var r = document.querySelector('#ga-form input[name="tipo"]:checked'); return r ? r.value : "imoveis"; }
  function negAtual() { var r = document.querySelector('#ga-form input[name="neg"]:checked'); return r ? r.value : "locacao"; }
  function mostrarTipo() {
    var lista = edicao.tipo === "lista";
    $("ga-ed-imoveis").hidden = lista;
    $("ga-ed-destino").hidden = lista;
    $("ga-ed-lista").hidden = !lista;
    $("ga-ed-texto").hidden = !lista;
  }
  /* a caixa do texto: no automático ela só MOSTRA a lista de agora; à mão, é ali que ele escreve */
  function mostrarTexto() {
    var t = $("ga-texto"), mao = edicao.modo === "mao", valor = mao ? edicao.texto : edicao.textoAuto;
    t.readOnly = !mao;
    t.classList.toggle("ga-texto--auto", !mao);
    if (t.value !== valor) t.value = valor;
    $("ga-texto-recarregar").hidden = !mao;
    $("ga-texto-dica").textContent = mao
      ? 'Um imóvel por linha, com o código escrito "cod 1234". Os valores não se atualizam sozinhos; na hora do envio, a linha do imóvel que saiu do ar é retirada e o resto sai como está.'
      : "O publicador monta a lista na hora do envio. Para mudar o título, a ordem, uma frase ou tirar um imóvel, escolha Escrito à mão.";
    contarTexto();
  }
  function contarTexto() {
    var alvo = $("ga-texto-conta");
    if (edicao.modo !== "mao") {
      alvo.textContent = edicao.erroAuto ? edicao.erroAuto : edicao.quantosAuto == null ? "buscando a lista…"
        : edicao.quantosAuto ? plural(edicao.quantosAuto, "imóvel", "imóveis") + " hoje" : "nenhum imóvel nessa lista hoje";
      return;
    }
    var n = contaDaLista(linhasDaLista(edicao.texto, negAtual(), true));
    alvo.textContent = plural(n.saem, "imóvel", "imóveis") + (n.fora ? " · " + plural(n.fora, "linha", "linhas") + " fora do ar" : "") +
      " · " + edicao.texto.length.toLocaleString("pt-BR") + " letras";
  }
  /* busca a lista que o publicador montaria agora para a categoria e o negócio escolhidos */
  function trazerLista(deNovo) {
    var cat = $("ga-categoria").value, neg = negAtual(), dono = edicao, antes = edicao.textoAuto;
    if (!cat) return;
    edicao.quantosAuto = null; edicao.erroAuto = "";
    contarTexto();
    listaDeAgora(cat, neg, deNovo).then(function (r) {
      if (edicao !== dono || $("ga-categoria").value !== cat || negAtual() !== neg) return;
      edicao.textoAuto = r.texto || ""; edicao.quantosAuto = r.quantos || 0; edicao.erroAuto = r.erro || "";
      // escrito à mão: só troca o texto se ele ainda não mexeu nele, ou se pediu para trazer de novo
      if (edicao.modo === "mao" && (deNovo || !edicao.texto.trim() || edicao.texto === antes)) edicao.texto = edicao.textoAuto;
      mostrarTexto(); resumoDoEditor();
    });
  }
  var previaT = null;
  function previaDepois() { clearTimeout(previaT); previaT = setTimeout(function () { if (edicao) resumoDoEditor(); }, 250); }

  function recAtual() { var r = document.querySelector('#ga-form input[name="rec"]:checked'); return r ? r.value : "diaria"; }
  function mostrarRepeticao() {
    $("ga-dias").hidden = recAtual() !== "semanal";
    $("ga-data-rot").hidden = recAtual() !== "unica";
  }
  function diasMarcados() {
    return Array.prototype.map.call(document.querySelectorAll("#ga-dias input:checked"), function (c) { return Number(c.value); });
  }
  function resumoDoEditor() {
    var lista = edicao.tipo === "lista";
    var v = { horario: $("ga-hora").value || "--:--", recorrencia: recAtual(), dias: diasMarcados(), data: $("ga-data").value,
              destino: lista ? $("ga-destino-lista").value : $("ga-destino").value,
              categoria: lista ? $("ga-categoria").value : null, negocio: lista ? negAtual() : null };
    var quando = v.recorrencia === "semanal" && !v.dias.length ? "escolha os dias" : v.recorrencia === "unica" && !v.data ? "escolha o dia" : descreverRepeticao(v);
    if (lista) {
      var gsLista = gruposDaLista(v.destino, v.negocio, v.categoria);
      $("ga-resumo-ed").textContent = nomeDaLista(v) + (edicao.modo === "mao" ? ", com o texto escrito à mão, " : ", montada na hora, ") +
        quando + ", para " + nomeDoDestino(v).toLowerCase() + ".";
      $("ga-lista-dica").innerHTML = gsLista.length
        ? tachinhas(gsLista) + " Vai para " + plural(gsLista.length, "grupo", "grupos") +
          (gsLista.length <= 4 ? ": " + esc(gsLista.map(function (g) { return nomeCurto(g.nome); }).join(", ")) : "") +
          ". Grupo com valor mínimo (Alto Padrão) recebe só os imóveis que passam na regra dele."
        : "Nenhum grupo ativo recebe essa lista hoje.";
      desenharConversa($("ga-previa"), { categoria: v.categoria, negocio: v.negocio, destino: v.destino,
                                         escrita: edicao.modo === "mao", texto_fixo: edicao.texto },
        gsLista.length === 1 ? gsLista[0] : null, null, "previa", $("ga-hora").value || "");
      return;
    }
    var n = edicao.escolhidos.length;
    $("ga-resumo-ed").textContent = (n ? n + (n === 1 ? " imóvel" : " imóveis") + ", " : "Escolha os imóveis. ") +
      quando + ", para " + nomeDoDestino(v).toLowerCase() + ".";
    var d = opcoes.destinos.find(function (x) { return x.apelido === v.destino; });
    var gsDestino = d ? d.grupos.map(function (nome) { return grupoPorNome[nome]; }).filter(Boolean) : [];
    $("ga-destino-dica").innerHTML = v.destino
      ? gsDestino.map(function (g) { return tacha(g); }).join("") + " Vai para: " + esc(d ? d.grupos.map(nomeCurto).join(", ") : v.destino) +
        ". O Comercial só aceita imóvel comercial e o Alto Padrão tem valor mínimo: o publicador confere na hora."
      : "Cada imóvel vai aos grupos que aceitam o tipo e o valor dele (venda, locação, condomínio, comercial).";
    // a prévia: a conversa como vai chegar (no grupo do destino, ou com o card inteiro)
    desenharConversa($("ga-previa"), { imoveis: edicao.escolhidos }, gsDestino[0] || null, null, "previa", $("ga-hora").value || "");
  }

  function desenharEscolhidos() {
    $("ga-escolhidos").innerHTML = edicao.escolhidos.length ? edicao.escolhidos.map(function (i, k) {
      return '<span class="ga-escolhido" style="--im:' + ACENTOS[k % ACENTOS.length] + '">' + (i.foto ? '<img src="' + esc(foto(i.foto, "small")) + '" alt="">' : "") +
        "<b>" + esc(i.codigo) + "</b><small>" + esc(i.titulo || "") + "</small>" +
        '<button type="button" data-tirar="' + k + '" aria-label="Tirar o ' + esc(i.codigo) + '">×</button></span>';
    }).join("") : '<p class="ga-dica">Nenhum imóvel ainda.</p>';
  }

  function procurar(q) {
    var alvo = $("ga-achados");
    q = String(q || "").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    if (!q) { alvo.innerHTML = ""; return; }
    if (!imoveisCatalogo) { alvo.innerHTML = '<p class="ga-dica">Carregando os imóveis…</p>'; return; }
    var ja = edicao.escolhidos.map(function (i) { return i.codigo; });
    var achados = imoveisCatalogo.filter(function (m) {
      var t = (m.codigo + " " + (m.condominio || "") + " " + (m.bairro || "") + " " + (m.titulo || "")).toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
      return t.indexOf(q) >= 0 && ja.indexOf(String(m.codigo)) < 0;
    }).slice(0, 8);
    alvo.innerHTML = achados.length ? achados.map(function (m) {
      var valor = m.venda ? "venda " + curto(m.venda) : m.aluguel ? "aluguel " + reais(m.aluguel) : "";
      return '<button type="button" class="ga-achado" data-escolher="' + esc(m.codigo) + '">' +
        (m.foto ? '<img src="' + esc(foto(m.foto, "small")) + '" alt="">' : '<span class="ga-sem-foto"></span>') +
        "<span><b>" + esc(m.codigo) + " · " + esc(m.condominio || m.tipo || "") + "</b><small>" + esc([m.bairro, valor].filter(Boolean).join(" · ")) + "</small></span></button>";
    }).join("") : '<p class="ga-dica">Nada encontrado entre os imóveis que a Nay oferece (imóvel de parceiro não sai nos grupos).</p>';
  }

  function salvar(e) {
    e.preventDefault();
    var corpo = { horario: $("ga-hora").value, recorrencia: recAtual(), dias: diasMarcados(), data: $("ga-data").value };
    $("ga-erro").textContent = "";
    if (edicao.tipo === "lista") {
      if (edicao.modo === "mao" && !edicao.texto.trim()) { $("ga-erro").textContent = "Escreva o texto da lista, ou volte para o Automático."; return; }
      corpo.categoria = $("ga-categoria").value;
      corpo.negocio = negAtual();
      corpo.destino = $("ga-destino-lista").value;
      corpo.texto_fixo = edicao.modo === "mao" ? edicao.texto : "";      // vazio: a lista volta a ser montada na hora
    } else {
      corpo.destino = $("ga-destino").value;
      corpo.codigos = edicao.escolhidos.map(function (i) { return i.codigo; });
    }
    $("ga-salvar").disabled = true;
    pedir(edicao.id ? "/admin/api/grade/" + edicao.id : "/admin/api/grade", { method: edicao.id ? "PUT" : "POST", body: JSON.stringify(corpo) })
      .then(function (r) {
        if (!r.ok) { $("ga-erro").textContent = r.erro || "Não salvou."; return; }
        fecharDialogo($("ga-editor"));
        metricasVelhas();
        return carregar();
      })
      .catch(function (e2) { $("ga-erro").textContent = e2.message; })
      .then(function () { $("ga-salvar").disabled = false; });
  }

  function excluir(id) {
    var v = vagasPorId[id];
    if (!v || !window.confirm("Excluir esta mensagem?\n\n" + tituloDaVaga(v) + "\n" + descreverRepeticao(v) + "\n\nEla para de sair nos grupos. O que já saiu continua medido.")) return;
    pedir("/admin/api/grade/" + id, { method: "DELETE" })
      .then(function (r) {
        if (!r.ok) { window.alert(r.erro || "Não excluiu."); return; }
        fecharDialogo($("ga-detalhe"));
        metricasVelhas();
        return carregar();
      })
      .catch(function (e) { window.alert(e.message); });
  }

  /* ---- as métricas: quantas vezes cada mensagem saiu e quanta gente chegou por ela ---- */
  function painelDasMetricas() { return document.querySelector('[data-painel="metricas"]'); }
  function metricasVelhas() {           // mudou a grade: a conta de antes não vale mais
    metricas.dados = null;
    if (!painelDasMetricas().hidden) carregarMetricas();
  }
  function dataBr(iso) { return new Date(String(iso).slice(0, 10) + "T12:00:00").toLocaleDateString("pt-BR"); }
  function quandoCurto(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit" }) + " " + horaDe(d);
  }
  function carregarMetricas() {
    var ate = metricas.ate || diaDe(new Date());
    var de = metricas.de || somaDias(ate, -(metricas.dias - 1));
    var n = ++metricas.pedido;
    $("gm-corpo").innerHTML = '<p class="ga-carregando">Calculando as métricas…</p>';
    pedir("/admin/api/grade/metricas?de=" + de + "&ate=" + ate)
      .then(function (d) {
        if (n !== metricas.pedido) return;
        metricas.dados = d;
        desenharMetricas();
      })
      .catch(function (e) {
        if (n === metricas.pedido) $("gm-corpo").innerHTML = '<p class="ga-erro">Não consegui calcular as métricas: ' + esc(e.message) + "</p>";
      });
  }
  /* os números de uma linha: saiu, posts, marcaram, só o código e pessoas (com a barrinha) */
  function colunasDeGente(x, max) {
    var pessoas = x.pessoas || 0;
    return '<td class="num">' + (x.vezes || 0) + "</td>" +
      '<td class="num">' + (x.posts || 0) + "</td>" +
      '<td class="num">' + (x.marcaram || 0) + "</td>" +
      '<td class="num">' + (x.perguntaram || 0) + "</td>" +
      '<td class="num gm-pessoas"><b>' + pessoas + '</b><span class="gm-barra" style="--p:' + (max ? Math.round(pessoas * 100 / max) : 0) + '%"></span></td>' +
      '<td class="num">' + (x.vezes ? (pessoas / x.vezes).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) : "—") + "</td>" +
      "<td>" + esc(quandoCurto(x.ultima)) + "</td>";
  }
  function desenharMetricas() {
    var d = metricas.dados;
    if (!d) return;
    var t = d.total || {};
    $("gm-periodo").textContent = dataBr(d.de) + " a " + dataBr(d.ate);
    $("gm-de").value = d.de; $("gm-ate").value = d.ate;
    $("gm-de").max = $("gm-ate").max = diaDe(new Date());
    var msgs = (d.mensagens || []).filter(function (m) { return m.categoria || (m.imoveis || []).length; });
    var ims = d.imoveis || [];
    var maior = function (l) { return l.reduce(function (m, x) { return Math.max(m, x.pessoas || 0); }, 0); };
    var maxM = maior(msgs), maxI = maior(ims);
    var mostrados = metricas.todos ? ims : ims.slice(0, 40);
    var desde = d.listas_com_id_desde ? new Date(d.listas_com_id_desde).toLocaleDateString("pt-BR", { timeZone: FUSO }) : "";
    var cabeca = '<th class="num" title="Quantas vezes a mensagem saiu no período">Saiu</th>' +
      '<th class="num" title="Quantos posts isso deu: um por grupo que recebeu">Posts</th>' +
      '<th class="num" title="Pessoas que escreveram no privado marcando o post do grupo">Marcaram</th>' +
      '<th class="num" title="Pessoas que escreveram o código do imóvel até 6 h depois do envio, sem marcar o post">Só o código</th>' +
      '<th class="num" title="Marcaram + só o código: cada pessoa conta uma vez">Pessoas</th>' +
      '<th class="num" title="Pessoas por vez que saiu">Por envio</th><th>Última vez</th>';
    $("gm-corpo").innerHTML =
      '<div class="ga-resumo">' +
        '<div class="ga-cartao-num"><b>' + (t.disparos || 0) + "</b><span>vezes que alguma mensagem saiu</span></div>" +
        '<div class="ga-cartao-num"><b>' + (t.posts || 0) + "</b><span>posts nos grupos</span></div>" +
        '<div class="ga-cartao-num"><b>' + (t.marcaram || 0) + "</b><span>pessoas marcaram um post</span></div>" +
        '<div class="ga-cartao-num"><b>' + Math.max(0, (t.pessoas || 0) - (t.marcaram || 0)) + "</b><span>só escreveram o código</span></div>" +
        '<div class="ga-cartao-num ga-cartao-num--destaque"><b>' + (t.pessoas || 0) + "</b><span>pessoas chegaram pelas mensagens (estimativa)</span></div>" +
      "</div>" +
      '<p class="ga-dica">É uma <b>estimativa</b> de quem chegou no privado da Nay por causa de cada mensagem. <b>Marcaram</b>: escreveram marcando o post do grupo. ' +
        "<b>Só o código</b>: escreveram o código do imóvel até 6 h depois do envio, sem marcar. Cada pessoa conta uma vez por mensagem; a equipe e os números de teste ficam de fora. " +
        "Quem viu no grupo e chamou sem marcar nem citar o código não entra: o número é um piso, não o total." +
        (desde ? " Nas <b>listas</b>, a conta só existe desde " + esc(desde) + ": antes disso o publicador não guardava o id nem os imóveis de cada lista enviada."
               : " Nas <b>listas</b>, a conta começa na próxima lista que sair: até 03/10 o publicador não guardava o id nem os imóveis de cada lista enviada.") + "</p>" +
      '<section class="ga-mensagens" aria-labelledby="gm-tit-msgs"><h2 id="gm-tit-msgs">Por mensagem da grade</h2>' +
      '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela ga-tabela gm-tabela"><thead><tr><th>Mensagem</th><th>Quando</th><th>Destino</th>' + cabeca +
        '<th class="col-acoes"></th></tr></thead><tbody>' +
        (msgs.length ? msgs.map(function (m) {
          var oQue = m.categoria ? listaMini(m) : (m.imoveis || []).map(function (i) {
            return '<span class="ga-im"><b>' + esc(i.codigo) + "</b>" + (i.titulo ? "<small>" + esc(i.titulo) + "</small>" : "") + "</span>";
          }).join("");
          return '<tr class="' + (m.vezes ? "" : "gm-parada") + '"><td class="ga-tab-imoveis">' + oQue + "</td>" +
            "<td>" + esc(descreverRepeticao(m)) + "</td><td>" + esc(nomeDoDestino(m)) + "</td>" + colunasDeGente(m, maxM) +
            '<td class="col-acoes">' + (vagasPorId[m.vaga] ? '<button type="button" class="btn-mini" data-editar="' + m.vaga + '">Editar</button>' : "") + "</td></tr>";
        }).join("") : '<tr><td colspan="11" class="ga-dica">Nenhuma mensagem na grade.</td></tr>') +
      "</tbody></table></div></div>" +
      '<p class="ga-dica">Mensagem excluída da grade sai desta tabela; o que ela já enviou continua contado por imóvel, abaixo.</p></section>' +
      '<section class="ga-mensagens" aria-labelledby="gm-tit-ims"><h2 id="gm-tit-ims">Por imóvel</h2>' +
      '<p class="ga-dica">Todo post de imóvel nos grupos no período, da grade ou mandado na mão pelo WhatsApp. Imóvel que só saiu dentro de lista não aparece aqui.</p>' +
      '<div class="tabela-envolucro"><div class="tabela-rolagem"><table class="tabela ga-tabela gm-tabela"><thead><tr><th>Imóvel</th>' + cabeca + "</tr></thead><tbody>" +
        (mostrados.length ? mostrados.map(function (i) {
          return '<tr><td><span class="ga-im"><b>' + esc(i.codigo) + "</b><small>" + esc([i.titulo, i.bairro].filter(Boolean).join(" · ")) + "</small></span></td>" +
            colunasDeGente(i, maxI) + "</tr>";
        }).join("") : '<tr><td colspan="8" class="ga-dica">Nenhum imóvel saiu nos grupos nesse período.</td></tr>') +
      "</tbody></table></div></div>" +
      (ims.length > mostrados.length ? '<p><button type="button" class="btn-mini" id="gm-todos">Ver os ' + ims.length + " imóveis</button></p>" : "") +
      "</section>";
  }
  function trocarPeriodo(dias, de, ate) {
    metricas.dias = dias || metricas.dias; metricas.de = de || ""; metricas.ate = ate || ""; metricas.todos = false;
    document.querySelectorAll("#gm-periodos [data-dias]").forEach(function (b) {
      b.setAttribute("aria-pressed", String(!de && !ate && Number(b.dataset.dias) === metricas.dias));
    });
    carregarMetricas();
  }

  /* ---- janelas ---- */
  function abrirDialogo(d) { if (d.showModal) { if (!d.open) d.showModal(); } else d.setAttribute("open", ""); }
  function fecharDialogo(d) { if (d.close) d.close(); else d.removeAttribute("open"); }

  /* ---- eventos ---- */
  document.addEventListener("click", function (e) {
    var t = e.target.closest ? e.target.closest("button, [data-fechar]") : null;
    if (!t) { if (e.target.tagName === "DIALOG") fecharDialogo(e.target); return; }
    if (t.hasAttribute("data-fechar")) { fecharDialogo(t.closest("dialog")); return; }
    if (t.hasAttribute("data-grupo") && $("ga-legenda").contains(t)) { grupoFiltro = t.dataset.grupo; if (dados) desenhar(); return; }
    if (t.dataset.verGrupo) { verNoGrupo(t.dataset.verGrupo); return; }
    if (t.dataset.ocorrencia) { abrirDetalhe(t.dataset.ocorrencia); return; }
    if (t.dataset.editar) { fecharDialogo($("ga-detalhe")); abrirEditor(vagasPorId[t.dataset.editar]); return; }
    if (t.dataset.excluir) { excluir(t.dataset.excluir); return; }
    if (t.dataset.escolher) {
      if (edicao.escolhidos.length >= 10) { $("ga-erro").textContent = "No máximo 10 imóveis por mensagem."; return; }
      var m = (imoveisCatalogo || []).find(function (x) { return String(x.codigo) === t.dataset.escolher; });
      if (m) edicao.escolhidos.push({ codigo: String(m.codigo), titulo: m.condominio || m.tipo, foto: m.foto, bairro: m.bairro, venda: m.venda, aluguel: m.aluguel });
      $("ga-busca").value = ""; $("ga-achados").innerHTML = ""; $("ga-busca").focus();
      desenharEscolhidos(); resumoDoEditor(); return;
    }
    if (t.dataset.tirar != null) { edicao.escolhidos.splice(Number(t.dataset.tirar), 1); desenharEscolhidos(); resumoDoEditor(); return; }
    if (t.id === "ga-texto-recarregar") {
      if (edicao.texto.trim() && edicao.texto !== edicao.textoAuto &&
          !window.confirm("Trocar o texto pela lista de agora?\n\nO que está escrito aqui é substituído.")) return;
      trazerLista(true); return;
    }
    // as abas: o admin.js troca o painel; aqui só se calcula a métrica na primeira vez que a aba abre
    if (t.dataset.painelAbre) {
      if (t.dataset.painelAbre === "metricas" && !metricas.dados) carregarMetricas();
      try { history.replaceState(null, "", t.dataset.painelAbre === "metricas" ? "#metricas" : location.pathname + location.search); } catch (_) { /* sem histórico */ }
      return;
    }
    if (t.dataset.dias) { trocarPeriodo(Number(t.dataset.dias)); return; }
    if (t.id === "gm-todos") { metricas.todos = true; desenharMetricas(); return; }
    if (t.id === "ga-nova") abrirEditor(null);
    if (t.id === "ga-ant") { semana = somaDias(semana, -7); carregar(); }
    if (t.id === "ga-prox") { semana = somaDias(semana, 7); carregar(); }
    if (t.id === "ga-hoje") { semana = segundaDe(diaDe(new Date())); carregar(); }
  });
  $("ga-busca").addEventListener("input", function () { procurar(this.value); });
  $("ga-busca").addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); var b = $("ga-achados").querySelector("[data-escolher]"); if (b) b.click(); }
  });
  $("ga-form").addEventListener("change", function (e) {
    var nome = e.target.name, id = e.target.id;
    if (nome === "rec") mostrarRepeticao();
    if (nome === "tipo") {
      edicao.tipo = tipoAtual();
      mostrarTipo();
      if (edicao.tipo === "lista") trazerLista(false);
    }
    if (nome === "neg" || id === "ga-categoria") trazerLista(false);
    if (nome === "modo") {
      edicao.modo = e.target.value === "mao" ? "mao" : "auto";
      if (edicao.modo === "mao" && !edicao.texto.trim()) edicao.texto = edicao.textoAuto;     // começa pela lista de agora
      mostrarTexto();
      if (edicao.modo === "mao") $("ga-texto").focus();
    }
    if (id !== "ga-busca" && id !== "ga-texto") resumoDoEditor();
  });
  $("ga-hora").addEventListener("input", resumoDoEditor);
  $("ga-texto").addEventListener("input", function () {
    if (!edicao || edicao.modo !== "mao") return;
    edicao.texto = this.value;
    contarTexto();
    previaDepois();
  });
  $("ga-form").addEventListener("submit", salvar);
  ["gm-de", "gm-ate"].forEach(function (id) {
    $(id).addEventListener("change", function () {
      var de = $("gm-de").value, ate = $("gm-ate").value;
      if (!de || !ate) return;
      if (de > ate) { if (id === "gm-de") ate = de; else de = ate; }
      trocarPeriodo(null, de, ate);
    });
  });

  /* ---- começar ---- */
  pedir("/admin/api/grade/opcoes")
    .then(function (o) {
      opcoes = { grupos: prepararGrupos(o.grupos || []), destinos: o.destinos || [],
                 categorias: o.categorias || [], destinos_lista: o.destinos_lista || [] };
    })
    .catch(function () { /* sem as opções, a agenda ainda aparece (sem as cores) */ })
    .then(carregar)
    .then(function () {
      // o link direto para as métricas (#metricas) abre a aba; o admin.js troca o painel no clique
      var aba = document.querySelector('[data-painel-abre="metricas"]');
      if (location.hash === "#metricas" && aba) aba.click();
    });
})();
