CREATE OR REPLACE FUNCTION public.crm_olx_clientes_etapas()
 RETURNS TABLE(telefone text, etapa text, nome text, codigo integer, quer_visita boolean, humano boolean, atualizado_em timestamp with time zone, origem text, passo integer, finalidade text, visita_confirmada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT ON (right(l.telefone, 8)) l.telefone, l.etapa, l.nome, l.codigo, l.quer_visita, l.humano_em IS NOT NULL,
         greatest(l.atualizado_em, l.etapa_em), l.origem,
         CASE l.etapa WHEN 'filtrar' THEN 1 WHEN 'feito_busca' THEN 2 WHEN 'imoveis_enviados' THEN 3
                      WHEN 'visita' THEN CASE WHEN c.ok THEN 5 ELSE 4 END
                      WHEN 'proprietarios' THEN CASE WHEN c.ok THEN 5 ELSE 4 END
                      WHEN 'fechamento' THEN 5 WHEN 'finalizado' THEN 5 ELSE 0 END,
         nullif(l.filtros->>'finalidade', ''),
         c.ok
    FROM privado.olx_lead_whatsapp l
    CROSS JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM privado.olx_visita v
                                        WHERE v.lead = l.id AND v.estado = 'confirmada') AS ok) c
   ORDER BY right(l.telefone, 8), l.criado_em DESC
$function$;
