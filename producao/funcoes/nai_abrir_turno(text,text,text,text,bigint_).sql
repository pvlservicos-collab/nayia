CREATE OR REPLACE FUNCTION public.nai_abrir_turno(p_tel text, p_nome text, p_texto text, p_citado_id text, p_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave   text := nai_chave(p_tel);
  v_modo    text := nai_cfg('modo', 'desligado');
  v_teste   boolean;
  v_contato bigint;
  v_papel   text := 'corretor';
  v_visita  bigint;
  v_texto   text := coalesce(p_texto, '');
  v_m       text[];
  v_cit     record;
  v_n       int;
  v_turno   bigint;
  v_aprov   boolean;
  v_prim    boolean;
  v_pausado boolean;
  v_tel_lid text;
  v_rayssa  text;       -- 197: a conversa é da Rayssa (visita, fechamento, proprietário)
  v_porta   record;   -- a porta: atende essa mensagem?
BEGIN
  IF v_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_identificador');
  END IF;
  IF v_modo NOT IN ('teste', 'todos') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nai_desligada');
  END IF;
  v_teste := v_chave = ANY (nai_chaves_teste());

  -- O FILTRO DE PALAVRAS (106, Tel 23/09: "se ela estiver escrita mais ou
  -- menos certo, acima de 70% da palavra certa ela conserta a palavra antes
  -- ate de enviar para a Nay"). "bom pedro" vira Dom Pedro, "aquarelli" vira
  -- Acquarelle -- e isso vale para a PORTA tambem, que assim reconhece o
  -- imovel nosso mesmo quando o nome chega torto do audio.
  -- O comando do Tel nao passa por aqui: filtro de palavras nao pode ter
  -- poder de quebrar um DEVOLVER.
  IF NOT nai_pode_comandar(v_chave) THEN
    v_texto := nai_corrigir_nomes(v_texto);
  END IF;
  -- O COMANDO DELES PASSA MESMO EM MODO TESTE (Tel, 15/09: "tel mandou agenda
  -- de visitas e ela n respondeu"). O numero do Tel nao esta em
  -- `numeros_teste` -- so o do Pedro esta --, entao o turno nem abria e o
  -- comando morria calado. A excecao e so para o COMANDO: conversa normal
  -- desses numeros continua caindo na mesma porta de antes.
  IF v_modo = 'teste' AND NOT v_teste
     AND nai_pode_comandar(v_chave)
     AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)) THEN
    NULL;   -- deixa passar
  ELSIF v_modo = 'teste' AND NOT v_teste THEN
    -- Defesa em profundidade: o roteador nao devia ter mandado.
    RETURN jsonb_build_object('ok', false, 'motivo', 'fora_do_teste');
  END IF;

  v_contato := nai_contato_de(p_tel, p_nome);

  -- O TEL ASSUMIU este chat: a mensagem fica gravada (status 'Com o Tel') e
  -- a NAI nao responde. No teste, "T: ..." continua sendo o Tel mandando
  -- comando (e o DEVOLVER precisa passar).
  -- 16/09: a leitura da pausa passou a ser uma so, em `nai_tel_com_a_conversa`
  -- -- que sabe do gap. Antes eram tres copias de
  -- `humano_assumiu_em IS NOT NULL`, e com a janela entrando elas iam divergir.
  -- 240: A DÚVIDA ERA DE OUTRO IMÓVEL. Chat pausado por "dúvida fora da base" e ele
  -- MARCA ou CITA um imóvel diferente do que foi escalado: a pausa cai e a Nay
  -- atende (a base pode saber a resposta do imóvel certo). O Tel é avisado.
  DECLARE
    v_irmaos bigint[] := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);
    v_cit    int;
    v_esc    int;
  BEGIN
    IF EXISTS (SELECT 1 FROM nai_contato c WHERE c.id = ANY (v_irmaos) AND c.humano_motivo ~ '^duvida fora da base') THEN
      v_cit := coalesce(
        nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int,
        (SELECT x::int FROM unnest(coalesce(nay_codigos_citados(v_texto), '{}'::text[])) x
          WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int) LIMIT 1));
      SELECT t.codigo INTO v_esc FROM nai_turno t
       WHERE t.contato_id = ANY (v_irmaos) AND 'escalar' = ANY (coalesce(t.ferramentas, '{}'))
       ORDER BY t.id DESC LIMIT 1;
      IF v_cit IS NOT NULL AND v_cit IS DISTINCT FROM v_esc THEN
        UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_irmaos);
        BEGIN
          PERFORM nai_avisar_tel(NULL, NULL,
            'Tel, pode desconsiderar a dúvida de ' || coalesce(nullif(btrim(p_nome), ''), 'um corretor')
            || coalesce(' sobre o ' || nai_ref_imovel(v_esc), '') || ': ela falava de outro imóvel ('
            || coalesce(nai_ref_imovel(v_cit), 'código ' || v_cit) || '), marcou o card e eu voltei a atender.',
            'duvida_era_de_outro_imovel');
        EXCEPTION WHEN others THEN NULL;   -- o aviso nunca derruba o atendimento
        END;
      END IF;
    END IF;
  END;

  IF nai_tel_com_a_conversa(v_contato)
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN
    UPDATE mensagens SET status = 'Com o Tel' WHERE id = ANY (coalesce(p_ids, '{}')) AND status IN ('Recebido', 'Processando');
    RETURN jsonb_build_object('ok', false, 'motivo', 'tel_assumiu', 'contato_id', v_contato);
  END IF;

  IF v_teste THEN
    -- No teste, o mesmo numero faz todos os papeis. O papel vem da MARCACAO
    -- (ele respondeu marcando a mensagem que iria para o proprietario) ou
    -- do prefixo P: / M: / T:. Sem nada disso, e corretor.
    IF nullif(p_citado_id, '') IS NOT NULL THEN
      SELECT s.papel_destino, s.visita_id INTO v_cit
        FROM nai_saida s WHERE s.message_id = p_citado_id AND s.redirecionado LIMIT 1;
      IF v_cit.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_papel := v_cit.papel_destino; v_visita := v_cit.visita_id;
      END IF;
    END IF;
    v_m := regexp_match(v_texto, ('^\s*(p|prop|propriet[aá]ri[oa]|m|moto|motoboy|fernando|'
                          -- as DUAS grafias do nome: quem digita "André:" e quem digita
                          -- "Andre:" tem que cair no mesmo lugar. O texto NAO passa por
                          -- unaccent -- ele e capturado aqui e vira a mensagem.
                          || lower(nai_acompanhante()) || '|' || lower(unaccent(nai_acompanhante()))
                          || '|t|tel)\s*[:\-–]\s*(.*)$'), 'is');
    IF v_m IS NOT NULL THEN
      v_texto := v_m[2];
      IF v_papel = 'corretor' THEN
        -- O NOME DO ACOMPANHANTE tambem manda para o motoboy (Tel, 16/09).
        -- Sem esta linha, "André: pode ser" caia como TEL: a decisao testava
        -- so as iniciais m e f (motoboy e Fernando), e "andre" nao comeca com
        -- nenhuma das duas. Medido antes de aplicar.
        v_papel := CASE WHEN lower(v_m[1]) ~ '^p' THEN 'proprietario'
                        WHEN lower(v_m[1]) ~ '^(m|f)' THEN 'motoboy'
                        WHEN lower(unaccent(v_m[1])) = lower(unaccent(nai_acompanhante()))
                          THEN 'motoboy'
                        ELSE 'tel' END;
      END IF;
    END IF;
    -- O NUMERO DO TEL no teste (13/09): comando da NAI (VISITAS, VISITA N, ACESSO,
    -- ASSUMIR, DEVOLVER) sem o prefixo T: tambem e o Tel. Conversa normal dele
    -- continua sendo corretor -- e assim que ele testa.
    -- 28/09: `nai_e_voz_do_tel` no lugar da igualdade com `tel_telefone`.
    -- O Tel pediu um SEGUNDO número "como se fosse ele", e a regra de quem
    -- é o Tel passou a morar numa função só -- repetida nos quatro pontos,
    -- divergiria e daria comando aceito num caminho e recusado no outro.
    IF v_papel = 'corretor' AND nai_e_voz_do_tel(v_chave) AND nai_e_comando_tel(v_texto) THEN
      v_papel := 'tel';
    END IF;
    -- AGENDA DE VISITAS (Tel, 15/09): "quero que o tel e eu quando digitar no
    -- pv dela Agenda de visitas". Vale para os telefones de
    -- `comando_telefones`, e SO para esse comando -- o resto da conversa deles
    -- continua caindo onde sempre caiu.
    IF v_papel = 'corretor' AND nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave) THEN
      v_papel := 'tel';
    END IF;
    -- ENVIA <NUMERO> O <CODIGO> DA EQUIPE (27/09/2026, 135): o pedido de envio
    -- do Pedro e da Rayssa e comando, nao conversa. O do Tel continua indo para
    -- o publicador, pelo caminho de sempre -- por isso o Tel fica de fora aqui.
    IF v_papel = 'corretor' AND NOT nai_e_voz_do_tel(v_chave)
       AND nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato) THEN
      v_papel := 'tel';
    END IF;
    -- 184: "checklist aluguel para 92 ..." da equipe também é comando
    IF v_papel = 'corretor' AND nai_e_comando_checklist(v_texto) AND nai_e_da_equipe_contato(v_contato) THEN
      v_papel := 'tel';
    END IF;
    -- 141: o SIM/NAO da Rayssa (ou "SIM 123" de quem e da equipe) e comando.
    IF v_papel = 'corretor' AND (nai_resposta_aprovacao_valida(v_contato, v_texto)
                                 -- 142: o lembrete da equipe
                                 OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato))) THEN
      v_papel := 'tel';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') AND v_visita IS NULL THEN
      -- A unica visita esperando esse papel. Mais de uma = pergunta.
      SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
       WHERE nai_visita_aberta(x.estado) AND x.aguardando = v_papel;
      IF v_n <> 1 THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND (v_papel = 'proprietario' AND x.proprietario_id IS NOT NULL
             OR v_papel = 'motoboy' AND x.estado IN ('aguardando_motoboy', 'confirmada'));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  ELSE
    IF nai_e_voz_do_tel(v_chave)
       OR (nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave))
       -- o pedido de envio da equipe (135)
       OR (nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato))
       -- 184: o checklist da equipe
       OR (nai_e_comando_checklist(v_texto) AND nai_e_da_equipe_contato(v_contato))
       -- 141: a aprovacao da visita
       OR nai_resposta_aprovacao_valida(v_contato, v_texto)
       -- 142: o lembrete da equipe
       OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato)) THEN
      v_papel := 'tel';
    ELSIF nai_e_motoboy(v_chave) THEN
      v_papel := 'motoboy';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.proprietario_id = v_contato AND nai_visita_aberta(x.estado)) THEN
      v_papel := 'proprietario';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') THEN
      -- Qual visita: pela mensagem marcada; senao, a unica aberta dele.
      IF nullif(p_citado_id, '') IS NOT NULL THEN
        SELECT s.visita_id INTO v_visita FROM nai_saida s
         WHERE s.message_id = p_citado_id AND s.contato_id = v_contato AND s.visita_id IS NOT NULL LIMIT 1;
      END IF;
      IF v_visita IS NULL THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND ((v_papel = 'proprietario' AND x.proprietario_id = v_contato)
             OR (v_papel = 'motoboy' AND x.motoboy_id = v_contato AND x.estado IN ('aguardando_motoboy', 'confirmada')));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  END IF;

  -- Corretor aprovado? Teste = sim. @lid: so pelo mapeamento ja gravado,
  -- e SO para aprovar -- a conversa continua sendo a do @lid.
  IF v_teste THEN
    v_aprov := true;
  ELSE
    IF v_chave ~ '^lid:' THEN
      -- 193: sem o sufixo @lid, nos dois formatos (o grupo grava so digitos).
      SELECT telefone INTO v_tel_lid FROM identidade_lid
       WHERE lid IN (regexp_replace(p_tel, '@lid$', ''), regexp_replace(p_tel, '@lid$', '') || '@lid')
       LIMIT 1;
    END IF;
    v_aprov := EXISTS (SELECT 1 FROM corretores c
                        WHERE c.aprovado AND c.ativo
                          AND nai_chave(c.telefone) = coalesce(nai_chave(v_tel_lid), v_chave));
  END IF;
  v_prim := NOT EXISTS (SELECT 1 FROM mensagens m
                         WHERE m.telefone = p_tel AND m.direcao = 'recebida'
                           AND NOT (m.id = ANY (coalesce(p_ids, '{}'))));

  -- A PORTA (Tel, 15/09): quem ela atende quando a regra publica esta ligada.
  -- Com a regra desligada devolve atende=true e o roteador segue com o
  -- porteiro de sempre -- entao ligar este campo nao muda nada sozinho.
  -- O IMOVEL DA MENSAGEM MARCADA vai junto (Tel, 15/09): quem responde o card
  -- do grupo esta falando de imovel, escreva o que escrever -- ate "Boa
  -- noite!". `nay_imovel_da_citacao` ja resolve o card do grupo, o card que ela
  -- mandou e o envio do publicador.
  SELECT * INTO v_porta FROM nai_deve_atender(
    p_tel, v_texto,
    nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int);
  -- A pausa geral da Nay (config.atendimento_pausado) vale para a NAI tambem --
  -- menos para o numero de teste, do mesmo jeito que a Nay antiga isenta o Tel.
  -- A PAUSA E SO A DELA (Tel, 15/09, na revisao depois de ativar).
  --
  -- Ate aqui a pausa da Nay ANTIGA (`config.atendimento_pausado`) tambem calava
  -- a NAI, menos para o numero de teste. Enquanto ela era so teste isso nunca
  -- aparecia -- o unico que falava com ela era o Pedro, e ele e "teste". Ao
  -- abrir para todos, as 14:12, TODO MUNDO caiu naquela pausa: 133 mensagens
  -- entraram e nenhuma foi respondida, e nao havia erro nenhum para ver.
  --
  -- A Nay antiga esta pausada desde agosto, de proposito e para sempre. Ela nao
  -- pode calar um atendimento que e outro produto, com a propria chave e o
  -- proprio botao no painel.
  v_pausado := nai_cfg('pausada', 'sim') <> 'nao';

  INSERT INTO nai_turno (contato_id, papel, visita_id, teste, texto, msg_ids, porta)
       VALUES (v_contato, v_papel, v_visita, v_teste, v_texto, p_ids, v_porta.motivo)
  RETURNING id INTO v_turno;

  -- Registra que o proprietario / Fernando respondeu (para as cobrancas).
  IF v_papel = 'proprietario' THEN
    UPDATE nai_visita SET ult_resp_prop_em = now(), atualizado_em = now()
     WHERE (id = v_visita) OR (v_visita IS NULL AND proprietario_id = v_contato AND nai_visita_aberta(estado));
  ELSIF v_papel = 'motoboy' AND v_visita IS NOT NULL THEN
    UPDATE nai_visita SET ult_resp_moto_em = now(), atualizado_em = now() WHERE id = v_visita;
  END IF;

  -- 186 (Pedro, 29/09/2026: "diz para a Nay parar de responder o André, ele é
  -- da equipe, ela só manda avisos para ele, não atende"). O acompanhante só
  -- RECEBE aviso: a mensagem dele fica gravada (o turno e a resposta à visita,
  -- logo acima) e a Nay não responde -- o roteador do fluxo não manda nada com
  -- ok falso. Comando dele (envia/checklist) já virou papel 'tel' lá em cima.
  IF v_papel = 'motoboy' THEN
    -- 187 (Pedro, 29/09/2026: "continua avisando o Tel as conversas depois de
    -- alguém agendar uma visita, só para depois que é marcado visita
    -- finalizada"). Com visita dele agendada e ainda não finalizada, o que ele
    -- escreve vai para o Tel (a Nay continua sem responder); sem visita, silêncio.
    PERFORM nai_avisar_tel(NULL, x.id,
      'Tel, o ' || coalesce((SELECT e.nome FROM equipe e
                               WHERE right(regexp_replace(coalesce(e.telefone, ''), '[^0-9]', '', 'g'), 8)
                                   = right(regexp_replace(coalesce((SELECT telefone FROM nai_contato WHERE id = v_contato), ''), '[^0-9]', '', 'g'), 8)
                               LIMIT 1), nai_acompanhante())
      || ' (acompanhante) escreveu sobre a visita #' || x.id || ' (' || nai_ref_imovel(x.codigo) || ', '
      || nai_hora_exata(x.quando) || E'):\n"' || left(coalesce(v_texto, ''), 800) || '"',
      'acompanhante_escreveu')
      FROM nai_visita x
     WHERE x.motoboy_id = ANY (nai_contato_irmaos(v_contato))
       AND nai_visita_aberta(x.estado) AND x.estado <> 'realizada'
     ORDER BY x.quando NULLS LAST
     LIMIT 1;
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'acompanhante_so_recebe_aviso', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;

  -- 197 (Pedro, 30/09/2026): corretor com a visita confirmada (até ela acabar), em
  -- fechamento, ou proprietário: quem responde é a Rayssa, pelo CRM. A mensagem
  -- fica gravada e a Nay não responde (o mesmo "ok falso" do 186).
  IF v_papel IN ('corretor', 'proprietario') THEN
    v_rayssa := nai_com_a_rayssa(v_contato, v_papel);
    IF v_rayssa IS NOT NULL THEN
      UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
      RETURN jsonb_build_object('ok', false, 'motivo', v_rayssa, 'turno_id', v_turno,
                                'contato_id', v_contato, 'papel', v_papel);
    END IF;
  END IF;

  -- 213: a RESPOSTA AUTOMÁTICA do WhatsApp Business do corretor ("estou ausente",
  -- "retornarei seu contato") não é mensagem dele: fica gravada e a Nay não responde.
  -- Em 30/09 uma delas ("Que 2026 seja um ano...") fez a Nay mandar um imóvel.
  IF v_papel = 'corretor' AND nai_e_resposta_automatica(v_texto) THEN
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'resposta_automatica', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;

  -- 223: a resposta dele à pergunta do perfil ("só serve com elevador?") vai para o perfil
  IF v_papel = 'corretor' THEN
    PERFORM nai_perfil_resposta(v_contato, v_texto, v_turno);
  END IF;

  -- 141b: a etapa e atualizada ANTES de montar o cabecalho. Dentro do
  -- jsonb_build_object a ordem de avaliacao nao e garantida, e o contexto
  -- saiu com a etapa velha ("recebeu o imovel") no turno do "sim" da visita.
  IF v_papel = 'corretor' THEN
    PERFORM nai_etapa_atualizar(v_contato);
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'turno_id', v_turno,
    'contato_id', v_contato,
    'chave', v_chave,
    'telefone', (SELECT telefone FROM nai_contato WHERE id = v_contato),
    'papel', v_papel,
    'visita_id', v_visita,
    'teste', v_teste,
    'modo', v_modo,
    'texto', v_texto,
    -- 233: imagem, documento e vídeo do turno inteiro, para o ramo "Mídia para o Tel"
    'midias', nai_midias_do_turno(v_turno),
    'tem_midia_visual', jsonb_array_length(nai_midias_do_turno(v_turno)) > 0,
    'aprovado', v_aprov,
    -- ATENDE: NULL quando a regra publica esta desligada (o roteador decide
    -- como sempre decidiu); true/false quando ela manda. `porta` diz o motivo,
    -- e e ele que explica um silencio depois.
    'atende', CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim'
                   THEN v_porta.atende END,
    'porta', v_porta.motivo,
    -- SO CUMPRIMENTOU (Tel, 15/09): "ela tem que responder o cumprimento e
    -- aguardar nesse caso". Quem chega dizendo so "boa noite" ainda nao disse a
    -- que veio -- despejar o roteiro em cima dele e responder outra pergunta.
    'so_cumprimento', nai_so_cumprimentou(v_texto),
    'primeira_vez', v_prim,
    'pausado', v_pausado,
    -- "3500" depois de "qual a faixa de preco?" e VALOR, nao codigo (13/09).
    'esperando_valor', nai_esperando_valor(v_contato),
    'memoria', 'nai:' || v_papel || ':' || v_contato || coalesce(':v' || v_visita, ''),
    -- O PROMPT VEM DO BANCO (Tel, 15/09): editar no painel vale na mensagem
    -- seguinte, sem import nem reinicio. Vazio aqui = o fluxo usa o texto que
    -- ja esta dentro dele, entao nada quebra.
    'prompt', nai_prompt_de(CASE WHEN v_papel = 'tel' THEN 'corretor' ELSE v_papel END),
    -- COMANDO DA NAI: o roteador do fluxo lia uma COPIA da regex de
    -- `nai_e_comando_tel` dentro do JS, e as duas se afastariam na primeira
    -- mudanca. Agora quem responde e o banco, e o JS so le este campo.
    'comando_nai', (v_papel = 'tel' AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)
                    -- 135: o envio da equipe vai para `nai_comando_tel`; o do
                    -- Tel segue no publicador (comando_nai falso para ele)
                    OR (nai_e_comando_envio(v_texto)
                        AND NOT nai_e_voz_do_tel(v_chave))
                    -- 184: o checklist, do Tel e da equipe
                    OR nai_e_comando_checklist(v_texto)
                    -- 141: SIM/NAO da aprovacao da visita
                    OR nai_resposta_aprovacao_valida(v_contato, v_texto)
                    -- 142: o lembrete da equipe
                    OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato)))),
    -- A BIBLIOTECA DE PALAVRAS (96, Tel 22/09) entra colada no contexto: so a
    -- explicacao da giria que ELE escreveu nesta mensagem, e nada quando nao
    -- ha giria nenhuma.
    -- 141: A ETAPA vem na frente do contexto (identificacao / recebeu o
    -- imovel / agendamento de visita) -- e o que a mantem no fio da conversa.
    'etapa', CASE WHEN v_papel = 'corretor' THEN (SELECT e.etapa FROM nai_etapa_contato e WHERE e.contato_id = v_contato) END,
    -- 235: a instrução da equipe (CRM) vem na frente de tudo, enquanto vale
    'contexto', CASE WHEN v_papel = 'corretor' THEN coalesce(nai_instrucao_texto(v_contato), '') END
                || CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' || coalesce(nai_retomada_texto(v_contato), '')
                        || coalesce(E'\n' || nai_perfil_texto(v_contato), '') ELSE '' END
                || nai_contexto(v_papel, v_contato, v_visita, v_teste)
                || CASE WHEN v_papel IN ('corretor', 'tel')
                        THEN nai_giria_explica(v_texto) ELSE '' END,
    -- Como chamar a pessoa: Sr./Sra. + primeiro nome (Tel, 12/09 -- o mesmo
    -- tom da captacao). Quando o nome nao diz o genero, vem so o primeiro
    -- nome: melhor sem tratamento do que chamar uma corretora de "Sr.".
    'vocativo', CASE WHEN v_papel = 'proprietario'
                     THEN nai_vocativo((SELECT proprietario_nome FROM nai_visita WHERE id = v_visita))
                     WHEN v_papel = 'corretor'
                     THEN nai_vocativo(coalesce((SELECT nome_completo FROM nai_contato WHERE id = v_contato),
                                                nay_nome_de_pessoa((SELECT nome_whatsapp FROM nai_contato WHERE id = v_contato)))) END
  );
END;
$function$;
