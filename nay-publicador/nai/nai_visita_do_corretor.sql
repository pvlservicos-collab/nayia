CREATE OR REPLACE FUNCTION public.nai_visita_do_corretor(p_contato bigint, p_codigo text, p_estados text[])
 RETURNS TABLE(visita_id bigint, qtd integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_cod int := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int;
BEGIN
  IF v_cod IS NOT NULL THEN
    RETURN QUERY SELECT x.id, 1 FROM nai_visita x
                  WHERE x.corretor_id = p_contato AND x.codigo = v_cod AND nai_visita_aberta(x.estado)
                    AND (p_estados IS NULL OR x.estado = ANY (p_estados))
                  ORDER BY x.id DESC LIMIT 1;
    RETURN;
  END IF;
  RETURN QUERY SELECT min(x.id), count(*)::int FROM nai_visita x
                WHERE x.corretor_id = p_contato AND nai_visita_aberta(x.estado)
                  AND (p_estados IS NULL OR x.estado = ANY (p_estados))
               HAVING count(*) > 0;
END;
$function$
;
