-- =====================================================================
-- PAINEL -- 31: a aba da Nay de Captação (Tel, 15/09/2026)
--
-- Ele: "lá no nay locação cria outra tab em cima no mesmo menu, nay captação,
-- e põe as coisas de captação lá".
--
-- Mesmo desenho do painel da locação: só VIEWS de leitura e as chaves de
-- configuração. Nada aqui escreve em lead nenhum -- a campanha continua
-- inteirinha como está, e o painel só olha.
--
-- A role `nay_site_nai` ganha SELECT nestas views e leitura/escrita restrita
-- em `captacao_config`, do mesmo jeito que já tem em `nai_config`.
-- =====================================================================

-- ------------------------------------------------------------ o funil de hoje
CREATE OR REPLACE VIEW vw_captacao_resumo AS
SELECT
  count(*)                                                          AS leads,
  count(*) FILTER (WHERE status = 'novo')                           AS na_fila,
  count(*) FILTER (WHERE ultimo_envio_em IS NOT NULL)               AS falados,
  count(*) FILTER (WHERE respondeu_em IS NOT NULL)                  AS responderam,
  count(*) FILTER (WHERE situacao = 'disponivel')                   AS disponiveis,
  count(*) FILTER (WHERE situacao = 'alugado')                      AS alugados,
  count(*) FILTER (WHERE situacao = 'vendido')                      AS vendidos,
  count(*) FILTER (WHERE tem_outro_imovel)                          AS com_outro_imovel,
  count(*) FILTER (WHERE opt_out)                                   AS pediram_para_sair,
  count(*) FILTER (WHERE humano_assumiu_em IS NOT NULL)             AS com_o_tel,
  count(*) FILTER (WHERE status = 'concluido')                      AS concluidos,
  -- quanto tempo, em media, entre a mensagem dela e a resposta deles
  round(avg(extract(epoch FROM (respondeu_em - ultimo_envio_em)))
        FILTER (WHERE respondeu_em > ultimo_envio_em))::int          AS segundos_ate_responder
FROM captacao_leads;

COMMENT ON VIEW vw_captacao_resumo IS 'O funil inteiro da campanha de captacao. Painel, Tel 15/09.';

-- ------------------------------------------------------------- dia a dia
CREATE OR REPLACE VIEW vw_captacao_dia AS
SELECT
  d.dia,
  count(*) FILTER (WHERE (l.ultimo_envio_em AT TIME ZONE 'America/Manaus')::date = d.dia)  AS falados,
  count(*) FILTER (WHERE (l.respondeu_em   AT TIME ZONE 'America/Manaus')::date = d.dia)   AS responderam,
  count(*) FILTER (WHERE (l.fechado_em     AT TIME ZONE 'America/Manaus')::date = d.dia)   AS encerrados,
  count(*) FILTER (WHERE (l.fechado_em AT TIME ZONE 'America/Manaus')::date = d.dia
                     AND l.situacao = 'disponivel')                                        AS disponiveis,
  count(*) FILTER (WHERE (l.atualizado_em AT TIME ZONE 'America/Manaus')::date = d.dia
                     AND l.tem_outro_imovel)                                               AS com_outro_imovel
FROM (SELECT DISTINCT (x AT TIME ZONE 'America/Manaus')::date AS dia
        FROM (SELECT ultimo_envio_em AS x FROM captacao_leads WHERE ultimo_envio_em IS NOT NULL
              UNION ALL SELECT respondeu_em FROM captacao_leads WHERE respondeu_em IS NOT NULL
              UNION ALL SELECT fechado_em FROM captacao_leads WHERE fechado_em IS NOT NULL) u) d
CROSS JOIN LATERAL (SELECT 1) z
JOIN captacao_leads l ON true
GROUP BY d.dia
ORDER BY d.dia DESC;

COMMENT ON VIEW vw_captacao_dia IS 'Captacao dia a dia: quantos ela falou, quantos responderam, quantos fecharam.';

-- --------------------------------------------------- as ultimas conversas
CREATE OR REPLACE VIEW vw_captacao_conversas AS
SELECT
  l.id,
  l.nome,
  l.codigo,
  l.condominio,
  l.status,
  l.etapa,
  l.situacao,
  coalesce(l.situacao_por, CASE WHEN l.situacao IS NOT NULL THEN 'ia' END) AS situacao_por,
  l.contrato_ate,
  l.valor_locacao_pedido,
  l.tem_outro_imovel,
  l.opt_out,
  l.tentativas,
  l.humano_assumiu_em IS NOT NULL                                      AS com_o_tel,
  l.ultimo_envio_em,
  l.respondeu_em,
  (SELECT m.texto FROM captacao_mensagens m
    WHERE m.lead_id = l.id AND m.direcao = 'recebida' AND nullif(btrim(m.texto), '') IS NOT NULL
    ORDER BY m.id DESC LIMIT 1)                                        AS ele_disse,
  (SELECT m.texto FROM captacao_mensagens m
    WHERE m.lead_id = l.id AND m.direcao = 'enviada' AND nullif(btrim(m.texto), '') IS NOT NULL
    ORDER BY m.id DESC LIMIT 1)                                        AS ela_respondeu
FROM captacao_leads l
WHERE l.ultimo_envio_em IS NOT NULL
ORDER BY coalesce(l.respondeu_em, l.ultimo_envio_em) DESC;

COMMENT ON VIEW vw_captacao_conversas IS 'Ultimas conversas da captacao, com o que ele disse e o que ela respondeu.';

-- -------------------------------------------- os outros imoveis que apareceram
CREATE OR REPLACE VIEW vw_captacao_outros_imoveis AS
SELECT e.id, e.lead_id, l.nome, l.telefone, e.descricao, e.negocio, e.criado_em
  FROM captacao_imoveis_extra e
  JOIN captacao_leads l ON l.id = e.lead_id
 ORDER BY e.id DESC;

COMMENT ON VIEW vw_captacao_outros_imoveis IS
  'O que a campanha CAPTOU: imoveis que o proprietario disse ter alem do cadastrado.';

GRANT SELECT ON vw_captacao_resumo, vw_captacao_dia, vw_captacao_conversas,
                vw_captacao_outros_imoveis TO nay_site_nai;
GRANT SELECT ON captacao_config TO nay_site_nai;
GRANT UPDATE (valor) ON captacao_config TO nay_site_nai;
