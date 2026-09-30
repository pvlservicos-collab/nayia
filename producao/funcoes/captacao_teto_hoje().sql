CREATE OR REPLACE FUNCTION public.captacao_teto_hoje()
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT GREATEST(0, LEAST(
    COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'limite_dia'), 0),
    CASE WHEN COALESCE((SELECT btrim(valor) FROM captacao_config WHERE chave = 'rampa_desde'), '') = '' THEN 0
         -- rampa marcada para um dia que ainda não chegou: hoje é zero
         WHEN (now() AT TIME ZONE 'America/Manaus')::date
              < (SELECT btrim(valor)::date FROM captacao_config WHERE chave = 'rampa_desde') THEN 0
         ELSE LEAST(
           COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'rampa_maximo'), 0),
           COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'rampa_inicio'), 0)
             + COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'rampa_passo'), 0)
               * GREATEST(0, (now() AT TIME ZONE 'America/Manaus')::date
                             - (SELECT btrim(valor)::date FROM captacao_config WHERE chave = 'rampa_desde')))
    END))
$function$;
