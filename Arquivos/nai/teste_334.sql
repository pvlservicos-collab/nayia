-- Testes da 334 (rodam dentro do ensaio, antes do ROLLBACK). Nada daqui chega a ninguém: a caixa de saída
-- só é lida depois do COMMIT, e o ensaio termina em ROLLBACK.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

-- o relógio não decide o teste; e o que estiver de verdade na fila sai da frente (só nesta transação)
UPDATE nai_config SET valor = '0'  WHERE chave = 'aviso_saida_hora_ini';
UPDATE nai_config SET valor = '24' WHERE chave = 'aviso_saida_hora_fim';
UPDATE aviso_de_saida SET avisado_em = now() WHERE avisado_em IS NULL AND marcado_em > now() - interval '30 hours';

SELECT nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel') AS tel \gset
SELECT nai_cfg('tel_telefone') AS tel_fone \gset
SELECT id AS outro FROM nai_contato WHERE NOT (id = ANY (nai_contato_irmaos(:tel))) ORDER BY id DESC LIMIT 1 \gset
SELECT coalesce((SELECT x FROM unnest(nai_contato_irmaos(:tel)) x WHERE x <> :tel LIMIT 1), :tel) AS tel_irmao \gset
SELECT k[1] AS a, k[2] AS b, k[3] AS c, k[4] AS d, k[5] AS e, k[6] AS f, k[7] AS g, k[8] AS h
  FROM (SELECT array_agg(codigo ORDER BY codigo DESC) AS k
          FROM (SELECT codigo FROM imoveis
                 WHERE coalesce(disponivel, true) AND status = 'Disponível' AND motivo_bloqueio IS NULL
                   AND codigo BETWEEN 2000 AND 99999
                 ORDER BY codigo DESC LIMIT 8) x) y \gset

-- ============ 1. um imóvel sai: entra na fila, mas o grupo espera
UPDATE imoveis SET disponivel = false, status = 'Alugado' WHERE codigo = :a;
INSERT INTO _t SELECT 'a saída entrou na fila', 'alugado', (SELECT motivo FROM aviso_de_saida WHERE codigo = :'a' AND avisado_em IS NULL);
INSERT INTO _t SELECT 'antes da pergunta, o grupo não recebe nada', '0', (SELECT count(*)::text FROM nay_saidas_a_avisar(6));

SELECT nay_saidas_perguntar() AS p1 \gset
INSERT INTO _t SELECT 'a agenda pergunta ao Tel (1 imóvel)', '1', :'p1';
INSERT INTO _t SELECT 'a pergunta está na caixa, para o Tel, com o código e o pedido de SIM ou NÃO', 'sim',
  coalesce((SELECT CASE WHEN s.contato_id = :tel AND s.papel_destino = 'tel' AND s.estado = 'pendente'
                         AND s.texto LIKE 'Tel, saiu do ar: ' || :'a' || ' — %, alugado.%'
                         AND s.texto LIKE '%Aviso no grupo Easy? Responda SIM ou NÃO.' THEN 'sim'
                        ELSE s.estado || ' | ' || s.texto END
              FROM nai_saida s JOIN aviso_de_saida_pergunta q ON q.saida_id = s.id
             WHERE q.codigo = :'a' AND s.motivo = 'aviso_saida_pergunta'), '(sem mensagem)');
INSERT INTO _t SELECT 'depois da pergunta e antes do SIM, o grupo continua sem nada', '0', (SELECT count(*)::text FROM nay_saidas_a_avisar(6));
SELECT nay_saidas_perguntar() AS p2 \gset
INSERT INTO _t SELECT 'não pergunta duas vezes o mesmo imóvel', '0', :'p2';

