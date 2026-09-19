-- =====================================================================
-- NAI -- 20: metricas POR IMOVEL no painel (Tel, 15/09/2026)
--
-- Ele: "quero la nas metricas as metricas por imoveis, quantas vezes os
-- imoveis foram mandados, e quantas visitas foram agendadas para eles".
--
-- COMO SE CONTA "FOI MANDADO", e por que nao e obvio: `nai_saida.codigo` so
-- vem preenchido nas FOTOS (686 linhas hoje); o card e a lista de ofertas sao
-- texto, e o codigo mora dentro do texto. Entao a oferta e contada lendo o
-- texto com `nay_codigos_citados`, a mesma funcao que o resto do sistema usa
-- para achar codigo em mensagem -- e que ja sabe que "paga ate 4000" e valor,
-- nao o imovel 4000.
--
-- Uma mensagem que lista tres imoveis conta UMA oferta para cada um dos tres,
-- que e o que ele quer saber: quantas vezes aquele imovel foi parar na frente
-- de um corretor.
--
-- So conta o que foi para CORRETOR: aviso ao Tel e recado a proprietario
-- citam codigo o tempo todo e nao sao oferta de imovel a ninguem.
-- =====================================================================

CREATE OR REPLACE VIEW vw_nai_metricas_imovel AS
WITH ofertas AS (
  SELECT s.id,
         s.criado_em,
         c.codigo::int AS codigo
    FROM nai_saida s
    CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(s.texto), '{}'::text[])) AS c(codigo)
   WHERE s.tipo = 'texto'
     AND s.papel_destino = 'corretor'
     AND s.estado = 'enviado'
     -- so codigo que E imovel: `nay_codigos_citados` ja tira valor em reais,
     -- mas um numero de cinco digitos solto no texto (um ramal, uma senha)
     -- ainda passa, e apareceu como "imovel 99201" na primeira medicao.
     AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c.codigo::int)
),
fotos AS (
  SELECT s.codigo, count(*) AS fotos, count(DISTINCT s.contato_id) AS pessoas_com_foto,
         max(s.criado_em) AS ultima_foto
    FROM nai_saida s
   WHERE s.tipo = 'imagem' AND s.codigo IS NOT NULL AND s.estado = 'enviado'
   GROUP BY s.codigo
),
mandados AS (
  SELECT o.codigo, count(*) AS vezes_mandado, max(o.criado_em) AS ultima_vez
    FROM ofertas o GROUP BY o.codigo
),
visitas AS (
  SELECT v.codigo,
         count(*) AS visitas_pedidas,
         count(*) FILTER (WHERE v.confirmada_em IS NOT NULL) AS visitas_confirmadas,
         count(*) FILTER (WHERE v.estado = 'cancelada') AS visitas_canceladas,
         count(*) FILTER (WHERE nai_visita_aberta(v.estado)) AS visitas_em_pe,
         max(v.quando) AS proxima_visita
    FROM nai_visita v GROUP BY v.codigo
),
conversas AS (
  SELECT t.codigo, count(*) AS turnos, count(DISTINCT t.contato_id) AS pessoas
    FROM nai_turno t WHERE t.codigo IS NOT NULL GROUP BY t.codigo
)
SELECT coalesce(m.codigo, f.codigo, v.codigo, c.codigo)                AS codigo,
       i.condominio_nome,
       i.bairro,
       i.valor_aluguel::int                                            AS aluguel,
       i.quartos,
       coalesce(i.disponivel, true)                                    AS disponivel,
       coalesce(m.vezes_mandado, 0)                                    AS vezes_mandado,
       coalesce(f.fotos, 0)                                            AS fotos_enviadas,
       coalesce(c.turnos, 0)                                           AS mensagens_sobre_ele,
       coalesce(c.pessoas, 0)                                          AS pessoas_perguntaram,
       coalesce(v.visitas_pedidas, 0)                                  AS visitas_pedidas,
       coalesce(v.visitas_confirmadas, 0)                              AS visitas_confirmadas,
       coalesce(v.visitas_em_pe, 0)                                    AS visitas_em_pe,
       coalesce(v.visitas_canceladas, 0)                               AS visitas_canceladas,
       greatest(m.ultima_vez, f.ultima_foto)                           AS ultima_vez_mandado,
       v.proxima_visita
  FROM mandados m
  FULL JOIN fotos     f ON f.codigo = m.codigo
  FULL JOIN visitas   v ON v.codigo = coalesce(m.codigo, f.codigo)
  FULL JOIN conversas c ON c.codigo = coalesce(m.codigo, f.codigo, v.codigo)
  LEFT JOIN imoveis   i ON i.codigo = coalesce(m.codigo, f.codigo, v.codigo, c.codigo);

COMMENT ON VIEW vw_nai_metricas_imovel IS
  'Por imovel: quantas vezes foi oferecido, fotos, conversas e visitas. Painel da Nay Locacao (Tel, 15/09).';

GRANT SELECT ON vw_nai_metricas_imovel TO nay_site_nai;
