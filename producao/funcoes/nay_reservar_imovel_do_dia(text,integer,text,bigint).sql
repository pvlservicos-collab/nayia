CREATE OR REPLACE FUNCTION public.nay_reservar_imovel_do_dia(p_chave text, p_codigo integer, p_origem text, p_turno bigint DEFAULT NULL::bigint)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_dia    date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_chaves text[];
  r        imovel_enviado_no_dia;
BEGIN
  IF p_codigo IS NULL OR nay_fora_da_regra_do_dia(p_chave) THEN
    RETURN NULL;
  END IF;

  -- Dois pedidos iguais chegando juntos: o segundo espera o primeiro gravar.
  PERFORM pg_advisory_xact_lock(hashtext('imovel_24h:' || p_codigo));

  -- Todas as linhas da pessoa (telefone e @lid).
  SELECT coalesce(array_agg(DISTINCT c.chave), '{}') INTO v_chaves
    FROM nai_contato k
    JOIN nai_contato c ON c.id = ANY (nai_contato_irmaos(k.id))
   WHERE k.chave = p_chave;
  v_chaves := array_append(v_chaves, p_chave);

  -- O ÚLTIMO envio nas últimas 24 horas.
  SELECT * INTO r
    FROM imovel_enviado_no_dia e
   WHERE e.chave = ANY (v_chaves) AND e.codigo = p_codigo
     AND e.primeiro_em > now() - interval '24 hours'
   ORDER BY e.primeiro_em DESC
   LIMIT 1;

  IF r.chave IS NULL THEN
    INSERT INTO imovel_enviado_no_dia (chave, codigo, dia, origem, turno_id)
    VALUES (p_chave, p_codigo, v_dia, p_origem, p_turno)
    ON CONFLICT (chave, codigo, dia) DO UPDATE
       SET primeiro_em = now(), origem = EXCLUDED.origem, turno_id = EXCLUDED.turno_id;
    RETURN NULL;
  END IF;

  -- A mesma resposta continuando (card e fotos são linhas separadas).
  IF p_turno IS NOT NULL AND r.turno_id = p_turno THEN
    RETURN NULL;
  END IF;

  RETURN r.primeiro_em;
END;
$function$;