-- ============ 2. o que é e o que não é resposta
INSERT INTO _t SELECT 'lê "' || x.txt || '"', x.esp, coalesce((SELECT resposta FROM nay_saida_resposta_ler(:tel, x.txt, NULL)), '-')
  FROM (VALUES ('sim', 'sim'), ('Sim.', 'sim'), ('SIM!', 'sim'), ('s', 'sim'), ('pode avisar', 'sim'), ('Pode sim', 'sim'),
               ('avisa no grupo', 'sim'), ('nay, sim', 'sim'), ('Sim, pode mandar no grupo', 'sim'),
               ('não', 'nao'), ('Nao precisa', 'nao'), ('n', 'nao'), ('não avisa', 'nao'), ('Não, deixa quieto', 'nao'),
               ('ok', '-'), ('bom dia', '-'), ('sim, manda as fotos do 3050 pro Carlos', '-'), ('sim quero', '-'),
               ('não sei', '-'), ('', '-'), ('visitas', '-'), ('simone', '-'), ('alugado 5727', '-')) AS x(txt, esp);
INSERT INTO _t SELECT 'lê "SIM <código>" do imóvel perguntado', 'sim', coalesce((SELECT resposta FROM nay_saida_resposta_ler(:tel, 'SIM ' || :'a', NULL)), '-');
INSERT INTO _t SELECT 'lê "não <código>" do imóvel perguntado', 'nao', coalesce((SELECT resposta FROM nay_saida_resposta_ler(:tel, 'não ' || :'a', NULL)), '-');
INSERT INTO _t SELECT '"SIM <código>" de imóvel sem pergunta não é daqui', '-', coalesce((SELECT resposta FROM nay_saida_resposta_ler(:tel, 'SIM ' || :'h', NULL)), '-');
INSERT INTO _t SELECT 'o "sim" de outra pessoa não vale', 'false', nay_saida_resposta_valida(:outro, 'sim')::text;
INSERT INTO _t SELECT 'o "sim" pela outra linha do Tel vale', 'true', nay_saida_resposta_valida(:tel_irmao, 'sim')::text;
INSERT INTO _t SELECT 'marcou OUTRA mensagem: o "sim" não é do aviso', 'false', nay_saida_resposta_valida(:tel, 'sim', 'TESTE334-OUTRA-MENSAGEM')::text;
UPDATE nai_saida SET message_id = 'TESTE334-PERGUNTA-A' WHERE id = (SELECT saida_id FROM aviso_de_saida_pergunta WHERE codigo = :'a');
INSERT INTO _t SELECT 'marcou a pergunta: o "sim" é do aviso', 'true', nay_saida_resposta_valida(:tel, 'sim', 'TESTE334-PERGUNTA-A')::text;

-- ============ 3. o caminho inteiro: a mensagem do Tel abre turno de comando e o comando responde
CREATE TEMP TABLE _cab AS SELECT nai_abrir_turno(:'tel_fone', 'Tel', 'sim', NULL, '{}'::bigint[]) AS cab;
INSERT INTO _t SELECT 'o "sim" do Tel abre turno de comando', 'true/tel/true',
  (SELECT (cab->>'ok') || '/' || (cab->>'papel') || '/' || (cab->>'comando_nai') FROM _cab);
SELECT (cab->>'turno_id') AS turno FROM _cab \gset
SELECT msg_tel AS r1 FROM nai_comando_tel(:turno, 'sim') \gset
INSERT INTO _t SELECT 'a Nay confirma ao Tel que vai avisar', 'sim',
  CASE WHEN :'r1' LIKE 'Combinado, aviso no grupo Easy: ' || :'a' || ' — %, alugado.' THEN 'sim' ELSE :'r1' END;
INSERT INTO _t SELECT 'a resposta ficou gravada, com o turno', 'sim/' || :'turno',
  (SELECT resposta || '/' || turno_id FROM aviso_de_saida_pergunta WHERE codigo = :'a');
INSERT INTO _t SELECT 'a confirmação está na caixa como resposta do turno', '1',
  (SELECT count(*)::text FROM nai_saida WHERE turno_id = :turno AND motivo = 'comando_aviso_saida' AND papel_destino = 'turno' AND estado = 'pendente');
