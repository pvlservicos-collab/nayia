CREATE OR REPLACE FUNCTION public.site_ia_cotacao()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce((SELECT jsonb_build_object('usd_brl', c.brl, 'fonte', c.fonte,
                                             'atualizado_em', to_char(c.atualizado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
                                             'horas', round(extract(epoch FROM now() - c.atualizado_em) / 3600, 1))
                     FROM privado.ia_cotacao c WHERE c.moeda = 'USD'), '{}'::jsonb)
$function$;
