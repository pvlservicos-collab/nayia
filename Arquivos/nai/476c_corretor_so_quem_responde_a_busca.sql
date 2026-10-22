-- 476c: a Nay dos corretores só entra na conversa de quem RESPONDE a uma busca (22/10, no primeiro teste da 476: ela pegou
-- o Clemerson, a Laura Motta e o Carlus, que estavam no meio de visitas com a equipe pelo 8595, e o nosso próprio número
-- da Parceria, que é membro dos grupos; em teste, nada saiu para eles).
--   busca_nossos_numeros()  os nossos números (Parceria 9445-3618, captação 8595-6408, oficial 8456-0874), a equipe e os
--                           de whatsapp_nunca (o Tel): nunca são corretores da busca nem são perguntados na OLX
--   busca_corretor_e        só: (a) o anunciante que perguntamos (busca_contato, 7 dias); (b) o membro de um grupo onde a
--                           busca ATIVA foi pedida de verdade (não em teste) nos últimos 3 dias e que não falava conosco
--                           pelo 8595 nos 3 dias antes do pedido; (c) quem já está oferecendo imóvel (cadastrando/ofertado)

BEGIN;

CREATE OR REPLACE FUNCTION public.busca_nossos_numeros()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT array_agg(DISTINCT right(d, 8)) FROM (
    SELECT unnest(ARRAY['9294453618', '9285956408', '9284560874']) AS d
    UNION ALL SELECT regexp_replace(telefone, '\D', '', 'g') FROM equipe
    UNION ALL SELECT regexp_replace(x, '\D', '', 'g')
      FROM privado.olx_config, regexp_split_to_table(valor, '[,;\s]+') x WHERE chave = 'whatsapp_nunca'
  ) n WHERE length(d) >= 8;
$function$;

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
     AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = t.t8)
     AND (EXISTS (SELECT 1 FROM privado.busca_corretor b WHERE b.telefone8 = t.t8 AND b.estado IN ('cadastrando', 'ofertado'))
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
                                  AND m.criada_em BETWEEN p.pedido_em - interval '3 days' AND p.pedido_em)))
    FROM t;
$function$;

-- as 5 conversas que a primeira versão abriu por engano (ninguém recebeu nada: estava em teste)
DELETE FROM privado.busca_corretor WHERE estado = 'conversando' AND busca IS NULL AND codigo IS NULL;

COMMIT;
