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
    carregando: false,
    atual: null,        // a rodada mais nova -- a que o Tel quer ver
    historico: false,   // true = ele abriu o historico e escolheu outra rodada
    vistos: {},         // ids ja desenhados, para destacar o que acabou de chegar
    relogio: null
  };

  var ESPERA_MS = 8000;   // de quanto em quanto a barra pergunta o progresso

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

  /* Conversa simulada (rodada 7 em diante): o nome e o do corretor simulado,
     e a etiqueta diz de qual conversa e qual passo e aquela resposta. */
  function quem(c) { return c.persona || c.nome_completo || c.nome_whatsapp; }
  function etiqueta(c) {
    return esc(c.ciclo_rotulo || ("ciclo " + c.ciclo_id)) +
      (c.roteiro ? " · conversa " + esc(c.roteiro) + " · passo " + esc(c.passo) : "");
  }

  function casoPorId(id) {
    for (var i = 0; i < estado.casos.length; i++) {
      if (estado.casos[i].id === id) return estado.casos[i];
    }
    return null;
  }

  /* Na rodada ATUAL so aparece o que ela ja respondeu (Tel, 21/09: "as
     conversas que vao aparecer ja vai ser a resposta da nay"). Caso ainda na
     fila so tem a fala dele, e nao ha o que julgar. */
  function naAtual() {
    return !estado.historico && estado.ciclo === estado.atual;
  }

  function filtrados() {
    return estado.casos.filter(function (c) {
      if (naAtual() && c.estado !== "rodado" && c.estado !== "erro") return false;
      if (estado.filtro === "pendentes") return !c.veredito;
      if (estado.filtro === "errados")   return c.veredito === "errado";
      if (estado.filtro === "corretos")  return c.veredito === "correto";
      return true;
    });
  }

  /* ============================================================ CARTÕES ==== */
  function desenharCartoes() {
    var t = estado.casos.length;
    var visiveis = naAtual()
      ? estado.casos.filter(function (c) { return c.estado === "rodado" || c.estado === "erro"; }).length
      : t;
    var rodados = estado.casos.filter(function (c) { return c.estado === "rodado"; }).length;
    var erros = estado.casos.filter(function (c) { return c.estado === "erro"; }).length;
    var julgados = estado.casos.filter(function (c) { return !!c.veredito; }).length;
    var corretos = estado.casos.filter(function (c) { return c.veredito === "correto"; }).length;

    el("tr-cartoes").innerHTML =
      cartao("Respondidas", rodados + erros, "de " + t + " na rodada") +
      cartao("Julgados", julgados, t ? Math.round(julgados * 100 / t) + "%" : "") +
      cartao("Conversou certo", corretos, julgados ? Math.round(corretos * 100 / julgados) + "% dos julgados" : "") +
      cartao("Com erro anotado", julgados - corretos) +
      (erros ? cartao("Falharam ao rodar", erros, "veja a coluna Estado") : "");

    var filtros = [
      ["todos", "Todos", visiveis],
      ["pendentes", "Por julgar", visiveis - julgados],
      ["errados", "Com erro", julgados - corretos],
      ["corretos", "Certos", corretos]
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
  /* O que ela respondeu, do jeito que sai no WhatsApp: uma mensagem por
     linha e as fotos no lugar delas. Antes vinha tudo grudado com "---", e o
     Tel leu isso como se ela mandasse um blocao so -- e como se as fotos nao
     tivessem saido (Tel, 22/09: "parece que nem enviou as fotos"). */
  /* AS FOTOS DA CONVERSA INTEIRA (Tel, 22/09: "nao ta aparecendo um
     indicativo que saiu as fotos em varias conversas, preciso ver
     visualmente"). A regra dele e foto UMA VEZ POR CONVERSA: pediu o mesmo
     imovel de novo, vai o card e as fotos nao se repetem. Sem dizer isso na
     tela, o card sem foto parece defeito. */
  function codigoDoCard(c) {
    var m = String(c.ela_respondeu_agora || "").match(/C[óo]digo:\s*(\d{3,5})/);
    return m ? m[1] : null;
  }
  function temFotos(c) {
    return (c.saida || []).some(function (b) { return b.tipo === "fotos"; });
  }
  function passosAnteriores(c) {
    if (!c.roteiro) return [];
    return estado.casos.filter(function (x) {
      return x.ciclo_id === c.ciclo_id && x.roteiro === c.roteiro && x.passo < c.passo;
    }).sort(function (a, b) { return a.passo - b.passo; });
  }
  /* card sem foto: as fotos desse imovel ja sairam antes nesta conversa? */
  function fotosJaSairam(c) {
    var cod = codigoDoCard(c);
    if (!cod || temFotos(c)) return null;
    var antes = passosAnteriores(c).filter(function (x) {
      return temFotos(x) &&
        (String(x.ela_respondeu_agora || "").indexOf(cod) >= 0 || String(x.ele_disse || "").indexOf(cod) >= 0);
    });
    return { cod: cod, passo: antes.length ? antes[0].passo : null };
  }

  function resumoDaSaida(c) {
    if (c.estado === "erro") return esc(cortar(c.erro_execucao, 120));
    if (c.estado === "calada") return '<span class="fraco">' + esc(c.erro_execucao || "calada") + "</span>";
    var blocos = c.saida && c.saida.length ? c.saida : null;
    if (!blocos) {
      return esc(cortar(c.ela_respondeu_agora || "(calada)", 120)) +
        (Number(c.fotos_agora || 0) > 0
           ? '<span class="tr__fotos-selo">+' + esc(c.fotos_agora) + " fotos</span>" : "");
    }
    var ja = fotosJaSairam(c);
    var nota = !ja ? ""
      : ja.passo
        ? '<div class="tr__msg tr__msg--ja">fotos do ' + esc(ja.cod) + " já enviadas no passo " + esc(ja.passo) + "</div>"
        : '<div class="tr__msg tr__msg--sem">card do ' + esc(ja.cod) + " saiu SEM fotos</div>";
    return '<div class="tr__msgs">' + blocos.map(function (b) {
      return b.tipo === "fotos"
        ? '<div class="tr__msg tr__msg--fotos">' + esc(b.fotos) +
            (b.fotos === 1 ? " foto" : " fotos") + "</div>"
        : '<div class="tr__msg">' + esc(cortar(b.texto, 90)) +
            (b.para && b.para !== "quem escreveu" && b.para !== "o corretor"
               ? '<span class="tr__para">para ' + esc(b.para) + "</span>" : "") +
          "</div>";
    }).join("") + nota + "</div>";
  }

  function desenharLista() {
    var lista = filtrados();
    var cab = "<thead><tr>" +
      ["Rodada", "Quando", "Quem", "Ele disse", "Ela respondeu agora", "Ferramentas", "Estado", "Veredito", ""]
        .map(function (c) { return "<th>" + esc(c) + "</th>"; }).join("") + "</tr></thead>";

    var corpo = "<tbody>" + (lista.length ? lista.map(function (c) {
      var vered = c.veredito === "correto" ? '<span class="selo selo--ok">certo</span>'
                : c.veredito === "errado"  ? '<span class="selo selo--erro">erro</span>'
                : '<span class="selo selo--cinza">por julgar</span>';
      var est = c.estado === "rodado" ? '<span class="selo selo--ok">respondeu</span>'
              : c.estado === "calada"  ? '<span class="selo selo--parou">calada</span>' 
              : c.estado === "erro"   ? '<span class="selo selo--parou">falhou</span>'
              : '<span class="selo selo--cinza">' + esc(c.estado) + "</span>";
      var ferr = (c.ferramentas_agora || []).filter(function (f) { return f.charAt(0) !== "_"; });
      return '<tr><td><span class="tr__rodada">' + etiqueta(c) + "</span></td>" +
             "<td>" + esc(quando(c.quando_original)) + "</td>" +
             "<td>" + esc(quem(c) || "—") + "</td>" +
             "<td>" + esc(cortar(c.ele_disse, 90)) + "</td>" +
             "<td>" + resumoDaSaida(c) +

             "</td>" +
             '<td class="mono">' + esc(ferr.join(", ") || "—") + "</td>" +
             "<td>" + est + "</td><td>" + vered + "</td>" +
             '<td><button class="btn-mini" type="button" data-abrir="' + c.id + '">Abrir</button></td></tr>';
    }).join("") : '<tr><td colspan="9" class="fraco">Nenhum caso com esse filtro.</td></tr>') + "</tbody>";

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
                : "";
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
    /* Conversa simulada: o historico vem dos PASSOS ANTERIORES, com as fotos
       que sairam em cada um -- o `contexto` guarda so texto. */
    var anteriores = passosAnteriores(c);
    var histPassos = anteriores.length ? anteriores.map(function (x) {
      var dele = balao("dele", (x.persona === "Tel (comando)" ? "[comando do Tel] " : "") + x.ele_disse, hora(x.rodado_em));
      var dela = (x.saida || []).map(function (b) {
        return b.tipo === "fotos"
          ? balao("dela", "(" + b.fotos + (b.fotos === 1 ? " foto" : " fotos") + ")", hora(x.rodado_em), "tr__b--fotos")
          : balao("dela", (b.para && b.para !== "quem escreveu" && b.para !== "o corretor" ? "[para " + b.para + "] " : "") + b.texto,
                  hora(x.rodado_em));
      }).join("");
      return dele + dela;
    }).join("") : null;
    var hist = histPassos !== null ? histPassos : (c.contexto || []).map(function (m) {
      var pedaco = "";
      var d = dia(m.quando);
      if (d && d !== diaAnterior) { diaAnterior = d; pedaco += '<div class="tr__dia">' + esc(d) + "</div>"; }
      return pedaco + balao(m.lado === "dele" ? "dele" : "dela", m.texto, hora(m.quando));
    }).join("");

    var d = dia(c.quando_original);
    if (d && d !== diaAnterior) hist += '<div class="tr__dia">' + esc(d) + "</div>";

    /* o turno do caso: a fala dele em foco, a resposta original, e a de agora */
    var foco = balao("dele", c.ele_disse, hora(c.quando_original), "tr__b--foco");

    var agora = pedacos(c.ela_respondeu_agora);

    /* O "o que ela respondeu na epoca" SAIU (Tel, 21/09): "eu quero so as
       conversas novas... voce vai simular no nosso fluxo as mensagens que o
       cliente mandou para a nay de novo". Duas respostas lado a lado faziam
       ele comparar em vez de julgar, e a da epoca e de uma Nay que nao existe
       mais -- prompt diferente, regras diferentes. O dado continua na tabela,
       so nao ocupa a tela. */

    /* NA ORDEM EM QUE SAIU NO WHATSAPP (Tel, 22/09: "ela juntando as mensagens
       em um blocao, falando que enviou as fotos mas nao enviou mesmo"). A
       caixa de saida vem pronta da view, em `saida`: cada texto um balao,
       cada rajada de fotos um balao "(12 fotos)" no lugar certo. Antes os
       textos vinham grudados e as fotos, quando apareciam, iam todas para o
       fim -- e lia-se "Aqui as fotos" sem foto nenhuma embaixo. */
    var blocos = c.saida && c.saida.length ? c.saida : null;
    var blocoAgora = c.estado === "erro"
      ? '<div class="tr__rot">a re-execução falhou</div>' +
        balao("dela", c.erro_execucao || "sem detalhe", "", "tr__b--agora")
      : c.estado === "calada"
        ? '<div class="tr__rot">ela não respondeu: ' + esc(c.erro_execucao || "a conversa saiu da mão dela") + "</div>"
        : blocos
          ? '<div class="tr__rot">o que ela responde</div>' +
            blocos.map(function (b) {
              return b.tipo === "fotos"
                ? balao("dela", "(" + b.fotos + (b.fotos === 1 ? " foto" : " fotos") + ")",
                        hora(c.rodado_em), "tr__b--agora tr__b--fotos")
                : balao("dela",
                        (b.para && b.para !== "quem escreveu" && b.para !== "o corretor"
                           ? "[para " + b.para + "] " : "") + b.texto,
                        hora(c.rodado_em), "tr__b--agora");
            }).join("")
          : agora.length
            ? '<div class="tr__rot">o que ela responde</div>' +
              agora.map(function (t) { return balao("dela", t, hora(c.rodado_em), "tr__b--agora"); }).join("")
            : '<div class="tr__rot">agora ela ficou calada</div>';

    /* AS FOTOS. `ela_respondeu_agora` guarda so texto -- as linhas de imagem
       da caixa de saida nunca chegavam aqui, e a tela dava a entender que ela
       nao tinha mandado foto nenhuma. Em 21/09 o Tel julgou um caso por isso.
       O Tel pediu "(fotos)", nao as fotos: o balao diz quantas e para. */
    var ja = fotosJaSairam(c);
    if (ja && c.estado === "rodado") {
      blocoAgora += balao("dela", ja.passo
          ? "(sem fotos aqui: as fotos do " + ja.cod + " já foram no passo " + ja.passo + " desta conversa)"
          : "(atenção: o card do " + ja.cod + " saiu sem nenhuma foto nesta conversa)",
        hora(c.rodado_em), ja.passo ? "tr__b--nota" : "tr__b--alerta");
    }
    var qFotos = Number(c.fotos_agora || 0);
    if (qFotos > 0 && c.estado !== "erro" && !blocos) {
      blocoAgora += balao("dela", "(" + qFotos + (qFotos === 1 ? " foto" : " fotos") + ")",
                          hora(c.rodado_em), "tr__b--agora tr__b--fotos");
    }

    var ferr = (c.ferramentas_agora || []).filter(function (f) { return f.charAt(0) !== "_"; });

    alvo.innerHTML =
      '<div class="tr__topo">' +
        '<span class="tr__ini">' + esc(iniciais(quem(c))) + "</span>" +
        "<span><h4>" + esc(quem(c) || "(sem nome)") + "</h4>" +
        "<small>" +
          '<span class="tr__rodada">' + etiqueta(c) + "</span> · " +
          (c.turno_origem ? "turno #" + esc(c.turno_origem) + " · " : "") + esc(quando(c.quando_original)) +
          (ferr.length ? " · " + esc(ferr.join(", ")) : "") + "</small></span>" +
      "</div>" +
      '<div class="tr__baloes">' + hist + foco + blocoAgora + "</div>" +
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
  /* ============================================== A BARRA DA RODADA ===== */
  function desenharProgresso() {
    var caixa = el("tr-progresso");
    var c = null;
    for (var i = 0; i < estado.ciclos.length; i++) {
      if (estado.ciclos[i].id === estado.atual) c = estado.ciclos[i];
    }
    if (!c) { caixa.hidden = true; return 0; }
    var total = Number(c.casos) || 0;
    var ok = Number(c.rodados) || 0;
    var erro = Number(c.com_erro) || 0;
    var feitos = ok + erro;
    var falta = Math.max(0, total - feitos);
    var pct = function (n) { return total ? (n * 100 / total).toFixed(2) + "%" : "0%"; };
    caixa.hidden = false;
    caixa.innerHTML =
      '<div class="tr-prog__topo">' +
        '<span class="tr-prog__titulo">' + esc(c.rotulo) + "</span>" +
        '<span class="tr-prog__conta">' + feitos + " <small>de " + total + " respondidas</small></span>" +
      "</div>" +
      '<div class="tr-prog__trilho" role="progressbar" aria-valuemin="0" aria-valuemax="' + total +
        '" aria-valuenow="' + feitos + '" aria-label="Conversas respondidas nesta rodada">' +
        '<span class="tr-prog__ok" style="width:' + pct(ok) + '"></span>' +
        '<span class="tr-prog__erro" style="width:' + pct(erro) + '"></span>' +
      "</div>" +
      '<div class="tr-prog__rodape">' +
        (falta
          ? '<span class="tr-prog__vivo">rodando agora</span><span>' + falta + " na fila</span>"
          : '<span class="tr-prog__fim">rodada concluída</span>') +
        "<span>" + ok + " responderam</span>" +
        (erro ? '<span style="color:#b4234a;font-weight:700">' + erro + " falharam ao rodar</span>" : "") +
        "<span>" + (Number(c.julgados) || 0) + " julgadas por você</span>" +
      "</div>";
    return falta;
  }

  function feitosDaAtual() {
    var n = null;
    estado.ciclos.forEach(function (c) {
      if (c.id === estado.atual) n = (Number(c.rodados) || 0) + (Number(c.com_erro) || 0);
    });
    return n;
  }

  /* Enquanto a rodada anda, pergunta o progresso de tempos em tempos e, se
     chegou resposta nova, recarrega os casos. Para sozinho quando acaba. */
  function acompanhar() {
    clearTimeout(estado.relogio);
    estado.relogio = setTimeout(function () {
      var antes = feitosDaAtual();
      buscar("/api/nai/treino/ciclos").then(function (j) {
        estado.ciclos = j.ciclos || [];
        var falta = desenharProgresso();
        if (feitosDaAtual() !== antes && naAtual()) carregarCasos(true);
        if (falta) acompanhar();
      }).catch(function () { acompanhar(); });
    }, ESPERA_MS);
  }

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
        return '<option value="' + c.id + '">' + esc(c.rotulo) +
               (c.fechado_em ? " (fechado)" : "") +
               " — " + c.julgados + "/" + c.casos + " julgados</option>";
      }).join("");
      // A rodada ATUAL, nao a primeira da lista (Tel, 21/09: "quero la na aba
      // treinamentos para eu julgar so as atuais"). Julgar conversa de ciclo
      // fechado e trabalho jogado fora: a solucao dele ja foi aplicada.
      var maisNova = estado.ciclos.reduce(function (a, b) { return b.id > a.id ? b : a; });
      estado.atual = maisNova.id;
      estado.ciclo = estado.ciclo || maisNova.id;
      sel.value = String(estado.ciclo);
      if (desenharProgresso()) acompanhar();
      el("tr-aviso").innerHTML = "";
      return estado.ciclo;
    });
  }

  /* `aoVivo` = recarga automatica durante a rodada. Nela a conversa aberta
     NAO e redesenhada se ele estiver escrevendo um julgamento -- senao o
     texto sumiria no meio da digitacao. */
  function carregarCasos(aoVivo) {
    if (!estado.ciclo || estado.carregando) return Promise.resolve();
    estado.carregando = true;
    return buscar("/api/nai/treino/casos?ciclo=" + estado.ciclo).then(function (j) {
      estado.casos = j.casos || [];
      // Na rodada atual, a resposta mais nova primeiro: e a que acabou de sair.
      if (naAtual()) {
        estado.casos.sort(function (a, b) {
          return String(b.rodado_em || "").localeCompare(String(a.rodado_em || "")) || b.id - a.id;
        });
      }
      var novos = {};
      var primeiraVez = !Object.keys(estado.vistos).length;
      estado.casos.forEach(function (c) {
        if ((c.estado === "rodado" || c.estado === "erro") && !estado.vistos[c.id]) {
          if (!primeiraVez) novos[c.id] = true;
          estado.vistos[c.id] = true;
        }
      });
      var lista = filtrados();
      if (!lista.some(function (c) { return c.id === estado.escolhido; })) {
        estado.escolhido = lista.length ? lista[0].id : null;
      }
      var conv = el("tr-conversa");
      var escrevendo = aoVivo && conv && document.activeElement && conv.contains(document.activeElement);
      desenharCartoes(); desenharLista(); desenharIndice();
      if (!escrevendo) desenharConversa();
      Object.keys(novos).forEach(function (id) {
        var b = document.querySelector('#tr-tabela [data-abrir="' + id + '"]');
        var linha = b && b.closest("tr");
        if (linha) linha.classList.add("tr__novo");
      });
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
      estado.historico = estado.ciclo !== estado.atual;
      estado.escolhido = null;
      carregarCasos();
    });
    // Historico: abre o seletor das rodadas antigas; fechar volta para a atual.
    el("tr-historico").addEventListener("click", function () {
      var caixa = el("tr-ciclo-caixa");
      var abrir = caixa.hidden;
      caixa.hidden = !abrir;
      this.setAttribute("aria-expanded", String(abrir));
      this.textContent = abrir ? "Voltar para a rodada atual" : "Histórico de rodadas";
      if (!abrir && estado.ciclo !== estado.atual) {
        estado.ciclo = estado.atual;
        estado.historico = false;
        estado.escolhido = null;
        el("tr-ciclo").value = String(estado.atual);
        carregarCasos();
      }
    });
    carregarCiclos().then(function (c) { if (c) carregarCasos(); });
  });
})();
