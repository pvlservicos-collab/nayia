CREATE OR REPLACE FUNCTION public.captacao_ainda_e_da_ia(p_tel text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT NOT EXISTS (SELECT 1 FROM captacao_leads
                      WHERE id = captacao_lead_por_contato(p_tel) AND humano_assumiu_em IS NOT NULL);
$function$;
