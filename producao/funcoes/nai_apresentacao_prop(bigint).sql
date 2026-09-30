CREATE OR REPLACE FUNCTION public.nai_apresentacao_prop(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN nullif(btrim(coalesce(nai_cfg('apresentacao_proprietario', ''), '')), '') IS NULL
      THEN ''
    -- ja falamos com ele antes por aqui: nao se apresenta de novo
    WHEN EXISTS (SELECT 1 FROM nai_saida s
                  WHERE s.contato_id = p_contato
                    AND s.papel_destino = 'proprietario'
                    AND s.estado IN ('enviado', 'enviando', 'simulado'))
      THEN ''
    ELSE btrim(nai_cfg('apresentacao_proprietario', '')) || E'\n\n'
  END;
$function$;
