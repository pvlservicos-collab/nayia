CREATE OR REPLACE FUNCTION public.nay_imovel_ja_foi_24h(p_chave text, p_codigo integer, p_turno bigint DEFAULT NULL::bigint)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_chaves text[];
  r        imovel_enviado_no_dia;
BEGIN
  IF p_codigo IS NULL OR nay_fora_da_regra_do_dia(p_chave) THEN
    RETURN NULL;
  END IF;
  SELECT coalesce(array_agg(DISTINCT c.chave), '{}') INTO v_chaves
    FROM nai_contato k
    JOIN nai_contato c ON c.id = ANY (nai_contato_irmaos(k.id))
   WHERE k.chave = p_chave;
  v_chaves := array_append(v_chaves, p_chave);
  SELECT * INTO r
    FROM imovel_enviado_no_dia e
   WHERE e.chave = ANY (v_chaves) AND e.codigo = p_codigo
     AND e.primeiro_em > now() - interval '24 hours'
   ORDER BY e.primeiro_em DESC
   LIMIT 1;
  IF r.chave IS NULL OR (p_turno IS NOT NULL AND r.turno_id = p_turno) THEN
    RETURN NULL;
  END IF;
  RETURN r.primeiro_em;
END;
$function$;
