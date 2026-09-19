-- =====================================================================
-- NAI -- 42: os TEXTOS passam a usar o nome do cadastro (Tel, 16/09/2026)
--
-- Gerado por `scratchpad/trocar_acompanhante.py` a partir do que estava NO
-- BANCO. O nome do acompanhante estava escrito a mao em 19 funcoes -- recado
-- ao corretor, ao proprietario, ao proprio acompanhante e nos cards ao Tel.
-- Agora todos chamam `nai_acompanhante()`, que le de `equipe`.
--
-- As duas REGEX de entrada (o prefixo 'M:' e o comando FERNANDO OK) aceitam o
-- nome novo E continuam aceitando 'fernando': quem ja conversava com ele pode
-- responder com o prefixo antigo por semanas.
--
-- Comentarios nao foram tocados de proposito.
--
-- Rode `41_acompanhante_pelo_cadastro.sql` ANTES deste arquivo.
-- =====================================================================

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
  v_porta   record;   -- a porta: atende essa mensagem?
BEGIN
  IF v_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_identificador');
  END IF;
  IF v_modo NOT IN ('teste', 'todos') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nai_desligada');
  END IF;
  v_teste := v_chave = ANY (nai_chaves_teste());
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
  IF (SELECT humano_assumiu_em FROM nai_contato WHERE id = v_contato) IS NOT NULL
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
    IF v_papel = 'corretor' AND v_chave = nai_chave(nai_cfg('tel_telefone')) AND nai_e_comando_tel(v_texto) THEN
      v_papel := 'tel';
    END IF;
    -- AGENDA DE VISITAS (Tel, 15/09): "quero que o tel e eu quando digitar no
    -- pv dela Agenda de visitas". Vale para os telefones de
    -- `comando_telefones`, e SO para esse comando -- o resto da conversa deles
    -- continua caindo onde sempre caiu.
    IF v_papel = 'corretor' AND nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave) THEN
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
    IF v_chave = nai_chave(nai_cfg('tel_telefone'))
       OR (nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave)) THEN
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
      SELECT telefone INTO v_tel_lid FROM identidade_lid WHERE lid = p_tel;
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
    'comando_nai', (v_papel = 'tel' AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto))),
    'contexto', nai_contexto(v_papel, v_contato, v_visita, v_teste),
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


CREATE OR REPLACE FUNCTION public.nai_agenda_tick()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v        nai_visita;
  c        nai_contato;
  n        int := 0;
  v_nome   text;
  v_falta  text[];
  d        record;
  v_reenv  interval := make_interval(mins => nai_cfg_int('reenvio_proprietario_min', 30));
  v_rmoto  interval := make_interval(mins => nai_cfg_int('reenvio_motoboy_min', 30));
  v_max    int := nai_cfg_int('reenvios_proprietario_max', 3);
  v_tel_h  interval := make_interval(hours => nai_cfg_int('aviso_tel_horas_antes', 2));
  v_lemb   interval := make_interval(mins => nai_cfg_int('lembrete_corretor_min', 60));
  v_moto   interval := make_interval(mins => nai_cfg_int('aviso_motoboy_min', 30));
  v_pos    interval := make_interval(mins => nai_cfg_int('pos_visita_min', 60));
  v_ini    timestamptz;
