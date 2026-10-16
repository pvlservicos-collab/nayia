-- 390: o LEAD ORGÂNICO no número de captação (92 8595-6408): a Nay do WhatsApp atende quem escreve pela primeira vez
--
-- Pedro, 16/10/2026: "92 9 8250-8556 quando chega lead novo a nay deve atender normal, e perguntar se ele quer imóvel, esse
-- vem com a tag orgânico, e depois fazer o mesmo filtro que ela faz da olx, pode pôr ela para atender ele".
--
-- privado.olx_lead_whatsapp passa a guardar também o cliente orgânico: sem conversa da OLX (chat NULL), origem 'organico'.
-- olx_organicos_novos(janela) acha quem escreveu no 8595 pela PRIMEIRA vez nos últimos minutos e é gente de fora:
--   · telefone brasileiro de verdade (nem @lid nem grupo);
--   · nenhuma mensagem antes neste número (nem dele nem para ele);
--   · não é dono da campanha (captacao_leads), nem proprietário do cadastro, nem já conhecido pela Nay da Parceria
--     (nai_contato: corretor, equipe), nem cliente da OLX, nem número da lista whatsapp_nunca;
--   · e só depois de `organico_desde` (o que chegou antes de ligar não é chamado de volta sozinho).
-- crm_olx_clientes_etapas ganha a origem (o CRM põe a tag "Orgânico" e mostra nas etapas da aba Captação).
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.olx_lead_whatsapp ALTER COLUMN chat DROP NOT NULL;
ALTER TABLE privado.olx_lead_whatsapp ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'olx';
ALTER TABLE privado.olx_lead_whatsapp DROP CONSTRAINT IF EXISTS olx_lead_whatsapp_origem_check;
ALTER TABLE privado.olx_lead_whatsapp ADD CONSTRAINT olx_lead_whatsapp_origem_check CHECK (origem IN ('olx', 'organico'));
CREATE UNIQUE INDEX IF NOT EXISTS olx_lead_whatsapp_organico_um ON privado.olx_lead_whatsapp (right(telefone, 8)) WHERE origem = 'organico';

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
     AND position(right(p.d, 8) IN regexp_replace(cfg.nunca, '\D', '', 'g')) = 0
$function$;
COMMENT ON FUNCTION public.olx_organicos_novos(integer) IS
  '390: quem escreveu no 8595-6408 pela primeira vez e é de fora (não é dono, corretor, equipe nem cliente da OLX)';

DROP FUNCTION IF EXISTS public.crm_olx_clientes_etapas();
CREATE FUNCTION public.crm_olx_clientes_etapas()
 RETURNS TABLE(telefone text, etapa text, nome text, codigo integer, quer_visita boolean, humano boolean,
               atualizado_em timestamptz, origem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT ON (right(l.telefone, 8)) l.telefone, l.etapa, l.nome, l.codigo, l.quer_visita, l.humano_em IS NOT NULL,
         greatest(l.atualizado_em, l.etapa_em), l.origem
    FROM privado.olx_lead_whatsapp l
   ORDER BY right(l.telefone, 8), l.criado_em DESC
$function$;
REVOKE ALL ON FUNCTION public.crm_olx_clientes_etapas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_clientes_etapas() TO nay_disparo;

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('organico_atende', 'sim', '390: a Nay do WhatsApp atende quem escreve pela primeira vez no 8595-6408 (lead orgânico): sim | nao'),
  ('organico_desde', to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF'), '390: só quem escreveu depois disto entra sozinho como orgânico')
ON CONFLICT (chave) DO NOTHING;

-- o 92 98250-8556 ("Boa tarde", 16/10 15:31): o Pedro mandou a Nay atender
INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, etapa, etapa_em, assumido_em, ultima_lida, perfil)
SELECT NULL, '92982508556', 'organico', 'filtrar', now(), now(),
       (SELECT coalesce(max(id), 0) FROM captacao_mensagens WHERE id < 9023), '{"procura": "escreveu direto no WhatsApp"}'::jsonb
 WHERE NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = '82508556');

COMMIT;
