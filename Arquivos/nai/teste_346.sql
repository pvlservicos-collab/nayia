-- Testes da 346 (rodam dentro do ensaio, antes do ROLLBACK). Usa um condomínio de mentira e desfaz com o ROLLBACK.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

SELECT site_condominio_salvar(NULL, '{"nome": "Condomínio Teste 346", "bairro": "Parque 10 de Novembro", "tipo": "apartamentos",
  "torres": "6 torres", "andares": "8 andares", "aptos_por_andar": "8", "elevador": "Sim, possui elevador", "construtora": "Tecnisa",
  "ano_construcao": "2011 e 2013", "complemento": "próx. ao Flex Parque Dez", "observacao": "portaria recebe encomenda",
  "lazer": ["Academia", "Piscina", "Salão de festas"], "seguranca": ["Condomínio fechado", "Guarita 24 Horas"],
  "comodidades": ["Elevador", "Gás Encanado"],
  "taxas": [{"quartos": "3", "condominio": "648,00", "iptu": "980"}, {"quartos": "2", "condominio": "462", "iptu": ""}]}'::jsonb) AS r \gset
INSERT INTO _t SELECT 'cadastrou', 'true', (:'r'::jsonb ->> 'ok');
SELECT (:'r'::jsonb ->> 'id')::int AS cid \gset
INSERT INTO _t SELECT 'as três listas gravadas', '3/2/2',
  (SELECT cardinality(lazer) || '/' || cardinality(seguranca) || '/' || cardinality(comodidades) FROM condominio_ficha WHERE condominio_id = :cid);
INSERT INTO _t SELECT 'ano, complemento e observação', '2011 e 2013|próx. ao Flex Parque Dez|portaria recebe encomenda',
  (SELECT ano_construcao || '|' || complemento || '|' || observacao FROM condominio_ficha WHERE condominio_id = :cid);
INSERT INTO _t SELECT 'taxas por quartos (número, com vírgula lida)', '[{"iptu": 980, "quartos": 3, "condominio": 648}, {"quartos": 2, "condominio": 462}]',
  (SELECT taxas::text FROM condominio_ficha WHERE condominio_id = :cid);
-- editar só a segurança: as outras listas ficam
SELECT site_condominio_salvar(:cid, '{"seguranca": ["Guarita 24 Horas"]}'::jsonb) AS r2 \gset
INSERT INTO _t SELECT 'editar uma lista não mexe nas outras', '3/1/2',
  (SELECT cardinality(lazer) || '/' || cardinality(seguranca) || '/' || cardinality(comodidades) FROM condominio_ficha WHERE condominio_id = :cid);

-- a página pública: imóvel de teste no condomínio, cobertura, observação, mobília
INSERT INTO imoveis (codigo, tipo, status, condo_id, condominio_nome, bairro, quartos, area_util, valor_aluguel, mobilia, observacao, cobertura,
                     caracteristicas, origem, publicado_no_site, disponivel)
VALUES (999346, 'Apartamento', 'Disponível', :cid, 'Condomínio Teste 346', 'Parque 10 de Novembro', 3, 90, 2500, 'com modulados e ar',
        'vista para o rio; falta só TV', true, '{Varanda,Closet}', 'site', true, true);
SELECT site_imovel_publico(999346) AS p \gset
INSERT INTO _t SELECT 'público: tags do condomínio vêm da ficha', 'true',
  ((:'p'::jsonb -> 'tagscondo') @> '["Academia", "Guarita 24 Horas", "Elevador"]'::jsonb)::text;
INSERT INTO _t SELECT 'público: as do imóvel não repetem as do condomínio', '["Varanda", "Closet"]', (:'p'::jsonb -> 'tagsimovel')::text;
INSERT INTO _t SELECT 'público: observação, cobertura e nível da mobília', 'vista para o rio; falta só TV|Sim|semi',
  (:'p'::jsonb ->> 'obs') || '|' || (:'p'::jsonb -> 'carac' ->> 'cobertura') || '|' || (:'p'::jsonb -> 'carac' ->> 'mobilia_nivel');
INSERT INTO _t SELECT 'público: a ficha do condomínio vai junto', 'Tecnisa/2011 e 2013/6 torres',
  (:'p'::jsonb -> 'condo' ->> 'construtora') || '/' || (:'p'::jsonb -> 'condo' ->> 'ano') || '/' || (:'p'::jsonb -> 'condo' ->> 'torres');
-- o imóvel de teste some com o ROLLBACK; mesmo assim, por garantia
DELETE FROM imoveis WHERE codigo = 999346;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '346: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '346: % testes, todos certos', m;
END $$;
