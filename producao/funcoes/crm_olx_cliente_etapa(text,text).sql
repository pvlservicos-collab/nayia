CREATE OR REPLACE FUNCTION public.crm_olx_cliente_etapa(p_telefone text, p_etapa text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  UPDATE privado.olx_lead_whatsapp SET etapa = p_etapa, etapa_em = now(), atualizado_em = now()
   WHERE right(telefone, 8) = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)
     AND p_etapa IN ('filtrar', 'feito_busca', 'imoveis_enviados', 'visita', 'proprietarios', 'fechamento', 'finalizado')
  RETURNING true
$function$;
