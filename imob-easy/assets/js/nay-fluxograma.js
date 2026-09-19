/* ==========================================================================
   Cérebro da Nay — O FLUXOGRAMA
   O caminho que ela percorre TODA VEZ que responde alguém.

   A topologia aqui é o fluxo REAL do n8n `NaiAtendLocacao1` (69 nós, lidos do
   export em 19/09/2026) somada às funções do banco que cada nó chama. Está
   escrita à mão de propósito: o n8n diz o que cada nó É, não o que ele
   SIGNIFICA — e é o significado que precisa ser lido aqui.

   Os números vêm ao vivo de /api/nai/trace/setores.
   ========================================================================== */
(function () {
  "use strict";

  var API = window.API_BASE || "";

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function el(id) { return document.getElementById(id); }

  // ------------------------------------------------------------------
  // O MAPA. Cada etapa: o que é, onde mora, e o que já deu errado nela.
  // `onde` é o endereço para ir conferir: nó do n8n, função ou tabela.
  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // AS FASES. O nivel de cima: em que parte do pensamento ela esta.
  // `grupos` aponta para os indices de GRUPOS que caem em cada fase.
  // ------------------------------------------------------------------
  var FASES = [
    { id: "ouvir",     nome: "Ouvir",      resumo: "o que chegou, e o que isso quer dizer",       cor: "#6d28d9", grupos: [0, 1] },
    { id: "reconhece", nome: "Reconhecer", resumo: "quem e, e se ela pode falar com essa pessoa", cor: "#0e7490", grupos: [2, 3, 4] },
    { id: "pensa",     nome: "Pensar",     resumo: "o modelo decide, e consulta a base",          cor: "#b45309", grupos: [5, 6] },
    { id: "confere",   nome: "Conferir",   resumo: "as paredes, antes de qualquer coisa sair",    cor: "#9f1239", grupos: [7, 8] },
    { id: "fala",      nome: "Falar",      resumo: "a caixa de saida ate o WhatsApp",             cor: "#15803d", grupos: [9] },
    { id: "sozinha",   nome: "Fora da conversa", resumo: "o que roda sem ninguem escrever",       cor: "#4b5563", grupos: [10, 11] }
  ];

  function faseDoGrupo(gi) {
    for (var i = 0; i < FASES.length; i++) {
      if (FASES[i].grupos.indexOf(gi) >= 0) return FASES[i];
    }
    return FASES[FASES.length - 1];
  }

  var GRUPOS = [
    { setor: "entrada", titulo: "1. Entrada", etapas: [
      { n: "Chega a mensagem", tipo: "n8n", onde: "n8n · nó Webhook (v2.1)",
        oque: "A Z-API entrega a mensagem do WhatsApp no webhook do fluxo ANTIGO, que é a porta de entrada de tudo. O fluxo da NAI não tem porta própria — ele é chamado de lá.",
        erro: "Se a instância da Z-API cair ou o webhook mudar de endereço, nada chega e nenhum erro aparece em lugar nenhum." },
      { n: "Filtrar e normalizar", tipo: "n8n", onde: "n8n · nó Filtrar e normalizar (code, 122 linhas)",
        oque: "Descarta o que não é mensagem de gente: o eco da própria API, newsletter, transmissão, grupo. Normaliza telefone, nome e texto.",
        erro: "Ramo novo que não repete este filtro passa a processar o que a própria Nay enviou." },
      { n: "Foi o Tel pelo celular?", tipo: "parede", onde: "n8n · Foi o Tel pelo celular? → Espera 15s → nai_tel_assumiu()",
        oque: "Se a mensagem saiu do celular do Tel (fromMe sem fromApi), espera 15s para não confundir com o eco da API, e marca que ELE assumiu a conversa. A Nay cala por 30 minutos.",
        erro: "O carimbo caía na linha do @lid enquanto a conversa rodava na linha do telefone — 38 casos medidos. Consertado em 19/09 com nai_contato_irmaos()." },
      { n: "Gravar na fila", tipo: "sql", onde: "n8n · Gravar na fila → tabela mensagens",
        oque: "Grava a mensagem com status Recebido. É a fila de onde tudo sai." },
      { n: "Janela de espera", tipo: "n8n", onde: "n8n · Janela de 25s · nai_config.janela_segundos = 60",
        oque: "Espera para juntar mensagens que a pessoa quebrou em várias linhas. O nome do nó diz 25s, mas o valor real mora na config e hoje é 60s.",
        erro: "Reiniciar o n8n com carência menor que a janela MATA toda mensagem que estiver esperando. Use docker stop -t 75, nunca docker restart." },
      { n: "Reservar mensagens", tipo: "sql", onde: "n8n · Reservar mensagens",
        oque: "Pega o lote da janela e marca como Processando, para dois gatilhos não responderem a mesma coisa.",
        erro: "Cerca de 70% das mensagens ficam em Processando. Isso é o normal, não é fila presa." }
    ]},

    { setor: "entrada", titulo: "2. Mídia vira texto", etapas: [
      { n: "Detectar áudio", tipo: "n8n", onde: "n8n · Detectar audio (code, 12 linhas)",
        oque: "Vê se veio áudio no lote." },
      { n: "Baixar e transcrever", tipo: "modelo", onde: "n8n · Baixar audio → Transcrever (OpenAI whisper, pt)",
        oque: "Baixa o ogg da Z-API e transcreve para texto em português.",
        erro: "O Juntar mensagens roda duas vezes, e até 16/09 a transcrição era descartada na segunda rodada." },
      { n: "Detectar imagem", tipo: "n8n", onde: "n8n · Detectar imagem (code, 59 linhas)",
        oque: "Vê se veio foto ou documento no lote." },
      { n: "Ler a imagem", tipo: "modelo", onde: "n8n · Ler imagem (GPT) (httpRequest)",
        oque: "Manda a imagem ao modelo para descrever. É o que impede a Nay de responder que não consegue abrir.",
        erro: "Sem esta etapa ela dizia literalmente que não conseguia ver a imagem." },
      { n: "Juntar mensagens", tipo: "n8n", onde: "n8n · Juntar mensagens (code, 186 linhas)",
        oque: "Costura texto, transcrição do áudio e descrição da imagem numa mensagem só.",
        erro: "É o nó que roda DUAS vezes. Toda mudança aqui precisa aguentar rodar duas vezes sem estragar nada." }
    ]},

    { setor: "identidade", titulo: "3. Quem é a pessoa", etapas: [
      { n: "A chave", tipo: "sql", onde: "nai_chave() → nay_fone_chave()",
        oque: "Reduz o telefone a DDI + DDD + os 8 dígitos finais. É o que faz 5592981272285 e 559281272285 serem a MESMA pessoa.",
        erro: "O nono dígito quase derrubou a campanha inteira: lead gravado com 13 dígitos, Z-API entregando com 12, lead nunca encontrado." },
      { n: "Resolver o @lid", tipo: "sql", onde: "tabela identidade_lid · nai_contato_irmaos()",
        oque: "A mesma pessoa tem DUAS linhas em nai_contato: uma pelo telefone e outra pelo @lid do chat. Aqui as duas viram uma.",
        erro: "50 pares medidos em 19/09, e em 38 o carimbo do Tel estava só no lado do LID — por isso ela falava por cima dele." }
    ]},

    { setor: "porta", titulo: "4. A porta", etapas: [
      { n: "Quem atende?", tipo: "parede", onde: "nai_quem_atende(fone, grupo, texto)",
        oque: "Decide se quem responde é a NAI nova ou a Nay antiga.",
        erro: "TEM DUAS ASSINATURAS. A de 2 argumentos decide sem ler o texto da mensagem. Chamador antigo pega a regra velha e não dá erro nenhum." },
      { n: "Deve atender?", tipo: "parede", onde: "nai_deve_atender() → grava o motivo em nai_turno.porta",
        oque: "Decide se ela abre a boca, e registra POR QUÊ: contato novo falando de imóvel, conversa já liberada, conversa que o Tel assumiu, assunto que não é de corretor.",
        erro: "Em 7 dias, o motivo mais comum foi 'conversa que já existia: quem responde é o Tel' — 342 vezes." },
      { n: "Está na lista?", tipo: "parede", onde: "nai_pode_falar() · corretores.pode_falar · nai_lista_governa()",
        oque: "Desde 19/09 ela só atende corretor da lista: 1.449 pessoas. Quem tem visita aberta, cadastro ou captação em andamento passa mesmo estando fora.",
        erro: "Quem está fora e pergunta de imóvel gera uma pergunta ao Tel. Quem está fora e escreve outra coisa some em silêncio." },
      { n: "O Tel está na conversa?", tipo: "parede", onde: "nai_tel_com_a_conversa() · nai_config.gap_tel_min = 30",
        oque: "Se o Tel escreveu nos últimos 30 minutos, ela cala. Se a conversa foi escalada, ela cala até ele mandar DEVOLVER." }
    ]},

    { setor: "cabecalho", titulo: "5. O cabeçalho", etapas: [
      { n: "Abrir turno", tipo: "sql", onde: "nai_abrir_turno() → tabela nai_turno",
        oque: "Abre a rodada de conversa, define o PAPEL (corretor, proprietário, motoboy, Tel), acha o imóvel em foco e monta o contexto da conversa.",
        erro: "Só dá papel de proprietário a quem tem visita ABERTA. Dono de imóvel sem visita aberta entra como corretor." },
      { n: "Montar o prompt", tipo: "modelo", onde: "tabela nai_prompt (corretor 9.502b · proprietário 2.239b · Fernando 813b)",
        oque: "O prompt vem do BANCO e é editável no painel, sem deploy. Vale já na mensagem seguinte.",
        erro: "Se vier NULL, o nó cai num prompt de RESERVA escondido dentro dele (4.733 caracteres) que o painel não mostra e ninguém versionou." },
      { n: "Rotear pelo cabeçalho", tipo: "n8n", onde: "n8n · Rotear pelo cabeçalho (code, 100 linhas)",
        oque: "Lê o que o Abrir turno devolveu e escolhe por qual das 8 saídas seguir." },
      { n: "Qual caminho?", tipo: "n8n", onde: "n8n · Qual caminho? (switch, 8 saídas)",
        oque: "As 8 saídas: corretor · card do código · cortesia · proprietário · Fernando · comando de visita · comando do Tel · aviso no teste." }
    ]},

    { setor: "modelo", titulo: "6. O modelo pensa", etapas: [
      { n: "O agente", tipo: "modelo", onde: "n8n · NAI (corretor) / (proprietário) / (Fernando) — agent v3.1",
        oque: "Três agentes, um por papel. Cada um com seu prompt, sua memória e suas ferramentas." },
      { n: "O modelo", tipo: "modelo", onde: "n8n · GPT (corretor) — lmChatOpenAi · modelo gpt-5.6-sol",
        oque: "É OpenAI gpt-5.6-sol nos três agentes. Sem temperature e sem maxTokens definidos — usa o padrão do nó.",
        erro: "O CLAUDE.md diz Claude Haiku 4.5 com temperatura 0.2. A documentação está errada; o que está no ar é o gpt." },
      { n: "A memória", tipo: "sql", onde: "n8n · Memória (corretor) — memoryPostgresChat · tabela nai_memoria",
        oque: "Guarda a conversa para ela não perguntar duas vezes a mesma coisa.",
        erro: "Quando ela inventa um dado, nai_memoria é o primeiro lugar a olhar — foi assim que se descobriu o valor inventado na conversa do Gustavo." }
    ]},

    { setor: "ferramenta", titulo: "7. As ferramentas (17)", etapas: [
      { n: "Achar imóvel", tipo: "sql", onde: "imovel_por_codigo · buscar_por_perfil · listar_no_condominio · disponibilidade_no_condominio · resumo_do_condominio",
        oque: "As cinco formas de achar imóvel: pelo código, por perfil (bairro e faixa de valor), e pelo nome do condomínio.",
        erro: "Em nay_buscar_por_perfil, negócio vazio cai em VENDA. E não existe coluna de finalidade: venda x locação é adivinhado de valor_venda e valor_aluguel estarem preenchidos." },
      { n: "Saber do imóvel", tipo: "sql", onde: "o_que_sei_do_imovel · guardar_do_imovel · imovel_do_disparo",
        oque: "Responde pergunta sobre um imóvel (mobília, andar, vaga, IPTU, financiamento) e guarda o que o Tel ensinar na conversa." },
      { n: "A visita", tipo: "sql", onde: "pedir_visita · guardar_dados_da_visita · mudar_horario_da_visita · responder_horario_do_proprietario · resultado_da_visita",
        oque: "Todo o ciclo: pedir a visita, coletar nome, CPF e CRECI, remarcar horário e registrar como foi." },
      { n: "Escalar ao Tel", tipo: "parede", onde: "escalar_ao_tel → nai_escalar()",
        oque: "Quando a resposta não está na base, avisa o Tel e se cala naquele chat. Ela responde SILENCIO.",
        erro: "Pedido de perfil NUNCA deve escalar — tem que acionar a busca. Escalar ali é o sintoma de que o gatilho da busca não pegou." },
      { n: "A descrição é prompt", tipo: "parede", onde: "n8n · toolDescription de cada ferramenta",
        oque: "O texto que descreve cada ferramenta é o que faz o modelo chamar ou não chamar. Não aparece em nenhum painel.",
        erro: "O listar_no_condominio está com a descrição padrão do n8n colada na frente: 'Execute a SQL query in Postgres' + a descrição de verdade." }
    ]},

    { setor: "conferencia", titulo: "8. A esteira", etapas: [
      { n: "Achar código na resposta", tipo: "n8n", onde: "n8n · Achar codigo na resposta (code, 43 linhas)",
        oque: "Procura 'Código: NNNN' no que o modelo escreveu, para saber de qual imóvel mandar foto." },
      { n: "Fotos faltando?", tipo: "sql", onde: "n8n · Fotos faltando? → nai_fotos_faltando() → Buscar fotos no site",
        oque: "Se o imóvel não tem foto no banco, busca no anúncio do site na hora." },
      { n: "As 17 conferências", tipo: "parede", onde: "nai_enfileirar_resposta() → nai_conferir_resposta() → tabela nai_conferencia",
        oque: "Cada resposta passa por 17 checagens antes de sair. Umas são PAREDE (barram a resposta), outras só ajustam a forma. Cada passagem fica registrada com o resultado.",
        erro: "10 das 17 nunca agiram desde 14/09. A que mais age é 'de qual imóvel é a conversa', que corrige 61% das respostas." }
    ]},

    { setor: "montagem", titulo: "9. Montagem", etapas: [
      { n: "Card e fotos", tipo: "sql", onde: "nai_enfileirar_card() · nai_imagens_do_envio()",
        oque: "Quando o corretor manda só o código: o card com as informações vem PRIMEIRO, depois as fotos, com a colagem na frente.",
        erro: "Quando o modelo decide mandar foto no meio da conversa, cai no ramo SEM CARD e as fotos saem sem informação nenhuma junto." },
      { n: "Depois das fotos", tipo: "sql", onde: "nai_depois_das_fotos()",
        oque: "As frases que fecham o bloco: a sugestão de visita e o convite a pedir mais imóveis." },
      { n: "Quebrar em balões", tipo: "sql", onde: "nai_enfileirar_texto() → tabela nai_saida",
        oque: "Cada frase vira uma linha em nai_saida, na ordem, para sair como balões separados no WhatsApp." }
    ]},

    { setor: "saida", titulo: "10. A caixa de saída", etapas: [
      { n: "O gatilho da inserção", tipo: "parede", onde: "gatilho nai_saida_validar na tabela nai_saida",
        oque: "Recusa linha cujo destino não seja parte daquele turno ou daquela visita. O telefone nunca vem de quem enfileira: sai de nai_contato pelo id. Foto só entra se a URL pertencer, no banco, ao código declarado.",
        erro: "É a parede que impede mandar a foto de um imóvel dentro do card de outro." },
      { n: "Liberar saída", tipo: "parede", onde: "nai_liberar_saida()",
        oque: "Na hora de mandar, confere tudo de novo: modo, pausa, contato mudou, o Tel assumiu, foto não confere, mensagem repetida em 10 minutos, modo teste.",
        erro: "A trava de repetida só olhava estado 'enviado'. Duas levas a 16 segundos de distância passavam as duas — 14 fotos para a mesma pessoa. Fechado em 19/09." },
      { n: "Proprietário vai pro Tel", tipo: "parede", onde: "nai_config.proprietario_pelo_tel = sim",
        oque: "TEMPORÁRIO: o que iria para o dono do imóvel vai para o Tel, com o nome e o número de quem ligar e o comando VISITA <id> OK para responder de volta." },
      { n: "Conferir cabeçalho", tipo: "n8n", onde: "n8n · Conferir cabeçalho (code, 28 linhas)",
        oque: "Recalcula a chave do destino em JavaScript, com outra implementação, e compara com a do banco. Se divergir, não manda.",
        erro: "É a terceira camada da mesma parede. As três existem porque mandar mensagem para a pessoa errada não tem desfazer." },
      { n: "Enviar", tipo: "saida", onde: "n8n · Pode enviar? → Enviar Z-API → Confirmar envio",
        oque: "Manda pela Z-API e grava o messageId. Se não puder, grava o motivo em nai_saida.bloqueio.",
        erro: "Ler o TEXTO de nai_saida não é ler o ESTADO dela. Texto perfeito com estado 'bloqueado' nunca saiu para ninguém." }
    ]},

    { setor: "agenda", titulo: "11. A agenda (roda sozinha)", etapas: [
      { n: "Todo minuto", tipo: "n8n", onde: "n8n · Agenda (todo minuto) — scheduleTrigger",
        oque: "Um gatilho por minuto, independente de alguém escrever alguma coisa." },
      { n: "O que está devendo", tipo: "sql", onde: "n8n · Agenda da NAI → nai_agenda_tick()",
        oque: "Lembrete de visita, cobrança dos dados que faltam, aviso ao Fernando, aviso ao Tel, pós-visita e devolver a chave." },
      { n: "Volta pela saída", tipo: "sql", onde: "→ Liberar saída (a mesma do passo 10)",
        oque: "O que a agenda gera passa pelas MESMAS paredes da resposta. Não existe atalho para o WhatsApp." }
    ]},

    { setor: "comandos", titulo: "12. Comandos do Tel", etapas: [
      { n: "Comando do Tel", tipo: "sql", onde: "n8n · Comando do Tel (code, 113 linhas) → nai_comando_tel()",
        oque: "VISITAS · AGENDA DE VISITAS · VISITA id OK/CANCELA/REMARCA/HORARIO/AVISA/FERNANDO OK · ACESSO · ASSUMIR · DEVOLVER · PARAR e VOLTAR ATENDIMENTO · CORRETOR e NAO CORRETOR.",
        erro: "O bloco do Tel vem ANTES da checagem de pausa — é o que permite religar a Nay pelo WhatsApp depois de PARAR ATENDIMENTO. Inverter essa ordem tranca ele do lado de fora." }
    ]}
  ];

  // ------------------------------------------------------------------
  // Desenho
  // ------------------------------------------------------------------
  var vivo = {};
  var escolhida = null;

  function selo(g) {
    var d = vivo[g.setor];
    if (!d) return '<span class="fx__selo fx__selo--mudo">sem dado</span>';
    if (!d.passagens) return '<span class="fx__selo fx__selo--mudo">nunca passou</span>';
    var cls = d.semaforo === "vermelho" ? "ruim" : d.semaforo === "amarelo" ? "alerta" : "ok";
    return '<span class="fx__selo fx__selo--' + cls + '">' + d.passagens + " passagens</span>";
  }

  var PLANO = [];   // a lista achatada, na ordem de execucao

  function achatar() {
    PLANO = [];
    GRUPOS.forEach(function (g, gi) {
      g.etapas.forEach(function (e, ei) {
        PLANO.push({ g: g, e: e, gi: gi, ei: ei, passo: PLANO.length + 1 });
      });
    });
  }

  function desenhar() {
    var alvo = el("fx-canvas");
    if (!alvo) return;
    achatar();

    // Tres niveis: FASE (faixa colorida) > SETOR (regiao tracejada) > ETAPA.
    // A corda atravessa os tres, e a ordem continua sendo a posicao.
    var html = '<div class="fx__trilho"><div class="fx__corda"></div>';
    var passo = 0;

    FASES.forEach(function (f) {
      html += '<div class="fx__fase fx__fase--' + f.id + '">';
      html += '<div class="fx__fase-topo">' + esc(f.nome) +
              " <small>" + esc(f.resumo) + "</small></div>";
      html += '<div class="fx__fase-corpo">';

      f.grupos.forEach(function (gi) {
        var g = GRUPOS[gi];
        if (!g) return;
        var d = vivo[g.setor] || {};
        html += '<div class="fx__grupo">';
        html += '<div class="fx__grupo-topo"><span class="fx__farol fx__farol--' +
                (d.semaforo || "cinza") + '"></span>' + esc(g.titulo) +
                (d.passagens ? ' <span class="fx__conta">' + d.passagens + "x</span>" : "") +
                "</div>";
        html += '<div class="fx__cards">';
        g.etapas.forEach(function (e, ei) {
          passo++;
          if (ei > 0) html += '<div class="fx__vao"></div>';
          html += '<button class="fx__etapa fx__etapa--' + e.tipo + '" type="button"' +
                  ' aria-pressed="false" data-fx="' + gi + "." + ei + '"' +
                  ' title="Passo ' + passo + ": " + esc(e.n) + '">' +
                  '<div class="fx__cab"><span class="fx__num">' + passo + "</span>" +
                  '<span class="fx__nome">' + esc(e.n) + "</span></div>" +
                  '<div class="fx__onde">' + esc(e.onde) + "</div>" +
                  "</button>";
        });
        html += "</div></div>";
      });

      html += "</div></div>";
    });

    html += "</div>";
    alvo.innerHTML = html;

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-fx]"), function (b) {
      b.addEventListener("click", function () { abrir(b.getAttribute("data-fx")); });
    });
    var total = el("fx-total");
    if (total) {
      total.textContent = PLANO.length + " etapas em " + FASES.length +
        " fases, na ordem em que acontecem";
    }
  }

  function abrir(ref, semRolar) {
    var alvo = el("fx-canvas");
    var p = ref.split("."), gi = +p[0], ei = +p[1];
    var g = GRUPOS[gi], e = g.etapas[ei];
    var item = PLANO.filter(function (x) { return x.gi === gi && x.ei === ei; })[0] || { passo: "?" };

    var botoes = alvo.querySelectorAll("[data-fx]");
    Array.prototype.forEach.call(botoes, function (b) {
      var meu = b.getAttribute("data-fx") === ref;
      b.setAttribute("aria-pressed", meu ? "true" : "false");
      if (meu && !semRolar && b.scrollIntoView) {
        b.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
      }
    });
    escolhida = ref;

    var d = vivo[g.setor] || {};
    var f = faseDoGrupo(gi);
    var h = '<h3><span class="fx__passo">passo ' + item.passo + " de " + PLANO.length + "</span>" +
            '<span class="fx__fita" style="background:' + f.cor + '">' + esc(f.nome) + "</span>" +
            esc(e.n) + "</h3>";
    h += '<p class="fx__detalhe__onde">' + esc(e.onde) + "</p>";
    h += '<div class="fx__campo"><h4>O que acontece aqui</h4><p>' + esc(e.oque) + "</p></div>";
    if (e.erro) {
      h += '<div class="fx__campo"><h4>O que já deu errado</h4><p>' + esc(e.erro) + "</p></div>";
    }
    h += '<div class="fx__campo"><h4>Setor ' + esc(g.setor) + " &mdash; números de agora</h4>";
    if (d.passagens === undefined) {
      h += '<p class="fx__vazio">Sem medição para este setor ainda. Os números aparecem ' +
           "depois que os nós de trace do n8n forem instalados (passo 5).</p>";
    } else {
      h += '<div class="fx__numeros">' +
        '<div class="fx__numero"><b>' + (d.passagens || 0) + "</b><span>passagens</span></div>" +
        '<div class="fx__numero"><b>' + (d.paradas || 0) + "</b><span>paradas</span></div>" +
        '<div class="fx__numero"><b>' + (d.erros || 0) + "</b><span>erros</span></div>" +
        '<div class="fx__numero"><b>' + (d.funcoes || 0) + "</b><span>funções</span></div>" +
        '<div class="fx__numero"><b>' + (d.da_ia_antiga || 0) + "</b><span>da Nay antiga</span></div>" +
        "</div>";
    }
    h += "</div>";

    // Andar pelo caminho sem precisar cacar o cartao no meio da corda.
    var i = PLANO.indexOf(item);
    h += '<div class="fx__nav">';
    if (i > 0) {
      var a = PLANO[i - 1];
      h += '<button class="btn-mini" type="button" data-fx-ir="' + a.gi + "." + a.ei +
           '">&larr; ' + esc(a.e.n) + "</button>";
    }
    if (i > -1 && i < PLANO.length - 1) {
      var b2 = PLANO[i + 1];
      h += '<button class="btn-mini" type="button" data-fx-ir="' + b2.gi + "." + b2.ei +
           '">' + esc(b2.e.n) + " &rarr;</button>";
    }
    h += "</div>";

    var caixa = el("fx-detalhe");
    caixa.innerHTML = h;
    Array.prototype.forEach.call(caixa.querySelectorAll("[data-fx-ir]"), function (b) {
      b.addEventListener("click", function () { abrir(b.getAttribute("data-fx-ir")); });
    });
  }

  function carregar() {
    fetch(API + "/api/nai/trace/setores")
      .then(function (r) { return r.json(); })
      .then(function (d) {
        (d.setores || []).forEach(function (s) { vivo[s.setor] = s; });
        desenhar();
        if (escolhida) abrir(escolhida, true);
      })
      .catch(function () { desenhar(); });
  }

  // ------------------------------------------------------------------
  // EXPORTAR
  // Junta num arquivo so: o mapa em portugues (o que cada etapa significa),
  // os numeros ao vivo, e o fluxo REAL do n8n com os 69 nos e as ligacoes.
  //
  // O export do n8n tem token da Z-API dentro dos nos. O arquivo servido em
  // admin/dados/ ja sai REDIGIDO -- token, clientToken, apiKey, Bearer e o
  // id da instancia viram [REDIGIDO]. E para poder mandar para outra IA sem
  // mandar a credencial junto.
  // ------------------------------------------------------------------
  function exportar() {
    var botao = el("fx-exportar");
    if (botao) { botao.disabled = true; botao.textContent = "Montando…"; }

    // O arquivo mora em admin/dados/ e NAO em assets/: /assets e publico, e o
    // fluxo inteiro (queries, prompts, a logica toda) nao deve ficar baixavel
    // por qualquer um. Em admin/ ele herda a senha do painel.
    Promise.all([
      fetch("dados/nai-fluxo-n8n.json").then(function (r) {
        return r.ok ? r.json() : null;
      }).catch(function () { return null; }),
      fetch(API + "/api/nai/trace/regras").then(function (r) {
        return r.ok ? r.json() : null;
      }).catch(function () { return null; })
    ]).then(function (res) {
      var n8n = res[0], regras = res[1];
      achatar();

      var pacote = {
        gerado_em: new Date().toISOString(),
        o_que_e: "O caminho que a Nay de Locacao percorre para responder uma mensagem. " +
                 "Tres camadas: o mapa em portugues (o que cada etapa significa), os numeros " +
                 "medidos, e o fluxo real do n8n.",
        aviso_de_seguranca: n8n
          ? "O fluxo do n8n vem com as credenciais REDIGIDAS: token, clientToken, apiKey, " +
            "Bearer e o id da instancia da Z-API foram substituidos por [REDIGIDO]."
          : "O fluxo do n8n NAO pode ser lido agora (arquivo admin/dados/nai-fluxo-n8n.json " +
            "ausente). O pacote saiu so com o mapa e os numeros.",

        mapa_do_caminho: {
          total_de_etapas: PLANO.length,
          etapas: PLANO.map(function (x) {
            return {
              passo: x.passo,
              grupo: x.g.titulo,
              setor: x.g.setor,
              etapa: x.e.n,
              tipo: x.e.tipo,
              onde_fica: x.e.onde,
              o_que_acontece: x.e.oque,
              o_que_ja_deu_errado: x.e.erro || null
            };
          })
        },

        medicao_por_setor: Object.keys(vivo).map(function (k) { return vivo[k]; }),
        regras: regras || null,
        fluxo_n8n: n8n || null
      };

      var nome = "nay-locacao-fluxo-" +
        new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "") + ".json";
      var blob = new Blob([JSON.stringify(pacote, null, 2)], { type: "application/json" });
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url; a.download = nome;
      document.body.appendChild(a); a.click(); document.body.removeChild(a);
      setTimeout(function () { URL.revokeObjectURL(url); }, 2000);

      if (botao) {
        botao.disabled = false;
        botao.textContent = n8n ? "Exportar JSON" : "Exportar JSON (sem o n8n)";
      }
    });
  }

  function iniciar() {
    if (!el("fx-canvas")) return;
    desenhar();
    carregar();
    var b = el("fx-recarregar");
    if (b) b.addEventListener("click", carregar);
    var x = el("fx-exportar");
    if (x) x.addEventListener("click", exportar);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else { iniciar(); }
})();
