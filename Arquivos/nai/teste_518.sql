-- teste da 518 (dentro da transação do ensaio)
\echo '--- os dois depois da troca'
SELECT codigo, status, disponivel, publicado_no_site,
       nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AS no_mercado, travado_motivo
  FROM imoveis WHERE codigo IN (5609, 2084) ORDER BY codigo;
\echo '--- a lista dos grupos não traz mais nenhum dos dois'
SELECT c.categoria, n.neg, (l.texto_pronto ~ '\m(5609|2084)\M') AS ainda_aparece
  FROM (SELECT DISTINCT nay_categoria_do_imovel(tipo, condominio_nome) AS categoria FROM imoveis WHERE codigo IN (5609, 2084)) c
  CROSS JOIN (VALUES ('locacao'), ('venda')) n(neg)
  CROSS JOIN LATERAL nay_lista_de_imoveis(c.categoria, n.neg) l;
\echo '--- o log'
SELECT codigo, status_antes, status_depois, quem FROM imovel_situacao_log WHERE codigo IN (5609, 2084) ORDER BY id DESC LIMIT 2;
