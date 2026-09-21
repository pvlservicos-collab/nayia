/* ==========================================================================
   Imob Easy — Cérebro da Nay: aba TREINO

   Tel (19/09/2026):
     "cria um menu de treinamento lá dentro do cérebro da Nay e lá nós vamos
      testar... vai ter uma lista dessas conversas e você vai executar elas
      como se fossem reais com mockups de conversa igual os mockups do
      revisar no whatsapp"
     "eu quero 2 formatos de visualização"
     "eu vou marcar como conversou corretamente, ou descrever um erro... e
      mais um campo verde solução... então são 1 botão e 2 campos de texto e
      um botão de salvar"
     "esses testes não são no whatsapp e sim no nosso site com intuito de
      aprendizado"

   TRÊS DECISÕES QUE VÊM DAÍ:

   1. ESTA TELA NÃO EXECUTA NADA. Ela lê o que o `nai_treino_rodar.py` já
      produziu e grava o julgamento. Um botão "rodar" aqui transformaria uma
      página de painel em disparador de fluxo — o mesmo motivo pelo qual a
      tela de captação não envia mensagem.

   2. DOIS FORMATOS, UMA FICHA SÓ. A lista serve para varrer os 50 e achar
      onde olhar; a conversa serve para julgar, porque sem o que veio antes
      não dá para dizer se a resposta estava certa. Julgar num formato
      aparece no outro na hora, porque o julgamento mora no estado, não no
      HTML de cada um.

   3. O JULGAMENTO SALVA SOZINHO O "CORRETO". Marcar certo é um clique e
      não tem texto para escrever; obrigar um segundo clique em Salvar faria
      o Tel dar 50 cliques a mais por ciclo. Errado exige Salvar, porque aí
      ele ainda está escrevendo.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";
  var FUSO = "America/Manaus";

  var estado = {
    ciclo: null,
    ciclos: [],
    casos: [],
    visao: "lista",     // lista | mockup
    filtro: "todos",    // todos | pendentes | errados | corretos | mudou
    escolhido: null,
    carregando: false
  };

  /* ------------------------------------------------------------ utilidades */
  function esc(t) {
    return String(t == null ? "" : t)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function el(id) { return document.getElementById(id); }

  function buscar(rota, opcoes) {
    return fetch(API + rota, opcoes).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok) throw new Error(j && j.erro ? j.erro : "a API respondeu " + r.status);
        return j;
      });
    });
  }

  function hora(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleTimeString("pt-BR",
      { hour: "2-digit", minute: "2-digit", timeZone: FUSO });
  }
  function dia(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleDateString("pt-BR",
      { day: "2-digit", month: "long", timeZone: FUSO });
  }
  function quando(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return isNaN(d) ? String(iso) : d.toLocaleString("pt-BR",
      { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  }
  function iniciais(nome) {
    var p = String(nome || "?").trim().split(/\s+/);
    return ((p[0] || "?").charAt(0) + (p.length > 1 ? p[p.length - 1].charAt(0) : "")).toUpperCase();
  }
  function cortar(t, n) {
    t = String(t == null ? "" : t).replace(/\s+/g, " ").trim();
    return t.length > n ? t.slice(0, n - 1) + "…" : t;
  }
  function cartao(rotulo, valor, nota) {
    return '<div class="painel-cartao"><div class="painel-cartao__n">' + esc(valor) +
           '</div><div class="painel-cartao__r">' + esc(rotulo) +
           (nota ? " · " + esc(nota) : "") + "</div></div>";
  }

  /* A resposta sai da caixa como várias mensagens separadas por ---. No
     WhatsApp elas chegam como balões separados, e é assim que ele as viu. */
  function pedacos(texto) {
    return String(texto == null ? "" : texto)
      .split(/\n---\n/)
      .map(function (t) { return t.trim(); })
      .filter(Boolean);
  }

  function casoPorId(id) {
    for (var i = 0; i < estado.casos.length; i++) {
      if (estado.casos[i].id === id) return estado.casos[i];
    }
    return null;
  }

  function filtrados() {
    return estado.casos.filter(function (c) {
      if (estado.filtro === "pendentes") return !c.veredito;
      if (estado.filtro === "errados")   return c.veredito === "errado";
      if (estado.filtro === "corretos")  return c.veredito === "correto";
      if (estado.filtro === "mudou")     return !!c.mudou;
      return true;
    });
  }

  /* ============================================================ CARTÕES ==== */
  function desenharCartoes() {
    var t = estado.casos.length;
    var rodados = estado.casos.filter(function (c) { return c.estado === "rodado"; }).length;
    var erros = estado.casos.filter(function (c) { return c.estado === "erro"; }).length;
    var julgados = estado.casos.filter(function (c) { return !!c.veredito; }).length;
    var corretos = estado.casos.filter(function (c) { return c.veredito === "correto"; }).length;
    var mudou = estado.casos.filter(function (c) { return !!c.mudou; }).length;

    el("tr-cartoes").innerHTML =
      cartao("Casos no ciclo", t, rodados + " re-executados") +
      cartao("Julgados", julgados, t ? Math.round(julgados * 100 / t) + "%" : "") +
      cartao("Conversou certo", corretos, julgados ? Math.round(corretos * 100 / julgados) + "% dos julgados" : "") +
      cartao("Com erro anotado", julgados - corretos) +
      cartao("Mudou de resposta", mudou, "vs. a execução original") +
      (erros ? cartao("Falharam ao rodar", erros, "veja a coluna Estado") : "");

    var filtros = [
      ["todos", "Todos", t],
      ["pendentes", "Por julgar", t - julgados],
      ["errados", "Com erro", julgados - corretos],
      ["corretos", "Certos", corretos],
      ["mudou", "Mudaram", mudou]
    ];
    el("tr-filtros").innerHTML = filtros.map(function (f) {
      return '<button class="filtro" type="button" data-filtro="' + f[0] + '" aria-pressed="' +
             (estado.filtro === f[0] ? "true" : "false") + '">' + esc(f[1]) +
             ' <span class="filtro__c">' + f[2] + "</span></button>";
    }).join("");
  }

  /* ====================================================== FORMATO 1: LISTA ==
     Os 50 de uma vez. Cada linha mostra o que ele disse, o que ela respondeu
     agora, e o veredito — o suficiente para decidir onde vale abrir a
     conversa inteira. */
  function desenharLista() {
    var lista = filtrados();
    var cab = "<thead><tr>" +
      ["Quando", "Quem", "Ele disse", "Ela respondeu agora", "Ferramentas", "Estado", "Veredito", ""]
        .map(function (c) { return "<th>" + esc(c) + "</th>"; }).join("") + "</tr></thead>";

    var corpo = "<tbody>" + (lista.length ? lista.map(function (c) {
      var vered = c.veredito === "correto" ? '<span class="selo selo--ok">certo</span>'
                : c.veredito === "errado"  ? '<span class="selo selo--erro">erro</span>'
                : '<span class="selo selo--cinza">por julgar</span>';
      var est = c.estado === "rodado" ? (c.mudou ? '<span class="selo selo--mudou">mudou</span>'
                                                 : '<span class="selo selo--cinza">igual</span>')
              : c.estado === "erro"   ? '<span class="selo selo--parou">falhou</span>'
              : '<span class="selo selo--cinza">' + esc(c.estado) + "</span>";
      var ferr = (c.ferramentas_agora || []).filter(function (f) { return f.charAt(0) !== "_"; });
      return '<tr><td>' + esc(quando(c.quando_original)) + "</td>" +
             "<td>" + esc(c.nome_completo || c.nome_whatsapp || "—") + "</td>" +
             "<td>" + esc(cortar(c.ele_disse, 90)) + "</td>" +
             "<td>" + esc(cortar(c.ela_respondeu_agora || (c.estado === "erro" ? c.erro_execucao : "(calada)"), 120)) +
               (c.mudou ? '<span class="tr__cmp">antes: ' + esc(cortar(c.ela_respondeu_antes, 90)) + "</span>" : "") +
             "</td>" +
             '<td class="mono">' + esc(ferr.join(", ") || "—") + "</td>" +
             "<td>" + est + "</td><td>" + vered + "</td>" +
             '<td><button class="btn-mini" type="button" data-abrir="' + c.id + '">Abrir</button></td></tr>';
    }).join("") : '<tr><td colspan="8" class="fraco">Nenhum caso com esse filtro.</td></tr>') + "</tbody>";

    el("tr-tabela").innerHTML = cab + corpo;
  }

  /* =================================================== FORMATO 2: CONVERSA ==
     O mockup. Reusa a linguagem do "Revisar no WhatsApp": balão branco dele,
     balão verde dela. O balão do caso fica destacado, e logo abaixo entra a
     resposta da re-execução para comparar lado a lado. */
  function desenharIndice() {
    var lista = filtrados();
    el("tr-indice-topo").textContent = lista.length + " caso" + (lista.length === 1 ? "" : "s") +
      (estado.filtro === "todos" ? "" : " (filtrado)");

    if (!lista.length) {
      el("tr-itens").innerHTML = '<p class="tr__vazio">Nada com esse filtro.</p>';
      return;
    }
    el("tr-itens").innerHTML = lista.map(function (c, i) {
      var ponto = c.veredito === "correto" ? '<span class="selo selo--ok">certo</span>'
                : c.veredito === "errado"  ? '<span class="selo selo--erro">erro</span>'
                : c.mudou                  ? '<span class="selo selo--mudou">mudou</span>' : "";
      return '<button class="tr__item" type="button" data-caso="' + c.id + '" aria-selected="' +
             (estado.escolhido === c.id ? "true" : "false") + '">' +
             '<span class="tr__item-topo"><span class="tr__item-n">' + (i + 1) + "</span>" + ponto +
             '<span class="tr__item-n" style="margin-left:auto">' + esc(hora(c.quando_original)) + "</span></span>" +
             '<span class="tr__item-t">' + esc(cortar(c.ele_disse, 46)) + "</span></button>";
    }).join("");
  }

  function balao(lado, texto, carimbo, extra) {
    return '<div class="tr__b tr__b--' + lado + (extra ? " " + extra : "") + '">' +
           esc(texto) + (carimbo ? "<time>" + esc(carimbo) + "</time>" : "") + "</div>";
  }

  function desenharConversa() {
    var alvo = el("tr-conversa");
    var c = casoPorId(estado.escolhido);
    if (!c) {
      alvo.innerHTML = '<p class="tr__vazio">Escolha um caso na lista ao lado.</p>';
      return;
    }

    /* o histórico que veio antes — é o que dá sentido à pergunta dele */
    var diaAnterior = "";
    var hist = (c.contexto || []).map(function (m) {
      var pedaco = "";
      var d = dia(m.quando);
      if (d && d !== diaAnterior) { diaAnterior = d; pedaco += '<div class="tr__dia">' + esc(d) + "</div>"; }
      return pedaco + balao(m.lado === "dele" ? "dele" : "dela", m.texto, hora(m.quando));
    }).join("");

    var d = dia(c.quando_original);
    if (d && d !== diaAnterior) hist += '<div class="tr__dia">' + esc(d) + "</div>";

    /* o turno do caso: a fala dele em foco, a resposta original, e a de agora */
    var foco = balao("dele", c.ele_disse, hora(c.quando_original), "tr__b--foco");

    var antes = pedacos(c.ela_respondeu_antes);
    var agora = pedacos(c.ela_respondeu_agora);

    var blocoAntes = antes.length
      ? '<div class="tr__rot">o que ela respondeu na época</div>' +
        antes.map(function (t) { return balao("dela", t, hora(c.quando_original)); }).join("")
      : "";

    var blocoAgora = c.estado === "erro"
      ? '<div class="tr__rot">a re-execução falhou</div>' +
        balao("dela", c.erro_execucao || "sem detalhe", "", "tr__b--agora")
      : agora.length
        ? '<div class="tr__rot">o que ela responde AGORA' + (c.mudou ? " — mudou" : " — igual") + "</div>" +
          agora.map(function (t) { return balao("dela", t, hora(c.rodado_em), "tr__b--agora"); }).join("")
        : '<div class="tr__rot">agora ela ficou calada</div>';

    var ferr = (c.ferramentas_agora || []).filter(function (f) { return f.charAt(0) !== "_"; });

    alvo.innerHTML =
      '<div class="tr__topo">' +
        '<span class="tr__ini">' + esc(iniciais(c.nome_completo || c.nome_whatsapp)) + "</span>" +
        "<span><h4>" + esc(c.nome_completo || c.nome_whatsapp || "(sem nome)") + "</h4>" +
        "<small>turno #" + esc(c.turno_origem) + " · " + esc(quando(c.quando_original)) +
        (ferr.length ? " · " + esc(ferr.join(", ")) : "") + "</small></span>" +
      "</div>" +
      '<div class="tr__baloes">' + hist + foco + blocoAntes + blocoAgora + "</div>" +
      ficha(c);
  }

  /* ========================================================= A FICHA ======== */
  /* Um botão e dois campos, como ele pediu. O botão marca certo na hora; os
     campos só valem quando ele clica em Salvar. */
  function ficha(c) {
    var certo = c.veredito === "correto";
    var marca = c.veredito
      ? "julgado como <b>" + (certo ? "certo" : "errado") + "</b> em " + esc(quando(c.julgado_em))
      : "ainda não julgado";
    return '<div class="tr__ficha" data-ficha="' + c.id + '">' +
      '<div class="tr__ficha-linha">' +
        '<button class="tr__ok" type="button" data-correto="' + c.id + '" aria-pressed="' +
          (certo ? "true" : "false") + '">✓ Conversou corretamente</button>' +
        '<span class="tr__marca">' + marca + "</span>" +
      "</div>" +
      '<div class="tr__campos">' +
        '<div class="tr__cx tr__cx--erro"><label for="tr-erro-' + c.id + '">O erro</label>' +
          '<textarea id="tr-erro-' + c.id + '" data-campo="erro" placeholder="O que ela fez de errado nesta conversa?">' +
          esc(c.julgamento_erro || "") + "</textarea></div>" +
        '<div class="tr__cx tr__cx--sol"><label for="tr-sol-' + c.id + '">A solução</label>' +
          '<textarea id="tr-sol-' + c.id + '" data-campo="solucao" placeholder="É só uma regra? Precisa mudar alguma coisa? Ela não respeitou o que já existe?">' +
          esc(c.julgamento_solucao || "") + "</textarea></div>" +
      "</div>" +
      '<button class="tr__salvar" type="button" data-salvar="' + c.id + '">Salvar</button>' +
      '<span class="tr__estado" data-estado="' + c.id + '"></span>' +
      "</div>";
  }

  /* ========================================================== GRAVAR ======== */
  function gravar(id, veredito, erro, solucao, aviso) {
    return buscar("/api/nai/treino/julgamento/" + id, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ veredito: veredito, erro: erro, solucao: solucao, por: "painel" })
    }).then(function (j) {
      var c = casoPorId(id);
      if (c) {
        c.veredito = veredito;
        c.julgamento_erro = erro || null;
        c.julgamento_solucao = solucao || null;
        c.julgado_em = j.julgamento && j.julgamento.julgado_em;
      }
      if (aviso) aviso.textContent = "salvo";
      desenharCartoes();
      desenharLista();
      desenharIndice();
      return j;
    }).catch(function (e) {
      if (aviso) aviso.textContent = e.message || "não salvou";
      throw e;
    });
  }

  /* =========================================================== EVENTOS ====== */
  document.addEventListener("click", function (ev) {
    var t = ev.target;

    /* trocar de formato */
    var vb = t.closest && t.closest("[data-visao]");
    if (vb) {
      estado.visao = vb.dataset.visao;
      Array.prototype.forEach.call(document.querySelectorAll("[data-visao]"), function (b) {
        b.setAttribute("aria-pressed", b.dataset.visao === estado.visao ? "true" : "false");
      });
      el("tr-lista-visao").hidden = estado.visao !== "lista";
      el("tr-mockup-visao").hidden = estado.visao !== "mockup";
      if (estado.visao === "mockup") { desenharIndice(); desenharConversa(); }
      return;
    }

    /* filtro */
    var f = t.closest && t.closest("[data-filtro]");
    if (f && f.closest("#tr-filtros")) {
      estado.filtro = f.dataset.filtro;
      var lista = filtrados();
      if (!lista.some(function (c) { return c.id === estado.escolhido; })) {
        estado.escolhido = lista.length ? lista[0].id : null;
      }
      desenharCartoes(); desenharLista(); desenharIndice(); desenharConversa();
      return;
    }

    /* "Abrir" na lista leva para a conversa daquele caso */
    var ab = t.closest && t.closest("[data-abrir]");
    if (ab) {
      estado.escolhido = Number(ab.dataset.abrir);
      estado.visao = "mockup";
      Array.prototype.forEach.call(document.querySelectorAll("[data-visao]"), function (b) {
        b.setAttribute("aria-pressed", b.dataset.visao === "mockup" ? "true" : "false");
      });
      el("tr-lista-visao").hidden = true;
      el("tr-mockup-visao").hidden = false;
      desenharIndice(); desenharConversa();
      el("tr-mockup-visao").scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }

    /* escolher um caso no índice */
    var it = t.closest && t.closest("[data-caso]");
    if (it) {
      estado.escolhido = Number(it.dataset.caso);
      desenharIndice(); desenharConversa();
      return;
    }

    /* o botão de certo: salva na hora */
    var ok = t.closest && t.closest("[data-correto]");
    if (ok) {
      var idOk = Number(ok.dataset.correto);
      var avisoOk = document.querySelector('[data-estado="' + idOk + '"]');
      if (avisoOk) avisoOk.textContent = "salvando…";
      gravar(idOk, "correto", null, null, avisoOk).then(function () {
        desenharConversa();
        /* anda para o próximo por julgar: o Tel está varrendo 50, e parar
           para procurar o próximo a cada clique é o que faz cansar */
        var prox = filtrados().filter(function (c) { return !c.veredito; })[0];
        if (prox) { estado.escolhido = prox.id; desenharIndice(); desenharConversa(); }
      }).catch(function () {});
      return;
    }

    /* salvar erro + solução */
    var sv = t.closest && t.closest("[data-salvar]");
    if (sv) {
      var id = Number(sv.dataset.salvar);
      var ficha = document.querySelector('[data-ficha="' + id + '"]');
      if (!ficha) return;
      var erro = ficha.querySelector('[data-campo="erro"]').value.trim();
      var sol = ficha.querySelector('[data-campo="solucao"]').value.trim();
      var aviso = ficha.querySelector('[data-estado="' + id + '"]');
      if (!erro && !sol) {
        aviso.textContent = "escreva o erro ou a solução — ou marque como correto";
        return;
      }
      sv.disabled = true;
      aviso.textContent = "salvando…";
      gravar(id, "errado", erro, sol, aviso)
        .then(function () { sv.disabled = false; desenharConversa(); })
        .catch(function () { sv.disabled = false; });
      return;
    }

    if (t.closest && t.closest("#tr-recarregar")) carregarCasos();
  });

  /* ============================================================ CARGA ======= */
  function carregarCiclos() {
    return buscar("/api/nai/treino/ciclos").then(function (j) {
      estado.ciclos = j.ciclos || [];
      var sel = el("tr-ciclo");
      if (!estado.ciclos.length) {
        sel.innerHTML = '<option value="">nenhum ciclo montado ainda</option>';
        el("tr-aviso").innerHTML = '<div class="aviso-caixa">' +
          "<b>Ainda não há ciclo montado.</b> O pool tem <b>" + esc(j.pool) +
          "</b> turnos respondidos disponíveis. Para montar o primeiro e rodar, no servidor:" +
          '<br><span class="mono">python3 nai_treino_rodar.py --montar 50</span></div>';
        return null;
      }
      sel.innerHTML = estado.ciclos.map(function (c) {
        return '<option value="' + c.id + '">ciclo ' + c.id + " — " + esc(c.rotulo) +
               " (" + c.julgados + "/" + c.casos + " julgados)</option>";
      }).join("");
      estado.ciclo = estado.ciclo || estado.ciclos[0].id;
      sel.value = String(estado.ciclo);
      el("tr-aviso").innerHTML = j.pool
        ? '<p class="painel-nota">Sobram <b>' + esc(j.pool) +
          "</b> turnos nunca usados para os próximos ciclos — nenhum se repete.</p>"
        : '<p class="painel-nota">Todos os turnos respondidos já viraram caso.</p>';
      return estado.ciclo;
    });
  }

  function carregarCasos() {
    if (!estado.ciclo || estado.carregando) return Promise.resolve();
    estado.carregando = true;
    return buscar("/api/nai/treino/casos?ciclo=" + estado.ciclo).then(function (j) {
      estado.casos = j.casos || [];
      var lista = filtrados();
      if (!lista.some(function (c) { return c.id === estado.escolhido; })) {
        estado.escolhido = lista.length ? lista[0].id : null;
      }
      desenharCartoes(); desenharLista(); desenharIndice(); desenharConversa();
    }).catch(function (e) {
      el("tr-aviso").innerHTML = '<div class="aviso-caixa"><b>Não consegui carregar os casos.</b> ' +
        esc(e.message) + "<br>Confira se o blueprint <span class=\"mono\">treino_api.py</span> " +
        "está registrado no <span class=\"mono\">app.py</span>.</div>";
    }).then(function () { estado.carregando = false; });
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (!el("tr-ciclo")) return;
    el("tr-ciclo").addEventListener("change", function () {
      estado.ciclo = Number(this.value) || null;
      estado.escolhido = null;
      carregarCasos();
    });
    carregarCiclos().then(function (c) { if (c) carregarCasos(); });
  });
})();
