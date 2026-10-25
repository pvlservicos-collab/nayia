-- 497 (Pedro, 24-25/10): "ao corretor sugerir horário, antes da confirmação checar a agenda do motoboy ... e explicar
-- horário vago". Com o MESMO cliente, 45 min entre uma visita e outra; com OUTRO cliente, 1 hora (correção dele, 25/10).
--
-- nay_agenda_de_visitas(de, ate): as visitas vivas da agenda única (Parceria, nai_visita; Leads, privado.olx_visita) no
-- intervalo, com a chave de quem pediu (o corretor na Parceria, o cliente na Leads) e se tem motoboy marcado. Quem
-- decide o conflito é o nay-core (nay/acoes/agenda.py), que só lê.
BEGIN;

CREATE OR REPLACE FUNCTION public.nay_agenda_de_visitas(p_de timestamptz, p_ate timestamptz)
 RETURNS TABLE(origem text, id bigint, quando timestamptz, chave text, codigo integer, com_motoboy boolean, estado text)
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

REVOKE ALL ON FUNCTION public.nay_agenda_de_visitas(timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nay_agenda_de_visitas(timestamptz, timestamptz) TO nay, nay_core, nay_leitura;

COMMIT;
