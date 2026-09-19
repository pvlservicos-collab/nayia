/* ==========================================================================
   Imob Easy — Cérebro da Nay (admin)

   Tel (19/09/2026):
     "quero um painel de logs para eu ver que caminho a ia percorreu em cada
      execução para ficar fácil olhar os erros"
     "queria um fluxograma horizontal, tipo a ia percorrendo um caminho"
     "não quero tirar as regras que já tinha ensinado para ela, o problema dela
      hoje é ignorar essas regras"

   Duas decisões que vêm direto daí:

   1. A tela ABRE EM REGRAS. A pergunta do Tel não é "o que o sistema fez", é
      "ela obedeceu?". As 17 conferências sempre foram o registro disso --
      `mudou`/`cortou`/`parou` é ela ignorando e o sistema consertando antes de
      a mensagem sair. Nunca tinham sido lidas assim.

   2. A execução é um CAMINHO DA ESQUERDA PARA A DIREITA: a mensagem dele entra
      numa ponta, a resposta sai na outra, e no meio estão os setores. Quando um
      setor PARA, a seta seguinte fica tracejada e o resto do caminho apaga --
      porque foi isso que aconteceu de verdade.

   Só leitura. O que muda comportamento (prompt, regras, pausa) continua na
   página "Nay Locação", num lugar só.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";

  var estado = {
    filtro: "problema",
    turno: null,
    setor: null,
    no: null,             // qual nó do fluxo está aberto
    execucoes: [],
    resumo: [],
    trilha: null,         // a execução aberta
    regras: {},           // etapa -> a regra, para mostrar dentro do passo
    carregando: false
  };

  /* ------------------------------------------------------------ utilidades */
  function esc(t) {
    return String(t == null ? "" : t)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function el(id) { return document.getElementById(id); }

  function buscar(rota) {
    return fetch(API + rota, { headers: { "Accept": "application/json" } })
      .then(function (r) {
        if (!r.ok) throw new Error("a API respondeu " + r.status + " em " + rota);
        return r.json();
      });
  }

  function quando(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    if (isNaN(d)) return String(iso);
    return d.toLocaleString("pt-BR", {
      timeZone: "America/Manaus",
      day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit"
    });
  }

  function dur(ms) {
    if (ms == null) return "";
    return ms < 1000 ? ms + " ms" : (ms / 1000).toFixed(1) + " s";
  }

  function selo(v, rotulo) {
    return '<span class="selo selo--' + esc(v) + '">' + esc(rotulo || v) + "</span>";
  }

  var TETO_JSON = 14000;
  function json(v) {
    if (v == null) return null;
    var t;
    try { t = JSON.stringify(v, null, 1); } catch (e) { t = String(v); }
    if (t.length > TETO_JSON) {
      t = t.slice(0, TETO_JSON) + "\n… (cortado aqui na tela; o inteiro está em nai_evento)";
    }
    return t;
  }

  function tabela(alvo, colunas, linhas, celula, vazio) {
    if (!alvo) return;
    var cab = "<thead><tr>" + colunas.map(function (c) {
      var n = typeof c === "object" ? c : { t: c };
      return '<th' + (n.num ? ' class="num"' : "") + ">" + esc(n.t) + "</th>";
    }).join("") + "</tr></thead>";
    var corpo = "<tbody>" + (linhas && linhas.length
      ? linhas.map(function (l, i) { return "<tr>" + celula(l, i) + "</tr>"; }).join("")
      : '<tr><td colspan="' + colunas.length + '" class="fraco">' +
        esc(vazio || "Nada por aqui ainda.") + "</td></tr>") + "</tbody>";
    alvo.innerHTML = cab + corpo;
  }

  function erroNaTela(alvo, e) {
    if (!alvo) return;
    alvo.innerHTML = '<div class="aviso-caixa"><b>Não consegui carregar.</b> ' +
      esc(e && e.message ? e.message : e) +
      "<br>Se persistir, veja se a rota /api/nai/trace/ existe na API " +
      "(o blueprint trace_api.py precisa estar registrado no app.py).</div>";
  }

  /* ======================================================== DIAGNÓSTICO ==== */
  function desenharDiagnostico(d) {
    var alvo = el("cb-diagnostico");
    if (!alvo) return;
    if (!d || d.diagnostico === "ok") {
      alvo.innerHTML = '<p class="painel-nota">' +
        "Trace <b>" + esc(d && d.trace_nivel) + "</b> · <b>" +
        esc((d && d.eventos) || 0) + "</b> etapas guardadas (" + esc(d && d.tamanho_trace) +
        ") · retenção de <b>" + esc(d && d.trace_dias) + "</b> dias · última em <b>" +
        quando(d && d.ultimo_evento) + "</b>.</p>";
      return;
    }
    alvo.innerHTML = '<div class="aviso-caixa"><b>Atenção:</b> ' + esc(d.diagnostico) +
      '<br><span class="fraco">turnos nas últimas 24h: ' + esc(d.turnos_24h || 0) +
      " · com id de execução: " + esc(d.turnos_24h_com_exec || 0) +
      " · etapas guardadas: " + esc(d.eventos || 0) + "</span></div>";
  }

  /* ============================================================= REGRAS ====
     A aba que responde "ela ignora as regras que eu ensinei". */
  function desenharRegras(d) {
    var alvo = el("cb-regras");
    var topo = el("cb-obediencia");
    if (!alvo) return;

    if (d && d.instalado === false) {
      alvo.innerHTML = '<div class="aviso-caixa"><b>Falta um passo.</b> ' +
        esc(d.erro) + " — aplique o arquivo e recarregue. As outras abas " +
        "funcionam normalmente sem ele.</div>";
      if (topo) topo.innerHTML = "";
      return;
    }

    var regras = (d && d.regras) || [];
    // guarda para mostrar a regra dentro de cada passo da conferência
    estado.regras = {};
    regras.forEach(function (r) { estado.regras[r.etapa] = r; });

    /* Os números do topo: só PAREDE entra na conta de obediência. Misturar
       markdown e emoji com "não prometa foto que não existe" produz um número
       que sobe quando nada importante melhorou. */
    var obed = (d && d.obediencia) || [];
    var sete = obed.slice(0, 7).reduce(function (a, o) {
      a.ex += Number(o.paredes_exercidas || 0);
      a.se += Number(o.paredes_seguidas || 0);
      a.ig += Number(o.paredes_ignoradas || 0);
      a.aj += Number(o.ajustes_de_forma || 0);
      return a;
    }, { ex: 0, se: 0, ig: 0, aj: 0 });
    var pct = sete.ex ? Math.round(1000 * sete.se / sete.ex) / 10 : null;

    if (topo) {
      topo.innerHTML =
        cartao(pct == null ? "—" : pct + "%", "das regras de parede ela seguiu sozinha", "últimos 7 dias") +
        cartao(sete.ig, "vezes que ignorou uma parede", "e o sistema corrigiu") +
        cartao(regras.filter(function (r) { return r.veredito === "IGNORA MUITO"; }).length,
               "regras que ela ignora muito", "5% ou mais das vezes") +
        cartao(sete.aj, "ajustes de forma", "markdown, emoji — não é parede");
    }

    if (!regras.length) {
      alvo.innerHTML = '<p class="fraco">Sem dado ainda. As regras aparecem aqui ' +
        "depois da primeira conversa registrada.</p>";
      return;
    }

    alvo.innerHTML = regras.map(function (r) {
      var cls = (r.tipo === "fluxo") ? "semdado"
              : r.veredito === "IGNORA MUITO" ? "ignora"
              : r.veredito === "ignora às vezes" ? "asvezes"
              : r.veredito === "sempre seguiu" ? "seguiu" : "semdado";
      var pctIg = Number(r.pct_ignorou || 0);
      var turnos = r.ultimos_turnos || [];

      /* `fluxo` não é desobediência dela: é o sistema escolhendo caminho.
         O verbo muda, senão a tela acusa a Nay de algo que ela não fez. */
      var ehRegra = r.tipo === "parede" || r.tipo === "ajuste";
      var verbo = ehRegra ? "ignorou" : "agiu";

      return '<div class="regra regra--' + cls + '">' +
        '<div class="regra__topo">' +
          selo(r.tipo) +
          '<span class="regra__n">' + esc(r.titulo) + "</span>" +
          '<span class="regra__c">' +
            (Number(r.passagens || 0)
              ? verbo + " <b>" + esc(r.ignorou) + "</b> de " + esc(r.passagens)
              : '<span class="fraco">sem dado</span>') +
          "</span>" +
        "</div>" +
        '<p class="regra__t">' + esc(r.regra) + "</p>" +
        (Number(r.passagens || 0)
          ? '<div class="regra__barra" title="' + esc(pctIg) + '% ' + verbo + '">' +
              '<i style="width:' + Math.min(100, pctIg) + '%"></i></div>'
          : "") +
        '<div class="regra__f">' +
          "<b>" + (ehRegra ? "Quando ela ignora:" : "O que o sistema faz:") + "</b> " +
          esc(r.o_que_faz) +
          (r.nasceu ? '<br><span class="fraco">nasceu de: ' + esc(r.nasceu) + "</span>" : "") +
          (r.nunca_exercida
            ? '<br><b>Nunca precisou agir nestes 30 dias.</b> Isso é uma parede ' +
              "não testada, não uma regra morta — tirar não a tornaria mais segura."
            : "") +
        "</div>" +
        (turnos.length
          ? '<div class="regra__turnos"><span class="fraco">últimas vezes que ela ignorou: </span>' +
            turnos.map(function (t) {
              return '<a href="#" data-ir-turno="' + esc(t) + '">#' + esc(t) + "</a>";
            }).join("") + "</div>"
          : "") +
      "</div>";
    }).join("");

    ligarLinksDeTurno(alvo);
  }

  function cartao(valor, rotulo, nota) {
    return '<div class="painel-cartao">' +
      '<div class="painel-cartao__n">' + esc(valor) + "</div>" +
      '<div class="painel-cartao__r">' + esc(rotulo) + (nota ? " · " + esc(nota) : "") + "</div>" +
    "</div>";
  }

  function ligarLinksDeTurno(raiz) {
    Array.prototype.forEach.call(raiz.querySelectorAll("[data-ir-turno]"), function (a) {
      a.addEventListener("click", function (ev) {
        ev.preventDefault();
        irParaExecucao(Number(a.getAttribute("data-ir-turno")));
      });
    });
  }

  /* ========================================================= EXECUÇÕES ==== */
  var FILTROS = [
    { k: "problema", r: "só problema" },
    { k: "todos",    r: "todas" },
    { k: "erro",     r: "erro" },
    { k: "muda",     r: "muda" },
    { k: "barrada",  r: "barrada" },
    { k: "parada",   r: "parada" },
    { k: "corrigida", r: "corrigida" },
    { k: "ok",       r: "ok" }
  ];

  function desenharFiltros() {
    var alvo = el("cb-filtros");
    if (!alvo) return;
    var conta = {};
    (estado.resumo || []).forEach(function (r) { conta[r.veredito] = r.quantas; });
    var problema = Object.keys(conta).reduce(function (a, k) {
      return a + (k === "ok" ? 0 : Number(conta[k] || 0));
    }, 0);

    alvo.innerHTML = FILTROS.map(function (f) {
      var n = f.k === "problema" ? problema : f.k === "todos" ? null : conta[f.k];
      return '<button class="filtro" type="button" data-filtro="' + esc(f.k) + '"' +
             ' aria-pressed="' + (estado.filtro === f.k ? "true" : "false") + '">' +
             esc(f.r) + (n != null ? ' <span class="filtro__c">' + esc(n) + "</span>" : "") +
             "</button>";
    }).join("") + '<span class="fraco" style="align-self:center;font-size:var(--fs-xs);margin-left:6px">' +
      "contagem dos últimos 7 dias</span>";

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-filtro]"), function (b) {
      b.addEventListener("click", function () {
        estado.filtro = b.getAttribute("data-filtro");
        carregarExecucoes();
      });
    });
  }

  function rotaExecucoes() {
    if (estado.filtro === "problema") return "/api/nai/trace/execucoes?so_problema=1&limite=80";
    if (estado.filtro === "todos") return "/api/nai/trace/execucoes?limite=80";
    return "/api/nai/trace/execucoes?veredito=" + encodeURIComponent(estado.filtro) + "&limite=80";
  }

  function carregarExecucoes() {
    if (estado.carregando) return Promise.resolve();
    estado.carregando = true;
    var lista = el("cb-lista");
    if (lista) lista.innerHTML = '<p class="fraco" style="padding:14px">Carregando…</p>';

    return buscar(rotaExecucoes()).then(function (d) {
      estado.execucoes = d.execucoes || [];
      estado.resumo = d.resumo_7_dias || [];
      desenharFiltros();
      desenharLista();
    }).catch(function (e) {
      erroNaTela(lista, e);
    }).then(function () { estado.carregando = false; });
  }

  function desenharLista() {
    var alvo = el("cb-lista");
    if (!alvo) return;
    if (!estado.execucoes.length) {
      alvo.innerHTML = '<p class="fraco" style="padding:16px">Nenhuma conversa com esse filtro.</p>';
      return;
    }
    alvo.innerHTML = estado.execucoes.map(function (e) {
      var nota = [];
      if (e.conf_agiram) nota.push("a esteira agiu em: " + e.conf_agiram);
      if (e.motivos_barrada) nota.push("barrada: " + e.motivos_barrada);
      if (e.setores_com_problema) nota.push("setor: " + e.setores_com_problema);
      if (e.imovel) nota.push("imóvel " + e.imovel);
      return '<button class="exec" type="button" data-turno="' + esc(e.turno) + '"' +
             ' aria-current="' + (estado.turno === e.turno ? "true" : "false") + '">' +
        '<span class="exec__topo">' + selo(e.veredito) +
          '<span class="exec__q">' + quando(e.quando) + " · " + esc(e.papel) + "</span>" +
          '<span class="exec__id">#' + esc(e.turno) + "</span>" +
        "</span>" +
        '<span class="exec__t">' + (e.ele_disse ? esc(e.ele_disse) : '<span class="fraco">(sem texto)</span>') + "</span>" +
        (nota.length ? '<span class="exec__nota">' + esc(nota.join(" · ")) + "</span>" : "") +
      "</button>";
    }).join("");

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-turno]"), function (b) {
      b.addEventListener("click", function () { abrirExecucao(Number(b.getAttribute("data-turno"))); });
    });
  }

  /* =============================================== O CAMINHO (horizontal) == */
  function abrirExecucao(turno) {
    estado.turno = turno;
    estado.no = null;
    Array.prototype.forEach.call(document.querySelectorAll("[data-turno]"), function (b) {
      b.setAttribute("aria-current", Number(b.getAttribute("data-turno")) === turno ? "true" : "false");
    });
    var alvo = el("cb-trilha");
    if (alvo) alvo.innerHTML = '<p class="trilha__vazia">Carregando o caminho…</p>';

    buscar("/api/nai/trace/execucao/" + turno).then(function (d) {
      estado.trilha = d;
      desenharCaminho();
    }).catch(function (e) { erroNaTela(alvo, e); });
  }

  /* O resumo de um nó: uma linha que diz o que aconteceu naquele setor. */
  function resumoDoNo(s) {
    var passos = s.passos || [];
    var ruins = passos.filter(function (p) { return p.resultado !== "ok"; });

    if (s.setor === "conferencia") {
      /* Conta como "ignorada" só o que é parede ou ajuste. Etapa de `fluxo`
         que agiu é o sistema escolhendo caminho, não ela desobedecendo. */
      var ignoradas = ruins.filter(function (p) {
        var r = estado.regras[p.etapa];
        return !r || r.tipo === "parede" || r.tipo === "ajuste";
      }).length;
      if (ignoradas) return ignoradas + (ignoradas > 1 ? " regras ignoradas" : " regra ignorada");
      return passos.length ? "seguiu as " + passos.length : "—";
    }
    if (s.setor === "ferramenta") {
      return passos.length + (passos.length > 1 ? " ferramentas" : " ferramenta");
    }
    if (s.setor === "saida") {
      var barradas = passos.filter(function (p) { return p.resultado === "parou"; }).length;
      if (barradas) return barradas + " barrada" + (barradas > 1 ? "s" : "");
      return passos.length + " mensage" + (passos.length > 1 ? "ns" : "m");
    }
    if (ruins.length) return ruins[0].detalhe || ruins[0].resultado;
    return passos.length ? (passos[0].detalhe || passos.length + " etapa") : "—";
  }

  function classeDoNo(s) {
    var passos = s.passos || [];
    if (passos.some(function (p) { return p.resultado === "erro" || p.resultado === "parou"; })) return "problema";
    if (passos.some(function (p) { return p.resultado === "mudou" || p.resultado === "cortou"; })) return "mexeu";
    return "ok";
  }

  function desenharCaminho() {
    var alvo = el("cb-trilha");
    var d = estado.trilha;
    if (!alvo || !d) return;
    var c = d.cabecalho || {};
    var setores = d.setores || [];

    /* ---- cabeçalho da execução ---- */
    var meta = [];
    meta.push("<b>" + quando(c.quando) + "</b>");
    meta.push("papel <b>" + esc(c.papel) + "</b>");
    if (c.quem) meta.push("de <b>" + esc(c.quem) + "</b>");
    if (c.imovel) meta.push("imóvel <b>" + esc(c.imovel) + "</b>");
    if (c.modelo) meta.push("modelo <b>" + esc(c.modelo) + "</b>");
    if (c.prompt_versao) meta.push("prompt <b>v" + esc(c.prompt_versao) + "</b>");
    if (c.seg_ate_responder != null) meta.push("respondeu em <b>" + esc(c.seg_ate_responder) + "s</b>");
    if (c.porta) meta.push("porta: <b>" + esc(c.porta) + "</b>");
    if (c.exec_id) meta.push('execução n8n <span class="mono">' + esc(c.exec_id) + "</span>");

    var html = '<div class="trilha__cab">' +
      '<h3 class="trilha__titulo">Conversa #' + esc(c.turno) + " " + selo(c.veredito) +
        (c.teste ? " " + selo("cinza", "teste") : "") + "</h3>" +
      '<p class="trilha__meta">' + meta.join(" · ") + "</p>" +
      (c.primeiro_erro ? '<div class="aviso-caixa" style="margin:10px 0 0"><b>Erro:</b> ' +
                         esc(c.primeiro_erro) + "</div>" : "") +
    "</div>";

    if (!setores.length) {
      alvo.innerHTML = html + '<p class="trilha__vazia">' +
        "Esta conversa não tem etapa registrada — provavelmente aconteceu antes " +
        "do trace ser ligado.</p>";
      return;
    }

    /* ---- a resposta que saiu, para a ponta direita ---- */
    var resposta = [];
    setores.forEach(function (s) {
      if (s.setor !== "saida") return;
      (s.passos || []).forEach(function (p) {
        var t = p.saida && p.saida.texto;
        if (t && p.resultado === "ok") resposta.push(t);
      });
    });

    /* ---- onde o caminho morreu ---- */
    var parouEm = -1;
    setores.forEach(function (s, i) {
      if (parouEm === -1 && (s.passos || []).some(function (p) { return p.resultado === "parou"; })) {
        parouEm = i;
      }
    });

    /* ---- o fluxo horizontal ---- */
    var pecas = [];
    pecas.push('<div class="fluxo__ponta">' +
      '<span class="fluxo__pl">ele escreveu</span>' +
      '<span class="fluxo__pt">' + (c.ele_disse ? esc(c.ele_disse) : "(sem texto)") + "</span></div>");
    pecas.push('<span class="fluxo__seta" aria-hidden="true"></span>');

    setores.forEach(function (s, i) {
      var cls = classeDoNo(s);
      var apagado = parouEm !== -1 && i > parouEm ? " fluxo__no--apagado" : "";
      pecas.push('<button class="fluxo__no fluxo__no--' + cls + apagado + '" type="button"' +
        ' data-no="' + esc(s.setor) + '" aria-pressed="' +
        (estado.no === s.setor ? "true" : "false") + '">' +
        '<span class="fluxo__pos">' + (i + 1) + " de " + setores.length + "</span>" +
        '<span class="fluxo__n">' + esc(s.titulo || s.setor) + "</span>" +
        '<span class="fluxo__r">' + esc(resumoDoNo(s)) + "</span>" +
      "</button>");
      var seta = (parouEm === i) ? " fluxo__seta--parou" : "";
      var apSeta = (parouEm !== -1 && i > parouEm) ? ' style="opacity:.42"' : "";
      pecas.push('<span class="fluxo__seta' + seta + '"' + apSeta + ' aria-hidden="true"></span>');
    });

    pecas.push('<div class="fluxo__ponta"' +
      (parouEm !== -1 ? ' style="opacity:.42"' : "") + ">" +
      '<span class="fluxo__pl">' + (resposta.length ? "ela respondeu" : "não saiu nada") + "</span>" +
      '<span class="fluxo__pt">' + (resposta.length ? esc(resposta.join(" ")) :
        (parouEm !== -1 ? "o caminho parou antes" : "—")) + "</span></div>");

    html += '<div class="fluxo-rolagem"><div class="fluxo" id="cb-fluxo">' +
      pecas.join("") + "</div></div>";

    html += '<div class="fluxo-detalhe" id="cb-fluxo-detalhe">' +
      '<p class="fluxo-detalhe__vazio">Clique numa etapa do caminho acima para ver o que ' +
      "aconteceu nela.</p></div>";

    alvo.innerHTML = html;

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-no]"), function (b) {
      b.addEventListener("click", function () { abrirNo(b.getAttribute("data-no")); });
    });

    /* Abre sozinho o primeiro nó com problema: quem entra aqui quer ver o erro,
       não quer procurar por ele. */
    var comProblema = setores.filter(function (s) { return classeDoNo(s) === "problema"; })[0]
                   || setores.filter(function (s) { return classeDoNo(s) === "mexeu"; })[0];
    if (comProblema) abrirNo(comProblema.setor);
  }

  function abrirNo(setor) {
    estado.no = setor;
    Array.prototype.forEach.call(document.querySelectorAll("[data-no]"), function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-no") === setor ? "true" : "false");
    });
    var alvo = el("cb-fluxo-detalhe");
    var s = ((estado.trilha && estado.trilha.setores) || []).filter(function (x) {
      return x.setor === setor;
    })[0];
    if (!alvo || !s) return;

    alvo.innerHTML =
      '<h4 class="fluxo-detalhe__n">' + esc(s.titulo || s.setor) + "</h4>" +
      '<p class="fluxo-detalhe__d">' + esc(textoDoSetor(s.setor)) + "</p>" +
      (s.passos || []).map(function (p, i) { return passoHtml(p, setor + "-" + i); }).join("");

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-abre]"), function (b) {
      b.addEventListener("click", function () {
        var corpoEl = el(b.getAttribute("data-abre"));
        if (!corpoEl) return;
        var aberto = !corpoEl.hidden;
        corpoEl.hidden = aberto;
        b.setAttribute("aria-expanded", aberto ? "false" : "true");
        var mais = b.querySelector(".passo__mais");
        if (mais) mais.textContent = aberto ? "ver o dado" : "fechar";
      });
    });
  }

  function textoDoSetor(s) {
    return {
      entrada: "O que a Z-API entregou, antes de qualquer coisa acontecer.",
      identidade: "Quem é a pessoa: a chave do telefone, o @lid, as duas linhas da mesma pessoa.",
      porta: "Se ela ia ser atendida ou não, e por qual motivo.",
      cabecalho: "O prompt e o contexto exatos que foram ao modelo nesta conversa.",
      modelo: "O que o modelo respondeu ANTES de qualquer conferência. É o texto cru dele.",
      ferramenta: "Que ferramenta ele chamou, com quais argumentos, e o que voltou.",
      conferencia: "As regras que você ensinou, conferidas uma a uma. O que não está 'ok' é regra que ela ignorou e o sistema corrigiu.",
      montagem: "Como a resposta virou mensagem: card, fotos do card, frases do sistema.",
      saida: "O que saiu de verdade — e o que foi barrado, com o motivo.",
      agenda: "Os ticks de minuto: cobranças, lembretes, visitas.",
      comando: "Os comandos do Tel pelo WhatsApp.",
      catalogo: "Imóveis, fotos e a varredura do site."
    }[s] || "";
  }

  function passoHtml(p, id) {
    var problema = p.resultado === "erro" || p.resultado === "parou";
    var mexeu = p.resultado === "mudou" || p.resultado === "cortou";
    var temDado = p.entrada != null || p.saida != null;
    var corpoId = "cb-passo-" + id;
    var regra = estado.regras[p.etapa];   // só existe para as conferências

    var h = '<div class="passo' + (problema ? " passo--problema" : mexeu ? " passo--mudou" : "") + '">' +
      '<button class="passo__b" type="button"' +
        (temDado ? ' data-abre="' + corpoId + '" aria-expanded="false" aria-controls="' + corpoId + '"'
                 : ' aria-disabled="true"') + ">" +
        (p.resultado !== "ok" ? selo(p.resultado) + " " : "") +
        '<span class="passo__e">' + esc(regra ? regra.titulo : p.etapa) + "</span>" +
        (p.detalhe ? '<span class="passo__d">' + esc(p.detalhe) + "</span>" : "") +
        (temDado ? '<span class="passo__mais">ver o dado</span>' : "") +
        (p.ms != null ? '<span class="passo__ms">' + dur(p.ms) + "</span>" : "") +
      "</button>";

    /* A REGRA, escrita por extenso, dentro do passo. É o que transforma
       "citou_o_tel = cortou" em "ela ignorou: nunca citar o Tel". */
    if (regra) {
      /* `fluxo` NÃO é regra que ela possa ignorar -- é o sistema escolhendo
         caminho (qual imóvel é a conversa, se as fotos entram). Escrever
         "ela ignorou" aqui inflaria o número que o Tel usa para decidir, e
         a primeira vez que ele conferisse um caso desses a tela perderia a
         confiança dele. O mesmo critério do arquivo 66. */
      var ehRegra = regra.tipo === "parede" || regra.tipo === "ajuste";
      h += '<div class="passo__regra">' +
        selo(regra.tipo) + " <b>" + esc(regra.regra) + "</b>" +
        (p.resultado === "ok"
          ? '<br><span class="fraco">' +
            (ehRegra ? "Ela seguiu esta regra nesta resposta."
                     : "O sistema não precisou agir aqui.") + "</span>"
          : ehRegra
            ? '<br><span style="color:#8f2740"><b>Ela ignorou aqui.</b> ' +
              esc(regra.o_que_faz) + "</span>"
            : '<br><span class="fraco"><b>O sistema decidiu aqui</b> (não é ' +
              "desobediência dela). " + esc(regra.o_que_faz) + "</span>") +
      "</div>";
    }

    if (temDado) {
      var ent = json(p.entrada), sai = json(p.saida);
      h += '<div class="passo__corpo" id="' + corpoId + '" hidden>' +
        (ent ? '<p class="passo__rot">entrou</p><pre>' + esc(ent) + "</pre>" : "") +
        (sai ? '<p class="passo__rot">saiu</p><pre>' + esc(sai) + "</pre>" : "") +
      "</div>";
    }
    return h + "</div>";
  }

  function irParaExecucao(turno) {
    var aba = document.querySelector('[data-painel-abre="execucoes"]');
    if (aba) aba.click();
    estado.filtro = "todos";
    carregarExecucoes().then(function () {
      abrirExecucao(turno);
      var t = el("cb-trilha");
      if (t && t.scrollIntoView) t.scrollIntoView({ behavior: "smooth", block: "nearest" });
    });
  }

  /* =========================================================== SETORES ==== */
  function desenharSetores(lista) {
    var alvo = el("cb-setores");
    if (!alvo) return;
    if (!lista || !lista.length) { alvo.innerHTML = '<p class="fraco">Sem setores.</p>'; return; }

    alvo.innerHTML = lista.map(function (s) {
      var antiga = Number(s.da_ia_antiga || 0);
      var entulho = Number(s.candidatas_a_entulho || 0);
      return '<button class="setor setor--' + esc(s.semaforo) + '" type="button"' +
             ' data-setor="' + esc(s.setor) + '" aria-pressed="' +
             (estado.setor === s.setor ? "true" : "false") + '"' +
             ' title="' + esc(s.descricao || "") + '">' +
        '<span class="setor__topo"><span class="setor__ponto"></span>' +
          '<span class="setor__n">' + esc(s.titulo) + "</span></span>" +
        '<span class="setor__num"><b>' + esc(s.passagens || 0) + "</b> passagens" +
          (Number(s.erros || 0) ? " · <b>" + esc(s.erros) + "</b> erros" : "") +
          (Number(s.paradas || 0) ? " · <b>" + esc(s.paradas) + "</b> paradas" : "") +
          (Number(s.correcoes || 0) ? " · <b>" + esc(s.correcoes) + "</b> correções" : "") +
          "<br><b>" + esc(s.funcoes || 0) + "</b> funções" +
          (antiga ? ", <b>" + antiga + "</b> da IA antiga" : "") + "</span>" +
        (entulho ? '<span class="setor__aviso">' + entulho + " candidata" +
                   (entulho > 1 ? "s" : "") + " a entulho</span>" : "") +
      "</button>";
    }).join("");

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-setor]"), function (b) {
      b.addEventListener("click", function () { abrirSetor(b.getAttribute("data-setor")); });
    });
  }

  function abrirSetor(setor) {
    estado.setor = estado.setor === setor ? null : setor;
    Array.prototype.forEach.call(document.querySelectorAll("[data-setor]"), function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-setor") === estado.setor ? "true" : "false");
    });
    var caixa = el("cb-setor-detalhe");
    if (!estado.setor) { if (caixa) caixa.hidden = true; return; }

    buscar("/api/nai/trace/setor/" + encodeURIComponent(estado.setor)).then(function (d) {
      if (caixa) caixa.hidden = false;
      el("cb-setor-titulo").textContent = "Setor " + (d.setor.titulo || estado.setor);
      el("cb-setor-desc").textContent = d.setor.descricao || "";
      tabela(el("cb-setor-etapas"),
        ["Etapa", { t: "Passagens", num: true }, { t: "Agiu", num: true },
         { t: "% agiu", num: true }, { t: "Erros", num: true }, { t: "Paradas", num: true },
         "Último problema", "Últimas conversas"],
        d.etapas,
        function (l) {
          var r = estado.regras[l.etapa];
          return "<td><b>" + esc(r ? r.titulo : l.etapa) + "</b></td>" +
                 '<td class="num">' + esc(l.passagens) + "</td>" +
                 '<td class="num">' + esc(l.agiu) + "</td>" +
                 '<td class="num">' + esc(l.pct_agiu) + "%</td>" +
                 '<td class="num">' + esc(l.erros) + "</td>" +
                 '<td class="num">' + esc(l.paradas) + "</td>" +
                 "<td>" + (l.ultimo_problema ? quando(l.ultimo_problema) : '<span class="fraco">nunca</span>') + "</td>" +
                 "<td>" + (l.ultimos_turnos && l.ultimos_turnos.length
                   ? l.ultimos_turnos.map(function (t) {
                       return '<a href="#" data-ir-turno="' + esc(t) + '">#' + esc(t) + "</a>";
                     }).join(" ")
                   : '<span class="fraco">—</span>') + "</td>";
        },
        "Nenhuma etapa registrada neste setor nos últimos 30 dias.");
      ligarLinksDeTurno(el("cb-setor-etapas"));
    }).catch(function (e) { erroNaTela(el("cb-setor-etapas"), e); });
  }

  /* ======================================================== INVENTÁRIO ==== */
  function desenharInventario(d) {
    var foto = (d.fotos || [])[0];
    var nota = el("cb-foto-nota");
    if (nota) {
      nota.innerHTML = foto
        ? "Comparando com a foto <b>" + esc(foto.rotulo) + "</b>, de " + quando(foto.tirada_em) +
          " (" + esc(foto.funcoes) + " funções). Linha aqui significa que o banco mudou " +
          "depois dessa foto — quase sempre conserto feito direto em produção que não " +
          "voltou para o repositório."
        : "Nenhuma foto do banco foi tirada ainda. Rode " +
          "<span class='mono'>SELECT nai_foto_tirar('marco zero');</span>";
    }

    tabela(el("cb-desvio"), ["Mudança", "Setor", "Função", "Assinatura", "Detalhe"], d.desvio,
      function (l) {
        return "<td>" + selo(l.mudanca === "corpo_mudou" ? "muda"
                           : l.mudanca === "apagada" ? "erro" : "corrigida", l.mudanca) + "</td>" +
               "<td>" + esc(l.setor) + "</td>" +
               '<td class="mono">' + esc(l.funcao) + "</td>" +
               '<td class="mono fraco">' + esc(l.args) + "</td>" +
               "<td>" + esc(l.detalhe) + "</td>";
      },
      "Nada mudou desde a última foto. O banco e a foto estão iguais.");

    tabela(el("cb-mapa"),
      ["Setor", { t: "Funções", num: true }, { t: "IA nova", num: true },
       { t: "IA antiga", num: true }, { t: "Candidatas a entulho", num: true },
       { t: "Depende da antiga", num: true }],
      d.mapa,
      function (l) {
        return "<td><b>" + esc(l.titulo) + "</b></td>" +
               '<td class="num">' + esc(l.funcoes) + "</td>" +
               '<td class="num">' + esc(l.da_ia_nova) + "</td>" +
               '<td class="num">' + (Number(l.da_ia_antiga) ? "<b>" + esc(l.da_ia_antiga) + "</b>" : "0") + "</td>" +
               '<td class="num">' + esc(l.candidatas_a_entulho) + "</td>" +
               '<td class="num">' + esc(l.dependencias_da_antiga) + "</td>";
      });

    tabela(el("cb-acoplamento"),
      ["Função da Nay antiga", "Setor dela", { t: "Quantas NAI chamam", num: true },
       "Chamada por", "Setores afetados"],
      d.acoplamento,
      function (l) {
        return '<td class="mono">' + esc(l.funcao_antiga) + "</td>" +
               "<td>" + esc(l.setor_da_antiga) + "</td>" +
               '<td class="num"><b>' + esc(l.quantas_nai_chamam) + "</b></td>" +
               '<td class="mono fraco">' + esc(l.chamada_por) + "</td>" +
               "<td>" + esc(l.setores_afetados) + "</td>";
      },
      "Nenhum acoplamento — a IA nova não depende da antiga.");

    tabela(el("cb-sobrecargas"),
      ["Função", "Setor", { t: "Versões", num: true }, "Assinaturas", "Veredito"],
      d.sobrecargas,
      function (l) {
        var deProposito = /proposito/i.test(l.veredito || "");
        return '<td class="mono">' + esc(l.funcao) + "</td>" +
               "<td>" + esc(l.setor) + "</td>" +
               '<td class="num">' + esc(l.versoes) + "</td>" +
               '<td class="mono fraco">' + esc(l.assinaturas) + "</td>" +
               "<td>" + (deProposito ? selo("ok", "de propósito") + " " + esc(l.esperada_porque || "")
                                     : selo("erro", "investigar") + " " + esc(l.veredito)) + "</td>";
      },
      "Nenhuma função com mais de uma assinatura.");

    tabela(el("cb-orfas"),
      ["Função", "Setor", "Família", { t: "Tamanho", num: true }, "Chamador de fora", "Confiança"],
      d.orfas,
      function (l) {
        var candidata = /CANDIDATA/.test(l.confianca || "");
        return '<td class="mono">' + esc(l.funcao) + "</td>" +
               "<td>" + esc(l.setor) + "</td>" +
               "<td>" + esc(l.familia === "nay" ? "IA antiga" : "IA nova") + "</td>" +
               '<td class="num">' + esc(l.tamanho) + "</td>" +
               "<td>" + (l.chamador_de_fora ? '<span class="mono fraco">' + esc(l.chamador_de_fora) + "</span>"
                                            : '<span class="fraco">—</span>') + "</td>" +
               "<td>" + (candidata ? selo("muda", "candidata") : selo("ok", "viva")) + "</td>";
      },
      "Nenhuma função órfã.");
  }

  /* ============================================================== INÍCIO == */
  function carregarTudo() {
    buscar("/api/nai/trace/saude").then(desenharDiagnostico)
      .catch(function (e) { erroNaTela(el("cb-diagnostico"), e); });

    /* As regras carregam PRIMEIRO: o resto da tela usa `estado.regras` para
       escrever o nome da regra em vez do nome técnico da conferência. */
    buscar("/api/nai/trace/regras").then(function (d) {
      desenharRegras(d);
      return carregarExecucoes();
    }).catch(function (e) { erroNaTela(el("cb-regras"), e); carregarExecucoes(); });

    buscar("/api/nai/trace/setores").then(function (d) { desenharSetores(d.setores); })
      .catch(function (e) { erroNaTela(el("cb-setores"), e); });

    buscar("/api/nai/trace/inventario").then(desenharInventario)
      .catch(function (e) { erroNaTela(el("cb-mapa"), e); });
  }

  function iniciar() {
    var b = el("cb-recarregar");
    if (b) b.addEventListener("click", function () {
      estado.setor = null;
      var caixa = el("cb-setor-detalhe");
      if (caixa) caixa.hidden = true;
      carregarTudo();
    });
    carregarTudo();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else {
    iniciar();
  }
})();