INSERT INTO _t SELECT 'depois do SIM, o grupo recebe esse (e só esse)', :'a' || '/alugado',
  (SELECT string_agg(codigo || '/' || motivo, ',') FROM nay_saidas_a_avisar(6));

SELECT nay_reservar_aviso_de_saida(:'a') AS res \gset
INSERT INTO _t SELECT 'o cron reservou: não volta para a fila', 't/0', :'res' || '/' || (SELECT count(*) FROM nay_saidas_a_avisar(6));
INSERT INTO _t SELECT 'sem pergunta aberta, "sim" volta a ser conversa comum', 'false', nay_saida_resposta_valida(:tel, 'sim')::text;
CREATE TEMP TABLE _cab2 AS SELECT nai_abrir_turno(:'tel_fone', 'Tel', 'sim', NULL, '{}'::bigint[]) AS cab;
INSERT INTO _t SELECT 'e o cabeçalho não chama de comando', 'tel/false', (SELECT (cab->>'papel') || '/' || (cab->>'comando_nai') FROM _cab2);

-- ============ 4. dois saem juntos: uma pergunta só; "não" vale para os dois; "SIM <código>" muda um
UPDATE imoveis SET disponivel = false, status = 'Vendido' WHERE codigo IN (:b, :c);
SELECT nay_saidas_perguntar() AS p3 \gset
INSERT INTO _t SELECT 'dois imóveis: uma pergunta só, com os dois', '2/1/sim',
  :'p3' || '/' || (SELECT count(DISTINCT saida_id) FROM aviso_de_saida_pergunta WHERE codigo IN (:'b', :'c')) || '/' ||
  (SELECT CASE WHEN s.texto LIKE 'Tel, saíram do ar:%' AND s.texto LIKE '%• ' || :'b' || ' — %, vendido%'
                AND s.texto LIKE '%• ' || :'c' || ' — %, vendido%' AND s.texto LIKE '%SIM avisa todos, NÃO nenhum.%' THEN 'sim' ELSE s.texto END
     FROM nai_saida s WHERE s.id = (SELECT max(saida_id) FROM aviso_de_saida_pergunta WHERE codigo = :'b'));
SELECT nay_saida_responder(NULL, :tel, 'não', NULL) AS r2 \gset
INSERT INTO _t SELECT '"não" solto: nenhum dos dois vai ao grupo', 'sim/nao,nao/0',
  CASE WHEN :'r2' LIKE 'Combinado, não aviso no grupo: %' AND :'r2' LIKE '%' || :'b' || ' — %' AND :'r2' LIKE '%' || :'c' || ' — %' THEN 'sim' ELSE :'r2' END
  || '/' || (SELECT string_agg(resposta, ',') FROM aviso_de_saida_pergunta WHERE codigo IN (:'b', :'c'))
  || '/' || (SELECT count(*) FROM nay_saidas_a_avisar(6));
SELECT nay_saida_responder(NULL, :tel, 'SIM ' || :'b', NULL) AS r3 \gset
INSERT INTO _t SELECT 'mudou de ideia com "SIM <código>": só esse vai', 'sim/' || :'b' || '/vendido',
  CASE WHEN :'r3' LIKE 'Combinado, aviso no grupo Easy: ' || :'b' || ' — %, vendido.' THEN 'sim' ELSE :'r3' END
  || '/' || (SELECT string_agg(codigo || '/' || motivo, ',') FROM nay_saidas_a_avisar(6));
SELECT nay_reservar_aviso_de_saida(:'b') AS res \gset

