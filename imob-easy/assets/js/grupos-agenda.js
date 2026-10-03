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

  /* ---- estado ---- */
  var semana = segundaDe(diaDe(new Date()));
  var opcoes = { grupos: [], destinos: [] };
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
  /* a faixa da esquerda do cartão: uma cor só, ou as cores de todos os grupos, uma embaixo da outra */
  function faixa(gs) {
    if (!gs.length) return "transparent";
    if (gs.length === 1) return cor(gs[0]);
    return "linear-gradient(" + gs.map(function (g, k) {
      return cor(g) + " " + (k * 100 / gs.length).toFixed(2) + "% " + ((k + 1) * 100 / gs.length).toFixed(2) + "%";
    }).join(", ") + ")";
  }

  function nomeDoDestino(v) {
    if (v.categoria) return "Lista de " + v.categoria.replace(/_/g, " ") + " (" + (v.negocio === "venda" ? "venda" : "locação") + ")";
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
    if (v.categoria) return nomeDoDestino(v);
    var ims = v.imoveis || [];
    if (!ims.length) return "Horário livre (sem imóvel)";
    return ims.map(function (i) { return i.codigo + (i.titulo ? " · " + i.titulo : ""); }).join(" + ");
  }
  function tituloCurto(v) {
    if (v.categoria) return "Lista " + v.categoria.replace(/_/g, " ") + " · " + (v.negocio === "venda" ? "venda" : "locação");
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
        '<td><span class="ga-tab-tachas">' + previstos.map(function (g) { return tacha(g); }).join("") + "</span>" + esc(nomeDoDestino(v)) + "</td>" +
        '<td class="num">' + os.length + "</td>" +
        '<td class="num">' + s("pessoas") + "</td>" +
        '<td class="num">' + s("novos") + "</td>" +
        '<td class="num"><b>' + s("pelo_imovel") + "</b></td>" +
        '<td class="col-acoes"><button type="button" class="btn-mini" data-editar="' + v.id + '">Editar</button> ' +
          '<button type="button" class="btn-mini btn-mini--perigo" data-excluir="' + v.id + '">Excluir</button></td></tr>';
    }).join("") : '<tr><td colspan="8" class="ga-dica">Nenhuma mensagem para esse grupo.</td></tr>';
  }

  function imoveisMini(v) {
    if (v.categoria) return '<span class="ga-dica">' + esc(nomeDoDestino(v)) + "</span>";
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
      '<span class="ga-cartao__tachas' + (gs.length > 10 ? " ga-cartao__tachas--muitas" : "") + '">' + gs.map(function (g) { return tacha(g, estado === "falhou"); }).join("") + num + "</span>" +
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
  /* alvo: onde desenhar; v: a vaga (ou a edição); g: o grupo visto (ou nada); quando: Date ou nada */
  function desenharConversa(alvo, v, g, quando, estado, hora) {
    var ims = v.imoveis || [];
    var cabeca = '<div class="ga-zap__topo" style="--g:' + (g ? cor(g) : "#8696a0") + '">' +
      '<span class="ga-zap__avatar">' + (g ? esc(iniciais(g.nome)) : "G") + "</span>" +
      "<div><b>" + esc(g ? nomeCurto(g.nome) : "Grupos que aceitam o imóvel") + "</b><small>" +
      (g ? (g.todas_fotos ? "grupo de anunciar: vão todas as fotos" : "Imob Easy · número da Parceria") : "cada um recebe só os valores que aceita") +
      "</small></div></div>";
    var dia = quando ? quando.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" })
      : estado === "previa" ? "como vai chegar" : "";
    var corpo;
    if (v.categoria) corpo = '<div class="ga-zap__nota">' + esc(nomeDoDestino(v)) + ": a lista é montada pelo publicador na hora do envio, com os imóveis daquele momento.</div>";
    else if (!ims.length) corpo = '<div class="ga-zap__nota">' + (estado === "previa" ? "Escolha os imóveis: cada um vira um texto e uma foto aqui." : "Horário livre: sem imóvel, nada sai.") + "</div>";
    else corpo = '<p class="ga-zap__carregando">Montando a conversa…</p>';
    alvo.innerHTML = '<div class="ga-zap">' + cabeca + '<div class="ga-zap__corpo">' + (dia ? '<div class="ga-zap__dia">' + esc(dia) + "</div>" : "") + corpo + "</div></div>";
    if (v.categoria || !ims.length) return;
    var marca = {};
    alvo.__marca = marca;          // se a conversa for redesenhada antes de chegar, esta resposta não vale mais
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
      falhou: '<p class="ga-situacao ga-situacao--falhou">Não saiu. O publicador recusa imóvel fora do ar, de parceiro ou abaixo da faixa do grupo, e avisa o motivo ao Tel no WhatsApp.</p>',
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
              (saiu(o) ? "" : '<p class="ga-dica">Sem destino, cada imóvel vai só aos grupos que aceitam o tipo e o valor dele: a lista exata sai na hora do envio.</p>')
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
    edicao = { id: v ? v.id : null, lista: !!(v && v.categoria), categoria: v && v.categoria, negocio: v && v.negocio,
      escolhidos: v && !v.categoria ? (v.imoveis || []).map(function (i) {
        return { codigo: String(i.codigo), titulo: i.titulo, foto: i.foto, bairro: i.bairro, venda: i.venda, aluguel: i.aluguel };
      }) : [] };
    $("ga-ed-tit").textContent = v ? "Editar mensagem" : "Nova mensagem";
    $("ga-ed-imoveis").hidden = edicao.lista;
    $("ga-ed-destino").hidden = edicao.lista;
    $("ga-ed-lista").hidden = !edicao.lista;
    $("ga-ed-lista").textContent = edicao.lista ? nomeDoDestino(v) + ": a lista é montada pelo publicador na hora; aqui só muda o quando." : "";
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
    $("ga-destino").value = v && v.destino ? v.destino : "";
    $("ga-busca").value = ""; $("ga-achados").innerHTML = ""; $("ga-erro").textContent = "";
    mostrarRepeticao(); desenharEscolhidos(); resumoDoEditor();
    abrirDialogo($("ga-editor"));
    if (!edicao.lista && !imoveisCatalogo) {
      fetch(API + "/api/imoveis-para-enviar").then(function (r) { return r.json(); })
        .then(function (d) { imoveisCatalogo = d.imoveis || []; })
        .catch(function () { imoveisCatalogo = []; $("ga-achados").innerHTML = '<p class="ga-erro">Não consegui carregar os imóveis.</p>'; });
    }
    setTimeout(function () { (edicao.lista ? $("ga-hora") : $("ga-busca")).focus(); }, 50);
  }

  function recAtual() { var r = document.querySelector('#ga-form input[name="rec"]:checked'); return r ? r.value : "diaria"; }
  function mostrarRepeticao() {
    $("ga-dias").hidden = recAtual() !== "semanal";
    $("ga-data-rot").hidden = recAtual() !== "unica";
  }
  function diasMarcados() {
    return Array.prototype.map.call(document.querySelectorAll("#ga-dias input:checked"), function (c) { return Number(c.value); });
  }
  function resumoDoEditor() {
    var v = { horario: $("ga-hora").value || "--:--", recorrencia: recAtual(), dias: diasMarcados(), data: $("ga-data").value,
              destino: $("ga-destino").value, categoria: null };
    var n = edicao.escolhidos.length;
    $("ga-resumo-ed").textContent = (edicao.lista ? "Vai sair " : (n ? n + (n === 1 ? " imóvel" : " imóveis") + ", " : "Escolha os imóveis. ")) +
      (v.recorrencia === "semanal" && !v.dias.length ? "escolha os dias" : v.recorrencia === "unica" && !v.data ? "escolha o dia" : descreverRepeticao(v)) +
      (edicao.lista ? "." : ", para " + nomeDoDestino(v).toLowerCase() + ".");
    var d = opcoes.destinos.find(function (x) { return x.apelido === v.destino; });
    var gsDestino = d ? d.grupos.map(function (nome) { return grupoPorNome[nome]; }).filter(Boolean) : [];
    $("ga-destino-dica").innerHTML = v.destino
      ? gsDestino.map(function (g) { return tacha(g); }).join("") + " Vai para: " + esc(d ? d.grupos.map(nomeCurto).join(", ") : v.destino) +
        ". O Comercial só aceita imóvel comercial e o Alto Padrão tem valor mínimo: o publicador confere na hora."
      : "Cada imóvel vai aos grupos que aceitam o tipo e o valor dele (venda, locação, condomínio, comercial).";
    // a prévia: a conversa como vai chegar (no grupo do destino, ou com o card inteiro)
    var previa = edicao.lista ? { categoria: edicao.categoria, negocio: edicao.negocio } : { imoveis: edicao.escolhidos };
    desenharConversa($("ga-previa"), previa, gsDestino[0] || null, null, "previa", $("ga-hora").value || "");
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
    var corpo = { horario: $("ga-hora").value, recorrencia: recAtual(), dias: diasMarcados(), data: $("ga-data").value,
                  destino: $("ga-destino").value, codigos: edicao.escolhidos.map(function (i) { return i.codigo; }) };
    $("ga-erro").textContent = "";
    $("ga-salvar").disabled = true;
    pedir(edicao.id ? "/admin/api/grade/" + edicao.id : "/admin/api/grade", { method: edicao.id ? "PUT" : "POST", body: JSON.stringify(corpo) })
      .then(function (r) {
        if (!r.ok) { $("ga-erro").textContent = r.erro || "Não salvou."; return; }
        fecharDialogo($("ga-editor"));
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
        return carregar();
      })
      .catch(function (e) { window.alert(e.message); });
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
    if (e.target.name === "rec") mostrarRepeticao();
    if (e.target.id !== "ga-busca") resumoDoEditor();
  });
  $("ga-hora").addEventListener("input", resumoDoEditor);
  $("ga-form").addEventListener("submit", salvar);

  /* ---- começar ---- */
  pedir("/admin/api/grade/opcoes")
    .then(function (o) {
      opcoes = { grupos: prepararGrupos(o.grupos || []), destinos: o.destinos || [] };
    })
    .catch(function () { /* sem as opções, a agenda ainda aparece (sem as cores) */ })
    .then(carregar);
})();
