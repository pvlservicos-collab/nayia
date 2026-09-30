CREATE OR REPLACE FUNCTION public.captacao_config_religou()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE captacao_config
     SET valor = to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD')
   WHERE chave = 'rampa_desde' AND COALESCE(btrim(valor), '') = '';
  UPDATE captacao_config SET valor = '' WHERE chave = '_disjuntor' AND COALESCE(valor, '') <> '';
  RETURN NULL;
END $function$;
