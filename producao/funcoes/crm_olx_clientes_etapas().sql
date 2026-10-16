CREATE OR REPLACE FUNCTION public.crm_olx_clientes_etapas()
 RETURNS TABLE(telefone text, etapa text, nome text, codigo integer, quer_visita boolean, humano boolean, atualizado_em timestamp with time zone, origem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT ON (right(l.telefone, 8)) l.telefone, l.etapa, l.nome, l.codigo, l.quer_visita, l.humano_em IS NOT NULL,
         greatest(l.atualizado_em, l.etapa_em), l.origem
    FROM privado.olx_lead_whatsapp l
   ORDER BY right(l.telefone, 8), l.criado_em DESC
$function$;
