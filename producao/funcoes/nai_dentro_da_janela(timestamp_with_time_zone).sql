CREATE OR REPLACE FUNCTION public.nai_dentro_da_janela(p_ts timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (p_ts AT TIME ZONE 'America/Manaus')::time
         BETWEEN nai_cfg('janela_inicio', '06:00')::time AND nai_cfg('janela_fim', '22:00')::time;
$function$;
