CREATE OR REPLACE FUNCTION public.nai_dono_disse_sim(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT length(t) BETWEEN 1 AND 80
     AND t ~ '^\W*(sim|pode|ok|okay|okey|tudo bem|tudo certo|confirmad[oa]|confirmo|combinado|fechado|beleza|blz|claro|com certeza|perfeito|certo|tranquilo|show|isso|positivo|liberado|autorizado)\M'
     AND t !~ '\m(nao|n|nunca|renov\w*|alugad\w*|vendid\w*|ocupad\w*|indisponiv\w*|outr[oa]s?|mais tarde|mais cedo|amanha|depois|so|apenas|mas|porem|infelizmente|desculp\w*|viaj\w*|reforma\w*|quem|qual|quando|onde)\M'
     AND t !~ '\d{1,2}\s*(h\M|:|horas)' AND position('?' IN t) = 0
    FROM (SELECT lower(unaccent(btrim(coalesce(p_texto, '')))) AS t) x
$function$;
