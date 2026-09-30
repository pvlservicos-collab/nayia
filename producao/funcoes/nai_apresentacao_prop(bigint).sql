CREATE OR REPLACE FUNCTION public.nai_apresentacao_prop(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH pessoa AS (
    SELECT coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]) AS ids
  ), fones AS (
    SELECT right(regexp_replace(c.telefone, '\D', '', 'g'), 8) AS f
      FROM nai_contato c, pessoa WHERE c.id = ANY (pessoa.ids) AND c.telefone ~ '\d{8}'
  )
  SELECT CASE
    WHEN nullif(btrim(coalesce(nai_cfg('apresentacao_proprietario', ''), '')), '') IS NULL THEN ''
    -- já conversamos por este número: nada de apresentação
    WHEN EXISTS (SELECT 1 FROM nai_saida s, pessoa
                  WHERE s.contato_id = ANY (pessoa.ids) AND s.estado IN ('enviado', 'enviando', 'simulado'))
      OR EXISTS (SELECT 1 FROM mensagens m
                  WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) IN (SELECT f FROM fones))
      THEN ''
    ELSE btrim(nai_cfg('apresentacao_proprietario', '')) || E'\n\n'
  END;
$function$;