BEGIN
  UPDATE nai_config SET valor = to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'), atualizado_em = now()
   WHERE chave = '_agenda_rodou_em';
  IF NOT FOUND THEN
    INSERT INTO nai_config (chave, valor, descricao)
    VALUES ('_agenda_rodou_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'),
            'Carimbo: a ultima vez que a agenda da NAI rodou (so leitura).')
    ON CONFLICT (chave) DO NOTHING;
  END IF;
  IF nai_cfg('modo', 'desligado') NOT IN ('teste', 'todos') THEN RETURN 0; END IF;

  FOR v IN
    SELECT * FROM nai_visita
     WHERE estado NOT IN ('encerrada', 'cancelada', 'expirada')
     ORDER BY quando
     FOR UPDATE SKIP LOCKED
  LOOP
    SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
    v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));

    -- ---------------------------------------------- passou da hora sem fechar
    IF v.estado IN ('coletando', 'aguardando_proprietario', 'negociando', 'aguardando_acesso', 'aguardando_motoboy', 'com_tel')
       AND v.quando IS NOT NULL AND now() >= v.quando THEN
      UPDATE nai_visita SET estado = 'expirada', aguardando = NULL, senha = NULL, encerrada_em = now(), atualizado_em = now()
       WHERE id = v.id;
      PERFORM nai_evento(v.id, 'expirada', v.estado);
      -- Visita que estava COM O TEL (urgente, por exemplo) nao leva "nao
      -- consegui fechar" ao corretor: quem estava tratando era ele.
      IF v.estado <> 'com_tel' THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'não consegui fechar a visita de ' || nai_quando_humano(v.quando) || ' a tempo, desculpa. Quer tentar outro horário?',
          'expirada', 1);
      END IF;
      PERFORM nai_avisar_tel(NULL, v.id, 'Tel, a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || ') chegou no horário sem fechar (estava: ' || v.estado || '). Avisei o corretor.', 'expirada');
      n := n + 1;
      CONTINUE;
    END IF;

    -- ---------------------------------------------- faltam dados (coletando)
    -- fluxo v17: os dados so sao pedidos depois da confirmacao (card Revisao).
    IF v.estado = 'confirmada' AND v.proximo_lembrete_dados_em IS NOT NULL AND now() >= v.proximo_lembrete_dados_em THEN
      SELECT * INTO d FROM nai_dados_corretor(v.corretor_id);
      v_falta := ARRAY_REMOVE(ARRAY[
        CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
        CASE WHEN d.cpf IS NULL THEN 'seu CPF' END,
        CASE WHEN d.creci IS NULL THEN 'seu CRECI' END,
        CASE WHEN v.visitante_nome IS NULL THEN 'o nome completo do visitante' END,
        CASE WHEN v.visitante_cpf IS NULL THEN 'o CPF do visitante' END], NULL);
      IF coalesce(array_length(v_falta, 1), 0) = 0 THEN
        UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
      ELSIF v.lembretes_dados >= nai_cfg_int('dados_lembretes_max', 3) OR now() >= v.quando - interval '1 hour' THEN
        UPDATE nai_visita SET proximo_lembrete_dados_em = NULL, aviso_tel_dados_em = now() WHERE id = v.id;
        IF v.aviso_tel_dados_em IS NULL THEN
          PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o corretor ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' ||
            nai_fone_fmt(c.telefone) || ') pediu visita no ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) ||
            ', e não mandou: ' || array_to_string(v_falta, ', ') || '. Parei de cobrar. Visita #' || v.id || '.', 'dados_sem_resposta');
        END IF;
      ELSE
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita', 'dados_falta', 1);
        UPDATE nai_visita SET lembretes_dados = lembretes_dados + 1,
                              proximo_lembrete_dados_em = now() + nai_intervalo_dados(v.quando)
         WHERE id = v.id;
      END IF;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- proprietario sem responder
    IF v.aguardando = 'proprietario' AND v.proprietario_id IS NOT NULL AND v.ult_msg_prop_em IS NOT NULL
       AND (v.ult_resp_prop_em IS NULL OR v.ult_resp_prop_em < v.ult_msg_prop_em) THEN

      -- Hora marcada pelo Tel (VISITA <id> AVISA 10h).
      IF v.proximo_aviso_prop_em IS NOT NULL AND now() >= v.proximo_aviso_prop_em THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.proprietario_id, 'proprietario',
          'Oi' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') || ', passando de novo sobre a visita de ' ||
          nai_quando_humano(v.quando) || '. Consegue me confirmar?', 'p_lembrete_tel', 1);
        UPDATE nai_visita SET proximo_aviso_prop_em = NULL, aviso_tel_em = NULL, ult_msg_prop_em = now(),
                              reenvios_prop = reenvios_prop + 1 WHERE id = v.id;
        n := n + 1;
        CONTINUE;
      END IF;

      IF now() >= v.ult_msg_prop_em + v_reenv THEN
        IF v.reenvios_prop < v_max AND v.proximo_aviso_prop_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.proprietario_id, 'proprietario',
            'Oi' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') || ', passando de novo sobre a visita de ' ||
            nai_quando_humano(v.quando) || '. Consegue me confirmar?', 'p_lembrete', 1);
          UPDATE nai_visita SET reenvios_prop = reenvios_prop + 1, ult_msg_prop_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
        -- Depois do primeiro reenvio sem resposta, o corretor sabe da demora.
        IF v.reenvios_prop >= 1 AND v.aviso_demora_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
            coalesce(v_nome || ', ', '') || 'ainda estou aguardando o retorno do proprietário. Assim que ele responder eu te aviso, tá?',
            'p_avisa', 2);   -- card p_avisa: aqui quem esta devendo e o proprietario, nao o Tel
          UPDATE nai_visita SET aviso_demora_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
      END IF;

      -- Faltando 2h e ainda sem confirmacao: card "Acionar o Tel" e FIM (Tel,
      -- 13/09). A visita fica com ele e a Nay para o chat do corretor E o do
      -- proprietario ("chama o tel para ambos"). O VISITA N AVISA 10h dele
      -- devolve os dois chats e agenda o proximo aviso. Uma vez so por visita.
      IF now() >= v.quando - v_tel_h AND v.proximo_aviso_prop_em IS NULL
         AND NOT EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'tel_2h') THEN
        PERFORM nai_avisar_tel(NULL, v.id, 'Tel, a visita #' || v.id || ' no ' || nai_ref_imovel(v.codigo) || ' é ' ||
          nai_hora_exata(v.quando) || ' e o proprietário ainda não confirmou.' ||
          E'\nQue horas eu mando o próximo aviso ao proprietário? Responda VISITA ' || v.id || ' AVISA 10h — se ele não responder em ' ||
          nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar. Ou VISITA ' || v.id || ' OK se já confirmou.' ||
          E'\nParei com o corretor e com o proprietário até você responder.', 'p_tel_2h');
        UPDATE nai_visita SET aviso_tel_em = now(), estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
        PERFORM nai_evento(v.id, 'tel_2h', NULL);
        PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': proprietario sem resposta 2h antes');
        PERFORM nai_parar_chat(v.proprietario_id, 'visita #' || v.id || ': proprietario sem resposta 2h antes');
        n := n + 1;
        CONTINUE;
      END IF;
    END IF;

    -- Depois do aviso marcado pelo Tel, sem resposta: "pode ligar".
    IF v.aguardando = 'proprietario' AND v.reenvios_prop > 0 AND v.aviso_tel_em IS NULL AND v.proximo_aviso_prop_em IS NULL
       AND v.ult_msg_prop_em IS NOT NULL AND now() >= v.ult_msg_prop_em + v_reenv
       AND (v.ult_resp_prop_em IS NULL OR v.ult_resp_prop_em < v.ult_msg_prop_em)
       AND EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'mensagem_proprietario' AND e.detalhe = 'p_lembrete_tel'
                    AND e.quando >= v.ult_msg_prop_em - interval '1 minute') THEN
      PERFORM nai_avisar_tel(NULL, v.id, 'Tel, mandei o aviso ao proprietário da visita #' || v.id || ' e ele não respondeu em ' ||
        nai_cfg_int('reenvio_proprietario_min', 30) || E' minutos. Pode ligar para ele?\nParei com o corretor e com o proprietário até você responder.', 'p_ligar');
      UPDATE nai_visita SET aviso_tel_em = now(), estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': proprietario nao respondeu o aviso');
      PERFORM nai_parar_chat(v.proprietario_id, 'visita #' || v.id || ': proprietario nao respondeu o aviso');
      n := n + 1;
    END IF;

    -- ---------------------------------------------- Fernando sem responder
    IF v.estado = 'aguardando_motoboy' AND v.ult_msg_moto_em IS NOT NULL
       AND (v.ult_resp_moto_em IS NULL OR v.ult_resp_moto_em < v.ult_msg_moto_em)
       AND now() >= v.ult_msg_moto_em + v_rmoto THEN
      IF v.reenvios_moto < 1 THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
          '' || nai_acompanhante() || ', consegue me confirmar a visita do ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '?',
          'motoboy_lembrete', 1);
        UPDATE nai_visita SET reenvios_moto = reenvios_moto + 1, ult_msg_moto_em = now() WHERE id = v.id;
      ELSIF v.aviso_tel_moto_em IS NULL THEN
        PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o ' || nai_acompanhante() || ' não confirmou a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) ||
          ', ' || nai_hora_exata(v.quando) || '). O proprietário já confirmou. Responda VISITA ' || v.id || ' ' || nai_acompanhante_maiusculo() || ' OK quando ele confirmar.',
          'motoboy_sem_resposta');
        UPDATE nai_visita SET aviso_tel_moto_em = now() WHERE id = v.id;
      END IF;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- visita confirmada
    IF v.estado = 'confirmada' THEN
      v_ini := nai_inicio_periodo(v.quando);
      -- No comeco do periodo (se ficar a mais de 1h da visita).
      IF v.lembrete_periodo_em IS NULL AND now() >= v_ini AND v_ini <= v.quando - v_lemb
         AND v.confirmada_em < v_ini AND now() < v.quando - v_lemb THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'passando pra lembrar da visita ' || nai_quando_humano(v.quando) || ' no ' ||
          nai_ref_imovel(v.codigo) || '. O ' || nai_acompanhante() || ' te encontra lá', 'lembrete_periodo', 1);
        UPDATE nai_visita SET lembrete_periodo_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- 1 hora antes (se a confirmacao nao foi ja dentro dessa hora).
      IF v.lembrete_1h_em IS NULL AND now() >= v.quando - v_lemb AND now() < v.quando AND v.confirmada_em < v.quando - v_lemb THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'daqui a 1 hora, às ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') ||
          ', é a visita no ' || nai_ref_imovel(v.codigo) || '. O ' || nai_acompanhante() || ' te encontra lá. Qualquer imprevisto me avisa por aqui.', 'lembrete_1h', 1);
        UPDATE nai_visita SET lembrete_1h_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- 30 min antes: senha (fechadura) ou conferir a chave, com o Fernando.
      IF v.aviso_motoboy_em IS NULL AND now() >= v.quando - v_moto AND now() < v.quando AND v.motoboy_id IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
          CASE v.acesso
            WHEN 'fechadura' THEN '' || nai_acompanhante() || ', a senha da fechadura do ' || nai_ref_imovel(v.codigo) || ' é ' || coalesce(v.senha, '(peça ao Tel)') ||
                                  '. A visita é às ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '. Conseguiu anotar?'
            WHEN 'proprietario_acompanha' THEN '' || nai_acompanhante() || ', lembrete: visita no ' || nai_ref_imovel(v.codigo) || ' às ' ||
                                  to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '. O proprietário vai estar lá.'
            ELSE '' || nai_acompanhante() || ', só confirmando: você já está com a chave do ' || nai_ref_imovel(v.codigo) || ' pra visita das ' ||
                 to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '?' ||
                 CASE WHEN v.acesso = 'buscar_chave' THEN ' Depois não esquece de devolver ao proprietário.' ELSE '' END END,
          'aviso_motoboy', 1);
        UPDATE nai_visita SET aviso_motoboy_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- Depois da visita: como foi? (e a senha sai do banco).
      IF v.pos_visita_em IS NULL AND now() >= v.quando + v_pos THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          'E aí' || coalesce(', ' || v_nome, '') || ', como foi a visita no ' || nai_ref_imovel(v.codigo) || '? O cliente gostou?',
          'pos_visita', 1);
        IF v.acesso = 'buscar_chave' AND v.motoboy_id IS NOT NULL AND v.devolver_chave_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
            '' || nai_acompanhante() || ', não esquece de devolver a chave do ' || nai_ref_imovel(v.codigo) || ' ao proprietário.', 'devolver_chave', 2);
          UPDATE nai_visita SET devolver_chave_em = now() WHERE id = v.id;
        END IF;
        UPDATE nai_visita SET pos_visita_em = now(), estado = 'realizada', senha = NULL, atualizado_em = now() WHERE id = v.id;
        PERFORM nai_evento(v.id, 'realizada', NULL);
        n := n + 1;
      END IF;
    END IF;

    -- Realizada ha mais de 2 dias sem retorno: encerra.
    IF v.estado = 'realizada' AND now() >= coalesce(v.pos_visita_em, v.quando) + interval '2 days' THEN
      UPDATE nai_visita SET estado = 'encerrada', encerrada_em = now(), senha = NULL WHERE id = v.id;
    END IF;
  END LOOP;
  RETURN n;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_cancelar_visita(p_turno bigint, p_codigo text, p_motivo text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; sel record; v nai_visita;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor cancela a visita dele.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, NULL);
  IF sel.visita_id IS NULL THEN RETURN QUERY SELECT 'Não achei visita sua em andamento pra cancelar.'::text, NULL::text; RETURN; END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Qual delas?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = left(p_motivo, 300), senha = NULL,
                        encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'cancelada_pelo_corretor', p_motivo);
  IF v.proprietario_id IS NOT NULL AND v.ult_msg_prop_em IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
      'Passando para avisar que a visita de ' || nai_quando_humano(v.quando) || ' foi cancelada pelo corretor. Obrigada, e desculpa o transtorno.',
      'cancelada', 500);
  END IF;
  IF v.motoboy_id IS NOT NULL AND (v.ult_msg_moto_em IS NOT NULL OR v.moto_ok_em IS NOT NULL) THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
      '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
  END IF;
  RETURN QUERY SELECT 'Tudo bem, cancelei a visita. Se quiser remarcar, é só me falar.'::text, NULL::text;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_comando_tel(p_turno bigint, p_texto text)
 RETURNS TABLE(msg_tel text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t     nai_turno;
  s     text := regexp_replace(btrim(coalesce(p_texto, '')), '^\s*@?nay[\s,:;.!-]*', '', 'i');
  m     text[];
  v     nai_visita;
  q     timestamptz;
  v_ac  text;
  linhas text;
  v_msg text;
  v_lib int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'tel' THEN
    RETURN QUERY SELECT 'comando so do Tel.'::text; RETURN;
  END IF;

  -- AGENDA DE VISITAS (Tel, 15/09): a agenda de hoje em diante, separada por
  -- dia. O comando VISITAS logo abaixo continua igual ao que sempre foi.
  -- PARAR / VOLTAR ATENDIMENTO (Tel, 15/09). A chave geral sempre existiu e so
  -- se mexia por UPDATE no banco; agora ele desliga do proprio WhatsApp.
  -- Parada, ela NAO envia nada para ninguem -- as mensagens continuam chegando
  -- e ficam gravadas, e os comandos dele continuam funcionando.
  IF nai_e_comando_parada(s) THEN
    IF nai_parada_e_para(s) THEN
      UPDATE nai_config SET valor = 'sim' WHERE chave = 'pausada';
      v_msg := 'Parei o atendimento. Não respondo mais ninguém até você mandar VOLTAR ATENDIMENTO.'
               || E'\nAs mensagens continuam chegando e ficando guardadas, e seus comandos continuam valendo.';
    ELSE
      UPDATE nai_config SET valor = 'nao' WHERE chave = 'pausada';
      v_msg := 'Voltei a atender.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF nai_e_comando_agenda(s) THEN
    v_msg := nai_agenda_por_dia();
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF s ~* '^visitas\s*$' THEN
    SELECT string_agg('#' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) || ' · ' || x.estado ||
                      coalesce(' (esperando ' || x.aguardando || ')', ''), E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x WHERE nai_visita_aberta(x.estado);
    v_msg := coalesce(E'Visitas em andamento:\n' || linhas, 'Nenhuma visita em andamento.');
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- ASSUMIR <telefone> / DEVOLVER <telefone>: o Tel pega ou devolve a conversa.
  m := regexp_match(s, '^(assumir|devolver)\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    IF nai_chave(m[2]) IS NULL THEN
      v_msg := 'Não entendi o telefone. Use: ASSUMIR 92 99999-8888  ou  DEVOLVER 92 99999-8888';
    ELSIF lower(m[1]) = 'assumir' THEN
      PERFORM nai_contato_do_cadastro(m[2], NULL);
      UPDATE nai_contato SET humano_assumiu_em = coalesce(humano_assumiu_em, now()), humano_motivo = 'comando ASSUMIR do Tel'
       WHERE chave = nai_chave(m[2]);
      v_msg := 'Feito: a conversa com ' || nai_fone_fmt(m[2]) || ' é sua. A NAI não manda mais nada para essa pessoa até você mandar DEVOLVER ' || btrim(m[2]) || '.';
    ELSE
      UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave(m[2]);
      v_msg := 'Feito: a NAI volta a atender ' || nai_fone_fmt(m[2]) || '.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^acesso\s+(\d{3,5})\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    v_ac := nai_acesso_normalizar(m[2]);
    IF v_ac IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = m[1]::int) THEN
      v_msg := 'Não entendi. Use: ACESSO 5611 chave com a gente / buscar a chave na portaria / fechadura / proprietário abre';
    ELSE
      INSERT INTO nai_acesso_imovel (codigo, acesso, detalhe, fonte) VALUES (m[1]::int, v_ac, m[2], 'tel')
      ON CONFLICT (codigo) DO UPDATE SET acesso = EXCLUDED.acesso, detalhe = EXCLUDED.detalhe, fonte = 'tel', atualizado_em = now();
      v_msg := 'Guardei: no ' || nai_ref_imovel(m[1]::int) || ' o acesso é ' || v_ac || '.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^visita\s+#?(\d+)\s+(.*)$', 'i');
  IF m IS NULL THEN RETURN QUERY SELECT NULL::text; RETURN; END IF;
  SELECT * INTO v FROM nai_visita WHERE id = m[1]::bigint FOR UPDATE;
  IF v.id IS NULL OR NOT nai_visita_aberta(v.estado) THEN
    v_msg := 'Não achei a visita #' || m[1] || ' em andamento. Mande VISITAS para ver a lista.';
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF unaccent(m[2]) ~* ('^(fernando|motoboy|' || lower(unaccent(nai_acompanhante())) || ')\s+(ok|confirm)') THEN
    UPDATE nai_visita SET moto_ok_em = now() WHERE id = v.id RETURNING * INTO v;
    IF v.prop_ok_em IS NOT NULL THEN PERFORM nai_confirmar_visita(v.id, p_turno); END IF;
    v_msg := 'Feito: ' || nai_acompanhante() || ' confirmado na visita #' || v.id || CASE WHEN v.prop_ok_em IS NOT NULL THEN '. Confirmei ao corretor.' ELSE '. Ainda falta o proprietário.' END;
  ELSIF m[2] ~* '^(ok|confirm|pode)' THEN
    UPDATE nai_visita SET prop_ok_em = now(), quando = coalesce(quando_sugerido, quando) WHERE id = v.id;
    PERFORM nai_evento(v.id, 'tel_confirmou_proprietario', NULL);
    IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL AND NOT EXISTS (SELECT 1 FROM nai_acesso_imovel WHERE codigo = v.codigo) THEN
      UPDATE nai_visita SET acesso_detalhe = 'combinado pelo Tel' WHERE id = v.id;
    END IF;
    -- Sem conversa com o proprietario (foi o Tel): segue direto para o Fernando.
    IF v.proprietario_id IS NULL OR v.estado = 'com_tel' THEN
      UPDATE nai_visita SET acesso = coalesce(acesso, (SELECT acesso FROM nai_acesso_imovel WHERE codigo = v.codigo)) WHERE id = v.id;
      UPDATE nai_visita SET estado = 'aguardando_acesso' WHERE id = v.id AND acesso IS NULL;
      IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL THEN
        v_msg := 'Anotado o OK do proprietário na visita #' || v.id || '. Como é o acesso? Responda: ACESSO ' || v.codigo || ' chave com a gente / buscar a chave / fechadura / proprietário abre — e depois VISITA ' || v.id || ' OK de novo.';
        PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
        RETURN QUERY SELECT v_msg; RETURN;
      END IF;
      UPDATE nai_visita SET senha = coalesce(senha, 'com o Tel') WHERE id = v.id AND acesso = 'fechadura';
      UPDATE nai_visita SET acesso_detalhe = coalesce(acesso_detalhe, 'combinado pelo Tel') WHERE id = v.id AND acesso = 'buscar_chave';
    END IF;
    PERFORM nai_prosseguir_acesso(v.id, p_turno, false);
    v_msg := 'Feito: visita #' || v.id || ' com o OK do proprietário. Estou chamando o ' || nai_acompanhante() || '.';
  ELSIF m[2] ~* '^cancel' THEN
    UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = 'Tel: ' || m[2], senha = NULL,
                          encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'cancelada_pelo_tel', m[2]);
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
      coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
      'a visita de ' || nai_quando_humano(v.quando) || ' no ' || nai_ref_imovel(v.codigo) ||
      ' não vai dar certo. Quer que eu veja outro horário?', 'cancelada_pelo_tel', 400);
    IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
        '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
    END IF;
    v_msg := 'Feito: visita #' || v.id || ' cancelada e o corretor avisado.';
  -- VISITA <id> REMARCA <quando> (Tel, 15/09): "remarcar uma visita manualmente
  -- pelo whatsapp dele". NAO e o HORARIO logo abaixo: aquele PERGUNTA ao
  -- corretor se o horario novo serve (e a negociacao que veio do proprietario);
  -- este e decisao do Tel -- muda a hora e comunica os tres.
  ELSIF m[2] ~* '^remarc' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' REMARCA 16h  ou  VISITA ' || v.id || ' REMARCA 18/09 16h';
    ELSE
      -- Os carimbos de aviso voltam a zero: senao a agenda entenderia que ja
      -- avisou desta visita e ninguem seria lembrado no horario novo.
      UPDATE nai_visita
         SET quando = q, quando_sugerido = NULL, atualizado_em = now(),
             aviso_motoboy_em = NULL, lembrete_1h_em = NULL, lembrete_periodo_em = NULL,
             aviso_tel_em = NULL, pos_visita_em = NULL
       WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_remarcou', nai_hora_exata(q));
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'a visita ao ' || nai_ref_imovel(v.codigo) || ' foi remarcada para ' || nai_quando_humano(q) || '.',
        'tel_remarcou', 400);
      IF v.proprietario_id IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
          -- `nai_ref_imovel_prop` ja devolve "no seu imovel do X": sem isto sai
          -- "A visita ao no seu imovel do X".
          'A visita ' || nai_ref_imovel_prop(v.codigo) || ' foi remarcada para ' || nai_quando_humano(q) || '.',
          'tel_remarcou', 420);
      END IF;
      IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
        PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
          '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' passou para ' || nai_hora_exata(q) || '.',
          'tel_remarcou', 440);
      END IF;
      v_msg := 'Feito: visita #' || v.id || ' remarcada para ' || nai_hora_exata(q) || '. Avisei o corretor'
               || CASE WHEN v.proprietario_id IS NOT NULL THEN ', o proprietário' ELSE '' END
               || CASE WHEN v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL)
                       THEN ' e o ' || nai_acompanhante() || '' ELSE '' END || '.';
    END IF;
  ELSIF m[2] ~* '^hor' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' HORARIO 16h  ou  VISITA ' || v.id || ' HORARIO 13/09 16h';
    ELSE
      UPDATE nai_visita SET quando_sugerido = q, estado = 'negociando', aguardando = 'corretor', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_sugeriu_horario', nai_hora_exata(q));
      -- Mesmo card p_repassa do caminho do proprietario: com o tratamento
      -- ("Sr. Pedro, o proprietario nao consegue..."). No teste ao vivo de 13/09
      -- saia sem tratamento e com letra minuscula quando quem mandava era o Tel.
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'o proprietário não consegue ' || nai_quando_humano(v.quando) || ', mas sugeriu ' || nai_quando_humano(q) || '. Funciona pro seu cliente?',
        'tel_sugeriu', 400);
      v_msg := 'Feito: perguntei ao corretor se ' || nai_hora_exata(q) || ' serve.';
    END IF;
  ELSIF m[2] ~* '^avis' THEN
    q := nai_ler_hora_tel(m[2], now());
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi a hora. Use: VISITA ' || v.id || ' AVISA 10h';
    ELSE
      UPDATE nai_visita SET proximo_aviso_prop_em = q WHERE id = v.id;
      -- Card "Acionar o Tel" (2h antes): a resposta dele devolve a visita ao proprietario.
      UPDATE nai_visita SET estado = 'aguardando_proprietario', aguardando = 'proprietario', atualizado_em = now()
       WHERE id = v.id AND estado = 'com_tel' AND proprietario_id IS NOT NULL AND prop_ok_em IS NULL;
      v_msg := 'Combinado: mando o próximo aviso ao proprietário ' || nai_hora_exata(q) || '. Se ele não responder em ' ||
               nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar.';
    END IF;
  ELSE
    v_msg := 'Comandos: VISITAS · AGENDA DE VISITAS · VISITA ' || v.id || ' OK · VISITA ' || v.id || ' CANCELA · VISITA ' || v.id ||
             ' REMARCA 16h · VISITA ' || v.id || ' HORARIO 16h · VISITA ' || v.id || ' AVISA 10h · VISITA ' || v.id ||
             ' ' || nai_acompanhante_maiusculo() || ' OK · ACESSO <código> <como> · ASSUMIR <telefone> · DEVOLVER <telefone> · PARAR ATENDIMENTO · VOLTAR ATENDIMENTO';
  END IF;
  -- Quando o fluxo para, a Nay para os chats (13/09); o comando do Tel sobre a
  -- visita e o "pode seguir": volta a atender quem estava parado por ELA.
  IF v_msg NOT LIKE 'Comandos:%' AND v_msg NOT LIKE 'Não entendi%' THEN
    v_lib := nai_liberar_chats_da_visita(v.id);
    IF v_lib > 0 THEN v_msg := v_msg || ' Voltei a atender quem estava parado por essa visita.'; END IF;
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
  RETURN QUERY SELECT v_msg;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_conferir_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_guarda text;
  v_alvo   int;
  v_cods   int[];
  v_sem    int[] := '{}';
  v_gate   boolean := false;
  v_sugerir boolean := false;
  v_base   text;
  v_novo   text;
  v_corretor boolean;
  v_calada boolean;
  c_ok     int;
  c_card   text;
  v_n      int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('acao', 'parou', 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_corretor := t.papel = 'corretor';
  v_calada := v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$';

  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É
  -- O código do turno (card marcado, card da resposta, o que ele escreveu) e,
  -- faltando esse, o imóvel da CONVERSA. O turno guarda o que achou: é o fio
  -- para a mensagem seguinte ("me manda as fotos dele").
  SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x)::int END INTO v_alvo
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF v_alvo IS NULL THEN v_alvo := nai_imovel_da_conversa(t.contato_id, p_escreveu); END IF;
  IF v_alvo IS NOT NULL THEN
    UPDATE nai_turno SET codigo = v_alvo WHERE id = p_turno AND codigo IS DISTINCT FROM v_alvo;
  END IF;
  PERFORM nai_anotar(p_turno, 1, 'imovel_da_conversa',
                     CASE WHEN v_alvo IS NULL THEN 'passou' ELSE 'mudou' END,
                     coalesce('imóvel ' || v_alvo, 'nenhum imóvel identificado'));

  -- 02 ------------------------------------------- FOTOS LIDAS NO SITE (camada 2)
  v_n := nai_gravar_fotos_do_site(p_fotos_site);
  PERFORM nai_anotar(p_turno, 2, 'fotos_do_site', CASE WHEN v_n > 0 THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_n > 0 THEN v_n || ' fotos gravadas do anúncio' END);

  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO
  -- Não existe "vou ver e te aviso": ou responde com a base, ou o Tel responde.
  IF v_corretor AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND ((v_calada AND coalesce(p_escreveu, '') ~ '\?') OR v_texto ~* nai_re_promessa()) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu,
      CASE WHEN v_texto ~* nai_re_promessa() THEN 'prometeu retorno' ELSE 'pergunta sem resposta' END, v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'parou', 'subiu ao Tel e parou o chat');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'sem_resposta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_calada := false; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'mudou', 'a ficha respondeu no lugar');
  ELSIF v_corretor AND 'escalar' = ANY (coalesce(t.ferramentas, '{}')) AND v_texto ~* nai_re_promessa() THEN
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'cortou', 'já escalou neste turno: promessa cortada');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'promessa_cortada');
  ELSE
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'passou', NULL);
  END IF;

  -- 04 ----------------------------------------------- RESPOSTA SEM CONSULTA
  -- Afirmou sobre imóvel sem ter chamado ferramenta nenhuma.
  IF v_corretor AND '_lidas' = ANY (coalesce(t.ferramentas, '{}'))
     AND coalesce(array_length(array_remove(t.ferramentas, '_lidas'), 1), 0) = 0
     AND NOT v_calada
     AND v_texto !~ '\?\s*\S{0,3}\s*$'
     AND (coalesce(p_escreveu, '') ~ '\?' OR coalesce(p_escreveu, '') ~ '\m\d{3,5}\M')
     AND (coalesce(p_escreveu, '') || ' ' || v_texto) ~* nai_re_assunto_imovel()
     AND v_guarda IS DISTINCT FROM 'respondido_pela_base' THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'respondeu sem consultar a base', v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'parou', 'afirmou sem ferramenta: subiu ao Tel');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'resposta_sem_consulta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'mudou', 'trocada pela resposta da ficha');
  ELSE
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'passou', NULL);
  END IF;

  -- 05 ------------------------------------------- O FORMATO É DO TEL, NÃO DO MODELO
  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\?'
     AND v_texto !~* 'c[óo]digo:'
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[]) THEN
    v_base := nai_resposta_da_base(v_alvo, p_escreveu);
    IF v_base IS NOT NULL AND v_texto IS DISTINCT FROM v_base THEN
      v_texto := v_base; v_calada := false;
      v_guarda := coalesce(v_guarda || '+', '') || 'formato_da_base';
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'mudou', 'resposta da ficha, no formato dele');
    ELSE
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO
  IF v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$' THEN
    PERFORM nai_anotar(p_turno, 6, 'silencio', 'parou', 'ela não responde nada, de propósito');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 6, 'silencio', 'passou', NULL);

  -- 07 ---------------------------------------------------- A VOZ DE CADA PAPEL
  IF t.papel IN ('proprietario', 'motoboy') THEN
    v_novo := nai_sem_emoji(v_texto);
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END,
                       'proprietário e ' || nai_acompanhante() || ': voz da captação');
    v_texto := v_novo;
  ELSE
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', 'passou', NULL);
  END IF;

  -- 08 ------------------------------------------ SUGERIR VISITA (uma vez por dia)
  IF v_corretor AND v_texto !~ '\?'
     AND (v_guarda LIKE '%respondido_pela_base%' OR v_guarda LIKE '%formato_da_base%' OR v_texto ~* '^\s*sobre isso:'
          OR coalesce(t.ferramentas, '{}') && ARRAY['o_que_sei_do_imovel', 'imovel_por_codigo',
                                                    'disponibilidade_no_condominio', 'listar_no_condominio',
                                                    'resumo_do_condominio']::text[])
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND v_texto !~* nai_re_sugere_visita()
     AND coalesce((k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date, date '1900-01-01')
         <> (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND nai_visita_aberta(x.estado)) THEN
    v_sugerir := true;
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'mudou', 'sai em outra mensagem, depois da resposta');
  ELSE
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'passou', NULL);
  END IF;

  -- 09 ------------------------------------------ SUGESTÃO REPETIDA NO MESMO DIA
  IF v_corretor AND v_texto ~* nai_re_sugere_visita()
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.estado IN ('coletando', 'negociando')) THEN
    IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
      v_texto := btrim(regexp_replace(v_texto, '(\m(e|se)\s+)?' || nai_re_sugere_visita() || '[^?!\n]*[?!]?', '', 'gi'));
      v_guarda := 'visita_repetida_cortada';
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'cortou', 'já sugeriu visita hoje');
      IF v_texto = '' THEN
        RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
      END IF;
    ELSE
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = k.id;
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', 'primeira sugestão do dia, registrada');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', NULL);
  END IF;

  -- 10 --------------------------------------------- NEGOU IMÓVEL QUE EXISTE
  IF v_corretor AND v_texto ~* nai_re_nega_imovel() THEN
    SELECT i.codigo INTO c_ok
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
      JOIN imoveis i ON i.codigo::text = x
     WHERE x ~ '^[0-9]{3,5}$'
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     ORDER BY i.codigo LIMIT 1;
    IF c_ok IS NOT NULL THEN
      SELECT texto_pronto INTO c_card FROM nai_card_do_imovel(c_ok);
      IF coalesce(c_card, '') <> '' THEN
        v_texto := c_card;
        v_guarda := coalesce(v_guarda || '+', '') || 'negou_imovel_que_existe';
        PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'mudou', 'negativa trocada pelo card do ' || c_ok);
      END IF;
    ELSE
      PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', 'negou, mas o código não é nosso ou não está no ar');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', NULL);
  END IF;

  -- 11 -------------------------------------- FRASE DE VISITA SEM A FERRAMENTA
  IF v_corretor AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND v_texto ~* nai_re_frase_de_visita() THEN
    v_texto := nai_tirar_frase(v_texto, nai_re_frase_de_visita());
    v_guarda := coalesce(v_guarda || '+', '') || 'visita_sem_ferramenta';
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, k.telefone) ||
      ' (' || nai_fone_fmt(k.telefone) || ') falou de visita e eu não consegui resolver aqui. Ele disse: "' ||
      left(coalesce(p_escreveu, ''), 300) ||
      E'". Não respondi nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'visita_sem_ferramenta');
    PERFORM nai_parar_chat(k.id, 'visita que eu nao consegui tratar');
    PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'parou', 'falou de visita sem chamar a ferramenta');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'passou', NULL);

  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');
    IF v_texto = '' THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'passou', NULL);
  END IF;

  -- 13 --------------------------------------------- UMA PERGUNTA POR MENSAGEM
  IF v_corretor THEN
    v_novo := nai_uma_pergunta_da_sequencia(v_texto);
    IF v_novo IS NOT NULL THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'sequencia_uma_pergunta';
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'mudou', 'juntou duas perguntas: saiu só a primeira');
    ELSE
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
  END IF;

  -- 14 ------------------------------------------------------------- MARKDOWN
  v_novo := nai_limpar_markdown(v_texto);
  PERFORM nai_anotar(p_turno, 14, 'markdown', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END, NULL);
  v_texto := v_novo;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
  SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cods
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x
   WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF t.papel IN ('corretor', 'tel') THEN
    v_gate := coalesce(nay_deve_mandar_fotos(k.telefone, coalesce(p_escreveu, '')), false);
  END IF;
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;
  PERFORM nai_anotar(p_turno, 15, 'portao_de_fotos', CASE WHEN v_gate THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_gate THEN 'ele pediu foto; imóveis: ' || coalesce(array_to_string(v_cods, ', '), 'nenhum')
                          ELSE 'ele não pediu foto' END);

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
  IF v_gate AND v_texto ~* nai_re_nega_foto() AND coalesce(array_length(v_cods, 1), 0) >= 1 THEN
    SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = v_cods[1];
    IF v_n > 0 THEN
      v_texto := regexp_replace(v_texto, '[^.?!\n]*' || nai_re_nega_foto() || '[^.?!\n]*[.?!]?', 'segue as fotos', 'i');
      v_guarda := 'negacao_corrigida';
      PERFORM nai_anotar(p_turno, 16, 'negou_foto_que_existe', 'mudou', 'a foto existe: negativa trocada');
    END IF;
  END IF;
  IF v_gate THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_sem FROM unnest(v_cods) c
     WHERE NOT EXISTS (SELECT 1 FROM imovel_fotos fx WHERE fx.codigo = c);
    IF coalesce(array_length(v_sem, 1), 0) >= 1 THEN
      -- 14/09: antes esta conferência TROCAVA a frase por "as fotos desse eu vou
      -- confirmar com o Tel e já te mando" -- promessa de retorno, que o fluxo
      -- v17 proíbe ("não existe vou ver e te aviso"). Agora a frase de foto
      -- (promessa ou negativa) sai fora e o Tel é avisado; o corretor não recebe
      -- promessa nenhuma.
      v_texto := nai_tirar_frase(v_texto, nai_re_promete_foto() || '|' || nai_re_nega_foto());
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, o corretor ' || coalesce(k.nome_whatsapp, k.telefone) || ' pediu fotos do ' ||
        array_to_string(v_sem, ', ') || ' e não achei foto nem no banco nem no anúncio do site. Pode me mandar?',
        'foto_inexistente');
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_sem_foto';
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'mudou', 'imóvel sem foto: o Tel foi avisado');
    ELSE
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
  END IF;

  RETURN jsonb_build_object(
    'acao', 'responder',
    'texto', v_texto,
    'guarda', v_guarda,
    'alvo', v_alvo,
    'cods', to_jsonb(v_cods),
    'gate', v_gate,
    'sugerir', v_sugerir);
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_confirmar_visita(p_visita bigint, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v nai_visita; c nai_contato; m record; v_nome text; d record; v_pede text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO m FROM nai_motoboy();
  v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));
  UPDATE nai_visita SET estado = 'confirmada', aguardando = NULL, confirmada_em = now(), atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'confirmada', NULL);
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
    'Visita confirmada' || coalesce(', ' || v_nome, '') || '! ' || initcap(left(nai_quando_humano(v.quando), 1)) ||
    substr(nai_quando_humano(v.quando), 2) || ', no ' || nai_ref_imovel(v.codigo) || '.' ||
    E'\nQuem vai acompanhar sua visita é o ' || nai_acompanhante() || '' || coalesce(', ' || nai_fone_fmt(m.telefone), '') || '.' ||
    CASE WHEN nai_linha_acesso_corretor(v.acesso) <> '' THEN E'\n' || nai_linha_acesso_corretor(v.acesso) ELSE '' END,
    'visita_confirmada', 400);
  -- Fluxo v17 (Tel, 13/09): SO AGORA os dados. Cards "Checa os dados do
  -- corretor" -> CORRETOR CONHECIDO / CORRETOR NOVO, sem o "vou confirmar aqui
  -- a visita" (ela ja esta confirmada) -- "tira o vou confirmar e pede claramente".
  SELECT * INTO d FROM nai_dados_corretor(c.id);
  IF NOT coalesce(d.completo, false) THEN
    v_pede := 'Me passa o ' || nai_lista_pt(ARRAY_REMOVE(ARRAY[
      CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
      CASE WHEN d.cpf IS NULL THEN 'o CPF' END,
      CASE WHEN d.creci IS NULL THEN 'o CRECI' END], NULL)) || '?';
  ELSIF v.visitante_nome IS NULL OR v.visitante_cpf IS NULL THEN
    v_pede := 'Me passa o nome completo e o CPF do visitante?';
  END IF;
  IF v_pede IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor', v_pede, 'pedir_dados', 401);
    UPDATE nai_visita SET lembretes_dados = 0,
           proximo_lembrete_dados_em = now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
  END IF;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_contexto(p_papel text, p_contato bigint, p_visita bigint, p_teste boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v nai_visita; r text; linhas text;
BEGIN
  IF p_papel = 'corretor' THEN
    RETURN nai_contexto_corretor(p_contato);
  END IF;

  IF p_papel = 'proprietario' THEN
    IF p_visita IS NULL THEN
      SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel_prop(x.codigo) || ' · ' ||
                        coalesce(nai_quando_humano(x.quando), 'sem horário'), E'\n' ORDER BY x.id)
        INTO linhas FROM nai_visita x
       WHERE nai_visita_aberta(x.estado)
         AND (x.proprietario_id = p_contato OR (p_teste AND x.proprietario_id IS NOT NULL));
      RETURN CASE WHEN linhas IS NULL
        THEN 'NAO HA VISITA EM ANDAMENTO com este proprietario. Agradeca e diga que vai passar ao Tel, chamando resposta_do_proprietario com decisao duvida.'
        ELSE E'NAO DA PARA SABER DE QUAL VISITA ele fala. Pergunte, com educacao, qual destas:\n' || linhas END;
    END IF;
    SELECT * INTO v FROM nai_visita WHERE id = p_visita;
    RETURN 'visita #' || v.id || ' ' || nai_ref_imovel_prop(v.codigo) ||
      '. proprietario: ' || coalesce(nai_vocativo(v.proprietario_nome), 'nome nao informado') ||
      '. horario em discussao: ' || coalesce(nai_quando_humano(v.quando), 'nenhum') ||
      CASE WHEN v.quando_sugerido IS NOT NULL THEN '. horario que ELE sugeriu: ' || nai_quando_humano(v.quando_sugerido) ELSE '' END ||
      '. situacao: ' || nai_status_humano(v) ||
      CASE v.estado
        WHEN 'aguardando_proprietario' THEN '. ESPERANDO DELE: se tem como receber a visita nesse horario.'
        WHEN 'negociando' THEN CASE WHEN v.aguardando = 'proprietario' THEN '. ESPERANDO DELE: outro horario.' ELSE '. ele ja sugeriu outro horario; estamos vendo com o corretor.' END
        WHEN 'aguardando_acesso' THEN '. ESPERANDO DELE: como fica o acesso' ||
             CASE WHEN v.acesso = 'fechadura' THEN ' (a senha da fechadura)'
                  WHEN v.acesso = 'buscar_chave' THEN ' (onde e a partir de que horas pegar a chave)' ELSE '' END || '.'
        ELSE '' END;
  END IF;

  IF p_papel = 'motoboy' THEN
    SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) ||
                      ' · ' || CASE WHEN x.moto_ok_em IS NULL THEN 'ESPERANDO ELE CONFIRMAR' ELSE 'ele ja confirmou' END,
                      E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x
     WHERE nai_visita_aberta(x.estado) AND x.estado IN ('aguardando_motoboy', 'confirmada')
       AND (x.motoboy_id = p_contato OR p_teste);
    RETURN coalesce(E'visitas do ' || nai_acompanhante() || ':\n' || linhas, 'o ' || nai_acompanhante() || ' nao tem visita pendente.') ||
           CASE WHEN p_visita IS NOT NULL THEN E'\nele esta respondendo sobre a visita #' || p_visita || '.' ELSE '' END;
  END IF;
  RETURN NULL;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_estado_por_extenso(p_estado text, p_aguardando text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_estado
           WHEN 'confirmada'              THEN 'confirmada'
           WHEN 'coletando'               THEN 'montando o pedido'
           WHEN 'aguardando_proprietario' THEN 'esperando o proprietário'
           WHEN 'negociando'              THEN 'negociando o horário'
           WHEN 'aguardando_acesso'       THEN 'esperando saber como entra'
           WHEN 'aguardando_motoboy'      THEN 'esperando o ' || nai_acompanhante() || ''
           WHEN 'com_tel'                 THEN 'parada com o Tel'
           ELSE p_estado
         END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_frase_visitante(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'O ' || nai_acompanhante() || ', da nossa equipe, acompanha a visita. O visitante é ' || coalesce(v.visitante_nome, 'o cliente do corretor') ||
         coalesce(', CPF ' || nai_cpf_fmt(v.visitante_cpf), '') ||
         coalesce(', com o corretor ' || coalesce(c.nome_completo, nay_nome_de_pessoa(c.nome_whatsapp)), '') || '.'
    FROM nai_contato c WHERE c.id = v.corretor_id;
$function$;


CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  r          record;
  v_modo     text := nai_cfg('modo', 'desligado');
  v_pausada  boolean := nai_cfg('pausada', 'sim') <> 'nao';
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim';
  v_testes   text[] := nai_chaves_teste();
  v_destino  text := nai_fone_envio(nai_cfg('telefone_teste_destino', ''));
  v_tel      text;
  v_texto    text;
  v_chave_c  text;
  v_bloq     text;
  v_redir    boolean;
  v_papel_t  text;
  v_etiqueta text;
  v_nome     text;
  v_cmd      boolean;   -- e a resposta a um comando de quem pode comandar?
BEGIN
  FOR r IN
    SELECT s.* FROM nai_saida s
     WHERE s.estado = 'pendente'
       AND s.enviar_apos <= now()
       AND ((p_turno IS NOT NULL AND s.turno_id = p_turno)
         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval '3 minutes')
             AND (nai_dentro_da_janela() OR s.papel_destino = 'tel')))
     ORDER BY s.id
     LIMIT 80
     FOR UPDATE SKIP LOCKED
  LOOP
    v_bloq := NULL; v_redir := false; v_texto := r.texto; v_etiqueta := NULL;
    SELECT k.chave, k.telefone, coalesce(k.nome_completo, k.nome_whatsapp)
      INTO v_chave_c, v_tel, v_nome FROM nai_contato k WHERE k.id = r.contato_id;

    -- RESPOSTA A COMANDO: volta para quem mandou, sempre. Nao e redirecionada
    -- no modo teste (senao a resposta do Tel cairia no chat do Pedro) e nao e
    -- barrada pela pausa (senao PARAR ATENDIMENTO ficaria sem confirmacao --
    -- medido em 15/09: saiu 'bloqueado' com motivo nai_pausada, e ele nao
    -- soube se tinha funcionado). Vale so para o texto que a propria funcao de
    -- comando escreveu, indo para um telefone de `comando_telefones`.
    v_cmd := r.motivo = 'comando_tel' AND r.papel_destino = 'turno'
             AND nai_pode_comandar(v_chave_c);

    IF v_modo NOT IN ('teste', 'todos') THEN
      v_bloq := 'nai_desligada';
    ELSIF v_pausada AND NOT v_cmd THEN
      v_bloq := 'nai_pausada';
    ELSIF v_chave_c IS DISTINCT FROM r.chave_destino THEN
      v_bloq := 'contato_mudou';
    ELSIF r.papel_destino <> 'tel'
          AND (SELECT k2.humano_assumiu_em FROM nai_contato k2 WHERE k2.id = r.contato_id) IS NOT NULL
          AND NOT (r.papel_destino = 'turno' AND (SELECT t2.papel FROM nai_turno t2 WHERE t2.id = r.turno_id) = 'tel') THEN
      -- O TEL ASSUMIU esse chat: a NAI nao manda mais nada para essa pessoa
      -- (so a resposta a um comando do proprio Tel passa).
      v_bloq := 'tel_assumiu';
    ELSIF r.tipo = 'imagem'
          AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = r.codigo AND f.url = r.imagem_url)
          -- A COLAGEM tambem e imagem legitima daquele imovel (Tel, 12/09): ela
          -- nao esta em `imovel_fotos` -- e montada por nos e mora em
          -- `imovel_colagem`. Sem esta linha, toda colagem sairia bloqueada
          -- como "foto_nao_confere", que e a trava contra mandar a foto de um
          -- imovel no card de outro.
          AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = r.codigo AND c.url = r.imagem_url) THEN
      v_bloq := 'foto_nao_confere';
    -- REPETIDA: o mesmo texto para a mesma pessoa em 10 minutos não sai de novo.
    -- EXCEÇÃO (Tel, 14/09): as frases do "depois das fotos" são passo do
    -- roteiro, não repetição do modelo. Ela mandou a sugestão de visita às
    -- 20:12 e as fotos às 20:17 -- e "Ou se tiver alguma dúvida ou quiser mais
    -- imóveis..." saiu BLOQUEADA como repetida, logo depois das fotos.
    -- ...e só conta o que saiu DEPOIS do marco de conversa zerada (14/09): o
    -- pré-voo mandou as frases da sugestão em modo simulado, a conversa foi
    -- zerada, e no teste seguinte a mesma sugestão saiu BARRADA como repetida.
    -- Conversa zerada é conversa nova, também para esta trava.
    -- ...e mensagem de VISITA só é repetida se for da MESMA visita (14/09): dois
    -- pedidos de visita seguidos ao mesmo proprietário, com o mesmo texto, são
    -- duas visitas -- o segundo saía barrado e o proprietário nunca sabia.
    -- ...e RESPOSTA A COMANDO nunca e repetida (Tel, 15/09): ele mandou
    -- "agenda de visitas" duas vezes, a agenda estava igual, e a segunda saiu
    -- BLOQUEADA como repetida -- que e exatamente o sintoma de "ela nao
    -- respondeu" que ele relatou. Comando pedido duas vezes e respondido duas
    -- vezes.
    ELSIF r.tipo = 'texto' AND NOT v_cmd AND coalesce(r.motivo, '') <> 'depois_das_fotos' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    ELSIF r.tipo = 'imagem' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    END IF;

    -- MODO TESTE: o que iria para proprietario, Fernando ou Tel vai para o
    -- numero de teste, com a etiqueta de para quem iria.
    IF v_bloq IS NULL AND v_modo = 'teste' AND NOT v_cmd THEN
      IF r.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_redir := true;
        v_etiqueta := '🧪 TESTE · iria para o ' ||
          CASE r.papel_destino WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)' ELSE 'TEL' END ||
          coalesce(' ' || v_nome, '') ||
          coalesce(' · visita #' || r.visita_id, '') || E'\n' ||
          CASE r.papel_destino
            WHEN 'proprietario' THEN 'Para responder como proprietário: MARQUE esta mensagem, ou comece com P:'
            WHEN 'motoboy' THEN 'Para responder como ' || nai_acompanhante() || ': MARQUE esta mensagem, ou comece com M:'
            ELSE 'Para responder como Tel: comece com T:' END || E'\n\n';
        v_tel := v_destino;
      ELSIF r.papel_destino = 'turno' THEN
        SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
        IF v_papel_t IN ('proprietario', 'motoboy', 'tel') THEN
          v_etiqueta := '🧪 (resposta ao ' ||
            CASE v_papel_t WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || '' ELSE 'TEL' END || E')\n';
        END IF;
        -- TODAS AS MENSAGENS NO CHAT DELE (Tel, 13/09: "quero que as mensagens
        -- vao todas para mim, corretores, proprietarios e tal nesse teste"). O
        -- que iria para outro numero -- um corretor simulado, por exemplo --
        -- chega no numero de teste com a etiqueta de para quem iria. Antes isso
        -- morria como 'teste_fora_da_lista' e ele nao via a mensagem.
        IF nai_chave(v_tel) IS DISTINCT FROM nai_chave(v_destino) THEN
          v_redir := true;
          v_etiqueta := coalesce(v_etiqueta, '') || '🧪 TESTE · iria para o ' ||
            CASE coalesce(v_papel_t, 'corretor')
              WHEN 'proprietario' THEN 'PROPRIETÁRIO'
              WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)'
              WHEN 'tel' THEN 'TEL'
              ELSE 'CORRETOR' END ||
            coalesce(' ' || v_nome, '') || ' ' || nai_fone_fmt(v_tel) || E'\n\n';
          v_tel := v_destino;
        END IF;
      END IF;
      -- PAREDE DO TESTE: nada sai para numero fora da lista de teste.
      IF NOT (nai_chave(v_tel) = ANY (v_testes)) THEN
        v_bloq := 'teste_fora_da_lista';
      END IF;
    END IF;

    IF v_bloq IS NOT NULL THEN
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = v_bloq, telefone_final = v_tel, enviado_em = now()
       WHERE s.id = r.id;
      CONTINUE;
    END IF;

    IF r.tipo = 'texto' AND v_etiqueta IS NOT NULL THEN
      v_texto := v_etiqueta || v_texto;
    END IF;

    IF v_simulado THEN
      UPDATE nai_saida s SET estado = 'simulado', telefone_final = v_tel, redirecionado = v_redir,
                             enviado_em = now(), resposta = jsonb_build_object('texto_final', v_texto)
       WHERE s.id = r.id;
      IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
        UPDATE nai_visita SET ult_msg_prop_em = now() WHERE nai_visita.id = r.visita_id;
      ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
        UPDATE nai_visita SET ult_msg_moto_em = now() WHERE nai_visita.id = r.visita_id;
      END IF;
      CONTINUE;
    END IF;

    UPDATE nai_saida s SET estado = 'enviando', telefone_final = v_tel, redirecionado = v_redir
     WHERE s.id = r.id;

    id := r.id;
    rota := CASE r.tipo WHEN 'imagem' THEN 'send-image' ELSE 'send-text' END;
    telefone := v_tel;
    chave_esperada := nai_chave(v_tel);
    corpo := CASE r.tipo
               WHEN 'imagem' THEN jsonb_build_object('phone', v_tel, 'image', r.imagem_url)
               ELSE jsonb_build_object('phone', v_tel, 'message', v_texto) END;
    codigo := r.codigo;
    papel := r.papel_destino;
    redirecionado := v_redir;
    RETURN NEXT;
  END LOOP;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_linha_acesso_corretor(p_acesso text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_acesso
    -- Chave conosco: o corretor nao precisa saber do arranjo (Tel, 12/09).
    WHEN 'chave_conosco' THEN '🔑 A chave fica por nossa conta, deixa que eu providencio.'
    WHEN 'buscar_chave' THEN '🔑 O ' || nai_acompanhante() || ' pega a chave antes e abre pra vocês.'
    WHEN 'fechadura' THEN '🔐 O imóvel tem fechadura eletrônica, o ' || nai_acompanhante() || ' abre pra vocês.'
    WHEN 'proprietario_acompanha' THEN '🙋 O proprietário vai estar lá pra abrir. Chega no horário certinho, tá?'
    ELSE '' END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_minhas_visitas(p_turno bigint)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE t nai_turno; linhas text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT string_agg('• ' || nai_ref_imovel(x.codigo) || ' — ' || coalesce(nai_quando_humano(x.quando), 'sem horário') ||
                    ' — ' || CASE x.estado
                      WHEN 'coletando' THEN 'falta me passar os dados'
                      WHEN 'aguardando_proprietario' THEN 'esperando o proprietário confirmar'
                      WHEN 'negociando' THEN CASE WHEN x.aguardando = 'corretor' THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(x.quando_sugerido), 'outro horário') ELSE 'vendo outro horário com o proprietário' END
                      WHEN 'aguardando_acesso' THEN 'acertando a chave com o proprietário'
                      WHEN 'aguardando_motoboy' THEN 'confirmando com o ' || nai_acompanhante() || ''
                      WHEN 'confirmada' THEN 'confirmada'
                      WHEN 'com_tel' THEN 'o Tel está vendo'
                      WHEN 'realizada' THEN 'já aconteceu'
                      ELSE x.estado END, E'\n' ORDER BY x.quando)
    INTO linhas
    FROM nai_visita x WHERE x.corretor_id = t.contato_id AND nai_visita_aberta(x.estado);
  RETURN QUERY SELECT coalesce(linhas, 'Não tem nenhuma visita em andamento com você agora.'),
                      'repita a lista como veio.'::text;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_mudar_horario(p_turno bigint, p_codigo text, p_quando text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t   nai_turno;
  k   nai_contato;
  sel record;
  v   nai_visita;
  q   timestamptz := nai_ler_quando(p_quando);
  v_antes text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor muda o horario da visita dele.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, NULL);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'ele nao tem visita em andamento. se quer marcar, chame pedir_visita.'::text; RETURN;
  END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('De qual visita?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  IF q IS NULL THEN
    RETURN QUERY SELECT 'Pra qual dia e horário?'::text, 'chame de novo com o horario no formato AAAA-MM-DD HH:MM.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro fica bom?'::text, NULL::text; RETURN;
  END IF;

  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  v_antes := nai_quando_humano(v.quando);

  -- Horario novo em cima da hora (menos de 3h): mesma regra da visita urgente.
  IF q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 3)) THEN
    UPDATE nai_visita SET quando = q, estado = 'com_tel', aguardando = 'tel', urgente = true, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'urgente_com_tel', nai_hora_exata(q));
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, VISITA URGENTE (menos de ' || nai_cfg_int('antecedencia_minima_horas', 3) || 'h): o corretor ' ||
      coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) || ' mudou a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ') para ' || nai_hora_exata(q) ||
      E'.\nEu parei aqui e parei de responder esse corretor. A visita é sua. Se quiser que eu siga, responda VISITA ' || v.id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v.id || ': urgente (mudou o horario)');
    RETURN QUERY SELECT NULL::text, 'foi para o Tel (menos de 3h). responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- O proprietario ja foi envolvido: pergunta de novo a ele, e o Fernando
  -- (se ja tinha confirmado) fica sabendo que mudou.
  IF v.moto_ok_em IS NOT NULL OR v.estado = 'aguardando_motoboy' THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
      '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' que era ' || nai_hora_exata(v.quando) ||
      ' vai mudar de horário. Te confirmo o novo assim que o proprietário responder.', 'motoboy_mudou', 600);
  END IF;
  UPDATE nai_visita SET quando = q, quando_sugerido = NULL, prop_ok_em = NULL, moto_ok_em = NULL, confirmada_em = NULL,
                        estado = CASE WHEN proprietario_id IS NULL THEN 'com_tel' ELSE 'aguardando_proprietario' END,
                        aguardando = CASE WHEN proprietario_id IS NULL THEN 'tel' ELSE 'proprietario' END,
                        reenvios_prop = 0, aviso_demora_em = NULL, aviso_tel_em = NULL,
                        lembrete_periodo_em = NULL, lembrete_1h_em = NULL, aviso_motoboy_em = NULL,
                        urgente = q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 2)),
                        atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'corretor_mudou_horario', v_antes || ' -> ' || nai_hora_exata(q));
  IF v.proprietario_id IS NULL THEN
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o corretor pediu para mudar a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ') para ' || nai_hora_exata(q) || E'.\nResponda VISITA ' || v.id || ' OK quando o proprietário confirmar.', 'mudou_horario');
  ELSE
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
      'O corretor pediu para mudar a visita de ' || v_antes || ' para ' || nai_quando_humano(q) || '. Tem como receber nesse horário?',
      'mudou_horario', 500);
  END IF;
  RETURN QUERY SELECT 'Certo, vou ver o novo horário com o proprietário e já te retorno'::text,
    'NAO diga que o novo horario esta confirmado.'::text;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_pedir_visita(p_turno bigint, p_codigo text, p_quando text, p_qualificado text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  i        imoveis;
  v_cod    int := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int;
  v_q      timestamptz := nai_ler_quando(p_quando);
  v_conf   text;
  v_v      nai_visita;
  v_id     bigint;
  v_dono   record;
  v_moto   record;
  v_urg    boolean;
  d        record;
  v_min_h  int := nai_cfg_int('antecedencia_minima_horas', 2);
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'pedir_visita e so para o corretor. nao chame de novo neste turno.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  IF v_cod IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'voce ainda nao sabe QUAL imovel. pergunte ao corretor (ou mostre a lista com imovel_do_disparo) antes de chamar pedir_visita.'::text; RETURN;
  END IF;

  -- O codigo NAO pode vir da cabeca do modelo: ele escreveu, ou foi o unico
  -- card que mandamos para ele, ou ja existe visita aberta desse imovel.
  v_conf := nay_codigo_confirmado(k.telefone, v_cod::text, 72);
  IF v_conf = 'nao' AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado)) THEN
    RETURN QUERY SELECT NULL::text,
      ('o codigo ' || v_cod || ' nao foi dito por ele nesta conversa. NAO suponha: pergunte de qual imovel ele fala, confirmando o nome ou o codigo, e so depois chame pedir_visita.')::text;
    RETURN;
  END IF;

  SELECT * INTO i FROM imoveis WHERE codigo = v_cod;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei nenhum imóvel com o código ' || v_cod || '. Confere pra mim?')::text, NULL::text; RETURN;
  END IF;
  IF coalesce(i.e_parceiro, false) THEN
    RETURN QUERY SELECT NULL::text, 'esse imovel e de PARCERIA, a visita nao e com a gente: chame escalar_ao_tel com o pedido de visita e diga o texto_pronto que vier.'::text; RETURN;
  END IF;
  IF NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) THEN
    RETURN QUERY SELECT ('Esse imóvel saiu do mercado' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '') || '. Quer que eu veja outro parecido pro seu cliente?')::text, NULL::text; RETURN;
  END IF;
  IF coalesce(i.valor_aluguel, 0) <= 0 THEN
    RETURN QUERY SELECT NULL::text, 'esse imovel e so de VENDA: a visita de venda segue pelo Tel. chame escalar_ao_tel com o pedido de visita (codigo e horario) e diga o texto_pronto que vier.'::text; RETURN;
  END IF;

  IF v_q IS NULL THEN
    RETURN QUERY SELECT 'Claro! Me informa o dia e o horário que fica bom pro seu cliente, ok?'::text,
      'ele nao disse dia e hora (ou nao deu para entender). quando ele disser, chame pedir_visita de novo com o horario no formato AAAA-MM-DD HH:MM.'::text;
    RETURN;
  END IF;
  -- v_regra: ja passou
  IF v_q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro horário fica bom pro seu cliente?'::text,
      'quando ele disser outro horario, chame pedir_visita de novo.'::text;
    RETURN;
  END IF;
  IF v_q > now() + interval '45 days' THEN
    RETURN QUERY SELECT NULL::text, 'o horario ficou para daqui a mais de 45 dias: confirme a data com ele antes de chamar de novo.'::text; RETURN;
  END IF;

  -- SEM pergunta de renda (Tel, 12/09): isso vinha da regra 2 da tabela
  -- `regras` (14/08, da Nay antiga) e NAO existe em card nenhum do fluxo do
  -- site. O fluxo e a lista completa do que ela faz com o corretor. O
  -- parametro p_qualificado continua sendo aceito (para nao quebrar chamada
  -- antiga), mas nao segura mais nada.

  -- Ja existe visita aberta deste imovel com este corretor?
  SELECT * INTO v_v FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado);
  IF v_v.id IS NOT NULL THEN
    RETURN QUERY SELECT NULL::text,
      ('ja existe visita em andamento desse imovel com ele (' || nai_status_humano(v_v) || ', ' ||
       coalesce(nai_quando_humano(v_v.quando), 'sem horario') || '). se ele quer OUTRO horario, chame mudar_horario_da_visita; se mandou nome/CPF, chame guardar_dados_da_visita; nao chame pedir_visita.')::text;
    RETURN;
  END IF;

  v_urg := v_q < now() + make_interval(hours => v_min_h);
  SELECT * INTO v_dono FROM nai_proprietario_do_imovel(v_cod);
  SELECT * INTO v_moto FROM nai_motoboy();

  INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, urgente, qualificado,
                          proprietario_cadastro, proprietario_nome, motoboy_id, proximo_lembrete_dados_em)
       VALUES (v_cod, k.id, v_q, 'coletando', 'corretor', v_urg, NULL,
               v_dono.cadastro_id, v_dono.nome, v_moto.contato_id, NULL)
  RETURNING id INTO v_id;
  PERFORM nai_evento(v_id, 'pedida', 'horario ' || nai_hora_exata(v_q));

  -- VISITA URGENTE (Tel, 12/09): menos de 3 horas nao passa pela IA. Sobe
  -- para o Tel e a Nay PARA -- e desde 13/09 para o chat inteiro do corretor.
  IF v_urg THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', urgente = true,
                          proximo_lembrete_dados_em = NULL, atualizado_em = now()
     WHERE id = v_id;
    PERFORM nai_evento(v_id, 'urgente_com_tel', nai_hora_exata(v_q));
    PERFORM nai_avisar_tel(p_turno, v_id,
      'Tel, VISITA URGENTE (menos de ' || v_min_h || 'h): ' || nai_ref_imovel(v_cod) || ', ' || nai_hora_exata(v_q) ||
      E'.\nCorretor: ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) ||
      E'\nEu parei aqui: não falei com o proprietário nem com o ' || nai_acompanhante() || ', e parei de responder esse corretor. A visita #' || v_id || ' é sua.' ||
      E'\nSe quiser que eu siga, responda VISITA ' || v_id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v_id || ': urgente (menos de ' || v_min_h || 'h)');
    RETURN QUERY SELECT NULL::text,
      'visita URGENTE: foi para o Tel e voce PAROU neste chat. responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- FLUXO v17 (Tel, 13/09): o horario vai DIRETO ao proprietario. Os dados do
  -- corretor e do visitante so sao pedidos depois da "Visita confirmada", e
  -- nesta hora o corretor nao recebe nada ("Nada, fica calada").
  PERFORM nai_pedir_ao_proprietario(v_id, p_turno);
  RETURN QUERY SELECT NULL::text,
    'o pedido foi ao proprietario (ou ao Tel). o corretor NAO recebe nada agora: responda exatamente SILENCIO. NAO peca dados e NAO diga que a visita esta confirmada.'::text;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_prosseguir_acesso(p_visita bigint, p_turno bigint, p_devolver boolean)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  c       nai_contato;
  ac      nai_acesso_imovel;
  v_texto text;
  v_moto  text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;

  IF v.acesso IS NULL THEN
    SELECT * INTO ac FROM nai_acesso_imovel WHERE codigo = v.codigo;
    IF ac.codigo IS NOT NULL THEN
      UPDATE nai_visita SET acesso = ac.acesso, acesso_detalhe = coalesce(acesso_detalhe, ac.detalhe) WHERE id = v.id
      RETURNING * INTO v;
    ELSIF EXISTS (SELECT 1 FROM imovel_privado p WHERE p.codigo = v.codigo AND p.proprietario_acompanha) THEN
      UPDATE nai_visita SET acesso = 'proprietario_acompanha' WHERE id = v.id RETURNING * INTO v;
    END IF;
  END IF;

  IF v.acesso IS NULL THEN
    -- Pergunta curta (Tel, 13/09: "ela so pergunta: E como e para entrar? precisa de chave?").
    v_texto := 'E como é para entrar? precisa de chave?';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSIF v.acesso = 'fechadura' AND v.senha IS NULL THEN
    v_texto := 'Obrigada! Pode me passar a senha da fechadura? Ela fica só com o ' || nai_acompanhante() || ', que acompanha a visita.';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSIF v.acesso = 'buscar_chave' AND v.acesso_detalhe IS NULL THEN
    v_texto := 'Obrigada! Onde e a partir de que horas o ' || nai_acompanhante() || ' pode pegar a chave?';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSE
    -- Tudo certo com o proprietario: confirma com ele e chama o Fernando.
    -- Cards c_prop ("Visita confirmada ... de forma humanizada") e, com a
    -- chave conosco, novo_5 ("so passando para avisar que vamos fazer uma visita").
    v_texto := CASE WHEN v.acesso = 'chave_conosco'
      THEN 'Obrigada! Só passando para avisar que a visita fica ' || nai_quando_humano(v.quando) || '. '
      ELSE 'Combinado, então: visita confirmada ' || nai_quando_humano(v.quando) || '. ' END ||
      -- sem nome/CPF do visitante: no fluxo v17 eles chegam DEPOIS da confirmacao
      'O ' || nai_acompanhante() || ', da nossa equipe, acompanha a visita. Qualquer novidade eu aviso por aqui.';
    -- Card "Avisar motoboy", literal (revisao de 13/09): sem o acesso aqui -- o
    -- acesso vai no "Fechado, Fernando, agendei aqui", depois que ele confirma (card novo_8).
    v_moto := 'Olá, reservamos uma visita ao imóvel ' || nai_endereco_interno(v.codigo) ||
      coalesce(' do proprietário ' || v.proprietario_nome, '') || ', ' || nai_hora_exata(v.quando) ||
      ', pelo corretor ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' || nai_fone_fmt(c.telefone) || ').' ||
      ' Posso confirmar que você vai acompanhar?';
    UPDATE nai_visita SET estado = 'aguardando_motoboy', aguardando = 'motoboy', ult_msg_moto_em = now(),
                          reenvios_moto = 0, atualizado_em = now() WHERE id = v.id;
    IF v.motoboy_id IS NULL THEN
      UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel' WHERE id = v.id;
      PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || ') foi aceita pelo proprietário, mas não tenho o ' || nai_acompanhante() || ' cadastrado na equipe.', 'sem_motoboy');
    ELSE
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy', v_moto, 'flag_fernando', 600);
    END IF;
    PERFORM nai_evento(v.id, 'proprietario_ok', v.acesso);
  END IF;

  IF p_devolver THEN RETURN v_texto; END IF;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', v_texto, 'acesso_ou_confirmacao', 500);
  RETURN NULL;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_resposta_motoboy(p_turno bigint, p_visita text, p_decisao text, p_obs text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t   nai_turno;
  v   nai_visita;
  dec text := lower(coalesce(p_decisao, ''));
  v_id bigint := coalesce(NULLIF(regexp_replace(coalesce(p_visita, ''), '\D', '', 'g'), '')::bigint, NULL);
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'motoboy' THEN
    RETURN QUERY SELECT NULL::text, 'so para quando quem escreve e o ' || nai_acompanhante() || '.'::text; RETURN;
  END IF;
  -- A visita: a do cabecalho; senao, a que ele citou -- mas SO se for dele.
  SELECT * INTO v FROM nai_visita x
   WHERE x.id = coalesce(t.visita_id, v_id)
     AND nai_visita_aberta(x.estado)
     AND (x.motoboy_id = t.contato_id OR t.teste);
  IF v.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao sei de qual visita ele fala. mostre a lista do contexto e pergunte qual (pelo numero da visita).'::text; RETURN;
  END IF;

  IF dec IN ('confirma', 'sim', 'ok') THEN
    UPDATE nai_visita SET moto_ok_em = now(), atualizado_em = now() WHERE id = v.id RETURNING * INTO v;
    PERFORM nai_evento(v.id, 'motoboy_ok', p_obs);
    IF v.prop_ok_em IS NOT NULL AND v.estado = 'aguardando_motoboy' THEN
      PERFORM nai_confirmar_visita(v.id, p_turno);
    END IF;
    RETURN QUERY SELECT nai_texto_motoboy_ok(v), 'diga o texto_pronto como veio.'::text; RETURN;
  END IF;

  IF dec IN ('nao_pode', 'nao', 'problema', 'imprevisto') THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', moto_ok_em = NULL, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'motoboy_nao_pode', p_obs);
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o ' || nai_acompanhante() || ' disse que NÃO consegue acompanhar a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || ')' || coalesce(': "' || left(p_obs, 300) || '"', '') ||
      E'.\nNão existe acompanhante reserva. Parei com o ' || nai_acompanhante() || ' e com o corretor até você responder.\nMe responda VISITA ' || v.id || ' HORARIO <novo> ou VISITA ' || v.id || ' CANCELA.',
      'motoboy_nao_pode');
    PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': ' || nai_acompanhante() || ' nao pode');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': ' || nai_acompanhante() || ' nao pode');
    -- CALADA (Tel, 12/09): foi para o Tel, o corretor nao e avisado.
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;

  PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o ' || nai_acompanhante() || ' escreveu sobre a visita #' || v.id || ': "' ||
    left(coalesce(nullif(p_obs, ''), t.texto, ''), 300) || E'"\nParei de responder o ' || nai_acompanhante() || ' até você mandar um VISITA ' || v.id || ' ...', 'motoboy_outro');
  PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': mensagem do ' || nai_acompanhante() || '');
  RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_status_humano(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE v.estado
    WHEN 'coletando' THEN 'esperando os dados (nome completo e CPF) para pedir ao proprietário'
    WHEN 'aguardando_proprietario' THEN 'pedido feito ao proprietário, esperando ele confirmar'
    WHEN 'negociando' THEN CASE WHEN v.aguardando = 'corretor'
                             THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(v.quando_sugerido), 'outro horário') || ' e estamos esperando o corretor responder'
                             ELSE 'esperando o proprietário dizer outro horário' END
    WHEN 'aguardando_acesso' THEN 'proprietário aceitou, acertando o acesso ao imóvel'
    WHEN 'aguardando_motoboy' THEN 'proprietário confirmou, confirmando com o ' || nai_acompanhante() || ''
    WHEN 'confirmada' THEN CASE WHEN v.visitante_nome IS NULL OR v.visitante_cpf IS NULL
                              THEN 'CONFIRMADA, mas os dados que o sistema pediu ainda nao chegaram'
                              ELSE 'CONFIRMADA' END
    WHEN 'com_tel' THEN 'o Tel está resolvendo'
    WHEN 'realizada' THEN 'a visita já aconteceu, esperando o retorno do corretor'
    ELSE v.estado END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_texto_motoboy_ok(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'Fechado, ' || nai_acompanhante() || ', agendei aqui: ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '. ' ||
    CASE v.acesso
      WHEN 'chave_conosco' THEN 'A chave está com a gente: separa ela pra visita, por favor.'
      WHEN 'buscar_chave' THEN 'A chave fica com o proprietário' || coalesce(' (' || v.acesso_detalhe || ')', '') ||
                               ': pega antes da visita e devolve depois, tá?'
      WHEN 'fechadura' THEN 'É fechadura eletrônica: te mando a senha ' || nai_cfg_int('aviso_motoboy_min', 30) || ' minutos antes.'
      WHEN 'proprietario_acompanha' THEN 'Quem abre é o proprietário' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') ||
           coalesce(' (' || nai_fone_fmt((SELECT telefone FROM nai_contato WHERE id = v.proprietario_id)) || ')', '') ||
           ': combina com ele de se encontrarem lá no horário.'
      ELSE 'O acesso eu confirmo com o Tel e te aviso.' END;
$function$;
