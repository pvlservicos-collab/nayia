CREATE OR REPLACE FUNCTION public.campanha_baixa_destinatarios(p_baixa bigint)
 RETURNS TABLE(lead bigint, telefone text, tel8 text, nome text, recebeu_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT l.id, l.telefone, right(l.telefone, 8), l.nome, max(o.enviado_em)
    FROM campanha_baixa b
    JOIN olx_cliente_enviada o ON o.codigo = b.codigo AND o.tipo = 'card'
     AND o.enviado_em > b.confirmada_em - make_interval(days => coalesce(nullif(regexp_replace(coalesce(
           (SELECT valor FROM olx_config WHERE chave = 'campanha_baixa_dias'), ''), '\D', '', 'g'), '')::int, 30))
    JOIN olx_lead_whatsapp l ON l.id = o.lead
   WHERE b.id = p_baixa
     AND l.humano_em IS NULL AND l.etapa NOT IN ('fechamento', 'finalizado', 'proprietarios')
     AND NOT (right(l.telefone, 8) = ANY (site_painel_internos()))
     AND position(right(l.telefone, 8) IN regexp_replace(coalesce((SELECT valor FROM olx_config WHERE chave = 'whatsapp_nunca'), ''), '\D', '', 'g')) = 0
     AND NOT EXISTS (SELECT 1 FROM campanha_baixa_aviso a WHERE a.codigo = b.codigo AND a.tel8 = right(l.telefone, 8))
     AND NOT EXISTS (SELECT 1 FROM nai_proprietario_do_imovel(b.codigo) d WHERE right(regexp_replace(coalesce(d.telefone, ''), '\D', '', 'g'), 8) = right(l.telefone, 8))
     AND NOT (b.finalidade = 'locacao' AND coalesce(l.filtros->>'finalidade', '') ~* '^vend')
     AND NOT (b.finalidade = 'venda' AND coalesce(l.filtros->>'finalidade', '') ~* '^(loc|alug)')
   GROUP BY l.id, l.telefone, l.nome
   ORDER BY max(o.enviado_em) DESC
$function$;
