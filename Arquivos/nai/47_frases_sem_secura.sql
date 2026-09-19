-- =====================================================================
-- NAI -- 47: as frases fixas deixam de ser secas (Tel, 16/09/2026)
--
-- Ele: "ela respondeu de forma muito rispida, nem deu o bom dia dele -- ela so
-- perguntou 'de qual imovel voce fala?'". "Quero cordialidade, educacao e
-- delicadeza sem forcar, e cumprimentos curtos."
--
-- O ARQUIVO 46 nao alcancava esta parte. Aquelas frases nao sao do modelo: sao
-- texto_pronto, e o prompt manda repetir texto_pronto EXATAMENTE. Nenhuma regra
-- de voz escrita no prompt mudava uma virgula delas. Por isso, com o Carlus,
-- saiu "de qual imovel voce fala? me manda o codigo" -- minusculo e seco --
-- enquanto no resto da conversa ela tratava todo mundo por Sr.
--
-- O que muda, par a par:
--   "de qual imovel voce fala? me manda o codigo"
--     -> "De qual imovel o Sr. fala? Se tiver o codigo me manda, ou me diz o
--         bairro que eu procuro aqui."  (oferece o caminho, para ele nao ter
--                                        que ir procurar codigo nenhum)
--   "qual desses?"                     -> "E de algum destes que te mandei?"
--   "De qual visita?"                  -> "Claro! De qual visita?"
--   "Pra qual dia e horario?"          -> "Certo! Pra qual dia e horario fica melhor?"
--   "Esses dados sao pra qual visita?" -> "So me confirma de qual visita sao esses dados?"
--
-- O "o Sr." / "a Sra." de nay_qual_imovel sai do cadastro, aqui dentro, porque
-- essa funcao recebe o telefone. nay_imovel_do_disparo nao recebe, entao a
-- frase sai com "voce" e o modelo troca -- e a regra que o 46 pos no prompt.
--
-- Gerado por `scratchpad/patch47.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nay_qual_imovel(p_telefone text, p_horas integer DEFAULT 48)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_tel   text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_lista text;
  v_n     int;
  -- CORDIALIDADE (Tel, 16/09): "o Sr." / "a Sra." / "voce", pelo cadastro.
  -- Sem isto a frase saia com "voce" para todo mundo, inclusive para quem ela
  -- trata por Sr. no resto da conversa.
  v_pron  text;
BEGIN
  SELECT CASE nay_tratamento_por_nome(k.nome_whatsapp)
           WHEN 'Sr.'  THEN 'o Sr.'
           WHEN 'Sra.' THEN 'a Sra.'
           ELSE 'você' END
    INTO v_pron
    FROM nai_contato k
   WHERE k.chave = nai_chave(coalesce(p_telefone, ''));
  v_pron := coalesce(v_pron, 'você');
  SELECT count(*), string_agg(linha, chr(10) ORDER BY quando DESC)
    INTO v_n, v_lista
  FROM (
    SELECT DISTINCT ON (e.codigo)
           '• ' || e.codigo || ' — '
           || coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'imóvel')
           || coalesce(' (' || i.bairro || ')', '') AS linha,
           max(e.enviado_em) AS quando
      FROM envios e
      LEFT JOIN imoveis i ON i.codigo::text = e.codigo
     WHERE e.destino = 'corretor'
       AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = v_tel
       AND e.enviado_em > now() - make_interval(hours => greatest(p_horas,1))
     GROUP BY e.codigo, i.condominio_nome, i.tipo, i.bairro
     ORDER BY e.codigo, max(e.enviado_em) DESC
     LIMIT 6
  ) s;

  IF coalesce(v_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('De qual imóvel ' || v_pron || ' fala? Se tiver o código me manda, '
       || 'ou me diz o bairro que eu procuro aqui.')::text,
      ('voce NAO sabe de qual imovel ele fala e NAO mandou card nenhum para ele '
       || 'nas ultimas ' || p_horas || ' horas. PERGUNTE o codigo. NAO CHUTE, NAO '
       || 'use o ultimo imovel que voces conversaram e NAO use o ultimo imovel '
       || 'postado nos grupos -- sao mais de 3 por dia, e mandar informacao de um '
       || 'imovel como se fosse de outro e o pior erro possivel.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('É de algum destes que te mandei?' || chr(10) || v_lista || chr(10)
     || '• nenhum desses — me diz o bairro ou o código')::text,
    ('sao ' || v_n || ' imoveis que voce mandou para ele. Mostre a lista do '
     || 'texto_pronto e deixe ele escolher -- nao peca o codigo seco, ele teria '
     || 'que ir procurar. A opcao "nenhum desses" tem que aparecer: ele pode '
     || 'estar falando de um card que veio de outro corretor, do grupo ou do '
     || 'site, e menu sem saida so empurra ele a escolher errado. '
     || 'NAO ESCOLHA POR ELE. '
     || 'Devolva o cumprimento dele antes da lista, se ele cumprimentou.')::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nay_imovel_do_disparo(p_horas integer DEFAULT 12)
 RETURNS TABLE(texto_pronto text, codigo text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_n    int;
  v_cod  text;
  v_nome text;
BEGIN
  SELECT count(DISTINCT e.codigo), min(e.codigo)
    INTO v_n, v_cod
    FROM envios e
   WHERE e.destino = 'grupo'
     AND e.enviado_em > now() - make_interval(hours => greatest(p_horas, 1));

  IF coalesce(v_n, 0) = 0 THEN
    RETURN QUERY SELECT
      ('De qual imóvel você fala? Se tiver o código me manda, '
       || 'ou me diz o bairro que eu procuro aqui.')::text,
      NULL::text,
      ('nao houve disparo em grupo nas ultimas ' || p_horas || ' horas, entao nao da '
       || 'para saber de qual imovel ele fala. PERGUNTE o codigo. Nao chute. '
       || 'Devolva o cumprimento dele antes, se ele cumprimentou, e troque o '
       || '"voce" da frase pelo tratamento dele.')::text;
    RETURN;
  END IF;

  IF v_n > 1 THEN
    -- Sao ~4 disparos por dia, entao ambiguidade e a REGRA, nao a excecao.
    -- Perguntar "me manda o codigo" obriga o corretor a ir procurar; listar
    -- o que saiu deixa ele responder "o Acquarelle" e seguir.
    SELECT string_agg(linha, chr(10) ORDER BY ultimo DESC) INTO v_nome
      FROM (
        SELECT '• ' || e.codigo || ' — '
               || coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'imóvel') AS linha,
               max(e.enviado_em) AS ultimo
          FROM envios e
          LEFT JOIN imoveis i ON i.codigo::text = e.codigo
         WHERE e.destino = 'grupo'
           AND e.enviado_em > now() - make_interval(hours => greatest(p_horas, 1))
         GROUP BY e.codigo, i.condominio_nome, i.tipo
      ) s;

    RETURN QUERY SELECT
      ('É de algum destes que saiu no grupo?' || chr(10) || coalesce(v_nome,''))::text,
      NULL::text,
      ('foram ' || v_n || ' imoveis nos grupos nesse periodo, entao "esse" e '
       || 'ambiguo. Mostre a lista do texto_pronto e deixe ele escolher -- NAO '
       || 'peca o codigo seco, ele teria que ir procurar. E NAO chute: mandar '
       || 'informacao de um imovel como se fosse de outro e o pior erro possivel. '
       || 'Devolva o cumprimento dele antes da lista, se ele cumprimentou.')::text;
    RETURN;
  END IF;

  SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'o imóvel')
    INTO v_nome FROM imoveis i WHERE i.codigo::text = v_cod;

  RETURN QUERY SELECT
    ''::text,
    v_cod,
    ('ele esta falando do imovel ' || v_cod || ' (' || coalesce(v_nome,'?')
     || '), o unico que foi para os grupos nas ultimas ' || p_horas
     || ' horas. Use imovel_por_codigo com esse codigo para responder. Se a '
     || 'pergunta dele nao for respondida pela consulta, escale ao Tel COM esse '
     || 'codigo, para a resposta virar conhecimento do imovel certo.')::text;
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
    RETURN QUERY SELECT ('Claro! De qual visita?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  IF q IS NULL THEN
    RETURN QUERY SELECT 'Certo! Pra qual dia e horário fica melhor?'::text, 'chame de novo com o horario no formato AAAA-MM-DD HH:MM.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro fica bom pro seu cliente?'::text, NULL::text; RETURN;
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
  RETURN QUERY SELECT 'Certo! Vou ver o novo horário com o proprietário e já te retorno.'::text,
    'NAO diga que o novo horario esta confirmado.'::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_guardar_dados_visita(p_turno bigint, p_codigo text, p_visitante_nome text, p_visitante_cpf text, p_corretor_nome text, p_corretor_cpf text, p_corretor_creci text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t       nai_turno;
  k       nai_contato;
  sel     record;
  v       nai_visita;
  d       record;
  v_vcpf  text := nai_cpf_valido(p_visitante_cpf);
  v_ccpf  text := nai_cpf_valido(p_corretor_cpf);
  v_vnome text := nai_nome_completo(p_visitante_nome);
  v_cnome text := nai_nome_completo(p_corretor_nome);
  v_creci text := NULLIF(btrim(coalesce(p_corretor_creci, '')), '');
  v_falta text[] := '{}';
  v_erro  text[] := '{}';
  v_res   text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'so o corretor passa os dados da visita.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, ARRAY['confirmada']);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao ha visita confirmada esperando dados. se ele quer marcar uma visita, chame pedir_visita.'::text; RETURN;
  END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Só me confirma de qual visita são esses dados?' || E'\n' || nai_lista_visitas_corretor(k.id))::text,
      'pergunte de qual imovel sao os dados e chame de novo com o codigo.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;

  -- Os do CORRETOR (se veio). Grava no cadastro antigo quando ele existe,
  -- como a ferramenta antiga fazia, e sempre no contato da NAI.
  IF p_corretor_cpf IS NOT NULL AND btrim(p_corretor_cpf) <> '' AND v_ccpf IS NULL THEN
    v_erro := v_erro || 'o seu CPF não confere (confere os 11 números?)'::text;
  END IF;
  IF v_ccpf IS NOT NULL OR v_cnome IS NOT NULL OR (v_creci IS NOT NULL AND length(v_creci) BETWEEN 3 AND 30) THEN
    UPDATE nai_contato SET cpf = coalesce(v_ccpf, cpf), nome_completo = coalesce(v_cnome, nome_completo),
                           creci = coalesce(CASE WHEN length(v_creci) BETWEEN 3 AND 30 THEN v_creci END, creci),
                           atualizado_em = now()
     WHERE id = k.id;
    IF k.chave !~ '^lid:' THEN
      UPDATE corretores c SET nome = coalesce(v_cnome, c.nome),
                              nome_origem = CASE WHEN v_cnome IS NOT NULL THEN 'manual' ELSE c.nome_origem END,
                              creci = coalesce(NULLIF(btrim(c.creci), ''), CASE WHEN length(v_creci) BETWEEN 3 AND 30 THEN v_creci END),
                              ultima_interacao = now()
       WHERE nai_chave(c.telefone) = k.chave;
    END IF;
  END IF;

  -- Os do VISITANTE.
  IF p_visitante_cpf IS NOT NULL AND btrim(p_visitante_cpf) <> '' AND v_vcpf IS NULL THEN
    v_erro := v_erro || 'o CPF do visitante não confere (confere os 11 números?)'::text;
  END IF;
  IF p_visitante_nome IS NOT NULL AND btrim(p_visitante_nome) <> '' AND v_vnome IS NULL THEN
    v_erro := v_erro || 'preciso do nome COMPLETO do visitante (nome e sobrenome)'::text;
  END IF;
  UPDATE nai_visita SET visitante_nome = coalesce(v_vnome, visitante_nome),
                        visitante_cpf = coalesce(v_vcpf, visitante_cpf), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  SELECT * INTO d FROM nai_dados_corretor(k.id);
  IF d.nome_completo IS NULL THEN v_falta := v_falta || 'seu nome completo'::text; END IF;
  IF d.cpf IS NULL THEN v_falta := v_falta || 'seu CPF'::text; END IF;
  IF d.creci IS NULL THEN v_falta := v_falta || 'seu CRECI'::text; END IF;
  IF v.visitante_nome IS NULL THEN v_falta := v_falta || 'o nome completo do visitante'::text; END IF;
  IF v.visitante_cpf IS NULL THEN v_falta := v_falta || 'o CPF do visitante'::text; END IF;

  IF array_length(v_falta, 1) >= 1 OR array_length(v_erro, 1) >= 1 THEN
    UPDATE nai_visita SET proximo_lembrete_dados_em =
             now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
    RETURN QUERY SELECT
      (CASE WHEN array_length(v_erro, 1) >= 1 THEN initcap(left(array_to_string(v_erro, '. '), 1)) || substr(array_to_string(v_erro, '. '), 2) || '. ' ELSE '' END ||
       CASE WHEN coalesce(array_length(v_erro, 1), 0) = 0 AND d.completo AND v.visitante_nome IS NULL AND v.visitante_cpf IS NULL
            THEN 'Anotado! Agora pode passar o nome completo e o CPF do visitante?'
            WHEN array_length(v_falta, 1) >= 1
            THEN 'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita' ELSE '' END)::text,
      'quando ele mandar, chame guardar_dados_da_visita de novo.'::text;
    RETURN;
  END IF;

  -- Tudo certo (fluxo v17, Tel 13/09): a visita JA esta confirmada. Os dados
  -- do visitante vao ao proprietario agora ("coloca para mandar depois") e o
  -- corretor nao recebe nada ("Nada, fica calada").
  UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
  IF NOT EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'dados_ao_proprietario') THEN
    PERFORM nai_evento(v.id, 'dados_completos', NULL);
    IF v.proprietario_id IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', nai_texto_dados_visitante(v), 'dados_visitante', 500);
    ELSE
      PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, dados do visitante da visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || '): ' || nai_texto_dados_visitante(v), 'dados_visitante');
    END IF;
    PERFORM nai_evento(v.id, 'dados_ao_proprietario', NULL);
  END IF;
  RETURN QUERY SELECT NULL::text,
    'dados completos e repassados. o corretor NAO recebe nada: responda exatamente SILENCIO.'::text;
END;
$function$;
