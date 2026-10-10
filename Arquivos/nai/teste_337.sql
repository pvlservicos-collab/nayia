-- Testes da 337 (rodam dentro do ensaio, antes do ROLLBACK). Linhas inventadas, em tabela nova.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

SELECT to_char(now() - interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SS') || '-04:00' AS h1,
       to_char(now() - interval '30 hours', 'YYYY-MM-DD"T"HH24:MI:SS') || '-04:00' AS h2,
       to_char(now() - interval '80 hours', 'YYYY-MM-DD"T"HH24:MI:SS') || '-04:00' AS velha \gset

SELECT site_captacao_grupos_importar('  🟢 Locação   OFERTA e BUSCA 🔍 - TESTE337 ', jsonb_build_array(
  jsonb_build_object('quando', :'h1', 'autor', 'Carla Corretora', 'texto', 'Procuro apartamento para alugar no Parque Vile, 2 quartos até 1.800'),
  jsonb_build_object('quando', :'h2', 'autor', '+55 92 98888-7777', 'texto', 'Busco aluguel Primer cidada nova, cru. Valor máximo 2 mil'),
  jsonb_build_object('quando', :'h2', 'autor', '~ João Silva', 'texto', 'alguém tem casa no Tarumã?'),
  jsonb_build_object('quando', :'velha', 'autor', 'Fulano', 'texto', 'pedido de três dias atrás'),
  jsonb_build_object('quando', 'ontem de tarde', 'autor', 'Fulano', 'texto', 'data torta'),
  jsonb_build_object('quando', :'h1', 'autor', 'Fulano', 'texto', '   '))) AS r1 \gset
INSERT INTO _t SELECT 'importa só o que tem data certa, texto e está na janela de 48 h', 'true/4/3/3/0/48',
  (:'r1'::jsonb->>'ok') || '/' || (:'r1'::jsonb->>'recebidas') || '/' || (:'r1'::jsonb->>'na_janela') || '/' || (:'r1'::jsonb->>'novas') || '/' ||
  (:'r1'::jsonb->>'repetidas') || '/' || (:'r1'::jsonb->>'horas');
INSERT INTO _t SELECT 'o nome do grupo fica limpo', '🟢 Locação OFERTA e BUSCA 🔍 - TESTE337', :'r1'::jsonb->>'grupo';
INSERT INTO _t SELECT 'autor que é telefone vira telefone; nome vira nome (sem o til)', '(telefone)/João Silva/Carla Corretora',
  (SELECT CASE WHEN remetente ~ '^55\d{10,11}$' AND remetente_nome IS NULL THEN '(telefone)' ELSE 'errado' END FROM privado.grupo_importada WHERE texto LIKE 'Busco aluguel Primer%' AND grupo_nome LIKE '%TESTE337')
  || '/' || (SELECT remetente_nome FROM privado.grupo_importada WHERE texto = 'alguém tem casa no Tarumã?' AND grupo_nome LIKE '%TESTE337')
  || '/' || (SELECT remetente_nome FROM privado.grupo_importada WHERE texto LIKE 'Procuro apartamento%' AND grupo_nome LIKE '%TESTE337');

SELECT site_captacao_grupos_importar('🟢 Locação OFERTA e BUSCA 🔍 - TESTE337', jsonb_build_array(
  jsonb_build_object('quando', :'h1', 'autor', 'Carla Corretora', 'texto', 'Procuro apartamento para alugar no Parque Vile, 2 quartos até 1.800'),
  jsonb_build_object('quando', :'h1', 'autor', 'Outra Pessoa', 'texto', 'Procuro apartamento para alugar no Parque Vile, 2 quartos até 1.800'))) AS r2 \gset
INSERT INTO _t SELECT 'importar o mesmo arquivo de novo não repete (só entra o que é novo)', '2/1/1',
  (:'r2'::jsonb->>'na_janela') || '/' || (:'r2'::jsonb->>'novas') || '/' || (:'r2'::jsonb->>'repetidas');

INSERT INTO _t SELECT 'sem grupo, sem lista, e lista grande demais são recusados', 'true/true/true',
  (site_captacao_grupos_importar(' ', '[]') ? 'erro')::text || '/' || (site_captacao_grupos_importar('G', '{"a": 1}') ? 'erro')::text || '/' ||
  (site_captacao_grupos_importar('G', (SELECT jsonb_agg(jsonb_build_object('quando', :'h1', 'autor', 'a', 'texto', 't' || n)) FROM generate_series(1, 2001) n)) ? 'erro')::text;

-- a tela sabe o que foi importado e o que falta ler
INSERT INTO _t SELECT 'a tela conta as importadas e a fila do leitor', '4/1/true',
  (SELECT (j->'fonte'->>'importadas') || '/' || (j->'fonte'->>'grupos_importados') || '/' || ((j->'fonte'->>'na_fila')::int >= 4)::text FROM site_captacao_grupos() j);
INSERT INTO privado.grupo_mensagem_lida (fonte, ref, pedidos, motivo)
SELECT 'grupo', g.ref, 0, 'a IA leu e não é pedido de imóvel' FROM privado.grupo_importada g WHERE g.texto = 'alguém tem casa no Tarumã?' AND g.grupo_nome LIKE '%TESTE337';
INSERT INTO _t SELECT 'lida uma, a fila diminui e ela conta como "não era pedido"', 'true/true',
  (SELECT ((j->'fonte'->>'na_fila')::int >= 3)::text || '/' || ((j->'fonte'->>'nao_eram_pedido')::int >= 1)::text FROM site_captacao_grupos() j);
INSERT INTO _t SELECT 'o resto da tela continua igual (modo, contagem, pedidos)', 'treino/true/true',
  (SELECT (j->>'modo') || '/' || (j ? 'contagem')::text || '/' || (jsonb_typeof(j->'pedidos') = 'array')::text FROM site_captacao_grupos() j);

INSERT INTO _t SELECT 'só o papel de escrita do site importa; ninguém do site lê a tabela direto', 'true/false/false',
  has_function_privilege('nay_site_escrita', 'public.site_captacao_grupos_importar(text, jsonb)', 'EXECUTE')::text || '/' ||
  has_function_privilege('nay_site_leitura', 'public.site_captacao_grupos_importar(text, jsonb)', 'EXECUTE')::text || '/' ||
  has_table_privilege('nay_site_escrita', 'privado.grupo_importada', 'SELECT')::text;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '337: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '337: % testes, todos certos', m;
END $$;
