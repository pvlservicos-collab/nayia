-- =====================================================================
-- PAINEL -- 39: os envios da locação, contados pela fonte certa
--              (Tel, 15/09/2026)
--
-- A primeira versao desta tela partia do ECO -- a copia que volta pelo webhook
-- quando o numero envia algo -- e perguntava, para cada eco, se existia uma
-- saida dela com aquele id. Media, e o numero nao fechava: 144 dela contra 807
-- "alguem digitou", quando `nai_saida` tinha 534 mensagens dela.
--
-- O MOTIVO: o eco so passou a ser gravado em 14/09. Tudo o que ela mandou de 11
-- a 13/09 -- 362 mensagens -- nao tem eco nenhum, e a tela as classificaria
-- como "alguem digitou" ou simplesmente nao as mostraria. Uma tela que erra
-- isso e pior do que nao ter tela: e sobre ela que se responde "foi a IA que
-- mandou?".
--
-- A FONTE CERTA sao as duas pontas, cada uma no que sabe:
--   * o que E dela vem de `nai_saida` -- ali esta registrado tudo o que ela
--     mandou, desde sempre;
--   * o que e de GENTE vem do eco que nao tem par em `nai_saida` -- nem pelo
--     id, nem pelo texto na mesma janela de tempo. E a mesma comparacao que
--     `nai_tel_assumiu` usa para decidir se o Tel assumiu o chat.
-- =====================================================================

DROP VIEW IF EXISTS vw_nai_envios_resumo;
DROP VIEW IF EXISTS vw_nai_envios;

CREATE VIEW vw_nai_envios AS
-- 1) o que ELA mandou: a fonte e a caixa de saida dela
SELECT
  s.id,
  s.criado_em                                        AS quando,
  coalesce(k.nome_completo, k.nome_whatsapp,
           nai_fone_fmt(k.telefone))                 AS para_quem,
  'a Nay'::text                                      AS quem_mandou,
  s.papel_destino                                    AS papel,
  coalesce(s.motivo, '-')                            AS motivo,
  CASE WHEN s.tipo = 'imagem' THEN '[foto ' || coalesce(s.codigo::text, '') || ']'
       ELSE left(s.texto, 160) END                   AS texto,
  s.estado                                           AS status
FROM nai_saida s
LEFT JOIN nai_contato k ON k.id = s.contato_id
WHERE s.estado IN ('enviado', 'enviando', 'simulado')

UNION ALL

-- 2) o que ALGUEM digitou: saiu pelo numero e nao tem par na caixa dela
SELECT
  m.id + 1000000,                                    -- id proprio, para nao colidir
  m.criada_em,
  -- o NOME da mensagem enviada e de quem ENVIOU ("Nay Mendes"), nao de quem
  -- recebeu -- por isso o destinatario vem do contato, pelo telefone da
  -- conversa. Sem isto a coluna "Para quem" mostrava "Nay Mendes" em toda
  -- linha, que e o oposto do que ela promete.
  coalesce((SELECT coalesce(k2.nome_completo, k2.nome_whatsapp) FROM nai_contato k2
             WHERE k2.chave = nai_chave(m.telefone)),
           nai_fone_fmt(m.telefone)),
  'alguém digitou'::text,
  '-'::text,
  '-'::text,
  CASE WHEN coalesce(btrim(m.texto), '') = ''
       THEN '[foto ou mídia]' ELSE left(m.texto, 160) END,
  coalesce(m.status, '-')
FROM mensagens m
WHERE m.direcao = 'enviada' AND m.fluxo = 'nai'
  AND NOT EXISTS (SELECT 1 FROM nai_saida s
                   WHERE s.message_id IS NOT NULL AND s.message_id = m.message_id)
  AND NOT EXISTS (SELECT 1 FROM nai_saida s
                   WHERE s.estado IN ('enviado', 'enviando')
                     AND coalesce(btrim(m.texto), '') <> ''
                     AND btrim(s.texto) = btrim(m.texto)
                     AND s.criado_em BETWEEN m.criada_em - interval '20 minutes'
                                         AND m.criada_em + interval '20 minutes')
ORDER BY quando DESC;

COMMENT ON VIEW vw_nai_envios IS
  'Tudo que saiu pelo numero da locacao: o dela vem da caixa de saida, o de gente vem do eco sem par. Tel, 15/09.';

CREATE VIEW vw_nai_envios_resumo AS
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

GRANT SELECT ON vw_nai_envios, vw_nai_envios_resumo TO nay_site_nai;
