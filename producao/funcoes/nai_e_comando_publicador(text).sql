CREATE OR REPLACE FUNCTION public.nai_e_comando_publicador(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(vendeu|alugou)\M'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(posta|postar|publica|publicar|dispara|disparar)\M'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(tira|remove)\s+(o\s+|os\s+)?\d{3,5}'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?vagas\s*[.!?]*\s*$'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(resposta|descartar)\s+#?\d+'
      -- envio para alguem: exige o destino depois de para/pra/pro (a mesma
      -- preposicao obrigatoria do publicador) e nao vale "pra mim"
      OR (x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|solt)(a|ar|e|ei|ou|o)?\M.*\m(para|pra|pro|p/)\s*\S'
          AND x !~* '\m(para|pra|pro)\s+(mim|eu)\M')
  FROM (SELECT coalesce(p, '') AS x) t;
$function$;
