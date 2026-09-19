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

  function desenhar() {
    var alvo = el("fx-canvas");
    if (!alvo) return;
    var num = 0;
    var html = '<div class="fx__trilho">';

    GRUPOS.forEach(function (g, gi) {
      var d = vivo[g.setor] || {};
      var farol = d.semaforo || "cinza";
      html += '<div class="fx__grupo">';
      html += '<div class="fx__grupo-topo"><span class="fx__farol fx__farol--' + farol + '"></span>' + esc(g.titulo) + "</div>";
      html += '<div class="fx__coluna">';
      g.etapas.forEach(function (e, ei) {
        num++;
        html += '<div class="fx__linha">';
        html += '<button class="fx__etapa fx__etapa--' + e.tipo + '" type="button" aria-pressed="false" data-fx="' + gi + "." + ei + '">' +
                '<div><span class="fx__num">' + num + '</span><span class="fx__nome">' + esc(e.n) + "</span></div>" +
                '<div class="fx__onde">' + esc(e.onde) + "</div>" +
                (ei === 0 ? selo(g) : "") +
                "</button>";
        if (ei < g.etapas.length - 1 || gi < GRUPOS.length - 1) {
          html += '<div class="fx__seta"></div>';
        }
        html += "</div>";
      });
      html += "</div></div>";
    });

    html += "</div>";
    alvo.innerHTML = html;

    Array.prototype.forEach.call(alvo.querySelectorAll("[data-fx]"), function (b) {
      b.addEventListener("click", function () { abrir(b.getAttribute("data-fx")); });
    });
    var total = el("fx-total");
    if (total) total.textContent = num + " etapas";
  }

  function abrir(ref) {
    var alvo = el("fx-canvas");
    var p = ref.split("."), g = GRUPOS[+p[0]], e = g.etapas[+p[1]];
    Array.prototype.forEach.call(alvo.querySelectorAll("[data-fx]"), function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-fx") === ref ? "true" : "false");
    });
    escolhida = ref;
    var d = vivo[g.setor] || {};
    var h = "<h3>" + esc(e.n) + "</h3>";
    h += '<p class="fx__detalhe__onde">' + esc(e.onde) + "</p>";
    h += '<div class="fx__campo"><h4>O que acontece aqui</h4><p>' + esc(e.oque) + "</p></div>";
    if (e.erro) {
      h += '<div class="fx__campo"><h4>O que já deu errado</h4><p>' + esc(e.erro) + "</p></div>";
    }
    h += '<div class="fx__campo"><h4>Setor ' + esc(g.setor) + " — números de agora</h4>";
    if (d.passagens === undefined) {
      h += '<p class="fx__vazio">Sem medição para este setor ainda. Os números aparecem depois que os nós de trace do n8n forem instalados (passo 5).</p>';
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
    el("fx-detalhe").innerHTML = h;
  }

  function carregar() {
    fetch(API + "/api/nai/trace/setores")
      .then(function (r) { return r.json(); })
      .then(function (d) {
        (d.setores || []).forEach(function (s) { vivo[s.setor] = s; });
        desenhar();
        if (escolhida) abrir(escolhida);
      })
      .catch(function () { desenhar(); });
  }

  function iniciar() {
    if (!el("fx-canvas")) return;
    desenhar();
    carregar();
    var b = el("fx-recarregar");
    if (b) b.addEventListener("click", carregar);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else { iniciar(); }
})();
