CREATE OR REPLACE FUNCTION public.nai_pede_mais_em_conta(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 225: só aqui a busca sai da faixa de -20%/+10% para baixo
  SELECT x ~ '\m(mais em conta|mais barat\w*|mais acessive\w*|abaixo (disso|desse valor|do valor)|menos que isso|menor valor|qualquer valor|pode ser (mais|menor|abaixo)|nao tem problema o valor|o valor nao importa|independente do valor)'
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x) t;
$function$;
