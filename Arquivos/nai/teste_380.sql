-- teste da 380: o mesmo pedido do mesmo corretor num card só
SELECT motivo, count(*) AS pedidos FROM privado.grupo_pedido_junto GROUP BY motivo ORDER BY 2 DESC;

-- 48 h, como a tela: pedidos, cards da 371 (texto igual) e cards da 380
WITH g AS (
  SELECT q.*, j.card, privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte) AS k371
    FROM privado.grupo_pedido q JOIN privado.grupo_pedido_junto j ON j.pedido_id = q.id
   WHERE q.enviada_em >= now() - interval '48 hours' AND q.fonte <> 'teste'
)
SELECT count(*) AS pedidos, count(DISTINCT k371) AS cards_371, count(DISTINCT card) AS cards_380 FROM g;

-- quem ainda tem mais de um card (para ver se sobrou repetido ou se juntou o que não devia)
WITH g AS (
  SELECT j.card, j.quem, q.remetente_nome, q.texto, q.enviada_em, j.motivo
    FROM privado.grupo_pedido q JOIN privado.grupo_pedido_junto j ON j.pedido_id = q.id
   WHERE q.enviada_em >= now() - interval '48 hours' AND q.fonte <> 'teste'
), c AS (
  SELECT DISTINCT ON (card) card, quem, left(remetente_nome, 12) AS nome, left(regexp_replace(texto, '\s+', ' ', 'g'), 80) AS texto,
         to_char(enviada_em, 'DD HH24:MI') AS em, (SELECT count(*) FROM g g2 WHERE g2.card = g.card) AS pedidos
    FROM g ORDER BY card, enviada_em DESC
)
SELECT nome, card, pedidos, em, texto FROM c WHERE quem IN (SELECT quem FROM c GROUP BY quem HAVING count(*) > 1)
 ORDER BY quem, em LIMIT 80;

-- os cards que juntaram versões diferentes do texto (para conferir a junção por semelhança)
SELECT j.card, left(min(q.remetente_nome), 12) AS nome, count(*) AS pedidos, count(DISTINCT j.nt) AS versoes,
       string_agg(DISTINCT left(regexp_replace(q.texto, '\s+', ' ', 'g'), 60), ' || ') AS textos
  FROM privado.grupo_pedido_junto j JOIN privado.grupo_pedido q ON q.id = j.pedido_id
 WHERE j.enviada_em >= now() - interval '72 hours'
 GROUP BY j.card HAVING count(DISTINCT j.nt) > 1 ORDER BY 2 LIMIT 40;

-- a tela
SELECT jsonb_pretty(site_captacao_grupos('todos', 48, 300)->'contagem') AS contagem;
SELECT p->>'nome' AS nome, p->>'vezes' AS vezes, p->>'versoes' AS versoes, jsonb_array_length(p->'outras_partes') AS outras_partes,
       jsonb_array_length(p->'outras_versoes') AS outras_versoes, jsonb_array_length(p->'pares') AS pares, p->>'nota' AS nota
  FROM jsonb_array_elements(site_captacao_grupos('todos', 48, 300)->'pedidos') p
 WHERE p->>'nome' ~* '^(G Silva|Aira|Juliana Pinh|Iraci|Marcelo Mich|Everton)' ORDER BY 1;

-- rodar de novo não junta nada (nada novo)
SELECT privado.grupo_pedido_juntar_novos() AS juntados_de_novo;