-- ============ 5. duas perguntas abertas: "sim" solto vale para a ÚLTIMA, e a Nay lembra da outra
UPDATE imoveis SET disponivel = false, status = 'Alugado' WHERE codigo = :d;
SELECT nay_saidas_perguntar() AS p4 \gset
UPDATE imoveis SET disponivel = false, status = 'Indisponível' WHERE codigo = :e;
SELECT nay_saidas_perguntar() AS p5 \gset
SELECT nay_saida_responder(NULL, :tel, 'Sim', NULL) AS r4 \gset
INSERT INTO _t SELECT '"sim" solto com duas perguntas: só a última', '1/1/sim/' || :'e',
  :'p4' || '/' || :'p5' || '/' ||
  CASE WHEN :'r4' LIKE 'Combinado, aviso no grupo Easy: ' || :'e' || ' — %, indisponível.%'
        AND :'r4' LIKE '%Ainda sem resposta: ' || :'d' || '. Responda SIM ' || :'d' || ', NÃO ' || :'d' || ' ou SIM TODOS.' THEN 'sim' ELSE :'r4' END
  || '/' || (SELECT string_agg(codigo, ',') FROM nay_saidas_a_avisar(6));
SELECT nay_saida_responder(NULL, :tel, 'sim todos', NULL) AS r5 \gset
INSERT INTO _t SELECT '"SIM TODOS" pega a que faltava', 'sim/2',
  CASE WHEN :'r5' LIKE 'Combinado, aviso no grupo Easy: ' || :'d' || ' — %, alugado.' THEN 'sim' ELSE :'r5' END
  || '/' || (SELECT count(*) FROM nay_saidas_a_avisar(6));
SELECT nay_reservar_aviso_de_saida(:'d') AS res \gset
SELECT nay_reservar_aviso_de_saida(:'e') AS res \gset

-- ============ 6. o imóvel voltou antes da resposta: não tem aviso
UPDATE imoveis SET disponivel = false, status = 'Alugado' WHERE codigo = :f;
SELECT nay_saidas_perguntar() AS p6 \gset
UPDATE imoveis SET disponivel = true, status = 'Disponível' WHERE codigo = :f;
SELECT nay_saida_responder(NULL, :tel, 'sim', NULL) AS r6 \gset
INSERT INTO _t SELECT 'voltou a ficar disponível: o SIM não avisa', '1/Voltou a ficar disponível, então não tem aviso: ' || :'f' || './vencida/0',
  :'p6' || '/' || :'r6' || '/' || (SELECT resposta FROM aviso_de_saida_pergunta WHERE codigo = :'f') || '/' || (SELECT count(*) FROM nay_saidas_a_avisar(6));

-- ============ 7. sem resposta no prazo: vence, o grupo não é avisado, e a Nay não pergunta de novo
UPDATE imoveis SET disponivel = false, status = 'Alugado' WHERE codigo = :g;
SELECT nay_saidas_perguntar() AS p7 \gset
UPDATE aviso_de_saida_pergunta SET perguntado_em = now() - interval '25 hours' WHERE codigo = :'g';
INSERT INTO _t SELECT 'passou das 24 h: "sim" solto já não vale', 'false', nay_saida_resposta_valida(:tel, 'sim')::text;
SELECT nay_saidas_perguntar() AS p8 \gset
INSERT INTO _t SELECT 'a pergunta vence e não é refeita', '1/0/vencida/0',
  :'p7' || '/' || :'p8' || '/' || (SELECT resposta FROM aviso_de_saida_pergunta WHERE codigo = :'g') || '/' || (SELECT count(*) FROM nay_saidas_a_avisar(6));
INSERT INTO _t SELECT 'vencida ainda aceita "SIM <código>"', 'true', nay_saida_resposta_valida(:tel, 'sim ' || :'g')::text;

