-- =====================================================================
-- PAINEL -- 37: os ENVIOS de cada Nay (Tel, 15/09/2026)
--
-- Ele: "faz o painel sim de envios de cada, captação ou aluguel".
--
-- O pedido nasceu de uma pergunta dele no mesmo dia -- "foi a IA que mandou
-- isso?" -- sobre um recado que tinha saido pelo numero da Nay. Responder
-- aquilo deu quatro consultas no banco. Aqui a resposta fica na tela: cada
-- envio diz se saiu DELA ou da MAO DE ALGUEM.
--
-- COMO SE SABE QUEM MANDOU:
--   * captacao: a tabela ja guarda `origem` -- disparo, resposta (os dois sao
--     dela) e humano;
--   * locacao: pelo `message_id`. Tudo o que ELA envia fica registrado em
--     `nai_saida` com o id que a Z-API devolveu; o eco de uma mensagem digitada
--     no celular volta pelo webhook SEM esse id em `nai_saida`. E a mesma
--     comparacao que `nai_tel_assumiu` ja usa para decidir se o Tel assumiu o
--     chat -- entao a tela e o comportamento concordam por construcao.
-- =====================================================================

-- ------------------------------------------------------- LOCAÇÃO: envios
CREATE OR REPLACE VIEW vw_nai_envios AS
SELECT
  m.id,
  m.criada_em                                        AS quando,
  coalesce(m.nome, nai_fone_fmt(m.telefone))         AS para_quem,
  CASE
    WHEN s.id IS NOT NULL THEN 'a Nay'
    ELSE 'alguém digitou'
  END                                                AS quem_mandou,
  coalesce(s.papel_destino, '-')                     AS papel,
  coalesce(s.motivo, '-')                            AS motivo,
  CASE WHEN coalesce(btrim(m.texto), '') = ''
       THEN '[foto ou mídia]' ELSE left(m.texto, 160) END AS texto,
  m.status
FROM mensagens m
LEFT JOIN nai_saida s
       ON s.message_id = m.message_id AND m.message_id IS NOT NULL
WHERE m.direcao = 'enviada' AND m.fluxo = 'nai'
ORDER BY m.id DESC;

COMMENT ON VIEW vw_nai_envios IS
  'Tudo que saiu pelo numero da Nay de Locacao, dizendo se foi ela ou alguem digitando. Tel, 15/09.';

CREATE OR REPLACE VIEW vw_nai_envios_resumo AS
SELECT
  count(*)                                                      AS total,
  count(*) FILTER (WHERE quem_mandou = 'a Nay')                 AS da_nay,
  count(*) FILTER (WHERE quem_mandou = 'alguém digitou')         AS de_gente,
  count(*) FILTER (WHERE quando > now() - interval '24 hours')  AS nas_24h,
  count(*) FILTER (WHERE quando > now() - interval '24 hours'
                     AND quem_mandou = 'a Nay')                 AS da_nay_24h,
  count(DISTINCT para_quem)                                     AS pessoas
FROM vw_nai_envios;

COMMENT ON VIEW vw_nai_envios_resumo IS 'Quantos envios, e quantos foram dela. Painel da locacao.';

-- ------------------------------------------------------ CAPTAÇÃO: envios
CREATE OR REPLACE VIEW vw_captacao_envios AS
SELECT
  c.id,
  c.criada_em                                        AS quando,
  coalesce(l.nome, nai_fone_fmt(c.telefone))         AS para_quem,
  l.codigo,
  l.condominio,
  CASE c.origem
    WHEN 'disparo'  THEN 'a Nay (1ª mensagem)'
    WHEN 'resposta' THEN 'a Nay (resposta)'
    WHEN 'humano'   THEN 'alguém digitou'
    ELSE coalesce(c.origem, '-')
  END                                                AS quem_mandou,
  CASE WHEN coalesce(btrim(c.texto), '') = ''
       THEN '[foto ou mídia]' ELSE left(c.texto, 160) END AS texto,
  c.status
FROM captacao_mensagens c
LEFT JOIN captacao_leads l ON l.id = c.lead_id
WHERE c.direcao = 'enviada'
ORDER BY c.id DESC;

COMMENT ON VIEW vw_captacao_envios IS
  'Tudo que saiu pelo numero da captacao, dizendo se foi ela ou alguem digitando. Tel, 15/09.';

CREATE OR REPLACE VIEW vw_captacao_envios_resumo AS
SELECT
  count(*)                                                       AS total,
  count(*) FILTER (WHERE quem_mandou LIKE 'a Nay%')              AS da_nay,
  count(*) FILTER (WHERE quem_mandou = 'alguém digitou')          AS de_gente,
  count(*) FILTER (WHERE quem_mandou = 'a Nay (1ª mensagem)')    AS primeiras,
  count(*) FILTER (WHERE quando > now() - interval '24 hours')   AS nas_24h,
  count(DISTINCT para_quem)                                      AS pessoas
FROM vw_captacao_envios;

COMMENT ON VIEW vw_captacao_envios_resumo IS 'Quantos envios, e quantos foram dela. Painel da captacao.';

GRANT SELECT ON vw_nai_envios, vw_nai_envios_resumo,
                vw_captacao_envios, vw_captacao_envios_resumo TO nay_site_nai;
