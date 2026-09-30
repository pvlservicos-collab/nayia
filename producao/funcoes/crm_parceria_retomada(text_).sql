CREATE OR REPLACE FUNCTION public.crm_parceria_retomada(p_telefones text[])
 RETURNS TABLE(telefone text, etapa text, resumo text, proximo_passo text, imoveis integer[], criado_em timestamp with time zone, valido_ate timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT pe.telefone, r.etapa, r.resumo, r.proximo_passo, r.imoveis, r.criado_em, r.valido_ate
    FROM crm_pessoas(p_telefones) pe
    JOIN LATERAL (SELECT * FROM nai_retomada_resumo r WHERE r.contato_id = ANY (pe.ids)
                   ORDER BY r.criado_em DESC LIMIT 1) r ON true;
$function$;