-- ============ 8. de noite e parada a pergunta espera; com a chave desligada volta o aviso automático
UPDATE imoveis SET disponivel = false, status = 'Vendido' WHERE codigo = :h;
UPDATE nai_config SET valor = '0' WHERE chave = 'aviso_saida_hora_fim';
SELECT nay_saidas_perguntar() AS p9 \gset
UPDATE nai_config SET valor = '24' WHERE chave = 'aviso_saida_hora_fim';
UPDATE nai_config SET valor = 'sim' WHERE chave = 'pausada';
SELECT nay_saidas_perguntar() AS p10 \gset
UPDATE nai_config SET valor = 'nao' WHERE chave = 'pausada';
INSERT INTO _t SELECT 'fora de hora e com a Nay parada, não pergunta (e não perde a saída)', '0/0/0',
  :'p9' || '/' || :'p10' || '/' || (SELECT count(*) FROM aviso_de_saida_pergunta WHERE codigo = :'h');
UPDATE nai_config SET valor = 'nao' WHERE chave = 'aviso_saida_pergunta';
SELECT nay_saidas_perguntar() AS p11 \gset
-- sai sozinho o que ficou sem resposta (o vencido e o novo); o que ele respondeu NÃO continua sem aviso
INSERT INTO _t SELECT 'chave desligada: não pergunta e o aviso sai sozinho, menos o que teve NÃO',
  '0/' || (SELECT string_agg(x, ',' ORDER BY x) FROM unnest(ARRAY[:'g', :'h']) x) || '/false',
  :'p11' || '/' || (SELECT string_agg(codigo, ',' ORDER BY codigo) FROM nay_saidas_a_avisar(6)) || '/' || nay_saida_resposta_valida(:tel, 'sim')::text;
UPDATE nai_config SET valor = 'sim' WHERE chave = 'aviso_saida_pergunta';
SELECT nay_saidas_perguntar() AS p12 \gset
INSERT INTO _t SELECT 'chave ligada de novo: pergunta, e o grupo espera', '1/0', :'p12' || '/' || (SELECT count(*) FROM nay_saidas_a_avisar(6));

-- ============ 9. o resto continua como era
CREATE TEMP TABLE _cab3 AS SELECT nai_abrir_turno(:'tel_fone', 'Tel', 'visitas', NULL, '{}'::bigint[]) AS cab;
SELECT (cab->>'turno_id') AS turno3 FROM _cab3 \gset
SELECT msg_tel AS r7 FROM nai_comando_tel(:turno3, 'visitas') \gset
INSERT INTO _t SELECT 'o comando VISITAS responde como sempre', 'sim',
  CASE WHEN :'r7' LIKE 'Visitas em andamento:%' OR :'r7' = 'Nenhuma visita em andamento.' THEN 'sim' ELSE :'r7' END;
INSERT INTO _t SELECT 'a aprovação da visita não foi tocada', '0',
  position('nay_saida' IN pg_get_functiondef('public.nai_resposta_aprovacao_valida(bigint,text)'::regprocedure))::text;
INSERT INTO _t SELECT 'cada função foi remendada o número certo de vezes (agenda 1, turno 2, comando 1)', '1/2/1',
  ((length(pg_get_functiondef('public.nai_agenda_tick()'::regprocedure))
    - length(replace(pg_get_functiondef('public.nai_agenda_tick()'::regprocedure), 'nay_saidas_perguntar()', ''))) / length('nay_saidas_perguntar()'))::text
  || '/' ||
  ((length(pg_get_functiondef('public.nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure))
    - length(replace(pg_get_functiondef('public.nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure), 'nay_saida_resposta_valida(', ''))) / length('nay_saida_resposta_valida('))::text
  || '/' ||
  ((length(pg_get_functiondef('public.nai_comando_tel(bigint,text)'::regprocedure))
    - length(replace(pg_get_functiondef('public.nai_comando_tel(bigint,text)'::regprocedure), 'nay_saida_responder(', ''))) / length('nay_saida_responder('))::text;
INSERT INTO _t SELECT 'nenhuma mensagem deste ensaio foi para grupo', '0',
  (SELECT count(*)::text FROM nai_saida s JOIN nai_contato c ON c.id = s.contato_id WHERE s.criado_em = now() AND c.chave ~ 'group');

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '334: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '334: % testes, todos certos', m;
END $$;
