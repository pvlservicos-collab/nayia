CREATE OR REPLACE FUNCTION public.nay_agenda_de_visitas(p_de timestamp with time zone, p_ate timestamp with time zone)
 RETURNS TABLE(origem text, id bigint, quando timestamp with time zone, chave text, codigo integer, com_motoboy boolean, estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT 'parceria', v.id, v.quando, c.chave, v.codigo, v.motoboy_id IS NOT NULL, v.estado
    FROM nai_visita v LEFT JOIN nai_contato c ON c.id = v.corretor_id
   WHERE v.quando >= p_de AND v.quando < p_ate AND v.estado NOT IN ('cancelada', 'expirada')
  UNION ALL
  SELECT 'leads', o.id, o.quando, nai_chave(l.telefone), o.codigo, o.corretor_telefone IS NOT NULL, o.estado
    FROM privado.olx_visita o LEFT JOIN privado.olx_lead_whatsapp l ON l.id = o.lead
   WHERE o.quando >= p_de AND o.quando < p_ate
     AND o.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada')
$function$;
