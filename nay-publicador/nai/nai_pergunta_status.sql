CREATE OR REPLACE FUNCTION public.nai_pergunta_status(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(coalesce(p, ''))) ~ ('(\mainda\s+(ta|esta|tem|disponivel|livre|vago)\M'
            || '|\mdisponive(l|is)\M'
            || '|\mfoi\s+(alugad|vendid)'
            || '|\mja\s+(alugou|vendeu|foi\s+(alugad|vendid))'
            || '|\m(esta|ta)\s+(alugad|vendid|livre|vag[oa]|ocupad)'
            || '|\mstatus\M|\msituacao\s+d[oa]\M'
            || '|\mcontinua\s+(disponivel|livre|vago)'
            || '|\msegue\s+disponivel)')
     AND lower(unaccent(coalesce(p, ''))) !~ ('\m(cliente|estou|estamos|ele|ela|voce|vc|eu|fico|ficamos)\s+'
            || '(ta|esta|fica|ficou)?\s*disponive'
            || '|disponivel\s+(em\s+qualquer|qualquer|amanha|hoje|a\s+partir|pra\s+visit|para\s+visit|de\s+manha|a\s+tarde|a\s+noite)'
            || '|\m(horario|hora|dia)s?\s+disponive');
$function$
;
