CREATE OR REPLACE FUNCTION public.nai_texto_sem_os_barrados(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_linha text; v_cod int; v_saida text[] := '{}'; v_tirou int := 0;
BEGIN
  IF p_texto IS NULL THEN RETURN NULL; END IF;
  FOREACH v_linha IN ARRAY string_to_array(p_texto, E'\n') LOOP
    v_cod := (regexp_match(v_linha, '\m(\d{3,5})\s*[—–-]\s*\w'))[1]::int;
    IF v_cod IS NOT NULL AND nai_imovel_barrado(v_cod) THEN
      v_tirou := v_tirou + 1;
      CONTINUE;
    END IF;
    v_saida := v_saida || v_linha;
  END LOOP;
  IF v_tirou = 0 THEN RETURN p_texto; END IF;
  RETURN array_to_string(v_saida, E'\n');
END;
$function$
;
