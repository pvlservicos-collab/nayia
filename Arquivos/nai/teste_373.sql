-- testes da 373 (no ensaio, que termina em ROLLBACK)
CREATE TEMP TABLE _alvo AS
SELECT (p->>'id')::bigint AS id FROM jsonb_array_elements(site_captacao_grupos('todos', 48, 300)->'pedidos') p
 WHERE p->>'fonte' = 'grupo' AND p->>'telefone' IS NOT NULL LIMIT 1;
SELECT site_captacao_grupos_mensagem((SELECT id FROM _alvo), 'teste 373 primeira', 'teste') AS primeira,
       site_captacao_grupos_mensagem((SELECT id FROM _alvo), 'teste 373 segunda, logo em seguida', 'teste') AS segunda_seguida,
       site_captacao_grupos_mensagem((SELECT id FROM _alvo), 'teste 373 primeira', 'teste') AS clique_duplo;
\echo '== a citação de cada uma (grupo e id da mensagem dele) =='
SELECT s.id, left(s.texto, 30) texto, site_captacao_grupos_citacao(s.id) AS citacao
  FROM nai_saida s WHERE s.motivo = 'captacao_ativa_negociacao' AND s.texto LIKE 'teste 373%' ORDER BY s.id;
\echo '== linha que não é negociação: sem citação =='
SELECT site_captacao_grupos_citacao((SELECT max(id) FROM nai_saida WHERE motivo IS DISTINCT FROM 'captacao_ativa_negociacao')) AS outra;
