-- testes da 371 (dentro da transação do ensaio, que termina em ROLLBACK)
\echo '== contagem: 48 h e 7 dias =='
SELECT h, v->'contagem'->>'todos' AS solicitacoes, v->'contagem'->>'mensagens' AS mensagens, v->'contagem'->>'juntadas' AS juntadas,
       jsonb_array_length(v->'pedidos') AS na_lista
  FROM (SELECT h, site_captacao_grupos('todos', h, 300) v FROM unnest(ARRAY[48, 168]) h) x;

\echo '== as 5 que mais se repetem (7 dias) =='
SELECT p->>'id' id, p->>'vezes' vezes, jsonb_array_length(p->'grupos') grupos, p->>'nota' nota, p->>'estado' estado,
       left(p->>'texto', 60) texto
  FROM jsonb_array_elements(site_captacao_grupos('todos', 168, 300)->'pedidos') p
 ORDER BY (p->>'vezes')::int DESC LIMIT 5;

\echo '== nota mínima 90: nenhuma abaixo (deve dar 0 abaixo) =='
SELECT v->'contagem'->>'com_a_nota' com_a_nota, jsonb_array_length(v->'pedidos') na_lista,
       (SELECT count(*) FROM jsonb_array_elements(v->'pedidos') p WHERE coalesce((p->>'nota')::numeric, 0) < 90) AS abaixo
  FROM (SELECT site_captacao_grupos('todos', 168, 300, 90) v) x;

\echo '== ordem por nota: as 5 primeiras =='
SELECT p->>'nota' nota, p->>'vezes' vezes, left(p->>'texto', 50) texto
  FROM jsonb_array_elements(site_captacao_grupos('todos', 168, 5, NULL, 'nota')->'pedidos') p;

\echo '== rejeitar uma cópia rejeita todas; desfazer volta todas =='
CREATE TEMP TABLE _alvo AS
SELECT (p->>'id')::bigint AS id, (SELECT array_agg(x::bigint) FROM jsonb_array_elements_text(p->'ids') x) AS ids
  FROM jsonb_array_elements(site_captacao_grupos('todos', 168, 300)->'pedidos') p
 WHERE p->>'estado' = 'novo' ORDER BY (p->>'vezes')::int DESC LIMIT 1;
SELECT site_captacao_grupos_estado((SELECT ids[1] FROM _alvo), 'rejeitado') AS rejeitar_a_primeira_copia;
SELECT estado, count(*) FROM privado.grupo_pedido WHERE id IN (SELECT unnest(ids) FROM _alvo) GROUP BY estado;
SELECT site_captacao_grupos_estado((SELECT id FROM _alvo), 'novo') AS desfazer;
SELECT estado, count(*) FROM privado.grupo_pedido WHERE id IN (SELECT unnest(ids) FROM _alvo) GROUP BY estado;

\echo '== imóvel enviado numa cópia vale para todas (a trava do envio) =='
INSERT INTO privado.grupo_pedido_oferta (pedido_id, codigo, telefone, abertura, com_card, resumo, quem)
SELECT a.ids[1], p.codigo, '5592999999999', 'teste 371', false, 'teste 371', 'teste'
  FROM _alvo a JOIN privado.grupo_pedido_par p ON p.pedido_id = a.id AND p.posicao = 1
 WHERE a.ids[1] <> a.id;
SELECT site_captacao_grupos_enviar(a.id, p.codigo, 'teste', 'teste') AS enviar_na_outra_copia
  FROM _alvo a JOIN privado.grupo_pedido_par p ON p.pedido_id = a.id AND p.posicao = 1;
SELECT p->>'estado' estado, jsonb_array_length(p->'ofertas') ofertas
  FROM jsonb_array_elements(site_captacao_grupos('todos', 168, 300)->'pedidos') p WHERE (p->>'id')::bigint = (SELECT id FROM _alvo);
