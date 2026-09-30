# A Nay em produção: entrevista técnica (29/09/2026)

Respostas às 62 perguntas da entrevista, medidas no banco `naydb`, no n8n e no servidor de produção em 29/09/2026, entre 19h e 21h (Manaus). Tudo foi lido em modo só leitura: transação `read_only` no Postgres, sqlite do n8n aberto como `OPEN_READONLY`, nenhum restart e nenhum commit.

**Como ler**
- **FATO** é o que foi visto no código vivo (`pg_get_functiondef`), no banco, no JSON do workflow exportado de produção ou no log, sempre com o lugar de onde veio.
- **[OPINIÃO]** vem marcada. O bloco 12 é todo opinião.
- **NÃO SEI** diz o que teria que ser olhado para saber.
- Telefones aparecem só com os 4 últimos dígitos, pessoas só com o primeiro nome. Não há token, senha nem URL de instância da Z-API.
- Quando a pergunta partia de uma premissa que não vale mais em produção, a resposta começa corrigindo a premissa. Os casos mais importantes: são 60 casos na bateria, não 15; 36 etapas de conferência, não 17; o Jev não escolhe mais o atendente desde 25/09; o acompanhante é o André, não o Fernando; nenhuma visita real chegou ao proprietário.
- Horários em Manaus. O sqlite do n8n grava em UTC, e onde isso importa a resposta converte.
- Alguns números aparecem em mais de um bloco com recortes diferentes, e quando isso acontece o recorte está dito. Exemplo: funções fora do repositório são 41 contando só o `nayia` e 19 contando também o repositório do publicador.


---

## Bloco 1: o caminho de uma mensagem

Fontes usadas em todo o bloco: os dois workflows exportados (`wf_sQuiEjbEDMEbjX5U.json`, `wf_NaiAtendLocacao1.json`), a versão VIVA das funções (`pg_get_functiondef`), as tabelas `nai_turno`, `nai_saida`, `mensagens`, `nai_jev`, `nai_mente`, `nai_turno_decisao`, `nai_conferencia`, e 8 execuções do n8n lidas pelo id (142098, 142858, 142862, 143364, 143387, 143446, 143689, mais 143772/143789 do fluxo antigo). O histórico do n8n só vai de 29/09 13:57 a 19:30 (Manaus), porque `EXECUTIONS_DATA_PRUNE_MAX_COUNT=2000`. Horários em Manaus.

Gatilhos que existem nas tabelas do caminho (`pg_trigger`, todos ligados): em `mensagens`, `mensagens_uma_vez_so` (BEFORE INSERT) e `mensagens_espera_a_rajada` (BEFORE UPDATE OF status); em `nai_saida`, `nai_saida_validar` (BEFORE INSERT) e `nai_saida_imutavel` (BEFORE UPDATE); em `nai_turno`, `nai_turno_pergunta_corretor` (AFTER INSERT, só quando `porta = 'fora da lista: perguntou de imovel, perguntar ao Tel'`).

### 1. "tem o 5717?" no privado: o caminho inteiro

**Premissas a corrigir antes:**
- O nó "Janela de 25s" do fluxo NAI **não espera 25 s**. Ele espera `$('Gravar na fila').first().json.janela`, que é `nai_janela_segundos(telefone)`: hoje 20 s (`nai_config.janela_segundos`) e 15 s para os números de teste. O nome ficou de uma versão antiga. Só o nó homônimo do fluxo antigo espera 25 s fixos.
- "Enfileirar resposta" não chama `nai_enfileirar_resposta`. Ele chama `nai_enfileirar_resposta_ferramentas`, que registra as ferramentas usadas, corta códigos e só depois chama `nai_enfileirar_resposta`.
- "tem o 5717?" **não** pega o atalho sem modelo. O atalho (`rota: 'codigo'`) só vale para texto que é exatamente um número de 3 a 5 dígitos (`/^\d{3,5}$/` em "Rotear pelo cabeçalho"). Com "tem o" na frente, a mensagem vai para a mente (Jev) e para o agente.

**Fluxo antigo "Nay- recebe mensagem"** (é ele que recebe o webhook da Z-API):
1. "Webhook" (path `13d4116a-…`).
2. "NAI ou Nay? (quem atende)": `SELECT nai_quem_atende(phone, isGroup||isNewsletter||broadcast, texto||legenda)`. Com `nai_config.modo='todos'` a resposta é `'nai'` para qualquer conversa privada. O nó tem `onError: continueRegularOutput`; se a SQL falhar, `atende` fica vazio e a mensagem cai no caminho antigo.
3. "Vai para a NAI?": testa `atende == 'nai'`.
4. "Mandar para a NAI": POST do corpo cru da Z-API em `http://127.0.0.1:5678/webhook/nai-atendimento-locacao`, com timeout de 10 s. Na saída de erro fica "Prazo estourado? (a NAI recebeu)": se o erro for timeout, a execução para ali, porque a NAI recebeu mesmo assim. Com qualquer outro erro, a mensagem volta para o caminho antigo.

**Fluxo "NAI atendimento locação"**, na ordem em que roda de verdade (runData da execução 142098):
1. "Webhook". Ele liga em "Filtrar e normalizar" e em "Espelhar no CRM", mas pela ordem de execução do n8n o "Espelhar no CRM" só roda **no fim da execução**, cerca de 80 s depois na 142098.
2. "Filtrar e normalizar" (JS): descarta grupo, newsletter, broadcast, status e qualquer `type` diferente de `ReceivedCallback`. Classifica `origem` (reação, figurinha, áudio, imagem, documento, vídeo, texto), marca `saindo = fromMe||fromApi` e `tel_celular = fromMe`, e pega `citadoId = referenceMessageId` e a `midia_url`.
3. "Gravar na fila": `INSERT INTO mensagens (… fluxo='nai', status 'Recebido')`.
   - O gatilho `mensagens_uma_vez_so` descarta cópia do mesmo `message_id` (hexa maiúsculo) gravada há menos de 2 dias (`RETURN NULL`, e a cópia fica em `mensagem_repetida`). No eco, o descarte vale por fluxo.
   - O nó também roda `nay_sincronizar_nome` e `nay_congelar_lembretes` e devolve `janela = nai_janela_segundos()`.
   - `WHERE ins.direcao='recebida'`: o eco para aqui.
4. "Janela de 25s": espera 20 s.
5. "Reservar mensagens": `UPDATE mensagens SET status='Processando' WHERE telefone=$1 AND status='Recebido' AND fluxo='nai'`.
   - O gatilho `mensagens_espera_a_rajada` devolve NULL em todas as linhas enquanto houver mensagem 'Recebido' da pessoa mais nova que `janela-1` s. A execução de uma mensagem que não é a última reserva zero linhas e morre; a execução da última junta a rajada.
   - Para cada mensagem o nó calcula `nay_nome_de_pessoa`, `nay_pede_localizacao_da_unidade`, `nay_pede_visita`, `nay_aviso_do_foco`, `nay_deve_mandar_fotos`, `nay_negocio_pedido`, `nay_codigos_citados` (aqui dá `['5717']`), `nay_imovel_da_citacao(citado_id)` e `nay_opcoes_da_citacao`.
6. "Juntar mensagens" (JS): junta os textos e produz `codigosDele`, `codigoCitado`, `pedeVisita`, `vaoSairFotos`, `negocioPedido` e `qtd`.
   - Se houver mídia no webhook, espera "Transcrever" ou "Ler imagem (GPT)".
   - Detecta card colado (`Código: NNNN` com 📍 ou •) e embrulha o texto com "NAO mande esse card de volta".
7. "Detectar audio" e "Detectar imagem": sem mídia devolvem vazio. Olham **só o corpo do webhook desta execução**.
8. "Abrir turno": `nai_abrir_turno(tel, nome, textoCru, citadoId, ids)`. É aqui que o banco decide quem fala e se ela responde.
   - Monta a chave. Se o `modo` não for teste nem todos, devolve `ok=false`.
   - Corrige nomes (`nai_corrigir_nomes`), salvo para quem pode comandar.
   - Se `nai_tel_com_a_conversa`, grava `status='Com o Tel'` e devolve `ok=false, motivo='tel_assumiu'`.
   - Define o papel: tel pela voz ou comando, motoboy, proprietário com visita aberta, senão corretor.
   - Calcula `aprovado` (em `corretores`) e `primeira_vez`.
   - A **porta** é `nai_deve_atender(tel, texto, código citado)`. Para "tem o 5717?" o resultado costuma ser "conversa ja liberada" ou "conversa que ela ja estava atendendo". Numa conversa antiga ainda não liberada, o código existente abre a porta como "colou o card de um imovel nosso" e grava `liberado_em`. Fora da lista de corretores (`so_corretor_da_lista='sim'`) o resultado é "fora da lista…" e ela fica calada.
   - `pausado` vem de `nai_cfg('pausada')`.
   - Faz INSERT em `nai_turno` e chama `nai_etapa_atualizar`.
   - Devolve o cabeçalho `cab`: prompt de `nai_prompt_de('corretor')` (10.294 caracteres), `contexto` (etapa + `nai_contexto` + gíria), chave de memória `nai:corretor:<id>`, `esperando_valor`, `vocativo`, `comando_nai` e `atende` (com `regra_publico='sim'`, `atende` é o que a porta decidiu).
9. "Rotear pelo cabeçalho" (JS):
   - `ok≠true`: para.
   - Papel tel: comando ou agente.
   - `pausado≠false`: para.
   - Proprietário ou motoboy: rota própria.
   - Corretor com `atende===false`: para.
   - Número puro sem `esperando_valor`: `codigo`.
   - O resto: `agente`. "tem o 5717?" cai aqui.
10. "Precisa da mente?": só `rota=='agente'` passa.
11. "Ler estado": `nai_estado_v2(contato, 3)` devolve foco, mostrados, recusados, última fala dela e as 3 últimas trocas.
12. "Montar pergunta ao Jev" (JS): monta o estado e 6 perguntas: `intencao` (8 opções), `codigo_quer`, `codigo_rejeita`, `oferta`, `cortesia` e `o_que_mandou`. Os candidatos são o foco, os códigos que ele escreveu e os já mostrados, no máximo 8.
13. "Jev decide": POST `openrouter.ai/api/alpha/decisions`, modelo `typesafe/jev-1.13`, timeout 25 s, `onError` segue em frente.
14. "Ler o Jev": empacota as respostas. Se o Jev cair, calcula uma "reserva" por regex, mas o campo `atendente` dessa reserva **não é usado**: o nó seguinte só lê `$json.jev`, que chega vazio.
15. "Decidir quem responde" roda quatro coisas:
   - `nai_decidir_com_jev` grava em `nai_jev`: cortesia ≥ 0,70 dá `locacao`; oferta ≥ 0,60 ou foto de anúncio dele dá `secretaria`; o resto segue o campo `atendente` do Jev. **Esse campo não existe mais:** o nó "Montar pergunta ao Jev" parou de perguntar `atendente` e `pedido`. Nenhuma resposta em `nai_jev` tem essas chaves desde 25/09 08:34 (494 respostas em 3 dias, 0 com elas). Por isso `nai_mente.motivo` sai "sem resposta (0.00) …" em 406 de 494 turnos, e o resto sempre dá `locacao`. O script do repositório `Arquivos/nai/montar_fluxo_jev.py` ainda monta a pergunta `atendente`, então **o repositório diverge do n8n**.
   - `nai_mente_registrar` aplica as paredes: cortesia segue com quem atendia nas últimas 6 h; ficha de cadastro aberta vai para a secretária; oferta ou link vai para a secretária. Grava `nai_turno.atendente` e `nai_mente`.
   - `nai_decidir_v2` grava a intenção em `nai_turno_decisao`, com piso de 0,60.
   - `nai_pediu_imovel` e o `prompt_secretaria`.
16. "Rota da mente" e depois "Qual caminho?": vai para `agente` ou `secretaria`.
17. "NAI (corretor)": agente do LangChain.
   - System prompt: `cab.prompt`. Se vier com menos de 500 caracteres, o nó lança erro.
   - Mensagem do usuário: hora de Manaus, vocativo, nome, citação, "as fotos VAO/NAO sair", `cab.contexto` e o texto.
   - Memória: "Memória (corretor)", tabela `nai_memoria`, chave `cab.memoria`, últimas 20 mensagens.
   - Modelo: "GPT (corretor)" = `gpt-5.6-sol`. São 16 ferramentas.
   - Para "tem o 5717?" o caminho esperado é chamar `imovel_por_codigo(5717)`. Essa ferramenta devolve o card de `nai_card_do_imovel`, que é o card do grupo lido em `imovel_ficha` se tiver menos de 26 h e o preço bater, senão o do banco. Também devolve uma instrução sobre administrado, forma de pagamento e descrição.
18. "Achar codigo na resposta" (JS): pega todos os `Código: NNNN` da resposta. Sem nenhum, usa a citação, o `codigoCitado`, o código escrito por ele ou `codigosDele`. Se `pediu_imovel===false`, devolve `['0']`. Isso nunca acontece hoje: `nai_pediu_imovel` vira `coalesce(nai_jev_pedido(), true)`, e como o Jev não recebe mais a pergunta `pedido`, o resultado é sempre `true`.
19. "Fotos faltando?": `nai_fotos_faltando(códigos)` lista os imóveis publicados, que não são de parceria e não têm linha em `imovel_fotos`. "Buscar fotos no site" lê até 3 anúncios em imobeasy.com (15 s por anúncio).
20. "Enfileirar resposta": `nai_enfileirar_resposta_ferramentas`.
   - Carimba `nai_turno.ferramentas`. Parede 1: sem ferramenta de imóvel, corta os códigos. Parede 2: tira código já recusado.
   - Atualiza o estado da conversa.
   - Chama `nai_enfileirar_resposta`, que roda `nai_conferir_resposta`. São cerca de 20 conferências, cada uma com uma linha em `nai_conferencia`: parceria, secretária, link, oferta, promessa, "sem consulta", formato da base, pagamento, silêncio, voz, sugestão de visita, citou o Tel, uma pergunta por mensagem, markdown, visita inventada, ficha de identificação (14i), confirmação de visita, portão de fotos (`nai_deve_mandar_fotos`, que devolve `true` salvo negação explícita) e foto inexistente.
   - Corta o texto em blocos por `Código:`. Põe o balão "📌 Status" antes. Para cada foto de `nai_imagens_do_envio` faz um INSERT em `nai_saida`, e cada INSERT passa pelo gatilho `nai_saida_validar`, que:
     - fixa `chave_destino` e tira Sr./Sra.;
     - bloqueia imóvel de parceria;
     - bloqueia finalidade trocada (190), salvo código que ele mesmo digitou;
     - troca o card de imóvel indisponível pelo texto de situação;
     - aplica "um imóvel por corretor por dia": a foto reserva o dia (`nay_reservar_imovel_do_dia`); o card vira "O 5717 eu já mandei … está aqui em cima";
     - confere que a foto é daquele imóvel.
   - Depois vêm `nai_depois_das_fotos` (2 textos), `nai_fila_dos_outros_imoveis`, `nai_conferir_imoveis_da_saida`, `nai_conferir_texto_da_saida` e `nai_espacar_depois_das_fotos`, que empurra o `enviar_apos` do texto que vem depois das fotos em 2,5 s por foto.
21. "Fechar turno": `nai_fechar_turno` grava `fechado_em` e passa as mensagens de `Processando` para `Respondido`. Devolve `lote = turno`.
22. "Liberar saída": `nai_liberar_saida(lote)` pega o que está `pendente` com `enviar_apos <= now()` naquele turno.
   - Motivos de bloqueio: `nai_desligada`, `nai_pausada`, `contato_mudou`, `tel_assumiu`, `foto_nao_confere` e `repetida` (mesmo texto ou foto em 10 min).
   - Aplica o redirecionamento do modo teste e o "proprietário pelo Tel".
   - Espelho do treino vira `simulado`. O resto vira `enviando` e sai com rota, corpo e chave.
23. "Conferir cabeçalho" (JS): recalcula a chave do telefone e confere telefone do corpo, rota, URL da foto (imobeasy.com ou a colagem) e texto vazio.
24. "Pode enviar?": falso vai para "Registrar bloqueio" (`nai_registrar_bloqueio`).
25. "Enviar Z-API": POST `send-text` ou `send-image` na URL da Z-API (instância omitida). Lote de 1 item a cada 2 s, com `onError` seguindo em frente.
26. "Confirmar envio": `nai_confirmar_envio`.
   - Com `messageId`: grava `enviado`, `mensagem_saida`, `envios` (se for card para corretor) e o carimbo da visita.
   - Sem `messageId` e erro passageiro (5xx, timeout): volta para `pendente` com +1 e +2 min, até 2 vezes.
   - Senão grava `erro` e solta a trava de 24 h.
27. No fim da execução rodam "Detectar audio" e "Detectar imagem" (vazios), "Foi o Tel pelo celular?" (falso) e "Espelhar no CRM" (POST do corpo cru no CRM, `/api/webhooks/zapi`).

**Depois do n8n.**
- Cada mensagem enviada volta como eco (`fromMe`) e percorre de novo o fluxo antigo e a NAI:
  - "Gravar na fila" grava a linha `enviada` e para.
  - "Foi o Tel pelo celular?" dá verdadeiro, vem "Espera 15s (eco)" e depois "O Tel assumiu a conversa" (`nai_tel_assumiu`).
  - Se o `message_id` ou o texto casar com `nai_saida`, `mensagem_saida`, `envios` ou `saida_do_sistema`, é eco nosso e nada acontece. Senão grava `humano_assumiu_em`, e ela fica 30 min calada.
- O ciclo "Agenda (todo minuto)" chama "Agenda da NAI" (`nai_agenda_tick()`: visitas, lembretes, follow-up) e depois "Liberar saída" com `lote NULL`. Esse ciclo manda:
  - o que não tem turno;
  - o que tem mais de 3 min;
  - o que tem hora marcada (`enviar_apos > criado_em + 1 s`, que é o texto "depois das fotos");
  - dentro da janela de horário (06:00–22:00) ou destinado a `tel` ou `equipe`.

**Onde o modelo é chamado para "tem o 5717?": 3 vezes.**
1. **Jev** (OpenRouter, `typesafe/jev-1.13-20260917`): classifica intenção, código pedido ou recusado, oferta, cortesia e o que veio na mídia. Custo médio de US$ 0,000061 por chamada (183 chamadas desde 28/09 11:34), 0,38 a 0,55 s nas execuções medidas. Só decide rota e anotações. Não escreve texto.
2. **gpt-5.6-sol, 1ª chamada**: lê prompt, memória e mensagem e decide chamar `imovel_por_codigo`.
3. **gpt-5.6-sol, 2ª chamada**: recebe o card e a instrução e escreve a resposta final.

Não há transcrição nem leitura de imagem. Todo o resto (qual card, quais fotos, visita, "depois das fotos", bloqueios) é SQL.

**Onde o caminho morre calado depois da mente.** Nos últimos 2 dias, 40 turnos passaram pelo Jev e ficaram sem `fechado_em`, sem nenhuma `nai_saida` e com uma única linha em `nai_conferencia` (a `mente_mestra`). Eles se concentram em 28/09 das 07:05 às 10:21 e em 29/09 das 09:51 às 14:32. A execução parou entre o Jev e o "Enfileirar resposta", as mensagens ficaram em `Processando`, e não existe caminho de reserva.
- Contando só os turnos que passaram pelo Jev desde 28/09 11:34: 125 responderam, 23 ficaram em silêncio de propósito e 27 não fecharam.
- A causa não está no n8n: essas execuções já foram apagadas do histórico. A memória da sessão diz que em 29/09 a OpenAI ficou sem crédito ("Rate limit reached").

**Caso real parecido, turno 12427 (29/09).**
- 08:48:54,8: chega um áudio. 08:49:04,4: chega "Código 2133". A rajada juntou os dois (`msg_ids` 31235 e 31239).
- 08:49:24,8: turno aberto, 20,4 s depois da última mensagem. Porta: "conversa ja liberada".
- 08:49:28,1: Jev com `pergunta_sobre_imovel` 0,48 (virou "indefinida" pelo piso de 0,60) e `codigo_quer` 2133 com 0,98.
- O agente chamou `imovel_por_codigo`.
- 08:49:37,5: enfileirado.
- 08:49:40,4: `nai_saida` 36461 `enviado` (card do Life Ponta Negra, código 2133) e 36460 para o Tel, motivo `foto_inexistente`: o 2133 não tem foto nem no banco nem no site. Nenhuma foto saiu.
- **O áudio 31235 nunca foi transcrito.** O texto do turno ficou só "Código 2133", porque os detectores leem o webhook da execução vencedora, que era a do texto (ver pergunta 2).

**Atalho do número puro.** Existe um só nos últimos 7 dias: turno 12135 (28/09 09:45:41), texto "964".
- Caminho: "Rotear" dá `codigo`, "Qual caminho?" vai para "Enfileirar card do código" (`nai_enfileirar_card`: card e fotos, sem Jev, sem agente, sem `nai_conferir_resposta`), depois "Fechar turno" e "Liberar saída". Zero chamada de modelo.
- O gatilho trocou o card por "O 964 eu já mandei hoje às 09h43…" e bloqueou as 5 fotos (`imovel ja enviado a este corretor nas ultimas 24h`).
- Da mensagem ao envio foram 4,5 s, porque a janela de 28/09 antes das 11:33 era de uns 3 s.

### 2. "boa tarde, meu cliente quer um apartamento de 2 quartos no Parque 10 até 3 mil"

O caminho é o mesmo da pergunta 1 até o agente. As diferenças:

- **Porta** (`nai_deve_atender`): numa conversa não liberada, abre por `nai_pedido_de_perfil(texto)->>'e_pedido'`, com motivo "pediu imoveis" (e grava `liberado_em`) ou "contato novo falando de imovel". Não abre por código.
- **Reservar e Juntar:** `nay_codigos_citados` tira os valores, então `codigosDele=[]`. "3 mil" não vira código 3000. Não há `codigoCitado`.
- **Jev:** intenção `pedir_imovel`. `codigo_quer` fica em "nenhum" ou "outro_nao_listado". A rota é `locacao`, que vai para "NAI (corretor)".
- **Agente:** chama `buscar_por_perfil(bairro, teto, quartos, mobilia)`, que é `nai_buscar_por_perfil(turno, …)`. Quem conduz a conversa é a função, não o modelo. Ela devolve **uma** pergunta de filtro por vez e, só quando os filtros estão resolvidos, a lista:
  - Locação ou venda (144): `nai_negocio_da_conversa`; na falta dele, `nai_negocio_do_pedido` pela régua de valor (até R$ 30 mil é locação, de R$ 100 mil para cima é venda, abaixo de R$ 300 não conta).
  - Casa ou apartamento (152): feita uma vez em 24 h.
  - Valor e região (190): cada pergunta uma vez em 24 h (`nai_filtro_ja_perguntado`).
  - Nesta mensagem nada disso falta: "até 3 mil" dá locação, "apartamento" dá o tipo, 3000 é o teto e "Parque 10" é o bairro. A função lista até 5 imóveis no bairro (`nai_oferta_serve`) e até 5 nos bairros ao redor (`nay_bairros_proximos`), no formato "🏢 *Nome — Bairro #NNNN*". Fecha com "Qual deles é de seu interesse?…" e oferece o filtro que falta (mobília).
  - Com um resultado só, devolve o card inteiro, e aí saem fotos e "depois das fotos".
- **Depois do agente:**
  - A lista usa `#NNNN`, não `Código:`, então "Achar codigo na resposta" não acha código e nenhuma foto sai. Em turno com `buscar_por_perfil`, `nai_conferir_resposta` também não manda fotos do "imóvel da conversa" (regra 190) e pula a conferência 05 (formato da base).
  - A conferência 14i pode trocar o texto pela "ficha de identificação" ("Qual deles?" com 🏠 📍 💰 #código).
- **Chamadas de modelo:** Jev mais 2 do gpt-5.6-sol. Se o modelo chamar mais de uma ferramenta, elas vêm na mesma rodada: na execução 143689 (turno 12611, "Mosaico Ponta Negra") foram `buscar_por_perfil` e `disponibilidade_no_condominio` em paralelo, com 2 chamadas de GPT de 2,96 s e 4,74 s. Por áudio, soma 1 chamada de transcrição (`gpt-4o-transcribe`).

**Casos reais:**
- **Filtro em sequência (turnos 12428 a 12431, corretora Nora).** 29/09: 08:52:59 turno 12428, "Vc tem algum soto mobiliado na ponta negra ii?", resposta "Seu cliente procura imóvel para alugar ou para comprar?". 08:53:53 turno 12429, "Alugar", resposta "Seu cliente procura casa ou apartamento?". 08:54:39 turno 12431, "Apto", resposta "No Ponta Negra eu tenho estas opções: 🏢 *Conquista rio negro — Ponta Negra #5733* …". Zero fotos. São 3 turnos, e cada um paga os 20 s de janela, o Jev e 2 chamadas de GPT.
- **Turno 12451 (29/09 09:14), por áudio.** A transcrição deu "Estou procurando uma casa em condomínio fechado até quatro mil". O `buscar_por_perfil` achou 2 opções e a conferência 14i entregou "Qual deles?" com as fichas #1778 e #5746.
- **Turno 12600 (29/09).** 5 mensagens entre 17:34:07 e 17:34:39 ("Nay" / "Ela precisa de mais um cômodo" / "P escritório" / "Ideal 3 quartos…" / "A casa tá show") viraram um turno só às 17:35:00. Resposta às 17:35:11: "Seu cliente procura imóvel para alugar ou para comprar?".

**Um defeito do caminho de mídia que aparece aqui.**
- "Detectar audio" e "Detectar imagem" leem só `$('Webhook')` da execução que venceu a rajada, que é a última mensagem. Áudio ou imagem que não seja a última mensagem do turno nunca é transcrito nem lido.
- Nos últimos 7 dias, em `nai_turno` e `mensagens.origem`: 24 de 138 áudios e 118 de 181 imagens ou documentos estavam em posição que não é a última. A `midia_url` gravada na linha não é usada por esses nós.
- Quando a última mensagem é áudio, "Juntar mensagens" troca `textoCru` pela transcrição e **descarta os textos do mesmo lote**. Aconteceu nos turnos 10829 e 10846: o texto "👆🏼" e "Eu só tenho essas informações" sumiram.

### 3. "obrigado"

**Premissa a corrigir:** o ramo "Enfileirar cortesia" **não** é o do "obrigado". A rota `cortesia` de "Rotear pelo cabeçalho" é a mensagem de apresentação para número não aprovado na primeira vez ("oi! aqui é a Nay…" mais aviso ao Tel, `nai_enfileirar_cortesia`). Com `regra_publico='sim'`, `cab.atende` sempre vem `true` ou `false`, e essa condição nunca é alcançada. Em 7 dias houve zero `nai_saida.motivo='cortesia'`. O "obrigado" vai pelo agente.

O caminho:
- **Porta.** Numa conversa que ela já atende, o motivo é "conversa que ela ja estava atendendo" ou "conversa ja liberada". Numa conversa antiga não liberada, o motivo é "conversa que ja existia: quem responde e o Tel", e ela fica calada. Contato novo cai em "contato novo, assunto que nao e de corretor", também calada.
- **"Rotear pelo cabeçalho"** dá `agente`. O `cab.so_cumprimento` é calculado, mas o roteador não usa.
- **Jev:** cortesia (`noul`) ≥ 0,70 dá `locacao`. Depois `nai_mente_registrar`, pela regra da cortesia (`nai_e_so_cortesia`), devolve a conversa a quem atendeu nas últimas 6 h. Um "obrigado" numa conversa com a secretária vai para a secretária.
- **Agente "NAI (corretor)":** normalmente **1 chamada** de gpt-5.6-sol, sem ferramenta. O prompt vivo (`nai_prompt.corretor`) diz: `Ele agradece: "Imagina!"` e `Responda exatamente SILENCIO … quando ele só agradecer ou disser "ok" depois que você já encerrou.`
- **"Achar codigo na resposta"** não acha código e devolve `['0']`.
- **"Enfileirar resposta":**
  - A parede 1 anota "cortou 0", que não tem efeito prático mas suja `nai_turno_decisao.bloqueados` com `{"cortados":1}`.
  - `nai_conferir_resposta` identifica o imóvel da conversa. O portão de fotos (`nai_deve_mandar_fotos` = true) só não manda as fotos desse imóvel porque `nai_fotos_ja_mandadas(…, 24h)` já as marcou. Em 7 dias houve 0 turnos de cortesia com foto.
  - Se o modelo respondeu `SILENCIO`, a conferência 06 para e nada vai para a caixa.
- **"Fechar turno"** e **"Liberar saída"** fecham o caminho.

**Chamadas de modelo:** Jev mais 1 do gpt-5.6-sol.

**Números (7 dias, `nai_turno_decisao.intencao='cortesia'`):** 74 turnos. 16 responderam, 32 ficaram em silêncio de propósito (`nai_conferencia` com etapa `silencio`, resultado `parou`), 3 morreram sem fechar, 4 fecharam sem saída e 19 foram enfileirados sem sair (25 a 27/09, simulados).

**Caso real: turno 12603 (29/09).** "Tendi" chegou às 17:41:40,9 e "De qq forma muito obrigado" às 17:41:46,6, e viraram um turno só às 17:42:07,4. Jev às 17:42:09,9, com cortesia 0,95 e intenção `cortesia` 1,0. Uma chamada de GPT de 2,26 s (execução 143387) respondeu "Imagina!", enfileirado às 17:42:12,56 e enviado às 17:42:13,4. A execução levou 26,9 s a partir da segunda mensagem.

### 4. Resposta marcando (citando) um card que a Nay mandou

- **"Filtrar e normalizar":** a Z-API manda só o id da mensagem citada (`referenceMessageId`, que vira `citadoId`), **nunca o texto**. Das 3.726 mensagens recebidas em 7 dias, 0 têm `mensagens.citado` preenchido. O texto citado não existe no sistema.
- **"Gravar na fila"** grava `citado_id`.
- **"Reservar mensagens"** chama `nay_imovel_da_citacao(citado_id)`, que procura nesta ordem:
  1. `envios.message_id` (o que o publicador ou a própria NAI mandou);
  2. `nai_saida.codigo`;
  3. `Código:` dentro do texto da `nai_saida`;
  4. a mensagem dele próprio em `mensagens`;
  5. `grupo_mensagens`;
  6. `nay_codigos_da_saida` (a Nay antiga).
  `nay_opcoes_da_citacao` monta a lista quando a mensagem citada tinha 2 códigos ou mais.
- **Taxa de acerto em 7 dias:** 301 mensagens com citação e **75 resolvidas (25%)**. Nas outras 226 a Nay não sabe o que foi marcado.
- **"Juntar mensagens"** passa adiante `citadoId`, `codigoCitado` e `opcoesCitacao`.
- **"Abrir turno":** `nai_deve_atender(…, p_codigo_citado)`. Com um código resolvido, a porta abre como "marcou uma mensagem de imovel", seja qual for o texto (até "Boa noite!"). No modo teste, a citação de uma `nai_saida` redirecionada define o papel (proprietário ou motoboy).
- **Jev: não vê a citação.** Nem o estado nem os candidatos incluem `codigoCitado`. No caso real abaixo, `codigo_quer` saiu "nenhum" e `nai_turno_decisao.codigos_pedidos` ficou `{}`.
- **Agente:** a mensagem do usuário recebe uma destas frases, no nó "NAI (corretor)":
  - com código resolvido: "ele MARCOU a mensagem do imovel 3210. E desse que ele fala: siga com esse codigo e NAO pergunte qual e";
  - com vários códigos: "Pergunte qual, mostrando esta lista";
  - sem resolução: "ele respondeu CITANDO uma mensagem que voce nao consegue ver… PERGUNTE. Nunca suponha".
- **"Achar codigo na resposta"** usa o `Código:` da resposta e, sem ele, o `codigoCitado`.

**Caso real: turno 12556 (29/09, execução 142098).**
- 16:01:31,2: chega "Boa tarde, Nay. Tudo bom? Esse imóvel está disponível?", citando um envio do 3210, achado em `envios`.
- 16:01:51,3: turno aberto, porta "marcou uma mensagem de imovel".
- Jev: `pergunta_sobre_imovel` 0,99, `codigo_quer` "nenhum". O agente chamou `o_que_sei_do_imovel`, com 2 chamadas de GPT de 2,02 s e 2,30 s.
- 16:01:58,5: 23 linhas em `nai_saida`, nesta ordem:
  - 1: "📌 Status: Disponível", motivo `status`;
  - 2: "Boa tarde, Paulo! Tudo bom sim! 📌 Status: Disponível 📍 Morada dos Pássaros … Código: 3210", ou seja, **o status saiu duas vezes**: o modelo pôs o status dentro do texto e `nai_enfileirar_resposta` pôs outro balão porque o bloco não começava com 📌;
  - 3 a 21: 19 fotos;
  - 22 e 23: "depois das fotos", com `enviar_apos` 16:02:46.
- Todas `enviado`. As 21 do lote têm `enviado_em` 16:02:50,605 (ver pergunta 6). As duas últimas saíram pelo ciclo do minuto às 16:05:37.
- Contradição na mesma execução: "Juntar mensagens" tinha `vaoSairFotos=false` (`nay_deve_mandar_fotos`), então o prompt disse ao modelo "as fotos NAO saem neste turno". O portão de fotos usa outra função (`nai_deve_mandar_fotos`, que devolve `true` sempre) e mandou 19 fotos.

**Chamadas de modelo:** Jev mais 2 do gpt-5.6-sol.

### 5. O workflow antigo "Nay- recebe mensagem"

**Sim, ele ainda recebe o webhook da Z-API.** Foram 1.038 execuções de 13:57 a 19:30 de 29/09 (tudo o que o histórico guarda).

**O que ele faz antes de entregar à NAI:** só uma consulta, "NAI ou Nay? (quem atende)" com `nai_quem_atende(phone, grupo, texto)` (3 argumentos), e o "Vai para a NAI?". Não grava nada, não tira duplicata, não resolve @lid (a NAI grava o telefone como chegou) e repassa o corpo cru em "Mandar para a NAI". `nai_quem_atende` devolve `'nay'` (fica no fluxo antigo) em quatro casos:
1. mensagem do número do Tel (`tel_telefone`), fora de grupo, com comando do publicador (`nai_e_comando_publicador`: vendeu/alugou, posta/publica/dispara, tira/remove N, vagas, resposta/descartar #N, "envia … para X");
2. grupo, newsletter ou broadcast;
3. telefone sem chave;
4. qualquer exceção (`EXCEPTION WHEN others THEN RETURN 'nay'`).

Comando da NAI de quem pode comandar vai sempre para a NAI, mesmo em modo teste. Todo o resto vai para a NAI com `modo='todos'`.

**Medido nas 1.038 execuções** (busca por texto no `execution_data` do sqlite):

| Resultado | Execuções |
|---|---|
| Entregue à NAI em cerca de 0,1 s ("Workflow was started") | 318 |
| Estourou os 10 s de "Mandar para a NAI" (a NAI recebeu, a execução parou em "Prazo estourado?") | 709 |
| Foi para o caminho antigo | 11 (as mesmas 11 com `isGroup:true`) |

Das 1.038, **771 eram `fromMe`**: ecos do que a Nay ou o Tel mandaram.

**O que ainda passa por ele sem chegar na NAI:**
- **Grupos, newsletter e broadcast:** 11 hoje. O "Filtrar e normalizar" antigo descarta tudo isso logo de cara, e nada é gravado.
- **Comandos de publicador do Tel pelo número dele:** vão pelo caminho antigo inteiro: "Filtrar e normalizar", "Gravar na fila" (`nay_resolver_identidade`, `fluxo` NULL), "Janela de 25s" (25 s fixos), "Reservar mensagens" (sem filtro de `fluxo`), "Juntar mensagens" e "Comando do Tel", que faz POST no publicador `http://172.16.0.1:8080/comando`. Pendência passa por "Responder pendencia" (`nay_comando`) e "Preparar aviso do comando" e sai por "Enviar Z-API" direto, **sem passar por `nai_saida`**.
  - Desde 28/09 as linhas de `mensagens` com `fluxo IS NULL` e `direcao='recebida'` são 11, todas do Tel (…7316), do tipo "Posta 5764", "posta no grupo alto padrão 5052…".
  - O agente antigo ("AI Agent", `gpt-5.6-luna`) não roda para ninguém: `config.atendimento_pausado='sim'` e "Rotear para o agente" descarta os comandos do Tel.
- **Caminho latente:** se "Mandar para a NAI" falhar com erro que não seja timeout (por exemplo, NAI desativada depois de um import), qualquer conversa privada cai no fluxo antigo. Lá, "Achar codigo" (número puro) **não confere pausa nem aprovação** e mandaria card e fotos pela Nay antiga.

**Outras entradas que não passam pelo fluxo antigo:**
- O botão "Nay voltar a atender" do CRM (`crm/src/app/api/leads/[id]/nay/route.ts`) faz POST direto no webhook da NAI (`http://n8n-viux-n8n-1:5678/webhook/nai-atendimento-locacao`) com `messageId` `CRMNAY<epoch>`. Foram 11 mensagens em 2 dias, por exemplo os turnos 12589 a 12595 às 17:13, que reentregaram pedidos do intervalo em que a Nay caiu.
- "disparo pelo painel" (`/api/disparo`) cria turnos sem webhook nenhum.

### 6. Quanto tempo leva, e de onde vem

**Premissa a corrigir:** a janela não é de 25 s. Medido como `nai_turno.criado_em` menos a última mensagem, para turnos de corretor, a mediana foi de 25 s (10 a 15/09), 60 s (16 a 24/09), cerca de 3 s (26 e 27/09) e **20 s desde 28/09 11:33** (`nai_config.janela_segundos`, atualizado 28/09 11:33:52).

**Cuidado com `nai_saida.enviado_em`: ele não é a hora do envio de cada mensagem.** O "Confirmar envio" roda uma vez só, depois que a Z-API enviou o lote inteiro. Todas as linhas do lote ficam com o mesmo carimbo, o do fim do lote: no turno 12556, as 21 linhas estão em 16:02:50,605, enquanto a primeira chamada à Z-API foi uns 41 s antes. Por isso calculei também a "1ª chamada estimada", que é o `enviado_em` menos 2 s por item antes dele no lote.

**Métrica pedida:** primeira mensagem do bloco em `mensagens.criada_em` até o `min(enviado_em)` do turno. Turnos de corretor com resposta enviada, sem contar "disparo pelo painel":

| Período | n | p50 | p90 |
|---|---|---|---|
| 7 dias (desde 22/09 19:22) | 263 | 41,5 s | 99,4 s |
| 30 dias (a tabela começa em 10/09) | 457 | 36,3 s | 93,3 s |
| Só com janela de 20 s (desde 28/09 11:34) | 122 | 39,1 s | 79,4 s |

**Decomposição com a janela de 20 s** (desde 28/09 11:34, n=122, mesma fonte):

| Trecho | p50 | p90 |
|---|---|---|
| Rajada (1ª à última mensagem) | 0 s | 16,6 s |
| Janela (última mensagem até o turno aberto) | 20,5 s | n/d |
| Turno aberto até a caixa de saída (Abrir turno, Jev, agente, Enfileirar) | 10,2 s | 15,7 s |
| Caixa de saída até a 1ª chamada à Z-API (estimado) | 1,2 s | 7,6 s |
| **Mensagem até a 1ª chamada à Z-API (estimado)** | **36,6 s** | **52,5 s** |
| Idem, turnos só com texto (97) | 34,1 s | 51,6 s |
| Idem, turnos com foto (25; lote mediano de 19 itens) | 45,4 s | 52,1 s |
| Mensagem até a última saída do turno ("depois das fotos") | 39,1 s | 96,1 s |

**Tempo de cada nó em 5 execuções reais** (runData, em segundos):

| Execução / turno | Janela | Abrir turno | Jev (nó) | Agente (chamadas de GPT) | Enfileirar | Liberar | Z-API | 1ª chamada à Z-API desde o início |
|---|---|---|---|---|---|---|---|---|
| 143387 / 12603 "obrigado" | 20,0 | 1,89 | 0,46 | 2,3 (1: 2,26) | 0,55 | 0,22 | 0,06 (1 item) | 26,8 |
| 143364 / 12600 perfil, 5 msgs | 20,0 | 3,90 | 0,55 | 4,9 (2: 2,28 + 2,02; ferramenta 0,42) | 0,66 | 0,26 | 0,08 | 31,7 |
| 142098 / 12556 citação | 20,0 | 1,80 | 0,38 | 4,5 (2: 2,02 + 2,30) | 3,39 | 7,74 | 40,98 (21 itens) | 38,5 |
| 143689 / 12611 condomínio | 20,0 | 2,35 | 0,45 | 9,0 (2: 2,96 + 4,74; 2 ferramentas) | 2,13 | 1,27 | 10,63 (6) | 36,2 |
| 143446 / 12605 "fotos do Sollar" | 20,0 | 2,16 | 0,48 | 5,0 (2: 2,21 + 2,57) | 8,78 | 8,22 | 46,78 (24) | 45,4 |

**De onde vem o tempo, num dia calmo:**
- **A janela fixa de 20 s** é 55% a 75% do caminho até a 1ª mensagem.
- **O agente:** 2,3 a 9,3 s, cada chamada do gpt-5.6-sol levando 2 a 4,7 s.
- **O banco:** 2,5 a 19 s somando Abrir turno (1,8 a 3,9 s), Enfileirar (0,5 a 8,8 s) e Liberar (0,2 a 8,2 s). Pesa muito quando há fotos, porque cada foto passa pelo gatilho `nai_saida_validar` e pelas conferências.
- **O Jev:** 0,4 a 0,55 s.
- **A Z-API:** cada chamada responde em cerca de 0,06 a 0,1 s, mas o lote manda 1 item a cada 2 s. Uma resposta com 20 fotos leva uns 40 s só para ser empurrada, e o `enviado_em` de todo o lote só é gravado no fim.
- O texto "depois das fotos" fica com `enviar_apos` = agora + 2,5 s por foto e **só sai no ciclo do minuto seguinte**. No turno 12556, `enviar_apos` era 16:02:46 e o envio foi às 16:05:37. No turno 12595, 17:15:27 e 17:18:18.

**O que o banco não mostra: a fila do n8n.**
- `mensagens.criada_em` é gravado quando a execução da NAI **começa**, então não inclui o tempo que o webhook esperou vaga. Cruzei os 42 turnos com resposta de 29/09 (14:00 a 19:30) com as execuções do fluxo antigo e da NAI. O cruzamento é por horário (mensagem até 1,5 s depois do início da execução da NAI; execução antiga até 0,6 s antes da criação da NAI) e ligou 42 de 42.
- Do webhook chegando ao n8n até a 1ª chamada à Z-API: **p50 43,7 s, p90 302 s, máximo 926 s**. No máximo, turno 12599, "Posso sim", às 17:32, a mensagem esperou 456 s pela vaga do fluxo antigo e mais 433 s pela vaga da NAI.
- Para os mesmos 42 turnos, a métrica do banco dá p50 33,8 s e p90 48,2 s. **12 dos 42 turnos esperaram mais de 25 s na fila antes de a mensagem ser gravada** (12559, 12561 a 12568, 12575, 12598, 12599).
- Espera na fila (início menos criação da execução) nas execuções guardadas de hoje:
  - webhook da NAI: p50 77,5 s, p90 480 s (1.037 execuções);
  - fluxo antigo: p50 50,2 s, p90 260 s;
  - ciclo do minuto: p90 87 s, máximo 499 s.
  - Por hora (fluxo antigo): 14h, p50 47 s; 16h, p50 54 s; 17h, p50 193 s. Às 13h, 15h e 19h, zero.
- Configuração: `N8N_CONCURRENCY_PRODUCTION_LIMIT=5` (lido no container) numa máquina com 2 vCPU.
- **[OPINIÃO]** O mecanismo provável: cada mensagem recebida ocupa uma das 5 vagas durante os 20 s da janela, porque espera curta no n8n roda dentro da própria execução. Cada eco ocupa 15 s ("Espera 15s (eco)"), e cada repasse do fluxo antigo ocupa até 10 s quando a NAI está na fila (709 timeouts hoje). Com 74% do tráfego sendo eco das nossas próprias mensagens, uma resposta com 20 fotos gera uns 20 ecos × (15 s + até 10 s) e enche a fila, que atrasa o corretor seguinte e o ciclo do minuto.

**Resumo:** em hora calma, cerca de 35 s até a primeira mensagem (20 s de janela, uns 10 s de Jev + agente + banco, uns 1 a 2 s de liberação). Com fotos, a última foto e o "depois das fotos" chegam 1,5 a 4 min depois. Em hora cheia, o que manda é a fila do n8n: minutos.

**Chamadas de modelo por turno, por caminho:**

| Caminho | Jev | gpt-5.6-sol | Outros |
|---|---|---|---|
| Número puro (rota `codigo`) | 0 | 0 | nenhum |
| Agente, sem ferramenta ("obrigado", conversa) | 1 | 1 | nenhum |
| Agente, 1 rodada de ferramentas (código, perfil, citação) | 1 | 2 | nenhum |
| Agente, mais rodadas | 1 | 3 ou mais | nenhum |
| Secretária | 1 | 1 ou mais ("GPT (secretária)") | nenhum |
| Proprietário ("NAI (proprietário)") | 0 (não passa pela mente) | 1 ou mais | nenhum |
| Fernando e acompanhante | 0 | hoje 0: a versão viva de `nai_abrir_turno` tem o bloco da 186 e devolve `ok=false`. Antes era 1 ou mais em "NAI (Fernando)": os turnos 12537 a 12547 (29/09, 14:59 a 15:22) ainda receberam resposta, então a 186 entrou depois disso | nenhum |
| Comando do Tel (`tel_nai` ou `tel_antigo`) | 0 | 0 | publicador ou `nai_comando_tel` |
| Com áudio na última mensagem | +0 | +0 | +1 `gpt-4o-transcribe` |
| Com imagem ou PDF na última mensagem | +0 | +0 | +1 `gpt-4o-mini` (chat/completions) |

**Contagem real desde 28/09 11:34** (turnos de corretor ou Tel fechados, por `nai_turno.ferramentas` sem os marcadores `_lidas`, `escalar`, `visita`):
- 2 sem Jev;
- 48 com Jev e 0 ferramentas (1 chamada de GPT);
- 86 com 1 ferramenta (2 chamadas ou mais);
- 9 com 2 ferramentas;
- 10 com 3 ou mais;
- 3 da secretária, com a lista de ferramentas vazia porque não é gravada nesse ramo.

As 5 execuções medidas confirmam: 1 chamada de GPT no "obrigado" e 2 nos casos com ferramenta. Em cada turno que passou pela mente houve exatamente 1 linha em `nai_jev`.

---

## BLOCO 2: DECIDIR (perguntas 7 a 13)

Fontes: workflow `NaiAtendLocacao1` exportado hoje (wf_NaiAtendLocacao1.json`), `pg_get_functiondef` das funções vivas no `naydb`, contagens no banco (sessão em America/Manaus) e execuções do n8n que ainda estavam guardadas (29/09, a partir de ~13:57). "Espelho" é o contato 9707, o espelho do treino: separo os números dele dos números reais sempre que isso muda a conclusão.

---

### 7. A "mente" (Jev): perguntas, opções, pisos e quantas vezes o banco desfaz a escolha

**A premissa está desatualizada.** Desde 25/09 o Jev não escolhe mais o atendente. O nó "Montar pergunta ao Jev" parou de mandar as perguntas `atendente`, `tipo`, `finalidade` e `pedido`. Em `nai_jev.respostas`, `atendente/tipo/finalidade` aparecem só em 57 linhas (24/09 12:31 até 25/09 08:34) e `pedido` em 8. A partir de 25/09 11:07 vêm `intencao`, `codigo_quer` e `codigo_rejeita` (650 linhas). Mesmo assim, `nai_decidir_com_jev` continua lendo `{atendente,choice}`, `{pedido,noul}` e `{tipo,choice}`, que agora chegam NULL. O resultado é que a função cai sempre no ramo `'sem resposta (0.00)'` → `locacao`. Em 527 das decisões, o motivo gravado em `nai_mente.motivo` é "sem resposta (0.00) · foto: nao_da_para_saber". Hoje o Jev só consegue mandar alguém para a secretária por dois sinais: `oferta` acima do piso ou `o_que_mandou = anuncio_dele`.

**O que vai para o modelo** (nó "Montar pergunta ao Jev", POST para `https://openrouter.ai/api/alpha/decisions`, com o corpo `{model:'typesafe/jev-1.13', state, questions}`):

- **O `state`**, montado a partir de `nai_estado_v2` (ver 10) e do "Juntar mensagens". Tem estes campos:
  - `mensagem`: é o `j.texto` com até 1500 caracteres. Não é o `textoCru`, então inclui o envelope de sistema do áudio, da imagem e do card colado.
  - `quem_fala`
  - `nome`: é o nome do contato. Esse dado pessoal sai para a OpenRouter.
  - `leitura_das_imagens`
  - `imovel_em_foco`
  - `imoveis_ja_mostrados`
  - `imoveis_que_ele_recusou`
  - `ultima_coisa_que_a_nay_disse`
  - `tem_visita_pendente`: sempre chega "nao" (ver 10).
  - `ultimas_trocas`
- **As `questions`**:

| chave | tipo | opções |
|---|---|---|
| `intencao` | choice | pedir_imovel, rejeitar_imovel, pergunta_sobre_imovel, visita, resultado_visita, cortesia, oferta_de_imovel, assunto_geral |
| `codigo_quer` | choice | até 8 candidatos de 3 a 5 dígitos (`codigo_foco`, `codigosDele` e `codigos_mostrados`, nessa ordem), mais `nenhum` e `outro_nao_listado` |
| `codigo_rejeita` | choice | os mesmos candidatos, mais `nenhum` |
| `oferta` | noul | true: "tem um imóvel e quer enviar/cadastrar/anunciar"; false: o resto |
| `cortesia` | noul | true: "só agradecimento/confirmação/saudação"; false: o resto |
| `o_que_mandou` | choice | anuncio_dele, documento, duvida_sobre_nosso, nao_da_para_saber |

A resposta traz `choice`, `confidence` e `probabilities` por pergunta (ou `noul`, a probabilidade de true). O modelo devolvido é `typesafe/jev-1.13-20260917`, a cerca de US$ 0,00005 por chamada (`nai_jev.custo`).

**O que o banco faz com os números.** O nó "Decidir quem responde" roda duas CTEs `MATERIALIZED`:

1. **`nai_decidir_com_jev(turno, jev)`**. Grava tudo em `nai_jev`, inclusive `'{}'` quando o Jev falha, e decide nesta ordem:
   - `cortesia.noul ≥ jev_piso_cortesia` → `locacao` (provisório);
   - senão, `oferta.noul ≥ jev_piso_oferta` OU `o_que_mandou='anuncio_dele'` → `secretaria`;
   - senão, `atendente.choice='secretaria'` (hoje nunca chega) → `secretaria`; em qualquer outro caso → `locacao`.

   A cortesia ganha da oferta. No turno 11230, a oferta veio 0,79 e a cortesia 0,70, e o resultado foi locação. Depois disso a função chama `nai_mente_registrar(..., 'jev')`.
2. **`nai_decidir_v2`**. Faz três coisas:
   - `intencao` com `confidence < v2_piso_intencao` vira `'indefinida'` (188 de 657);
   - grava `nai_turno_decisao` (`intencao`, `confianca`, `codigos_pedidos` = `codigo_quer`, `codigos_rejeitados` = `codigo_rejeita`, `jev_bruto`);
   - manda `codigo_rejeita` na hora para `nai_estado_gravar_v2`, que tira o imóvel do foco e barra a saída dele.

   `intencao` e `codigos_pedidos` não são lidos por nenhuma função de produção. O único leitor é `nai_bloco_colher`, do treino.
3. **`nai_pediu_imovel(turno)`** = `coalesce(nai_jev_pedido(turno), true)`. Como `pedido` não é mais perguntado, o valor é sempre `true`. Por isso estão mortas a parede "SEM PEDIDO, SEM IMOVEL" do nó "Achar codigo na resposta" e o passo 3 de `nai_fila_dos_outros_imoveis`.

**Por cima de tudo, `nai_mente_registrar`** reescreve a decisão em quatro passos (por regex e estado, não pelo Jev):

1. Cortesia pela regex (`nai_pedido_do_turno.cortesia` = `nai_e_so_cortesia`): herda o atendente do último turno com menos de 6 h (`por='cola'`).
2. Regra 117: se ficou secretária, a regex diz que é assunto de imóvel (`de_imovel`), não há oferta nem link, e `v_pediu IS NULL`, vira `locacao` (`por='regra'`). Como `pedido` nunca vem, a 117 manda sempre.
3. Ficha `nai_imovel_novo.situacao='colhendo'` com menos de 24 h: vai para `secretaria` (`por='cola'`), a não ser que seja pergunta de catálogo (`cola_solta_no_catalogo`). Esse passo também chama `nai_cadastro_absorver`.
4. Oferta ou link pela regex (`nai_oferece_imovel`, `nai_e_link_de_produto`): vai para `secretaria` (`por='regra'`).

No fim, a função grava `nai_turno.atendente` e `nai_mente`.

**Os pisos, em `nai_config`:**

| chave | valor | atualizado_em |
|---|---|---|
| jev_piso_cortesia | 0.70 | 24/09 11:50 |
| jev_piso_oferta | 0.60 | 24/09 11:50 |
| jev_piso_pedido | 0.60 | 24/09 23:11 |
| jev_piso_imovel | 0.50 | 24/09 11:50 |
| v2_piso_intencao | 0.60 | 25/09 09:48 |
| cola_solta_no_catalogo | sim | 24/09 17:15 |
| secretaria_ligada | sim | 22/09 18:33 |
| pedido_ignora_oferta / pedido_ignora_anuncio | sim / sim | 24/09 12:32 / 12:34 |

Nenhuma função lê `jev_piso_imovel`. `jev_piso_pedido` só é lido por `nai_jev_pedido`, que hoje nunca tem dado. Quem definiu os pisos foram as migrações (`Arquivos/nai/118_jev_decide_por_numeros.sql` e as seguintes). O `atualizado_em` de cada um é o da criação, então ninguém mexeu depois. O painel não edita os pisos: no `/app/app.py` do container `nay-site-api`, `NAI_CHAVES_EDITAVEIS` só contém modo, pausada, envio_simulado, numeros_teste, telefone_teste_destino, janela_inicio/fim, escala_sem_parar, regra_publico, tel_telefone, aviso_motoboy_min, dados_primeiro_lembrete_min e apresentacao_proprietario. Os pisos aparecem na tela só para leitura; mudar exige `UPDATE` no banco.

**Frequência** (reconstruí a escolha do Jev com `nai_jev_decidiria(nai_jev.respostas)`, a função do próprio banco, e comparei com `nai_mente`):

| período | decisões | o banco trocou a escolha | carimbou sem trocar |
|---|---|---|---|
| Desde o Jev (24/09 12:31 a 29/09 19:04) | 714 (366 reais + 348 espelho) | **18 (2,5%)**, sendo 13 de 366 reais (3,6%) | 20 |
| Só com as perguntas novas (desde 25/09 11:07) | 657 | 14 | – |

As 18 trocas, por motivo:

- **locação → secretária pela ficha aberta** (`cola`): 9, todas em 24–25/09 (7 reais);
- **secretária → locação pela 117** (`regra`): 5 (3 reais: 12273, 12346 e 12456). Em todas, o corretor colou um card ou um print e o Jev leu como `anuncio_dele`, então a 117 acertou;
- **locação → secretária pela regex de oferta**: 2 (12460 e 12575, ambos em 29/09). O 12575 é falso positivo: uma ficha de cliente com documentos pessoais virou "está oferecendo imóvel";
- **locação → secretária por cortesia herdada**: 2 (24/09).

Antes do Jev (22/09 20:15 a 24/09 11:37) houve 125 decisões (`mente` 120, um LLM de texto; `cola` 4; `teste` 1). Para esse período, NÃO SEI quantas o banco desfez, porque `nai_mente` só guarda a decisão final e a escolha original da mente antiga não foi gravada.

Decisões em que o Jev sozinho mandou para a secretária (final `secretaria` com `por='jev'`): 10 das 714. Nove delas foram em 24–25/09, quando ainda existia a pergunta `atendente`. Desde 25/09 11:07 houve **1 de 657** (turno 12591).

**[OPINIÃO]** Hoje o "cérebro" que escolhe o atendente é regex mais estado. O Jev virou um detector de oferta ou anúncio que quase nunca é decisivo. O que ele entrega de útil é o `codigo_rejeita`, que alimenta a parede do imóvel recusado.

---

### 8. Quando o Jev falha ou demora: a reserva e se ela dá o mesmo resultado

Configuração do nó "Jev decide": httpRequest v4.2, autenticação por credencial de header (omitida), `options.timeout = 25000` ms, `onError = continueRegularOutput`, sem `retryOnFail`. Quando dá erro ou estoura o tempo, o item segue sem `answers`.

**A reserva de verdade não é a que o nó diz.** O nó "Ler o Jev" devolve `{jev:{}, reserva:true, atendente: /(imovel|casa|aluguel|…)/ ? 'imoveis' : 'secretaria'}`. Só que nenhum nó lê esse `atendente`: o "Decidir quem responde" passa apenas `JSON.stringify($json.jev || {})`, ou seja, `'{}'`. Com isso:

- `nai_decidir_com_jev` grava `nai_jev.respostas='{}'` e devolve `locacao`, com motivo "sem resposta (0.00)";
- `nai_decidir_v2` grava a intenção como `indefinida`, sem confiança;
- `nai_mente_registrar` roda as mesmas regras de sempre.

Em resumo, a reserva real é "locação, e por cima as regras de regex e de estado do banco". O comentário do nó ("vale a reserva pelo próprio texto") não corresponde ao que o fluxo faz.

**Fica registrado?** Sim, como `nai_jev.respostas = '{}'`. São 7 turnos, todos em 28/09 entre 09:28 e 10:08 (12119, 12120, 12121, 12124, 12128, 12129 e 12151). Os 7 foram para locação e 6 tiveram resposta enviada. NÃO SEI a causa: as execuções de 28/09 não estão mais no n8n; seria preciso olhar os logs da OpenRouter ou um backup do sqlite do n8n. Hoje o n8n guardava 52 execuções com o Jev, com 0 erros e latência de 285 a 551 ms (mediana 471 ms, `executionTime` do nó). Nenhuma chegou perto dos 25 s.

**Dá o mesmo resultado?** Quase sempre. Como todas as outras regras rodam do mesmo jeito sem o Jev, a reserva só mudaria o desfecho onde a decisão final foi secretária com `por='jev'`: 10 das 714 decisões (7 reais) e, desde 25/09 11:07, 1 de 657 (turno 12591). O que se perde na falha:

- a detecção de oferta ou anúncio que a regex não pega;
- `codigo_rejeita`: a recusa não entra em `nai_estado_conversa`, então o imóvel recusado não fica barrado. Houve 9 turnos com recusa gravada, de 27/09 em diante;
- `intencao`, que ninguém usa.

`pediu_imovel` fica `true` com ou sem o Jev. Se o Jev só demorar, o custo é até 25 s antes do agente (pela configuração; nunca observado). Se a OpenRouter responder 200 com só parte das chaves, o banco usa o que veio e trata o resto como 0 ou NULL.

---

### 9. `nai_pedido_do_turno`: campos, como cada um é extraído, e o que acontece quando vem vazio

**A premissa está errada em dois pontos:**

- A função não extrai quartos, mobília nem bairro. Esses três saem de outra função, `nai_pedido_de_perfil` (regex, usada por `nai_contexto_corretor` e `nai_etapa_calcular`), e dos argumentos que o próprio modelo passa ao `buscar_por_perfil` (`$fromAI`).
- Nenhum campo usa modelo: é 100% regex mais tabelas (`imoveis`, `vw_condominio_som`, `bairro_zona`, `bairro_area`) mais histórico (`nai_turno`, `mensagens`, `nai_saida`).

A função é `STABLE` e recalcula com `now()`, ou seja, não é uma foto do turno. O turno 12451 (29/09 09:14, "Estou procurando uma casa em condomínio fechado até quatro mil.") hoje devolve `negocio='venda'`, porque 32 minutos depois o mesmo corretor escreveu "Tens algum acqua pra venda?" (turno 12471). Às 09:14, a fala mais nova com palavra de negócio era a 12268 (locação).

| campo | como sai | vazio ou ambíguo |
|---|---|---|
| `texto` | `nai_turno.texto`, já passado por `nai_corrigir_nomes` em `nai_abrir_turno` | – |
| `tipo` | `nai_tipo_da_conversa` → `nai_tipo_das_falas` sobre [texto atual, até 30 turnos em 30 dias, até 30 mensagens recebidas em 60 dias, incluindo as da outra linha da pessoa]. Vale a fala mais nova em que `nai_tipo_pedido` (regex) acha algo e que não seja fala dele (`nai_fala_e_dele`: oferta ou anúncio dele). A regex tem ordem fixa: casa > apartamento > cobertura > flat > sala/loja/galpão (só com marca comercial ou verbo de pedido) > lote > chácara > prédio. Devolve um padrão LIKE (`'Casa%'`). "casa ou apartamento" vira `Casa%`. Ignora `zerado_em`. | NULL: nenhuma parede de tipo na saída |
| `rotulo` | `nai_rotulo_do_tipo(tipo)` | – |
| `negocio` | `nai_negocio_da_conversa`, em três passos: (1) a mensagem atual; (2) os últimos 40 turnos em 3 dias (ou desde `zerado_em`), primeiro pela **palavra** (`nay_negocio_pedido`: vend/compr → venda, loca/alug → locação, as duas → `ambos`, valor ≥ `piso_venda` 100000 → venda) e depois pelo **valor** (`nai_negocio_pelo_valor`: só números com cara de dinheiro; 300 a 30000 é locação, ≥ 100000 é venda, entre 30 mil e 100 mil fica NULL); (3) `nai_negocio_do_que_recebeu`, a finalidade dos imóveis enviados em 3 dias, se forem todos iguais | NULL ou `ambos`: nenhuma parede de negócio em `nai_conferir_imoveis_da_saida`; em `nai_fila_dos_outros_imoveis`, com NULL só passa o código que ele digitou. "aluguéis" não casa com `aluguel` |
| `teto` | `nay_maior_valor(texto)`, só deste turno: o **maior** valor entre "5mil", "700k", "1,5 milhão", "3.500" e "R$ 3500". Antes tira telefone, CEP, data, hora e CPF | "até 3500" sem R$ nem ponto dá NULL, e "quatro mil" por extenso também (testado) |
| `imoveis` | `nai_imoveis_pedidos(texto, telefone)`, ordenado pela posição no texto. Junta os códigos de 3 a 5 dígitos que existem no catálogo (`nay_codigos_citados`, depois de `nay_tirar_valores`) e os imóveis do condomínio citado (`nai_imovel_pelo_condominio`: nome inteiro com 8 ou mais letras, núcleo com 6 ou mais que não seja nome de bairro, chave de som igual e, em último caso, trigram ≥ 0,50 descartando pedaços que contêm bairro) | `[]`: sem "passe do citado". Exemplo: no 12428, "soto mobiliado na ponta negra ii" vira [2472, 3564, 3848, 5755] |
| `cortesia` | `nai_e_so_cortesia`: até 40 caracteres e uma lista fechada (ok, obrigado, bom dia, 👍…) | false |
| `oferta` | `nai_oferece_imovel`: 4 ramos de regex ("se quiser te envio", "tenho um…", "tenho … mobiliado/quartos…", "como anunciar") | falso positivo real: o 12575 |
| `link` | `nai_e_link_de_produto`: `wa.me/p/`, `api.whatsapp.com/product`, `/catalog/` | – |
| `pede_lista` | `nai_pede_os_valores` (regex) | – |
| `sem_bairro` | `nai_sem_preferencia_de_bairro` OR `nai_e_a_cidade` | – |
| `de_imovel` | `nai_e_assunto_de_locacao`: lista de palavras entre `\m…\M`. `mobiliad\M` nunca casa com "mobiliado" (o 12428 deu `de_imovel=false`) | false: a regra 117 não salva |

**Quem lê cada campo:**

- `nai_mente_registrar` lê `cortesia`, `de_imovel`, `oferta`, `link` e `texto`;
- `nai_conferir_imoveis_da_saida` lê `tipo`, `negocio` e `imoveis`: barra na caixa de saída o imóvel de tipo ou negócio errado, exceto o apontado quando são até `passe_citado_ate`=2;
- `nai_fila_dos_outros_imoveis` lê `oferta` e `link`.

`teto`, `pede_lista`, `sem_bairro` e `rotulo` são calculados, mas nenhum desses chamadores os lê.

---

### 10. O "estado" da conversa (o que "Ler estado" devolve)

**A premissa confunde duas coisas.** O nó "Ler estado" roda `SELECT nai_estado_v2(contato, 3)` e só alimenta o nó "Montar pergunta ao Jev". O modelo que responde não recebe esse estado. O que ele recebe está logo abaixo, em "O que a Nay lembra de fato".

| campo | onde mora | quem escreve | quando zera |
|---|---|---|---|
| `codigo_foco`, `foco_origem` (e `foco_desde`) | `nai_estado_conversa` | `nai_estado_gravar_v2`, chamada por `nai_enfileirar_resposta_ferramentas` quando sai código na resposta. O foco é o **maior** código (`max()`), não o último como diz o comentário; a origem é `'mostramos'` | NULL não apaga. Só sai do foco se for recusado. 59 das 219 linhas têm foco |
| `codigos_mostrados` | idem | idem, somando sem repetir | nunca (máximo de 17 na tabela) |
| `codigos_rejeitados` | idem | `nai_decidir_v2`, a partir do `codigo_rejeita` do Jev | nunca. 4 contatos têm |
| `visita_pendente` | idem | nenhum chamador passa `p_visita`: 0 de 219 linhas | o Jev sempre recebe "nao" |
| `papel` | idem | nenhum chamador passa `p_papel`. As 188 linhas com papel vieram da semeadura de 25/09 09:48 (`foco_origem='semeado'` em 169) | – |
| `ultima_fala_dela` | idem | `p_texto` do nó "Enfileirar resposta": o texto do modelo **antes** das guardas da conferência, não necessariamente o que saiu. Vale para os caminhos corretor, secretária, proprietário e Fernando; o caminho `codigo` (card por número solto) e o `cortesia` não atualizam nada | nunca |
| `tel_assumiu`, `nome` | `nai_contato` | comandos e pausas (ver 13) | – |
| `ultimas_trocas` | calculado: os 3 últimos `nai_turno` (ele) mais os `nai_saida` tipo texto do mesmo turno (ela) | – | a leitura de `nai_saida` não filtra estado, então entra texto bloqueado que nunca saiu. No 12347 entrou o aviso interno "Tel, o corretor … pediu fotos do 109…" |

A criação de `nai_estado_conversa`, `nai_turno_decisao`, `nai_estado_v2` e `nai_decidir_v2` não está em nenhum `.sql` do repositório (só a `140_…` recria `nai_estado_gravar_v2`): o banco está à frente. `nai_zerar_conversa` não toca `nai_estado_conversa`. Ela marca `nai_contato.zerado_em` e renomeia as sessões `nai:%:<id>` de `nai_memoria`, mas não a da secretária (`nai:corretor:<id>-sec`, que não casa com o LIKE).

**O que a Nay lembra de fato de um turno para o outro:**

1. **Memória do n8n** (`memoryPostgresChat`, tabela `nai_memoria`, chave `cab.memoria` = `nai:<papel>:<contato>[:v<visita>]`). `contextWindowLength` é 20 para o corretor, 40 para proprietário e Fernando, e 20 para a secretária, cuja sessão tem o sufixo `-sec`. **São duas memórias separadas**: quando a mente troca locação ↔ secretária, uma não vê o que a outra disse. A mensagem "human" gravada é o envelope inteiro (média de 968 caracteres; 1585 começam com "(informação de sistema"; 476 contêm "IMOVEL DESTA CONVERSA"). Por isso contextos velhos ficam na memória junto com o novo.
2. **Cabeçalho recalculado a cada turno** em `nai_abrir_turno` (`cab.contexto` = `nai_etapa_para_o_modelo` + `nai_contexto_corretor` + `nai_giria_explica`). Ele traz:
   - a etapa;
   - as visitas abertas e os dados que faltam;
   - os imóveis que ele já recebeu (`envios` de 30 dias, até 15);
   - "IMOVEL DESTA CONVERSA";
   - se é busca;
   - como chamá-lo;
   - parceria;
   - "já estão conversando" (12 h);
   - "já sugeriu visita hoje";
   - o histórico da Nay antiga, quando a memória tem menos de 6 mensagens.

**O que a Nay NÃO lembra de forma estruturada:**

- teto, bairro, quartos e mobília que o corretor já disse. Só existem na memória de chat; `nai_buscar_por_perfil` re-deriva negócio e tipo, mas não teto nem bairro;
- a intenção do Jev;
- `codigo_foco`;
- que um imóvel foi recusado: isso só vira parede de saída, o modelo não é informado;
- os imóveis da lista do `buscar_por_perfil`: o formato `#5733*` não tem "Código:", então não entram em `codigos_mostrados` nem na "mesa" de `nai_imovel_da_conversa`;
- o que a outra atendente (locação ou secretária) falou;
- o que de fato saiu depois das guardas.

---

### 11. Como a Nay sabe de qual imóvel se fala ("esse", "dele", "o primeiro")

**A premissa não se confirma.** Não existe uma ordem única de prioridade aplicada por um árbitro. Três fontes entram como texto no prompt do modelo ao mesmo tempo, e o modelo escolhe. Depois da resposta, o banco grava o imóvel do turno com **outra** ordem. O `codigo_foco` (imóvel em foco do estado) não entra nesse caminho, só vai para o Jev. Sobre a citação: o texto da mensagem citada **nunca chega**. Em 7 dias foram 3.726 mensagens recebidas no fluxo `nai`, 0 com `mensagens.citado`, 301 com `citado_id` e só 75 em que o `citado_id` resolve para um imóvel.

**Antes do modelo** (o que ele lê):

1. **Card colado** (nó "Juntar mensagens"): se o texto tem "Código: NNNN" e 📍 ou •, a mensagem é substituída por "ele COLOU o card do imovel NNNN… tratando o NNNN como o imovel escolhido".
2. **Mensagem marcada** (nó "Reservar mensagens" → `nay_imovel_da_citacao(citado_id)`). A função tenta, em ordem:
   - `envios.message_id`;
   - `nai_saida.message_id` com código;
   - um único "Código:" no texto da NAI;
   - uma mensagem dele com um único código;
   - `grupo_mensagens`;
   - a saída da Nay antiga.

   No texto do "NAI (corretor)" isso vira "ele MARCOU a mensagem do imovel N… NAO pergunte qual e". Com mais de um imóvel (`nay_opcoes_da_citacao`), vira uma pergunta com lista. Mas a condição `citadoId && !citado` é sempre verdadeira (o texto citado nunca chega), então vai junto a frase oposta: "ele respondeu CITANDO uma mensagem que voce nao consegue ver… PERGUNTE. Nunca suponha." Conferi as duas frases juntas no prompt real do turno 12556 (execução 142098).
3. **Imóvel desta conversa**: `cab.contexto` → `nai_contexto_corretor` → `nai_imovel_da_conversa(contato, texto do turno)`. A ordem é:
   - (1) código escrito agora que existe no catálogo;
   - (1b) nome de condomínio que aponta um único imóvel, filtrado pela finalidade da conversa (190);
   - (2) a "mesa" de 48 h (ou desde `zerado_em`): `nai_saida.codigo`, "Código:" nos textos dela, `nai_turno.codigo`, códigos nas mensagens recebidas e `envios`, filtrados pela finalidade, exceto os códigos que ele digitou nos últimos 3 dias. Mesa vazia → NULL;
   - (3) a primeira palavra do condomínio, entre os imóveis da mesa;
   - (4) o `nai_turno.codigo` do último turno nas últimas 6 h;
   - (5) um único imóvel na mesa em 6 h;
   - (6) NULL, e ela pergunta.

   **A citação não entra nesta função.** O mesmo cabeçalho ainda pode trazer:
   - "ELE MUDOU DE IMOVEL";
   - "ELE FALOU DE UM IMOVEL NOSSO PELO NOME";
   - "ELE DESCREVEU O IMOVEL" (`nai_imovel_pela_descricao`);
   - "ELE DISSE SIM" (responde à última pergunta dela, em até 12 h).
4. **Memória** (`nai_memoria`, janela de 20), com os "IMOVEL DESTA CONVERSA" de turnos anteriores.
5. **Ferramentas**:
   - `imovel_do_disparo` (`nay_qual_imovel`): lista os envios para o corretor em 48 h e nunca escolhe;
   - `escalar_ao_tel` → `nay_escalar`, que tem a "parede 2" (`nay_codigo_confirmado`). Essa parede só conhece mensagens com o código e `envios`; não conhece `nai_saida` nem a citação.

**Sinais calculados que ninguém usa:**

- `nay_aviso_do_foco` é calculado no "Reservar mensagens" (`focoAviso`), mas nenhum nó usa;
- o `codigo_quer` do Jev vai para `nai_turno_decisao.codigos_pedidos` e ninguém lê. Em 114 turnos reais o Jev apontou um código: bate com `nai_turno.codigo` em 49, diverge em 24, e em 41 o turno ficou sem código.

**Depois do modelo:**

- O nó "Achar codigo na resposta" pega todos os "Código: N" da resposta. Se não houver nenhum, usa, nessa ordem: o "Código:" do texto citado (nunca vem), `codigoCitado`, o "Código:" do que ele escreveu, `codigosDele[0]` e o número solto do citado.
- `nai_conferir_resposta` (passo 01) usa o código único da resposta ou, se não houver, `nai_imovel_da_conversa(contato, escreveu)`. Com isso faz `UPDATE nai_turno.codigo`, que alimenta os passos 2 e 4 dos turnos seguintes, e anota `imovel_da_conversa` em `nai_conferencia` (em 30 dias: 561 com imóvel, 706 sem).
- `nai_enfileirar_resposta_ferramentas` grava o foco do estado.

A ordem se contradiz: o cabeçalho prefere o código digitado (a citação nem conta), e o pós-processamento prefere a citação ao código digitado.

**"O primeiro", "o segundo":** nenhum código resolve ordinais, e a lista do `buscar_por_perfil` não entra na mesa. Isso fica inteiro com o modelo lendo a própria memória. Nos últimos 7 dias não houve nenhum turno real de escolha por ordinal, então NÃO SEI como ela se sai. Para saber, seria preciso um caso de treino com lista seguida de "o segundo".

**Exemplo de acerto: turno 12556 (29/09 16:01, Paulo).** Ele escreveu "Boa tarde, Nay. Tudo bom? Esse imóvel está disponível?" marcando uma mensagem. A citação resolveu para 3210, o prompt levou "MARCOU a mensagem do imovel 3210" (e a frase contrária junto), o modelo chamou `o_que_sei_do_imovel` e respondeu "📌 Status: Disponível" com o card do 3210. O turno ficou com `codigo=3210`. O cabeçalho não tinha "IMOVEL DESTA CONVERSA" (`nai_imovel_da_conversa` deu NULL): acertou só por causa da linha da citação.

**Exemplo de erro 1: turnos 12346 e 12347 (28/09 18:44, Patricia).**

1. Ela mandou o print de uma casa de outra imobiliária. A leitura do GPT dizia "A propriedade possui 109 m²…".
2. `nay_codigos_citados` guardou o "109": "m²" com ² não é retirado, "m2" é. O imóvel 109 existe (casa de venda em Petrópolis, indisponível), então o turno 12346 ficou com `codigo=109`.
3. No turno seguinte, "Boa noite! Essa casa ainda está disponível 👆🏻", o passo 4 escolheu 109.
4. O portão de fotos pediu fotos do 109, foi gerado um aviso ao Tel (bloqueado), e ela respondeu perguntando o bairro.

O mesmo turno 12346 também foi um caso da regra 117: o Jev leu `anuncio_dele`. O erro ainda se reproduz: `nay_codigos_citados('possui 109 m² e')` devolve `{109}` hoje.

**Exemplo de erro 2: turno 12123 (28/09 09:34, Lily).**

1. Ela escreveu "Esse mesmo" marcando uma mensagem. A citação deu 3050 (certo) e `nai_imovel_da_conversa` também deu 3050.
2. O modelo chamou `escalar_ao_tel(3050)`. Em `nay_escalar`, a parede 2 deu `nay_codigo_confirmado='nao'`: não havia mensagem com 3050 em 48 h, e os `envios` tinham 5728 e 5757. A NAI tinha mandado fotos do 3050 às 09:29, mas essa função não lê `nai_saida`.
3. A parede devolveu a lista do `nay_qual_imovel`, e saiu para a corretora "É de algum destes que te mandei? • 5757 — Saint Martin • 5728 — Park Golf • nenhum desses".

O `codigo_quer` do Jev tinha escolhido 2539 (0,82), também errado, mas ignorado. Os turnos 12122 e 12123 rodaram em paralelo, com 10 s de diferença.

**Onde ela ainda erra:**

- números lidos em prints ou áudio que parecem código (área com m², valores sem R$);
- as funções da Nay antiga (`nay_codigo_confirmado`, `nay_qual_imovel`), que não enxergam o que a NAI mandou;
- o prompt com as frases "não pergunte" e "pergunte" juntas;
- o `nai_turno.codigo` errado, que se propaga por até 6 h (passo 4);
- os ordinais em listas;
- a memória com contextos velhos.

---

### 12. A "próxima pergunta" da busca por perfil

**A premissa está desatualizada.** "Bairro → faixa → mobília" era a sequência antiga, substituída pela 146 e depois pela 190. Mobília e quartos **nunca são perguntados**: só aparecem no fim da lista ("Se quiser mais opções, me diz …"). A ordem que a memória descreve ("locação/venda → tipo → valor → região, cada pergunta 1x/24h") está certa para quem chega pedindo imóvel, com três correções:

- quem veio do grupo é perguntado primeiro a região e depois o valor;
- a pergunta de negócio **não** tem trava de 24 h;
- a trava do tipo é própria (procura "casa ou apartamento?" nos textos dela em 24 h).

A 190 entrou em 29/09 por volta das 19:00 (arquivos `190_venda_locacao_e_filtro.sql` às 19:01 e `190p_remendos.sql` às 19:02). O último turno de produção com `buscar_por_perfil` foi o 12611, às 18:45: **nenhum turno real rodou ainda com a ordem nova**.

**Onde está definida:** `nai_buscar_por_perfil(p_turno, p_bairro, p_teto, p_quartos, p_mobilia)`, `STABLE`, chamada pela ferramenta `buscar_por_perfil`. Bairro, teto, quartos e mobília vêm do modelo via `$fromAI`, e é `nai_contexto_corretor` que manda o modelo chamar a busca "AGORA com bairro=…, teto=…". A função calcula primeiro:

- `v_direta`: `nai_imovel_da_conversa(...) IS NULL` (chegou pedindo) ou não (veio do grupo);
- negócio e tipo, **da conversa**;
- `v_livre`: cidade ou "tanto faz";
- `v_mostra_logo`: ele pediu os valores, ou o bairro tem de 1 a `limite_sem_teto`=5 imóveis no perfil.

Depois devolve **uma** pergunta por vez:

| ordem | condição para perguntar | texto |
|---|---|---|
| 1 | negócio NULL na conversa **e** em `nai_negocio_do_pedido` | "Seu cliente procura imóvel para alugar ou para comprar?" (com a frase de abertura se não houver nenhum filtro) |
| 2 | tipo NULL, nenhum "tanto faz/os dois/…" nas mensagens de 24 h, e "casa ou apartamento?" não perguntado em 24 h | "Seu cliente procura casa ou apartamento?" |
| 3 | teto NULL, sem "sem valor", sem `mostra_logo`, valor não perguntado em 24 h, **e** (chegou pedindo OU já tem região) | "[Eu vou fazer um filtro com você…] Até que valor o seu cliente quer?" |
| 4 | bairro vazio, sem "tanto faz", região não perguntada em 24 h | "Qual região ou bairro atende o seu cliente?" / "Sem problema! …" / (veio do grupo) "Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?" |
| 5 | – | Lista: até 5 imóveis no bairro e até 5 nos vizinhos (se sobrar 1 só, vai o card; se nenhum, "não tenho…" ou "Você quis dizer X?"), mais "Qual deles é de seu interesse?…", mais a oferta dos filtros que faltam |

**O "já perguntei" não mora em tabela.** `nai_filtro_ja_perguntado` procura por regex nos textos que ela mesma mandou (`nai_saida`, 24 h, `estado <> 'bloqueado'`). Duas consequências:

- **O fim da lista conta como pergunta de valor.** A frase "Se quiser mais opções, me diz até que valor o cliente vai…" casa com `at[ée] que valor`. Confirmei com a Nora (contato 10462): `nai_filtro_ja_perguntado(10462,'valor') = true` por causa da saída 36466, que era o fim de uma lista. Depois da primeira lista, a pergunta de valor não volta naquele dia.
- **O número solto não é protegido.** O roteador só protege o número solto quando `nai_esperando_valor` é verdadeiro, e a regex dele (`faixa de pre|qual (o )?valor|ate quanto|teto de valor`) **não** reconhece a pergunta nova "Até que valor o seu cliente quer?" (testei: false). Além disso, 1000, 1200, 1500, 1800, 2000, 2200, 2500, 2800, 3000, 3200, 3500, 3800, 4000, 4500 e 5000 são todos códigos de imóvel. Uma resposta "3500" vai pelo caminho `codigo` e recebe o card do imóvel 3500. Até agora a pergunta nova saiu 2 vezes (28/09 10:45 e 29/09 18:45) e nenhuma resposta foi um número solto. **[OPINIÃO]** Esse risco vai aparecer.

**Cenários** (as simulações rodaram em transação só leitura, com os turnos reais 12600 e 12431):

- **Responde tudo de uma vez.** A busca pula tudo o que já sabe e lista. No caso real 12595 (29/09 17:14, Sulivam), "Vc tem casa? Na média de 5mil", só havia uma opção e saiu o card do Vila do Sol Maior (Chapada, R$ 4.400). Na simulação 12600 com (Coroado, 5000, 3 quartos) a resposta foi "No Coroado não tenho nenhuma casa nesse perfil, nem nos bairros aqui perto."
- **Responde fora de ordem.** Cada argumento que chega preenche o seu lugar, e só se pergunta o que falta, na ordem fixa. No 12600 (veio do grupo, imóvel da conversa 5746):
  - Flores sem teto → "Eu vou fazer um filtro… Até que valor o seu cliente quer?";
  - teto 5000 sem bairro → "Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?";
  - teto "sem valor" → "Sem problema! Qual região ou bairro atende o seu cliente?".

  No 12431 (Nora, chegou pedindo): sem nada → "Qual região ou bairro atende o seu cliente?" (o valor foi pulado pelo fim da lista); Ponta Negra → a lista.
- **Muda de ideia.**
  - Negócio: vence a fala mais nova com palavra, em 3 dias; depois, a mais nova com valor.
  - Tipo: vence a fala mais nova com tipo. Os argumentos do modelo não mudam o tipo, a não ser que o bairro passado traga a palavra. Na simulação, Flores e Adrianópolis continuam "nenhuma casa" por causa do "casa" do 12595.
  - Bairro e teto: vale o que o modelo passar **nesta** chamada; a função não guarda nada. Se ele trocar o bairro e esquecer o teto, a pergunta de valor já foi feita, e ela lista sem teto.

  O caso real que motivou a 190 é o 12600 (29/09 17:35): "mais um Coroado … 3 quartos". O modelo passou bairro=Coroado e teto vazio, e a função perguntou "alugar ou comprar?" mesmo depois dos "5mil" às 17:14. A entrada e a saída da ferramenta estão na execução 143364 do n8n: `{bairro:"Coroado", teto:"", quartos:"3"}` → "Seu cliente procura imóvel para alugar ou para comprar?". O comentário da 190 dentro da função cita esse caso. Com a 190, o valor passou a definir o negócio: hoje, `nai_negocio_das_falas` sobre [12600, 12595] devolve `locacao`.
- **Laço possível.** Pela lógica do código (não observado), "tanto faz" ou "os dois" como resposta a "alugar ou comprar?" não definem o negócio (`nay_negocio_pedido` só devolve `ambos` com as duas palavras), e essa pergunta não tem trava de 24 h. A mesma pergunta volta enquanto o modelo chamar a ferramenta.

---

### 13. Existe máquina de estados explícita por conversa?

**Não.** Não há tabela com o estado atual e as transições permitidas da conversa: nenhuma tabela casa com `transic|maquina|fsm|state`. O mais próximo é `nai_visita.estado`, que tem 13 estados listados na CHECK `nai_visita_estado_check` (coletando, confirmando, aguardando_rayssa, aguardando_proprietario, negociando, aguardando_acesso, aguardando_motoboy, confirmada, com_tel, realizada, encerrada, cancelada, expirada) mais `aguardando`. Mas é só a visita, e as transições estão espalhadas em 17 funções, sem tabela de transições:

- crm_visita_excluir, crm_visita_realizada;
- nai_agenda_tick, nai_aprovar_visita, nai_cancelar_visita, nai_comando_tel, nai_confirmar_visita;
- nai_mudar_horario, nai_pedir_ao_proprietario, nai_pedir_visita, nai_prosseguir_acesso, nai_responder_horario;
- nai_resposta_motoboy, nai_resposta_proprietario, nai_resultado_visita;
- nai_visita_corretor_confirmou, nai_visita_seguir_para_proprietario.

Hoje: cancelada 27, encerrada 26, expirada 15, confirmando 1.

**O que faz esse papel hoje:**

| situação | onde | quem escreve |
|---|---|---|
| Etapa (identificacao / recebeu_imovel / agendamento_visita) | `nai_etapa_contato.etapa` (CHECK), com histórico em `nai_etapa_evento` (96 eventos) | `nai_etapa_atualizar`, chamada em `nai_abrir_turno` a cada turno de corretor. **Não é transição, é recálculo** a partir dos fatos (`nai_etapa_calcular`): visita aberta → agendamento; imóvel enviado ou foto em 7 dias sem busca depois → recebeu; senão, identificação. Pode voltar atrás. Hoje: identificacao 39, recebeu_imovel 31, agendamento_visita 1. Lida por `nai_etapa_para_o_modelo`, `crm_parceria_funil` e `crm_parceria_marcas` |
| Quem atende o turno | `nai_turno.atendente`, `nai_mente`, `nai_jev`, `nai_turno_decisao` | `nai_mente_registrar`, `nai_decidir_com_jev`, `nai_decidir_v2`, `nai_ferramentas_v2`, `nai_registrar_saida_v2` |
| Ficha de cadastro de imóvel | `nai_imovel_novo.situacao` (colhendo 2, descartada 3, subido 1). "colhendo" com menos de 24 h prende na secretária | `nai_sec_abrir_cadastro`, `nai_sec_guardar_do_imovel`, `nai_sec_guardar_foto(s)`, `nai_imovel_novo_subir` |
| Tel assumiu / pausa por conversa | `nai_contato.humano_assumiu_em` / `humano_motivo` (327 contatos), lida por `nai_tel_com_a_conversa` | `nai_tel_assumiu`, `nai_comando_tel` (ASSUMIR/DEVOLVER), `nai_parar_chat`, `nai_liberar_chats_da_visita`, `nai_zerar_conversa`, `crm_nay_parar`, `crm_nay_voltar` |
| Pausa geral e modo | `nai_config.pausada` = nao (19/09), `modo` = todos (22/09) | painel e comandos |
| Imóvel em foco, mostrados, recusados | `nai_estado_conversa` | `nai_estado_gravar_v2`, via `nai_decidir_v2` e `nai_enfileirar_resposta_ferramentas` |
| Imóvel do turno (o "fio") | `nai_turno.codigo` | `nai_conferir_resposta` |
| Filtro da busca | **sem tabela**: regex nos textos dela em `nai_saida` (`nai_filtro_ja_perguntado`, 24 h; "casa ou apartamento?", 24 h) e `nai_esperando_valor` (última saída, 2 h) | o próprio envio |
| Porta (se é atendido) | `nai_turno.porta`, `corretores.aprovado` | `nai_deve_atender`, via `nai_abrir_turno` |
| Mensagem e saída | `mensagens.status` (Recebido / Processando / Respondido / Com o Tel), `nai_saida.estado` (CHECK: pendente, enviando, enviado, bloqueado, erro, simulado) | n8n e `nai_liberar_saida` / `nai_confirmar_envio` |
| Follow-up, lembrete, retomada | `nai_followup.estado` (enviado 26, pulado 13), `nai_lembrete.estado`, `nai_retomada.estado` (enviado 11, pendente 4) | `nai_followup_rodar`; `nai_comando_lembrete` e `nai_lembretes_disparar`; `nai_retomada` só pelo script `Arquivos/retomar_sabado.py` (nenhuma função do banco escreve) |
| Marco de conversa zerada | `nai_contato.zerado_em` (25 contatos) | `nai_zerar_conversa`. É respeitado por `nai_imovel_da_conversa`, `nai_contexto_corretor` e `nai_negocio_da_conversa`, mas **não** por `nai_tipo_da_conversa` (30 e 60 dias), `nai_etapa_calcular` (7 dias), `nai_filtro_ja_perguntado` nem `nai_estado_v2` |

**[OPINIÃO]** O papel da máquina de estados está dividido entre um recálculo a cada turno (etapa, imóvel da conversa, negócio, tipo), marcas grudentas com prazo (ficha de 24 h, cortesia de 6 h, pausa do Tel) e o texto que ela mesma enviou (as perguntas do filtro). Não existe um lugar só que diga "esta conversa está esperando X". Cada função reconstrói isso do seu jeito e com a sua janela de tempo (6 h, 12 h, 24 h, 48 h, 3, 7, 30 ou 60 dias). É daí que vêm as divergências dos exemplos das perguntas 11 e 12.

---

## Bloco 3 — Responder (perguntas 14 a 21)

Fontes: wf_NaiAtendLocacao1.json` (exportado hoje), versão viva das funções (`pg_get_functiondef`), tabelas do `naydb` lidas em 29/09 entre 19h e 20h (Manaus), sqlite do n8n (execução 143446), `crontab -l` e log do cron em `/root/nay-publicador/logs/`. Horários em Manaus.

Três fatos atravessam o bloco inteiro:

- **O texto cru do modelo não é guardado em `nai_turno` nem em `nai_saida`.** Ele só existe em `nai_memoria` (a memória do n8n, `memoryPostgresChat`: linha `type='ai'`, sem `turno_id` e sem data) e, por poucas horas, no `execution_data` do n8n. Conferi na execução 143446: o `output` do nó "NAI (corretor)" é igual, caractere por caractere, à linha `ai` da memória. `nai_turno.exec_id`, `ms_total`, `prompt_versao` e `modelo` existem como colunas e estão vazios em 3.437 de 3.437 turnos.
- **A memória guarda o que o modelo escreveu, e não o que saiu depois das correções.** No turno seguinte o modelo "lembra" de ter dito coisas que o corretor nunca recebeu (exemplos na 18).
- **O mesmo agente atende o Tel.** Um turno de papel `tel` que não é comando cai na rota `agente` do "Rotear pelo cabeçalho" e vai para o "NAI (corretor)", com o prompt do corretor (`nai_abrir_turno`: `nai_prompt_de(CASE WHEN v_papel='tel' THEN 'corretor' ...)`). É por isso que `guardar_do_imovel` e `responder_pendencia` estão entre as ferramentas do corretor.

---

### 14. Ferramentas do agente do corretor

O agente "NAI (corretor)" tem **16 ferramentas** ligadas por `ai_tool`: 15 nós `postgresTool` e 1 `toolWorkflow`. A secretária tem outras 4 (`consultar_o_que_sei`, `perguntar_ao_tel`, `abrir_cadastro_de_imovel`, `guardar_do_imovel_novo`). O proprietário tem 1 (`resposta_do_proprietario`) e o Fernando tem 1 (`resposta_do_motoboy`). Nenhuma delas está no corretor.

Legenda: **M** = parâmetro que o modelo preenche via `$fromAI`. **I** = parâmetro que o n8n injeta por expressão. O uso nos últimos 30 dias vem de `nai_turno.ferramentas` e está no formato turnos de corretor / turnos do Tel.

| Ferramenta (nó) | O que chama | Recebe | Devolve | texto_pronto? | Uso 30d |
|---|---|---|---|---|---|
| `imovel_por_codigo` | SQL escrito dentro do nó: `imoveis` + `nai_card_do_imovel(codigo)` | M: codigo | texto_pronto (o card), disponivel, e_parceiro, aceita_financiamento, qtd_fotos, administrado, instrucao_para_voce (administrado, forma de pagamento, descrição do anúncio via `nay_descricao_segura`; parceiro sai sem descrição) | sim | 178 / 1 |
| `resumo_do_condominio` | SQL no nó sobre `imoveis` + `nay_cond($1)` | M: condominio | texto_pronto ("no X tenho N imóveis…"), instrucao | sim | 10 / 0 |
| `listar_no_condominio` | SQL no nó (até 8 imóveis, faixa de 0,85 a 1,10 do teto) | M: condominio, negocio, quartos (number), valor_teto (number) | texto_pronto (lista ou "nao encontrei…"), instrucao | sim | 4 / 0 |
| `buscar_por_perfil` | `nai_buscar_por_perfil(turno,bairro,teto,quartos,mobilia)` | I: turno_id. M: bairro, teto, quartos, mobilia | texto_pronto, instrucao | sim | 180 / 0 |
| `disponibilidade_no_condominio` | `nay_disponibilidade_no_condominio(nome,negocio)` | M: condominio, negocio | texto_pronto, codigo, instrucao | sim | 94 / 1 |
| `o_que_sei_do_imovel` | `nai_o_que_sei_do_imovel(codigo,pergunta)` | M: codigo, pergunta | texto_pronto, sabe, instrucao | sim, quando sabe=true | 133 / 0 |
| `guardar_do_imovel` | `nay_guardar_do_imovel(codigo,assunto,texto,telefone)` | M: codigo, assunto, texto. I: telefone ("Juntar mensagens") | uma coluna chamada texto_pronto com o recibo ("guardei…") ou a recusa | só no nome | 0 / 1 |
| `imovel_do_disparo` | `nay_qual_imovel(telefone)` | I: telefone. O modelo não passa nada | texto_pronto (lista do que mandamos), `codigo` NULL fixo, instrucao | sim | 16 / 0 |
| `responder_pendencia` (toolWorkflow) | subfluxo "Nay - responder pendencia" → `nay_responder_conversando(pendencia_id,texto,msg_id,telefone)` | M: pendencia_id, texto. I: msg_id ("Gravar na fila"), telefone | acao, texto_pronto, avisar, msg_corretor. O subfluxo manda a mensagem ao corretor por httpRequest direto na Z-API | sim | 0 / 1 (23/09) |
| `escalar_ao_tel` | `nai_escalar(turno,codigo,assunto,disse)` | I: turno_id. M: codigo, assunto, disse | texto_pronto: `SILENCIO` quando escala; ou a resposta da base, a frase fixa de parceria, a pergunta da busca, "Recebi, X! Já te respondo por aqui." (mídia), ou um texto do `nay_escalar` com `[INSTRUCAO: …]`/`ATENCAO:` dentro | sim | 145 / 3 |
| `dados_do_corretor` | `nai_dados_do_corretor_tool(turno)` | I: turno_id | só instrucao_para_voce | **não** | **0** |
| `pedir_visita` | `nai_pedir_visita(turno,codigo,quando,'')` | I: turno_id e `p_qualificado=''` fixo. M: codigo, quando | texto_pronto, instrucao | sim | 77 / 1 |
| `guardar_dados_da_visita` | `nai_guardar_dados_visita(turno,codigo,visitante_nome,visitante_cpf,corretor_nome,corretor_cpf,corretor_creci)` | I: turno_id. M: os outros 6 | texto_pronto, instrucao | sim | 16 / 0 |
| `responder_horario_do_proprietario` | `nai_responder_horario(turno,codigo,aceita,outro_quando)` | I: turno_id. M: 3 | texto_pronto, instrucao | sim | 7 / 0 |
| `mudar_horario_da_visita` | `nai_mudar_horario(turno,codigo,quando)` | I: turno_id. M: 2 | texto_pronto, instrucao | sim | 3 / 0 |
| `resultado_da_visita` | `nai_resultado_visita(turno,codigo,resultado,obs)` | I: turno_id. M: 3 | texto_pronto, instrucao | sim | 8 / 0 |

**Quem preenche.** Todo parâmetro de negócio (código, bairro, horário, CPF) vem do modelo, via `$fromAI(...)` com `?? null` ou `?? 0` como padrão. O `turno_id` é **injetado, não escolhido pelo modelo** (`$('Abrir turno').first().json.cab.turno_id`) em 8 ferramentas: buscar_por_perfil, escalar_ao_tel, dados_do_corretor, pedir_visita, guardar_dados_da_visita, responder_horario, mudar_horario e resultado_da_visita. O telefone é injetado em 3 (guardar_do_imovel, imovel_do_disparo e responder_pendencia, esta com o msg_id também). Outras 5 recebem **só** o que o modelo passa e não sabem quem pergunta: imovel_por_codigo, resumo, listar, disponibilidade e o_que_sei. Por isso elas não conseguem conferir se o código foi dito pelo corretor.

**Onde o banco corrige o que o modelo passou** (versão viva):
- `nai_escalar`: descarta o `codigo` do modelo, a não ser que ele esteja confirmado (`nay_codigo_confirmado(tel,cod,72)` ou citação na mensagem). Quando `disse` vem vazio, usa `nai_turno.texto`. Se for pergunta de parceria, devolve a frase fixa. Antes de escalar, tenta `nai_resposta_da_base`. Se o texto for pedido de perfil (`nai_pedido_de_perfil`), roda a busca e não escala. Por dentro, `nay_escalar` recusa assunto vazio, recusa número de unidade (`nay_pede_localizacao_da_unidade`) e anula código inexistente ou não confirmado. Neste último caso devolve `acao='perguntar'` com um texto_pronto que carrega `[INSTRUCAO: … NAO escale ainda …]`: foi o que o modelo recebeu nos turnos 12387 e 12602.
- `nai_pedir_visita`: o código precisa estar confirmado em 72h ou ter visita aberta. Recusa parceiro e imóvel fora do mercado. Interpreta o horário: pede de novo se está vazio, diz "já passou" se falta menos de 10 min, recusa mais de 45 dias, e visita com menos de 3h sobe ao Tel.
- `nai_buscar_por_perfil`: o negócio e o tipo **não vêm do modelo**. Vêm da conversa (`nai_negocio_da_conversa`, `nai_tipo_da_conversa`). O teto é interpretado por `nay_maior_valor`/`nay_valor_em_reais`, "Manaus" nunca vale como bairro, e é a função que escolhe a próxima pergunta do filtro.
- `nai_guardar_dados_visita`: aceita CPF por `nai_cpf_valido` (dígitos) e CRECI com 3 a 30 caracteres.
- `nay_guardar_do_imovel` e `nay_responder_conversando`: recusam quem não é o Tel. O telefone vem do fluxo, e o número do Tel está escrito fixo dentro de `nay_responder_conversando`.
- `imovel_por_codigo`, `o_que_sei_do_imovel`, `resumo`, `listar`: não corrigem nada. Código errado devolve vazio ou o imóvel errado.

Depois do modelo o banco corrige mais uma vez, e já não olha a chamada de ferramenta: olha o **texto**. O nó "Achar codigo na resposta" tira os códigos da resposta por regex (`Código: NNNN`) e não da ferramenta chamada. `nai_enfileirar_resposta_ferramentas` corta esses códigos quando nenhuma ferramenta de imóvel foi chamada (`saida_sem_consulta`: 373 cortes desde 25/09). E `nai_conferir_resposta` recalcula o imóvel e as fotos por conta própria.

**Achado.** O SQL do nó `imovel_por_codigo` lê `imoveis.extras->>'aceita financiamento'`. Quando o campo está vazio e o imóvel é de venda, ele diz ao modelo "este imovel NAO aceita financiamento, entao e SO A VISTA… NUNCA diga que vai verificar". Nem usa `nai_ficha_valor`, que olha `imovel_ficha`. Hoje, dos 219 imóveis de venda no ar, 78 recebem essa instrução, e **27 deles aceitam financiamento pela ficha do anúncio**. O caso 5664: extras vazio, ficha "Sim". A correção da 191 (`nai_conferir_pagamento`) age depois do modelo. A ferramenta continua mandando a instrução errada.

---

### 15. O prompt do papel corretor

**Onde mora.** Na tabela `nai_prompt`, linha `papel='corretor'` (colunas `papel, texto, versao, atualizado_em, atualizado_por`). O agente recebe o texto assim: `nai_abrir_turno` devolve `cab.prompt = nai_prompt_de(papel)` e o `systemMessage` do nó "NAI (corretor)" é uma expressão que lê `$('Abrir turno').first().json.cab.prompt`. A expressão **lança** `PROMPT_VAZIO` se o texto vier com menos de 500 caracteres, então não existe fallback dentro do fluxo. Editar a tabela vale na mensagem seguinte, sem import.

**Tamanho e versão atual.** Versão 16, **10.294 caracteres** (10.574 bytes).

**Última alteração.** 28/09 às 11:09:02, `atualizado_por = "Claude 28/09: filtro nao trava (lista com o que tem, sem valor segue outro filtro)"`. A anterior (v15) é de 28/09 às 10:46:49 ("Claude 28/09: etapas, ficha, status, parceria, filtro, confirmacao de visita, sem Sr/Sra").

**Quem altera.** A função `nai_salvar_prompt(papel, texto, versao, por)`, que é `SECURITY DEFINER`. Ela copia o texto **antigo** para `nai_prompt_historico` com a versão antiga, grava o novo, soma 1 na versão e recusa se a versão enviada não for a atual (trava otimista). Há dois caminhos até ela:
- o painel: `PUT /api/nai/prompt/<papel>` em `nay-site-api/app.py:564`, tela `imob-easy/assets/js/nay-locacao.js`. O campo `por` tem padrão `"painel"` e é cortado em 60 caracteres. A rota aceita corretor, proprietario, motoboy e captacao. **Não aceita secretaria.**
- scripts SQL que chamam `nai_salvar_prompt`: as migrações 68, 69, 72, 76, 82, 85, 90, 91, 94, 95 e 97 em `Arquivos/nai/`.

**Histórico.** `nai_prompt_historico` tem 15 linhas do corretor (v1 a v15, de 15/09 01:01 a 28/09 11:09) e 5 da captação. Nenhuma linha tem `salvo_por='painel'`. As duas últimas gravações (v15 e v16) têm `salvo_por` com mais de 60 caracteres, então **não vieram do painel**. E **não há arquivo no repositório com esse texto**: nenhuma `.sql`/`.py` contém "filtro nao trava" ou "Claude 28/09", e a 141 e a 146 não gravam prompt. O script que gravou as duas versões de 28/09 não está no repositório.

**Buraco no versionamento.** As migrações 46, 49b, 52, 56b e 63b fazem `UPDATE nai_prompt SET texto=…, atualizado_em=now()` direto, sem histórico e sem subir a versão. O histórico mostra a v2 com 4.666 caracteres, guardada em 15/09, e a v3 com 9.502 caracteres, guardada em 19/09 17:44. As cinco reescritas entre as duas não têm registro. E como `nai_turno.prompt_versao` nunca é preenchido, **não dá para saber com qual versão um turno foi respondido**, a não ser cruzando a hora do turno com `nai_prompt_historico.salvo_em`.

O prompt não é tudo o que o modelo lê. O campo `text` do nó "NAI (corretor)" monta a cada turno um envelope no n8n (fora do banco e sem versão): hora de Manaus, vocativo, nome, citação, "as fotos VAO/NAO saem", "chame pedir_visita", mais o `cab.contexto` (`nai_etapa_para_o_modelo` + `nai_contexto` + `nai_giria_explica`). Há uma contradição entre os dois. O envelope diz "trate o corretor por: X (**Sr./Sra.** + primeiro nome, como na captacao)" e o prompt v16 diz "sem Sr. e sem Sra.". O modelo obedece ao envelope às vezes ("Bom dia, Sra. Francisca!", memória do turno 12455). Quem limpa isso é o gatilho `nai_saida_validar` (`nai_sem_senhor`), na saída.

---

### 16. O que o modelo escreve numa resposta com card

**Na maioria das vezes: cumprimento e uma frase curta antes do card, que vai inteiro. Em um terço das vezes, porém, o modelo não manda o card e escreve prosa própria a partir da instrucao_para_voce.** Medi nos 12 grupos mais recentes de `nai_memoria` com chamada a `imovel_por_codigo` (28/09 16:41 a 29/09 18:04):

| Padrão | Quantos |
|---|---|
| cumprimento/"Claro, já te mando!" + card inteiro | 6 |
| só o card | 2 |
| não mandou o card, escreveu prosa própria usando a instrução | 4 |
| escreveu algo **depois** do card | 0 |

Três exemplos. Todos saem de `nai_memoria` (modelo) e de `nai_saida` (o que saiu).

1. **Turno 12605, 29/09 18:04, Ramon.** Ele escreveu "Tens foto do Sollar da Villa E informações". O texto_pronto foi o card 3854 (📍 Sollar da Villa … Código: 3854). O modelo escreveu `"Boa noite, Ramon! Claro, já te mando!\n\n" + card, sem mudar nada`. Saiu um balão com cumprimento e card, mais 23 fotos. As duas frases fixas de `depois_das_fotos` ficaram **bloqueadas com `tel_assumiu`** (veja a nota abaixo).
2. **Turno 12455, 29/09 09:18, Francisca, por áudio.** O texto_pronto foi o card 5725 (Jardim das Cerejeiras). O modelo acrescentou "Bom dia, Sra. Francisca! Entendi que ela não gostou da mobília e a Sra. quer o Jardim das Cerejeiras. Claro, já te mando!" antes do card. **Nada disso saiu.** Como as fotos do 5725 já tinham ido às 09:16, o gatilho `nai_saida_validar` trocou o bloco inteiro (cumprimento e card, porque o bloco vai até o `Código:`) por "O 5725 eu já mandei hoje às 09h16, está aqui em cima na conversa." Depois foram as duas frases de `sugere_visita`.
3. **Turno 12565, 29/09 16:13, Paulo.** Duas chamadas a `imovel_por_codigo` (1360 e 5664). A instrução do 5664 dizia "SO A VISTA" porque `extras` está vazio. O modelo não mandou nenhum dos dois cards e escreveu "Claro, Paulo! Os dois estão disponíveis. A casa 1360 aceita pagamento à vista ou financiado. Já o Living Comfort 5664 é somente à vista. Quer que eu te mande as fotos dos dois?". Saiu igual, porque foi antes da 191, junto com 7 fotos do 1360 e "O 5664 eu já mandei hoje às 16h10…". **"Somente à vista" está errado**: a ficha do anúncio diz que aceita financiamento. É o caso citado no comentário da 191.

Outros casos do mesmo tipo:
- **Turno 12444 (29/09 09:09, Luiz).** O modelo abriu com um parágrafo de interpretação, inventou "seria somente à vista" para o 650, pela mesma instrução, e colou a lista do `buscar_por_perfil`.
- **Turno 12378 (28/09 20:20, Luiz).** No lugar do card, o modelo respondeu com a descrição do anúncio ("R$ 9.000 semi-mobiliado ou R$ 10.000 mobiliado").

Nota para outros blocos: em 3 dias, 40 de 72 `depois_das_fotos` e 230 de 1.277 fotos ficaram `bloqueado/tel_assumiu`. No 12605, o carimbo `humano_assumiu_em` ("o Tel escreveu pelo celular") tem o mesmo segundo do envio da própria Nay (18:05:59). **[OPINIÃO]** Parece eco do envio lido como mensagem manual do Tel. Não verifiquei a causa.

---

### 17. As conferências da saída

**Premissa errada.** Não são "17 conferências de `nai_enfileirar_resposta`". O nó "Enfileirar resposta" chama `nai_enfileirar_resposta_ferramentas`, que chama `nai_enfileirar_resposta`, que chama `nai_conferir_resposta`. **`nai_conferir_resposta` tem hoje 25 blocos**, e há mais 5 camadas depois dele. Os "17" são a tabela `nai_regra` (17 linhas), que documenta os passos 1 a 17 como estavam em 14/09. `nai_conferencia` tem 36 nomes de etapa distintos. No código de hoje, 15 funções gravam ali (via `nai_anotar`).

**Todas as conferências agem depois de o modelo escrever.** Nenhuma reescreve a resposta chamando o modelo de novo. O que age **antes** do modelo não é conferência, é outra coisa:
- a porta e a pausa em `nai_abrir_turno` (`nai_deve_atender`, `nai_tel_com_a_conversa`, `nai_corrigir_nomes`, contexto e etapa);
- o "Rotear pelo cabeçalho": cortesia, e número solto vira `nai_enfileirar_card` sem passar pelo modelo;
- o Jev ("Decidir quem responde" → `nai_decidir_com_jev`, `nai_pediu_imovel`), que escolhe entre secretária e locação;
- o envelope do nó (fotos vão/não vão, "chame pedir_visita");
- as paredes dentro das ferramentas (item 14).

**A. `nai_conferir_resposta`, na ordem.** A última coluna conta os acionamentos em 30 dias (`resultado<>'passou'`).

| Bloco / etapa | Pega | Faz | 30d |
|---|---|---|---|
| 00p parceria | corretor pergunta de parceria (`nai_pergunta_parceria`) | **troca/antepõe** a frase fixa `nai_cfg('resposta_parceria')`; só parceria → só a frase | 2 |
| 00 secretária | `t.atendente='secretaria'` | sai do resto das conferências (silêncio se vazio) | sem registro |
| 01 imovel_da_conversa | — | descobre o imóvel (código único da resposta ou `nai_imovel_da_conversa`) e grava `nai_turno.codigo` | 561 "mudou" (é identificação, não correção) |
| 02 fotos_do_site | fotos lidas pelo nó "Buscar fotos no site" | grava com `nai_gravar_fotos_do_site` | 0 gravações |
| 02a link_de_catalogo | link de produto sem código | **escala** (`nai_escalar_link_de_catalogo`) e troca pelo texto que ela devolve | 3 |
| 02b oferta_de_imovel | corretor oferece imóvel | escala e **para** o chat | 0: morto enquanto `secretaria_ligada='sim'` |
| 03 promessa_ou_sem_resposta | "vou verificar/te retorno" (`nai_re_promessa`), ou resposta vazia com "?" dele | **troca** pela base (`nai_escalar_calado`); sem base, **escala e para**; se já escalou no turno, **silêncio** | 8 (7 pararam) |
| 04 resposta_sem_consulta | afirmou sobre imóvel sem nenhuma ferramenta | **troca** pela base; sem base, **escala e para** | 30 (27 pararam) |
| 05 formato_da_base | ele perguntou ("?"), há imóvel, a resposta não tem card, não houve busca, escalação nem visita | **troca o texto inteiro** por `nai_resposta_da_base` | 19 |
| 05p pagamento_da_ficha (191) | frase que afirma forma de pagamento (`nai_re_pagamento`) | **troca a frase** pela certa da ficha, **tira** a frase sem dado; pergunta sensível sem ficha → **escala e para** | 0 (entrou em 29/09 por volta das 18h) |
| 06 silencio | texto vazio ou "SILENCIO" | **para**: nada é montado | 198 |
| 07 voz_sem_emoji | só proprietário e Fernando | tira emoji | 0 |
| 08 sugerir_visita | informou imóvel, sem pergunta, 1ª vez no dia, sem visita aberta | marca `sugerir`; a montagem põe 2 frases fixas depois | 86 |
| 09 sugestao_repetida | convite de visita repetido no mesmo dia | **tira a frase** (se sobrar vazio, silêncio) | 0 |
| 10 negou_imovel_que_existe | "não encontrei" com código nosso no ar | **troca** pelo card | 0 |
| 11 visita_sem_ferramenta | frase de visita sem a ferramenta | **tira a frase, avisa o Tel e para** o chat | 1 (22/09) |
| 12 citou_o_tel | "Tel" no texto | **tira a frase**; vazio → silêncio | 2 (ambos no espelho de teste) |
| 13 uma_pergunta_por_mensagem | texto com menos de 300 caracteres, "?" e 2 dos 3 termos bairro/faixa de pre/mobiliad | **troca o texto inteiro** por uma de 3 perguntas fixas (`nai_uma_pergunta_da_sequencia`) | 4 |
| 14 markdown | `**` e `#` no começo da linha | tira (não tira o `*negrito*` simples) | 0 |
| 14v visita_inventada (141) | "visita" + hora/hoje/amanhã sem pedido, ferramenta ou visita aberta | **silêncio** | 0 |
| 14i ficha_de_identificacao (141) | pergunta "qual deles / é esse / código" com 1 a 5 candidatos | **troca** por "É este imóvel?/Qual deles?" + `nai_ficha_imovel` de cada um (sem foto) | 7 (desde 28/09 11:20) |
| 14c visita_confirmada_pelo_corretor | "sim" curto com visita em `confirmando` e sem ferramenta | o banco confirma a visita e **troca** o texto por uma frase fixa | 0 |
| 15 portao_de_fotos | — | decide se as fotos vão (`nai_deve_mandar_fotos` + trava de 24h + regras 138/141/190) | 268 "mudou" (decisão, não correção) |
| 16 negou_foto_que_existe | "não tenho foto" e a foto existe | troca por "segue as fotos" | **nunca disparou** |
| 17 foto_que_nao_existe | fotos pedidas e nenhuma no banco | **tira a frase** de promessa/negação e **avisa o Tel** | 35 |

**B. Depois de `nai_conferir_resposta`**, ainda dentro do "Enfileirar resposta":
- `nai_enfileirar_resposta_ferramentas`, antes de tudo: `saida_sem_consulta` **corta os códigos** quando nenhuma ferramenta de imóvel foi chamada (373 em 30 dias). `imovel_rejeitado` corta os que ele recusou (0).
- Montagem em `nai_enfileirar_resposta`. Parte o texto por card, põe o balão de status na frente, segura as fotos quando a pergunta é "qual deles". Troca o texto pela frase fixa "De qual imóvel você quer as fotos?…". Aplica `nai_sem_emoji_resposta` e `nai_sem_pergunta_de_identidade` ao texto **fora** do card. Acrescenta `depois_das_fotos`, `sugere_visita` e a lista de `documentos_locacao`.
- `nai_fila_dos_outros_imoveis`: 69 acionamentos. Enfileira o segundo imóvel pedido ou corta.
- `nai_conferir_imoveis_da_saida`: bloqueia parceiro, imóvel fora do mercado, tipo errado, venda ou locação trocada, card que não bate com o pedido. Se não sobra imóvel, bloqueia o texto órfão ("segue abaixo") e avisa o Tel. Foram 35 retiradas e 4 textos órfãos.
- `nai_conferir_texto_da_saida`: tira a linha de imóvel barrado de uma lista escrita, ou barra a mensagem e avisa o Tel. 0 em 30 dias.
- `nai_espacar_depois_das_fotos`: só atrasa o texto até as fotos saírem.

**C. O gatilho `nai_saida_validar`**, `BEFORE INSERT` em `nai_saida`: toda linha passa por ele, venha de onde vier, e ele não grava em `nai_conferencia`.
- Tira Sr./Sra. (`nai_sem_senhor`).
- Barra destinatário errado (RAISE).
- Barra parceiro.
- Finalidade da 190: conversa de locação não recebe imóvel só de venda, e vice-versa.
- Imóvel indisponível: bloqueia a foto e troca o card pelo `nai_status_do_imovel`.
- Imóvel já enviado em 24h: bloqueia a foto e troca o card por "O X eu já mandei…". Foram 163 fotos bloqueadas e 12 cards trocados em 30 dias.
- A foto precisa ser daquele imóvel (RAISE).

**D. No envio.** `nai_liberar_saida`, no nó "Liberar saída", barra: `nai_desligada`, `nai_pausada`, `contato_mudou`, `tel_assumiu` (409 em 30 dias), `foto_nao_confere`, `repetida` (mesmo texto para a mesma pessoa em 10 min: 156). Ela também redireciona no modo teste. O nó "Conferir cabeçalho" (JavaScript) confere a chave do destino, a rota, se a foto tem código (`foto_sem_codigo`) e se o texto está vazio.

---

### 18. A frase tirada volta ao modelo?

**Não. O que sobra vai como está.** `nai_conferir_resposta` é SQL puro, sem chamada a modelo. O fluxo é uma linha só: "NAI (corretor)" → "Achar codigo na resposta" → "Fotos faltando?" → "Buscar fotos no site" → "Enfileirar resposta" → "Fechar turno" → "Liberar saída". Não existe aresta de volta ao agente. Quando a correção deixa o texto vazio, o resultado é silêncio (blocos 09 e 12) ou `parou` (03, 04, 05p, 11). Quando a correção troca o texto, entra um texto fixo, a ficha ou a base. E, como dito no começo, a `nai_memoria` guarda o texto **antes** da correção: o modelo não fica sabendo do corte.

Dois exemplos de "tirou a frase":

- **Turno 12430, 29/09 08:53, Lily** (bloco 17). Ela pediu "Me envia as fotos… por favor". O modelo escreveu: "Claro, Lily! **Já te mando as fotos.**\n\n📍 Life Ponta Negra … Código: 2133". O imóvel não tem foto (`qtd_fotos=0`). Saiu: "Claro, Lily!\n\n📍 Life Ponta Negra … Código: 2133", sem a promessa e **sem foto**. O aviso ao Tel ("pediu fotos do 2133…") ficou `bloqueado/repetida`. A corretora pediu foto e não recebeu nem foto nem explicação. Na memória do modelo ficou "Já te mando as fotos."
- **Turno 12387, 28/09 21:09, João** (bloco 03, `cortou`). Ele perguntou "Oii Ariranhas aceita pet?". O modelo chamou `escalar_ao_tel` e recebeu de volta "De qual imóvel você fala? … [INSTRUCAO: … NAO escale ainda …]". Mesmo assim escreveu "Boa noite, João! Vou confirmar se o Ariranhas aceita pet, tá?". Como a marca `escalar` já estava no turno, a promessa foi cortada e **não saiu nada**. O corretor ficou sem resposta nenhuma.

Dois exemplos de "troca o texto" que pioraram a resposta:

- **Turno 12350, 28/09 18:46** (bloco 13). O modelo escreveu "No Dom Pedro não tenho nenhuma casa nesse perfil, nem nos bairros aqui perto. Quer tentar outro bairro ou outra faixa de preço?". Saiu "Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?". A informação "não tenho" se perdeu. No 12348 (18:45), a mesma troca atingiu o texto_pronto de situação ("o 109 está indisponível…"). A frase trocada ficou `repetida` e **nada saiu**.
- **Turno 12186, 28/09 10:46, Stela** (bloco 04). Ela contou uma história ("…tava por 300 sem, mas tava impecável…"). O modelo respondeu bem: "Entendi, Stela… Fico no aguardo do retorno dele então." Como nenhuma ferramenta tinha sido chamada, a conferência leu "300" como **código de imóvel** e trocou a resposta por `nai_resposta_da_base(300, …)`. Saiu "Sim! Tem 11 banheiros.\n\nO aluguel é R$ 38.000.\nTem 750 m².". O Tel ainda recebeu "pediu fotos do 300". Do mesmo tipo:
  - 12447 (29/09 09:10): pedido de outras opções virou a ficha do 5722 que o cliente tinha achado isolado.
  - 12592 (29/09 17:14): virou a ficha e as fotos do 5748, de venda, numa conversa de locação. Esse caso gerou a correção da 190, que hoje exclui turno com `buscar_por_perfil` do bloco 05. O caminho do bloco 04 continua aberto.

---

### 19. As 17 regras do painel (9 paredes)

As 17 linhas de `nai_regra` estão todas em **`nai_conferir_resposta`** e todas **corrigem depois** do modelo. Algumas têm uma camada "antes", indicada na tabela. O prompt está na versão v16. Os números vêm de `vw_nai_regras_ignoradas` (30 dias).

| # | Etapa (tipo) | Função que aplica | Antes do modelo | Depois do modelo | Passagens / acionou |
|---|---|---|---|---|---|
| 1 | imovel_da_conversa (fluxo) | `nai_conferir_resposta` + `nai_imovel_da_conversa` | contexto "IMÓVEL DESTA CONVERSA" e `codigoCitado` no envelope | grava `nai_turno.codigo` | 1267 / 561 |
| 2 | fotos_do_site (fluxo) | nós "Fotos faltando?" e "Buscar fotos no site" + `nai_gravar_fotos_do_site` | — | sim | 1267 / 0 |
| 3 | promessa_ou_sem_resposta (**parede**) | `nai_re_promessa` + `nai_escalar_calado` | prompt e instrução das ferramentas ("responda SILENCIO") | troca, escala ou para | 1264 / 8 |
| 4 | resposta_sem_consulta (**parede**) | `nai_conferir_resposta` + `nai_escalar_calado`; mais `saida_sem_consulta` em `nai_enfileirar_resposta_ferramentas` | prompt | troca ou para | 1256 / 30 |
| 5 | formato_da_base (**parede**) | `nai_resposta_da_base` | `o_que_sei_do_imovel` já devolve o texto da base com "EXATAMENTE" | troca | 1229 / 19 |
| 6 | silencio (fluxo) | `nai_conferir_resposta` | prompt e texto_pronto `SILENCIO` | para | 1229 / 198 |
| 7 | voz_sem_emoji (ajuste) | `nai_sem_emoji` (proprietário/Fernando); `nai_sem_emoji_resposta` fora do card na montagem | prompt | tira | 1031 / 0 |
| 8 | sugerir_visita (fluxo) | `nai_conferir_resposta` + `nai_enfileirar_resposta` | — | acrescenta frases fixas | 1031 / 86 |
| 9 | sugestao_repetida (**parede**) | `nai_re_sugere_visita` | — | tira a frase | 1031 / 0 |
| 10 | negou_imovel_que_existe (**parede**) | `nai_re_nega_imovel` + `nai_card_do_imovel` | — | troca pelo card | 1031 / 0 |
| 11 | visita_sem_ferramenta (**parede**) | `nai_re_frase_de_visita`, `nai_tirar_frase`, `nai_avisar_tel`, `nai_parar_chat` | envelope "chame pedir_visita" (`pedeVisita`) | tira, avisa e para | 1031 / 1 |
| 12 | citou_o_tel (**parede**) | `nai_tirar_frase(…,'\mtel\M')` | — | tira | 1030 / 2 |
| 13 | uma_pergunta_por_mensagem (ajuste) | `nai_uma_pergunta_da_sequencia` | `nai_buscar_por_perfil` já devolve uma pergunta por vez | **troca o texto inteiro** (não "devolve só a primeira", como diz `o_que_faz`) | 1030 / 4 |
| 14 | markdown (ajuste) | `nai_limpar_markdown` | prompt | tira `**` e `#` | 1030 / 0 |
| 15 | portao_de_fotos (fluxo) | `nai_deve_mandar_fotos` + `nai_fotos_ja_mandadas` | envelope "as fotos VAO/NAO saem" | decide | 1030 / 268 |
| 16 | negou_foto_que_existe (**parede**) | `nai_re_nega_foto` | — | troca | **0 / 0: nunca rodou** |
| 17 | foto_que_nao_existe (**parede**) | `nai_re_promete_foto`, `nai_tirar_frase`, `nai_avisar_tel` | — | tira e avisa | 1030 / 35 |

As 9 paredes são os passos 3, 4, 5, 9, 10, 11, 12, 16 e 17. Os fluxos são 1, 2, 6, 8 e 15, e os ajustes são 7, 13 e 14.

A view tem três problemas de leitura:
- Conta todo "mudou" como "ignorou". Nas regras de fluxo, "mudou" é decisão normal, então 44% no passo 1 não quer dizer desobediência.
- Não enxerga as etapas que ficaram fora da tabela: `saida_sem_consulta` (373), `ficha_de_identificacao`, `pagamento_da_ficha`, `visita_inventada`, `conferencia_da_saida`, `fila_de_imoveis`, e as barragens do gatilho e do `nai_liberar_saida`, que nem passam por `nai_conferencia`.
- As passagens caem de 1.267 no passo 1 para 1.031 no passo 7: 236 turnos pararam antes, 198 deles no silêncio.

---

### 20. "Resposta da base"

**Função:** `nai_resposta_da_base(p_codigo int, p_pergunta text) RETURNS text`, `STABLE`, com 13.450 caracteres.

**Onde está o texto.** Não há tabela de frases. **As frases estão escritas dentro da função (PL/pgSQL).** Os dados vêm de:
- colunas de `imoveis`: quartos, suites, banheiros, vagas, vagas_cobertas, area_util, andar, sol, condominio_nome, taxa_condominio, iptu, valor_aluguel, valor_venda, mobilia, logradouro, bairro e disponível;
- `imovel_ficha`, lido do anúncio: campos jsonb, características do imóvel e do condomínio, descrição e observações. É acessado por `nai_ficha_valor`, `nai_ficha_caracteristicas` e `nai_ficha_texto_livre`. Hoje são 270 fichas, 269 encontradas, cobrindo os 259 imóveis nossos no ar, lidas pela última vez em 29/09 entre 18:11 e 18:19;
- `envios`, para a pergunta "foi para o grupo?".

**Formato da resposta.** "Sim! " só quando a pergunta é de sim/não e a resposta é positiva. Vem a primeira afirmação, uma linha em branco, depois as outras afirmações e a ficha básica (quartos, banheiros, vagas, área, andar).

**Assuntos cobertos: 21.** Todos são reconhecidos por regex sobre a pergunta sem acento.

1. foi para o grupo
2. mobília
3. quartos/suítes
4. banheiros
5. vagas (cobertas ou não)
6. área
7. andar
8. sol
9. nome do condomínio
10. taxa de condomínio (ou "inclusa")
11. IPTU
12. valor de aluguel ou de venda
13. disponibilidade
14. onde fica (condomínio, rua **sem número**, bairro)
15. financiamento/à vista/forma de pagamento (só imóvel de venda, só pela ficha)
16. FGTS (cita a frase do anúncio)
17. permuta
18. garantia do aluguel
19. lances de escada
20. pet (cita a frase do anúncio)
21. lazer/características: 20 termos de busca (piscina, academia, elevador, portaria, churrasqueira, salão de festas, playground, varanda, sacada, gourmet, ar-condicionado em duas grafias, área de lazer, quadra, sauna, quintal, jardim, interfone, cerca elétrica, segurança 24h). Só afirma o que o cadastro ou o anúncio dizem.

**Quem chama:**
- a ferramenta `o_que_sei_do_imovel`, por `nai_o_que_sei_do_imovel`, com a instrução "mande o texto_pronto EXATAMENTE como veio… NAO escale";
- `nai_escalar`, antes de escalar;
- `nai_escalar_calado`, nos blocos 03, 04 e 05p;
- o bloco 05 de `nai_conferir_resposta`, que substitui o texto do modelo.

**Quando a base sai e o modelo entra.** A função devolve NULL quando:
- não há código, a pergunta está vazia ou o imóvel é de parceiro;
- nenhum dos 21 assuntos casou;
- casou mas o dado está vazio (taxa nula, ficha sem "aceita financiamento" etc.).

Com NULL, `nai_o_que_sei_do_imovel` segue esta ordem:
1. Pergunta de status → `nai_status_do_imovel`.
2. Base.
3. O que o Tel já ensinou (`nay_o_que_sei_do_imovel`: `imovel_conhecimento` e pendências respondidas).
4. Assunto sensível (`nai_assunto_sensivel`: fgts, pagamento, permuta, garantia, documentação, pet) → instrução "chame escalar_ao_tel e responda SILENCIO".
5. Senão, entrega ao modelo **a ficha inteira** (`nai_ficha_completa`) dentro da `instrucao_para_voce`, com a ordem "responda SÓ com o que está escrito". Daí em diante quem redige é o modelo.

No bloco 05, a base só substitui o texto quando: é corretor, o imóvel é conhecido, a mensagem dele tem "?", a resposta não tem "Código:", não houve `buscar_por_perfil` e não houve escalação nem visita.

**Uso.** Não há log por assunto: **NÃO SEI** quantas vezes cada assunto respondeu. Para saber, seria preciso gravar o assunto que casou, e isso não é gravado. O que dá para medir:
- o bloco 05 trocou a resposta do modelo 19 vezes em 30 dias;
- os blocos 03 e 04 trocaram pela base 4 vezes;
- reconstrução com a função de hoje sobre as perguntas de 30 dias: dos 177 turnos de corretor com imóvel e "?", **91 (51%) seriam respondidos pela base hoje**. É o que a função faria hoje, não o que aconteceu naquele dia.

---

### 21. Escalação ao Tel

**O que dispara.** Quatro coisas:
- o modelo chama `escalar_ao_tel` (`nai_escalar`): 145 turnos de corretor em 30 dias;
- as conferências 03, 04, 05p e 11 (`nai_escalar_calado`, `nai_parar_chat`);
- link de catálogo (`nai_escalar_link_de_catalogo`);
- mídia sem conteúdo lido (dentro de `nai_escalar`).

A marca interna `escalar` aparece em 195 turnos de corretor em 30 dias. Em `nai_escalar`, o `nay_escalar` cria uma linha em `pendencias` (e em `escalacoes` e `pendencia_interessado`) e **em seguida** `nai_avisar_tel` enfileira o aviso ao Tel pela caixa da NAI. O modelo é `duvida_fora_da_base`, com este texto: "Tel, o corretor X (…) perguntou sobre o …: "…". Não achei na base, você sabe? … parei de responder esse chat… Para eu voltar: DEVOLVER <fone>". **O aviso não traz o número da pendência**: 0 de 135 avisos contêm "pendência".

**O que o corretor vê enquanto espera: nada.** A ferramenta devolve `SILENCIO`, a conferência 06 para, e `nai_parar_chat` grava `humano_assumiu_em` com o motivo "duvida fora da base: …". Daí em diante `nai_abrir_turno` devolve `ok=false, motivo='tel_assumiu'` e cada mensagem dele vira `status='Com o Tel'`, sem resposta e **sem novo aviso ao Tel**. A pausa por escalação **não expira**: `nai_tel_com_a_conversa` só aplica a janela de 30 min ao motivo "o Tel escreveu pelo celular". Se o Tel responder à mão, `nai_tel_assumiu` mantém o motivo antigo (`coalesce`) e só renova o carimbo.

Há duas exceções:
- com mídia, o corretor recebe "Recebi, X! Já te respondo por aqui.";
- os 3 números de `nai_config.escala_sem_parar` (…2835, …7316, …6408) não são pausados.

**Quando o Tel responde.** O desenho da NAI conduz ao `DEVOLVER`. Os caminhos:

- **`RESPOSTA n <texto>`.** O "Rotear pelo cabeçalho" reconhece a gramática de pendência e manda para a rota `tel_antigo`. O caminho é "Comando do Tel" → "Responder pendencia" (`nay_comando('RESPOSTA',n,texto)` → `nay_responder_pendencia`) → "Preparar aviso do comando" → "Enviar aviso do comando". Esse último nó manda **direto na Z-API**, fora de `nai_saida`, então o envio não aparece no painel de envios e não passa pelo `nai_saida_validar`. O efeito:
  - marca a pendência como `respondida` e fecha a escalação;
  - grava o conhecimento por assunto (`nay_gravar_conhecimento`) quando há código;
  - enfileira a mesma resposta aos outros interessados em `resposta_a_entregar`;
  - manda ao corretor "o <condomínio>, <texto>" e ao Tel "pendencia n respondida…";
  - **não tira a pausa do chat**.
- **`DEVOLVER <fone> [resposta]`** (`nai_comando_tel`): limpa `humano_assumiu_em` e, se vier texto, entrega pela caixa (`papel_destino='entrega'`, motivo `resposta_do_tel`). Limpa só a linha cuja chave é o telefone digitado. Quando o carimbo está na linha `@lid` irmã, a pausa continua (`nai_tel_com_a_conversa` lê as duas). Isso é leitura do código, não testei.
- **Botão "voltar" no CRM** (`crm_nay_voltar`, limpa as linhas irmãs). `nai_zerar_conversa` e `nai_liberar_chats_da_visita` também limpam.
- **A ferramenta `responder_pendencia`**, quando o Tel conversa com o agente: exige confirmação numa mensagem nova e manda pelo subfluxo "Nay - responder pendencia".

**Se ele nunca responde:**
- A pendência fica `aberta` para sempre. Não há prazo nem expiração.
- O chat do corretor fica calado até alguém liberar.
- O cron `* * * * * … /root/nay-publicador/ciclo_pendencias.sh` (confirmado no `crontab -l` e no batimento de hoje, 23:30 UTC) chama `nay_pendencias_esquecidas()`. Ele cobra o Tel com a lista das pendências abertas há mais de 4h (`pendencia_horas_para_cobrar`, padrão 4), no máximo a cada 6h, entre 8h e 20h. No log, isso dá **2 cobranças por dia (08:00 e 14:00)** e 58 desde 18/09, terminando em "Responda com RESPOSTA <número> <texto>." O envio sai pelo `enviar_zapi` do publicador.
- O corretor não recebe nada: nem aviso, nem prazo, nem retomada.

**Números de 30 dias:**

| Medida | Valor |
|---|---|
| Avisos `duvida_fora_da_base` criados | 135: **51 enviados**, 75 `simulado` (treino/teste), 9 barrados como `repetida` |
| Avisos `midia_para_o_tel` | 24 (21 enviados) |
| Corretores distintos escalados de verdade (dúvida ou mídia) | 42, dos quais **34 continuam pausados agora** |
| Mensagens de corretor que caíram em "Com o Tel" depois da 1ª escalação de cada um | 789 (inclui a conversa real do Tel com eles) |
| Contatos pausados agora por "duvida fora da base" | 26 (carimbo mais antigo: 15/09); 13 contatos com pausa não-manual há mais de 7 dias |
| Pendências `de_quem='tel'` | 60 **abertas** (todas de 24/09 a 29/09); as 43 de 13/09 a 23/09 foram todas **descartadas**; **0 respondidas** no período. As 7 respondidas por `RESPOSTA n` são de 31/08 a 01/09 |
| Comandos do Tel (`nai_turno` papel tel) | `RESPOSTA n`: **0**; `PENDENCIAS`: 0; `DEVOLVER`: 18 (com texto de resposta: 2, em 23/09); `ASSUMIR`: 8 |
| Das 51 escalações reais | 7 seguidas de `DEVOLVER` com o número; em 27 a Nay voltou a responder àquele contato por algum caminho (mediana de 2,1h); nas outras 24 ela não falou mais com ele até agora |

Quanto do "voltou" foi pelo CRM, por `DEVOLVER` ou por zeramento: **NÃO SEI**. `crm_nay_voltar` não grava log. Para saber, seria preciso um log na rota do CRM, ou comparar `nai_contato.humano_assumiu_em` antes e depois. Também **NÃO SEI** quantas das 406 mensagens "enviadas" sem `fluxo` para esses contatos o Tel digitou à mão: `mensagens` não separa o Tel do publicador.

---

## Blocos 4 (Sair) e 5 (Visita): respostas 22 a 30

Medido em produção em 29/09/2026, entre 19h e 20h de Manaus. Tudo foi lido em modo só leitura: o banco `naydb` pelo `q.sh`, o sqlite do n8n pelo `n8nq.sh`, o JSON do workflow `NaiAtendLocacao1`, o crontab e os scripts do servidor lidos com `cat`. Telefones aparecem só com os 4 últimos dígitos, e pessoas só com o primeiro nome. Os horários estão no fuso de Manaus.

---

## BLOCO 4: SAIR

### 22. nai_saida: estados, quem muda cada um, motivos de bloqueio e contagem

**Duas premissas da pergunta não valem.**
- Não são dois lugares que bloqueiam (`nai_liberar_saida` e o gatilho). São cinco lugares de código que gravam `bloqueado`, um que apaga a linha e dois motivos que foram gravados à mão.
- "Últimos 30 dias" é a vida inteira da tabela. A primeira linha de `nai_saida` é de 10/09 18:54, e há 7.374 linhas até 29/09 19:03.

**Estados.** A CHECK `nai_saida_estado_check` aceita `pendente` (o default), `enviando`, `enviado`, `bloqueado`, `erro` e `simulado`. Há mais três CHECKs:
- `nai_saida_tipo_check`: o tipo é `texto` ou `imagem`.
- `nai_saida_check`: texto não pode ser vazio, e imagem exige `imagem_url` e `codigo`.
- `nai_saida_papel_destino_check`: o papel é `turno`, `corretor`, `proprietario`, `motoboy`, `tel`, `entrega`, `equipe` ou `seguimento`.

**Gatilhos (pg_trigger): só existem dois.**
- `nai_saida_validar`, BEFORE INSERT.
- `nai_saida_imutavel`, BEFORE UPDATE. Ele proíbe mudar `contato_id`, `chave_destino`, `papel_destino`, `imagem_url` e `codigo`, mas deixa mudar `estado`, `texto` e `enviar_apos`.

A parede da parceria, a trava de 24 h, a separação venda x locação (190) e o "fora do mercado/indisponível" moram todos dentro de `nai_saida_validar`, nesta ordem:
1. destino = chave do contato;
2. tira "Sr./Sra.";
3. confere o papel;
4. parceria;
5. finalidade;
6. indisponível;
7. 24 h;
8. confere a foto.

A versão viva é igual ao último arquivo (`190p_remendos.sql`).

**Quem muda cada estado**

| Transição | Quem faz | Onde roda |
|---|---|---|
| (nova) → `pendente` | `nai_enfileirar_texto` e os INSERTs diretos em `nai_enfileirar_resposta`, `nai_enfileirar_card`, `nai_fila_dos_outros_imoveis`, `nai_enviar_imoveis_para` e `nai_followup_rodar` | banco |
| (nova) → `bloqueado` | `nai_saida_validar` | gatilho |
| `pendente` → `bloqueado` | `nai_conferir_imoveis_da_saida` e `nai_conferir_texto_da_saida` (chamadas no fim de `nai_enfileirar_resposta`), e `crm_visita_excluir` | banco |
| `pendente` → linha apagada | `nai_enfileirar_resposta_ferramentas` apaga a linha pendente de um código que o corretor já recusou | banco |
| `pendente` → `bloqueado`, `simulado` ou `enviando` | `nai_liberar_saida(lote)`: com o id do turno pelo nó "Fechar turno", com NULL pelo nó "Agenda da NAI" | nó "Liberar saída" |
| `enviando` → `bloqueado` | `nai_registrar_bloqueio`, pelo nó "Registrar bloqueio", quando o nó JS "Conferir cabeçalho" reprova | n8n |
| `enviando` → `enviado`, `pendente` (de novo) ou `erro` | `nai_confirmar_envio`, pelo nó "Confirmar envio" | n8n |

**Motivos de bloqueio possíveis, por lugar**

- **`nai_saida_validar`, sem exceção.** A linha entra como `bloqueado` e o resto da resposta segue.
  - `imovel de parceria: so no site, nunca enviado`: tem código de parceiro e o destino não é o Tel.
  - `finalidade: conversa de X, o N e so de Y`: só em turno de corretor. Vale para card ou foto. Passa o código que ele próprio digitou nos últimos 3 dias.
  - `imovel indisponivel: nem card nem foto`: vale para a foto. O card não é barrado: o texto dele é trocado pelo de `nai_status_do_imovel`.
  - `imovel ja enviado a este corretor nas ultimas 24h (HHhMM)`: vale para a foto. O card é reescrito para "O N eu já mandei …".
- **`nai_saida_validar` com RAISE EXCEPTION.** A linha não entra e a transação inteira do nó que enfileirava cai, então a resposta toda some. Acontece quando:
  - o contato não existe;
  - o papel `turno` aponta para quem não é o autor do turno;
  - o papel `entrega` vem de um turno que não é de comando do Tel;
  - `corretor`, `proprietario` ou `motoboy` não é a pessoa da visita;
  - `equipe` aponta para quem não é da equipe;
  - `seguimento` vai para quem não recebeu imóvel em 3 dias;
  - `tel` aponta para quem não é o Tel;
  - é foto para papel que não é corretor;
  - é foto cuja URL não está em `imovel_fotos` nem em `imovel_colagem` daquele código.
- **`nai_liberar_saida`:** `nai_desligada`, `nai_pausada`, `contato_mudou`, `tel_assumiu`, `foto_nao_confere`, `repetida`, `teste_fora_da_lista` e `prop_pelo_tel_sem_texto`.
  - `repetida`: mesmo texto para a mesma pessoa em 10 min. Também vale para a mesma foto em 10 min, se ele não pediu foto.
  - Ela também manda para `simulado` o que vai ao espelho de treino ou roda com `envio_simulado=sim`.
  - Ela processa até 80 linhas por chamada, em `ORDER BY id`, com `FOR UPDATE SKIP LOCKED`.
- **Nó "Conferir cabeçalho" + `nai_registrar_bloqueio`:** `sem_id`, `telefone_do_corpo_diferente`, `chave_nao_confere_js`, `rota_invalida`, `foto_sem_codigo` (a URL não é `https://imobeasy.com/system/pictures/…` nem a colagem daquele código) e `texto_vazio`.
- **Rede depois da inserção.**
  - `nai_conferir_imoveis_da_saida`: `parceiro`, `fora do mercado`, `tipo errado: ele pediu X`, `ele procura venda`, `ele procura locação`, `card que nao bate com o pedido (…)` e `texto sem o imóvel`.
  - `nai_conferir_texto_da_saida`: `texto citava imóvel barrado`.
  - `crm_visita_excluir`: `visita excluída no CRM`.
- **Gravados à mão (nenhuma função contém esses textos):**
  - `lixo_de_teste_12_09`: 300 linhas, 12/09 entre 19:28 e 19:31.
  - `cancelada antes de sair: o Tel disse que ja respondeu`: 1 linha, 23/09 09:22.

**Reenvio da Z-API (151, `nai_confirmar_envio`).** Quando a Z-API não devolve messageId:
- se o erro casa com 5xx, timeout ou rede e é a 1ª ou a 2ª tentativa, a linha volta a `pendente` com `enviar_apos` +1 min ou +2 min, e a contagem vai em `resposta->tentativas`;
- senão, vira `erro` e solta a reserva de 24 h, se nada daquele imóvel chegou naquele turno.

Achado: quando o reenvio dá certo, `resposta` é sobrescrita pela resposta da Z-API e a contagem some. Hoje há 0 linhas com `tentativas` e 0 em `erro` (os 48 erros de 28/09 foram recolocados na fila à mão, pelo REGRAS-E-BUGS #61). Por isso NÃO SEI quantas vezes o reenvio automático rodou.

Achado: uma linha que fica em `enviando` (o n8n cai entre "Liberar saída" e "Confirmar envio") não tem quem a recolha, porque nenhuma função devolve `enviando` para `pendente`. Hoje há 0 linhas nesse estado.

**Contagem (7.374 linhas, 10/09 a 29/09):** enviado 3.165; simulado 2.610; bloqueado 1.599; `erro`, `pendente` e `enviando`: 0.

Motivos dos 1.599 bloqueios. "Real" = destino fora dos números de teste e do espelho de treino. A classificação é aproximada.

| Motivo | Lugar | Real | Teste |
|---|---|---|---|
| tel_assumiu | liberar | 213 | 196 |
| imovel ja enviado a este corretor nas ultimas 24h (…) | gatilho | 163 | 0 |
| tipo errado: ele pediu casa / flat / sala / apartamento | conferência | 104 | 113 |
| ele procura locação / ele procura venda | conferência | 60 | 171 |
| repetida | liberar | 52 | 124 |
| fora do mercado | conferência | 38 | 0 |
| imovel indisponivel: nem card nem foto | gatilho | 35 | 0 |
| lixo_de_teste_12_09 | à mão | 25 | 275 |
| nai_pausada | liberar | 12 | 1 |
| teste_fora_da_lista | liberar | 8 | 0 |
| texto sem o imóvel / card que nao bate | conferência | 4 | 2 |
| cancelada antes de sair… | à mão | 1 | 0 |
| foto_sem_codigo | n8n | 0 | 2 |

A parede da parceria não barrou nada em 30 dias: quem escolhe imóvel já filtra `e_parceiro` antes. A de finalidade (190) nasceu hoje e ainda não barrou nada. 12 cards foram reescritos para "O N eu já mandei …" (10 saíram).

**Achado: a trava de 24 h reserva mesmo quando a foto é barrada depois.** A reserva é feita no INSERT da foto: o gatilho chama `nay_reservar_imovel_do_dia`. As barreiras que vêm depois (conferência, `tel_assumiu`) não soltam a reserva. Desde 28/09, 13 das 85 reservas de origem `nai` (15%) não tiveram nenhuma foto daquele código entregue àquela pessoa naquele turno:

| Barreira que segurou a foto | Reservas |
|---|---|
| tel_assumiu | 5 |
| ele procura locação | 3 |
| tipo errado | 3 |
| ele procura venda | 1 |

A pessoa fica 24 h sem poder receber aquelas fotos, e o follow-up pode perguntar de um imóvel que ela nunca recebeu (ver a 30).

---

### 23. Fotos: de onde vêm, quando são lidas, como a ordem é garantida e quando ainda chega fora de ordem

**De onde vêm.** Do banco, tabela `imovel_fotos`, com 17.886 linhas:

| Origem da URL | Linhas | Imóveis |
|---|---|---|
| imobeasy.com (site antigo) | 17.749 | 1.222 |
| imobeasy.online/fotos e /fotos-captacao | 114 | 11 |
| backblaze | 23 | 1 |

As de imobeasy.com não têm cópia nossa: a URL aponta para o site antigo. Os 37 imóveis de locação disponíveis para a Nay têm foto, todas em `imobeasy.com/system/pictures/`: mediana de 12 por imóvel, máximo de 94.

A lista que sai é `nai_imagens_do_envio(codigo)`, ordenada por `imovel_fotos.ordem` e depois `id`. Ela não inclui a colagem desde 14/09 e exclui foto marcada `e_mosaico` (1 linha).

**Quando as fotos são lidas do anúncio (três momentos):**
1. **Cron diário** às 09:17 UTC (05:17 em Manaus), `sincronizar_catalogo.sh`, que roda `varrer_fotos.py --escrever`. Ele só preenche imóvel sem nenhuma foto e nunca apaga. O log do sincronizador também registra "fotos trocadas" (31 ocorrências); NÃO SEI qual script faz essa troca.
2. **Na hora da resposta**, no caminho do corretor:
   - "Achar codigo na resposta" → "Fotos faltando?" (`nai_fotos_faltando`: códigos da resposta que são nossos, publicados e com ZERO foto).
   - → "Buscar fotos no site": GET `https://imobeasy.com/anuncios/<código>`, no máximo 3 códigos, timeout de 15 s, lendo os links `gallery-item`.
   - → as URLs vão no `p_fotos_site` do "Enfileirar resposta" e são gravadas por `nai_gravar_fotos_do_site`, chamada dentro de `nai_conferir_resposta`. Ela só grava se o código continua sem nenhuma foto, e só URL `imobeasy.com/system/pictures/`.
   - Imóvel que já tem uma foto nunca é relido na hora.
3. **`imovel_ficha` (191)**, cron `40 */3 * * *` UTC. Guarda o texto do anúncio (e o card dos grupos), não fotos.

**Parede de URL em dois pontos.**
- O gatilho exige que a URL esteja em `imovel_fotos` ou em `imovel_colagem` daquele código.
- O nó "Conferir cabeçalho" só aceita `imobeasy.com/system/pictures/` ou a colagem.

Achado: foto hospedada em imobeasy.online (cadastro novo e captação OLX: 11 imóveis, ex. 9001 e 9002) passa no gatilho e morreria no n8n como `foto_sem_codigo`. Nenhum deles está disponível para a Nay hoje, então ainda não aconteceu.

**A "hora marcada"** (113/114b/114c, `nai_espacar_depois_das_fotos(turno)`).
- É chamada no fim de `nai_enfileirar_resposta`, depois de `nai_fila_dos_outros_imoveis` e das conferências.
- **Grupo** = quantos textos existem até a linha. O card abre um grupo, e as fotos dele ficam no mesmo grupo.
- Cada linha recebe `enviar_apos = now() + segundos_por_foto × (fotos dos grupos anteriores)`, com `segundos_por_foto = 2.5` em `nai_config`.

Como isso vira envio:
- "Fechar turno" → "Liberar saída" com o id do turno só pega o que já venceu, ou seja, o primeiro grupo.
- O resto sai pelo "Agenda (todo minuto)" → "Agenda da NAI" → "Liberar saída" com lote NULL. Esse caminho aceita linha com hora marcada (`enviar_apos > criado_em + 1s`) sem esperar os 3 min, mas só dentro da janela 06:00–22:00 (menos para os papéis `tel` e `equipe`).
- Dentro de uma execução, "Enviar Z-API" manda item a item (batch 1, intervalo de 2.000 ms, `onError: continueRegularOutput`). "Confirmar envio" só roda depois do último item, por isso `enviado_em` é igual para o lote inteiro.
- Não há fila sequencial de verdade: a ordem depende do relógio.

Medido:
- Da hora marcada até a saída, as mensagens `depois_das_fotos` levaram em média 129 s (p90 265 s, máximo 17 min 45 s).
- Pelo eco das enviadas em `mensagens`, a Z-API entrega cada foto a cada 9,3 s na mediana (p90 20 s), em 52 turnos desde 28/09 12h. A conta de 2,5 s por foto é otimista.
- [OPINIÃO] Quem mantém a ordem nas respostas comuns da Nay é o atraso do ciclo de um minuto, não a conta.

**Quando ainda chega fora de ordem** (medido pelo eco, 28/09 12h a 29/09):
1. **Envio da equipe e do site** (`nai_enviar_imoveis_para`, `nai_disparo_enfileirar`). Eles não usam hora marcada: o disparo põe tudo em `now()+2s`. Em 3 de 3 envios com 2 ou mais imóveis, o card do imóvel seguinte chegou antes de fotos do anterior. Exemplo: turno 12486 (29/09 11:00, 58 mensagens, 5 imóveis). O card do Mirante das Flores (5727) chegou 11:03:22, antes de uma foto do 5733 (11:04:38). O n8n confirmou o lote às 11:03:22, mas a entrega foi até 11:11:26.
2. **Resposta da Nay com mais de um imóvel:** a ordem já está errada dentro da caixa (ver a 24, turnos 12088 e 12590).
3. **Fotos entre si:** em 34 de 52 turnos com foto, alguma foto chegou antes de outra de ordem menor (o upload da Z-API é assíncrono).
4. **Queda da Z-API mais reenvio à mão:** turno 12276 (28/09 14:17, disparo do site). As fotos 6, 9 e 19 saíram às 14:23 e o card e o resto às 14:35.
5. **Um turno partido em duas execuções:** turno 10946 (25/09). A 11ª foto e os dois textos de fechamento foram confirmados às 08:18:59; as 10 primeiras fotos às 08:19:57. Causa exata: NÃO SEI, porque a execução de 25/09 já foi apagada do n8n (`EXECUTIONS_DATA_PRUNE_MAX_COUNT=2000`). [OPINIÃO] O `FOR UPDATE SKIP LOCKED` trava linha a linha dentro do laço de `nai_liberar_saida`, o que deixa o "Liberar saída" do turno e o da agenda (que pega linha de turno com mais de 3 min) dividirem o mesmo turno.
6. **Não é troca de ordem, mas corta o fim:** o eco das próprias fotos marca "o Tel assumiu" e o fechamento é barrado (ver a 25).
7. **Risco já visto em treino:** hora marcada criada fora da janela espera até 06:00 (turnos 12017 e 12019, 27/09 02:2x → 06:02). São 52 turnos assim, todos de teste ou treino; nenhum real.

---

### 24. Vários imóveis numa resposta

**Há três caminhos.**

**(a) Resposta do modelo com vários cards** (`nai_enfileirar_resposta`).
- Corta o texto em blocos que terminam em "Código: NNNN".
- Cada bloco vira um texto. Antes dele vai "📌 Status: Disponível", se o corretor perguntou do status.
- Logo atrás do bloco vão todas as fotos daquele código, se o portão de fotos (`gate`, de `nai_conferir_resposta`/`nai_deve_mandar_fotos`) estiver aberto.
- O portão fecha em vários casos, entre eles: 2 ou mais códigos com o texto perguntando "qual deles…" (saem só os cards); nenhum imóvel identificado; resposta "Hmmm, vi aqui que o…"; pedido de visita ou de identificação.
- Se saiu foto, `nai_depois_das_fotos` põe os dois textos de fechamento ("Aqui as fotos, quer fazer uma visita?…" e "Ou se tiver alguma dúvida…").

**(b) `nai_fila_dos_outros_imoveis`** (114/144/147).
- Pega os códigos que ele pediu (`nai_imoveis_pedidos`) e que não entraram na resposta.
- Teto de 3 (`v_teto := 3`). Cada um vai com card e todas as fotos, na ordem em que ele escreveu, com `ordem = max+1`.
- Corta quando: quem atende é a secretária; é oferta ou link; o Jev disse que ele não pediu imóvel; a frase é só um bairro; o nome de bairro casou com um condomínio; o negócio ainda é desconhecido (aí só passa código digitado); o imóvel foi recusado; a finalidade não bate; está fora do mercado; é de parceiro.

**(c) Comando da equipe e aba Enviar imóvel do site** ("envia 92… o 5739 e 2014").
- `nai_enviar_imoveis_para`, papel `entrega`: saudação, depois card + fotos de cada imóvel.
- Sem teto de imóveis e sem espaçamento.

**Limite de fotos: não existe.** Cada imóvel vai com todas as fotos de `imovel_fotos`. Nos turnos reais desde 28/09, o maior lote foi de 32 fotos numa resposta de 2 cards, e de 58 mensagens num envio da equipe.

**Números reais** (28/09 07:00 a 29/09, turnos de corretor fora de teste):
- 31 turnos com card: 23 com 1 card, 4 com 2, 3 com 3 e 1 com 4.
- Dos 8 turnos com 2 ou mais cards, 5 saíram sem nenhuma foto. Só nos 3 turnos de 3 cards foram 101 fotos barradas.
- Só 1 dos 8 teve fechamento.

**O que quebra, com casos reais**
1. **Fechamento no meio.** Turno 12088 (28/09 07:13, Magna …7873, pedindo "do 1º da lista"):
   - saiu o card do 5733 com as fotos;
   - depois "Ou se tiver alguma dúvida…" (07:18:25) e "Aqui as fotos…" (07:20:35), trocados entre si e entre o 1º e o 2º imóvel;
   - o card do 5724 chegou às 07:19:16.
   - Causa no código: o fechamento é enfileirado com a ordem do 1º imóvel, e a fila dos outros entra depois com ordem maior. `nai_espacar_depois_das_fotos` põe o fechamento e o card 2 no mesmo instante.
2. **Sugestão de visita antes dos imóveis.** Turno 12590 (29/09 17:13, Luiz …6529):
   - a sequência foi "não temos no Belvedere" → "Quer fazer uma visita?…" → "Ou se tiver…" → card 3446 + fotos → card 5762 + fotos;
   - a entrega foi de 17:15:45 a 17:30:50, e não houve fechamento no fim.
   - Causa: `sugere_visita` é montada com `ordem = v_ordem+5`, com `v_ordem = 0`, antes de a fila dos outros acrescentar os cards.
3. **Card sai e a foto é barrada.** Turno 12183 (28/09 10:45, a mensagem era só "Ponta negra"): 3 cards de venda saíram e as fotos foram barradas com "ele procura locação". Isso foi antes da 144/190, que hoje barram o card também.
4. **O segundo imóvel morre em `tel_assumiu`.** Turno 12205 (28/09 11:19, Taysa …1312):
   - o 1351 saiu;
   - o card e as fotos do 2155 ficaram `bloqueado tel_assumiu` às 11:22:53, e as 7 mensagens seguintes dela caíram em "Com o Tel";
   - ninguém digitou: todos os ecos `enviada` desse intervalo estão em `nai_saida`. É o eco das próprias fotos (ver a 25).
5. **Envio da equipe fora de ordem:** ver a 23, item 1.
6. **Reserva de 24 h para foto barrada:** ver a 22.
7. **Foto numa confirmação de visita.** Turno 12372 (28/09 19:49, Efigenia …0860, "Sim Correto", confirmando a #1048): saíram 10 fotos antes de "Certo! Vou ver esse horário com o proprietário…".

---

### 25. "O Tel assumiu a conversa": detecção, duração e volta

**Detecção**
- Webhook → "Filtrar e normalizar": `tel_celular = !!b.fromMe`. Desde 16/09 conta todo eco `fromMe`, porque o `fromApi` vem `true` até no que o Tel digita (medido e comentado no próprio nó).
- → "Foi o Tel pelo celular?" → "Espera 15s (eco)" (Wait v1.1, amount 15) → "O Tel assumiu a conversa", que chama `nai_tel_assumiu(telefone, message_id, texto)`.

**`nai_tel_assumiu`** (igual ao `134_o_publicador_nao_e_o_tel.sql`)
- Ignora se o chat é o do próprio Tel (`tel_telefone` …7316).
- É eco nosso se:
  - o `message_id` está em `nai_saida`, `mensagem_saida`, `envios` ou `saida_do_sistema`; ou
  - o texto bate com uma linha `enviado`/`enviando` para essa chave nos últimos 15 min.
- Se não é eco, grava em todas as linhas daquela chave:
  - `humano_assumiu_em = now()`, renovado a cada mensagem;
  - `humano_motivo = coalesce(motivo, 'o Tel escreveu pelo celular')`.
- O eco chega com o @lid do chat, então o carimbo cai na linha `lid:`. Os 6 carimbos desse tipo ativos agora estão todos em linha LID.

**Leitura única: `nai_tel_com_a_conversa(contato)`.** Aqui o banco está à frente do repositório: a versão viva tem o bloco "quem tem a voz do Tel não tem o próprio chat assumido" (28/09), que não está em nenhum `.sql`. O último arquivo é o `130_equipe_nao_tem_janela.sql`, com 733 caracteres contra 2.030 no banco. A função faz, em ordem:
1. contato da equipe → false;
2. alguma linha irmã é voz do Tel → false;
3. pega o carimbo mais recente entre as irmãs (`nai_contato_irmaos`);
4. motivo `o Tel escreveu pelo celular` → vale por `gap_tel_min` (hoje 30 min);
5. qualquer outro motivo → vale até alguém tirar.

**Onde isso pesa**
- `nai_abrir_turno`: a checagem vem antes de decidir o papel. A mensagem fica `Com o Tel` e o turno não abre, também para proprietário e acompanhante.
- `nai_deve_atender`.
- `nai_liberar_saida`: grava `tel_assumiu` em tudo para a pessoa, menos a resposta a comando do Tel e a `entrega`.
- `nai_followup_rodar`: pula a pessoa.

**Por quanto tempo**
- 30 min contados da última mensagem manual.
- Escalada não expira: `duvida fora da base: …`, `midia: …`, `visita #N: …`, `proprietario sem visita definida`, `comando ASSUMIR do Tel` e `parada no CRM por …`. Quem grava escalada é `nai_parar_chat`, que pula os números de `escala_sem_parar` (…2835, o do Tel …7316 e …6408).
- Mensagem mandada pelo CRM conta como gente de propósito, porque não passa pelas tabelas de envio do sistema.

**Como volta**
1. **O gap vence.** A conversa volta à porta (`nai_deve_atender`), que devolve "conversa que ela ja estava atendendo" se já houve saída para a pessoa depois de `regra_publico_desde` (28/09 07:00).
2. **`DEVOLVER <telefone> [resposta]`** (`nai_comando_tel`). Zera só a linha cuja chave é aquele telefone. Se houver texto depois do número, entrega esse texto como `entrega`.
3. **Qualquer `VISITA N <comando>`.** `nai_liberar_chats_da_visita` zera `visita #N:%`.
4. **Botão "Nay voltar a atender" do CRM** (`crm_nay_voltar`). Zera todas as linhas da pessoa.
5. **`nai_zerar_conversa`.**

Hoje não há nenhuma escalada presa só na linha LID com a linha do telefone limpa, que é o caso em que o DEVOLVER não alcançaria.

**Números**
- 327 contatos com carimbo: 289 "o Tel escreveu pelo celular", 26 dúvida, 10 mídia e 2 visita.
- Ativos agora: 21 (13 dúvida fora da base, 2 mídia, 6 Tel pelo celular).
- Mensagens recebidas que ficaram `Com o Tel`: 232 em 28/09 (36 pessoas) e 207 em 29/09 (37 pessoas).
- Linhas de saída barradas `tel_assumiu` em 30 dias: 409, das quais 213 reais.

**Achado, bug vivo: a Nay se cala com o eco das próprias fotos.** Isso contradiz a memória "corrigido em 27/09". A 134 cobriu o eco do publicador, não este caso.
- **Mecanismo.** "Confirmar envio" só grava o `message_id` depois do último item do lote. O eco de uma foto chega antes, espera 15 s e não acha o id. Foto não tem texto, então o segundo teste também falha, e sai o carimbo "o Tel escreveu pelo celular". A partir daí, o fechamento e o que ainda estava na fila caem em `tel_assumiu`, e o que o corretor escrever nos 30 min seguintes vira "Com o Tel".
- **Prova.** Execuções do n8n 143455 e 143464, de 29/09 às 18:05:18 e 18:05:44. São o eco de duas fotos do 3854 do turno 12605, e a saída de "O Tel assumiu a conversa" foi `{tel_assumiu: true}`. O lote foi confirmado às 18:05:59, e os dois textos de fechamento foram barrados `tel_assumiu` às 18:07:40.
- **Tamanho.** Entre 27 e 29/09, 14 turnos reais tiveram parte da própria resposta barrada por `tel_assumiu`. Em 11 deles não houve nenhum eco humano nos 10 min anteriores. Nesses 11, 33 mensagens seguintes de corretores caíram em `Com o Tel`.
- **Custo no n8n.** Cada eco segura uma das 5 vagas (`N8N_CONCURRENCY_PRODUCTION_LIMIT=5`) por 15 s. Em 29/09, num lote de fotos, entrou um eco a cada 4 a 8 s.

---

## BLOCO 5: VISITA

### 26. O fluxo de visita que funciona hoje, de ponta a ponta

**Premissa errada: nenhuma visita real andou de ponta a ponta.**

`nai_visita` tem 69 visitas. Só 7 são de corretor real (fora dos números de teste, do espelho e da simulação): #1039, #1040, #1042, #1047, #1048, #1049 e #1056.
- Nenhuma chegou ao proprietário.
- Nenhuma foi confirmada nem realizada.
- 6 expiraram, e a #1056 está em `confirmando`.

Todas as 19 `confirmada` e as 11 `realizada` são de teste ou simulação: o número …2835 em modo teste entre 12 e 15/09, o espelho …0001 em 22/09 e a #1, uma simulação de 10/09 com corretor falso. As 38 conversas de papel `proprietario` são todas de teste (`nai_turno.teste = true`); a última é de 15/09. Das 25 de papel `motoboy`, 9 são reais, todas do André, sem visita.

O caminho novo da 179 ("o sim do corretor vai direto ao dono") nunca rodou: há 0 eventos `aprovada`.

O acompanhante não é o Fernando. Na tabela `equipe`, Fernando …9498 está inativo, e André …5964 está ativo desde 16/09.

As visitas reais de 29/09 foram tocadas por gente no chat e por uma agenda paralela do publicador:
- `detectar_visitas.py` e `alertar_visitas.py`, cron a cada minuto, tabela `visita`;
- por exemplo, o detector registrou "#30701 Efigenia 29/09 16h00 'Amanhã vou ter uma visita no Plaza às 16:00'";
- o André perguntou à Nay 5 vezes pela visita das 15:30 e recebeu "Não consta nenhuma visita pendente".

Abaixo está o que o código faz hoje (`visita_sem_aprovacao = sim`), com o teste completo #124 e os casos reais.

**Etapas, como estão no código**

| # | Etapa | Função | Mensagem | Quem recebe |
|---|---|---|---|---|
| 1 | Corretor pede, com código e horário | `pedir_visita` → `nai_pedir_visita` | Valida o código (dito por ele em 72 h, existe, não é parceiro, está no mercado), o horário (não passou, até 45 dias) e se há visita aberta. Com 3 h ou mais de antecedência (`antecedencia_minima_horas=3`), cria a visita em `confirmando` e devolve `nai_texto_confirmar_visita`: "🏠 *Confirmação de visita* / Sua visita ao imóvel foi agendada. / 🔑 Código do imóvel: #N / 📅 Data: DD/MM (dia) / 🕐 Horário: HHhMM / Por favor, confirme se os dados estão corretos." | corretor (papel `turno`) |
| 1b | Menos de 3 h | idem | Estado `com_tel`, evento `urgente_com_tel`. "Tel, VISITA URGENTE (menos de 3h): … Eu parei aqui: não falei com o proprietário nem com o André, e parei de responder esse corretor… Se quiser que eu siga, responda VISITA N OK." O chat do corretor para (`nai_parar_chat`) e o modelo responde SILENCIO. | Tel |
| 2 | Corretor confirma ("sim") | o modelo chama `pedir_visita` de novo com o mesmo horário → `nai_visita_corretor_confirmou` (179a) | Marca `aprovada_por = automática (o corretor confirmou)`. Se ficou em cima da hora, vai ao Tel. Senão chama `nai_visita_seguir_para_proprietario` → `nai_pedir_ao_proprietario`. O corretor recebe "Certo! Vou ver esse horário com o proprietário e já te retorno." Pelo código, se o dono não tiver telefone, o chat do corretor já parou no passo 3a e essa frase sai barrada `tel_assumiu`; isso ainda não aconteceu em produção. | corretor |
| 3a | Sem telefone do dono | `nai_pedir_ao_proprietario` | Estado `com_tel`, evento `proprietario_sem_contato`. "Tel, pedido de visita no X, … Não consigo falar com o proprietário (imóvel sem proprietário cadastrado). Parei de responder esse corretor… VISITA N OK / HORARIO 16h / CANCELA". O chat do corretor para. | Tel |
| 3b | Com telefone do dono | idem | Estado `aguardando_proprietario`, motivo `p_solicita`. Na primeira vez vai a apresentação (`apresentacao_proprietario`) + "Bom dia, Hugo! Tudo bem? Aqui é a Nay, da Imob Easy. Temos um pedido de visita no seu imóvel do Y para amanhã de manhã, às 10h. Tem como receber a visita nesse horário?". O Tel recebe `nai_texto_visita_completa`("…já estou falando com o proprietário…"), e o aprovador (…6408, papel `equipe`) recebe o mesmo aviso. | proprietário, Tel, …6408 |
| 4 | Dono responde | agente "NAI (proprietário)" → `nai_resposta_proprietario` | **aceita** → `nai_prosseguir_acesso`. Sem acesso conhecido: "E como é para entrar? precisa de chave?". Fechadura: pede a senha. Buscar chave: "Onde e a partir de que horas o André pode pegar a chave?". Tudo certo: "Combinado, então: visita confirmada…, O André, da nossa equipe, acompanha a visita." **outro_horario** → corretor: "o proprietário não consegue…, mas sugeriu…. Funciona pro seu cliente?". **cancela/dúvida** → Tel, e os chats param. | proprietário, corretor ou Tel |
| 5 | Acompanhante | `nai_prosseguir_acesso` | Estado `aguardando_motoboy`. "Olá, reservamos uma visita ao imóvel <endereço interno> do proprietário X, <hora>, pelo corretor Y (…). Posso confirmar que você vai acompanhar?" (`flag_fernando`) | André |
| 6 | Acompanhante confirma | antes da 186: agente "NAI (Fernando)" → `nai_resposta_motoboy`. Hoje: só pelo comando `VISITA N ANDRÉ OK` do Tel | `nai_confirmar_visita` → "Visita confirmada, X! Amanhã…, no Y. / Quem vai acompanhar sua visita é o André, (92) …5964. / 🔑 A chave fica por nossa conta, deixa que eu providencio." Em seguida: "Me passa o nome completo e o CPF do visitante?", e o Tel recebe "Tel, visita CONFIRMADA" com a ficha completa. | corretor, Tel |
| 7 | Dados do visitante | `guardar_dados_da_visita` → `nai_guardar_dados_visita` | O dono recebe "O visitante é X, CPF Y, com o corretor Z." A agenda cobra "Só falta … pra eu fechar a visita" (primeiro após 3 min, no máximo 3 vezes) e depois avisa o Tel. | proprietário, corretor |
| 8 | Lembretes | `nai_agenda_tick` | No começo do período: "passando pra lembrar da visita…". 1 h antes: "daqui a 1 hora…". 30 min antes, ao acompanhante: senha, chave ou "o proprietário vai estar lá". | corretor, André |
| 9 | Resultado | `nai_agenda_tick`; `resultado_da_visita` → `nai_resultado_visita` | 60 min depois: "E aí, X, como foi a visita no Y? O cliente gostou?", e a visita vira `realizada`. A resposta vai ao Tel ("…disse que o cliente QUER ALUGAR… É com você para fechar o contrato.") e o chat do corretor para. | corretor, Tel |

**Exemplo completo (teste #124, 13/09 00:11–00:22, modo teste, código da época v17)**
- 00:11 pedida para 14/09 10h → `p_solicita` ao dono (Hugo).
- 00:12 o dono sugere 16h → o corretor é consultado.
- 00:13 contraproposta 17h → o dono aceita e informa chave com a gente.
- 00:14 aviso ao acompanhante; ele diz que não pode → Tel.
- 00:15 o Tel manda `VISITA 124 HORARIO 18h`.
- 00:17 o corretor aceita → dono e acompanhante avisados.
- 00:18 o acompanhante confirma → "Visita confirmada" + pedido de dados → dados ao dono.
- 00:19 lembrete de 1 h; 00:20 aviso ao acompanhante; 00:21 pós-visita.
- 00:22 "quer alugar" → Tel.
- No total foram 29 eventos e 15 mensagens enviadas, todas redirecionadas ao número de teste.

**Casos reais**
- **#1048** (5758, Efigenia …0860; é o que andou mais longe, pelo caminho antigo 141):
  - 28/09 19:48 pedida para 29/09 16h; 19:49 "Sim Correto" → `aguardando_rayssa`.
  - Mensagem ao …6408: "Rayssa, pedido de visita para confirmar #1048: 🏠 Kopenhagen / 📍 … / 💰 Venda: R$ 270.000 / #5758 / 📅 29/09 (terça) 🕐 16h00 / Corretor: … / Proprietário: ⚠ sem proprietário cadastrado / … Falta o telefone do proprietário. Me manda assim: TELEFONE 1048 …"
  - Lembretes ao …6408 às 20:20 e 20:50. Ninguém respondeu.
  - 29/09 13:00 `aprovacao_sem_resposta` → Tel; o chat parou. 16:00 `expirada` → Tel.
  - Enquanto isso, a visita aconteceu de verdade às 16h e foi tratada fora da Nay. Às 17:00 a corretora escreveu "Ele gostou A compra é a vista". O modelo chamou `resultado_da_visita`, que não achou visita `confirmada`/`realizada`, e nada chegou ao Tel.
- **#1049** (5722, Maria …9959):
  - 29/09 07:15 pedida para 10:00 → urgente → Tel.
  - 07:18 o Tel mandou `visita 1049 ok` → a resposta pediu `ACESSO 5722 …` "e depois VISITA 1049 OK de novo". O Tel não respondeu, e a visita ficou em `aguardando_acesso`.
  - A corretora cancelou por conversa manual ("Pode cancelar os dois", 08:57), mas a visita continuou aberta.
  - 10:00 expirou. O "não consegui fechar…" à corretora foi barrado `tel_assumiu`, mas o texto ao Tel dizia "Avisei o corretor".
- **#1039** (5734, Maria …5070, 23/09): sem cadastro de dono → Tel. O Tel mandou `Visita 1039 ok` e `ACESSO 5734 proprietário abre`, mas não o "OK de novo". A visita ficou em `aguardando_acesso` até expirar em 26/09 10:00.
- **#1040, #1042 e #1047:**
  - #1040 e #1042: sem cadastro de dono → Tel → expiradas.
  - #1047: `confirmando` sem resposta; expirou calada às 03:28 de 29/09, antes da 179b.
- **#1056** (840, Úrsula …5952, 29/09 16:02, para 30/09 13:00): em `confirmando`. O 840 tem dono com telefone, então, se ela confirmar a tempo, será a primeira visita real a chegar a um proprietário. Pelo código, se não confirmar até 30/09 04:02 (12 h depois de criada), a visita expira e o aviso vai ao Tel nessa hora: papel `tel` sai fora da janela.

---

### 27. O que do fluxo desenhado ainda não existe ou não funciona

**Premissa.** O `fluxodemensagens.html` do repositório é a versão 1 (10/09, 70 cards). No servidor, o fluxo `locacao` está na versão 26 (`site_fluxos`, 16/09 14:30, 79 cards). Alguns cards mudaram:
- `v_2h`: era "Consulta se temos a chave, menos de 2 horas" e virou "VISITA URGENTE: menos de 3 horas".
- `pv_senha` e `pv_chave`: saíram do corretor e foram para o motoboy.
- `pv_feedback`: virou o "VISITA E aí…".

A comparação abaixo é com a v26.

Resumo: para os seis itens o código existe. Nenhum deles rodou numa visita real, porque o fluxo morre antes: sem dono em 23 de 37 imóveis, e sem o agente do acompanhante.

| Item desenhado | Hoje | Onde está |
|---|---|---|
| Chave (conosco / buscar e devolver) | Existe, nunca usado em visita real | `nai_prosseguir_acesso` pergunta ao dono "E como é para entrar? precisa de chave?" ou "Onde e a partir de que horas o André pode pegar a chave?". `nai_linha_acesso_corretor` gera "🔑 A chave fica por nossa conta, deixa que eu providencio." Agenda: `aviso_motoboy` ("você já está com a chave…") e `devolver_chave` depois do pós-visita. `nai_acesso_imovel` tem 6 linhas, todas de testes ou do comando `ACESSO` do Tel. Pelo Tel, `ACESSO` não faz a visita andar sozinho: precisa de `VISITA N OK` de novo (#1039 travou aí). |
| Fechadura | Existe, nunca usado | O dono recebe "Pode me passar a senha da fechadura? Ela fica só com o André…". A senha vai ao acompanhante 30 min antes ("Conseguiu anotar?") e é apagada ao encerrar. |
| Urgente, menos de 3 h | Existe e funciona | `nai_pedir_visita` e também `nai_visita_corretor_confirmou`. Real: #1049 (Tel avisado, chat parado). O caminho de volta (`VISITA N OK`) cai no pedido de ACESSO. |
| Cobrança do proprietário em 30 min | Existe, nunca usado em real | `nai_agenda_tick`: `reenvio_proprietario_min=30`, `reenvios_proprietario_max=3` (`p_lembrete`); depois do 1º reenvio, `p_avisa` ao corretor. Nos testes de 12–13/09, 16 cobranças foram barradas como `repetida`. |
| Aviso ao Tel 2 h antes | Existe, disparou 1 vez (teste de 13/09) | `nai_agenda_tick`, `p_tel_2h` (`aviso_tel_horas_antes=2`): para o chat do corretor e o do dono; o Tel responde `VISITA N AVISA 10h`, e se o dono não responder, `p_ligar`. Só vale quando `aguardando='proprietario'`, que nenhuma visita real alcançou. |
| Pós-visita "como foi?" | Existe só para a visita `confirmada` | Agenda, `pos_visita_min=60`; `nai_resultado_visita` → Tel. O botão do CRM `crm_visita_realizada` também existe. Real: a #1048 aconteceu fora da Nay, a corretora contou o resultado e ele se perdeu (ver a 26). |
| Acompanhante confirma pelo WhatsApp | Não funciona desde a 186 (29/09 ~16:40) | `nai_abrir_turno` devolve `ok:false` para o papel `motoboy`, e o "NAI (Fernando)" nunca roda. Só anda com `VISITA N ANDRÉ OK` (ou `FERNANDO OK`/`MOTOBOY OK`) do Tel. A agenda ainda pergunta ao acompanhante "consegue me confirmar a visita…?". |
| Dados do corretor e do visitante depois da confirmação | Existe | `nai_confirmar_visita`, `nai_guardar_dados_visita`, cobrança `dados_falta`. |
| Tel fecha o contrato ("quer alugar") | Existe | `nai_resultado_visita` → Tel + `nai_parar_chat`. |

Coisas que estão no código e não estão no desenho v26:
- o modelo "🏠 Confirmação de visita" (estado `confirmando`, 141);
- a aprovação pelo …6408 (141), desligada por `visita_sem_aprovacao=sim`;
- o aviso ao Tel e ao …6408 quando fala com o dono (179);
- a visita em `confirmando` que vence em 12 h (179b).

---

### 28. Como a Nay acha o proprietário, e quantos imóveis têm dono com telefone

**Caminho** (`nai_proprietario_do_imovel(codigo)`, igual ao `02_auxiliares.sql`)
1. `imovel_privado.proprietario_id` → `proprietarios` (nome e telefone).
2. Se não achou: `proprietarios_admin_imoveis` → `proprietarios_admin`, e só se o imóvel tiver exatamente um dono. Dois donos devolvem `dois_donos`.
3. Nome com "tratar/falar/contato com" devolve `tratar_com_outra_pessoa`.
4. Usa o primeiro telefone que aparece no campo; sem telefone, `sem_telefone`.

`nai_pedir_ao_proprietario` ainda dá preferência a `nai_visita.prop_telefone_manual`, gravado pelo comando `TELEFONE N 92…` do aprovador (141). Se o "dono" for o próprio corretor, a visita vai ao Tel.

A Nay **não lê `imoveis.proprietario_id`**, que é onde a maior parte dos donos está ligada.

**Número exato: 14.**
- `vw_catalogo_locacao` não é "disponível": é só `imoveis WHERE valor_aluguel > 0` (1.307 linhas, inclusive alugados e parceiros).
- Com o critério da própria visita (`nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)` e não parceiro), sobram 90 no mercado e **37** de locação disponíveis para a Nay.
- Desses 37, **14** têm dono com telefone pelo mesmo caminho da visita: 9 por `imovel_privado` e 5 pelo admin antigo. 6 desses 14 também têm preço de venda.
- Os outros 23: 22 `sem_cadastro` e 1 `tratar_com_outra_pessoa`.

**Achado.** 21 dos 22 `sem_cadastro` têm dono com telefone em `imoveis.proprietario_id` → `proprietarios`. Se a função lesse essa ligação, seriam 36 de 37. Foi exatamente o que derrubou as visitas reais: 5722, 5758, 3050, 5724 e 5734 têm `imoveis.proprietario_id` com telefone e nenhuma ligação em `imovel_privado`.

Para comparar, na venda são 219 disponíveis, e 180 têm dono com telefone.

---

### 29. Agentes "NAI (proprietário)" e "NAI (Fernando)"

**Como são montados**
- São dois nós Agent (langchain v3.1), cada um com um lmChatOpenAi `gpt-5.6-sol` ("GPT (proprietário)", "GPT (Fernando)").
- Memória: `memoryPostgresChat`, tabela `nai_memoria`, chave `cab.memoria` = `nai:<papel>:<contato>:v<visita>`, janela de 40.
- **Prompt:** vem do banco, tabela `nai_prompt` (papel `proprietario`, 2.239 caracteres; papel `motoboy`, 813; os dois atualizados em 15/09 00:50). Chega por `cab.prompt` (`nai_prompt_de`, chamada em `nai_abrir_turno`). A expressão do systemMessage lança `PROMPT_VAZIO` se o prompt tiver menos de 500 caracteres.
- A mensagem de usuário leva data e hora de Manaus, o vocativo, `cab.contexto` (`nai_contexto(papel, contato, visita, teste)`) e o texto.
- **Os dois prompts ainda falam "FERNANDO"**, e o do proprietário cita "o Fernando pega a chave". O acompanhante ativo é o André. Foi daí que veio o "Boa noite, Fernando." mandado ao André em 28/09 20:57.

**Ferramentas: uma para cada agente**
- `resposta_do_proprietario` → `nai_resposta_proprietario(turno, decisao, quando, acesso, detalhe, senha)`. As decisões são `aceita`, `outro_horario`, `recusa`, `acesso`, `cancela` e `duvida`.
  - Se não sabe de qual visita se trata: avisa o Tel, para o chat e manda SILENCIO.
  - Aprende o acesso em `nai_acesso_imovel`.
  - Aceita ou acesso → `nai_prosseguir_acesso`.
  - Outro horário → pergunta ao corretor.
  - Cancela ou dúvida → Tel, e os chats param.
- `resposta_do_motoboy` → `nai_resposta_motoboy(turno, visita, decisao, obs)`, com as decisões `confirma`, `nao_pode`, `problema` e `outro`.
  - Confirma: se o dono já confirmou, chama `nai_confirmar_visita` e devolve `nai_texto_motoboy_ok` ("Fechado, André, agendei aqui…").
  - Não pode ou problema: vai ao Tel e os dois chats param.

**Roteamento e volta**
- `nai_abrir_turno` decide o papel:
  - `motoboy` se o número é de `equipe` com papel `acompanhante` e `ativo`;
  - `proprietario` se o contato é `proprietario_id` de uma visita aberta.
- "Rotear pelo cabeçalho" → "Qual caminho?", saídas 3 (proprietário) e 4 (motoboy) → agente → "Resposta do proprietário" / "Resposta do Fernando". Esses nós são code que só repassa `output`, com `codigos: []`, sem fotos.
- → "Enfileirar resposta" (`nai_enfileirar_resposta_ferramentas`): SILENCIO corta a resposta, e para esses papéis os emojis são tirados na etapa 07 de `nai_conferir_resposta`.
- → "Fechar turno" → "Liberar saída".

**Como o resultado chega ao corretor.** Não é pelo agente do corretor. As próprias funções enfileiram linhas com `papel_destino='corretor'` e `visita_id`, no mesmo turno do dono ou do acompanhante. O gatilho só aceita se o contato for o `corretor_id` da visita. Essas linhas saem na mesma execução, porque o "Liberar saída" pega tudo o que tem `turno_id` daquele turno. Se o chat do corretor estiver parado, a linha cai em `tel_assumiu`. Avisos ao Tel saem como `tel`.

**Na prática**
- O agente do proprietário nunca atendeu um dono real: são 38 turnos, todos de teste, o último em 15/09.
- O agente do acompanhante virou código morto com a 186. Antes dela, ele respondia o André sem visita nenhuma: em 29/09, 5 respostas entre 14:59 e 15:22, do tipo "Não consta nenhuma visita pendente. Qual é o número da visita…?".
- Com a 187, o que o acompanhante escreve só vai ao Tel se ele tiver visita aberta em `nai_visita` (`acompanhante_escreveu`); até agora foram 0.
- `nai_acompanhante()` pega o acompanhante ativo mais novo, e `nai_motoboy()` o mais antigo. Hoje dá o mesmo resultado (só o André está ativo), mas os dois divergem se houver dois ativos.

---

### 30. Agenda (a cada minuto): o que verifica, o que dispara e o que já disparou errado

**Premissa.** Não é um gatilho de banco. É o nó "Agenda (todo minuto)" (scheduleTrigger, 1 min) → "Agenda da NAI" (`SELECT nai_agenda_tick()`) → "Liberar saída" com lote NULL. O batimento fica em `nai_config._agenda_rodou_em` (19:22:15 na leitura). No n8n, entre 13:58 e 19:36 de 29/09, há 339 execuções `trigger` com sucesso, uma por minuto, mais 48 com status `new`; NÃO SEI o que essas 48 significam. A função viva é igual ao `179b_visita_vencida_avisa_o_tel.sql`.

**O que `nai_agenda_tick` verifica, em ordem**

Antes do laço:
- Grava o batimento. Se `modo` não é `teste` ou `todos`, para.

Para cada visita não encerrada, cancelada nem expirada (ordenadas por `quando`, `FOR UPDATE SKIP LOCKED`):
1. **`confirmando` há mais de 12 h, ou a menos de 30 min da hora** → `expirada` + Tel ("o corretor não confirmou os dados a tempo…", 179b).
2. **`aguardando_rayssa`:**
   - perto da hora (3 h) → `com_tel`, Tel avisado, chat do corretor parado;
   - senão, lembrete ao …6408 a cada 30 min, no máximo 2 vezes.
   - Isso está dormente enquanto `visita_sem_aprovacao=sim`.
3. **Passou da hora sem fechar** (`coletando`, `aguardando_proprietario`, `negociando`, `aguardando_acesso`, `aguardando_motoboy`, `com_tel`) → `expirada`.
   - O corretor recebe "não consegui fechar a visita de … a tempo, desculpa. Quer tentar outro horário?", menos quando a visita estava `com_tel`.
   - O Tel recebe a ficha e o passo em que a visita parou.
4. **`confirmada` com dados faltando** → "Só falta … pra eu fechar a visita", até `dados_lembretes_max=3` ou 1 h antes; depois, Tel (`dados_sem_resposta`).
5. **Proprietário sem responder:**
   - aviso marcado pelo Tel (`AVISA`) → `p_lembrete_tel`;
   - 30 min sem resposta → `p_lembrete`, até 3 vezes;
   - depois do 1º reenvio → `p_avisa` ao corretor;
   - 2 h antes → `p_tel_2h`, e os dois chats param (uma vez só).
6. **Aviso do Tel sem resposta em 30 min** → `p_ligar`.
7. **Acompanhante sem responder 30 min** → `motoboy_lembrete` (1 vez); depois, Tel (`motoboy_sem_resposta`).
8. **`confirmada`:**
   - `lembrete_periodo` (início da manhã, tarde ou noite: 08h, 12h, 18h);
   - `lembrete_1h`;
   - `aviso_motoboy` 30 min antes;
   - `pos_visita` 60 min depois, com `devolver_chave` e a mudança para `realizada`.
9. **`realizada` há mais de 2 dias** → `encerrada`.

Depois do laço:
- **`nai_lembretes_disparar`** (lembrete da equipe, "⏰ Lembrete: …"). Tem EXCEPTION própria. Nunca foi usado: `nai_lembrete` tem 0 linhas.
- **`nai_followup_rodar`**, também com EXCEPTION própria.
  - Segunda a sábado, das 09:00 às 18:00, até 2 por minuto.
  - Vai para quem recebeu imóvel ontem: "Oi X, seu cliente tem interesse?" e, 8 s depois, "…o que está procurando para seus clientes?".
  - Pula quem é da equipe ou teste, quem recusou, quem tem visita aberta, quem está com o Tel, quem já conversou hoje e quem o Tel disse que não é corretor.
  - Até agora: 26 enviados (52 mensagens, 24 pessoas) e 13 pulados.

Por fim, o "Liberar saída" com lote NULL solta tudo que venceu:
- linhas sem turno;
- linhas de turno com mais de 3 min (a rede de segurança);
- hora marcada;
- reenvio da Z-API.

Tudo dentro da janela 06:00–22:00, menos os papéis `tel` e `equipe`.

**O que já disparou errado (casos reais)**
- **29/09 10:00, #1049:** o Tel recebeu "…chegou no horário sem fechar (estava: aguardando_acesso). Avisei o corretor." Mas a mensagem à corretora saiu `bloqueado tel_assumiu`: havia um carimbo "o Tel escreveu pelo celular" de 09:44 na linha LID dela. O texto novo da 179b continua dizendo "Avisei o corretor" sempre que o estado não é `com_tel`, sem conferir se a mensagem saiu.
- **24/09 15:00, #1040:** o aviso de expiração ao Tel foi barrado com `nai_pausada`. Com a Nay pausada, nem os avisos de visita chegam ao Tel; só passam respostas a comando e lembretes da equipe.
- **29/09 03:28, #1047:** expirou calada, só com o evento, porque foi antes da 179b.
- **28/09, #1048:** dois lembretes ao …6408 (20:20 e 20:50) e depois silêncio até 13:00 do dia seguinte, quando foi ao Tel. A visita ficou 17 h parada.
- **Follow-up de 29/09 ~09:03 para …4991:** perguntou "seu cliente tem interesse?" sobre 776, 2515, 3139 e 4903. Ele nunca recebeu esses imóveis: tudo tinha sido barrado `tel_assumiu` no turno 12273, mas a reserva de 24 h ficou (ver a 22). Foi 1 dos 26 follow-ups.
- **Acompanhante:** a agenda ainda manda perguntas ("consegue me confirmar a visita…?", "Conseguiu anotar?"), mas desde a 186 as respostas dele não chegam a nenhuma IA.
- **Testes de 12 e 13/09:** a mesma cobrança ao dono foi gerada repetidamente, e 16 `p_lembrete`, 7 `pos_visita`, 7 `p_avisa`, 6 `lembrete_1h` e 6 `aviso_motoboy` foram barrados como `repetida` (número de teste, horários forçados).

**Agenda paralela, fora da NAI (fato; se funciona bem hoje: NÃO SEI).** O publicador tem outra agenda de visitas.
- `detectar_visitas.py` roda por cron a cada minuto, lê `mensagens` e grava a tabela `visita` (0 linhas agora; ela apaga o que passou).
- `alertar_visitas.py` manda ao Tel e, desde 28/09, também ao …6408: briefing às 06:00, véspera às 18:00, lembrete 90 min antes, pendência de 1 h e "o que falta" às 08:00. Às 07:00 pergunta ao corretor se a visita está confirmada.
- O batimento `.batimento_alertar_visitas` foi tocado em 29/09 às 19:44 de Manaus.
- O log `alertar_visitas.log` tem 6 `NameError: _confirmar_com_o_corretor` e foi escrito pela última vez em 23/09 às 14:26 de Manaus. Desde então está em silêncio, que é o comportamento normal quando não há erro.

---

## Blocos 6 e 7: quem é quem e dados

Medido em 29/09/2026, entre 19h e 20h30 (Manaus), com `q.sh` (banco só leitura), `n8nq.sh`, os JSON exportados do n8n e `crontab -l` / `ls` / `grep` no servidor. Telefones e @lid aparecem só com os 4 últimos dígitos. O número do Tel (…7316) aparece inteiro onde o código o traz.

---

## BLOCO 6: QUEM É QUEM

### 31. Como a Nay decide o papel de quem escreveu

**Duas premissas da pergunta estão erradas.** (1) Não existe papel "desconhecido": o papel padrão é `corretor`, e quem decide se um desconhecido é atendido é a **porta** (`nai_deve_atender`), não o papel. (2) O "Fernando" não está mais em serviço: em `equipe`, Fernando (…9498) tem `ativo = false` e o acompanhante ativo é o André (…5964, `papel = 'acompanhante'`). O nó continua chamado "NAI (Fernando)" e o papel no banco continua `motoboy`.

**Etapa 0, qual fluxo recebe (fluxo antigo "Nay- recebe mensagem").** O Webhook da Z-API cai no nó "NAI ou Nay? (quem atende)", que chama `nai_quem_atende(phone, isGroup||isNewsletter||broadcast, texto)`, a sobrecarga de 3 argumentos. A ordem é esta:
1. É o Tel (`nai_config.tel_telefone` = 559294717316), fora de grupo, e o texto casa `nai_e_comando_publicador` (vendeu/alugou, posta/publica/dispara, tira N, vagas, resposta/descartar N, "envia … para …")? Então devolve `'nay'` e a mensagem segue no fluxo antigo até o publicador.
2. É comando da NAI (`nai_e_comando_tel` ou `nai_e_comando_extra`) de quem `nai_pode_comandar` (lista `comando_telefones` = …7316 e …6408)? Então devolve `'nai'`.
3. Senão cai na sobrecarga de 2 argumentos `nai_quem_atende(phone, grupo)`: grupo ou chave nula dá `'nay'`. Como `modo = 'todos'`, o resto dá `'nai'`. Um erro dá `'nay'`.
O nó "Vai para a NAI?" encaminha o corpo por HTTP ao webhook da NAI ("Mandar para a NAI"). Se esse POST estourar o prazo, o nó "Prazo estourado? (a NAI recebeu)" devolve a mensagem ao "Filtrar e normalizar" do fluxo antigo.

**Etapa 1, o papel (`nai_abrir_turno`, chamada pelo nó "Abrir turno").** Antes de tudo a função chama `nai_contato_de(p_tel, nome)`, que faz upsert em `nai_contato` pela chave (`nai_chave`: telefone normalizado ou `lid:<dígitos>`). Com isso **todo número novo ganha uma linha**, e não existe cadastro prévio. Fora do modo teste, a ordem é:

| Ordem | Condição (função viva) | Papel |
|---|---|---|
| 1 | `nai_e_voz_do_tel(chave)` = `tel_telefone` ou `comando_telefones` (…7316, …6408, o número da Imob Easy). Vale **para qualquer texto** | `tel` |
| 1 | `nai_e_comando_extra` + `nai_pode_comandar`; envio (`nai_e_comando_envio`), checklist ou lembrete de alguém da equipe (`nai_e_da_equipe_contato`); `nai_resposta_aprovacao_valida` (SIM/NÃO n da visita) | `tel` |
| 2 | `nai_e_motoboy(chave)`, isto é, `equipe.papel='acompanhante' AND ativo`, hoje só o André | `motoboy` |
| 3 | existe `nai_visita` aberta com `proprietario_id = v_contato`, **só essa linha, sem irmãos** | `proprietario` |
| 4 | todo o resto | `corretor` |

`nai_e_da_equipe_contato` junta o Tel, `so_estes_numeros` (hoje vazio), `nay_e_da_equipe` (tabela `equipe` ativa, comparando os 8 últimos dígitos; inclui o André e a Rayssa …1557) e `nai_pode_comandar`. No modo teste (números em `numeros_teste` = …2835 do Pedro e o espelho …0001), o papel vem dos prefixos `P:` / `M:` / `André:` / `T:` ou da mensagem redirecionada que foi marcada.

Desde a 186/187, um turno de `motoboy` é gravado e `nai_abrir_turno` devolve `ok:false, motivo 'acompanhante_so_recebe_aviso'`. A Nay não responde. Se o acompanhante tiver visita aberta e diferente de `realizada`, o texto vai ao Tel (`nai_avisar_tel … 'acompanhante_escreveu'`). Em 29/09 foram 7 turnos assim.

**Etapa 2, a porta (`nai_deve_atender`, gravada em `nai_turno.porta` e exposta em `cab.atende`).** A config é `regra_publico = 'sim'` desde `2026-09-28 07:00:02-04`. A ordem: Tel com a conversa (`nai_tel_com_a_conversa`, pausa de 30 min) → lista curta (vazia) → equipe ("da equipe: sempre atendida") → **lista de corretores** (`so_corretor_da_lista = 'sim'`, **ligada**) → "conversa já liberada" → "conversa que ela já estava atendendo" → marcou mensagem de imóvel → contato novo falando de imóvel → link de catálogo, card colado ou código → citou condomínio nosso → pediu foto com código → pediu imóveis → "conversa que já existia: quem responde é o Tel".
- A lista é `corretores` com `pode_falar AND ativo`: 1.523 de 1.538 linhas. Por fonte: grupo 1.459 (sincronização semanal, segunda 10:10 UTC = 06:10 Manaus, `sincronizar_grupos_corretores.sh` → `nai_sincronizar_grupos`, a partir dos 23 grupos com `nai_grupo_corretor.incluir`, 4.676 vínculos), agenda "Xx" 34 (cron `23 * * * *` `/root/sincronizar_agenda_xx.sh`), tel 32 (comando CORRETOR) e site 9. **Divergência com a memória:** o índice MEMORY.md diz "só corretor dos grupos, pronta e DESLIGADA". No banco a chave está `'sim'` e a porta a aplica.
- `nai_lista_governa` isenta da lista só o Tel, quem comanda, o acompanhante, a `equipe` e o **dono de visita aberta**. Um proprietário sem visita aberta passa pela lista como um corretor qualquer.

**Etapa 3, o roteador (nó "Rotear pelo cabeçalho").** `papel='tel'` vem **antes** da checagem de pausa: com `cab.comando_nai` vai para `tel_nai`; com o comando antigo (regex no JS) vai para `tel_antigo`; senão vai para `agente`. Depois vêm `pausado` → `proprietario` → `motoboy` → `cab.atende === false` (silêncio) → código solto → `agente`. O ramo `agente` passa pela mente ("Jev decide" → `nai_decidir_com_jev` → `nai_mente_registrar`), que escolhe entre "NAI (corretor)" e "NAI (secretária)".

**O que acontece com o desconhecido (número fora de `corretores`, sem ser equipe nem dono em visita).**
- Ele ganha linha em `nai_contato`, a mensagem fica em `mensagens` e o turno em `nai_turno`. **Não recebe resposta nenhuma.**
- Se a mensagem é pergunta de imóvel (`nai_pergunta_de_imovel`) e é a primeira vez, a porta grava `'fora da lista: perguntou de imovel, perguntar ao Tel'`. O gatilho `nai_turno_pergunta_corretor` (AFTER INSERT em `nai_turno`, WHEN porta = esse texto) roda `nai_perguntar_se_e_corretor`, que insere em `nai_corretor_pergunta` e manda ao Tel: "Chegou mensagem de quem NÃO está nos grupos… É corretor? Responda: CORRETOR (92)… / NAO CORRETOR (92)…". Nas mensagens seguintes a porta diz `'fora da lista: esperando o Tel dizer se e corretor'`. Se não é pergunta de imóvel, a porta diz `'fora da lista de corretores'`. Se o Tel disse NÃO, a porta diz `'o Tel disse que nao e corretor'`.
- Em `nai_corretor_pergunta` há 27 linhas: **21 nunca decididas** (a mais recente é de 29/09 14:13), 5 NÃO e 1 SIM. As 6 decisões são todas de 22 e 23/09.
- A rota "cortesia" ("oi! aqui é a Nay… me manda seu nome e CRECI", `nai_enfileirar_cortesia`) **está morta**. Ela exige `cab.atende` indefinido, e isso só acontece com `regra_publico` desligada. `nai_saida` nunca teve linha com `motivo='cortesia'`.
- Exemplo real: turnos 12302 e 12303 (28/09 15:44), @lid …6208, que em `identidade_lid` mapeia para um telefone terminado em …6615. O mesmo final é o do dono do 3050 em `imoveis.proprietario_id`. Os dois turnos ficaram com porta `'fora da lista de corretores'`, em silêncio. Seis horas antes a visita 1042 do 3050 tinha terminado em `proprietario_sem_contato / sem_cadastro`. [OPINIÃO: muito provavelmente o dono do 3050 escreveu e ficou calado por ser tratado como corretor fora da lista.]

**Contagem de papéis em `nai_turno`.** A tabela começa em 10/09, então os 30 dias cobrem tudo: 3.437 turnos.

| Papel | Turnos | Contatos | Observação |
|---|---|---|---|
| corretor | 3.213 | 279 | 1.032 de teste |
| tel | 161 | 3 | …7316: 104; …2835 (Pedro, teste): 49; …6408: 8. Inclui 35 "disparo pelo painel" do site/CRM |
| proprietario | 38 | 2 | **todos de teste**, o último em 15/09. Nenhum proprietário real teve turno na NAI |
| motoboy | 25 | 3 | 9 reais, do André, em 28 e 29/09 |

Porta desde a religação (28/09 07:00, só produção): "conversa já liberada" 113, "já estava atendendo" 100, **"fora da lista de corretores" 90 (12 contatos)**, "conversa que já existia: quem responde é o Tel" 43 (24 contatos), "esperando o Tel dizer se é corretor" 29, equipe 21, citou condomínio 14, marcou mensagem 9, colou card 9, contato novo falando de imóvel 8, contato novo sem assunto de corretor 6, perguntar ao Tel 4, pediu imóveis 4.

**Onde mora.**
- Config em `nai_config`: `modo`, `regra_publico`, `regra_publico_desde`, `so_corretor_da_lista`, `so_estes_numeros`, `tel_telefone`, `comando_telefones`, `aprovador_visita_telefone` (…6408), `numeros_teste`, `pausada`, `secretaria_ligada`, `proprietario_pelo_tel = 'nao'`.
- Tabelas: `equipe`, `corretores`, `nai_corretor_pergunta`, `identidade_lid`, `nai_visita`.
- O fluxo antigo ainda tem uma cópia literal dos números do Tel no JS: `TELS_DO_TEL = ['559294717316','…6408 (número da Imob Easy)']` nos nós "Rotear para o agente" e "Comando do Tel".

### 32. O problema telefone × @lid

**O mecanismo.**
- A Z-API entrega a mesma pessoa às vezes com o telefone e às vezes com o @lid (`<dígitos>@lid`). O "Gravar na fila" da NAI grava o `phone` **como chegou**: "o @lid NÃO é trocado por um telefone adivinhado". Já o fluxo antigo resolvia com `nay_resolver_identidade`. A chave vira `lid:<dígitos>` e `nai_contato_de` cria uma segunda linha.
- Quem mais cria linha @lid é o próprio Tel. O que ele digita no celular da Nay chega com `fromMe` e `phone` = @lid do chat. O ramo "Foi o Tel pelo celular?" → "Espera 15s (eco)" → "O Tel assumiu a conversa" (`nai_tel_assumiu`) carimba `humano_assumiu_em` **na linha @lid**, enquanto o corretor escreve pela linha do telefone.
- O conserto está na leitura. `nai_contato_irmaos(id)` junta as linhas pela tabela `identidade_lid`. Desde a 168 (29/09) aceita os dois formatos de `lid`: `i.lid IN (d, d||'@lid')`.

**Quanto está duplicado hoje.**

| Medida | Valor |
|---|---|
| `nai_contato` | 511 linhas: 273 de telefone, 238 @lid |
| Pessoas com duas linhas (telefone + @lid, por `nai_contato_irmaos`) | **168** (336 linhas) |
| Linhas @lid sem par | **70**: 68 sem mapeamento em `identidade_lid`, 2 mapeadas para um telefone que não tem linha |
| Linhas @lid carimbadas pelo Tel | 235 de 238. Só 21 linhas @lid têm turno, e só 30 turnos na história abriram numa linha @lid |
| Onde está o carimbo, nos 168 pares | 95 só no lado @lid, 1 só no telefone, 70 nos dois, 2 em nenhum |
| Pessoas com turno nas duas linhas | 17 |
| Linhas @lid **órfãs** carimbadas | 20 nos últimos 7 dias, 6 nos últimos 2 (último em 29/09 18:39) |
| `identidade_lid` | 1.620 linhas, 1.526 LIDs distintos (94 repetidos pelo formato), **1.463 só dígitos** (origem `grupo`) e 157 com `@lid`. Nenhum LID aponta para dois telefones |

Nas órfãs, a pausa do Tel (30 min) é invisível quando a pessoa escreve pelo telefone. [OPINIÃO: é o caso original de "a Nay falou por cima do Tel", ainda aberto para essas conversas.]

**Achado mais grave, que não é de irmãos, é de formato.** `nai_pode_falar(p_chave, p_telefone)` faz `WHERE p_chave ~ '^lid:' AND i.lid = p_telefone`, com o `phone` cru do webhook (`…@lid`). A sincronização dos grupos grava o LID **sem** `@lid`.
- Teste: 200 corretores com `pode_falar` e LID de origem `grupo`. `nai_pode_falar('lid:'||lid, lid||'@lid')`, que é o formato real do webhook, deu verdadeiro em 11. O mesmo teste com o formato só dígitos deu verdadeiro em 200.
- 1.362 corretores liberados só têm o mapeamento sem sufixo. Quando um deles escreve pelo @lid, a porta o trata como **fora da lista**.
- Caso real: turno 9985 (19/09 09:11), @lid …2549, mapeado para o corretor …6531 (`pode_falar` e ativo), texto "Cliente só quer casa em condomínio". A porta registrou `'fora da lista: perguntou de imovel, perguntar ao Tel'`, e o Tel recebeu "É corretor?" sobre um corretor da lista.
- Também caíram em `'fora da lista de corretores'`, já com a 168 no ar, os turnos 12553 (29/09 16:00, …1992 → corretor …4045) e 12609 (29/09 18:34, …4415 → corretor …8622). Nos dois a mensagem era `origem 'outro'`, sem texto.
- O mesmo `lid = p_tel` cru está em `nai_abrir_turno` (cálculo de `aprovado`). Hoje isso não pesa, porque com a regra pública ligada quem decide é `cab.atende`.
- Volume: 99 mensagens recebidas com @lid em 30 dias, de 41 LIDs. É pouco, porque a Z-API manda o telefone na maioria dos casos.

**Funções que ainda leem uma linha só.** A varredura foi `prosrc ~ 'contato_id\s*='` em funções `nai_/nay_` que não citam `nai_contato_irmaos`, e deu 47. Separei as que importam:

| Peso | Função | O que lê de uma linha só | Efeito |
|---|---|---|---|
| Alto | `nai_deve_atender` | `liberado_em` e "conversa antiga" por `c.chave = v_chave`; "já estava atendendo" por `s.contato_id = v_id`; chama `nai_pode_falar` com o LID cru | Uma conversa liberada ou atendida no telefone é julgada como nova ou antiga no @lid, e vice-versa. Corretor da lista pelo @lid fica fora da lista |
| Alto | `nai_pode_falar` | formato do LID (acima) | corretor calado |
| Alto | `nai_abrir_turno` | `x.proprietario_id = v_contato` para dar papel `proprietario`; `primeira_vez` por `m.telefone = p_tel` | Dono que responde pela outra linha vira "corretor" e cai na lista |
| Alto | `nai_lista_governa` | isenção do dono de visita por `x.proprietario_id = p_contato` | idem |
| Médio | `nai_imovel_da_conversa` | imóvel em foco pela `nai_saida` e pelo `nai_turno` da linha | Perde o imóvel ao trocar de linha |
| Médio | `nai_mente_registrar` | ficha `nai_imovel_novo` 'colhendo' por `n.contato_id = v_contato` | A secretária "desgruda" |
| Médio | `nai_contexto_corretor` | último turno, perguntas dela, o que saiu | contexto pela metade |
| Médio | `nai_estado_v2` / `nai_estado_conversa` (lidos por `nai_enfileirar_resposta_ferramentas`, `nai_pode_enviar_codigo_v2`, `nai_fila_dos_outros_imoveis`) | códigos recusados e foco | Pode voltar a oferecer o que ele recusou |
| Médio | `nai_esperando_valor`, `nai_fotos_ja_mandadas` | a pergunta de valor e as fotos já enviadas | "3500" lido como código; foto repetida |
| Médio | `nai_zerar_conversa` | `WHERE chave = v_chave` | Zera só uma das duas linhas |
| Baixo | `nai_liberar_saida` (anti-repetição de 10 min), `nai_apresentacao_prop`, `nai_sec_*` | … | pouco efeito |

Já usam irmãos: `nai_tel_com_a_conversa`, `nai_e_da_equipe_contato`, `nai_na_lista_curta`, `nay_imovel_ja_foi_24h`, `nai_saida_validar`, `nai_negocio_da_conversa`, `nai_negocio_do_que_recebeu`, `nai_codigos_que_ele_digitou`, `nai_tipo_da_conversa`, `nai_etapa_calcular`, `nai_etapa_para_o_modelo`, `nai_filtro_ja_perguntado`, `nai_buscar_por_perfil`, `nai_janela_segundos`, `nai_followup_rodar`, `nai_comando_lembrete`, `nai_conferir_resposta`, `nai_resposta_aprovacao_valida`.

[OPINIÃO: como só 17 pessoas têm turno nas duas linhas, o buraco de "estado" é pequeno em volume. O que dói é a identidade: o LID cru em `nai_pode_falar` e o dono reconhecido por uma linha só.]

### 33. Grupos: a Nay responde? O que o publicador grava e ela lê

**Ela não responde em grupo nenhum.**
- O Webhook recebe mensagens de grupo. No sqlite do n8n, 11 das 1.305 execuções do fluxo antigo (29/09, de 13:57 a 19:30 Manaus) tinham `isGroup: true`; por exemplo as execuções 141975 e 142528, com `phone` terminado em `-group`.
- `nai_quem_atende(..., p_grupo=true)` devolve `'nay'` e a mensagem vai para o "Filtrar e normalizar" do fluxo antigo, que faz `if (b.isGroup || b.isNewsletter || b.broadcast || b.isStatusReply) return [];`. A execução termina ali, sem gravar nada.
- O fluxo da NAI tem o mesmo filtro, mas mensagem de grupo nunca chega lá.
- `grupo_mensagens` tem **0 linhas**. A função `nay_registrar_mensagem_grupo` existe e nenhum workflow nem script do publicador a chama.

**O publicador** (`/root/nay-publicador`, `publicador.py` com 3.088 linhas + `servidor.py`, Flask `POST /comando`, systemd `nay-publicador` ativo, crons de minuto `disparar_grade`, `entregar_pendentes`, `disparar_lembretes`, `catalogar_postados` a cada 2 min).
- Posta os cards nos 20 grupos de `grupos` (todos ativos).
- O Tel manda comando pelo WhatsApp, e o n8n repassa via HTTP para `/comando` (URL interna e token omitidos) nos nós "Comando do Tel" dos dois fluxos.

**O que ele grava e a Nay lê.**
- `envios`: `codigo, telefone, destino ('grupo'|'corretor'), grupo_nome, message_id`. São 2.344 linhas de grupo (2.292 com `message_id`, a última em 29/09 19:01) e 311 de envio a corretor. Leitores `nai_`/`nay_`:
  - `nay_imovel_da_citacao`: o corretor responde no privado **marcando o card do grupo**, o `referenceMessageId` casa com `envios.message_id` e isso vira o código. É o que abre a porta como "marcou uma mensagem de imóvel" (25 turnos em 30 dias).
  - `nai_oferta_serve`: não oferece de novo o que ele recebeu em 30 dias.
  - `nai_tel_assumiu`: o eco do envio do publicador não vira "o Tel escreveu".
  - `nai_imovel_da_conversa`, `nai_contexto_corretor`, `nai_saida_validar`, `nai_resposta_da_base`, `nai_confirmar_envio`.
  - `nay_qual_imovel`, que é a ferramenta `imovel_do_disparo`.
  - `nay_ficou_devendo` e `nay_o_que_ficou_de_enviar`, ferramentas do fluxo antigo.
- `saida_do_sistema` (896 linhas, gravada por `enviar_zapi.py` a cada envio): lida por `nai_tel_assumiu` para reconhecer eco.
- `imovel_enviado_no_dia`: a regra "um imóvel por corretor por dia". O publicador reserva por `nay_reservar_imovel_do_dia(chave, cod, 'publicador'|'pendentes')` e a Nay confere em `nay_imovel_ja_foi_24h` dentro de `nai_saida_validar`. Hoje há 106 linhas: nai 85, publicador 12, histórico 9.
- `easy_publicacoes`, `alto_padrao_*`, `comercial_publicacoes`, `lotado_publicacoes`: reserva por categoria de grupo. Só o publicador lê.
- `grupos`: lido por `nai_card_do_imovel` (o card é o mesmo dos grupos, montado sem regra de grupo), `nai_enviar_imoveis_para`, `nai_resposta_da_base` e `nay_qual_imovel`.
- `nai_grupo_corretor` e `identidade_lid`: gravados pela sincronização semanal. É de lá que vem a lista de corretores e o mapeamento LID só com dígitos (ver 32).

**O que não funciona.** O passo 4 de `nay_imovel_da_citacao` ("card visto em grupo, inclusive o que o Tel posta pelo celular dele") lê `grupo_mensagens`, que está vazia. Quando o card foi postado **à mão** pelo Tel, sem passar pelo publicador, a citação não resolve.

### 34. Comandos do Tel pelo WhatsApp

**Premissa.** Não existe um lugar único de comandos. São três gramáticas em três lugares:
- (A) `nai_comando_tel` no banco, via nó "Comando de visita (Tel)";
- (B) o parser do publicador (`interpretar_comando.py`, via `/comando`);
- (C) as pendências (`nay_comando`, via nó "Responder pendencia").

O caminho depende da regex. `nai_e_comando_publicador` pega "vendeu/alugou" antes e manda para o fluxo antigo. Por isso **"ALUGOU 5727" vai ao publicador e "ALUGADO 5727" vai à NAI**, e cada um grava de um jeito (`publicador.py:1778`, `UPDATE imoveis SET disponivel=false`, contra `nai_marcar_imovel` com `imovel_situacao_log`).

**(A) NAI**, de quem tem a "voz do Tel" (…7316 e …6408), salvo onde está marcado "equipe":

| Comando | Exemplo |
|---|---|
| VISITAS | `VISITAS` |
| AGENDA [DE VISITAS] | `agenda de visitas` |
| VISITA n OK | `VISITA 1042 OK` |
| VISITA n CANCELA | `VISITA 1042 CANCELA cliente desistiu` |
| VISITA n REMARCA | `VISITA 1042 REMARCA 30/09 16h` (muda e avisa os três) |
| VISITA n HORARIO | `VISITA 1042 HORARIO 16h` (pergunta ao corretor) |
| VISITA n AVISA | `VISITA 1042 AVISA 10h` |
| VISITA n ANDRÉ OK | `VISITA 1042 ANDRÉ OK` (aceita também FERNANDO ou MOTOBOY) |
| ACESSO | `ACESSO 5611 chave com a gente` |
| ASSUMIR | `ASSUMIR 92 99999-8888` |
| DEVOLVER [resposta] | `DEVOLVER (92) 99999-8888 é apartamento` (a resposta é entregue à pessoa) |
| PARAR / VOLTAR ATENDIMENTO | `PARAR ATENDIMENTO`, `VOLTAR ATENDIMENTO` (também pausar/retomar/volta o atendimento). Muda `nai_config.pausada` |
| CORRETOR / NAO CORRETOR | `NAO CORRETOR (92) 99999-8888` |
| Situação do imóvel | `ALUGADO 5727 e 5733`, `VENDIDO 3210`, `INDISPONIVEL 5721`, `DISPONIVEL 5727` (também aluguei, vendi, libera, voltou). `nai_e_comando_imovel` exige verbo + código de 3 a 5 dígitos |
| Checklist (Tel e equipe) | `checklist aluguel para 92 99999-1234`, `manda o cheklist de venda pra 92…` |
| Aprovação de visita (equipe, só com visita em `aguardando_rayssa`) | `SIM 1042`, `NAO 1042`, `TELEFONE 1042 92 9…` |
| Lembrete (equipe, inclui o Tel) | `me lembra às 15h de ligar pro proprietário`, `meus lembretes`, `cancela lembrete 12` |
| Envio (Pedro, Rayssa, André; **não** o Tel) | `envia 92 99999-1234 o 3050`, `92 99999-1234 manda o 5727 e 5733`. `nai_ler_pedido_de_envio` foi testado com essas frases |

**(B) Publicador**, só dos números do Tel (lista fixa no JS):
- postar: `posta o 5750`;
- agendar na grade: `posta o 5750 às 9h todo dia`;
- `publica no easy 5750`, e os equivalentes de alto padrão, comercial e lotado;
- `VAGAS`;
- `TIRA 5750`;
- `VENDEU 5750`, `ALUGOU 5750` e `5712 alugado`: tira da grade e grava `disponivel=false`;
- taxa: `5712 taxa inclusa` / `5712 sem taxa`;
- envio pelo Tel: `manda o 5727 para 92 99999-1234` e também `envia 92 9999-1234 o 3050`, que para o Tel vai ao publicador pela rota `tel_antigo`;
- listas: `manda a lista de apartamentos de locação para …`;
- escolha: `codigo 5719`;
- `sim` / `não` a uma pergunta aberta (`pergunta_ao_tel`).

**(C) Pendências** (`nay_comando`): `RESPOSTA 81 é apartamento`, `DESCARTA 81`, `DESCARTA TUDO` / `DESCARTA TUDO SIM`, `PENDENCIAS`. Quando a pendência é da secretária, a resposta vira `nai_saber` (ver 39).

**Uso real** (turnos `papel='tel'`, desde 10/09):

| Tipo | Turnos |
|---|---|
| disparo pelo painel (site/CRM, não é WhatsApp) | 35 |
| **não é comando** | 31 |
| VISITA n … | 27 |
| ASSUMIR / DEVOLVER | 26 |
| envia | 15 |
| VISITAS | 10 |
| CORRETOR / NAO CORRETOR | 6 |
| ACESSO | 3 |
| AGENDA | 3 |
| PARAR / VOLTAR | 2 |
| checklist, RESPOSTA, ALUGADO | 1 cada |

**Defeito no CORRETOR / NAO CORRETOR:** o ramo retorna `msg_tel` **sem** `nai_enfileirar_texto`, e o nó do n8n descarta o retorno. A decisão é gravada, mas o Tel não recebe confirmação. Os turnos 10522 (22/09 17:04), 10582, 10585, 10589, 10676 e 10687 têm 0 saídas.

**Quando o Tel escreve algo que não é comando:**
- Ele continua com `papel='tel'` e passa pela porta ("da equipe: sempre atendida"). O roteador manda para `agente`, a mente (Jev) decide, e responde o **agente de corretor**, com o prompt de corretor (`nai_prompt_de('corretor')`) e memória `nai:tel:<contato>`.
- Ou seja: ele é atendido **como um corretor**.
- Exemplos reais:
  - Turno 12606 (29/09 18:20): "ela mandou a comprovação de renda ?". Saíram "Boa noite, Tel! De qual pessoa você está falando?" e, ao próprio Tel, um aviso `foto_inexistente`: "Tel, o corretor Tel Sobreira pediu fotos do 1778…".
  - Turno 12374 (28/09 19:50): "sim". Saiu "Boa noite, Tel! De qual imóvel você quer as fotos?".
  - Turno 12465 (29/09 09:43): um documento sem texto. O Tel recebeu `midia_para_o_tel` sobre ele mesmo ("Tel Sobreira ((92) 99471-7316) me mandou um arquivo…"), e 36 fotos de um imóvel indisponível foram tentadas e barradas.
- Mensagem vazia só com figurinha ou reação não gera nada, porque o roteador devolve `[]`.
- O que o Tel digita **em conversas de outras pessoas**, no celular da Nay, não é comando. É o ramo "Foi o Tel pelo celular?", que pausa a Nay naquela conversa por 30 min (`gap_tel_min`).

---

## BLOCO 7: DADOS

### 35. O catálogo (`imoveis`)

**Premissa.** As views `vw_catalogo_locacao` e `vw_catalogo_venda` **não** medem o que a Nay pode oferecer. São só `WHERE coalesce(valor_aluguel,0) > 0` e `WHERE coalesce(valor_venda,0) > 0`, sem filtro de disponibilidade, e têm 1.307 e 4.607 linhas. O que a Nay oferece é `nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND NOT e_parceiro`, ou seja: `coalesce(disponivel,true) AND NOT coalesce(bloqueado,false) AND coalesce(publicado_no_site,false)`. Na busca, `nai_oferta_serve` ainda exige preço > 0 na finalidade.

**De onde vem.** Há cerca de 5.673 linhas por origem:

| Origem | Linhas | Publicadas | Disponíveis | Nota |
|---|---|---|---|---|
| `planilha_site_antigo_20260926` | 4.399 | 1 | 1 | importação da planilha geral de 26/09 |
| `site` | 1.269 | 833 | 1.131 | raspagem do imobeasy.com |
| `site_antigo` | 2 | | | |
| `secretaria` | 1 | | | |
| `olx` | 1 | | | o 9001, Rascunho, travado |

Não há nenhuma linha com origem `crm`.

**Como sincroniza.**
- Cron no servidor (UTC): `17 9 * * * … sincronizar_catalogo.sh`, ou seja **1x por dia às 05:17 em Manaus**. Os comentários logo acima da linha ainda dizem "DESLIGADO 19/09" e "PAUSADA 27/09", mas a linha está ativa.
- Última passada: `config.varredura_rodou_em = 2026-09-29T05:20:34`, com "0 novos, 1 alterados, 1 despublicados". Até a tarde de 28/09 o log mostra passadas de hora em hora.
- `max(sincronizado_em)` = 29/09 10:25, porque edições manuais também carimbam.
- `sincronizar_catalogo.py` varre 67 páginas de venda e 8 de aluguel, com 12 anúncios cada. Aborta com mais de 3 páginas falhas.
- Só atualiza `condominio_nome, bairro, logradouro, complemento, quartos, suites, banheiros, valor_venda, valor_aluguel, e_parceiro` e `publicado_no_site`. **Nunca** mexe em `disponivel`, `area_util`, `vagas` ou `imovel_privado`.
- Pula `origem IN ('crm','olx','captacao')` e `travado`. Hoje há 3 travados: 1778 (Disponível), 2133 (Indisponível) e 9001.
- Quem sumiu do .com vira `publicado_no_site=false`, e quem voltou é republicado.
- Depois roda `varrer_fotos.py`, `varrer_tipos.py` e `preencher_do_anuncio.py`, este só preenchendo campo vazio.
- A ficha (`imovel_ficha`, 270 linhas, 269 encontradas) foi lida **toda de uma vez em 29/09 18:11–18:19**. O cron `40 */3 * * *` de `ficha_do_anuncio.sh` está no crontab, mas `logs/ficha_do_anuncio.log` e o batimento não existem: NÃO SEI se já rodou pelo cron.

**Quantos a Nay pode oferecer hoje: 259.**

| Finalidade (`nai_finalidade_do_imovel`) | Ofertáveis | No mercado, mas de parceiro |
|---|---|---|
| **Locação** (30 só locação + 7 ambos) | **37** | 53 |
| **Venda** (212 só venda + 7 ambos) | **219** | 515 |
| Sem preço | 10 (só saem por código) | 7 |

No total há 562 imóveis de parceiro "no mercado", e parceiro nunca sai.

**Confiabilidade dos campos** (sobre os 259 ofertáveis):

| Campo | Situação |
|---|---|
| `bairro` | Confiável: 4 vazios e grafia limpa (53 bairros distintos no catálogo inteiro, nenhuma variante que o `nay_normalizar_lugar` junte) |
| `condominio_nome` | Nunca vazio, mas é texto livre com prefixos variando ("Condomínio Laranjeiras" e "Residencial Laranjeiras"; "Conquista Tarumã" e "Condomínio Residencial Conquista Tarumã"). `condo_id` é nulo em 78 |
| `mobilia` | **Fraco**: vazio em 134 dos 259 (52%); na locação, 5 de 30 e 2 de 7. Os valores são texto livre ("semi-mobiliado (moveis planejados + ar)", "so ar-condicionado"…) e `nai_oferta_serve` usa regex sobre `mobilia` e `descricao` |
| fotos | 259 de 259 têm linha em `imovel_fotos` (mediana 12, mínimo 1, máximo 94). 17.749 das 17.886 URLs estão no `imobeasy.com`, o site antigo. `e_fachada` não está marcada em **nenhum** ofertável |
| `e_parceiro` | Vem da varredura do .com e é sobrescrito a cada passada: 909 true no total |
| `status` × `disponivel` | Batem (Disponível ↔ true, o resto ↔ false). A Nay **só lê `disponivel`**. 17 ofertáveis estão com `status` nulo. 313 estão disponíveis e fora do site, invisíveis para ela |
| `taxa_condominio` | Nula em 160 dos 259 |
| dono | Ver 38: na locação, 22 dos 30 sem dono para a Nay |

### 36. Bairros, condomínios, zonas e o filtro de palavras

**Premissa.** Não existe `bairros_por_zona` no banco. É um arquivo do publicador (`/root/nay-publicador/bairros_por_zona.sql`) que criou a tabela `bairro_zona`. Também **não existe dimensão de "padrão"** (alto, médio) em tabela nenhuma. A única menção é a nota do Vieiralves em `bairro_area`.

**Tabelas e quem as lê (varredura em `pg_proc`):**

| Tabela | Linhas | Quem lê |
|---|---|---|
| `bairro_zona(bairro, zona)` | 56 bairros em 6 zonas (centro-oeste 6, centro-sul 9, leste 9, norte 10, oeste 12, sul 10) | `nay_bairros_proximos`, `nai_imovel_pelo_condominio`, `nai_nome_so_do_bairro` |
| `bairro_vizinho` | 24 pares, à mão | `nay_bairros_proximos` |
| `bairro_area` | **1 linha**: Vieiralves → Nossa Senhora das Graças | `nay_normalizar_lugar`, `nai_area_citada`, `nai_imovel_pelo_condominio` |
| `condominios(id, nome, bairro)` | 464 | só `nay_disponibilidade_no_condominio` |
| `condominio_taxas` | 0 | ninguém |
| `geo_bairro` (59), `geo_bairro_vizinho` (576, com divisa e km), `geo_bairro_nome` (45), `imovel_geo` (3.684: 1.985 por rua, 1.159 por condomínio, 540 por bairro), `imovel_bairro_ao_redor` (25.612) | | **nenhuma função `nai_`/`nay_`**. Só servem à aba Mapa |
| `vw_condominio_som` | 143 | `nai_imovel_pelo_condominio`, `nai_imoveis_pedidos` |
| `mv_vocabulario_nomes` | 183 (40 bairros + 143 condomínios) | `nai_corrigir_nomes` |
| `nai_palavra_conhecida` | 1.969 (1.381 com ≥ 5 mensagens) | `nai_corrigir_nomes` |

`vw_condominio_som` é a chave fonética `nai_chave_som` sobre `nai_condominio_nucleo`, só dos ofertáveis. Em `condominios`, `condo_id` está preenchido em 1.086 imóveis.

"Perto", em `nay_bairros_proximos`, é **a zona inteira mais os vizinhos**. Para Ponta Negra dá 12 bairros, entre eles Compensa, São Raimundo e Glória. [OPINIÃO: sem padrão nem distância, "perto" mistura públicos muito diferentes, embora as tabelas geo com km já existam.]

**Como um nome errado vira o certo: `nai_corrigir_nomes`.**
- Roda dentro de `nai_abrir_turno` para todos, menos quem `nai_pode_comandar`.
- Janelas de 3, 2 e 1 palavras, distância de Levenshtein contra `mv_vocabulario_nomes`, piso `greatest(nai_config.piso_correcao_nome, 0.80)`.
- Não troca: palavra de `nai_palavra_comum` (lista fixa), palavra com 5 ou mais mensagens em `nai_palavra_conhecida`, janela que começa ou termina em conectivo. Em janela de várias palavras, uma palavra conhecida só troca com diferença de 1 letra.
- **O vocabulário sai só dos ofertáveis:** bairros de imóveis no mercado e núcleos de condomínio de ofertáveis não parceiros. Condomínio sem imóvel ofertável não é corrigido.

**Como é atualizado.**
- `mv_vocabulario_nomes`: automático, cron `17 4 * * *` UTC (00:17 Manaus) → `SELECT nai_vocabulario_atualizar()` (REFRESH).
- `nai_palavra_conhecida`: **à mão**, por `nai_atualizar_palavras_conhecidas()`. Última vez em 29/09 17:42, sem cron. Detalhe: essa função guarda palavras com 3 ou mais mensagens, mas o filtro só respeita as de 5 ou mais.
- `nai_giria`: à mão (9 linhas, Tel em 22 e 23/09).
- `bairro_area` e `bairro_vizinho`: à mão.

**Onde o texto corrigido chega.**
- Grava em `nai_turno.texto` e em `cab.texto`, e alimenta a porta, `cab.contexto` (que lê `nai_turno.texto`), a fila e as funções que leem o turno.
- O **modelo** recebe no nó "NAI (corretor)" o texto **cru**: `mensagem do corretor: {{ $('Juntar mensagens').first().json.texto }}`, mais o contexto montado a partir do texto corrigido.

**Onde erra (casos reais).**
- A versão anterior à 190 estava no ar até pelo menos o turno 12600 (29/09 17:35). Nos últimos 14 dias alterou **48 de 1.615** turnos de corretor só de texto.
- Numa amostra de 20 que li, houve **11 erros**:

| Turno | Original | Virou |
|---|---|---|
| 12600 | cômodo | Coroado (e juntou as linhas) |
| 12517 | passando | passaredo |
| 12484 e 12428 | ponta negra | ponta negra ii (bairro virou condomínio) |
| 12051 | Parque dos Franceses | parque dos ingleses |
| 12042 | parte central | parte Centro |
| 12269 e 12219 | dentro | Centro |
| 12304 e 12297 | região | reserva |
| 12575 | um sobrenome dentro de uma ficha com CPF | outro nome (estragou dado pessoal) |

- Houve 8 acertos: "Jardins das cerejeiras" → jardim das cerejeiras, "Living Concert" → living comfort, "D Pedro II" → Dom Pedro II, "AQUARELLE" → acquarelle, "Copenhagen" → kopenhagen, "D. Pedro" → Dom Pedro, "Pq das laranjeiras" → Parque das Laranjeiras, "amamzon flat" → amazonas flat. E 1 meio certo: "Acquarelli Ponta Negra" → "acquarelle ponta negra ii".
- Reprocessei os 12 originais com a versão viva de agora. Todos os erros deixaram de acontecer. Deixaram de funcionar também "D Pedro II" e "amamzon". Continua funcionando "Acquarelli" → "acquarelle".
- Testes de leitura na versão viva: "aquarelli", "ponta negrra", "adrianopoles", "bom pedro" e "living confort" foram corrigidos. **Não** corrige "vieralves": só a forma exata "vieiralves" vira N. Sra. das Graças, via `bairro_area`. Também não corrige "alfaville", "PN" nem "acqua".

### 37. Cadastro de apelidos

**Não existe tabela de apelidos.** A busca por `relname ~ 'apelido|sinonimo|giria|vocab'` só acha:
- `nai_giria`, que tem expressões ("tá valendo", "joga aí"), não lugares;
- `grupos.apelido`, apelido de grupo do publicador;
- o vocabulário automático do item 36.

**Como os casos são tratados hoje:**
- `bairro_area`, com **1 linha** (Vieiralves).
- Regex fixa em `nay_normalizar_lugar`: `pq|pque → parque`, `dez → 10`, `quatorze|catorze → 14`, `sto/sta → santo/santa`, `cj|conj → conjunto`, `jd → jardim`.
- A correção por distância (`nai_corrigir_nomes`) e a chave fonética de condomínio (`vw_condominio_som`). No teste, "tem no acquarele?" deu {293, 1125, 2539}, todos do Condomínio Acquarelle.
- O que sobra fica com o modelo.

**"PN":** nada no banco trata. `nai_corrigir_nomes` ignora palavra com menos de 5 letras, `nay_normalizar_lugar('PN') = 'pn'`, `nay_bairro_parecido` devolve NULL e `nai_imovel_pelo_condominio('tem algo no PN')` devolve `{}`. Depende do GPT entender e passar "Ponta Negra" à ferramenta. O prompt de corretor (`nai_prompt`) não menciona "PN".

**Premissa errada: "Acqua" não é Acquarelle.**
- **Acqua** é outro condomínio: `condominios.id = 96`, bairro Parque 10 de Novembro, 49 imóveis, **0 ofertáveis**.
- **Condomínio Acquarelle** fica na Ponta Negra, com 74 imóveis e 3 ofertáveis.
- Há também "Residencial Piazza Dell'Acqua" (5 imóveis, 1 ofertável) e "Lacqua Residenza".
- "fotos do acqua" não casa nada (`nai_imovel_pelo_condominio` = `{}`) e `nay_condominios_candidatos('acqua')` devolve `(Acqua, 0)`.
- [OPINIÃO: um apelido "Acqua = Acquarelle" cadastrado à mão estaria errado para parte dos corretores. É exatamente o tipo de alias que precisa de desambiguação, não de tabela fixa.]

### 38. Proprietários

**Premissa.** "Casa por nome" não é verdade hoje, e nem na versão do repositório de `nai_proprietario_do_imovel` (`Arquivos/nai/02_auxiliares.sql`, idêntica à viva nesse ponto). O vínculo é **por id**, em dois passos:
1. `imovel_privado.proprietario_id` → `proprietarios`;
2. se faltar, `proprietarios_admin_imoveis.codigo` → `proprietarios_admin`, e só se o imóvel tiver um dono.

A frase "1.163 dos 1.250 sem dono, casa por nome" está em `COMO-A-NAY-FUNCIONA.md` §5, item 1 (commit 84890cd, 24/09). Não consigo reproduzir essa medida. A cópia mais antiga de `imovel_privado` é `privado.imovel_privado_antes_158` (28/09), que já tinha 1.172 donos. NÃO SEI de onde saiu o 1.163 nem se `imovel_privado` foi preenchido entre 24 e 28/09: não há carimbo de data nessa tabela.

**Tabelas e contagens.**

| Tabela | Linhas | Com telefone |
|---|---|---|
| `proprietarios(id, nome, telefone, email, tratamento, documento)` | **5.658** (ids 1–5.661, todos do admin antigo; 0 na faixa 900001+ do site novo) | 5.253; 5.232 legíveis pela regex da função |
| `proprietarios_admin` | 873 | 844 |
| `proprietarios_admin_imoveis` | 925 (922 códigos existem em `imoveis`) | |
| `proprietarios_export`, base da `vw_proprietarios_site` | 4.220 | 3.959 |

**Os dois vínculos (a armadilha).**
- `imoveis.proprietario_id` está preenchido em **5.647 de 5.673**. É o que o site e o CRM leem.
- `imovel_privado.proprietario_id` está preenchido em **1.172** das 1.978 linhas. **É só este que a Nay lê.**
- Onde os dois existem, batem (1.172 de 1.172).

**Resultado de `nai_proprietario_do_imovel` hoje.**
- Catálogo de origem `site` (1.269): 1.122 com telefone, 84 `sem_cadastro`, 61 `sem_telefone`, 2 `tratar_com_outra_pessoa`.
- Nos 259 ofertáveis: 188 ok, **59 `sem_cadastro`**, 11 `sem_telefone`, 1 `tratar_com_outra`.
- **Locação: 22 dos 30 ofertáveis só de locação estão `sem_cadastro`.** Desses, 21 têm dono em `imoveis.proprietario_id` com telefone válido. São justamente os novos e mais divulgados: 964, 2014, 3050, 5713, 5717, 5718, 5721, 5722, 5724, 5725, 5727, 5728, 5729, 5731, 5733, 5739, 5743, 5746, 5749, 5752, 5757 (e o 5763, sem dono em lugar nenhum).
- Na venda, 21 dos 27 sem cadastro também têm dono em `imoveis.proprietario_id`.

**Efeito.** `nai_pedir_ao_proprietario` grava `nai_visita_evento 'proprietario_sem_contato'`, avisa o Tel e para o chat do corretor (`nai_parar_chat`). Há 16 eventos `sem_cadastro`: o último na visita 1042 (3050, 28/09 09:35); antes nas visitas 1040 e 1035 (5724), 1039 (5734), 1038 e 1031 (5727), 1034 (5739), 1033 (5722), 1032 (5720)…

**O que mudou desde 24/09.**
- A 162 (28/09) criou o cadastro de dono no site novo, gravando nos **dois** lugares. A memória registra isso como regra, e o `_gravar_proprietario` fica em `nay-site-api/app.py`.
- A 160 aplicou respostas da captação em situação, não em dono.
- Nenhuma migração copiou `imoveis.proprietario_id` para `imovel_privado`.
- [OPINIÃO: para a locação, a situação piorou em relevância. Os imóveis novos têm dono no banco, mas no campo que a Nay não lê.]

### 39. `nai_saber` (o que a secretária aprendeu)

**Estrutura e conteúdo.**
- Colunas: `id, assunto, pergunta, resposta, ensinado_por, pendencia_id, vezes_usada, ativo, criado_em`. Não há coluna de código: **o saber não é por imóvel**.
- **8 entradas**, todas `ativo`, todas `ensinado_por='tel'`, criadas entre 23/09 09:48 e 24/09 08:14. Nenhuma depois disso. `vezes_usada` soma 7.
- Nascem de `nay_responder_pendencia`: quando a pendência é `de_quem='secretaria'`, o `RESPOSTA n <texto>` do Tel chama `nai_saber_guardar(o_que_falta, resposta)`. A "pergunta" guardada é o texto que o **modelo** passou a `perguntar_ao_tel`.
- Por isso as entradas 1, 2 e 3 têm como pergunta "A Sra. Geina enviou um áudio sem texto junto." e como respostas "tenho na ponta negra para locação", "mas é 4.000 mas vale 8.000" e "mas preciso de reforma a casa".

**Como casa.**
- A ferramenta `consultar_o_que_sei` chama `nai_sec_consultar(turno, $fromAI('pergunta'))`, que chama `nai_saber_busca`.
- `similarity(lower(unaccent(s.pergunta)), lower(unaccent(p_texto))) >= 0.35` (pg_trgm), pega o melhor e só ele (`LIMIT 1`).
- **O limiar é fixo no código.** Não há chave em `nai_config`. É igual ao repositório (`99_mente_mestra_e_secretaria.sql`).
- O argumento é a paráfrase do modelo, não o texto do corretor.
- Ao casar, incrementa `vezes_usada`, anota `nai_conferencia` etapa `secretaria_sabia` e devolve a resposta com a instrução "isto é o que o Tel já te ensinou… responda com esta informação". Não mostra a nota de semelhança nem confere nada.

**Quando casa errado.** Caso real, turnos 10862 (24/09 13:52), 11000 e 11008 (25/09):
- O dono de imóvel escreveu "Tenho vivenda verde p locação… 8mil incluso condomínio".
- Casou o saber 7 ("Vc é da Imobeasy?" → "sou secretaria da imob easy").
- A resposta saiu "Sou secretária da Imob Easy, Sra. …".
- NÃO SEI o texto exato que o modelo passou como pergunta; ele não é gravado.

Testes de leitura hoje:

| Pergunta testada | Casou com | Semelhança |
|---|---|---|
| "O Sr. João enviou um áudio sem texto junto." | saber 1, "tenho na ponta negra para locação" | 0,67 |
| "esse aqui amiga?" | saber 6, "vou confirmar o andar com o proprietário" | 0,73 |
| "Como funciona pra você vender?" | saber 8, "nossa parceria é 50% para cada lado" | 0,64 |

Não há desfazer, a não ser `ativo=false` à mão.

**Uso real.** 5 acertos registrados em `nai_conferencia`. A secretária atendeu 43 turnos em 23/09, 32 em 24/09, 21 em 25/09, **0 de 26 a 28/09** e 3 em 29/09. A última `secretaria_perguntou` foi em 25/09 07:48. Pendências da secretária: 11 abertas, 8 respondidas, 14 descartadas. NÃO SEI por que a mente parou de escolher a secretária a partir de 26/09: teria de ler `nai_jev` e `nai_mente_registrar` desses dias.

### 40. Memória do modelo (`memoryPostgresChat`)

**Os nós:**

| Nó | Tabela | `contextWindowLength` | `sessionKey` |
|---|---|---|---|
| "Memória (corretor)" | `nai_memoria` | 20 | `cab.memoria` |
| "Memória (proprietário)" | `nai_memoria` | 40 | `cab.memoria` |
| "Memória (Fernando)" | `nai_memoria` | 40 | `cab.memoria` |
| "Memória (secretária)" | `nai_memoria` | 20 | `cab.memoria + '-sec'` |
| fluxo antigo, "Postgres Chat Memory" | `nay_memoria` | 40 | telefone |

- `cab.memoria` é montado em `nai_abrir_turno`: `'nai:' || papel || ':' || contato_id || ':v' || visita`. A sessão é **por linha de `nai_contato`**, não por pessoa (ver 32), e separa papel e visita.
- **Quanto carrega.** O nó é typeVersion 1.4, e no n8n 2.33.7 isso usa `BufferWindowMemory({k})`. O código em `@langchain/classic/.../buffer_window_memory.cjs` faz `messages.slice(-this.k * 2)`. Então 20 significa **as últimas 40 mensagens da sessão**, contando mensagens `human`, `ai` e `tool`. Em quantidade de trocas pode ser menos de 20.
- **Premissa:** os documentos antigos falam em "janela de 15" (`REGRAS-E-BUGS.md` #19 e #24). Hoje a janela é 20 (40 mensagens) no corretor e 40 (80) no proprietário e no Fernando.

**A tabela hoje.**

| Medida | Valor |
|---|---|
| `nai_memoria` | 9.170 linhas, 788 sessões, 6,6 MB, sem coluna de data |
| Sessões vivas (prefixo `nai:`) | 137, com 1.830 linhas |
| Maior sessão viva | `nai:corretor:9221`, 76 linhas |
| Distribuição das vivas | média 13,4, p90 28; 3 sessões de corretor passam de 40 |
| Mais antiga viva | `nai:corretor:1`, desde 10/09 |
| Arquivadas (`arquivo-…`, `arq-r…`, teste e treino) | 651 sessões, 7.340 linhas |
| Por tipo | 4.546 `human`, 3.520 `ai`, 1.104 `tool` |
| `nay_memoria` (antiga) | 2.866 linhas, 134 sessões |

**Poda: não há.**
- Nenhum cron.
- Nenhuma função apaga, exceto `nai_treino_semear_memoria`, que faz DELETE da sessão de treino antes de semear.
- `nai_zerar_conversa` **arquiva renomeando** (`'arquivo-<data>:' || session_id`), mas o LIKE `'nai:%:'||id` não pega as sessões `…-sec` da secretária, que não são zeradas.
- O n8n lê a sessão inteira do banco e fatia na hora.

**O que entra na memória: o envelope.**
- A mensagem `human` gravada é o `text` inteiro do nó "NAI (corretor)": a hora, o vocativo, as instruções sobre fotos, **o `cab.contexto` do turno** (etapa, visita, códigos) e só então "mensagem do corretor: …".
- Nas sessões vivas de corretor: 439 de 439 mensagens `human` têm "informação de sistema", com média de **1.297 caracteres**, e 329 trazem código ou etapa.
- O nó "Ler estado" (`nai_estado_v2`, que **só existe no banco**, sem `.sql` no repositório) diz no comentário que "substitui o envelope de texto que hoje polui a nai_memoria". Na prática ele só alimenta o **Jev** ("Montar pergunta ao Jev"). O agente continua recebendo e gravando o envelope.
- Enquanto a sessão tem menos de 6 linhas, `nai_contexto_corretor` injeta as últimas 10 falas da `nay_memoria` antiga.

**Erros causados pela memória (registrados):**
1. Nay antiga, janela de 15. O corretor marcou o card do 4946 e o modelo chamou `escalar_ao_tel(codigo "5717")`, o imóvel da conversa anterior na memória (`/root/nay-publicador/HISTORICO-APRENDIZADO.md`, perto da linha 1016, sem data no trecho). Saída adotada: todo parâmetro que diz de qual imóvel se fala é conferido fora do modelo.
2. NAI, 12/09 (`REGRAS-E-BUGS.md` #19). O modelo repetiu da `nai_memoria` frases literais de ferramenta ("Não encontrei aqui. Pode confirmar o código?", 3 vezes, sobre o 5718, disponível; "Esse horário já passou") sem chamar ferramenta. Saída: travas `visita_sem_ferramenta` e `negou_imovel_que_existe`.
3. 13/09 (#24). A memória do número de teste, cheia de respostas erradas, "ensinava a errar". Saída: arquivar sessões renomeando.

**O que segura hoje, e ainda dispara:**
- `nai_enfileirar_resposta_ferramentas`, etapa 21 `saida_sem_consulta`: código citado na resposta sem ferramenta de imóvel é cortado. Foram 373 em 10 dias, mas 353 são um código "0" espúrio; **20 são códigos reais**.
  - Turno 12461 (29/09 09:34): "Eles precisam com 2 vagas, vc tem alguma opção?". Saiu o 5739, citado sem consulta, e foi cortado.
  - Turno 12095 (28/09 08:00): "vamos fazer parceria". O 2014 foi cortado.
  - Turno 12334 (28/09 18:02): o 5749 foi cortado.
  - [OPINIÃO: vêm da memória ou do contexto, não do que o corretor disse.]
- `nai_conferir_resposta`, etapa 1 `imovel_da_conversa`: o banco decide o imóvel pelo turno e pelo `nai_imovel_da_conversa` (421 em 10 dias).
- `resposta_sem_consulta`: 26 subiram ao Tel.

NÃO SEI quantas respostas de hoje usaram código antigo **sem** serem pegas. Para saber, teria de cruzar os códigos em `nai_saida.texto` de cada turno com os de `nai_turno.codigo` e `nay_codigos_citados(texto)` do mesmo turno.

---

## Bloco 8 — Erros

Fontes usadas neste bloco: banco `naydb` em modo só leitura (horários do psql já em Manaus), sqlite do n8n (horários do sqlite estão em **UTC**; converti para Manaus, −4 h, sempre que cito), o repositório local `Nay IA` (em dia com `origin/main`, commit 4695088 de 29/09), o repositório do publicador no servidor (`/root/nay-publicador`, outro git, remoto `Telsobreira/nay-publicador`) e a memória das sessões, usada só como pista e conferida no banco. Telefones com os 4 últimos dígitos, pessoas só com o primeiro nome.

Duas premissas valem para o bloco todo:

- **O n8n não guarda 30 dias.** O contêiner roda com `EXECUTIONS_DATA_PRUNE_MAX_COUNT=2000` e `EXECUTIONS_DATA_MAX_AGE=72`. Em 29/09 o histórico de execuções terminadas começava às 13:57 de Manaus. Por isso os números de 30 dias saem do banco (`nai_turno`, `nai_conferencia`, `nai_saida`, `mensagens`). O n8n só serve para o dia de hoje e para as execuções que nunca terminaram.
- **O rastreio não existe.** `nai_evento` tem 1 linha (a instalação de 19/09). Em `nai_turno`, as colunas `exec_id`, `modelo`, `ms_total` e `prompt_versao` estão vazias nos 3.437 turnos, e `vw_nai_execucoes.primeiro_erro` é NULL em todos. Não dá para ligar um turno à execução do n8n nem saber o que a ferramenta devolveu ao modelo. O que um turno "fez" se reconstrói com `nai_turno.ferramentas`, as linhas de `nai_conferencia` e as linhas de `nai_saida`.

---

### 41. As três reclamações do Tel: imóvel errado, dado errado, regra ignorada

**Premissa.** A pergunta supõe que os três erros vêm do modelo. Nos casos que eu medi nos últimos 30 dias, os dois primeiros vêm quase sempre da **camada determinística que roda depois do modelo**: `nai_conferir_resposta`, `nai_fila_dos_outros_imoveis` e a parede `nai_conferir_imoveis_da_saida`, alimentadas por funções de casamento de palavra e número (`nai_imovel_pelo_condominio`, `nai_imoveis_pedidos`, `nay_codigos_citados`, `nai_corrigir_nomes`). Essa camada escolhe o imóvel, acrescenta card e fotos e às vezes **troca o texto do modelo** pela ficha. O terceiro erro vem de regra que mora num caminho que não passa pelo modelo (frase pronta, fila, portão de fotos), ou de duas regras de código que competem entre si.

Um dado de contexto: a bateria `nai_caso` tem **60 casos**, 43 de 24/09 e 17 de 29/09 (coluna `quando`), e não 15. Ela testa funções, não o modelo. Hoje passa 60/60 em `nai_rodar_casos()`. Pelo campo `pergunta`, 38 dos 60 casos são leitura de texto por regex ou similaridade (tipo 9, nomes 5, imóveis 4, tipo_conversa 3, anúncio 3, negocio_valor 3, passe 3, negócio 2, negocio_conversa 2, pelo_nome 1, tipo_canon 1, sem_bairro 1, pede_lista 1), 12 são roteamento (catálogo 6, cortesia 2, oferta 2, de_imovel 1, link 1) e 9 são dado de pagamento (afirma_pagamento 5, assunto_sensivel 4). É o retrato dos erros que o Tel apontou.

**41a. Imóvel errado enviado.**

*Causa mais frequente:* o imóvel é escolhido pelo código, não pelo modelo, a partir de palavra ou número da mensagem (bairro lido como condomínio, número lido como código). Depois, o portão de fotos (`nai_deve_mandar_fotos`, que devolve `true` para quase tudo, regra do Tel de 16/09) manda card e fotos junto.

*Medida (FATO):* nos 30 dias, 69 turnos reais de corretor mandaram foto (`nai_saida` tipo imagem, estado enviado, papel `turno`). Em 63 deles o portão acrescentou as fotos (`nai_conferencia` etapa `portao_de_fotos` = `mudou`). Em 60, o imóvel foi fixado pela conferência (`imovel_da_conversa` = `mudou`). Em 11, o modelo não chamou nenhuma ferramenta de imóvel: o imóvel e as fotos foram escolhidos só pelo código. Desses 11, pelo menos 5 foram imóveis ou fotos que ninguém pediu:

- 10770 (24/09): o corretor ofereceu o imóvel dele e recebeu o Smart Vista do Sol 4778, de venda, com 15 fotos;
- 12119, 12299 e 12372 (28/09): conversa de agendamento de visita, com 18, 14 e 10 fotos;
- 12557 (29/09): "Ele está a caminho, já vai chegar", com 6 fotos do 5754.

As paredes pegaram outras tentativas antes da saída, em turnos reais: `conferencia_da_saida` retirou linhas em 12 turnos, `nai_saida.bloqueio` "tipo errado" em 8 turnos e "ele procura locação/venda" em 4.

*Exemplo real: turno 12592, 29/09 17:13, corretor …8050.*

- **Entrou:** "Grato Vou encaminhar Tem Vieira Alves e Adrianópolis 3 quartos ?".
- **O modelo:** chamou `buscar_por_perfil`, o caminho certo.
- **A conferência:** gravou `imovel_da_conversa` "imóvel 5748", porque a similaridade leu "Adrianópolis" como o condomínio Jardim Adrianópolis. Depois, `formato_da_base` "resposta da ficha, no formato dele", `portao_de_fotos` "ele pediu foto; imóveis: 5748", e 24 vezes `passe_do_citado` "ele apontou o 5748 pelo nome". A parede deu passe porque achou que ele tinha citado o imóvel.
- **Saiu** (tudo enviado): "Sim! Tem 4 quartos, sendo 4 suítes. Tem 6 banheiros. Tem 3 vagas cobertas. Tem 170 m²." e 24 fotos do 5748, que é de venda (`nai_finalidade_do_imovel(5748)` = 'venda', R$ 2 mi). A conversa era de locação desde a manhã.
- **Por quê:** o texto do modelo foi substituído pelo da ficha de um imóvel que o código inferiu. Consertado na 190 (29/09), que proíbe trocar a resposta da busca pela ficha e põe a parede de finalidade em `nai_saida_validar`.

*Segundo exemplo, do mesmo tipo:* turno 12205, 28/09 11:19, Taysa …1312. Entrou "Tem algo de 3 dormitórios Parque das Laranjeiras ou pq dez". A porta (`nai_turno.porta`) marcou "citou um imovel nosso pelo nome". A ferramenta devolveu a pergunta certa, "Seu cliente procura imóvel para alugar ou para comprar?". Mas `fila_de_imoveis` (etapa 22) registrou "ele pediu 2 imóveis; 2 foram para a fila", e no mesmo turno saíram o card de venda do Residencial Laranjeiras 1351 (R$ 2.000.000) e 28 fotos. O 2155 só não saiu porque o Tel assumiu às 11:22 (bloqueio `tel_assumiu`).

**41b. Dado errado sobre imóvel.**

*Causa mais frequente:* a mesma camada. `nai_conferir_resposta` (etapas 4 `resposta_sem_consulta` e 5 `formato_da_base`, usando `nai_resposta_da_base`) troca o texto do modelo pela resposta pronta da ficha do "imóvel da conversa". Quando o imóvel foi inferido errado, o dado sai errado e responde a uma pergunta que ninguém fez.

*Medida (FATO):* em 30 dias houve 11 turnos reais com o texto trocado pela ficha (`formato_da_base` ou `resposta_sem_consulta` = `mudou`). Li os 11. Pelo menos 5 são respostas erradas:

- 10711: pediu Planalto/Lírio do Vale até 2.200 e recebeu "É semi-mobiliado… Tem 2 quartos" do 5733;
- 10846: mensagem de logística de visita virou "Fica no Casa, na Rua Coronel Teixeira…";
- 12186 (abaixo);
- 12447: pediu "opções mobiliadas até R$ 2.800" e recebeu "Sim! É mobiliado…" do 5724;
- 12592.

Em 10711, 12447 e 12592 o modelo tinha chamado `buscar_por_perfil`.

A segunda causa é **dado que não existe no banco**, e aí o modelo supõe. Aconteceu com o 5664 em 29/09, nos turnos 12565 e 12568 (Paulo, …4045). O corretor colou o card do grupo, que dizia "aceita financiamento". O modelo, com `imovel_por_codigo` chamado, escreveu "Já o Living Comfort 5664 é somente à vista" e, no turno seguinte, "é somente à vista mesmo". O card do banco (`nai_card_do_banco`) não trazia forma de pagamento: `imoveis` vem da listagem do site, e o `extras` só existe para os imóveis importados. Nos 30 dias, só esses 2 textos enviados afirmam forma de pagamento sem estar num card. Consertado na 191 (`imovel_ficha` e a etapa 05p `nai_conferir_pagamento`).

Há uma terceira fonte, rara mas grave: `nai_corrigir_nomes` reescreve o texto antes do modelo. O turno 12600, de 29/09 17:35, está gravado em `nai_turno.texto` como "precisa de mais um **Coroado** P escritório"; a mensagem original dizia "cômodo".

*Exemplo real: turno 12186, 28/09 10:46, Stela …0860.*

- **Entrou:** um áudio transcrito sobre o Park Golf, com o trecho "tava por 300 sem, mas tava impecável…".
- **O modelo:** não chamou nenhuma ferramenta (`ferramentas` = {_lidas}).
- **A conferência:** `imovel_da_conversa` fixou "imóvel 300" (o número da fala virou código). `resposta_sem_consulta` "trocada pela resposta da ficha". `foto_que_nao_existe` avisou o Tel: "pediu fotos do 300 e não achei foto". `fila_de_imoveis` pôs o 5728.
- **Saiu:** "Sim! Tem 11 banheiros. O aluguel é R$ 38.000. Tem 750 m²." e "O 5728 eu já mandei ontem às 18h20…". Nada disso tinha sido perguntado.
- **Por quê:** número lido como código, e depois a resposta pronta da ficha no lugar do texto do modelo.

**41c. Regra ignorada.**

*Causa mais frequente:* a regra está no prompt ou numa camada, e a saída foi produzida por **outro caminho** que não a consulta. Pode ser frase pronta de função (`texto_pronto`), a fila de imóveis, ou o portão de fotos, que implementa a regra concorrente "fotos sempre". Violação do próprio modelo, contada pelas paredes em turnos reais, é rara (números na 42).

Os casos do Tel na janela, com a causa medida:

| Data | Reclamação | Causa medida |
|---|---|---|
| 27/09 | 3210 recebido 3× (…1119, `envios` 16:31–16:39) | infraestrutura (ver 44) |
| 28/09 | "perguntou aluguel ou venda mas não esperou" (12205) | fila etapa 22, a trava de rajada com furo e o bairro lido como condomínio |
| 28/09 | "nunca pode falar parceria" (12301) | frase pronta de `nay_disponibilidade_no_condominio` |
| 29/09 | "listou sem filtro" | regra 146 de código ("lista com qualquer filtro") contra o filtro completo |
| 29/09 | "conversava com o acompanhante" | papel motoboy com agente próprio; consertado na 186 |
| 23/09 a 29/09 | fotos em conversa de visita, 5 turnos (lista em 41a) | o prompt diz "AGENDAMENTO DE VISITA: cuide só da visita (etapa 5), sem card e sem fotos", e o portão (`nai_deve_mandar_fotos`, "Fora isso: SEMPRE (Tel, 16/09)") manda mesmo assim |

*Exemplo real: turno 12301, 28/09 15:30, Adriana …3366.* Entrou "Ibiza". O modelo chamou `disponibilidade_no_condominio`, e saiu, enviado: "No Ibiza Flex o que eu tenho é imóvel de parceria, não da Imob Easy." Isso fere a regra do Tel de nunca falar de parceria. O texto era `texto_pronto` da função com a instrução "diga isso e pare"; o modelo obedeceu à ferramenta. A mesma frase saiu em 6130 (16/09), 9620 (18/09) e 9977 (19/09). Consertado na 153.

---

### 42. Quais regras o modelo mais ignora, e por quê

**Premissa.** A view `vw_nai_regras_ignoradas` não mede isso bem, por três motivos (FATO, `pg_get_viewdef`):

1. Só cruza as 17 etapas de `nai_regra`. As etapas que mais agem ficam fora: `saida_sem_consulta` (373), `mente_mestra` (897), `fila_de_imoveis` (69), `conferencia_da_saida` (35), `espera_as_fotos` (106), `passe_do_citado` (750 linhas) e `mostra_sem_peneirar` (42).
2. Não filtra `nai_turno.teste`. Metade dos turnos de 30 dias é treino: 1.135 de 3.437.
3. Conta como "ignorou" as etapas de fluxo, que não são violação: `imovel_da_conversa` 44,3%, `portao_de_fotos` 26%, `silencio` 16,1%. `silencio parou` é o modelo **obedecendo**: respondeu SILENCIO.

Refiz a conta em `nai_conferencia`, só com turnos reais, de 30/08 a 29/09. Passaram pela conferência da resposta cerca de 435 turnos reais (`fotos_do_site` = 435).

| Parede que confere o texto ou a saída do modelo | Turnos reais que ela pegou | Observação |
|---|---|---|
| `saida_sem_consulta` (cita imóvel sem ferramenta de imóvel) | 135, mas só **7** reais | 353 das 373 linhas (todas as datas) são o código "0": o nó "Achar codigo na resposta" devolve `codigos: ['0']` quando não acha código, e a parede em `nai_enfileirar_resposta_ferramentas` conta esse "0" como código cortado. Falso positivo estrutural |
| `foto_que_nao_existe` | 24 | não é o modelo: dispara quando o portão escolheu imóvel sem foto (ex.: o "300" do 12186) |
| `formato_da_base` / `resposta_sem_consulta` `mudou` | 10 + 1 | troca do texto pela ficha (41b) |
| `promessa_ou_sem_resposta` | 4 | "vou ver e te aviso" |
| `uma_pergunta_por_mensagem` | 4 | todas em 28/09, e o texto era da ferramenta de busca |
| `texto_orfao` | 2 | texto que prometia fotos e card que a parede tirou |
| `resposta_sem_consulta` `parou` | 1 | 22 dos 23 casos são de treino |
| `citou_o_tel`, `visita_sem_ferramenta` | 0 | os 3 casos são de treino |

**Leitura [OPINIÃO], apoiada nos fatos acima.** O modelo raramente fere a regra que está escrita no prompt e que a parede consegue conferir. O que o Tel vê como "regra ignorada" se distribui assim, da mais frequente para a menos:

1. **A regra compete com outra, e as duas estão no código.**
   - O portão "fotos sempre" (`nai_deve_mandar_fotos`) contra o prompt "agendamento de visita sem card e sem fotos": 5 turnos com fotos em conversa de visita.
   - `nai_liberar_saida` ainda tem "foto que ELE pediu de novo sai de novo (Tel, 22/09)", e a parede de 24 h em `nai_saida_validar` (131/132) diz o contrário. Hoje vence a parede.
   - A regra 146 ("com qualquer filtro a ferramenta já lista", que ainda está no prompt v16: "Com qualquer filtro que ele der… a ferramenta já lista o que temos") contra o filtro completo da 190.
   - O próprio prompt manda responder "Sim, aceitamos parceria em todos os nossos imóveis" (parceria com corretor), e a 153 proíbe a palavra "parceria" (imóvel de parceiro). A conferência marcou `parceria` `mudou` nos turnos 12095 e 12104, em 28/09.
2. **A saída não passa pelo modelo.** O prompt manda "Mande o texto_pronto exatamente como veio" e "Siga a instrucao_para_voce". Então a frase pronta de uma função fere a regra sem o modelo decidir nada: o caso da parceria, com 4 turnos, ou 12347/12348 (28/09), em que "Essa casa ainda está disponível?" recebeu a pergunta do filtro "você está procurando imóveis em qual bairro?". A fila e o portão, por sua vez, acrescentam imóvel depois do modelo.
3. **O modelo não tem a informação.** O caso do 5664: o prompt não fala de pagamento, a ferramenta não trazia o dado, e o modelo completou sozinho, contrariando até o card que o corretor tinha colado. A 191 passa a entregar a ficha inteira em `o_que_sei_do_imovel` e faz de pagamento um "assunto sensível".
4. **A ferramenta devolve errado.** `nai_resposta_da_base` responde de forma genérica ("Sim! Tem N banheiros…") sem olhar a pergunta (12186, 12592). E, antes da 153, `nay_disponibilidade_no_condominio` devolvia a frase de parceria.

A ambiguidade pura do prompt é a causa menos visível. O prompt corretor v16 (10.294 caracteres, `nai_prompt`, 28/09 11:09) é afirmativo e delega muita coisa: "O sistema cuida do que vem depois de você: manda as fotos atrás do card, a pergunta atrás da lista e a sugestão de visita atrás da resposta". É essa delegação que tira do modelo as decisões em que acontecem os erros de 41a e 41b.

Um dado relacionado: o modelo escala muito. Em 30 dias, `escalar_ao_tel` aparece em 79 turnos reais e `escalar` em 101, contra cerca de 428 turnos com `_lidas`.

---

### 43. Quando o n8n falha no meio do turno

**Premissa.** As "274 execuções new" da NAI e as 267 do fluxo antigo **não são esperas em andamento**. Estão com `status='new'`, `startedAt` NULL e `waitTill` NULL, e **nunca começaram**. Foram criadas em três janelas principais (UTC convertido para Manaus): 25/09 11:19–11:22, 25/09 19:01–19:27 e 27/09 16:48–17:17. Há mais 5 execuções de agendamento em 25/09 09:01–09:16. A conta da NAI é 226 de webhook e 48 da "Agenda (todo minuto)". Há ainda 122 da captação e 4 do alarme nessas mesmas janelas. [OPINIÃO] É a fila interna do n8n, com `N8N_CONCURRENCY_PRODUCTION_LIMIT=5`, perdida num reinício. A última janela termina às 17:17, e o backup `/root/n8n_backup_20260927_fila/` é das 17:15–17:16 de Manaus, a hora do deploy da 133/134.

Decodifiquei o corpo das 493 de webhook, sem cabeçalhos:

- 439 são eco do que a própria Nay mandou (`fromMe`), a maioria fotos. Perder isso não tem efeito.
- 54 são mensagens recebidas, 27 ids distintos:
  - **12 nunca foram gravadas em `mensagens`** (fluxo antigo, 25/09 e 27/09): perdidas sem rastro, porque o alarme de órfãs só enxerga `status='Recebido'`;
  - **15 foram gravadas pelo fluxo antigo** (fluxo NULL, 'Processando') e nunca tiveram turno na NAI.

**O que o corretor vê:** nada. Os nós de modelo ("NAI (corretor)", "NAI (proprietário)", "NAI (Fernando)", "NAI (secretária)") não têm `retryOnFail` nem `onError`. Só "Baixar audio", "Transcrever", "Ler imagem (GPT)", "Baixar imagem", "Jev decide", "Enviar Z-API", "Enviar aviso do comando" e "Espelhar no CRM" usam `continueRegularOutput`. O erro derruba a execução, o turno fica aberto (`fechado_em` NULL) e as mensagens ficam em 'Processando'. Isso é igual, no banco, ao silêncio proposital: `nai_fechar_turno` é quem põe 'Respondido', e a view `vw_nai_execucoes` classifica os dois como `muda` (1.704 turnos reais em 30 dias, a maioria silêncio da porta).

A única reação é o fluxo de erro. Os dois fluxos ativos, "NAI atendimento locação" e "Nay- recebe mensagem", têm `settings.errorWorkflow` = "Nay - alarme de erro". Esse fluxo é: "Quando a Nay falhar" (Error Trigger) → "Montar aviso" (nome do fluxo, último nó, mensagem de erro, id da execução) → "Avisar o Tel" (POST na URL da Z-API, instância omitida, para …7316) → "Avisar no Telegram".

**Reprocessamento: não existe.** Três fatos:

1. Nenhum nó nem função refaz um turno morto.
2. O gatilho `mensagens_uma_vez_so` barra, por 2 dias e em qualquer fluxo, a reentrega da Z-API do mesmo `message_id`. Então nem a reentrega natural refaz a execução. Ficaram 443 barradas em `mensagem_repetida` entre 28/09 07:05 e 29/09 18:09.
3. `ciclo_pendencias.py` (cron de minuto, no publicador) só avisa o Tel de mensagem parada em 'Recebido' há mais de 5 min e a marca 'Perdida'. Foram 4 em 30 dias (16/09 ×2, 22/09, 24/09). Ele não vê 'Processando' sem turno (81 no fluxo NAI, de 15/09 a 28/09, 37 delas em 25/09) nem turno aberto sem saída.

O único reenvio automático é o da caixa de saída: `nai_confirmar_envio` (151) devolve à fila o erro passageiro da Z-API (5xx, tempo, rede) após 1 min e depois 2 min, até 2 vezes.

**Responde duas vezes?** Antes de 27/09, sim. "Mandar para a NAI" (httpRequest, timeout 10 s, `onError: continueErrorOutput`) caía no caminho do fluxo antigo quando estourava o prazo, e a NAI já tinha recebido. Resultado: o 3210 enviado 3× em 27/09. Desde 27/09, o nó "Prazo estourado? (a NAI recebeu)" testa `/timeout of \d+ms exceeded/` e encerra o fluxo. **Qualquer outro erro** (404 com a NAI desligada ou reiniciando) continua indo para "Filtrar e normalizar" e para o "AI Agent" do fluxo antigo (`gpt-5.6-luna`), que responde com a outra persona.

**Falhas mais comuns em 30 dias** (medidas no banco; o n8n só guarda as 2 de hoje):

| Quando (Manaus) | Falha | O que se mediu |
|---|---|---|
| 29/09 09:52–14:47 | OpenAI sem crédito | As 2 execuções com erro que sobraram no n8n: 14:15 "NAI (Fernando)" e 14:32 "NAI (corretor)", mensagem "OpenAI: Rate limit reached", `description` "You have no credits remaining". No banco: 51 turnos reais sem nenhuma saída, nenhum fechado; 26 deles roteados para locação pela mente, sem `montagem` nem `silencio`. Voltou às 14:48 (turno 12534) |
| 28/09 07:05–10:21 | FK `nai_estado_conversa_codigo_foco_fkey` no "Enfileirar resposta" | 10 turnos roteados que morreram sem saída (mais 1 às 21:09, causa NÃO SEI). O cabeçalho da 140 conta 12 desde 27/09 |
| 25/09 (21 dos 27 entre 15:09 e 15:28) | Sobrecarga | 27 turnos roteados mudos, 37 mensagens da NAI em 'Processando' sem turno, e a fila perdida (acima). A 122 (25/09) registra load 38 e consultas de 124 s. [OPINIÃO] mesma causa; o erro exato NÃO SEI, porque o n8n já apagou |
| 25/09 e 27/09, nas três janelas | Fila do n8n perdida no reinício | 12 mensagens nunca gravadas e 15 sem turno |
| 28/09 14:12–14:23 | Z-API 502 | 48 de 51 mensagens do disparo do Tel viraram `erro` e foram recolocadas às 14:35. Hoje o reenvio é automático (151) |
| Todo o período | Mensagem parada em 'Recebido' | 4 marcadas 'Perdida' |

**"Processando é o normal"**, conferido. No fluxo NAI, 'Processando' é a mensagem reservada por "Reservar mensagens" (`UPDATE … SET status='Processando' WHERE status='Recebido' AND fluxo='nai'`) cujo turno não foi fechado. Em 30 dias: 2.571 recebidas nesse estado, 2.490 com turno e 81 sem. No fluxo antigo, todas as 6.038 ficam 'Processando' para sempre. O rótulo junta silêncio de propósito e execução morta.

---

### 44. Resposta duplicada e mensagem para a pessoa errada

**Duplicadas medidas (FATO).** Procurei em `nai_saida`, estado enviado, o mesmo destino, tipo e texto (ou foto) em menos de 2 min, nos 30 dias. Achei 25 linhas em três episódios:

- **23/09 12:50–12:51, turnos 10648 e 10649 (…3439):** "Esse" e, 34 s depois, "Poderia ver as fotos" abriram dois turnos, e cada um mandou as mesmas 15 fotos do 5718 mais 2 textos. A trava de foto repetida em `nai_liberar_saida` libera quando ele pede foto ("foto que ELE pediu de novo sai de novo"), e a rajada não juntou as duas mensagens.
- **14/09 06:00:44 (…2835):** três lembretes iguais, "Só falta o CPF do visitante pra eu fechar a visita" (visita 243), criados às 23:50, 00:21 e 00:51 e liberados no mesmo segundo quando abriu a janela de horário.
- **12/09 19:28–19:30:** "Sobre isso: fica 4.300 😉" 5× para o contato de teste "Corretor…" (…6666), antes de a Nay entrar no ar.

Fora de `nai_saida` também há duplicata:

- **27/09 16:31–16:39:** o 3210 foi 3× para …1119 (`envios`). A causa foi a mensagem do Tel entrando várias vezes, com a queda para o fluxo antigo no timeout.
- **Fluxo antigo, respondendo ao Tel (…7316):** 7 respostas iguais, "tel, não consigo abrir a imagem, escreve a mensagem…", em 27/09 09:43–09:45 (duas no mesmo segundo), e 6 variações de "sem fotos então" em 25/09 18:10–18:30. Estão em `mensagem_saida` sem linha correspondente em `nai_saida`. O "AI Agent" antigo ainda responde por algum caminho. Qual, NÃO SEI: o n8n dessas datas já foi apagado.

**Como foi possível:**

- a Z-API reentrega;
- havia dois fluxos atendendo a mesma mensagem (a queda no timeout);
- a trava da rajada contava as outras mensagens e deixava a mais nova escapar (consertado na 147);
- a exceção "pediu foto de novo, sai de novo".

**O que impede hoje (FATO, código vivo):**

- o gatilho `mensagens_uma_vez_so` (BEFORE INSERT em `mensagens`): recebida com id real repetida em 2 dias vira `RETURN NULL`; enviada, uma por fluxo;
- o nó "Prazo estourado? (a NAI recebeu)";
- "Reservar mensagens", um UPDATE atômico de 'Recebido' para 'Processando';
- o gatilho `mensagens_espera_a_rajada`, com janela de 20 s (15 s para teste) via `nai_janela_segundos`;
- `nai_liberar_saida` com `FOR UPDATE SKIP LOCKED` e a trava 'repetida' de 10 min para texto;
- a trava de 24 h por imóvel e pessoa (`imovel_enviado_no_dia`, `nay_reservar_imovel_do_dia`) em `nai_saida_validar`, no publicador e em `entregar_pendentes.py`, que tornou o episódio de 23/09 impossível.

**Buraco que continua (FATO no código, risco [OPINIÃO]).** A trava de 10 min compara `coalesce(s2.enviado_em, s2.criado_em)`. A linha em 'enviando' tem `enviado_em` NULL, então vale o `criado_em`. Dois textos iguais criados com mais de 10 min de diferença e liberados no mesmo tick saem os dois, como no episódio de 14/09.

**Pessoa errada.** No `nai_saida` a trava é estrutural. `nai_saida_validar` sobrescreve `chave_destino` com a chave do contato ("Quem enfileira nao escolhe") e dá `RAISE` quando:

- a resposta de turno vai para quem não escreveu o turno;
- o papel corretor, proprietário ou motoboy não é o da visita;
- o papel `tel` não é o Tel;
- é foto para quem não é corretor.

Não achei, nos 30 dias, envio da NAI para um contato diferente do pretendido. O `RAISE` aborta a inserção e só aparece como erro no n8n, que já foi apagado; por isso a contagem de tentativas barradas é NÃO SEI.

O modo teste redirecionava tudo para …2835 com etiqueta: 1.260 linhas `redirecionado` entre 10/09 e 22/09, 84 enviadas. Hoje `modo='todos'`.

Os casos reais de "pessoa errada" vieram de antes da caixa:

- 01/09: `RESPOSTA 49` digitada pelo Tel no lugar da 48 (bug 9);
- 19/09: a mesma pessoa em duas linhas, telefone e @lid, e a Nay falou por cima do Tel (39; `nai_contato_irmaos` normalizado na 168 em 29/09, com 20 pessoas afetadas);
- 26/09: o espelho do treino criava lead falso no CRM com nome de corretor real (24 conversas; barrado por `ehEspelhoDeTreino`);
- 29/09: a Nay respondia ao acompanhante André e o chamava de Fernando (186).

---

### 45. Correções feitas direto em produção que não voltaram ao repositório

**Premissa.** São **dois** repositórios. O que a outra IA leu (`pvlservicos-collab/nayia`) não tem as funções nem os scripts do publicador. Esses vivem em `/root/nay-publicador`, outro git (`Telsobreira/nay-publicador`), com 86 `.sql` que criam boa parte das funções `nay_`. Parte do que parece "só no banco" está versionada lá.

**Método.** Puxei as 460 funções de usuário do schema public (as 506 menos 46 de extensão) com `oidvectortypes(proargtypes)` e `prosrc`. Tirei todos os `CREATE FUNCTION` dos `.sql`, `.py` e `.js` do repositório e dos `.sql` do publicador. Casei por nome mais tipos dos argumentos, com sobrecarga contada separada, e comparei o corpo sem comentários nem espaços, contra a última definição em ordem de migração. Também datei com `nai_funcao_foto` de 19/09 15:32: o `hash` é `md5(prosrc)` (206 de 245 batem hoje), então hash diferente quer dizer que a função mudou depois de 19/09.

| Comparação | Batem com a última definição | Batem com uma definição antiga | Divergem de todas | Só no banco |
|---|---|---|---|---|
| Só o repositório `Nay IA` | 407 | 1 | 11 | 41 |
| `Nay IA` + publicador | 430 | 4 | **7** | **19** |

Das 4 "antigas", 2 são só ordem entre os dois repos (`nay_comando`, `nay_resolver_identidade`, que batem com o arquivo mais novo). As outras 2 são reais:

- **`nay_esquecer_imovel`: regressão.** Hoje o corpo é o de `conhecimento_do_imovel.sql` (reaplicado pelo commit do publicador de 22/09 16:17 Manaus, "Tem armários e ar?"). Esse corpo desfez o conserto de 01/09 (`resposta_vira_conhecimento.sql`), que também limpava `pendencias.resposta` do código. É exatamente o risco de reaplicar arquivo antigo.
- **`nai_tel_com_a_conversa`:** o vivo é o `voz_do_tel_sem_chat_assumido.sql` do publicador (28/09 08:53), que acrescenta a exceção `nai_e_voz_do_tel`. No repo `Nay IA` a última versão é a 130 (27/09), atrasada.

**As 7 que divergem de todas as definições:**

| Função | O que o banco tem a mais | Data provável |
|---|---|---|
| `nai_enfileirar_resposta_ferramentas` | Parede 1 `saida_sem_consulta`, parede 2 (código rejeitado não volta) e chamadas a `nai_ferramenta_de_imovel` e `nai_registrar_saida_v2`. O repo (05, 14/09) só repassava para `nai_enfileirar_resposta` | 25/09 ~11:09 (1ª linha `saida_sem_consulta`) |
| `nai_decidir_com_jev` | Piso `jev_piso_pedido` e "· pediu imóvel: sim/não" no detalhe | 24/09 ~23:51 (1º detalhe com "pediu imóvel:"), depois do 118 |
| `nai_imoveis_pedidos` | CTE `alvo AS MATERIALIZED` (desempenho) | depois de 23/09 (114); [OPINIÃO] 25/09, com a 122 |
| `nai_oferece_imovel` | Dois padrões novos: "eu tenho… mobiliado/quartos/aluguel…" e "como funciona… anunciar" | depois de 22/09 18:28 (97); [OPINIÃO] logo após o turno 10770 de 24/09 |
| `nai_sec_guardar_do_imovel` | `nai_tipo_canonico`, `nai_um_nome_so` e teto de valor | depois de 22/09 19:33 (99c); [OPINIÃO] 23/09 (112) |
| `nay_pode_falar` | Compara o telefone exato; o repo compara os 8 últimos dígitos | antes de 19/09 15:32 (hash igual ao da foto) |
| `nay_responder_pendencia` | Ramo da secretária (`nai_saber_guardar`) | depois de 19/09; ≥ 22/09, quando nasceu a secretária |

**As 19 que só existem no banco** (nenhum `CREATE` em nenhum dos dois repos):

- **Arquitetura "v2", de 25/09 10:39–11:09:** `nai_decidir_v2` (nó "Decidir quem responde"), `nai_estado_v2` (nó "Ler estado"), `nai_ferramentas_v2`, `nai_registrar_saida_v2`, `nai_pode_enviar_codigo_v2` e `nai_ferramenta_de_imovel`. As tabelas `nai_turno_decisao` (657 linhas, a 1ª às 11:07), `nai_treino_rodada`, `nai_treino_conversa` e `nai_treino_bloco` também não têm `CREATE TABLE` em repo nenhum.
- **Chamadas por migrações que não as criam:** `nai_jev_pedido` (usada na 124b, 26/09), `nai_pediu_imovel` (144/147, 28/09) e `nai_chaves_de` (126, 26/09; usada por `nai_deve_atender` e `nai_na_lista_curta`).
- **Treino:** `nai_treino_colher`, `nai_treino_contexto`, `nai_treino_montar_ciclo`, `nai_treino_semear_memoria`, `nai_rodada_montar` e `nai_bloco_colher`. Todas depois de 19/09.
- **Anteriores a 19/09 e nunca versionadas:** `nay_captacao_tem_campo`, `nay_captacao_tem_contagem`, `nay_captacao_tem_valor` e `nay_cond`. A última é usada nos dois fluxos do n8n.

Olhando só o repositório `Nay IA`, somam-se a essas mais 22 funções `nay_` que estão versionadas apenas no publicador: lista de imóveis, linha da lista, aviso de saída, `nay_esta_no_mercado`, `nay_condominios_candidatos` e outras.

**O publicador tem código de produção sem commit.** `git status` em `/root/nay-publicador` (último commit 29/09 10:24 Manaus) mostra 250 linhas inseridas e não commitadas:

- `enviar_zapi.py`: a gravação em `saida_do_sistema`, conserto do "eco da API cala a Nay" de 27/09. O último commit desse arquivo é de 09/09;
- `publicador.py` e `entregar_pendentes.py`: a trava de 24 h via `nay_reservar_imovel_do_dia`, de 27/09. Os arquivos têm data de 29/09 10:24;
- `alertar_visitas.py`: 28/09 10:51;
- `sincronizar_catalogo.py`: `travado` e origem crm/olx/captação, 28/09 23:43.

E há arquivos de produção fora do git: `ficha_do_anuncio.py/.sh` (a 191, de 29/09 18:10, rodando no cron a cada 3 h), `sincronizar_etapas_crm.py/.sh` (28/09, cron de minuto), `avisar_saidas.sh` (28/09, cron de minuto) e `geocodificar_imoveis.py` (28/09).

**n8n.** O `workflow_history` guarda só a versão atual: a NAI por "import" em 28/09 11:34 Manaus, o antigo em 28/09 09:40. No repo existem os backups de 16/09 (4 arquivos) e o export de 19/09 (`imob-easy/admin/dados/nai-fluxo-n8n.json`). Contra o de 16/09, o fluxo vivo tem 41 nós iguais, 28 alterados e 19 novos.

Procurei cada linha de código dos nós (com 45 caracteres ou mais) nos dois repos:

- **NAI:** 18 de 70 nós com código têm linhas que não estão em repo nenhum. Os principais são "Montar pergunta ao Jev" (24 de 29 linhas), "Comando do Tel", "Achar codigo na resposta", "Rotear pelo cabeçalho" (os regex de envio de imóvel para um número), "Decidir quem responde" (`nai_decidir_v2`), "Ler estado" (`nai_estado_v2`, 25/09), "Gravar na fila", "Conferir cabeçalho" (a chave 'lid:'), "guardar_do_imovel_novo", "Transcrever" (o vocabulário) e "Espelhar no CRM" (28/09).
- **Fluxo antigo:** 41 de 50 nós com código não estão em repo nenhum. Entre eles, o prompt do "AI Agent" (282 de 292 linhas), "Comando do Tel", "Rotear para o agente", "NAI ou Nay? (quem atende)", "Mandar para a NAI" e "Prazo estourado? (a NAI recebeu)" (27/09).

As cópias existem só no servidor, fora de git: `/root/n8n_backup_20260927_fila/{antigo,nai,antigo_novo,nai_novo}.json`, `/root/backups-n8n` e `/root/backup_fluxo_antes_da_mente.json`.

**Outros estados de produção sem cópia no repo:**

- O prompt corretor v14–v16 (28/09 10:46 e 11:09, "Claude 28/09: …"): 46 das 76 linhas longas da v16 não estão em arquivo nenhum. O banco guarda as versões em `nai_prompt_historico`.
- As variáveis do n8n `N8N_CONCURRENCY_PRODUCTION_LIMIT=5` (25/09, pela memória), `N8N_RUNNERS_MAX_CONCURRENCY=2` e a poda 2000/72 h.
- O crontab do servidor, inclusive o disparo único `ligar_nay_20260928.sh`.

**O que a memória contava e já voltou ao repo:** as mudanças de 16/09 em `nai_liberar_saida` (`v_cmd` e `nai_tel_com_a_conversa`) hoje batem com a 142. As 190p/191p foram geradas a partir do `pg_proc` vivo, então batem por construção.

---

## Blocos 9 e 10: setores; como muda e como testa

Medido em 29/09/2026, entre 19h e 19h40 de Manaus, direto no `naydb` (transação só leitura), no sqlite do n8n de produção, no n8n da VPS2 (captação), nos scripts de `/root`, `/root/nay-publicador`, `/docker/*` e no repositório local. Os horários do banco já estão em Manaus. Os horários de arquivo no servidor estão em UTC: o servidor roda em UTC, e a prova é o cron `0 11 28 9 *` comentado como "07:00 de Manaus".

---

## BLOCO 9: SETORES

### 46. Os 12 setores e se 64/65/66 estão aplicados

**Os três arquivos estão aplicados, e o corpo das funções está idêntico ao do arquivo.** Comparei o md5 do `prosrc` vivo das 15 funções criadas pelos arquivos 64 e 65 com o md5 do corpo entre `$$` nos arquivos: as 15 batem. Essas 15 funções são `nai_setor_ordem`, `nai_mascarar_texto`, `nai_mascarar`, `nai_tracar`, `nai_tracar_modelo`, `nai_tracar_cabecalho`, `nai_tracar_entrada`, `nai_tracar_ferramenta`, `nai_tracar_erro`, `nai_trilha`, `nai_trace_limpar`, `nai_setor_de_funcao`, `nai_setor_final`, `nai_foto_tirar` e `nai_foto_diferenca`.

Existem também as 9 tabelas e as 10 views dos três arquivos:
- tabelas: `nai_setor`, `nai_evento`, `nai_setor_regra`, `nai_setor_excecao`, `nai_foto`, `nai_funcao_foto`, `nai_funcao_chamador`, `nai_sobrecarga_esperada` e `nai_regra`;
- views: `vw_nai_execucoes`, `vw_nai_setor_saude`, `vw_nai_setor_etapas`, `vw_nai_funcao_viva`, `vw_nai_acoplamento`, `vw_nai_funcao_orfa`, `vw_nai_sobrecarga`, `vw_nai_setor_mapa`, `vw_nai_regras_ignoradas` e `vw_nai_obediencia`;
- as 4 colunas novas de `nai_turno`: `exec_id`, `prompt_versao`, `modelo` e `ms_total`;
- as 3 chaves `trace_*` em `nai_config`.

A aplicação foi em 19/09, entre 15:31 e 15:32:
- `nai_config.atualizado_em` das chaves `trace_*` marca 19/09 15:31:42;
- `nai_evento` id 1 marca 15:31:47;
- `nai_foto` id 1 ("marco zero") marca 15:32;
- o commit é o `9590dc0`, do mesmo dia.

Não comparei o texto das views com o arquivo, só a existência delas.

**Aplicado não é o mesmo que funcionando.** Quatro partes nunca saíram do lugar:
- o trace nunca foi alimentado (ver a 53);
- a foto do inventário foi tirada uma vez só (`nai_foto` tem 1 linha);
- `nai_setor_excecao` tem 0 linhas;
- `nai_funcao_chamador` continua com as 26 linhas de 19/09.

`nai_trace_limpar()` não está em nenhum cron. O endpoint do painel `/api/nai/trace/inventario` (em `trace_api.py`, dentro do container `nay-site-api`) já caiu com `QueryCanceled: canceling statement due to statement timeout`, que aparece uma vez em `docker logs nay-site-api`. A view `vw_nai_setor_mapa` levou 12,8 s na minha medição.

Os 12 setores, na ordem de `nai_setor.ordem`, com a frase de `nai_setor.descricao` e o que o setor contém de fato hoje:

| setor | o que devia ser (descrição do banco) | o que o setor contém de fato hoje |
|---|---|---|
| entrada | webhook da Z-API, normalização, janela, áudio/imagem viram texto | Isso tudo mora no n8n e em dois gatilhos (`mensagens_uma_vez_so`, `mensagens_espera_a_rajada`) que ficam **fora** do inventário. As 18 funções "de entrada" são todas `captacao_*`, caídas na regra 999. |
| identidade | quem é a pessoa: chave DDI+DDD+8, @lid, as duas linhas da mesma pessoa | `nai_chave`, `nai_fone_fmt`, `nai_contato_irmaos`, `nay_resolver_identidade`, `nay_sincronizar_nome` |
| porta | quem é atendido e quem não é | `nai_quem_atende` (nó "NAI ou Nay? (quem atende)" do fluxo antigo), `nai_deve_atender` (chamada por `nai_abrir_turno` e pelo nó "Rotear pelo cabeçalho"), `nai_tel_assumiu`, `nai_tel_com_a_conversa` |
| cabecalho | abre o turno: papel, visita, memória, prompt, contexto | `nai_abrir_turno` e `nai_contexto_corretor`, mais um balde de 140 funções, 130 delas pela regra 900. O balde inclui a mente mestra e o Jev (`nai_decidir_com_jev`, `nai_decidir_v2`, `nai_mente_registrar`), a secretária (`nai_sec_*`), o cadastro, o treino e a própria bateria (`nai_rodar_casos`). |
| modelo | a resposta crua antes da conferência | **0 funções.** Não há regra para "modelo" em `nai_setor_regra`. O setor seria alimentado por `nai_tracar_modelo`, que nunca rodou. O modelo mora nos 4 nós `lmChatOpenAi` (`gpt-5.6-sol`). |
| ferramenta | que ferramenta o agente chamou, com que argumentos e o que voltou | 93 funções, 34 pela regra 901 (qualquer `nay_` sem padrão) |
| conferencia | a esteira das 17 | `nai_conferir_resposta` e `nai_anotar`. Hoje `nai_conferencia` grava **36** etapas distintas, não 17. |
| montagem | a resposta vira mensagem: card, fotos, frases do sistema | `nai_enfileirar_resposta_ferramentas` (nó "Enfileirar resposta"), `nai_enfileirar_resposta`, `nai_enfileirar_card`, `nai_card_do_imovel` |
| saida | liberação e travas: pausa, janela, repetida, Tel assumiu, Z-API | `nai_liberar_saida`, os gatilhos `nai_saida_validar` e `nai_saida_imutavel`, `nai_conferir_imoveis_da_saida`, `nai_conferir_texto_da_saida` |
| agenda | ticks de minuto: cobranças, lembretes, visitas, senha, "como foi?" | `nai_agenda_tick` (nó "Agenda da NAI") e as funções `_visita` |
| comando | comandos do Tel pelo WhatsApp | `nai_comando_tel` e `nay_comando` |
| catalogo | imóveis, fotos, varredura, "não encontrei o imóvel" | `nay_esta_no_mercado`, `nay_normalizar_lugar`, `nai_imovel_pelo_condominio`, `nay_disponibilidade_no_condominio` |

### 47. Funções por setor, acoplamento com a Nay antiga e órfãs

**A premissa precisa de ajuste: os números por setor que o banco mostra são inflados e em parte errados, por três motivos medidos.**

1. **As redes de segurança engolem 44% do inventário.** Medi a primeira regra que casa com cada uma das 415 assinaturas da `vw_nai_funcao_viva`. **182 caíram nas regras de rede**:
   - regra 900 (`^nai_` vai para "cabecalho"): 130 funções;
   - regra 901 (`^nay_` vai para "ferramenta"): 34;
   - regra 999 (`.` vai para "entrada"): 18, todas `captacao_*`.

   Resultado: **130 das 142 funções do "cabeçalho" (92%) estão lá por falta de padrão**. O mesmo vale para 34 das 93 de "ferramenta" e para 18 das 18 de "entrada". "Cabeçalho" virou o lugar da mente mestra, da secretária, do cadastro, do treino e da bateria. "Entrada" não contém nenhuma função de entrada da NAI.

2. **O filtro de exclusão do trace esconde funções de atendimento.** A regex `^nai_(tracar|mascarar|trilha|evento|foto|setor|...)` tira do inventário:
   - `nai_fotos_faltando`, chamada pelo nó "Fotos faltando?";
   - `nai_fotos_ja_mandadas`, a trava de 24h das fotos;
   - `nai_evento(p_visita, p_tipo, p_detalhe)`, que grava em `nai_visita_evento`.

   Também ficam de fora os 2 gatilhos `mensagens_*`, que rodam em toda mensagem, e as 24 funções `crm_*`. Estas não são `nai|nay|captacao`, mas escrevem em `nai_contato`, `nai_visita` e `nai_saida`.

3. **A "órfã" do 65 marca como entulho funções do caminho de toda mensagem.** A view só procura chamadas dentro de outras funções `nai_`/`nay_` e nas 26 linhas de `nai_funcao_chamador`, anotadas em 19/09 e nunca atualizadas. Consultei a `vw_nai_funcao_orfa` agora, e ela marca "CANDIDATA: ... conferir antes de apagar" para:
   - `nai_decidir_com_jev` e `nai_decidir_v2` (nó "Decidir quem responde");
   - `nai_enfileirar_resposta_ferramentas` (nó "Enfileirar resposta");
   - `nai_estado_v2` (nó "Ler estado");
   - `nai_registrar_bloqueio`;
   - `nai_enfileirar_cortesia`;
   - `nai_sec_consultar`;
   - o gatilho `nai_saida_validar`.

   Uma anotação de 19/09 também está velha: `nai_enfileirar_resposta` aparece como chamada pelo nó "Enfileirar resposta", mas hoje o nó chama `nai_enfileirar_resposta_ferramentas`.

**Os números por setor.** Contei por nome, juntando as sobrecargas; a view conta 415 assinaturas e dá porta 22, cabecalho 142 e catalogo 31. As colunas são:
- **chamam `nay_`**: funções cujo corpo cita alguma função `nay_`; entre parênteses, só as `nai_`;
- **órfã (régua do 65)**: o que a view dá; entre parênteses, as "candidatas" sem chamador anotado;
- **morta de verdade**: inalcançável depois do meu cruzamento (explicado abaixo).

| setor | funções | nai/nay/captação | chamam `nay_` | órfã (régua do 65) | morta de verdade | chars | a mais importante [OPINIÃO] |
|---|---|---|---|---|---|---|---|
| entrada | 18 | 0/0/18 | 2 (0) | 0 (a view não olha `captacao_`) | 0 | 23.300 | nenhuma função da NAI. A entrada real é o gatilho `mensagens_espera_a_rajada`, em toda mensagem. |
| identidade | 19 | 11/6/2 | 6 (3) | 3 (3) | 0 | 19.379 | `nai_chave`: 45 funções chamam, em toda mensagem |
| porta | 21 | 20/1/0 | 1 (1) | 5 (3) | 0 (+2 interruptores manuais) | 20.875 | `nai_deve_atender`: 19.490 chars, roda em todo `nai_abrir_turno` |
| cabecalho | 140 | 140/0/0 | 17 (17) | 25 (22) | 3 (+2 manuais) | 194.441 | `nai_abrir_turno` (36.018 chars, toda mensagem). Na parte escondida do balde, `nai_decidir_com_jev`. |
| modelo | 0 | – | – | – | – | – | – |
| ferramenta | 93 | 35/58/0 | 41 (13) | 31 (27) | 8 | 165.424 | `nay_codigos_citados`: 16 funções chamam, e está nos nós "Reservar mensagens" e "Achar codigo na resposta" dos dois fluxos |
| conferencia | 18 | 17/1/0 | 1 (1) | 1 (1) | 0 | 34.172 | `nai_conferir_resposta`: 53.664 chars, a maior do banco, em toda resposta do modelo |
| montagem | 12 | 11/1/0 | 1 (1) | 6 (5) | 0 | 23.827 | `nai_enfileirar_resposta_ferramentas`, a porta de entrada da esteira |
| saida | 11 | 7/4/0 | 3 (2) | 6 (5) | 0 | 34.059 | `nai_liberar_saida` (29.202 chars) e o gatilho `nai_saida_validar` |
| agenda | 42 | 32/9/1 | 7 (4) | 18 (11) | 4 | 91.906 | `nai_agenda_tick`: 37.432 chars, roda todo minuto |
| comando | 7 | 2/5/0 | 3 (0) | 3 (3) | 0 | 33.940 | `nai_comando_tel` (37.614 chars) |
| catalogo | 30 | 13/16/1 | 11 (5) | 10 (8) | 3 | 45.250 | `nay_esta_no_mercado`: 17 funções chamam, 12 delas `nai_` |
| **total** | **411** | **288/101/22** | **93 (47)** | **108 (88)** | **18** | | |

**Comparação com 19/09.** O 65 falava em 284 funções no schema (148 `nai_`, 89 `nay_`, 47 outras). Hoje o schema tem 506 funções:
- 309 `nai_`;
- 102 `nay_`: a Nay antiga **cresceu 13**. São funções do publicador, como `nay_codigos_da_lista`, `nay_reservar_imovel_do_dia` e `nay_saidas_a_avisar`;
- 22 `captacao_`;
- 73 outras.

O acoplamento dobrou. Em 19/09 eram 22 funções `nai_` chamando 28 `nay_`. Hoje **47 funções `nai_` chamam 22 `nay_`** (`vw_nai_acoplamento`: 22 antigas, 71 pares). As mais chamadas são:
- `nay_esta_no_mercado`: 12 chamadoras `nai_`;
- `nay_codigos_citados`: 11;
- `nay_maior_valor`: 7;
- `nay_normalizar_lugar`: 6.

Além disso, **os nós do fluxo NAI chamam direto 17 funções `nay_`**, entre elas as 9 do "Reservar mensagens", `nay_comando`, `nay_cond` e `nay_disponibilidade_no_condominio`.

Pela régua do 65, as órfãs foram de 35 para 108 e as candidatas de 16 para 88. `nai_foto_diferenca()` contra o marco zero mostra **170 funções novas, 39 com corpo mudado e 0 apagadas** desde 19/09 15:32. Ninguém limpou nada.

**Como cheguei às "mortas de verdade".** Juntei quatro fontes de chamada:
1. o corpo de **todas** as 460 funções não-C do schema, com os comentários tirados;
2. as 42 views, os 9 gatilhos, os defaults e os checks;
3. os nós dos 12 workflows do n8n de produção e dos 3 da VPS2;
4. os scripts em `/root`, `/root/nay-publicador` e `crontab -l`, mais o código vivo de `/docker/crm/app`, `/docker/nay-site-api` e `/docker/nay-painel`, e as pastas `crm/`, `nay-site-api/`, `imob-easy/` e `nay-painel/` do repositório.

A partir dessas raízes, calculei quem é alcançável. Sobram **18 inalcançáveis**, mais 4 que só uma pessoa chama à mão (`nai_rodar_casos`, `nai_ligar_regra_publico`, `nai_desligar_regra_publico` e `nai_rodada_montar`). As 18 são:
- catálogo: `nay_bairro_e_perto`, `nay_imovel_do_disparo` (citada só num comentário de `nay_codigo_confirmado`), `nay_registrar_mensagem_grupo`;
- ferramenta: `nai_enviar_imovel_para` (substituída pela `nai_enviar_imoveis_para`), `nai_pode_enviar_codigo_v2`, `nai_sec_guardar_foto`, `nay_captacao_campos_desconhecidos`, `nay_captacao_tem_campo`, `nay_captacao_tem_contagem`, `nay_captacao_tem_valor`, `nay_imovel_marcado`;
- agenda: `nai_cancelar_visita`, `nai_frase_visitante`, `nai_linha_acesso_motoboy`, `nai_minhas_visitas` (ferramentas antigas do agente de visita);
- cabeçalho: `nai_atualizar_palavras_conhecidas`, `nai_cadastro_modelo`, `nai_ferramentas_v2`.

Das 88 candidatas da view, 36 estão vivas **só** por chamadores de fora. Por exemplo:
- `disparar_lembretes.py`, `ciclo_pendencias.py`, `entregar_pendentes.py`, `avisar_saidas.py` e `publicador.py`, em `/root/nay-publicador`;
- `crm/src/lib/nayDisparo.ts`, que chama `nai_disparo_*` e `nai_checklist_enfileirar`;
- o crontab, que roda `nai_vocabulario_atualizar` às 04:17;
- `jev_rodada.py` e `nai_treino_rodar.py`;
- o site, que chama `nai_salvar_prompt`.

### 48. Por onde reconstruir, o que é frágil, o que é estável

Primeiro os fatos que sustentam a opinião:

| setor | chars | migrações 97–191 (22–29/09) que redefinem função do setor | desde 19/09: novas / corpo mudou | vivas sem cópia idêntica no repo |
|---|---|---|---|---|
| cabecalho (balde) | 194.441 | 49 | 95 / 5 | 14 |
| ferramenta | 165.424 | 31 | 30 / 13 | 25 |
| saida | 34.059 | 13 | 6 / 2 | 4 |
| catalogo | 45.250 | 11 | 10 / 2 | 4 |
| montagem | 23.827 | 9 | 4 / 3 | 2 |
| porta | 20.875 | 7 | 3 / 4 | 1 |
| conferencia | 34.172 | 6 | 0 / 3 | 0 |
| identidade | 19.379 | 5 | 2 / 2 | 1 |
| comando | 33.940 | 5 | 1 / 2 | 1 |
| agenda | 91.906 | 4 | 9 / 3 | 0 |
| entrada (captação) | 23.300 | 4 | 10 / 0 | 0 |

Fora do inventário, 18 migrações mexeram em funções `crm_*` e 3 nos gatilhos de `mensagens`.

**Os commits não servem para medir bugs por setor.** O repositório começa em 19/09 e tem 51 commits. O commit `4695088` ("llsss", 29/09 19:29) junta **80 arquivos de migração** (125 a 191) de uma vez. Por isso contei os arquivos de migração, que são um por conserto, e cruzei com os incidentes que as próprias migrações e a memória descrevem:

| data | setor | incidente |
|---|---|---|
| 24/09 | decisão (balde "cabeçalho") | a cola do cadastro calava a Nay: 13 de 16 turnos (121) |
| 24/09 | decisão | o prompt da mente dizia "LOCACAO" e 58 de 137 conversas foram para a secretária (115–117) |
| 25/09 | decisão | 124 s por turno na "fonte única" (122) |
| 27–28/09 | decisão | a FK de `nai_estado_conversa.codigo_foco` derrubou 12 respostas (140) |
| 25/09 | porta | a lista curta barrou o espelho (126) |
| 27/09 | porta | o eco do publicador calava a Nay por 30 min (134) |
| 27/09 | entrada (gatilhos) | duplicatas de mensagem (133) |
| 28/09 | entrada (gatilhos) | a rajada soltava a mensagem mais nova (147) |
| 24/09 | conferência da saída | apagou as 7 linhas do Park Golf (120) |
| 28/09 | saída | Z-API com 502 (151) |
| 29/09 | identidade | @lid dos irmãos (168) |
| 29/09 | modelo | OpenAI sem crédito calou tudo |
| 22–29/09 | catálogo/ferramenta | venda x locação e casa x apartamento, de novo e de novo (98, 103, 144, 152, 190) |

**[OPINIÃO] Antes de reconstruir qualquer coisa, eu consertaria o mapa.** Hoje "cabeçalho" é uma pilha sem critério: reconstruir o "setor cabeçalho" como ele está classificado seria reconstruir uma pilha aleatória. Ele precisa ser dividido pelo menos em:
- decisão (mente, Jev e secretária);
- pedido e filtro (`nai_pedido_do_turno`, `nai_tipo_*`, `nai_negocio_*`);
- normalização de texto (`nai_corrigir_nomes`, gírias);
- cadastro;
- teste e treino (`nai_rodar_casos`, `nai_treino_*`), que não é atendimento.

"Entrada" precisa receber os gatilhos e o que hoje mora no n8n. É só `INSERT` em `nai_setor_regra` e `nai_setor_excecao`, sem deploy.

**[OPINIÃO] O primeiro a reconstruir seria a decisão (quem responde e com que intenção)**, que hoje está escondida no "cabeçalho". São `nai_decidir_com_jev`, `nai_decidir_v2`, `nai_mente_registrar`, `nai_estado_v2`, `nai_estado_gravar_v2` e `nai_pedido_do_turno`. Os motivos:
1. É a mais nova (22 a 25/09) e a que mais causou silêncio: cola do cadastro, prompt da mente e FK do foco.
2. O código dela **não está no repositório**. `nai_decidir_v2`, `nai_estado_v2`, `nai_ferramentas_v2` e `nai_registrar_saida_v2` só existem em `/tmp/74_estado_e_decisao.sql` e `/tmp/75_gravar_decisao_e_semear_estado.sql` no servidor. Esses números colidem com os arquivos 74 e 75 do repositório, que são outra coisa.
3. Tem costura limpa no n8n: os nós "Decidir quem responde", "Ler o Jev" e "Ler estado".
4. Tem gabarito gravado para testar em sombra com a Nay no ar: `nai_mente` (839 linhas desde 22/09), `nai_jev` (714 desde 24/09) e `nai_turno_decisao` (657 desde 25/09, com `jev_bruto`). Dá para rodar a decisão nova em paralelo e comparar sem mandar nada.
5. A esteira hoje **recalcula** o que a decisão deveria entregar: `nai_conferir_imoveis_da_saida` chama `nai_pedido_do_turno` de novo. Uma decisão estruturada simplifica a reconstrução seguinte.

**[OPINIÃO] O mais frágil é a esteira: montagem, conferência e saída.** A fragilidade está nos fatos:
- As maiores funções do caminho de cada resposta estão todas nela: `nai_conferir_resposta` (53.664 chars), `nai_liberar_saida` (29.202), `nai_saida_validar` (23.578), `nai_enfileirar_resposta` (21.752) e `nai_enfileirar_resposta_ferramentas` (9.666).
- Tem três camadas de conferência em sequência e **apaga o que acabou de enfileirar** (`nai_enfileirar_resposta_ferramentas` faz `DELETE FROM nai_saida`).
- 28 migrações entre 22 e 29/09 (13 na saída, 9 na montagem e 6 na conferência).
- `nai_conferencia` grava 36 etapas, mas só 17 têm nome em `nai_regra`. As outras 19 ficam invisíveis para `vw_nai_regras_ignoradas` e `vw_nai_obediencia`, entre elas `mente_mestra` (897), `saida_sem_consulta` (373, agiu em 100%) e `espera_as_fotos` (106).
- 10 etapas nunca agiram desde 14/09, como `fotos_do_site`, `negou_imovel_que_existe`, `sugestao_repetida`, `voz_sem_emoji` e `markdown`, cada uma com mais de 1.000 passagens.
- Nos últimos 7 dias, 1.147 das 4.317 linhas de `nai_saida` foram bloqueadas. Os motivos que mais aparecem: `tel_assumiu` (385), "ele procura locação" (218), "tipo errado" (217), repetida (62) e as travas de 24h.
- As mortes silenciosas mais caras aconteceram aqui: a FK dentro de "Enfileirar resposta" e o Park Golf.

Eu não a reconstruiria primeiro porque é a última linha de proteção (parceria, venda x locação, 24h). Mexer nela antes de a decisão entregar dados estruturados é arriscar perder as paredes.

**[OPINIÃO] O mais estável, que dá para manter, é "identidade".** Os fatos:
- 19 funções e 19 mil chars;
- 18 das 19 idênticas a um `.sql` do repositório;
- só 2 corpos mudaram desde 19/09 (`nai_contato_irmaos` e `nai_vocativo`);
- `nai_chave` segura 45 chamadoras e não mudou desde o marco zero.

A ressalva é o @lid (168, 29/09). Entre os grandes, a **agenda** vem logo atrás:
- 42 de 42 funções idênticas ao repositório;
- só 4 migrações no período;
- nenhum incidente de bug desde 22/09, só mudanças de regra (179a/b).

O cuidado com a agenda é que o CRM passou a escrever em `nai_visita` (169 a 174).

### 49. Tabelas escritas por mais de um setor

Varri o `prosrc` sem comentários de todas as funções (`INSERT INTO`, `UPDATE` sem `DO UPDATE`/`FOR UPDATE`, `DELETE FROM`) e o SQL dos nós Postgres dos fluxos ativos. Cruzei com `nai_setor_final`. As tabelas com mais escritores:

| tabela | quem escreve |
|---|---|
| `nai_contato` | porta (`nai_deve_atender`, `nai_parar_chat`, `nai_tel_assumiu`), cabeçalho (`nai_zerar_conversa`, `nai_contato_do_cadastro`, `nai_enviar_imoveis_para`, `nai_enviar_checklist_para`), agenda (`nai_guardar_dados_visita`, `nai_liberar_chats_da_visita`), montagem (`nai_enfileirar_resposta`, `nai_depois_das_fotos`), comando (`nai_comando_tel`), conferência (`nai_conferir_resposta`), identidade (`nai_contato_de`) e o CRM (`crm_nay_parar`, `crm_nay_voltar`). **8 partes.** |
| `nai_visita` | agenda (13 funções), cabeçalho (`nai_abrir_turno`, `nai_confirmar_envio`, `nai_pedir_ao_proprietario`, `nai_resposta_proprietario`), comando, saída (`nai_liberar_saida`) e o CRM (`crm_visita_editar`, `_excluir`, `_mudar_horario`, `_realizada`) |
| `nai_saida` | montagem (7 funções), saída (`nai_liberar_saida`, `nai_conferir_imoveis_da_saida`, `nai_conferir_texto_da_saida`), cabeçalho (`nai_confirmar_envio`, `nai_registrar_bloqueio`, `nai_followup_rodar`, `nai_fila_dos_outros_imoveis`, `nai_enviar_imoveis_para`), CRM (`crm_visita_excluir`) e os gatilhos `nai_saida_validar`/`nai_saida_imutavel`. A montagem também **apaga** linhas: `DELETE` em `nai_enfileirar_resposta_ferramentas`. |
| `nai_turno` | cabeçalho (`nai_abrir_turno`, `nai_fechar_turno`, `nai_mente_registrar`, `nai_usou_ferramenta`), conferência (`nai_conferir_resposta`), montagem (`nai_disparo_enfileirar` e `nai_checklist_enfileirar` criam turno com papel 'tel') |
| `mensagens` | n8n: "Gravar na fila" (INSERT, nos dois fluxos), "Reservar mensagens" (UPDATE de status, nos dois) e "Fechar ciclo" (fluxo antigo). Banco: `nai_abrir_turno` e `nai_fechar_turno` (status), mais os gatilhos BEFORE `mensagens_uma_vez_so` e `mensagens_espera_a_rajada`, que cancelam INSERT/UPDATE com `RETURN NULL`. Scripts: `ciclo_pendencias.py`. |
| `nai_config` | porta (`nai_ligar_regra_publico`/`desligar`), agenda (`nai_agenda_tick`), catálogo (`nai_sincronizar_grupos`), comando (`nai_comando_tel`: PARAR ATENDIMENTO). Fora do banco: o site (`PUT /api/nai/config`), `preflight_nai.sh`, `retomar_sabado.py`, `ligar_nay_20260928.sh`, `religar_envio_apos_rodada12.sh`. |
| `corretores` | agenda, cabeçalho (`nai_decidir_corretor`), catálogo (`nai_sincronizar_grupos`), identidade (`nay_sincronizar_nome`), a ferramenta "guardar_dados_do_corretor" do fluxo antigo (INSERT ... ON CONFLICT) e `publicador.py` |
| `pendencias` | cabeçalho (`nai_sec_perguntar_ao_tel`), comando (`nay_comando`, `nay_responder_pendencia`), ferramenta (`nay_escalar`, `nai_escalar_link_de_catalogo`) |
| `imovel_enviado_no_dia` | cabeçalho (`nai_confirmar_envio`), catálogo (`nai_disparo_liberar`), ferramenta (`nay_reservar_imovel_do_dia`, `nay_liberar_imovel_do_dia`, chamadas pelo publicador) |
| `nai_memoria` | os 4 nós de memória do n8n ("Memória (corretor/proprietário/Fernando/secretária)"), `nai_zerar_conversa` (renomeia a sessão para `arquivo-...`), `nai_treino_semear_memoria` (DELETE e INSERT) e `nai_treino_conversa.py` |
| `envios` / `mensagem_saida` | `nai_confirmar_envio` (NAI), o nó "Registrar saida" do fluxo antigo, e `publicador.py` e `entregar_pendentes.py` (só `envios`) |

Com 2 setores cada: `lembrete`, `identidade_lid`, `escalacoes`, `nai_lembrete`, `resposta_a_entregar`, `entrega_pendente`, `captacao_leads`, `nai_corretor_pergunta`, `nai_acesso_imovel`, `nai_turno_decisao`, `imovel_fotos`, `aviso_de_saida` e `nai_imovel_novo`.

**Já causou conflito real? Sim, pelo menos 8 vezes documentadas.**

1. **`nai_contato.humano_assumiu_em`** tem 7 escritores e 3 setores mais o CRM. O eco dos envios do publicador era lido por `nai_tel_assumiu` como "o Tel digitou". Resultado: 285 envios viraram "Tel assumiu", 87 contatos foram carimbados em 3 dias e a Nay ficou calada 30 min depois de cada envio. Corrigido na 134 (27/09) com `saida_do_sistema`. Hoje `tel_assumiu` ainda é o motivo de bloqueio mais frequente: 385 em 7 dias.
2. **`nai_estado_conversa.codigo_foco`**: `nai_estado_gravar_v2` é chamada de dois lugares (`nai_decidir_v2` e `nai_enfileirar_resposta_ferramentas`). Um código inventado pelo modelo estourou a FK dentro de "Enfileirar resposta", e 12 respostas sumiram em 27 e 28/09 (140).
3. **`nai_saida`**: a montagem enfileirou card e 6 fotos do Park Golf, e a conferência da saída apagou as 7 linhas com "tipo errado: ele pediu sala". Ele nunca pediu sala. Aconteceu em 24/09, cabeçalho do arquivo 120.
4. **`mensagens`**: a reentrega da Z-API e o repasse do fluxo antigo gravavam a mesma mensagem duas vezes. Em 14 dias, 205 textos e 42 áudios foram atendidos pelos dois fluxos (133, 27/09). Depois veio a rajada: a execução de uma mensagem antiga deixava a mais nova sair sozinha (147, 28/09).
5. **`corretores.nome`**: `nay_sincronizar_nome` ("Gravar na fila") apagava o nome que a ferramenta "guardar_dados_do_corretor" gravava, e ela perguntava o nome para sempre. O conserto foi `nome_origem='manual'`, registrado em `Arquivos/CLAUDE.md`.
6. **`nai_config.envio_simulado`**: `preflight_nai.sh` deixava `'nao'` no fim, o que ligaria o WhatsApp de verdade. Foi corrigido em 22/09 para devolver o valor anterior. O risco continua, e está explicado na 50.
7. **`nai_memoria`**: `nai_treino_semear_memoria` gravava num formato diferente do n8n (`data.content` aninhado), e as 49 conversas do ciclo 1 de treino rodaram sem memória. Está escrito no cabeçalho de `/root/nai_rodada_bloco.py`.
8. **`nai_imovel_novo`** (cadastro) governando a decisão: a ficha aberta mandava tudo para a secretária por 24h (121, 24/09). Aqui a mesma tabela é escrita pelo cadastro e lida pelo roteador.

---

## BLOCO 10: COMO MUDA E COMO TESTA

### 50. Como uma mudança chega em produção hoje

**Quem aplica.** Quase sempre é o assistente de código (Claude Code), via `ssh` como root no srv1894338, a pedido do Tel ou do Pedro no chat. As evidências:
- 45 dos 51 commits trazem "Co-Authored-By: Claude";
- `nai_prompt_historico.salvo_por` registra "Claude 28/09: ...";
- as memórias registram "com aprovação do usuário".

Não existe revisão por outra pessoa, nem CI (não há `.github`), nem portão automático.

**Não existe tabela de migrações.** Procurei `relname ~ 'migra|schema_version|aplicad|flyway|liquibase|versao'` em todos os schemas e o resultado foi zero. O único registro versionado de verdade é `nai_prompt_historico`. O n8n guarda **uma** versão por workflow em `workflow_history`: a do NAI é de 28/09 15:34 UTC, com autor "import".

**Regra ou função nova (SQL).** São dois jeitos em uso:

1. **Arquivo inteiro.** `Arquivos/nai/NNN_nome.sql` com `\set ON_ERROR_STOP on`, `BEGIN; SET LOCAL lock_timeout = '5s'; CREATE OR REPLACE ...; COMMIT;`. O arquivo é copiado para o servidor (`/root`, `/root/v147/` ou `/tmp`, onde há 960 `.sql` soltos) e aplicado com `docker exec -i nay-postgres psql -U nay -d naydb -v ON_ERROR_STOP=1 < arquivo`.
2. **"Remendo" sobre a função viva**, o jeito de 190 e 191. Um Python (`190_remendos.py`, `191_remendos.py`, `190c_casos.py`, `montar124b.py`) roda `pg_get_functiondef` na função viva, troca um trecho-âncora (e aborta se a âncora não aparecer exatamente uma vez) e gera `NNNp_remendos.sql`, que então é aplicado. Assim não se reaplica arquivo velho, porque o banco está à frente.

O que é conferido antes, quando é conferido:
- **Ensaio** com o mesmo SQL entre `BEGIN ... ROLLBACK`, com contatos falsos (número inexistente terminado em …009x) e `SELECT nai_rodar_casos()` no fim. Exemplos: `/root/v147/ensaio152.sql` e `/tmp/ensaio_191_tudo.sql` (29/09 22:17 UTC).
- Em alguns casos, um wrapper que mede antes e depois na mesma sessão: `/root/aplicar173.sh`, e `/root/ensaio169.sh` para as `crm_visita_*`.
- Desde 28/09 a regra é "DDL num arquivo curto, separado; ensaio só de função com `statement_timeout`". Um ensaio com `ALTER TABLE` travou a Nay por 2 min.

Nada disso é obrigatório nem registrado.

**Parte do que está no ar não está em arquivo nenhum do repositório:**
- 41 das 415 funções do inventário não têm definição em nenhum dos 452 `.sql` do repositório; (o bloco 8 comparou também com o repositório do publicador e com SQL embutido em `.py`/`.js`, e por isso chega a 19 só no banco: os dois números estão certos, cada um no seu recorte)
- outras 11 têm definição, mas com corpo diferente do vivo;
- a arquitetura "v2" de 25/09 (`nai_decidir_v2`, `nai_estado_v2` e o resto) só existe em `/tmp` no servidor;
- as 80 migrações de 125 a 191 entraram de uma vez no commit "llsss" de 29/09.

**Prompt novo.** O texto mora em `nai_prompt`: 5 papéis, com corretor na v16, captação na v6, e proprietário, motoboy e secretária na v1. `nai_abrir_turno` lê o prompt a cada mensagem por `nai_prompt_de(papel)` e o devolve em `cab.prompt`. O nó agente usa esse texto como `systemMessage` e lança `PROMPT_VAZIO` se ele tiver menos de 500 chars; na secretária o limite é 300, via "Decidir quem responde". A troca vale na mensagem seguinte, sem deploy.

A escrita passa por `nai_salvar_prompt(papel, texto, versao, por)`, que tem trava otimista de versão e guarda o texto antigo em `nai_prompt_historico`. Há três caminhos até ela:
1. o painel, com `PUT /api/nai/prompt/<papel>` no `nay-site-api`;
2. uma migração que chama `nai_salvar_prompt` (82, 85, 90, 91, 94, 95, 97, 99b...);
3. uma chamada direta, sem arquivo: as versões 14 e 15 do corretor, "Claude 28/09", não aparecem em nenhum arquivo do repositório nem do servidor.

As migrações antigas 16, 46, 49b, 52, 56b e 63b faziam `UPDATE nai_prompt` direto e **pularam o histórico**. Antes de salvar um prompt, nada é conferido além da trava de versão e do texto vazio.

**Alerta de segurança, que é fato de código e não teste meu.** As rotas `PUT /api/nai/config`, que mexe em `modo`, `pausada`, `envio_simulado`, `numeros_teste` e outras chaves, e `PUT /api/nai/prompt/<papel>` não passam pela guarda `_captacao_exige_senha`, que só cobre os prefixos da captação. O host `api.imobeasy.online` não tem middleware de autenticação nas labels do traefik; só o `/admin/api` tem. Não chamei essas rotas.

**Nó novo no n8n.** O ciclo é este:
1. Exporta o fluxo vivo.
2. Um script edita o JSON: `montar*.py` (por exemplo `montar_fluxo_mente_e_secretaria.py` e `montar_fluxo_jev.py`) ou `patch_*.js`.
3. Os nós são provados fora do fluxo, com o Node do container: `provar_nos_da_nai.js`, `provar_nos_do_envio.js`, `teste_*.js` e `node --check`.
4. Backup em `/root/backups-n8n/` (145 arquivos, 28 do NAI).
5. `n8n import:workflow`, que **desativa** o fluxo, seguido de `n8n update:workflow --id=... --active=true` e `docker stop -t 40` com `docker start`.
6. Confere o log "Activated workflow" e um POST que responda 200.

O container do n8n subiu pela última vez em 28/09 19:38 UTC. Entre o import e o restart a Nay não recebe nada.

**O pré-voo, `/root/preflight_nai.sh` (lido, não rodado).** Ele manda 7 mensagens ao webhook como o número de teste …2835, com 42 s entre elas. Liga `envio_simulado='sim'` **globalmente** durante cerca de 5 min e devolve o valor anterior no fim. O último log é `preflight_22-09.log`, de 22/09.

**[OPINIÃO baseada no código]** Com a Nay no ar para todos (`modo=todos`, `envio_simulado=nao`), rodar o pré-voo faria **toda** resposta real desses 5 minutos virar `simulado` e nunca sair, porque `nai_liberar_saida` lê `envio_simulado` como trava geral. Hoje ele não serve como checagem de produção.

**`rodar_testes.sh`** (em `Arquivos/` e em `/root/nay-publicador`) roda:
- as suítes Python e JS;
- com `--com-banco`, também os `teste_*.sql` de `Arquivos/`;
- a checagem de deriva do `nay_comando`;
- a checagem do `REGRAS-E-BUGS.md`.

Ele **não** pega `Arquivos/nai/teste_nai.sql` nem `teste_64_trace.sql`, porque o glob é da pasta `Arquivos/`, e não testa o fluxo NAI. É rodado à mão e não guarda resultado.

### 51. `nai_rodar_casos`: o que cobre, como cresce, quando rodou, o que não testa

**A premissa está errada: não são 15 casos. `nai_caso` tem 60 linhas, todas ativas.** São 43 de 24/09 e 17 de 29/09. As colunas são `id`, `quando`, `quem`, `frase`, `pergunta`, `esperado`, `regra` e `ativo`. `quem` diz a origem, com o corretor pelo primeiro nome e a data (por exemplo "Park Golf 24/09", "Rodada 9", "corpus 14d", "regra 191").

**Como roda.** A versão viva é uma plpgsql `STABLE`. Ela percorre `nai_caso WHERE ativo` e, conforme `pergunta` (21 valores), chama **uma** função classificadora pura com `frase`. Em seguida compara o resultado com `esperado` por igualdade de texto e devolve `(passou, regra, frase, esperado, deu)`. **Não escreve nada.** Rodei agora (29/09, por volta das 19:30 de Manaus) dentro da transação só leitura do `q.sh`: **60 de 60 passaram**, em 1,1 s.

**O que os 60 cobrem, por tema.** Todos testam classificação de texto, frase por frase:

| tema | perguntas | casos |
|---|---|---|
| O que ele procura: tipo, negócio, valor | `tipo` 9, `tipo_canon` 1, `negocio` 2, `negocio_valor` 3, `tipo_conversa` 3, `negocio_conversa` 2 (conversa passada como "fala1 \|\| fala2") | 20 |
| Quem responde: imóveis x secretária, cola do cadastro | `catalogo` 6, `anuncio` 3, `oferta` 2, `cortesia` 2, `de_imovel` 1, `link` 1 | 15 |
| Afirmações sensíveis conferidas com a ficha (191) | `afirma_pagamento` 5, `assunto_sensivel` 4 | 9 |
| Quais imóveis ele apontou e o "passe" na conferência | `imoveis` 4, `passe` 3, `pelo_nome` 1 | 8 |
| Texto: corretor de nomes do áudio, texto sem barrados | `nomes` 5, `texto_limpo` 1 | 6 |
| Pedido de lista, sem preferência de bairro | `pede_lista` 1, `sem_bairro` 1 | 2 |

**Como um caso novo entra.** Um `INSERT INTO nai_caso (quando, quem, frase, pergunta, esperado, regra, ativo)` dentro da migração do conserto (120, 120c a 120f, 121, 190c e 191p). Se o caso precisar de um tipo novo de pergunta, a própria `nai_rodar_casos` ganha um `WHEN` novo por remendo: `190c_casos.py` troca a âncora `WHEN 'valor'` na função viva. O combinado registrado na memória é "rodar antes e depois de mexer".

**Quando rodou pela última vez: não há registro no banco.** Não existe tabela de resultado nem coluna de último resultado, e `track_functions` e `log_statement` estão em `none`. Os rastros que existem são arquivos no servidor:
- `/root/casos_antes_168.txt`, de 29/09 13:26 UTC: 43 de 43 com "t";
- `/tmp/ensaio_191_tudo.sql`, de 29/09 22:17 UTC, que contém o `SELECT count(*) FILTER (WHERE passou)...`. A data do arquivo não prova o resultado.

A rodada verificável mais recente é a minha, com 60 de 60.

**O que ela não consegue testar:**
- o n8n: nós, "Juntar mensagens", janela de 20 s, rotas, memória;
- o modelo `gpt-5.6-sol` e o que ele responde, as ferramentas que escolhe e o prompt;
- o Jev e a mente de ponta a ponta. Ela testa as peças `nai_e_so_cortesia`, `nai_pergunta_de_catalogo` e similares, não `nai_decidir_com_jev` nem `nai_mente_registrar`;
- a esteira inteira: `nai_conferir_resposta`, `nai_enfileirar_*`, `nai_liberar_saida` e os gatilhos;
- a Z-API: envio, ordem de entrega, eco, 502, reenvio;
- o tempo: janela, travas de 24h, horário, lembretes, agenda e visita;
- comandos, mídia (áudio e imagem) e identidade (@lid);
- conversa longa: fora `tipo_conversa` e `negocio_conversa`, é tudo frase solta.

Ela também não é imune ao catálogo. `pelo_nome` usa `nai_imovel_pelo_condominio` e `nomes` usa o vocabulário tirado de `imoveis`, então um imóvel que sai do ar pode derrubar caso sem mudança de código. Já aconteceu com a bateria antiga em 15/09.

### 52. Replay de turno antigo e o contato-espelho

**Replay exato de um turno antigo, sem enviar nada, não existe.** O que existe é re-mandar o **texto** de turnos antigos pelo fluxo de hoje, como se viesse de um contato falso.

**O espelho.** A configuração é esta:
- `nai_config.treino_espelho` = …0001 (número inexistente, fora do WhatsApp);
- `nai_config.numeros_teste` = …2835 e …0001;
- `nai_chaves_teste()` devolve a chave desses dois números.

O que protege:
- `nai_liberar_saida` marca `simulado`, sem chamar a Z-API, em toda linha cujo destino seja o espelho **ou** que nasça de um turno ou visita do espelho (migrações 92, 113b e 141). Isso vale mesmo com a Nay no ar e `envio_simulado='nao'`.
- `nai_deve_atender`, `nai_abrir_turno`, `nai_quem_atende` e `nai_janela_segundos` isentam as chaves de teste: janela de 15 s (`janela_segundos_teste`) e passagem pela lista curta.
- No CRM, `ehEspelhoDeTreino` impede lead falso.

**O caminho do treino.**
1. `nai_treino_montar_ciclo(n)` pega os N turnos mais recentes de `nai_treino_pool`: papel corretor, texto não vazio, com saída, ainda não usados.
2. Cada turno vira linha em `nai_treino_caso` com `turno_origem`, `ele_disse` (= `nai_turno.texto`), `ela_respondeu_antes` e `contexto`, sendo o contexto as 10 falas anteriores, via `nai_treino_contexto`.
3. `/root/nai_treino_rodar.py` faz POST no webhook interno do n8n como o espelho.
4. `nai_treino_colher` guarda `ela_respondeu_agora` e `ferramentas_agora`.

Esse script aceita rodar com a Nay no ar: ele confere que `nai_liberar_saida` contém "ESPELHO DO TREINO NUNCA SAI" e que `pausada='nao'`. Já `/root/nai_rodada_bloco.py`, que reproduz a conversa inteira bloco a bloco, **exige `envio_simulado='sim'` global**. Com a Nay no ar, isso calaria todo mundo, então ele não serve hoje.

Os números do uso:
- 15 ciclos, 567 casos;
- 2 rodadas de bloco com 227 blocos: 65 rodados, 137 em erro, 25 pendentes;
- 698 turnos do espelho, o último em **27/09 02:30**;
- **nenhum replay desde que a Nay foi ao ar**, em 28/09 07:00.

**O que o replay cobre.** O fluxo real de ponta a ponta com o que está no ar hoje: webhook, n8n, mente e Jev, agente com o prompt e o modelo atuais, ferramentas e SQL delas, esteira e `nai_saida` com o texto final e o motivo de cada bloqueio. É bom para "o que ela responderia hoje a isto".

**O que ele não cobre:**
- **A pessoa original.** O espelho é outro `nai_contato`, com outro estado (`nai_estado_conversa`), outro histórico de envios, outras visitas, outra lista curta e outra memória: vazia, ou semeada por `nai_treino_semear_memoria`, que no ciclo 1 gravou no formato errado.
- **O momento original.** O envelope usa `$now`, e o catálogo, `nai_config` e o prompt são os de hoje.
- **A mídia.** O pool leva `nai_turno.texto`; áudio e imagem não são reenviados.
- **A Z-API.** Nada sai, então ordem de entrega, eco, "Tel assumiu", 502 e atraso não são exercitados.
- **A trava de 24h das fotos.** Rodada repetida em menos de 24h sai sem fotos (21/09).
- **O determinismo do modelo.** A mesma entrada não garante a mesma saída.
- **Os papéis de proprietário e Fernando.** Só parcialmente, desde a 141.

Para captação há outro mecanismo: `simular.sh` na VPS2, com modelo e prompt vivos, banco numa transação desfeita e nada enviado. Ele não serve para a Nay de locação.

### 53. O trace (64)

**Ligado na configuração, desligado na prática.** `nai_config.trace_nivel='completo'`, `trace_payload='sim'` e `trace_dias='30'`, as três com `atualizado_em` de 19/09 15:31:42, quando o arquivo 64 foi aplicado. Mesmo assim, `nai_evento` tem **1 linha**: o teste de instalação, setor entrada, etapa "instalacao", 19/09 15:31.

**Por que não grava.** O "passo 5", os nós do n8n que chamariam `nai_tracar_entrada`, `_cabecalho`, `_modelo`, `_ferramenta` e `_erro`, **nunca foi feito**:
- zero ocorrências de "tracar" nos 12 workflows de produção, nos 3 da VPS2, nos backups de `/root/backups-n8n` e no código do CRM e do site;
- nenhuma função do banco chama `nai_tracar`, a não ser os próprios atalhos `nai_tracar_*`;
- o commit `ed70c6d` diz com todas as letras: "Enquanto os nós de trace do n8n não forem instalados (passo 5)...".

As consequências:
- `nai_turno.exec_id`, `prompt_versao`, `modelo` e `ms_total` estão **vazios nos 3.437 turnos**, porque só os atalhos do trace os preencheriam;
- `vw_nai_setor_saude` só tem dado em "conferencia" e "saida", e os outros 10 setores ficam "cinza";
- `nai_trilha(turno)` funciona, mas devolve só `nai_conferencia` e `nai_saida`.

**O que o trace gravaria por turno, se estivesse ligado:**
- uma linha por etapa: setor, etapa, resultado (ok/mudou/cortou/parou/erro), ms, entrada e saída em jsonb mascarado, `exec_id` do n8n;
- o texto cru do modelo, com nomes das ferramentas e tokens;
- a versão do prompt e o contexto;
- os argumentos e o resultado de cada ferramenta;
- o payload da Z-API.

**O que existe hoje para reconstruir um turno de duas semanas atrás.** Pegando 15 e 16/09:

- **`nai_turno`**: contato, papel, texto juntado, `msg_ids`, `codigo`, `ferramentas` (só os nomes), `porta` (texto do porteiro), criado e fechado. Há 231 turnos de 15/09.

  Os ids de 15/09 vão de 3511 a 6126: 2.616 ids para 231 linhas. No geral são 12.614 ids emitidos para 3.437 linhas. **NÃO SEI** se a diferença são turnos apagados ou ids queimados por transações desfeitas (ensaios e baterias fazem INSERT e ROLLBACK). Para saber, precisaria de log de statements, que está desligado. O que sei com certeza: 164 turnos órfãos de 19 a 25/09 foram copiados para `nai_turno_orfaos_bkp_20260925` e saíram da tabela.

- **`mensagens`**: o que chegou (texto, `audio_url`, `midia_url`, `message_id`, `status`) e o eco do que saiu (`direcao='enviada'`).

- **`nai_conferencia`** (desde 14/09 16:38): etapa, resultado e um `detalhe` curto. Não tem o texto de antes e depois da correção.

- **`nai_saida`**: cada linha da caixa com o **texto final depois da esteira**, imagem, código, motivo, estado, bloqueio, `enviado_em`, `message_id` e a resposta da Z-API.

- **`nai_memoria`**: é o achado que corrige a premissa. A memória do n8n guarda:
  - a mensagem "human" com o envelope inteiro que o agente recebeu (hora, vocativo, avisos do cabeçalho, contexto);
  - as `tool_calls` **com os argumentos**;
  - o resultado de cada ferramenta (`texto_pronto` e `instrucao_para_voce`);
  - a **resposta crua do agente**, antes da esteira.

  Não tem timestamp nem `turno_id`, então o alinhamento é pela ordem do `id` e pela linha "agora em Manaus é ..." do envelope. Ao zerar a conversa, a sessão é renomeada para `arquivo-...` e não apagada: há 7.340 linhas arquivadas e 1.830 vivas.

  Exemplo real: o **turno 6141** (16/09 08:05:35, corretora Martinha, "Pode me encaminhar esse por gentileza", marcando o 5717) aparece em `nai_memoria` ids 929 a 932:
  - envelope de 807 chars, com "ele MARCOU a mensagem do imovel 5717" e "voces JA ESTAO CONVERSANDO";
  - `imovel_por_codigo {"codigo":"5717"}`;
  - o card devolvido pela ferramenta;
  - a resposta crua (card + "A Sra. quer as fotos?").

  Esse texto bate com as 2 linhas `enviado` de `nai_saida` às 08:05:44. A conferência registrou só `imovel_da_conversa mudou`.

- **`nai_prompt_historico`**: dá para saber qual texto **estava vigente** no horário. O histórico guarda o texto antigo no momento da troca: em 15/09 à tarde valia a v3, que foi substituída em 19/09 17:44.

- **Backups do fluxo** em `/root/backups-n8n`. O mais próximo é `bk_20260915_1809_nai_antes_porta.json`: modelo `gpt-5.6-sol`, memória de 40 mensagens (hoje o corretor usa 20).

- **Não existem para 15/09**: `nai_mente` (desde 22/09), `nai_jev` (desde 24/09) e `nai_turno_decisao` com `jev_bruto` (desde 25/09).

- **Execuções do n8n**: só as de hoje, desde 29/09 por volta das 13:57 de Manaus. O limite é `EXECUTIONS_DATA_PRUNE_MAX_COUNT=2000` com `MAX_AGE=72h`, e o limite de contagem ganha: cerca de 5 a 6 horas de histórico.

**O que NÃO dá para reconstruir de um turno de 15/09:**
- **O prompt exato usado.** Dá para inferir pelo horário em `nai_prompt_historico`, mas sem prova: em 15/09 o nó era `cab.prompt || "texto de reserva"`, e nada registra se usou o do banco ou a reserva. `nai_turno.prompt_versao` está vazio.
- **Descrições das ferramentas e código dos nós naquele minuto.** Só o backup mais próximo, e os backups são irregulares.
- **Os valores de `nai_config` naquele momento.** Não há histórico: `modo`, `pausada`, `envio_simulado` e `numeros_teste` só têm o valor atual e o `atualizado_em`. O mesmo vale para os estados sobrescritos: `nai_estado_conversa`, `nai_contato.humano_assumiu_em` e `visita_sugerida_em`.
- **A entrada e a saída de cada nó do n8n**, os tempos, os erros de nó e qual execução gerou o turno. `exec_id` está vazio e as execuções foram apagadas.
- **Modelo, tokens e latência do turno.** `modelo` e `ms_total` estão vazios.
- **A ligação direta memória–turno** e a janela exata de memória carregada. Dá para inferir, sem certeza.
- **A decisão de roteamento.** A mente e o Jev não existiam em 15/09. Nos turnos de 15/09 sem resposta, o porquê fica só em `nai_turno.porta`:
  - 105 dos 179 turnos reais daquele dia dizem "conversa que ja existia: quem responde e o Tel";
  - 23 têm `porta` nula, sem motivo registrado;
  - só 15 dos 179 têm linhas em `nai_conferencia`.
- **O estado do catálogo naquele momento.** Só parcial, por `imovel_situacao_log` e `imoveis_admin_snapshot`; não conferi a cobertura dessas tabelas.

Resumo honesto: **a resposta crua, os argumentos das ferramentas e o contexto que foi no `text` dá para reconstruir, porque estão em `nai_memoria`, por alinhamento manual. O prompt e a configuração vigentes, a execução do n8n e o porquê de um silêncio, não.**

---

## BLOCO 11: INFRA E NÚMEROS

Tudo abaixo foi medido em 29/09/2026 entre 19:10 e 19:40 (Manaus), só leitura, no servidor srv1894338 (`ssh nay-srv1894338`), no `naydb` (psql, fuso já em Manaus), no sqlite do n8n de produção e no n8n da VPS2 (`ssh nay-srv1877774`, só leitura). O relógio do host é UTC; o crontab está em UTC, e eu converti para Manaus (UTC-4) onde digo "Manaus".

### 54. Backup do Postgres

**A premissa da pergunta se confirma em parte.** O backup automático do `naydb` existe. Ele nasceu em 02/09, segundo o cabeçalho do script. Duas coisas, porém, NÃO têm backup automático nenhum: o banco do CRM (`crmdb`) e o sqlite do n8n.

**naydb: existe, diário, só local.**
- FATO (crontab do root): `5 3 * * *` UTC, ou seja, **todo dia às 23:05 de Manaus**, com `flock` e log em `/root/nay-publicador/logs/backup_banco.log`. O cron chama `/root/nay-publicador/backup_banco.sh`.
- FATO (script): o script roda `docker exec nay-postgres pg_dump -U nay -d naydb -Fc` e grava em `/root/backups-banco/naydb-AAAAMMDD-HHMM.dump`. Depois ele confere o dump com `pg_restore --list`: se vierem menos de 25 `TABLE DATA`, o arquivo é descartado e o anterior fica valendo. A retenção é de 14 dias (`find -mtime +14 -delete`), e por isso ficam 15 arquivos. Ao terminar bem, o script toca o batimento `logs/.batimento_backup_banco`, que o `alarme_crons.py` lê com folga de 26 h (sobre isso, veja a 55).
- **Último backup:** `naydb-20260928-2305.dump`, **12.592.580 bytes (12 MB)**, gravado em **28/09 23:05:06 (Manaus)**. Linha do log: `backup OK -- 150 tabelas, 13M, 15 cópia(s) guardada(s)`. O próximo roda hoje, 29/09, às 23:05. O mais antigo guardado é o `naydb-20260914-2305.dump`, com 3,1 MB. A pasta inteira ocupa 82 MB. O dump quadruplicou em 14 dias (3,1 para 12,6 MB). Nenhum erro no log.
- **Onde fica:** no MESMO servidor e no MESMO disco (`/dev/sda1`, 96 GB, 80% usado, 20 GB livres) do volume `postgres_nay_pgdata` (169 MB). **Não existe cópia para fora do servidor.** Não há `rclone`, `restic`, `borg`, `aws` nem `s3cmd` instalados, e nenhum script de cron ou de `/root` usa `rsync`/`scp`/S3. O único arquivo que casou no grep, `teste_captacao_fotos.py`, é um teste e não faz cópia. Perder a VPS significa perder o banco e os backups juntos.
- **Snapshot da Hostinger:** NÃO SEI. Por dentro não há indício. O `qemu-guest-agent` rodando só mostra que é VM da Hostinger. Para saber, é preciso olhar o hPanel, em VPS, Snapshots/Backups.
- **Teste de restauração:** NÃO SEI se alguém já restaurou um desses dumps. O script só lê a lista de tabelas. O comando de restauração está comentado no cabeçalho do script.
- Dumps manuais avulsos: `/root/backups/naydb_antes_trace_20260919_1829.dump` (3,8 MB), `/root/imoveis_backup_pre_sincronizacao.sql` e `/root/nay_escalar_backup.sql`.

**A captação (VPS2) usa o mesmo Postgres.** FATO: o `tailscaled` do srv1894338 escuta em `100.86.114.74:5432`, e o `tailscale status` mostra `srv1877774 active; direct`. A credencial "Banco Nay" da VPS2 aponta para esse endereço (segundo a memória migracao-captacao-vps2; não abri a credencial). As tabelas `captacao_*` moram no `naydb` (consultei `captacao_mensagens` direto nele) e **entram no dump diário**.

**crmdb: NÃO EXISTE backup automático.** FATO: o container `nay-postgres` tem três bancos: `naydb` (99 MB), `crmdb` (14 MB, usado pelo `crm-imobeasy` com o usuário `crm`) e `postgres`. O `backup_banco.sh` faz dump só de `-d naydb`. Em `/root/backups-crm` só há `.tgz` de código-fonte (`antes_3_linhas_…tgz` lista `src/lib/*.ts`, sem nenhum `.sql` ou dump). A mídia do CRM, `/docker/crm/midia` com 559 MB, também não tem backup.

**sqlite do n8n de produção: NÃO EXISTE backup automático.** O arquivo `/var/lib/docker/volumes/n8n-viux_n8n_data/_data/database.sqlite` tem 736 MB, mais um WAL de 5,5 MB. O que existe é manual:
- a cópia inteira `/root/backups-n8n/sqlite_20260925_0413.sqlite` (1,5 GB, 25/09 ~00:13 Manaus);
- a pasta `/root/backups/n8n_data-20260909-025155` (09/09);
- 145 itens em `/root/backups-n8n`, JSONs exportados à mão antes de cada mudança. O último do NAI é o `bk_20260928_NaiAtendLocacao1_antes_janela20.json` (28/09 11:27 Manaus).

Os fluxos do n8n não estão no git: o repositório não tem export de workflow. As credenciais do n8n, cifradas no sqlite com a chave em `/home/node/.n8n/config`, só existem na cópia manual de 25/09.

**n8n da VPS2 (captação): NÃO EXISTE backup automático.** O sqlite `n8n-captacao_n8n_data/_data/database.sqlite` tem 678 MB. O crontab da VPS2 tem só `0 9 * * * lembrete_groq.sh` e um `monitor_stall.sh` comentado. As cópias manuais dos fluxos estão em `/root/n8n-captacao/fluxos/` (a última é de 28/09 23:14 UTC).

### 55. Como o Tel é avisado quando algo quebra

Hoje existem três avisos de infraestrutura e um indicador visual. Nenhum deles vigia o n8n parado, o container morto, a Z-API desconectada ou a "Nay calada por lógica".

**1. Fluxo n8n "Nay - alarme de erro" (id `4NJbiUC7P5W2BvJH`, ativo).** São quatro nós: "Quando a Nay falhar" (errorTrigger), "Montar aviso", "Avisar o Tel" e "Avisar no Telegram".
- "Avisar o Tel" faz um POST na URL da Z-API (instância omitida) com `phone: '559294717316'`, número fixo no nó. É o Tel, 92 9471-7316, o mesmo de `nai_config.tel_telefone`. A mensagem sai pela própria instância Z-API da Nay: o eco dela aparece em `mensagens` com `direcao='enviada'`. O token do cabeçalho está escrito no nó (não transcrevo).
- "Avisar no Telegram" manda o mesmo texto pelo bot "alarme Easy IA" ao chat "Tel Sobreira".
- O texto é `A Nay falhou / Fluxo / No / Erro / Execucao`. O erro usa `execution.error.message`, não o `description`.
- FATO (sqlite, `workflow_entity.settings`): o fluxo é `errorWorkflow` **só** de "Nay- recebe mensagem" e de "NAI atendimento locação". "Nay - escalar" e "Nay - responder pendencia" não têm. **O n8n da VPS2 (captação) não tem fluxo de alarme nem `errorWorkflow`** em nenhum dos três fluxos.
- Limites (FATO pelo desenho do n8n e pelo histórico):
  - só dispara quando uma execução termina em `error`;
  - não vê o nó HTTP que devolve erro no item com a execução em "success" (é o caso do 502 da Z-API);
  - não vê webhook que parou de chegar nem n8n fora do ar;
  - não tem trava de repetição: foram 48 avisos em 16/09, 32 em 27/09 e 28 em 29/09;
  - não manda ao segundo número do Tel (…6408).

**2. Alarmes Python no host: `alarme_crons.py` e `alarme_varredura.py` (em `/root/nay-publicador`).** Os dois mandam pela Z-API (`enviar_zapi.enviar_texto`) a todos os números de `TEL_WHATSAPP` do `.env`, que hoje são dois (`tel_whatsapp.enviar_ao_tel`). Cada um avisa no máximo uma vez a cada 24 h; o carimbo fica em `config.crons_alarme_em` e em `config.varredura_alarme_em`.
- `alarme_crons.py` olha a idade dos arquivos `logs/.batimento_<cron>` de 8 crons:
  - folga de 15 min: `disparar_grade`, `disparar_lembretes`, `entregar_pendentes`, `ciclo_pendencias`, `alertar_visitas` e `detectar_visitas`;
  - `sincronizar_catalogo`: 70 min;
  - `backup_banco`: 26 h.
- `alarme_varredura.py` avisa quando `config.varredura_rodou_em` passa de 3 h.
- **Nenhum dos dois está no crontab.** FATO (grep em todos os `.sh`): os dois só são chamados dentro de `sincronizar_catalogo.sh` (função `alarmar`). Esse wrapper hoje roda **uma vez por dia**, às 05:17 de Manaus (`17 9 * * *` UTC). Na prática, um cron de minuto que morrer às 06:00 só é avisado no dia seguinte, perto das 05:20. Se a linha da varredura sair do crontab, os dois alarmes param junto.
- Divergências entre comentário e código (FATO):
  - `alarme_crons.py:63` diz "quem o le sao os crons de minuto em minuto", o que é falso;
  - `sincronizar_grupos_corretores.sh:9` diz que o `alarme_crons.py` mede o batimento dele com folga de 8 dias, mas esse cron **não está** no dicionário `CRONS`;
  - também ficam sem vigia `avisar_saidas`, `sincronizar_etapas_crm`, `catalogar_postados`, `ficha_do_anuncio`, `sincronizar_agenda_xx`, `montar_colagens`, `nai_vocabulario_atualizar` e os crons do CRM.
- O último aviso de cron foi em 23/09 20:11 (`config.crons_alarme_em = 2026-09-23T20:11:35`; `mensagens.id` 19657: "Tem cron parado no servidor da Nay: • a varredura do catálogo — nunca rodou"). O `varredura_alarme_em` está zerado em 2020-01-01.

**3. Avisos de negócio da própria Nay, que não são de infraestrutura.** `nai_avisar_tel(p_turno, p_visita, p_texto, p_motivo)` enfileira em `nai_saida` com `papel_destino='tel'`. Ela é chamada por 23 funções: `nai_escalar`, `nai_agenda_tick`, `nai_pedir_visita`, `nai_sec_perguntar_ao_tel` etc. Os motivos são `duvida_fora_da_base`, `midia_para_o_tel`, `urgente`, `expirada`, `sem_proprietario`, `aprovacao_sem_resposta`… Some-se o `ciclo_pendencias.py`, que cobra do Tel as pendências abertas ("Responda com RESPOSTA <número> <texto>"). Nada disso fala de falha de sistema. Não existe aviso de "processando preso" nem de fila parada: procurei em `pg_proc` e nos `.py` do publicador e não achei.

**4. CRM, só visual.** A `BarraDeMetricas.tsx` (commit 4695088, 29/09, no ar desde o build de 29/09 17:21) mostra "CALADA HÁ …" quando há gente esperando e a última resposta da Nay passou de 15 min. Não manda nada a ninguém: só vê quem está com o CRM aberto. O `captacao_vigiar()` é o disjuntor da captação: pausa a captação e não avisa o Tel (não chama envio nem `nai_avisar_tel`).

**Funcionou na última falha real?**

**29/09, OpenAI sem crédito (a partir de 09:51): avisou rápido, com o texto errado, e só na metade do sistema.**
- O primeiro alarme saiu às **09:52:48** (`mensagens.id` 31857: "No: NAI (corretor) / Erro: OpenAI: Rate limit reached"). Seguiram-se mais 27 até 14:36:21 (id 32515), sendo 27 de "NAI (corretor)" e 1 de "NAI (Fernando)". Cada um foi também ao Telegram. A execução do alarme 141466 mostra a Z-API devolvendo `messageId` e o Telegram `ok: true`.
- O texto dizia "Rate limit reached". A causa real estava no `description`, que o aviso não lê: "You have no credits remaining" (execução 141465, 14:15).
- A primeira resposta do GPT depois da falha é a execução **141828, às 14:48**. Foram **~5 h de Nay calada** (turnos respondidos por hora em 29/09: 36 às 09h, 0 às 10h, 2 às 11h, 2 às 12h, 0 às 13h).
- **Ninguém foi avisado da captação.** O n8n da VPS2 tem 27 execuções `error` do "Nay - captacao proprietarios" entre 10:01 e 17:28, sem `errorWorkflow`.
- A transcrição do CRM (mesma chave) também não avisou.

**28/09, Z-API 502 (14:12–14:23, segundo a memória): não avisou.**
- Não há nenhum "A Nay falhou" em `mensagens` depois das 10:21 de 28/09.
- Pelo desenho, o erro da Z-API volta no item e a execução termina "success", então o errorTrigger nunca dispara.
- Hoje não encontrei rastro do 502 em `nai_saida`: 0 linhas com `resposta ? 'tentativas'` e nenhum `estado='erro'`; só existem `enviado`, `simulado` e `bloqueado`. Por isso o detalhe do incidente fica NÃO SEI.

**28/09 07:05–10:21, FK de `nai_estado_conversa_codigo_foco_fkey` no nó "Enfileirar resposta": avisou 13 vezes,** e o problema durou 3h16. Em 27/09 a mesma falha gerou 20 avisos entre 00:23 e 02:24, e em 26/09 mais 27.

**17/09, a entrada inteira parou 39 h sem nenhum aviso.**
- FATO: `mensagens` não tem nenhuma linha entre **16/09 17:52 e 18/09 09:09**, e `nai_turno` também não tem nenhuma em 17/09.
- Nesse intervalo não há nenhum "A Nay falhou" (entre 16/09 11:41 e 21/09 09:40 não há alarmes).
- A captação, que então rodava no mesmo n8n, gravou `captacao_mensagens` às 17/09 08:02, então o n8n estava de pé.
- A causa exata é NÃO SEI. [OPINIÃO: o número ou o webhook da Nay caiu. A memória diz que o WhatsApp caiu em 17/09 por volume, mas a própria memória fala do número da captação; é o tipo de falha que nenhum dos alarmes vê.]

**Outros alarmes enviados** (texto em `mensagens`, por nó e erro):

| Data e hora (Manaus) | Nó | Erro | Avisos |
|---|---|---|---|
| 12/09 | "Enfileirar resposta" | COALESCE | 1 |
| 13/09 12:21–12:41 | "NAI (corretor)" | "Bad request" | 3 |
| 16/09 | "Comando do Tel" | timeout de 300 s | 1 |
| 16/09 11:03 – 24/09 | "Janela de 25s" | "possible out-of-memory" | 34 |
| 16/09 11:32–11:41 | "Abrir turno" | `bigint: "chatcmpl-…"` | 19 |
| 21/09 – 22/09 | "NAI (corretor)" | "Service unavailable" | 3 |
| 25/09 08:57 | "Decidir quem responde" e "Resposta da secretária" | "out-of-memory" | 22 |
| 25/09 | "O Tel assumiu a conversa" | SQLITE_BUSY | 2 |
| 25/09 | "Espelhar no CRM" | Timeout do mutex do sqlite | 2 |

Não há watchdog de container: os 9 containers têm `restart=unless-stopped` e nenhum healthcheck.

**Veredito.** [OPINIÃO] Para erro de nó do n8n nos dois fluxos da VPS1, o aviso chega em 1–2 minutos, mas em rajada e às vezes com a causa errada. Para todo o resto (captação, CRM, Z-API, webhook parado, n8n parado, cron morto) o Tel não é avisado, ou só é avisado no dia seguinte.

### 56. Números dos últimos 30 dias (30/08 a 29/09, 29/09 parcial até ~19:15)

**Premissa a corrigir:**
- `nai_turno` só existe desde **10/09 18:52**. Para "turnos", a janela real é de 20 dias, não de 30. Antes disso só a Nay antiga respondia, e desde 31/08 18:08 ela está pausada: `config.atendimento_pausado='sim'`.
- Custo por dia **só tem registro para o Jev** (`nai_jev.custo`). Para OpenAI não há registro nenhum.
- `nai_turno.modelo` é NULL em 3.437 de 3.437 linhas. Não há coluna de tokens.

**Critérios que usei:**
- **Turno:** uma linha de `nai_turno`, aberta por lote de mensagens de um contato. Conta também os turnos em que a porta mandou ficar calada.
- **Real:** `teste = false`. Os números de teste ficam de fora (`nai_config.numeros_teste`: …2835 do Pedro e …0001 do treino).
- **Respondido:** o turno tem pelo menos uma `nai_saida` com `estado='enviado'`.
- **Recebidas:** `mensagens.direcao='recebida'`, sem os dois números de teste.
- **Nay enviou:** `nai_saida.estado='enviado'`. Cada foto conta como uma mensagem, e entram também os envios a números de teste.
- **Avisos ao Tel:** `nai_saida` com `papel_destino='tel'`, enviado, de turno não teste.
- **Escalações:** linhas de `escalacoes` (gravadas por `nay_escalar`, chamada por `nai_escalar` e pela ferramenta `escalar_ao_tel` do fluxo antigo), sem os números de teste.

| dia | recebidas | pessoas | turnos | reais | reais corretor | reais respondidos | corretor respondidos | Nay enviou | avisos ao Tel | escalações |
|---|---|---|---|---|---|---|---|---|---|---|
| 30/08–09/09 (11 dias) | 2.953 no total (média 268) | 8–48 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 19 (14 em 01/09) |
| 10/09 | 275 | 38 | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 11/09 | 346 | 29 | 2 | 0 | 0 | 0 | 0 | 53 | 0 | 0 |
| 12/09 | 374 | 24 | 222 | 48 | 48 | 8 | 8 | 92 | 0 | 0 |
| 13/09 | 231 | 17 | 76 | 0 | 0 | 0 | 0 | 214 | 1 | 3 |
| 14/09 | 574 | 41 | 85 | 0 | 0 | 0 | 0 | 73 | 1 | 1 |
| 15/09 | 641 | 58 | 231 | 179 | 176 | 15 | 15 | 104 | 4 | 5 |
| 16/09 | 710 | 66 | 276 | 276 | 272 | 51 | 48 | 124 | 10 | 8 |
| **17/09** | **0** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 18/09 | 306 | 43 | 160 | 160 | 160 | 8 | 8 | 32 | 2 | 1 |
| 19/09 | 283 | 47 | 111 | 97 | 97 | 18 | 18 | 103 | 6 | 1 |
| 20/09 | 25 | 12 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 21/09 | 309 | 37 | 164 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 22/09 | 336 | 37 | 198 | 67 | 51 | 24 | 23 | 180 | 7 | 1 |
| 23/09 | 397 | 50 | 162 | 162 | 138 | 87 | 72 | 474 | 30 | 2 |
| 24/09 | 423 | 51 | 147 | 114 | 110 | 25 | 25 | 134 | 13 | 3 |
| 25/09 | 787 | 48 | 369 | 270 | 267 | 4 | 4 | 37 | 2 | 4 |
| 26/09 | 954 | 72 | 619 | 394 | 394 | 0 | 0 | 53 | 1 | 1 |
| 27/09 | 236 | 22 | 117 | 47 | 41 | 0 | 0 | 3 | 0 | 1 |
| 28/09 | 634 | 61 | 293 | 291 | 254 | 133 | 107 | 829 | 26 | 11 |
| 29/09 (parcial) | 520 | 69 | 197 | 197 | 173 | 110 | 92 | 660 | 28 | 6 |

**Resumo dos 20 dias com NAI (10/09–29/09), por dia:**
- **Turnos (todos):** média 171,9, mediana 161, pico 619 em 26/09.
- **Turnos reais:** média 115,1, mediana 82, pico **394 em 26/09**. Nesse dia foram 0 respondidos, porque todos caíram em "fora da lista curta de teste".
- **Turnos reais de corretor:** média 109,1, mediana 74, pico 394 em 26/09.
- **Turnos reais respondidos:** média 24,2, mediana 6, pico **133 em 28/09**.
- **Mensagens recebidas nos 31 dias:** 11.314 (média 365/dia, mediana 345, pico 954 em 26/09), de 426 telefones ou @lid distintos (média de 36 pessoas por dia, pico 72).
- **O que a Nay enviou (`nai_saida`, desde 10/09):** média 158/dia, mediana 82,5, pico 829 em 28/09.

**Antes e depois de 28/09 07:00.** A Nay foi religada para todos por `/root/ligar_nay_20260928.sh`, com `regra_publico_desde = 2026-09-28 07:00:02` e `so_estes_numeros` vazio.

| período | dias | turnos reais | reais/dia | respondidos | respondidos/dia |
|---|---|---|---|---|---|
| A: 10/09 a 22/09 13:47 (teste e treino, reais esparsos) | 12,6 | 771 | 61 | 100 | 8 |
| B: 22/09 13:47 a 25/09 18:40 (só a lista de corretores) | 3,2 | 528 | 165 | 140 | 44 |
| C: 25/09 18:40 a 28/09 07:00 (lista curta: calada para quase todos) | 2,5 | 515 | 205 | **0** | 0 |
| D: 28/09 07:00 a 29/09 19:05 (todos) | 1,5 | 488 | 325 | 243 | **162** |

Depois de religada, o pico foi às 09h (67 turnos reais). Em 29/09 houve o buraco das 10h às 14h48 por falta de crédito na OpenAI (veja a 55).

**Corretores distintos atendidos.** O critério é: contato com turno real de `papel='corretor'`. Para juntar telefone e @lid numa pessoa só, mapeei `lid:` para o telefone por `identidade_lid`, que é a mesma lógica de `nai_contato_irmaos`. Chamar a função linha a linha estourou os 120 s, então reproduzi a regra em SQL.
- **258 pessoas** (274 contatos, dos quais 21 são @lid) tiveram turno como corretor desde 10/09.
- **86** receberam pelo menos uma resposta.
- Antes de 28/09 07:00: 229 pessoas, das quais 54 respondidas.
- Depois de 28/09 07:00: 74 pessoas, das quais **45 respondidas**, com 427 turnos de corretor e 170 respondidos.
- A lista que decide quem ela atende é a tabela `corretores`: 1.459 de fonte 'grupo', 34 'agenda', 32 'tel' e 9 'site'. Com `nai_config.so_corretor_da_lista = sim`, quem não está nela cai em "fora da lista de corretores" (175 turnos).

**Visitas.** Fonte: `nai_visita`, com 69 linhas. **62 são de teste**: corretor …2835 (Pedro), …0001 (treino) e a visita id 1, "simulacao automatica". **Reais: 7.**
- **Critério de "pedida":** linha criada (evento `pedida`). Houve 7 pedidas: ids 1039, 1040, 1042, 1047, 1048, 1049 e 1056, de 23/09 a 29/09.
- **Critério de "confirmada":** `confirmada_em` não nulo (evento `confirmada`). **0 confirmadas.**
- **Critério de "realizada":** evento `realizada` ou `resultado` preenchido. **0 realizadas.**
- Como cada uma terminou:
  - 1039 (5734), 1040 (5724) e 1042 (3050): "proprietario_sem_contato: sem_cadastro", foram para o Tel e expiraram (a 1039 em `aguardando_acesso`, depois de o Tel confirmar o proprietário);
  - 1047 (5722): "expirou_sem_confirmar", o corretor não confirmou;
  - 1048 (5758): o corretor confirmou, a aprovação foi à equipe (…6408) com 2 lembretes, sem resposta; foi ao Tel e expirou às 16:00 de 29/09;
  - 1049 (5722): urgente, foi ao Tel, o Tel confirmou o proprietário às 07:18 e ela expirou às 10:00 em `aguardando_acesso`;
  - 1056 (840): aberta em `confirmando`, para 30/09 13:00.

Existe uma segunda agenda, a legada: tabela `visita`, preenchida pelo cron `detectar_visitas.py` a partir das mensagens dos corretores e apagada pelo `alertar_visitas.py` quando a hora passa. Hoje está vazia. O log `detectar_visitas.log` tem 25 "registrar" e 13 "cancelar" (mensagens de 14/09 a 28/09; 12 delas de um único número em 22/09). "Realizadas" nessa agenda: NÃO SEI, porque a linha é apagada e não fica histórico. `visitas` (plural) tem 0 linhas.

**Escalações ao Tel por dia.** Uso duas medidas:
- **`escalacoes`** (pendência aberta para o Tel):
  - 67 reais em 31 dias, média 2,2/dia, pico 14 em 01/09 (Nay antiga);
  - depois de 28/09 07:00: **17 em 1,5 dia (~11/dia)**;
  - 57 das 67 continuam `aberta`, 10 `resolvida`. O Tel quase nunca fecha pelo comando `RESPOSTA`.
- **Mensagens da NAI ao Tel** (`nai_saida`, `papel_destino='tel'`, enviadas, turno real):
  - 131 em 20 dias, média 6,6/dia, pico 30 em 23/09;
  - 117 são de dúvida ou escalada (`duvida_fora_da_base`, `secretaria_pergunta`, `midia_para_o_tel`, `foto_inexistente`, `corretor fora da lista`…) e o resto é aviso de visita;
  - depois de religada: **54 em 1,5 dia (~36/dia)**.
- Turnos reais com a ferramenta `escalar` ou `escalar_ao_tel`: 24 em 28/09 e 17 em 29/09.
- Paralelo: 289 conversas estão com `nai_contato.humano_motivo = 'o Tel escreveu pelo celular'`, ou seja, o Tel assumiu digitando.

**Custo com modelo por dia.**
- **Jev (OpenRouter), registrado em `nai_jev.custo`, em US$:**

| dia | chamadas | custo (US$) |
|---|---|---|
| 24/09 | 49 | 0,0021 |
| 25/09 | 159 | 0,0090 |
| 26/09 | 177 | 0,0122 |
| 27/09 | 70 | 0,0058 |
| 28/09 | 125, mais 7 sem custo | 0,0073 |
| 29/09 | 127 | 0,0078 |

  Dá cerca de US$ 0,00006 por chamada, com modelo `typesafe/jev-1.13-20260917`.
- **OpenAI** (conversa gpt-5.6-sol, imagem gpt-4o-mini, transcrição gpt-4o-transcribe): **NÃO SEI**. Não há registro no banco.
  - Para saber, é preciso olhar o painel da OpenAI (platform.openai.com, em Usage). A mesma chave serve à NAI, à captação da VPS2 e à transcrição do CRM, então o painel mistura os três, a menos que se separe por projeto ou chave.
  - Existe uma amostra em tokens: as execuções que o n8n ainda guarda (29/09 14:01–19:04 Manaus, ~5 h, 89 execuções com modelo). Os nós de agente gravam só `tokenUsageEstimate`, que é estimativa e não conta tokens de raciocínio.

| nó | chamadas | tokens de entrada | tokens de saída |
|---|---|---|---|
| "GPT (corretor)" | 90 | ~563,5 mil (≈6,3 mil por chamada) | ~1,2 mil |
| "Ler imagem (GPT)" | 15 (9 com uso) | 241,6 mil (≈27 mil por imagem) | 945 |
| "Transcrever" | 21 (14 com uso) | 5,9 mil | 718 |
| "GPT (Fernando)" | 8 | 5,0 mil | 93 |
| "GPT (secretária)" | 2 | 1,2 mil | 25 |
| "Jev decide" | 52 | 73,8 mil | 15,5 mil |

  O histórico do n8n guarda pouco (`EXECUTIONS_DATA_MAX_AGE=72`, `PRUNE_MAX_COUNT=2000`; hoje começa ~13:57), então não serve para 30 dias.

### 57. Modelos e provedores, nó por nó

**Premissa a corrigir.** O `README.md` do repositório (linha 31) ainda diz "modelo (Haiku 4.5)". Em produção não há Claude ativo em lugar nenhum. O `nai_turno.modelo` nunca foi preenchido, então o banco não diz qual modelo respondeu cada turno.

**VPS1, "NAI atendimento locação" (ativo):**

| nó | tipo | provedor e modelo | parâmetros | usado por |
|---|---|---|---|---|
| "GPT (corretor)" | lmChatOpenAi v1.3 | OpenAI `gpt-5.6-sol`, credencial "OpenAI account" | `options: {}`: sem temperature, sem reasoning effort, sem max tokens (vale o padrão do provedor) | agente "NAI (corretor)" (agent v3.1, `returnIntermediateSteps: true`) |
| "GPT (proprietário)" | lmChatOpenAi v1.3 | OpenAI `gpt-5.6-sol` | idem | "NAI (proprietário)" |
| "GPT (Fernando)" | lmChatOpenAi v1.3 | OpenAI `gpt-5.6-sol` | idem | "NAI (Fernando)" |
| "GPT (secretária)" | lmChatOpenAi v1.3 | OpenAI `gpt-5.6-sol` | idem | "NAI (secretária)" (`returnIntermediateSteps: true`) |
| "Transcrever" | httpRequest v4.2 | POST `api.openai.com/v1/audio/transcriptions`, `model=gpt-4o-transcribe`, credencial openAiApi | `language=pt`; `prompt` com o vocabulário (bairros e condomínios de Manaus); timeout 45 s | ramo "Detectar audio" → "Baixar audio" → "Transcrever" → "Juntar mensagens" |
| "Ler imagem (GPT)" | httpRequest v4.2 | POST `api.openai.com/v1/chat/completions`; o corpo é montado em "Detectar imagem": `model: 'gpt-4o-mini'`, `max_tokens: 400` | prompt "Descreva em portugues, em ate 5 linhas…"; imagem em `data:…;base64` montada em "Montar leitura da imagem" com `getBinaryDataBuffer` (se falhar, vai a URL); timeout 30 s | "Detectar imagem" → "Baixar imagem" → "Montar leitura da imagem" → "Ler imagem (GPT)" → "Juntar mensagens" |
| "Jev decide" | httpRequest v4.2 | POST `openrouter.ai/api/alpha/decisions`, credencial httpHeaderAuth "OpenRouter (Jev)", `model: 'typesafe/jev-1.13'` (montado em "Montar pergunta ao Jev"; o provedor devolve `typesafe/jev-1.13-20260917`) | perguntas tipadas (`atendente`, `codigo_quer`, `codigo_rejeita`, `oferta`, `cortesia`, `o_que_mandou`); timeout 25 s | "Ler o Jev" empacota respostas, modelo e `usage.cost`; o banco decide em `nai_decidir_com_jev` (pisos em `nai_config`); grava em `nai_jev` e `nai_turno_decisao.jev_bruto`. Se o Jev cair, vale uma reserva por regex no próprio "Ler o Jev" |

Sobre o lmChatOpenAi v1.3: no código do nó (`LmChatOpenAi.node.js` do n8n 2.33.7), "Use Responses API" (`responsesApiEnabled`) tem `default: true` para versão ≥ 1.3, e nenhum dos nós muda isso. Então os agentes falam com a **API de Responses**. Segundo a memória do simulador, o `gpt-5.6-sol` só aceita ferramenta por ela.

Na amostra de 29/09 (execuções guardadas desde 13:57), rodaram: "Jev decide" em 52 execuções, "GPT (corretor)" em 50, "Transcrever" em 21, "Ler imagem" em 15, "GPT (Fernando)" em 6 e "GPT (secretária)" em 2.

**VPS1, "Nay- recebe mensagem" (ativo, mas com o agente dormente):**
- "OpenAI Chat Model" (lmChatOpenAi v1.3, `gpt-5.6-luna`, alimenta o "AI Agent").
- "Transcrever" (`@n8n/n8n-nodes-langchain.openAi` v1.8, audio/transcribe, `language=pt`). O modelo está **fixo em `whisper-1`** no `transcribe.operation.js` do n8n.
- Nas 1.304 execuções guardadas hoje, nem o "AI Agent" nem o "Transcrever" rodaram. `config.atendimento_pausado='sim'` desde 31/08 18:08.

**Inativos na VPS1:**
- "Nay Cerebro": "Anthropic Chat Model" `claude-haiku-4-5-20251001` e "OpenAI Chat Model" `gpt-5.6-luna`.
- "Nay - captacao proprietarios": cópia antiga, com "GPT (captação)" `gpt-5.6-sol` e "Transcrever" `whisper-1`.
- "ZZ teste leitura de imagem".

**VPS2, "Nay - captacao proprietarios" (ativo):** "GPT (captação)" (lmChatOpenAi v1.3, `gpt-5.6-sol`, credencial "OpenAI account") alimenta o "AI Agent". "Transcrever" é o nó OpenAI v1.8, então `whisper-1`. Os outros dois fluxos da VPS2 não têm modelo.

**Fora do n8n:**
- O CRM (`crm/src/lib/transcricao.ts`) transcreve com `OPENAI_TRANSCRIBE_MODEL` ou `gpt-4o-transcribe`, usando `OPENAI_API_KEY` (a mesma chave, segundo a memória).
- Os scripts Python do host (`/root/nay-publicador`) não chamam nenhum LLM: o grep por `api.openai.com`, `openrouter` e `anthropic` não achou nada.

**Histórico de trocas e o que quebrou em cada uma:**
1. **10/09, Claude Haiku 4.5** (temperatura 0,2, credencial Anthropic), segundo as memórias nai-atendimento-locacao-decisoes e -arquitetura. Na primeira simulação o modelo ignorou as ferramentas e inventou valor; corrigiram com o bloco "ANTES DE TUDO" no topo do prompt.
2. **13/09 à tarde, a Anthropic ficou sem crédito, e os agentes foram para `gpt-5.6-luna`** "sem temperature" (memória). O log de alarmes mostra 13/09 12:21, 12:39 e 12:41 com "NAI (corretor) — Bad request - please check your parameters" (`mensagens.id` 8011, 8024 e 8027). [OPINIÃO: coincide com a troca; parâmetro incompatível com o modelo novo. Não provado.]
3. **14/09, `luna` virou `gpt-5.6-sol` nos três agentes.** `Arquivos/REGRAS-E-BUGS.md:746`: "O modelo era o fraco… (sol > terra > luna)". Foi o teste do Tel com cinco erros numa conversa.
4. **Captação: continuou no Haiku em 13/09 e hoje está em `gpt-5.6-sol`.** A data da troca é NÃO SEI; foi antes de 19/09, porque o primeiro commit (475f61b) já tem `gpt-5.6-sol`.
5. **16/09, ramos de áudio (Whisper) e imagem (GPT).** Quebrou o "Abrir turno": 19 alarmes entre 11:32 e 11:41 com `invalid input syntax for type bigint: "chatcmpl-…"`, porque a resposta da OpenAI entrou no lote de mensagens (o comentário no código de "Detectar imagem" registra isso). Além disso, **até 22/09 nenhum turno recebeu transcrição nem descrição** (memória midia-lida-pelo-gpt-na-nai). O "Juntar mensagens" rodava duas vezes e descartava a transcrição, e a imagem ia pela URL da Z-API ou com a etiqueta `filesystem-v2` no lugar dos bytes, e a OpenAI respondia "unsupported image". A correção foi em 22/09 (commit e822df5).
6. **22/09, "mente mestra" com `gpt-4o-mini` escrevendo JSON** (commit e822df5, `MODELO_MENTE = "gpt-4o-mini"`). Quebrou por dois dias: mandava VENDA para a secretária com o motivo "VENDA DE IMÓVEL NÃO É LOCAÇÃO" (mensagem do commit f37b425).
7. **23/09, a transcrição da NAI passou de whisper para `gpt-4o-transcribe` com prompt de vocabulário** (commit af33997).
8. **24/09, o Jev (`typesafe/jev-1.13`, OpenRouter) substituiu a mente** (commit f37b425: "10 de 10 certos, US$ 0,000034 por mensagem"). O problema seguinte veio da ficha aberta, que grudava tudo na secretária: dos 9 casos com o Jev a ≥0,70, calaram os 9 (memória cola-do-cadastro-cala-a-nay, rodada 9). Em 25/09, das 08:57 às 08:58, houve 22 alarmes "out-of-memory" em "Decidir quem responde" e "Resposta da secretária". A ligação com o Jev não está provada.
9. **Incidentes de provedor, sem troca de modelo:**
   - OpenAI 503 ("Service unavailable") em 21/09 09:40 e até 22/09 09:56 (3 alarmes);
   - OpenAI sem crédito em 29/09, das 09:51 às 14:48. Derrubou os 4 agentes, a leitura de imagem, a transcrição, a captação da VPS2 e a transcrição do CRM. O Jev, que está na OpenRouter, continuou funcionando.

### 58. Serviços no host fora do Docker

FATO: o host é Ubuntu 24.04 com 2 CPUs e 7,8 GB de RAM, ligado há 50 dias. Os serviços próprios são 2 units systemd, o `tailscaled` e o cron (crontab do root e `/etc/cron.d`). Não há timer systemd próprio: os 13 timers são todos do sistema (sysstat, apt, logrotate, fstrim, e2scrub, dpkg-db-backup…). Os túneis cloudflared (`nay-site-api-tunnel` e `nay-painel-tunnel`) são containers, não serviços do host.

**systemd:**

| unit | o que faz | a Nay depende? |
|---|---|---|
| `nay-publicador.service` | Flask `/root/nay-publicador/servidor.py` em 0.0.0.0:8080, `POST /comando`, `Restart=always`, no ar desde 28/09 17:55 | **Sim, para os comandos do Tel.** Os nós "Comando do Tel" dos dois fluxos chamam `http://172.16.0.1:8080/comando`. Sem ele, os comandos do Tel pelo WhatsApp falham. Na resposta a corretor, não |
| `baixador-imagens.service` | Flask em 127.0.0.1:8090 (`/extrair`, `/baixar`, `/coletor`) | Não. Quem usa é o `captacao.py` (OLX) e a tela do Tel; nenhum nó do n8n chama |
| `tailscaled.service` | publica o `naydb:5432` no tailnet (100.86.114.74) | Não para a locação. **Crítico para a captação da VPS2**, que depende dele para acessar o banco |
| `docker`, `containerd`, `cron` | a base de tudo | críticos |
| `unattended-upgrades` | atualizações automáticas do APT ligadas; o Docker vem do repositório docker.com | — |

**Crontab do root** (horários já em Manaus):

| linha | o que faz | frequência | a Nay depende? |
|---|---|---|---|
| `disparar_grade.sh` | grade de postagem nos grupos (publicador) | todo minuto | Não para responder. Mas o card postado grava `envios` com o ID, e é por esse ID que a NAI reconhece "marcou uma mensagem de imóvel" |
| `disparar_lembretes.sh` | lembrete de retorno da Nay antiga (doc 31) | todo minuto | Não (log vazio desde 31/08) |
| `entregar_pendentes.sh` | entrega o que a Nay antiga ficou de mandar | todo minuto | Não (última entrega em 01/09) |
| `sincronizar_catalogo.sh` | raspagem do imobeasy.com (`sincronizar_catalogo.py`) e depois `varrer_fotos.py` (`imovel_fotos`), `varrer_tipos.py`, `preencher_do_anuncio.py` e **os dois alarmes** | diário, 05:17 (o comentário "PAUSADA 27/09" acima da linha está desatualizado: a linha está ativa e o batimento é de hoje, 05:23) | **Sim, para catálogo e fotos.** A Nay lê as tabelas, não o site. Sem ele, imóvel novo ou foto nova só entra pelo `catalogar_postados`, e os alarmes param |
| `ciclo_pendencias.sh` | entrega a resposta do Tel a quem esperava a mesma pendência e cobra o Tel | todo minuto | Parcial: é o fim do ciclo da escalada |
| `backup_banco.sh` | dump do naydb (veja a 54) | diário, 23:05 | — |
| `alertar_visitas.sh` | agenda legada (tabela `visita`): briefing da manhã, véspera, 90 min e cobrança de 1 h ao Tel; confirma com o corretor | todo minuto | Não para a NAI: a agenda da NAI é o nó "Agenda (todo minuto)" do n8n, que roda `SELECT nai_agenda_tick()`. Serve ao Tel |
| `/root/nay-colagem/montar_colagens.sh` | colagem de 4 fotos | diário, 23:23 | Não (a colagem é só dos grupos desde 14/09) |
| `detectar_visitas.sh` | lê as mensagens dos corretores e grava na tabela `visita` | todo minuto | Não para a NAI; alimenta a agenda legada |
| `catalogar_postados.sh` | código postado ou citado que falta no catálogo dispara uma varredura curta | a cada 2 min | **Sim**: é o que faz a Nay conhecer um imóvel recém-postado |
| `sincronizar_grupos_corretores.sh` | refaz a tabela `corretores` a partir dos grupos (1.459 de fonte 'grupo', última em 28/09 06:11) | segundas, 06:10 | **Sim, para a porta.** Com `so_corretor_da_lista=sim`, quem não está na lista não é atendido |
| `retomar_sabado.py` | tarefa única de 19/09 | só em 19/09 (linha morta) | Não |
| `/root/sincronizar_agenda_xx.sh` | contato salvo com "Xx" na agenda da Nay entra em `corretores` (fonte 'agenda', 34) | de hora em hora, :23 | **Sim, para a porta** |
| `psql … SELECT nai_vocabulario_atualizar()` | o filtro de palavras acompanha o catálogo | diário, 00:17 | Sim, indireto (vocabulário) |
| `/root/ligar_nay_20260928.sh` | religou a Nay para todos | tarefa única, 28/09 07:00 (já rodou; o arquivo-marca impede repetir) | — |
| `sincronizar_etapas_crm.sh` | etapa da Nay vira tag do lead no CRM | todo minuto | Só o CRM |
| `avisar_saidas.sh` | aviso de ALUGADO/VENDIDO no grupo Easy | todo minuto | Não (grupos) |
| `ficha_do_anuncio.sh` | `imovel_ficha` (270 linhas): a ficha completa que a Nay consulta antes de responder sobre um imóvel (191) | a cada 3 h, :40 (20:40, 23:40, 02:40…) | **Sim, para detalhe e pagamento.** Foi instalado hoje às 18:10; a primeira rodada do cron é às 20:40 e ainda não havia log |

**/etc/cron.d:**
- `crm-espelho-nay` (todo minuto), `crm-espelho-rapido` (6 vezes por minuto, a cada ~10 s) e `crm-funis` (todo minuto): conferência e funis do CRM, via `wget` dentro do `crm-imobeasy`. Só o CRM.
- `docker-builder-prune` (sexta, 20:18) e `docker-image-prune` (diário, com atraso aleatório de até 6 h).
- **`espelho-madrugada`: tarefa única PENDENTE para 30/09 às 03:30 de Manaus.** `/root/espelho_madrugada.sh` exporta o "NAI atendimento locação", aplica `/root/patch_espelho_n8n.py` no nó "Espelhar no CRM" (nome do container no lugar do IP, modo rápido, 2 tentativas, espelho ANTES do atendimento) e **reimporta o fluxo no n8n**. As travas são: só entre 1h e 5h, só com a Nay parada (espera até 60 min), backup antes, e devolução do backup se os fluxos não voltarem ativos. O próprio script apaga a linha de cron. [OPINIÃO: é mudança de produção agendada; quem redesenha precisa saber que o fluxo muda esta madrugada, e a memória "Import de fluxo desativa" lembra o risco.]

**Críticos.** Pelo código dos nós e dos scripts acima:
- **No caminho de cada resposta não há nenhum cron.** O caminho é Z-API → webhook do n8n → funções do Postgres → OpenAI/OpenRouter → Z-API, tudo em containers. As fotos saem das URLs de `imovel_fotos`, que apontam para o site antigo, e do nó "Buscar fotos no site" (imobeasy.com/anuncios).
- **Sem estes, a Nay erra ou se cala com o tempo:**
  - `sincronizar_catalogo` e `catalogar_postados`: catálogo e fotos velhos, e a Nay diz "não encontrei" ou escala;
  - `ficha_do_anuncio`: ficha velha;
  - `sincronizar_grupos_corretores` e `sincronizar_agenda_xx`: corretor novo cai em "fora da lista" e fica sem resposta;
  - `nai_vocabulario_atualizar`: o filtro de palavras fica defasado.
- **Sem este, o Tel perde os comandos:** `nay-publicador.service`.
- **Sem este, a captação para:** `tailscaled`.
- **O resto** é grupo, CRM ou legado.

Nada no host vigia o n8n, os containers ou a conexão da Z-API (veja a 55).

---

## BLOCO 12: OPINIÃO

Tudo neste bloco é **[OPINIÃO]**. Cada opinião se apoia em fatos medidos nos blocos anteriores, e o número da pergunta de onde o fato veio aparece entre parênteses, por exemplo (41).

### 59. Manter, reescrever, jogar fora

**Manter como está**

- **A caixa de saída como conceito.** `nai_saida` e o gatilho `nai_saida_validar` garantem que nada sai sem passar por uma tabela, e que a parede de destino, de parceria e de finalidade roda no banco, qualquer que seja o caminho que gerou a linha: modelo, comando, agenda ou painel. Foi a parede que mais segurou erro de verdade (22, 41a). O que precisa mudar é a ordem e a confirmação de envio (ver "Reescrever").
- **A idempotência de entrada.** O gatilho `mensagens_uma_vez_so` impede que o mesmo id da Z-API seja processado duas vezes. Hoje também impede reprocessar (43), mas isso se resolve com um reprocessamento explícito, não tirando a trava.
- **A identidade.** A ideia de `nai_contato` + `identidade_lid` + `nai_contato_irmaos` é certa: uma pessoa, várias chaves. Falta normalizar o formato do LID (6–7, 32) e obrigar toda leitura a passar pela função. É o setor mais estável (48).
- **O prompt no banco, com histórico.** `nai_prompt` + `nai_prompt_historico` + `nai_abrir_turno` entregando `cab.prompt`, com o nó recusando prompt vazio. Mantenho. Só fecharia a escrita: tudo por uma função que sobe a versão, sem `UPDATE` direto de migração (15).
- **`nai_config` como painel de interruptores**, e a regra de "vale na mensagem seguinte, sem deploy". Falta registrar quem mudou o quê e quando: hoje não há histórico de valor (50).
- **As ferramentas que devolvem `texto_pronto` do banco**: o card (`imovel_por_codigo` / `nai_card_do_banco`) e a busca que conduz a próxima pergunta (`nai_buscar_por_perfil`). "Quem conduz é a ferramenta" é a decisão certa. O problema está na camada que roda depois, não nelas.
- **A gramática de comando do Tel** em `nai_e_comando_extra` + `nai_comando_tel`, com o comando passando antes da pausa (34). Unificaria com a do publicador, que tem outra implementação de ALUGOU/VENDEU.
- **A bateria** `nai_caso` + `nai_rodar_casos()`: 60 casos, STABLE, roda em transação só leitura, 60/60 hoje (51). Manter e crescer, sabendo que ela testa regex e roteamento, não o modelo nem o n8n.
- **O backup diário** (`backup_banco.sh`, 23:05, 14 dias), com a condição de levar uma cópia para fora da VPS (54).

**Reescrever**

1. **A camada que corrige depois do modelo.** Em ordem de dano: `nai_conferir_resposta` (25 blocos), `nai_fila_dos_outros_imoveis`, `nai_deve_mandar_fotos` (sempre verdadeira) e a troca do texto pela ficha (`formato_da_base` / `resposta_sem_consulta`). A medição do bloco 8 mostra que a causa mais frequente de "imóvel errado" e "dado errado" é essa camada: ela infere o imóvel por palavra ou número ("Adrianópolis" vira o condomínio 5748; "tava por 300" vira o imóvel 300), troca o texto do modelo pela ficha e acrescenta card e fotos (turnos 12592, 12186, 12205, 12557). Violação do próprio modelo é rara (42). O desenho novo seria: o sistema **veta e explica**, não substitui. Se a saída viola uma regra, ela volta ao modelo uma vez com o motivo ("você citou o 5748 sem consultar; consulte ou retire"). Se falhar de novo, sai uma frase neutra ou vai ao Tel. Nenhum imóvel entra na resposta sem ter saído de uma ferramenta chamada neste turno.
2. **A decisão (mente/Jev).** `nai_decidir_com_jev` lê `atendente` e `pedido`, que o nó "Montar pergunta ao Jev" deixou de perguntar em 25/09. `nai_pediu_imovel()` virou sempre verdadeira, e `jev_piso_imovel` não é lido por ninguém (7). Metade do que o Jev devolve é jogada fora. No lugar: roteamento determinístico para o óbvio (código, comando, ficha aberta, cortesia) e **um** classificador com o esquema de pergunta e resposta versionado junto com a função que consome, no mesmo lugar. O que aconteceu aqui foi o esquema mudar num nó do n8n e o consumidor ficar no banco lendo campo que não existe mais.
3. **O pedido do turno.** `nai_pedido_do_turno` é só regex, não extrai quartos, mobília nem bairro, e é recalculada com `now()`, então o mesmo turno dá resultados diferentes depois (9). Deveria ser uma extração estruturada, feita uma vez e **gravada imutável** no turno.
4. **O estado da conversa.** Hoje está espalhado em `nai_estado_conversa`, `nai_estado_v2` (só alimenta o Jev), `codigo_foco`, `nai_etapa_contato`, `nai_imovel_novo.situacao`, `humano_assumiu_em`, a memória do chat e o filtro de 24 h (10, 13). Deveria ser uma tabela de estado por conversa com transições explícitas e um único escritor, e o agente deveria receber esse estado, não a memória.
5. **A ordem e a confirmação do envio.** A "hora marcada" supõe 2,5 s por foto, mas a Z-API entrega a cada 9,3 s na mediana (23). "Confirmar envio" grava o `message_id` só no fim do lote, e por isso o eco da própria foto chega antes e é lido como "o Tel escreveu": a Nay se cala sozinha (25, fato 4 do bloco 4–5). O certo é gravar o id **item a item**, na hora da resposta da Z-API, e sequenciar pelo status de entrega (webhook de status da Z-API), não por relógio.
6. **A visita.** Nenhuma das 7 visitas reais chegou ao proprietário (26). `nai_proprietario_do_imovel` lê `imovel_privado.proprietario_id`, e não `imoveis.proprietario_id`, onde estão os donos: com a leitura certa seriam 36 de 37 imóveis de locação com dono, não 14 (28). As transições de `nai_visita.estado` estão em 17 funções, e existe uma segunda agenda de visitas no publicador (`detectar_visitas.py` / `alertar_visitas.py`, tabela `visita`). Eu reescreveria como uma máquina de estados só, com um dono.
7. **A mídia.** "Detectar audio" e "Detectar imagem" só olham a última mensagem da rajada: 24 de 138 áudios nunca foram transcritos e 118 de 181 imagens nunca foram lidas em 7 dias (fato 10 do bloco 1). Cada mensagem da rajada precisa ser tratada.
8. **A escalação.** A pausa por escalação nunca expira (34 dos 42 corretores escalados continuam calados), `RESPOSTA n` teve 0 usos em 30 dias e o aviso ao Tel não traz o número da pendência (21). Precisa de prazo, de devolução automática e de uma fila que o Tel veja.

**Jogar fora**

- **O fluxo antigo "Nay- recebe mensagem" como porta de entrada.** Ele recebe o webhook da Z-API, repassa para a NAI com timeout de 10 s (709 timeouts em 5 h de 29/09), processa os ecos (74% das execuções) e, quando o repasse falha por outro motivo, o "AI Agent" antigo com `gpt-5.6-luna` responde em duplicata (5, 43). O webhook deveria ir direto para a entrada nova. Os comandos de publicador ("posta…") passariam a ser um ramo explícito dela.
- **As duplicatas nay_/nai_.** `nay_deve_mandar_fotos` diz "as fotos não saem" enquanto `nai_deve_mandar_fotos` manda (fato 12 do bloco 1); `nay_o_que_sei_do_imovel` convive com `nai_o_que_sei_do_imovel`; `nay_codigo_confirmado` e `nay_qual_imovel` não leem `nai_saida` (11). Também as 18 funções mortas de verdade (47) e o `regras` (48 linhas, fonte do prompt antigo).
- **O trace 64 e o inventário 65 como foram feitos.** O trace nunca foi ligado (1 evento em 10 dias). A classificação por regex manda 44% das funções para as redes de segurança, e as views caem por timeout no painel (46, 47, 53). Fica a ideia; o registro de turno deve ser gravado pela aplicação: texto cru do modelo, argumentos e retorno de cada ferramenta, versão do prompt, id da execução.
- **A memória do n8n como memória da conversa.** `memoryPostgresChat` guarda o envelope de contexto (1,3 mil caracteres por mensagem) e o texto do modelo **antes** das correções, então o modelo "lembra" de frases que o corretor nunca recebeu (16, 40). A memória deveria ser o que foi **enviado** (`nai_saida` enviado) mais o que ele escreveu (`mensagens`).
- **O casamento de `nai_saber` por similaridade 0,35 sem escopo de imóvel**, que já casou errado (39).
- **`nai_regra` (17) e `vw_nai_regras_ignoradas` como medida de obediência.** Cobrem 17 de 36 etapas, misturam treino e contam etapa de fluxo como "ignorou" (42).

### 60. O que a outra IA vai errar lendo só o repositório

O repositório descreve um sistema que existiu em algum momento entre 11/09 e 24/09. O que engana, do mais perigoso para o menos:

1. **Achar que o `.sql` é o banco.** A arquitetura v2 (`nai_decidir_v2`, `nai_estado_v2`, `nai_turno_decisao`, `nai_estado_conversa`) não existe em nenhum arquivo do `nayia`. Está em `/tmp/74_*.sql` e `/tmp/75_*.sql` no servidor, com números que colidem com os arquivos 74 e 75 do repositório (9–10, 45). São 41 funções vivas sem definição no repositório (19 se contar o repositório do publicador), e as migrações 125 a 191 entraram num commit só chamado "llsss". Quem reconstruir pelos arquivos vai reconstruir um sistema que não é o que está no ar.
2. **Achar que o `nayia` é o sistema inteiro.** Existe um segundo repositório, o do publicador (`/root/nay-publicador`), com 86 `.sql` de funções `nay_`, 250 linhas de produção sem commit e arquivos fora do git (`ficha_do_anuncio.py`, `saida_do_sistema`). O publicador, o CRM (botão "Nay voltar a atender", espelho), a agenda paralela de visitas, o follow-up e a captação da VPS2 falam com os mesmos corretores pelos mesmos números (5, 33, 58).
3. **Confiar nos documentos de arquitetura.** O COMO-A-NAY-FUNCIONA.md diz "espera 60 s" (é 20 s), "13 ferramentas" (são 16), "15 casos" (são 60), "a mente escolhe entre IMÓVEIS e SECRETÁRIA" (desde 25/09 o Jev não pergunta mais o atendente) e "o conferidor confere" (ele substitui). O README e a memória antiga dizem Haiku 4.5; o modelo é `gpt-5.6-sol` pela API de Responses (57). O `Arquivos/CLAUDE.md` descreve o fluxo antigo (ferramentas `nay_`, `nay_memoria` de 15 mensagens) como se fosse o atual.
4. **Achar que o JSON do workflow é estável.** O `workflow_history` do n8n guarda só a versão atual. 18 de 70 nós com código da NAI não estão em nenhum repositório, e o montador `montar_fluxo_jev.py` ainda faz a pergunta `atendente`, que o fluxo vivo não faz (2, 45). Há um cron (`/etc/cron.d/espelho-madrugada`) que reimporta o fluxo da NAI em 30/09 às 03:30 (58): o JSON que ela tem hoje já estará velho amanhã.
5. **Colunas e tabelas com nome de verdade que não são verdade:**
   - `nai_turno.modelo`, `exec_id`, `prompt_versao` e `ms_total` existem e estão vazias nos 3.437 turnos;
   - `nai_evento` existe e tem 1 linha;
   - `vw_catalogo_locacao` não filtra disponibilidade;
   - `imovel_privado.proprietario_id` parece ser o vínculo com o dono, mas o vínculo real está em `imoveis.proprietario_id`;
   - `mensagens.criada_em` é a hora em que a execução começou, não a hora da chegada;
   - `nai_saida.enviado_em` é o fim do lote, não a hora de cada item;
   - "Fernando" nos prompts de `motoboy` e `proprietario` é hoje o André.
6. **Ler "três camadas" como três redes de segurança.** A terceira camada, a que "impede", é também a que mais **produz** erro (41). A redundância aqui não é só redundância: as camadas decidem coisas diferentes e se contradizem (`nay_deve_mandar_fotos` × `nai_deve_mandar_fotos`; cabeçalho que prefere o código digitado × pós-processamento que prefere a citação, 11).
7. **Tomar número do repositório por número de hoje.** "1.163 de 1.250 sem dono" (24/09) não tem origem reproduzível (38). "259 ofertáveis" continua valendo, mas a locação ofertável é 37, e dela só 14 têm dono alcançável pela Nay (28).

### 61. O buraco que ainda não apareceu, mas vai

Em ordem de probabilidade:

1. **A fila escondida do n8n.** O limite é 5 execuções simultâneas numa máquina de 2 vCPU. A fila já leva o p90 do webhook até a Z-API para 302 s (6). A Nay foi religada para todos em 28/09, com 325 turnos reais por dia (56). Quando o volume subir, o atraso cresce sem aviso: nenhum alarme mede atraso nem silêncio. Houve 39 h sem mensagem em 17/09 e zero alarmes (55). Se alguém reiniciar o n8n com fila cheia, as execuções "new" nunca começam, a mensagem se perde (foram 27 em 25/09 e 27/09, 43) e o gatilho `mensagens_uma_vez_so` impede a reentrega. Isso já aconteceu duas vezes em escala pequena; em escala grande vai ser um dia inteiro de corretor sem resposta.
2. **A primeira visita real a chegar num proprietário.** O caminho da 179 ("o sim do corretor vai direto ao dono") tem 0 execuções reais. O agente "NAI (proprietário)" nunca falou com um proprietário real: os 38 turnos são de teste, até 15/09. O prompt dele é de 15/09 e chama o acompanhante de Fernando (26, 29). E `nai_proprietario_do_imovel` lê o vínculo menos preenchido, sem data de validade: quando um imóvel tiver um vínculo velho em `imovel_privado`, a Nay manda dados do visitante para o dono errado. A visita #1056 expira em 30/09 às 04:02 se não houver confirmação (26).
3. **"3500" virar o imóvel 3500.** O filtro da 190 entrou às ~19:00 de 29/09 e ainda não rodou com nenhum corretor real. A pergunta nova "Até que valor o seu cliente quer?" não é reconhecida por `nai_esperando_valor`, e os números de 1000 a 5000 são quase todos códigos de imóvel existentes (12). A primeira resposta de orçamento seco pode sair como card e fotos.
4. **As rotas do painel sem senha.** Pelo código e pelas labels do traefik, `PUT /api/nai/config` (modo, pausada, `envio_simulado`) e `PUT /api/nai/prompt/<papel>` em api.imobeasy.online não pedem senha. Não testei chamando (50). Se estiverem expostas, qualquer um que descobrir a URL pode calar a Nay ou reescrever o prompt, e não fica registro de quem mudou (`nai_config` não tem histórico).
5. **Perder o disco.** O backup do `naydb` fica no mesmo disco da mesma VPS. O sqlite do n8n (736 MB), que é a única cópia viva dos dois fluxos, não tem backup automático. O `crmdb` e a mídia do CRM também não (54).
6. **Corretor calado para sempre.** Isso já está acontecendo, só que ninguém vê: 34 de 42 corretores escalados continuam em pausa sem prazo (21), e o eco das próprias fotos cala a Nay em "Com o Tel" (25). Não gera erro, não gera alarme, e o corretor simplesmente para de receber resposta.

### 62. O que você deveria ter perguntado

- **Quem mais fala pelo mesmo número.** Publicador, CRM, follow-up, agenda paralela de visitas, disparo pelo painel e a equipe mandando imóvel. O redesenho precisa ser dono da caixa de saída inteira, não só da conversa da NAI, senão continuam as travas de 24 h cruzadas, o eco lido como Tel e as duplicatas (5, 22, 33).
- **Capacidade e latência.** Quantos turnos por hora a arquitetura aguenta, e o que acontece acima disso (6, 61). Nenhuma das 62 perguntas trata o n8n como gargalo, e hoje ele é.
- **O resultado de negócio.** 7 visitas reais pedidas, 0 confirmadas, 0 realizadas (56). Das 258 pessoas atendidas, 86 receberam alguma resposta. Se o objetivo é visita, a pergunta certa é por que nenhuma chegou ao fim, e a resposta está nos dados (dono não alcançável) e não no modelo.
- **Quais eventos da Z-API existem e quais estamos usando.** Status de entrega, eco de saída, citação só com id (4, 23, 25). Metade dos problemas de ordem e de "o Tel assumiu" vem de ler eventos do jeito errado.
- **Dados pessoais.** O nome do contato vai para a OpenRouter no Jev (7), o CPF passa pelo cadastro, e as rotas do painel não pedem senha. Qual é a política?
- **Que decisões de negócio estão em aberto e são do Tel.** Fotos sempre ou só quando pedidas (a regra de 16/09 compete com o prompt), `proprietario_pelo_tel`, `so_corretor_da_lista`, o que fazer com o desconhecido (21 perguntas "é corretor?" sem resposta), prazo da pausa por escalação. O desenho novo não pode escolher isso sozinho.
- **O que falta no dado, não no código.** `mobilia` vazia em 52% dos ofertáveis, forma de pagamento só na ficha nova, nenhuma foto de fachada marcada, dono no vínculo errado (35, 28). Uma parte dos "erros da IA" é dado ausente.
- **Quem aplica mudança e com que controle.** Hoje é o assistente, por ssh, sem CI, sem tabela de migrações e sem revisão, e há um cron agendado que reimporta o fluxo de madrugada (50, 58). O redesenho precisa do processo de mudança tanto quanto da arquitetura.
- **Como conviver.** Qual fluxo fica com o webhook durante a migração, e como os dois sistemas deixam de disputar `humano_assumiu_em`, `nai_contato` e `nai_saida` (49). Sem isso, a Nay nova vai herdar os conflitos de escrita da atual.
