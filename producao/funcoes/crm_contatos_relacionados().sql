CREATE OR REPLACE FUNCTION public.crm_contatos_relacionados()
 RETURNS TABLE(cliente text, contato text, em timestamp with time zone, motivos text, codigos integer[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH pares AS (
    SELECT right(regexp_replace(l.telefone, '\D', '', 'g'), 8) AS cliente,
           right(regexp_replace(m.telefone, '\D', '', 'g'), 8) AS contato,
           m.criada_em AS em, e.tipo AS motivo, e.codigo
      FROM privado.olx_cliente_enviada e
      JOIN captacao_mensagens m ON m.message_id = e.message_id AND m.direcao = 'enviada'
      JOIN privado.olx_lead_whatsapp l ON l.id = e.lead
     WHERE e.enviado_em > now() - interval '90 days'
    UNION ALL
    SELECT right(regexp_replace(d.cliente_tel, '\D', '', 'g'), 8), right(regexp_replace(d.dono_tel, '\D', '', 'g'), 8),
           coalesce(d.dono_perguntado_em, d.criada_em), 'duvida', d.codigo
      FROM privado.duvida d
     WHERE d.linha = 'captacao' AND d.dono_linha = 'captacao' AND d.dono_tel IS NOT NULL
  )
  SELECT cliente, contato, max(em), string_agg(DISTINCT motivo, ','),
         array_remove(array_agg(DISTINCT codigo), NULL)
    FROM pares
   WHERE length(contato) = 8 AND contato <> cliente
     -- quem também é cliente da Nay Leads é lead: fica na lista de cima
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(regexp_replace(o.telefone, '\D', '', 'g'), 8) = contato)
   GROUP BY cliente, contato
$function$;
