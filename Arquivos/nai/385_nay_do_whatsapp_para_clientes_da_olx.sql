-- 385: a NAY DO WHATSAPP para os clientes da OLX (número de captação, 92 8595-6408): as etapas, o que ela mandou e a busca
--
-- Pedro, 16/10/2026: "a nay de whatsapp vai assumir já sabendo as coisas que a da olx mandou, e lá ela vai perguntar se
-- quer agendar visitar ou receber mais opções ... o roteiro é: até que valor? quais bairros? se for 3 quartos, serve 2?
-- condomínio com elevador abaixo de 500 mil: serve escada? crédito aprovado ou simulação? ... vou pegar as opções no meu
-- sistema" e "a nay vai mandar os imóveis com a mesma tecnologia que a nay de parceria usa ... cada imóvel separadinho
-- card + fotos, aí espera carregar todas as fotos e vai para o próximo". E as etapas da aba Captação do CRM: FILTRAR,
-- FEITO BUSCA, IMÓVEIS ENVIADO, VISITA, PROPRIETÁRIOS, FECHAMENTO, FINALIZADOS.
--
-- Quem roda é o serviço nay-olx (olx/whatsapp.py), que já tem o banco, a chave do modelo e a Z-API da captação (config do
-- vigia). A conversa é a de captacao_mensagens: tudo o que chega no 8595-6408 já cai ali (quem não é dono da campanha fica
-- sem lead_id e o fluxo dos donos não responde). Os donos da campanha não são tocados.
--   · privado.olx_lead_whatsapp (384) ganha a etapa, os filtros, o que já foi enviado e onde a leitura parou;
--   · privado.olx_cliente_enviada: o id de cada mensagem que a Nay mandou (o eco da Z-API não é "gente respondendo");
--   · olx_cliente_buscar(filtros, excluir, limite): a busca da Nay de Parceria (core_imovel_busca, ofertável, faixa de 25%
--     abaixo a 10% acima do valor, o bairro pedido e os de perto, quartos, mobília, tipo; venda com financiamento não
--     oferece imóvel que não aceita financiamento);
--   · as chaves em privado.olx_config: whatsapp_responde nasce 'teste' (só os números de whatsapp_teste: o do Pedro).
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.olx_lead_whatsapp
  ADD COLUMN IF NOT EXISTS etapa text NOT NULL DEFAULT 'nova',
  ADD COLUMN IF NOT EXISTS etapa_em timestamptz,
  ADD COLUMN IF NOT EXISTS filtros jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS enviados integer[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS ultima_lida bigint NOT NULL DEFAULT 0,      -- captacao_mensagens.id da última mensagem dela já lida
  ADD COLUMN IF NOT EXISTS humano_em timestamptz,                       -- alguém da equipe escreveu: a Nay cala
  ADD COLUMN IF NOT EXISTS parada_motivo text,
  ADD COLUMN IF NOT EXISTS visita jsonb;
ALTER TABLE privado.olx_lead_whatsapp DROP CONSTRAINT IF EXISTS olx_lead_whatsapp_etapa_check;
ALTER TABLE privado.olx_lead_whatsapp ADD CONSTRAINT olx_lead_whatsapp_etapa_check
  CHECK (etapa IN ('nova', 'filtrar', 'feito_busca', 'imoveis_enviados', 'visita', 'proprietarios', 'fechamento', 'finalizado'));
COMMENT ON COLUMN privado.olx_lead_whatsapp.etapa IS
  '385: nova (ainda não chamada) · filtrar · feito_busca · imoveis_enviados · visita · proprietarios · fechamento · finalizado';

CREATE TABLE IF NOT EXISTS privado.olx_cliente_enviada (
  message_id text PRIMARY KEY,
  lead       bigint NOT NULL,
  tipo       text NOT NULL,          -- texto | card | foto
  codigo     integer,
  enviado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS olx_cliente_enviada_lead ON privado.olx_cliente_enviada (lead, enviado_em);
COMMENT ON TABLE privado.olx_cliente_enviada IS '385: o que a Nay do WhatsApp mandou pelo 8595-6408 (o eco da Z-API não cala a Nay).';

CREATE OR REPLACE FUNCTION public.olx_cliente_buscar(p_filtros jsonb, p_excluir integer[] DEFAULT '{}'::integer[],
                                                     p_limite integer DEFAULT 5)
 RETURNS TABLE(codigo integer, bairro text, condominio text, tipo text, quartos integer, preco numeric, perto boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH f AS (
    SELECT CASE WHEN lower(coalesce(p_filtros->>'finalidade', '')) LIKE 'vend%' THEN 'venda' ELSE 'locacao' END AS fin,
           lower(coalesce(p_filtros->>'tipo', '')) AS tipo,
           CASE WHEN coalesce(p_filtros->>'teto', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p_filtros->>'teto')::numeric END AS teto,
           CASE WHEN coalesce(p_filtros->>'quartos', '') ~ '^[0-9]+$' THEN (p_filtros->>'quartos')::int END AS quartos,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           lower(coalesce(p_filtros->>'mobilia', '')) AS mob,
           lower(coalesce(p_filtros->>'financiamento', '')) ~ '(financ|simula|aprovad)' AS financia
  ), pedidos AS (     -- os bairros que ela disse, no nome do cadastro ("pq 10" -> parque 10 de novembro)
    SELECT DISTINCT nay_normalizar_lugar(coalesce(nay_bairro_parecido(b), b), true) AS n
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros' ELSE '[]'::jsonb END) b
     WHERE btrim(b) <> ''
  ), perto AS (
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      FROM unnest(nai_bairros_ao_redor(ARRAY(SELECT n FROM pedidos))) x
     WHERE nay_normalizar_lugar(x, true) NOT IN (SELECT n FROM pedidos)
  ), c AS (
    SELECT i.codigo, i.bairro, i.condominio_nome, i.tipo, i.quartos, nay_normalizar_lugar(i.bairro, true) AS bn,
           CASE WHEN f.fin = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END AS p
      FROM core_imovel_busca i CROSS JOIN f
     WHERE i.ofertavel AND NOT coalesce(i.e_parceiro, false)
       AND CASE WHEN f.fin = 'venda' THEN i.de_venda ELSE i.de_locacao END
       AND CASE WHEN f.tipo IN ('', 'tanto_faz') THEN i.tipo IN ('apartamento', 'casa', 'casa_condominio', 'flat', 'cobertura')
                WHEN f.tipo = 'casa' THEN i.tipo IN ('casa', 'casa_condominio')
                ELSE i.tipo = f.tipo END
       AND (f.quartos IS NULL OR coalesce(i.quartos, 0) >= f.quartos - CASE WHEN f.menos THEN 1 ELSE 0 END)
       AND (f.mob NOT IN ('mobiliado', 'semi') OR i.mobilia = f.mob)
       AND NOT (i.codigo = ANY (coalesce(p_excluir, '{}')))
       -- quem vai financiar não recebe imóvel que não aceita financiamento (a regra dos pedidos dos grupos, 371)
       AND NOT (f.fin = 'venda' AND f.financia AND EXISTS (
             SELECT 1 FROM imoveis x WHERE x.codigo = i.codigo AND lower(coalesce(x.extras->>'aceita financiamento', '')) LIKE 'n%'))
  )
  SELECT c.codigo, c.bairro, c.condominio_nome, c.tipo, c.quartos, c.p, (c.bn IN (SELECT n FROM perto))
    FROM c CROSS JOIN f
   WHERE c.p > 0
     AND (f.teto IS NULL OR c.p BETWEEN f.teto * 0.75 AND f.teto * 1.10)
     AND (NOT EXISTS (SELECT 1 FROM pedidos) OR c.bn IN (SELECT n FROM pedidos) OR c.bn IN (SELECT n FROM perto))
   ORDER BY (c.bn IN (SELECT n FROM perto)), abs(c.p - coalesce(f.teto, c.p)), c.codigo
   LIMIT least(greatest(coalesce(p_limite, 5), 1), 10)
$function$;
COMMENT ON FUNCTION public.olx_cliente_buscar(jsonb, integer[], integer) IS
  '385: a busca da Nay do WhatsApp dos clientes da OLX (a mesma regra da Nay de Parceria: faixa -25%/+10%, bairro e perto).';

-- as etapas para o CRM (aba Captação): uma linha por telefone, a mais recente
CREATE OR REPLACE FUNCTION public.crm_olx_clientes_etapas()
 RETURNS TABLE(telefone text, etapa text, nome text, codigo integer, quer_visita boolean, humano boolean, atualizado_em timestamptz)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT ON (right(l.telefone, 8)) l.telefone, l.etapa, l.nome, l.codigo, l.quer_visita, l.humano_em IS NOT NULL,
         greatest(l.atualizado_em, l.etapa_em)
    FROM privado.olx_lead_whatsapp l
   ORDER BY right(l.telefone, 8), l.criado_em DESC
$function$;
REVOKE ALL ON FUNCTION public.crm_olx_clientes_etapas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_clientes_etapas() TO nay_disparo;

-- a equipe muda a etapa pelo CRM (Proprietários, Fechamento, Finalizados são dela)
CREATE OR REPLACE FUNCTION public.crm_olx_cliente_etapa(p_telefone text, p_etapa text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  UPDATE privado.olx_lead_whatsapp SET etapa = p_etapa, etapa_em = now(), atualizado_em = now()
   WHERE right(telefone, 8) = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)
     AND p_etapa IN ('filtrar', 'feito_busca', 'imoveis_enviados', 'visita', 'proprietarios', 'fechamento', 'finalizado')
  RETURNING true
$function$;
REVOKE ALL ON FUNCTION public.crm_olx_cliente_etapa(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_cliente_etapa(text, text) TO nay_disparo;

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('whatsapp_responde', 'teste', '385: a Nay do WhatsApp dos clientes da OLX (8595-6408): nao | teste (só whatsapp_teste) | sim'),
  ('whatsapp_teste', '96991712835', '385: os números que a Nay do WhatsApp atende em modo teste (DDD + número, vírgula)'),
  ('whatsapp_nunca', '92994717316', '385: números que ela nunca chama (o Telmario, a segunda conta do Pedro)'),
  ('whatsapp_silencio_s', '20', '385: segundos de silêncio da pessoa antes de responder'),
  ('whatsapp_humano_cala_horas', '24', '385: alguém da equipe escreveu para a pessoa: a Nay fica quieta por estas horas')
ON CONFLICT (chave) DO NOTHING;

COMMIT;
