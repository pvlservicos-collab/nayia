-- testes da 328 e do cadastro de condomínio (dentro do ensaio)
-- 1. criar, repetir o nome (com outra caixa e acento), nome curto
SELECT site_condominio_salvar(NULL, '{"nome": "Teste Curadoria Rápida", "bairro": "Flores", "logradouro": "Rua A", "numero": "10", "lazer": ["Piscina"]}') AS criar;
SELECT site_condominio_salvar(NULL, '{"nome": "teste curadoria rapida"}') ->> 'motivo' AS repetido;
SELECT site_condominio_salvar(NULL, '{"nome": "ab"}') ->> 'motivo' AS curto;
-- 2. editar: endereço e características
SELECT site_condominio_salvar((SELECT id FROM condominios WHERE nome = 'Teste Curadoria Rápida'), '{"cep": "69000-000", "lazer": ["Piscina", "Academia"]}') AS editar;
SELECT f.logradouro, f.numero, f.cep, f.lazer FROM condominio_ficha f JOIN condominios c ON c.id = f.condominio_id WHERE c.nome = 'Teste Curadoria Rápida';
-- 3. renomear um condomínio que tem imóvel ligado SÓ PELO NOME
CREATE TEMP TABLE alvo AS
SELECT c.id, c.nome, count(*) AS so_pelo_nome
  FROM condominios c JOIN imoveis i ON i.condo_id IS NULL AND lower(unaccent(btrim(i.condominio_nome))) = lower(unaccent(btrim(c.nome)))
 GROUP BY c.id, c.nome ORDER BY count(*) DESC LIMIT 1;
SELECT * FROM alvo;
SELECT site_condominio_salvar(a.id, jsonb_build_object('nome', a.nome || ' (renomeado)')) ->> 'imoveis_renomeados' AS renomeados FROM alvo a;
SELECT 'imóveis que ficaram com o nome velho (tem de ser 0)' AS o_que, count(*) FROM imoveis i, alvo a
 WHERE lower(unaccent(btrim(i.condominio_nome))) = lower(unaccent(btrim(a.nome)));
SELECT 'ligados pelo id agora' AS o_que, count(*) FROM imoveis i, alvo a WHERE i.condo_id = a.id;
