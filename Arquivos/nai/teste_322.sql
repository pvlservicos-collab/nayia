-- Testes da 322 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

-- 1. criar
SELECT site_condominio_salvar(NULL, '{"nome": "  Condomínio   Teste 322 ", "bairro": "Aleixo", "tipo": "apartamentos",
  "logradouro": "Av. do Teste", "numero": "100", "cidade": "Manaus", "estado": "AM", "cep": "69060-000",
  "torres": "2 torres", "andares": "18 andares", "elevador": "Sim, possui 2 elevadores", "ano_lancamento": "2019",
  "lazer": ["Piscina", "piscina", "Academia", " "]}'::jsonb) AS r \gset
SELECT (:'r'::jsonb->>'id')::int AS novo \gset
INSERT INTO _t SELECT 'cria e devolve ok', 'true/true', (:'r'::jsonb->>'ok') || '/' || (:'r'::jsonb->>'criado');
INSERT INTO _t SELECT 'o nome entra sem espaço sobrando', 'Condomínio Teste 322', (SELECT nome FROM condominios WHERE id = :novo);
INSERT INTO _t SELECT 'o endereço fica nos campos e no texto', 'Av. do Teste|100|69060-000|Av. do Teste, nº 100, Bairro Aleixo, Manaus - AM',
  (SELECT logradouro || '|' || numero || '|' || cep || '|' || endereco FROM condominio_ficha WHERE condominio_id = :novo);
INSERT INTO _t SELECT 'características sem repetir e sem vazio', 'Piscina,Academia', (SELECT array_to_string(lazer, ',') FROM condominio_ficha WHERE condominio_id = :novo);
INSERT INTO _t SELECT 'ano e tipo', '2019/apartamentos', (SELECT ano_lancamento || '/' || tipo FROM condominio_ficha WHERE condominio_id = :novo);

-- 2. não repete nome (nem com acento ou caixa diferente)
INSERT INTO _t SELECT 'nome repetido é recusado e diz qual é', 'false/' || :novo,
  (SELECT (x->>'ok') || '/' || (x->>'id') FROM site_condominio_salvar(NULL, '{"nome": "CONDOMINIO TESTE 322"}'::jsonb) x);
INSERT INTO _t SELECT 'sem nome não cria', 'false',
  (SELECT x->>'ok' FROM site_condominio_salvar(NULL, '{"bairro": "Aleixo"}'::jsonb) x);

-- 3. editar: o que veio vale (vazio apaga), o que não veio fica
SELECT site_condominio_salvar(:novo, '{"numero": "", "cep": "69060-001", "lazer": ["Salão de festas"]}'::jsonb) AS r2 \gset
INSERT INTO _t SELECT 'editar diz o que mudou', 'numero,cep,lazer',
  (SELECT string_agg(x, ',') FROM jsonb_array_elements_text(:'r2'::jsonb->'mudou') x);
INSERT INTO _t SELECT 'campo vazio apagou, o que não veio ficou', '(nada)|69060-001|Av. do Teste|Salão de festas',
  (SELECT coalesce(numero, '(nada)') || '|' || cep || '|' || logradouro || '|' || array_to_string(lazer, ',') FROM condominio_ficha WHERE condominio_id = :novo);
INSERT INTO _t SELECT 'o texto do endereço acompanha', 'Av. do Teste, Bairro Aleixo, Manaus - AM',
  (SELECT endereco FROM condominio_ficha WHERE condominio_id = :novo);

-- 4. renomear
SELECT site_condominio_salvar(:novo, '{"nome": "Residencial Teste 322"}'::jsonb) AS r3 \gset
INSERT INTO _t SELECT 'renomeia o condomínio e a ficha', 'Residencial Teste 322|Residencial Teste 322',
  (SELECT c.nome || '|' || f.nome FROM condominios c JOIN condominio_ficha f ON f.condominio_id = c.id WHERE c.id = :novo);
INSERT INTO _t SELECT 'não deixa esvaziar o nome', 'false', (SELECT x->>'ok' FROM site_condominio_salvar(:novo, '{"nome": "  "}'::jsonb) x);
INSERT INTO _t SELECT 'id que não existe', 'false', (SELECT x->>'ok' FROM site_condominio_salvar(-5, '{"nome": "Qualquer"}'::jsonb) x);

-- 5. os condomínios que vieram dos imóveis
INSERT INTO _t SELECT 'os nomes que não são condomínio ficaram de fora', '0',
  (SELECT count(*)::text FROM condominios WHERE lower(unaccent(nome)) ~ '^(condominio )?(nao identificado|casa|apartamento|predio|livre|casa de condominio)$');
INSERT INTO _t SELECT 'The Place Business Center passou a existir', '1',
  (SELECT count(*)::text FROM condominios WHERE lower(unaccent(nome)) = 'the place business center');
INSERT INTO _t SELECT 'nenhum id repetido', '0', (SELECT count(*)::text FROM (SELECT id FROM condominios GROUP BY id HAVING count(*) > 1) x);
INSERT INTO _t SELECT 'nenhum nome repetido entre os que entraram agora', '0',
  (SELECT count(*)::text FROM (SELECT lower(unaccent(btrim(nome))) FROM condominios WHERE id > 484 GROUP BY 1 HAVING count(*) > 1) x);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso, CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
\echo '== quantos condomínios ficaram'
SELECT count(*) AS condominios, count(*) FILTER (WHERE id > 484) - 1 AS vindos_dos_imoveis FROM condominios;
\echo '== uma amostra dos que entraram'
SELECT id, nome, bairro FROM condominios WHERE id > 484 AND nome NOT LIKE '%Teste 322%' ORDER BY id LIMIT 12;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _t WHERE esperado IS DISTINCT FROM veio;
  IF n > 0 THEN RAISE EXCEPTION '322: % teste(s) falharam', n; END IF;
END $$;
