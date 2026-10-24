-- 488 -- A Nay Corretores: o corretor que escreve no número de leads (8595) tem agente próprio
--
-- Pedro, 24/10/2026: "crie um agente diferente para receber os corretores da aba leads ... se vier do grupo é corretor, veio de
-- uma solicitação que fizemos ... precisa responder, atender e cadastrar o imóvel que ele tem na base ... se veio do grupo: 'Pode
-- me mandar o imóvel que você tem?' ... depois cadastra no site e avisa o agente de leads que tem uma opção nova ... faz parceria
-- no Kopenhagen? ... filtrado pela OLX, ou se ele pedir parceria é classificado como corretor".
-- - privado.busca_corretor.origem: 'grupo' (respondeu um pedido nosso), 'olx' (o anunciante que perguntamos) ou 'parceria'
--   (escreveu pedindo parceria / disse que é corretor); classificado_em.
-- - busca_corretor_e: o corretor classificado segue com a Nay Corretores (antes só quem tinha busca ou pedido recente).
-- - olx_organicos_novos: quem já é corretor classificado não vira lead orgânico da Nay do WhatsApp.
-- Funções antigas: /root/backups-funcoes/{busca_corretor_e,olx_organicos_novos}-AAAAMMDD-HHMM-antes-488.sql.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.busca_corretor ADD COLUMN IF NOT EXISTS origem text;
ALTER TABLE privado.busca_corretor ADD COLUMN IF NOT EXISTS classificado_em timestamptz;
ALTER TABLE privado.busca_corretor DROP CONSTRAINT IF EXISTS busca_corretor_origem_check;
ALTER TABLE privado.busca_corretor ADD CONSTRAINT busca_corretor_origem_check CHECK (origem IS NULL OR origem IN ('grupo', 'olx', 'parceria'));
COMMENT ON COLUMN privado.busca_corretor.origem IS '488: como virou corretor da Nay Corretores: grupo | olx | parceria.';

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
                                  AND m.criada_em BETWEEN p.pedido_em - interval '3 days' AND p.pedido_em)))
    FROM t;
$function$;

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

COMMIT;
