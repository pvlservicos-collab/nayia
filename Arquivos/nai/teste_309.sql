-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
SET LOCAL statement_timeout = '110s';
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;

-- um apartamento nosso que está no mercado, com condomínio de nome próprio, área e preço
CREATE TEMP TABLE _nosso ON COMMIT DROP AS
SELECT i.codigo, i.tipo, i.bairro, i.condominio_nome, i.quartos,
       coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) AS area,
       CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'aluguel' ELSE 'venda' END AS fin,
       CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN i.valor_aluguel ELSE i.valor_venda END AS preco
  FROM imoveis i
 WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
   AND crm_anuncio_familia(i.tipo) = 'apartamento' AND coalesce(i.quartos, 0) > 0
   AND coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) > 20
   AND coalesce(nullif(i.valor_aluguel, 0), nullif(i.valor_venda, 0)) > 0
   AND length(nay_sem_acento(lower(nai_condominio_nucleo(coalesce(i.condominio_nome, ''))))) >= 6
   AND nay_sem_acento(lower(nai_condominio_nucleo(i.condominio_nome))) NOT IN ('nao identificado', 'apartamento', 'predio')
   AND coalesce(i.bairro, '') <> ''
 ORDER BY i.codigo DESC LIMIT 1;

-- 1. sem link e só com o link: falha, nunca "abordar"
INSERT INTO _t (caso, esperado, veio)
SELECT 'sem link', 'false/faltam_campos', (r ->> 'consulta_ok') || '/' || (r ->> 'codigo_erro')
  FROM crm_anuncio_decidir('{"titulo": "Apartamento 3 quartos"}') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'só o link, nada para comparar', 'false/faltam_campos', (r ->> 'consulta_ok') || '/' || (r ->> 'codigo_erro')
  FROM crm_anuncio_decidir('{"link": "https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-so-link-9000000000"}') r;

-- 2. o imóvel nosso, anunciado igual: já temos
INSERT INTO _t (caso, esperado, veio)
SELECT 'imóvel nosso no mercado, anunciado igual', 'fechar/ja_temos/true/sem mensagem',
       (r ->> 'acao') || '/' || (r ->> 'motivo') || '/' || (r ->> 'temos') || '/' || CASE WHEN r ? 'mensagem' THEN 'COM MENSAGEM' ELSE 'sem mensagem' END
  FROM _nosso n, crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-nosso-9000000001', 'titulo', 'Apartamento ' || n.condominio_nome,
         'tipo', n.tipo, 'finalidade', n.fin, 'preco', n.preco, 'bairro', n.bairro, 'condominio_nome', n.condominio_nome,
         'area_m2', n.area, 'quartos', n.quartos, 'anunciante_nome', 'Zzzfulano Teste')) r;

-- 3. mesmo condomínio e mesma planta, outro preço e outro dono: é outra unidade, aborda
INSERT INTO _t (caso, esperado, veio)
SELECT 'mesma planta no mesmo condomínio, preço 37% acima', 'abordar/nao_temos/false',
       (r ->> 'acao') || '/' || (r ->> 'motivo') || '/' || (r ->> 'temos')
  FROM _nosso n, crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-vizinho-9000000002', 'titulo', 'Apartamento ' || n.condominio_nome,
         'tipo', n.tipo, 'finalidade', n.fin, 'preco', round(n.preco * 1.37), 'bairro', n.bairro, 'condominio_nome', n.condominio_nome,
         'area_m2', n.area, 'quartos', n.quartos, 'anunciante_nome', 'Zzzfulano Teste')) r;

-- 4. o telefone do anúncio é de um proprietário nosso
INSERT INTO _t (caso, esperado, veio)
SELECT 'telefone de proprietário nosso', 'fechar/proprietario_ja_e_nosso', (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM (SELECT pr.telefone FROM proprietarios pr
         WHERE nai_chave(pr.telefone) IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM corretores k WHERE nai_chave(k.telefone) = nai_chave(pr.telefone))
         ORDER BY pr.id DESC LIMIT 1) d,
       crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-dono-9000000003', 'titulo', 'Casa no Residencial Zzzinexistente',
         'tipo', 'casa', 'finalidade', 'venda', 'preco', 123456789, 'bairro', 'Flores', 'telefone', d.telefone)) r;

