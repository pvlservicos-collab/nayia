CREATE OR REPLACE FUNCTION public.busca_corretor_e(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH t AS (SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) AS t8)
  SELECT length(t.t8) = 8
     AND NOT (t.t8 = ANY (coalesce(busca_nossos_numeros(), '{}')))
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(o.telefone, 8) = t.t8)
     AND (
       -- 581: o anunciante que a busca perguntou na OLX responde à busca, mesmo sendo dono da campanha (com ela parada)
       (EXISTS (SELECT 1 FROM privado.busca_contato c WHERE c.telefone8 = t.t8 AND c.em > now() - interval '7 days')
        AND NOT EXISTS (SELECT 1 FROM captacao_leads l
                         WHERE right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = t.t8
                           AND l.humano_assumiu_em IS NULL))
       OR (
     NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = t.t8)
     AND (EXISTS (SELECT 1 FROM privado.busca_corretor b WHERE b.telefone8 = t.t8 AND b.estado IN ('cadastrando', 'ofertado'))
          -- 488: o corretor já classificado (pediu parceria, veio da OLX ou do grupo) segue com a Nay Corretores
          OR EXISTS (SELECT 1 FROM privado.busca_corretor b WHERE b.telefone8 = t.t8 AND b.origem IS NOT NULL AND b.estado <> 'humano')
          OR EXISTS (SELECT 1 FROM privado.busca_contato c WHERE c.telefone8 = t.t8 AND c.em > now() - interval '7 days')
          OR EXISTS (
            SELECT 1
              FROM privado.busca_grupo_membro gm
              CROSS JOIN LATERAL (
                SELECT min((g->>'em')::timestamptz) AS pedido_em
                  FROM privado.busca_cliente bc, jsonb_array_elements(bc.grupos) g
                 WHERE bc.estado = 'buscando' AND coalesce(g->>'teste', 'false') <> 'true'
                   AND g->>'grupo' = ANY (gm.grupos) AND (g->>'em')::timestamptz > now() - interval '3 days') p
             WHERE gm.telefone8 = t.t8 AND p.pedido_em IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                                WHERE right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = t.t8
                                  AND m.criada_em BETWEEN p.pedido_em - interval '3 days' AND p.pedido_em)))))
    FROM t;
$function$;
