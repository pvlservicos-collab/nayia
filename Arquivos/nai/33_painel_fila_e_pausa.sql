-- =====================================================================
-- PAINEL -- 33: a fila de mensagens e o botão de pausa (Tel, 15/09/2026)
--
-- Ele: "coloca lá na aba nay locação um botão de pausa e play e fila de
-- mensagens lá para eu ver e poder parar manualmente lá no site".
--
-- A fila mostra as duas pontas, porque um silencio pode estar em qualquer uma:
--   * o que CHEGOU e ainda nao virou resposta;
--   * o que ela ESCREVEU e ainda nao saiu (ou saiu barrado, e por que).
--
-- E mostra tambem quem ela NAO atendeu e o motivo da porta -- sem isso, "ela
-- nao respondeu fulano" vira caca ao tesouro.
-- =====================================================================

-- ------------------------------------------------ o que esta na fila AGORA
CREATE OR REPLACE VIEW vw_nai_fila AS
SELECT
  'saida'::text                                   AS lado,
  s.id,
  s.criado_em                                     AS quando,
  s.papel_destino                                 AS papel,
  coalesce(k.nome_completo, k.nome_whatsapp,
           nai_fone_fmt(k.telefone))              AS quem,
  s.tipo,
  CASE WHEN s.tipo = 'imagem' THEN '[foto ' || coalesce(s.codigo::text, '?') || ']'
       ELSE left(s.texto, 160) END                AS texto,
  s.estado,
  s.bloqueio,
  s.motivo,
  s.enviar_apos                                   AS sai_apos
FROM nai_saida s
LEFT JOIN nai_contato k ON k.id = s.contato_id
WHERE s.estado IN ('pendente', 'enviando')
   OR (s.estado = 'bloqueado' AND s.criado_em > now() - interval '24 hours')
UNION ALL
SELECT
  'entrada'::text,
  m.id,
  m.criada_em,
  'corretor'::text,
  coalesce(m.nome, nai_fone_fmt(m.telefone)),
  coalesce(m.origem, 'texto'),
  left(m.texto, 160),
  m.status,
  NULL, NULL, NULL
FROM mensagens m
WHERE m.fluxo = 'nai' AND m.direcao = 'recebida'
  AND m.status IN ('Recebido', 'Processando')
  AND m.criada_em > now() - interval '24 hours'
ORDER BY quando DESC;

COMMENT ON VIEW vw_nai_fila IS
  'O que chegou e ainda nao virou resposta, e o que ela escreveu e ainda nao saiu. Painel, Tel 15/09.';

-- --------------------------------------- quem bateu na porta e nao foi atendido
-- So existe quando a regra publica esta ligada. Sem esta lista, um silencio
-- legitimo (conversa do Tel) e um silencio por engano sao indistinguiveis.
CREATE OR REPLACE VIEW vw_nai_porta AS
SELECT
  t.id,
  t.criado_em                                   AS quando,
  coalesce(k.nome_completo, k.nome_whatsapp,
           nai_fone_fmt(k.telefone))            AS quem,
  k.telefone,
  left(t.texto, 120)                            AS ele_disse,
  (SELECT p.motivo FROM nai_deve_atender(k.telefone, t.texto, t.codigo) p) AS porta,
  k.liberado_em IS NOT NULL                     AS ja_liberada,
  k.humano_assumiu_em IS NOT NULL               AS com_o_tel
FROM nai_turno t
JOIN nai_contato k ON k.id = t.contato_id
WHERE t.papel = 'corretor'
  AND t.criado_em > now() - interval '48 hours'
ORDER BY t.id DESC;

COMMENT ON VIEW vw_nai_porta IS
  'Quem escreveu nas ultimas 48h e o que a porta decidiu para cada um.';

-- ------------------------------------------------------- o resumo da fila
CREATE OR REPLACE VIEW vw_nai_fila_resumo AS
SELECT
  (SELECT count(*) FROM nai_saida WHERE estado = 'pendente')                       AS a_sair,
  (SELECT count(*) FROM nai_saida WHERE estado = 'enviando')                       AS saindo,
  (SELECT count(*) FROM nai_saida
    WHERE estado = 'bloqueado' AND criado_em > now() - interval '24 hours')        AS barradas_24h,
  (SELECT count(*) FROM mensagens
    WHERE fluxo = 'nai' AND direcao = 'recebida' AND status IN ('Recebido', 'Processando')
      AND criada_em > now() - interval '24 hours')                                 AS chegando,
  (SELECT count(*) FROM nai_contato WHERE humano_assumiu_em IS NOT NULL)           AS conversas_com_o_tel,
  (SELECT count(*) FROM nai_contato WHERE liberado_em IS NOT NULL)                 AS conversas_liberadas,
  -- a mensagem mais velha que ainda nao saiu: se isto crescer, algo travou
  (SELECT round(extract(epoch FROM (now() - min(criado_em))))::int
     FROM nai_saida WHERE estado IN ('pendente', 'enviando'))                      AS mais_velha_segundos;

COMMENT ON VIEW vw_nai_fila_resumo IS 'Quantos estao na fila, dos dois lados. Painel, Tel 15/09.';

GRANT SELECT ON vw_nai_fila, vw_nai_porta, vw_nai_fila_resumo TO nay_site_nai;
