-- Testes da 336 (rodam dentro do ensaio, antes do ROLLBACK). Tudo aqui é linha inventada em tabela nova.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

INSERT INTO _t SELECT 'a chave do nome: sem acento, minúsculo, só letra e número', 'parque ville municipal',
  site_captacao_chave('  Parque  Ville-Municipal ');

INSERT INTO _t SELECT 'tela vazia: modo treino, serviço parado, nenhum pedido', 'treino/false/0',
  (SELECT (j->>'modo') || '/' || (j->>'servico_vivo') || '/' || jsonb_array_length(j->'pedidos') FROM site_captacao_grupos() j);

-- colar uma mensagem para testar
INSERT INTO _t SELECT 'teste curto demais é recusado', 'Cole a mensagem do corretor.', site_captacao_grupos_testar('oi') ->> 'erro';
SELECT (site_captacao_grupos_testar('Procuro Eliza Miranda para venda com 3 quartos e suite, Térreo', 'Pedro') ->> 'id') AS teste \gset
INSERT INTO _t SELECT 'teste colado entra na fila e ainda não foi lido', 'true/false',
  (:teste > 0)::text || '/' || (site_captacao_grupos_teste_lido(:teste) ->> 'lido');

-- o que o serviço gravaria: um pedido com o melhor imóvel e uma alternativa
INSERT INTO privado.grupo_mensagem_lida (fonte, ref, pedidos) VALUES ('teste', :'teste', 1);
INSERT INTO privado.grupo_pedido (fonte, ref, parte, grupo_nome, remetente, remetente_nome, enviada_em, texto, ficha, duvidosos,
                                  local, melhor_codigo, nota, faixa, pontuado_em)
VALUES ('teste', :'teste', 1, 'Teste colado na tela', NULL, 'Pedro', now(), 'Procuro Eliza Miranda para venda',
        '{"operacao": "venda", "condominio": "Eliza Miranda", "quartos": 3, "preco_max": 300000}', '{condominio}',
        '{"operacao": "venda", "bairros": [], "condominios": ["Eliza Miranda Residencial"]}', 3050, 92.5, 'verde', now())
RETURNING id AS pedido \gset
INSERT INTO privado.grupo_pedido_par (pedido_id, codigo, posicao, nota, detalhe, imovel) VALUES
  (:pedido, 3050, 1, 92.5, '[{"criterio": "preco", "peso": 72.7, "rendimento": 100, "pontos": 72.7, "texto": "x"}]', '{"codigo": 3050}'),
  (:pedido, 3051, 2, 71.0, '[]', '{"codigo": 3051}');
INSERT INTO privado.grupo_pedido (fonte, ref, parte, grupo_nome, enviada_em, texto, ficha, local, faixa, sem_match_motivo, pontuado_em)
VALUES ('grupo', 'TESTE336-MSG', 1, 'Locação OFERTA e BUSCA', now() - interval '1 hour', 'Busco aluguel no Tarumã 2q até 2 mil',
        '{"operacao": "aluguel", "bairros": ["Tarumã"], "quartos": 2, "preco_max": 2000}',
        '{"operacao": "aluguel", "bairros": ["Tarumã"], "condominios": []}', 'sem_match', 'nenhum imóvel nosso nesse local', now()),
       ('grupo', 'TESTE336-VELHA', 1, 'Locação OFERTA e BUSCA', now() - interval '60 hours', 'pedido velho',
        '{"operacao": "aluguel", "bairros": ["Tarumã"], "quartos": 2, "preco_max": 2000}',
        '{"operacao": "aluguel", "bairros": ["Tarumã"], "condominios": []}', 'sem_match', 'nenhum imóvel nosso nesse local', now());

INSERT INTO _t SELECT 'a tela traz os pedidos da janela (48 h), o mais recente primeiro, com o melhor e a alternativa', '2/venda/2/3050',
  (SELECT jsonb_array_length(j->'pedidos') || '/' || (j->'pedidos'->0->'ficha'->>'operacao') || '/' ||
          jsonb_array_length(j->'pedidos'->0->'pares') || '/' || (j->'pedidos'->0->'pares'->0->>'codigo') FROM site_captacao_grupos() j);
INSERT INTO _t SELECT 'a contagem dos filtros', '2/1/0/1/1',
  (SELECT (c->>'todos') || '/' || (c->>'verde') || '/' || (c->>'amarelo') || '/' || (c->>'sem_match') || '/' || (c->>'teste')
     FROM (SELECT site_captacao_grupos()->'contagem' AS c) x);
INSERT INTO _t SELECT 'filtro "sem match" e filtro "nota 90+"', '1,TESTE/1,3050',
  (SELECT jsonb_array_length(j->'pedidos') || ',' || left(j->'pedidos'->0->>'texto', 0) || 'TESTE' FROM site_captacao_grupos('sem_match') j)
  || '/' || (SELECT jsonb_array_length(j->'pedidos') || ',' || (j->'pedidos'->0->'pares'->0->>'codigo') FROM site_captacao_grupos('verde') j);
INSERT INTO _t SELECT 'pedindo 72 h o pedido velho aparece', '3', (SELECT jsonb_array_length(j->'pedidos')::text FROM site_captacao_grupos('todos', 72) j);
INSERT INTO _t SELECT 'o teste lido aparece como lido e pontuado', 'true/1/true',
  (SELECT (j->>'lido') || '/' || (j->>'pedidos') || '/' || (j->>'pontuado') FROM site_captacao_grupos_teste_lido(:teste) j);

