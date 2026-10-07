CREATE OR REPLACE FUNCTION public.captacao_ainda_e_da_ia(p_tel text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 308: a IA da captação também não responde corretor nem parceiro
  SELECT NOT EXISTS (SELECT 1 FROM captacao_leads
                      WHERE id = captacao_lead_por_contato(p_tel)
                        AND (humano_assumiu_em IS NOT NULL OR captacao_fora_da_campanha(id) IS NOT NULL));
$function$;
