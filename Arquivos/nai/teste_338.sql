-- Testes da 338 (rodam dentro do ensaio, antes do ROLLBACK). Eventos inventados, num grupo de mentira.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

-- um evento de grupo como a Z-API manda (os campos que importam)
CREATE FUNCTION pg_temp.ev(p_id text, p_extra jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('isGroup', true, 'messageId', p_id, 'phone', '120363000000000338-group', 'chatName', 'GRUPO TESTE 338',
                            'fromMe', false, 'participantPhone', '559200000338', 'senderName', 'Corretora Teste',
                            'momment', (extract(epoch FROM now()) * 1000)::bigint, 'type', 'ReceivedCallback') || p_extra;
$$;

-- (a chamada num comando e a leitura no seguinte: no mesmo comando a leitura não enxerga o que a função gravou)
SELECT nai_grupo_guardar(pg_temp.ev('T338-TEXTO', '{"text": {"message": "Procuro apto 2q no Parque 10"}}')) AS g1 \gset
INSERT INTO _t SELECT 'texto de grupo é guardado', 'true/texto/Procuro apto 2q no Parque 10',
  :'g1'::boolean::text || '/' || (SELECT tipo || '/' || texto FROM privado.grupo_conversa WHERE message_id = 'T338-TEXTO');
SELECT nai_grupo_guardar(pg_temp.ev('T338-FOTO', '{"image": {"caption": "Alugo casa", "imageUrl": "https://exemplo.invalid/f.jpg"}}')) AS g2 \gset
INSERT INTO _t SELECT 'foto com legenda: guarda a legenda e o endereço da foto', 'true/imagem/Alugo casa/sim',
  :'g2'::boolean::text || '/' ||
  (SELECT tipo || '/' || texto || '/' || CASE WHEN midia_url IS NOT NULL THEN 'sim' ELSE 'não' END FROM privado.grupo_conversa WHERE message_id = 'T338-FOTO');
SELECT nai_grupo_guardar(pg_temp.ev('T338-AUDIO', '{"audio": {"audioUrl": "https://exemplo.invalid/a.ogg"}}')) AS g3 \gset
INSERT INTO _t SELECT 'áudio sem texto entra como áudio', 'true/audio',
  :'g3'::boolean::text || '/' || (SELECT tipo FROM privado.grupo_conversa WHERE message_id = 'T338-AUDIO');
SELECT nai_grupo_guardar(pg_temp.ev('T338-ENQUETE', '{"poll": {"question": "Quem tem casa no Tarumã?"}}')) AS g4 \gset
INSERT INTO _t SELECT 'enquete vira texto dizendo que é enquete', 'true/texto/📊 Enquete: Quem tem casa no Tarumã?',
  :'g4'::boolean::text || '/' || (SELECT tipo || '/' || texto FROM privado.grupo_conversa WHERE message_id = 'T338-ENQUETE');

INSERT INTO _t SELECT 'aviso de saiu, entrou e apagou NÃO vira mensagem', 'false/false/false/0',
  nai_grupo_guardar(pg_temp.ev('T338-SAIU', '{"notification": "GROUP_PARTICIPANT_LEAVE", "notificationParameters": ["559200000338"]}'))::text || '/' ||
  nai_grupo_guardar(pg_temp.ev('T338-ENTROU', '{"notification": "GROUP_PARTICIPANT_INVITE", "notificationParameters": ["559200000338"]}'))::text || '/' ||
  nai_grupo_guardar(pg_temp.ev('T338-APAGOU', '{"notification": "REVOKE", "notificationParameters": []}'))::text || '/' ||
  (SELECT count(*) FROM privado.grupo_conversa WHERE message_id IN ('T338-SAIU', 'T338-ENTROU', 'T338-APAGOU'));
INSERT INTO _t SELECT 'reação, "aguardando mensagem" e evento sem conteúdo também não', 'false/false/false/false',
  nai_grupo_guardar(pg_temp.ev('T338-REACAO', '{"reaction": {"value": "👍"}}'))::text || '/' ||
  nai_grupo_guardar(pg_temp.ev('T338-ESPERA', '{"waitingMessage": true}'))::text || '/' ||
  nai_grupo_guardar(pg_temp.ev('T338-NADA', '{}'))::text || '/' ||
  nai_grupo_guardar(pg_temp.ev('T338-VAZIO', '{"text": {"message": "   "}}'))::text;
INSERT INTO _t SELECT 'repetida não entra duas vezes', 'false/1',
  nai_grupo_guardar(pg_temp.ev('T338-TEXTO', '{"text": {"message": "outra coisa"}}'))::text || '/' ||
  (SELECT count(*) FROM privado.grupo_conversa WHERE message_id = 'T338-TEXTO' AND texto = 'Procuro apto 2q no Parque 10');
INSERT INTO _t SELECT 'mensagem que não é de grupo, ou sem id, não entra', 'false/false',
  nai_grupo_guardar(pg_temp.ev('T338-PV', '{"isGroup": false, "text": {"message": "oi"}}'))::text || '/' ||
  nai_grupo_guardar(pg_temp.ev('', '{"text": {"message": "oi"}}'))::text;

-- a linha vazia que um evento antigo deixou dá lugar à mensagem de verdade com o mesmo id
INSERT INTO privado.grupo_conversa (message_id, grupo_id, grupo_nome, tipo) VALUES ('T338-OCUPADA', '120363000000000338-group', 'GRUPO TESTE 338', 'outro');
SELECT nai_grupo_guardar(pg_temp.ev('T338-OCUPADA', '{"text": {"message": "Busco sala comercial"}}')) AS g5 \gset
INSERT INTO _t SELECT 'linha vazia antiga não barra a mensagem de verdade', 'true/texto/Busco sala comercial',
  :'g5'::boolean::text || '/' || (SELECT tipo || '/' || texto FROM privado.grupo_conversa WHERE message_id = 'T338-OCUPADA');

-- a aba do CRM: só mensagem de verdade aparece e conta
INSERT INTO privado.grupo_conversa (message_id, grupo_id, grupo_nome, tipo) VALUES ('T338-LIXO', '120363000000000338-group', 'GRUPO TESTE 338', 'outro');
INSERT INTO _t SELECT 'a aba mostra as 5 mensagens e esconde a linha vazia', '5/0',
  (SELECT jsonb_array_length(j)::text || '/' || (SELECT count(*) FROM jsonb_array_elements(j) e WHERE e->>'tipo' = 'outro')
     FROM crm_grupo_mensagens('120363000000000338-group', NULL, 80) j);
INSERT INTO _t SELECT 'a lista de grupos conta só mensagem de verdade', '5',
  (SELECT crm_grupos_conhecidos() -> '120363000000000338-group' ->> 'mensagens');
INSERT INTO _t SELECT 'num grupo de verdade que só tinha avisos, a aba passa a vir vazia (antes vinham balões "Mensagem")', '0',
  (SELECT jsonb_array_length(crm_grupo_mensagens(g.grupo_id, NULL, 80))::text
     FROM (SELECT grupo_id FROM privado.grupo_conversa WHERE grupo_id <> '120363000000000338-group'
            GROUP BY 1 HAVING bool_and(tipo = 'outro' AND texto IS NULL AND midia_url IS NULL) ORDER BY count(*) DESC LIMIT 1) g);

-- o roteador: os dois formatos de id de grupo vão ao espelho; o resto continua como era
INSERT INTO _t SELECT 'grupo de id novo e de id ANTIGO vão ao espelho do CRM', 'nai/nai',
  nai_quem_atende('120363000000000338-group', true, 'oi') || '/' || nai_quem_atende('559200000338-1600000000', true, 'oi');
INSERT INTO _t SELECT 'lista de transmissão e canal (marcados como grupo, sem id de grupo) continuam fora', 'nay/nay',
  nai_quem_atende('559200000338', true, 'oi') || '/' || nai_quem_atende('120363000000000338@newsletter', true, 'oi');
INSERT INTO _t SELECT 'conversa privada continua indo para onde ia', nai_quem_atende('559200000338', false),
  nai_quem_atende('559200000338', false, 'bom dia');

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '338: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '338: % testes, todos certos', m;
END $$;
