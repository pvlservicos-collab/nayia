CREATE OR REPLACE FUNCTION public.nai_followup_rodar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_hoje   date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_hora   time := (now() AT TIME ZONE 'America/Manaus')::time;
  r        record;
  v_ct     bigint;
  v_ids    bigint[];
  v_chaves text[];
  v_nome   text;
  v_pula   text;
  v_feitos int := 0;
  v_lim    int := greatest(nai_cfg_int('followup_por_minuto', 2), 1);
  v_dias   date[];
BEGIN
  IF nai_cfg('followup_ligado', 'nao') <> 'sim' THEN RETURN 0; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' OR nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 0; END IF;
  IF extract(isodow FROM now() AT TIME ZONE 'America/Manaus') = 7 THEN RETURN 0; END IF;   -- domingo
  IF v_hora < nai_cfg('followup_inicio', '09:00')::time OR v_hora > nai_cfg('followup_fim', '18:00')::time THEN RETURN 0; END IF;

  -- 415: na segunda, o sábado também (domingo ela não roda; antes o sábado nunca ganhava follow-up). O dia gravado é o
  -- último em que recebeu; quem recebeu no sábado E no domingo ganha um só.
  v_dias := CASE WHEN extract(isodow FROM v_hoje) = 1 THEN ARRAY[v_hoje - 2, v_hoje - 1] ELSE ARRAY[v_hoje - 1] END;
  FOR r IN
    SELECT e.chave, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos, min(e.primeiro_em) AS primeiro,
           max((e.primeiro_em AT TIME ZONE 'America/Manaus')::date) AS dia
      FROM imovel_enviado_no_dia e
     WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = ANY (v_dias)
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave AND f.dia_recebeu = ANY (v_dias))
     GROUP BY e.chave
     ORDER BY min(e.primeiro_em)
  LOOP
    EXIT WHEN v_feitos >= v_lim;
    v_pula := NULL;
    SELECT id INTO v_ct FROM nai_contato WHERE chave = r.chave;
    IF v_ct IS NULL THEN v_ct := nai_contato_do_cadastro(r.chave, NULL); END IF;
    v_ids := nai_contato_irmaos(v_ct);
    SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);

    IF nay_fora_da_regra_do_dia(r.chave) THEN
      v_pula := 'equipe ou teste';
    ELSIF EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (v_chaves) AND f.dia_recebeu = ANY (v_dias)) THEN
      v_pula := 'a outra linha dele já recebeu';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND m.criada_em > r.primeiro AND nai_recusou(m.texto)) THEN
      v_pula := 'recusou';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado)) THEN
      v_pula := 'visita em andamento';
    ELSIF nai_tel_com_a_conversa(v_ct) THEN
      v_pula := 'o Tel está com a conversa';
    ELSIF cadastro_whats_da_parceria(r.chave, v_ct) IS NOT NULL THEN
      v_pula := 'a Nay do cadastro está falando com ele';      -- 430
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = v_hoje) THEN
      v_pula := 'já conversou hoje';
    ELSIF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = ANY (v_chaves) AND q.decisao = 'nao') THEN
      v_pula := 'o Tel disse que não é corretor';
    ELSIF btrim(nai_cfg('so_estes_numeros', '')) <> '' AND NOT nai_na_lista_curta(v_ct, r.chave) THEN
      v_pula := 'fora da lista curta';
    END IF;

    IF v_pula IS NOT NULL THEN
      INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado, motivo)
      VALUES (r.chave, r.dia, v_ct, r.codigos, 'pulado', v_pula) ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) INTO v_nome FROM nai_contato k WHERE k.id = v_ct;
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            'Oi' || coalesce(' ' || v_nome, '') || ', seu cliente tem interesse?', 1, 'followup', now());
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            coalesce(v_nome || ', q', 'Q') || 'ualquer coisa temos muitas opções de imóveis para locação e venda, '
            || 'o que está procurando para seus clientes?', 2, 'followup', now() + interval '8 seconds');
    INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado)
    VALUES (r.chave, r.dia, v_ct, r.codigos, 'enviado') ON CONFLICT DO NOTHING;
    v_feitos := v_feitos + 1;
  END LOOP;
  RETURN v_feitos;
END;
$function$;
