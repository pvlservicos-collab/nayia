-- A SOMBRA DA PORTA x O N8N (31/10/2026, a saída do n8n; plano, etapa 3). Rodar: ./scripts/nay q scripts/servidor/porta_comparar.sql
-- Para cada mensagem que a porta "gravaria na fila" (core_porta_sombra, acao gravaria_fila), procura a linha que o n8n
-- gravou em captacao_mensagens: mesmo telefone (8 últimos dígitos) e mesmo texto, até 2 min de diferença.
-- E o contrário: o que o n8n gravou de recebida e a porta não viu. Só vira 'python' com as duas listas vazias
-- (ou as diferenças explicadas).
WITH s AS (
  SELECT id, criado_em, right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) AS f8, coalesce(texto, '') AS texto
    FROM core_porta_sombra
   WHERE linha IN ('captacao', 'oficial') AND acao = 'gravaria_fila' AND criado_em > now() - interval '24 hours'
), m AS (
  SELECT id, criada_em, right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) AS f8, coalesce(texto, '') AS texto
    FROM captacao_mensagens
   WHERE direcao = 'recebida'
     AND criada_em > (SELECT coalesce(min(criado_em), now()) FROM s) - interval '1 min'
)
SELECT 'resumo' AS o_que,
       (SELECT count(*) FROM s) AS porta_gravaria,
       (SELECT count(*) FROM m) AS n8n_gravou,
       (SELECT count(*) FROM s WHERE EXISTS (SELECT 1 FROM m WHERE m.f8 = s.f8 AND m.texto = s.texto
                                                AND abs(extract(epoch FROM m.criada_em - s.criado_em)) < 120)) AS casaram;
-- só na porta (o n8n não gravou)
SELECT 'so_na_porta' AS o_que, s.criado_em::time(0) AS hora, '...' || s.f8 AS fone, left(s.texto, 60) AS texto
  FROM core_porta_sombra x
  JOIN LATERAL (SELECT x.criado_em, right(regexp_replace(coalesce(x.telefone, ''), '\D', '', 'g'), 8) AS f8,
                       coalesce(x.texto, '') AS texto) s ON true
 WHERE x.linha IN ('captacao', 'oficial') AND x.acao = 'gravaria_fila' AND x.criado_em > now() - interval '24 hours'
   AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                    WHERE m.direcao = 'recebida' AND right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = s.f8
                      AND coalesce(m.texto, '') = s.texto
                      AND abs(extract(epoch FROM m.criada_em - s.criado_em)) < 120)
 ORDER BY 2 LIMIT 30;
-- só no n8n (a porta não viu), desde a primeira sombra
SELECT 'so_no_n8n' AS o_que, m.criada_em::time(0) AS hora, '...' || right(m.telefone, 8) AS fone, left(m.texto, 60) AS texto
  FROM captacao_mensagens m
 WHERE m.direcao = 'recebida'
   AND m.criada_em > (SELECT coalesce(min(criado_em), now()) FROM core_porta_sombra WHERE linha = 'captacao')
   AND NOT EXISTS (SELECT 1 FROM core_porta_sombra x
                    WHERE x.linha IN ('captacao', 'oficial') AND x.acao = 'gravaria_fila'
                      AND right(regexp_replace(coalesce(x.telefone, ''), '\D', '', 'g'), 8)
                          = right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8)
                      AND coalesce(x.texto, '') = coalesce(m.texto, '')
                      AND abs(extract(epoch FROM m.criada_em - x.criado_em)) < 120)
 ORDER BY 2 LIMIT 30;