-- julgamento da leitura
INSERT INTO _t SELECT '"leitura errada" sem dizer o erro é recusada', 'Diga o que a leitura errou.', site_captacao_grupos_julgar(:pedido, 'errada', ' ') ->> 'erro';
INSERT INTO _t SELECT 'julgar: errada com o motivo, depois correta', 'true/true',
  (site_captacao_grupos_julgar(:pedido, 'errada', 'leu 3 quartos, eram 2') ->> 'ok') || '/' || (site_captacao_grupos_julgar(:pedido, 'correta') ->> 'ok');
INSERT INTO _t SELECT 'vale o último julgamento de cada pedido, e a taxa conta um por pedido', 'correta/1/1/0',
  (SELECT (j->'pedidos'->0->'julgamento'->>'leitura') || '/' || (j->'acerto'->>'julgados') || '/' || (j->'acerto'->>'corretas') || '/' || (j->'acerto'->>'erradas')
     FROM site_captacao_grupos() j);
INSERT INTO _t SELECT 'os dois julgamentos ficam guardados', '2', (SELECT count(*)::text FROM privado.grupo_pedido_julgamento WHERE pedido_id = :pedido);

-- o envio não existe
INSERT INTO _t SELECT 'APROVAR é recusado (modo treino) e o pedido continua novo', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui./novo',
  (site_captacao_grupos_estado(:pedido, 'aprovado') ->> 'erro') || '/' || (SELECT estado FROM privado.grupo_pedido WHERE id = :pedido);
INSERT INTO _t SELECT '"enviado" também é recusado', 'true', (site_captacao_grupos_estado(:pedido, 'enviado') ? 'erro')::text;
INSERT INTO _t SELECT 'rejeitar e desfazer', 'rejeitado/novo',
  (site_captacao_grupos_estado(:pedido, 'rejeitado') ->> 'estado') || '/' || (site_captacao_grupos_estado(:pedido, 'novo') ->> 'estado');

-- apelidos
SELECT btrim(bairro) AS um_bairro FROM imoveis WHERE nullif(btrim(bairro), '') IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1 \gset
INSERT INTO _t SELECT 'os apelidos de exemplo dele vieram', '3', (SELECT count(*)::text FROM privado.grupo_apelido WHERE oficial = 'Parque Ville Municipal');
INSERT INTO _t SELECT 'apelido para nome que não existe no cadastro é recusado', 'true', (site_captacao_grupos_apelido_salvar('xis', 'bairro', 'Bairro Que Não Existe 336') ? 'erro')::text;
-- (a chamada num comando e a leitura no seguinte: no mesmo comando a leitura não enxerga o que a função gravou)
SELECT site_captacao_grupos_apelido_salvar('  Apelido-Teste 336 ', 'bairro', upper(:'um_bairro')) ->> 'oficial' AS oficial_gravado \gset
INSERT INTO _t SELECT 'apelido novo de bairro: grava com o nome do cadastro e pede para refazer a conta', :'um_bairro' || '/true',
  :'oficial_gravado' || '/' || (SELECT repontuar::text FROM privado.grupo_captacao_estado WHERE id = 1);
INSERT INTO _t SELECT 'a lista traz o apelido e os nomes do cadastro para escolher', 'true/true/true',
  (SELECT (j->'apelidos' @> '[{"apelido": "apelido teste 336"}]')::text || '/' || (jsonb_array_length(j->'bairros') > 20)::text || '/' ||
          (jsonb_array_length(j->'condominios') > 300)::text FROM site_captacao_grupos_apelidos() j);
SELECT site_captacao_grupos_apelido_excluir('Apelido Teste 336') ->> 'ok' AS excluiu \gset
INSERT INTO _t SELECT 'excluir o apelido', 'true/0',
  :'excluiu' || '/' || (SELECT count(*) FROM privado.grupo_apelido WHERE apelido = 'apelido teste 336');

-- demanda do mercado: só pedido de grupo, e o que ficou sem imóvel
INSERT INTO _t SELECT 'demanda: os 2 pedidos de grupo, os 2 sem imóvel, uma linha (Tarumã, 2q, 1.500 a 2.500)', '2/2/1/aluguel/Tarumã/2/1.500 a 2.500/2',
  (SELECT (j->>'pedidos') || '/' || (j->>'sem_imovel') || '/' || jsonb_array_length(j->'linhas') || '/' || (j->'linhas'->0->>'operacao') || '/' ||
          (j->'linhas'->0->>'lugar') || '/' || (j->'linhas'->0->>'quartos') || '/' || (j->'linhas'->0->>'preco') || '/' || (j->'linhas'->0->>'sem_imovel')
     FROM site_captacao_grupos_demanda(30) j);

-- quem pode
INSERT INTO _t SELECT 'só o papel de escrita do site executa; ninguém do site lê a tabela direto', 'true/false/false',
  has_function_privilege('nay_site_escrita', 'public.site_captacao_grupos(text, integer, integer)', 'EXECUTE')::text || '/' ||
  has_function_privilege('nay_site_leitura', 'public.site_captacao_grupos(text, integer, integer)', 'EXECUTE')::text || '/' ||
  has_table_privilege('nay_site_escrita', 'privado.grupo_pedido', 'SELECT')::text;
INSERT INTO _t SELECT 'nenhuma função desta migração escreve em caixa de saída', '0',
  (SELECT count(*)::text FROM pg_proc p WHERE p.proname LIKE 'site_captacao_grupos%' AND pg_get_functiondef(p.oid) ~* '(nai_saida|core_saida|nai_enfileirar|mensagem_saida|envios)');

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '336: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '336: % testes, todos certos', m;
END $$;
