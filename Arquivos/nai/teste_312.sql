-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;

-- 1. as três visitas da Nay que já estavam no calendário continuam lá
INSERT INTO _t (caso, esperado, veio)
SELECT 'as 3 da Nay que já estavam no calendário continuam', '3', count(*)::text
  FROM crm_visitas('2026-10-01', NULL) WHERE id IN (1086, 1087, 1088);

-- um corretor de verdade (com telefone, não @lid) e dois imóveis sem visita nenhuma
CREATE TEMP TABLE _c ON COMMIT DROP AS
SELECT c.id AS cor, c.telefone FROM nai_contato c
 WHERE c.id IN (SELECT corretor_id FROM nai_visita WHERE criado_em > now() - interval '15 days')
   AND c.telefone !~* 'lid' AND nai_contato_do_cadastro(c.telefone, NULL) = c.id
 ORDER BY c.id DESC LIMIT 1;
CREATE TEMP TABLE _i ON COMMIT DROP AS
SELECT (array_agg(codigo ORDER BY codigo DESC))[1] AS a, (array_agg(codigo ORDER BY codigo DESC))[2] AS b
  FROM imoveis WHERE status = 'Disponível' AND codigo NOT IN (SELECT codigo FROM nai_visita);

-- 2. a Nay confirma uma visita com o corretor (a linha nasce como o fluxo dela faz: com_rayssa, sem "criada no CRM")
INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, confirmada_corretor_em)
SELECT i.a, c.cor, date_trunc('hour', now()) + interval '2 days', 'com_rayssa', 'equipe', now() FROM _c c, _i i
RETURNING id AS nay_id \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'visita nova da Nay: NÃO aparece na agenda', '0', count(*)::text FROM crm_visitas(NULL, NULL) WHERE id = :nay_id;
INSERT INTO _t (caso, esperado, veio)
SELECT 'mas continua aberta (é ela que põe o corretor na etapa Visitas e cala a Nay)', 'com_rayssa/true',
       estado || '/' || nai_visita_aberta(estado) FROM nai_visita WHERE id = :nay_id;

-- 3. a Rayssa agenda à mão o mesmo corretor e o mesmo imóvel, em outro horário: o pedido da Nay vira a visita dela
CREATE TEMP TABLE _r ON COMMIT DROP AS
SELECT r.ok, r.visita, r.mensagem FROM _c c, _i i,
       crm_visita_agendar(i.a, c.telefone, NULL, date_trunc('hour', now()) + interval '3 days', 90, 'Teste 312') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'agendar à mão: aceita e usa a MESMA visita', 'true/true', ok || '/' || (visita = :nay_id) FROM _r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'agora aparece na agenda, com o horário e a duração dela', '1/true/90/Teste 312',
       count(*) || '/' || bool_and(v.quando = date_trunc('hour', now()) + interval '3 days') || '/' || max(v.duracao_min) || '/' || max(v.criada_no_crm_por)
  FROM crm_visitas(NULL, NULL) a JOIN nai_visita v ON v.id = a.id WHERE a.id = :nay_id;
INSERT INTO _t (caso, esperado, veio)
SELECT 'continua uma visita só para esse corretor e esse imóvel', '1', count(*)::text
  FROM nai_visita v, _c c, _i i WHERE v.codigo = i.a AND v.corretor_id = c.cor;

-- 4. clicar de novo no mesmo horário: a trava do clique duplo continua valendo
INSERT INTO _t (caso, esperado, veio)
SELECT 'mesmo horário de novo: recusa', 'false/true', r.ok || '/' || (r.mensagem LIKE 'Essa visita já está na agenda%')
  FROM _c c, _i i, crm_visita_agendar(i.a, c.telefone, NULL, date_trunc('hour', now()) + interval '3 days', 90, 'Teste 312') r;

-- 5. visita à mão sem pedido da Nay: nasce nova, como sempre, e aparece
CREATE TEMP TABLE _m ON COMMIT DROP AS
SELECT r.ok, r.visita FROM _c c, _i i,
       crm_visita_agendar(i.b, c.telefone, NULL, date_trunc('hour', now()) + interval '4 days', 60, 'Teste 312') r;
INSERT INTO _t (caso, esperado, veio)
SELECT 'à mão, sem pedido da Nay: visita nova na agenda', 'true/true/1',
       m.ok || '/' || (m.visita <> :nay_id) || '/' || (SELECT count(*) FROM crm_visitas(NULL, NULL) a WHERE a.id = m.visita) FROM _m m;

-- 6. o papel do CRM continua lendo a agenda e agendando
SELECT has_function_privilege('nay_disparo', 'crm_visitas(date,date)', 'EXECUTE')
       AND has_function_privilege('nay_disparo', 'crm_visita_agendar(integer,text,text,timestamptz,integer,text)', 'EXECUTE') AS pode \gset
INSERT INTO _t (caso, esperado, veio) VALUES ('o CRM continua podendo ler a agenda e agendar', 't', :'pode');

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_312: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
