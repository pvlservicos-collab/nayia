CREATE OR REPLACE FUNCTION public.olx_organicos_novos(p_janela_min integer DEFAULT 60)
 RETURNS TABLE(telefone text, primeira bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH cfg AS (
    SELECT coalesce(nullif((SELECT valor FROM privado.olx_config WHERE chave = 'organico_desde'), '')::timestamptz, now()) AS desde,
           coalesce((SELECT valor FROM privado.olx_config WHERE chave = 'whatsapp_nunca'), '') AS nunca
  ), novas AS (
    SELECT m.id, regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g') AS d
      FROM captacao_mensagens m CROSS JOIN cfg
     WHERE m.direcao = 'recebida' AND m.criada_em > greatest(cfg.desde, now() - make_interval(mins => greatest(p_janela_min, 1)))
  ), primeiras AS (
    SELECT DISTINCT ON (right(d, 8)) d, id FROM novas
     WHERE d ~ '^55[1-9][0-9]9?[0-9]{8}$'
     ORDER BY right(d, 8), id
  )
  SELECT CASE WHEN length(p.d) IN (12, 13) THEN substr(p.d, 3) ELSE p.d END, p.id
    FROM primeiras p CROSS JOIN cfg
   WHERE NOT EXISTS (SELECT 1 FROM captacao_mensagens x WHERE x.id < p.id
                       AND right(regexp_replace(coalesce(x.telefone, ''), '\D', '', 'g'), 8) = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p.d))
     AND NOT EXISTS (SELECT 1 FROM proprietarios pr WHERE right(regexp_replace(coalesce(pr.telefone, ''), '\D', '', 'g'), 8) = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM nai_contato k WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(o.telefone, 8) = right(p.d, 8))
     -- 475: o anunciante que chamamos por uma busca e o corretor dos grupos são da Nay dos corretores (olx/buscas.py)
     AND NOT EXISTS (SELECT 1 FROM privado.busca_contato bc WHERE bc.telefone8 = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM privado.busca_grupo_membro gm WHERE gm.telefone8 = right(p.d, 8))
     -- 488: o corretor classificado pela Nay Corretores não vira lead
     AND NOT EXISTS (SELECT 1 FROM privado.busca_corretor bc2 WHERE bc2.telefone8 = right(p.d, 8))
     AND position(right(p.d, 8) IN regexp_replace(cfg.nunca, '\D', '', 'g')) = 0
$function$;