-- 5. corretor: pelo telefone da lista, pelo nome, pelo CRECI no texto, pela marca de profissional
INSERT INTO _t (caso, esperado, veio)
SELECT 'telefone na lista de corretores', 'fechar/corretor', (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM (SELECT k.telefone FROM corretores k
         WHERE nai_chave(k.telefone) IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM proprietarios pr WHERE coalesce(pr.telefone, '') <> '' AND nai_chave(pr.telefone) = nai_chave(k.telefone))
         ORDER BY k.criado_em DESC LIMIT 1) k,
       crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-corretor-9000000004', 'titulo', 'Casa no Residencial Zzzinexistente',
         'tipo', 'casa', 'finalidade', 'venda', 'preco', 123456789, 'bairro', 'Flores', 'telefone', k.telefone)) r;
INSERT INTO _t (caso, esperado, veio)
SELECT x.caso, x.esperado, (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM (VALUES
    ('nome "Fátima Melo Imoveis"', 'fechar/corretor', '{"anunciante_nome": "Fátima Melo Imoveis"}'::jsonb, 5),
    ('"CRECI 12345" na descrição', 'fechar/corretor', '{"anunciante_nome": "Carlos", "descricao": "Lindo apartamento. Carlos, CRECI 12345."}', 6),
    ('conta profissional', 'fechar/corretor', '{"anunciante_nome": "Carlos", "profissional": true}', 7),
    ('"Dispenso corretores e imobiliárias"', 'fechar/dispensa_imobiliaria', '{"anunciante_nome": "Carlos", "descricao": "Apartamento novo. Dispenso corretores e imobiliárias."}', 8),
    ('"direto com o dono, sem intermediários"', 'fechar/dispensa_imobiliaria', '{"anunciante_nome": "Carlos", "descricao": "Trato direto com o dono, sem intermediários."}', 9),
    ('"Não aceito permuta. Corretores são bem-vindos"', 'abordar/nao_temos', '{"anunciante_nome": "Carlos", "descricao": "Não aceito permuta. Corretores são bem-vindos."}', 10),
    ('nome "BLR Logística" (empresa, não imobiliária)', 'abordar/nao_temos', '{"anunciante_nome": "BLR Logística"}', 11)
  ) x(caso, esperado, extra, k),
  crm_anuncio_decidir(jsonb_build_object(
    'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-regra-90000001' || lpad(x.k::text, 2, '0'),
    'titulo', 'Apartamento no Residencial Zzzinexistente', 'tipo', 'apartamento', 'finalidade', 'venda',
    'preco', 123456789, 'bairro', 'Flores') || x.extra) r;

-- 6. o anúncio novo: aborda, com a mensagem montada
CREATE TEMP TABLE _novo ON COMMIT DROP AS
SELECT crm_anuncio_decidir('{"link": "https://am.olx.com.br/regiao-de-manaus/imoveis/apartamento-zzz-teste-309-9000000020?lis=x",
  "titulo": "Apartamento 3 quartos Residencial Zzzinexistente", "tipo": "apartamento", "finalidade": "venda", "preco": "R$ 987.654.321,00",
  "bairro": "nossa-senhora-das-gracas", "quartos": 3, "area_m2": 123, "anunciante_nome": "Mariana"}') AS r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'anúncio novo: aborda', 'abordar/nao_temos/false', (r ->> 'acao') || '/' || (r ->> 'motivo') || '/' || (r ->> 'temos') FROM _novo;
INSERT INTO _t (caso, esperado, veio)
SELECT 'mensagem: cliente, bairro do catálogo, "vendendo", sem marcador', 'true',
       (r ->> 'mensagem' LIKE 'Oii, bo% Me chamo Nay Mendes, da Imob Easy.%'
        AND r ->> 'mensagem' LIKE '%Tenho uma família procurando um apartamento maior na região de Nossa Senhora das Graças e o seu entrou no perfil deles.%'
        AND r ->> 'mensagem' LIKE '%você continua vendendo aqui no OLX.%'
        AND r ->> 'mensagem' LIKE '%Me passa seu nome e seu WhatsApp que a gente conversa melhor.'
        AND r ->> 'mensagem' !~ '[{}]')::text FROM _novo;
INSERT INTO _t (caso, esperado, veio)
SELECT 'ficou gravado com a mensagem e a hora da entrega', '1/abordar/true/1',
       count(*) || '/' || max(c.acao) || '/' || bool_and(c.entregue_em IS NOT NULL AND c.mensagem = (SELECT r ->> 'mensagem' FROM _novo)) || '/' || max(c.pedidos)
  FROM privado.anuncio_consulta c WHERE c.id_anuncio = '9000000020';

-- 7. perguntou de novo em seguida: a MESMA mensagem; 11 minutos depois: fechar
INSERT INTO _t (caso, esperado, veio)
SELECT 'repetiu em seguida: a mesma mensagem', 'abordar/true/true',
       (r ->> 'acao') || '/' || (r ->> 'repetido') || '/' || (r ->> 'mensagem' = (SELECT n.r ->> 'mensagem' FROM _novo n))
  FROM crm_anuncio_decidir('{"link": "https://am.olx.com.br/regiao-de-manaus/imoveis/apartamento-zzz-teste-309-9000000020", "titulo": "outro título"}') r;
UPDATE privado.anuncio_consulta SET entregue_em = now() - interval '11 minutes' WHERE id_anuncio = '9000000020';
INSERT INTO _t (caso, esperado, veio)
SELECT '11 minutos depois: não manda de novo', 'fechar/ja_abordado/sem mensagem',
       (r ->> 'acao') || '/' || (r ->> 'motivo') || '/' || CASE WHEN r ? 'mensagem' THEN 'COM MENSAGEM' ELSE 'sem mensagem' END
  FROM crm_anuncio_decidir('{"link": "https://am.olx.com.br/regiao-de-manaus/imoveis/apartamento-zzz-teste-309-9000000020", "titulo": "Apartamento", "preco": 1, "bairro": "Flores"}') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'mesmo anúncio com o título do link trocado (mesmo id)', 'fechar/ja_abordado', (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM crm_anuncio_decidir('{"link": "https://am.olx.com.br/regiao-de-manaus/imoveis/novo-titulo-do-mesmo-anuncio-9000000020", "titulo": "Apartamento", "preco": 1, "bairro": "Flores"}') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'continuou uma linha só, com os pedidos contados', '1/4', count(*) || '/' || max(pedidos)
  FROM privado.anuncio_consulta WHERE id_anuncio = '9000000020';

-- 8. teste de conexão: não grava e não é ordem
INSERT INTO _t (caso, esperado, veio)
SELECT '"teste": true', 'nenhuma/abordar/true/sem mensagem/com exemplo',
       (r ->> 'acao') || '/' || (r ->> 'seria') || '/' || (r ->> 'teste') || '/' || CASE WHEN r ? 'mensagem' THEN 'COM MENSAGEM' ELSE 'sem mensagem' END
       || '/' || CASE WHEN length(r ->> 'mensagem_exemplo') > 200 THEN 'com exemplo' ELSE 'SEM EXEMPLO' END
  FROM crm_anuncio_decidir('{"teste": true, "link": "https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-conexao-9000000030",
    "titulo": "Casa em condomínio", "tipo": "casa", "finalidade": "aluguel", "preco": 3500, "bairro": "Ponta Negra"}') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'o teste não gravou nada', '0', count(*)::text FROM privado.anuncio_consulta WHERE id_anuncio = '9000000030';

-- 9. a mensagem: tipo, finalidade, bairro e a saudação pela hora de Manaus
INSERT INTO _t (caso, esperado, veio)
SELECT x.caso, 'true', (crm_anuncio_mensagem(x.p, x.fin, x.quando) LIKE x.tem)::text
  FROM (VALUES
    ('casa para alugar: "uma casa" e "anunciando"', '{"tipo": "Casa de condomínio", "bairro": "Ponta Negra"}'::jsonb, 'aluguel', now(),
       '%Tenho uma família procurando uma casa na região de Ponta Negra e o seu%você continua anunciando aqui no OLX.%'),
    ('apartamento de 2 quartos', '{"titulo": "Alugo apto 2 quartos", "quartos": "2", "bairro": "Vieiralves"}', 'aluguel', now(),
       '%Tenho um casal procurando um apartamento na região de Nossa Senhora das Graças e o seu%'),
    ('sala comercial', '{"tipo": "Sala comercial", "bairro": "Adrianópolis"}', 'aluguel', now(),
       '%Tenho uma empresa procurando um ponto comercial na região de Adrianópolis e o seu%'),
    ('bairro fora do catálogo, escrito como nome', '{"tipo": "apartamento", "bairro": "Dom Pedro I"}', 'venda', now(),
       '%na região de Dom Pedro I e o seu%'),
    ('bairro que não dá para escrever: sem bairro', '{"tipo": "apartamento", "bairro": "bairro-inventado-zzz"}', 'venda', now(),
       '%procurando um apartamento na sua região e o seu%'),
    ('11:59 em Manaus', '{"tipo": "casa"}', NULL, '2026-10-08 11:59-04'::timestamptz, 'Oii, bom dia!%'),
    ('12:00 em Manaus', '{"tipo": "casa"}', NULL, '2026-10-08 12:00-04', 'Oii, boa tarde!%'),
    ('17:59 em Manaus', '{"tipo": "casa"}', NULL, '2026-10-08 17:59-04', 'Oii, boa tarde!%'),
    ('18:00 em Manaus', '{"tipo": "casa"}', NULL, '2026-10-08 18:00-04', 'Oii, boa noite!%'),
    ('04:59 em Manaus', '{"tipo": "casa"}', NULL, '2026-10-08 04:59-04', 'Oii, boa noite!%'),
    ('05:00 em Manaus', '{"tipo": "casa"}', NULL, '2026-10-08 05:00-04', 'Oii, bom dia!%')
  ) x(caso, p, fin, quando, tem);

-- 10. o que a Captação OLX já importou bate pelo link
INSERT INTO _t (caso, esperado, veio)
SELECT 'pré-cadastro da OLX, pelo link', 'fechar/ja_temos/' || i.codigo, (r ->> 'acao') || '/' || (r ->> 'motivo') || '/' || (r ->> 'id_imovel')
  FROM (SELECT codigo, extras ->> 'olx_url' AS url FROM imoveis WHERE origem = 'olx' AND coalesce(extras ->> 'olx_url', '') <> '' ORDER BY codigo LIMIT 1) i,
       crm_anuncio_decidir(jsonb_build_object('link', i.url)) r;

-- 11. texto com marcador desconhecido: não manda nada (o texto volta ao que era logo depois)
CREATE TEMP TABLE _texto ON COMMIT DROP AS SELECT texto FROM anuncio_abordagem_texto WHERE chave = 'mensagem';
UPDATE anuncio_abordagem_texto SET texto = texto || ' {nome}' WHERE chave = 'mensagem';
INSERT INTO _t (caso, esperado, veio)
SELECT 'texto com marcador que não existe', 'false/texto', (r ->> 'consulta_ok') || '/' || (r ->> 'codigo_erro')
  FROM crm_anuncio_decidir('{"link": "https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-texto-9000000040",
    "titulo": "Apartamento no Residencial Zzzinexistente", "tipo": "apartamento", "preco": 123456789, "bairro": "Flores"}') r;
UPDATE anuncio_abordagem_texto SET texto = (SELECT texto FROM _texto) WHERE chave = 'mensagem';
INSERT INTO _t (caso, esperado, veio)
SELECT 'a falha do texto não deixou linha gravada', '0', count(*)::text FROM privado.anuncio_consulta WHERE id_anuncio = '9000000040';

-- 12. o papel do CRM executa a decisão e não lê a tabela das consultas
SET LOCAL ROLE nay_disparo;
SELECT crm_anuncio_decidir('{"teste": true, "link": "https://am.olx.com.br/regiao-de-manaus/imoveis/teste-309-papel-9000000050",
    "titulo": "Apartamento", "tipo": "apartamento", "preco": 123456789, "bairro": "Flores"}') ->> 'acao' AS papel_acao \gset
RESET ROLE;
INSERT INTO _t (caso, esperado, veio) VALUES ('nay_disparo executa a decisão', 'nenhuma', :'papel_acao');
INSERT INTO _t (caso, esperado, veio)
SELECT 'nay_disparo não lê privado.anuncio_consulta', 'false', has_table_privilege('nay_disparo', 'privado.anuncio_consulta', 'SELECT')::text;

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;
\echo == a mensagem como sai (anúncio novo)
SELECT r ->> 'mensagem' AS mensagem FROM _novo;

-- A MEDIDA: os imóveis nossos que estão no mercado, apresentados como anúncio.
--   a) com os dados iguais, ele reconhece o próprio imóvel?
--   b) tirando o próprio da lista (como se fosse de OUTRO dono), sobra um gêmeo no mercado
--      com a mesma planta e o mesmo preço? É a parcela que fecharia sem ser o mesmo.
--   c) pela regra da 258 ("alta" = condomínio igual + área igual), quantos fechariam
--      sem ser o mesmo: é o erro que esta migração evita.
\echo == a medida (amostra dos imóveis no mercado)
WITH am AS (
  SELECT i.codigo, jsonb_build_object('link', 'https://medida.teste/anuncio-' || i.codigo,
           'titulo', i.tipo || ' ' || coalesce(i.condominio_nome, ''), 'tipo', i.tipo,
           'finalidade', CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'aluguel' ELSE 'venda' END,
           'preco', CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN i.valor_aluguel ELSE i.valor_venda END,
           'bairro', i.bairro, 'condominio_nome', i.condominio_nome,
           'area_m2', coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)), 'quartos', i.quartos,
           'anunciante_nome', 'Zzzfulano Teste') AS p
    FROM imoveis i
   WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND coalesce(nullif(i.valor_aluguel, 0), nullif(i.valor_venda, 0)) > 0
     AND coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) > 0
   ORDER BY i.codigo % 5, i.codigo LIMIT 200
),
r AS MATERIALIZED (SELECT am.codigo, am.p, crm_imovel_candidatos(am.p) AS cand FROM am),
s AS (
  SELECT r.codigo, r.p, r.cand,
         jsonb_set(r.cand, '{candidatos}', coalesce((SELECT jsonb_agg(x) FROM jsonb_array_elements(r.cand -> 'candidatos') x
                                                      WHERE x ->> 'id_imovel' <> r.codigo::text), '[]'::jsonb)) AS sem_ele
    FROM r
)
SELECT count(*) AS amostra,
       count(*) FILTER (WHERE crm_anuncio_mesma_unidade(p, cand) IS NOT NULL) AS a_reconhece_o_proprio,
       count(*) FILTER (WHERE crm_anuncio_mesma_unidade(p, sem_ele) IS NOT NULL) AS b_fecharia_por_um_gemeo,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(sem_ele -> 'candidatos') x WHERE x ->> 'confianca' = 'alta')) AS c_fecharia_pela_regra_da_258
  FROM s;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_309: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
