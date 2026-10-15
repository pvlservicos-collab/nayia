-- testes da 372 (dentro da transação do ensaio, que termina em ROLLBACK: nada vai para a fila de verdade)
CREATE TEMP TABLE _alvo AS
SELECT (p->>'id')::bigint AS id, (SELECT array_agg(x::bigint) FROM jsonb_array_elements_text(p->'ids') x) AS ids
  FROM jsonb_array_elements(site_captacao_grupos('todos', 48, 300)->'pedidos') p
 WHERE p->>'fonte' = 'grupo' AND p->>'telefone' IS NOT NULL ORDER BY (p->>'vezes')::int DESC LIMIT 1;

\echo '== vazia, teste colado e id que não existe: recusa =='
SELECT site_captacao_grupos_mensagem((SELECT id FROM _alvo), '   ') AS vazia,
       site_captacao_grupos_mensagem(-1, 'oi') AS nao_existe;

\echo '== envia: vai para a fila da Parceria, papel entrega =='
SELECT site_captacao_grupos_mensagem((SELECT id FROM _alvo), 'Boa tarde! Tenho uma casa no Flores que aceita financiamento, posso te mandar?', 'teste 372') AS envio;
SELECT s.papel_destino, s.estado, s.motivo, left(s.texto, 60) texto, s.enviar_apos > now() AS espera
  FROM nai_saida s WHERE s.motivo = 'captacao_ativa_negociacao' ORDER BY s.id DESC LIMIT 1;

\echo '== o mesmo texto de novo: recusa (clique duplo) =='
SELECT site_captacao_grupos_mensagem((SELECT ids[1] FROM _alvo), 'Boa tarde! Tenho uma casa no Flores que aceita financiamento, posso te mandar?', 'teste 372') AS repetida;

\echo '== aparece no card (em qualquer cópia) =='
SELECT p->'negociacao' FROM jsonb_array_elements(site_captacao_grupos('todos', 48, 300)->'pedidos') p
 WHERE (p->>'id')::bigint = (SELECT id FROM _alvo);
