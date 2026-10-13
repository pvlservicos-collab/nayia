-- Testes da 359 (dentro do ensaio, antes do ROLLBACK)
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
CREATE TEMP TABLE _d AS SELECT crm_captacao_disparo_oficial() AS j;
CREATE TEMP TABLE _l AS SELECT x->>'chave' AS chave, x->>'rotulo' AS rotulo, (x->>'enviados')::int AS enviados, (x->>'faltam')::int AS faltam, ord
  FROM _d, jsonb_array_elements(j->'listas') WITH ORDINALITY AS t(x, ord);
INSERT INTO _t SELECT 'as quatro listas, na ordem', 'lista6,lista8,anterior,retomada', (SELECT string_agg(chave, ',' ORDER BY ord) FROM _l);
INSERT INTO _t SELECT 'lista 6: recebeu = leads da lista com envio', (SELECT count(*)::text FROM captacao_leads WHERE quem_importou LIKE 'Pedro (lista 6:%' AND ultimo_envio_em IS NOT NULL),
  (SELECT enviados::text FROM _l WHERE chave = 'lista6');
-- "faltam" é quem AINDA está na fila: quem falou conosco depois de entrar, ou virou corretor, sai sozinho (352)
INSERT INTO _t SELECT 'lista 6: faltam = os da lista que estão na fila do disparo',
  (SELECT count(*)::text FROM captacao_py_fila_do_disparo() f(id) JOIN captacao_leads l ON l.id = f.id WHERE l.quem_importou LIKE 'Pedro (lista 6:%'),
  (SELECT faltam::text FROM _l WHERE chave = 'lista6');
INSERT INTO _t SELECT 'lista 8: ninguém recebeu ainda, 40 na fila', '0/40', (SELECT enviados || '/' || faltam FROM _l WHERE chave = 'lista8');
INSERT INTO _t SELECT 'a soma do que falta é a fila inteira', (SELECT count(*)::text FROM captacao_py_fila_do_disparo()), (SELECT sum(faltam)::text FROM _l);
INSERT INTO _t SELECT 'desligado aparece como desligado', 'false/desligado', (SELECT (j->>'ligado') || '/' || (j->>'motivo') FROM _d);
INSERT INTO _t SELECT 'os campos de sempre continuam', 'true', (SELECT (j ? 'hoje' AND j ? 'falharam_hoje' AND j ? 'seg_medio' AND j ? 'volta_em' AND j ? 'ultimo_em')::text FROM _d);
INSERT INTO _t SELECT 'o papel que o CRM usa (nay_disparo) continua podendo chamar', 'true', (SELECT has_function_privilege('nay_disparo', 'crm_captacao_disparo_oficial()', 'EXECUTE')::text);
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT rotulo, enviados, faltam FROM _l ORDER BY ord;
