CREATE OR REPLACE FUNCTION public.nai_ler_pedido_de_envio(p text)
 RETURNS TABLE(telefone text, codigos integer[])
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  s       text := btrim(coalesce(p, ''));
  v_fone  text := '(?:55[\s.-]*)?\(?[0-9]{2}\)?[\s.-]*[0-9]{4,5}[\s.-]*[0-9]{4}';
  v_verbo text := '(?:envi|m[a]?nd|repass|encaminh)[a-zçã]*';
  v_voc   text := '(?:@?nay[\s,;:.!?-]*)?';
  v_cods  text := '(?:(?:o|os|a|as|c[oó]d(?:igo)?s?)[\s:=.-]*)?([0-9]{3,5}(?:(?:\s*[,;]\s*|\s+e\s+|\s+)(?:(?:o|os)\s+)?[0-9]{3,5})*)';
  m       text[];
BEGIN
  -- "92 8110-1119 envia o 3210"
  m := regexp_match(s, '^' || v_voc || '(' || v_fone || ')[\s,;:.-]+' || v_voc
                       || v_verbo || '\s+' || v_cods || '\s*$', 'i');
  -- "envia 92 8110-1119 o 3210" / "envia pra 92 ... o 3210"
  IF m IS NULL THEN
    m := regexp_match(s, '^' || v_voc || v_verbo || '\s+(?:(?:para|pra|pro)\s+|p/\s*)?('
                         || v_fone || ')\s+' || v_cods || '\s*$', 'i');
  END IF;
  -- "manda o 3210 e o 5729 para 92 8110-1119"
  IF m IS NULL THEN
    m := regexp_match(s, '^' || v_voc || v_verbo || '\s+' || v_cods
                         || '\s+(?:para|pra|pro|p/)\s*(' || v_fone || ')\s*$', 'i');
    IF m IS NOT NULL THEN
      m := ARRAY[m[2], m[1]];
    END IF;
  END IF;
  IF m IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT m[1],
           (SELECT array_agg(z.c ORDER BY z.o)
              FROM (SELECT DISTINCT ON (x[1]) x[1]::int AS c, o
                      FROM regexp_matches(m[2], '([0-9]{3,5})', 'g') WITH ORDINALITY AS r(x, o)
                     ORDER BY x[1], o) z);
END;
$function$
;
