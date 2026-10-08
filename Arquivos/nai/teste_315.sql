-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
SET LOCAL statement_timeout = '20s';
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;
SELECT telefone AS tel FROM captacao_leads WHERE id = 835 \gset
SELECT telefone AS outro FROM captacao_leads WHERE id <> 835 AND status = 'concluido' ORDER BY id LIMIT 1 \gset

-- 1. quem é do Python: o número do Pedro, com e sem o nono dígito; os outros não
INSERT INTO _t (caso, esperado, veio)
SELECT 'o número do Pedro é do Python (13 e 12 dígitos); outro número não', 'true/true/false',
       captacao_e_do_python(:'tel') || '/' || captacao_e_do_python(left(:'tel', 4) || right(:'tel', 8)) || '/' || captacao_e_do_python(:'outro');

-- 2. o gatilho: a mensagem que CHEGA do Pedro entra como 'Recebido py'; a dos outros e a que SAI não mudam
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES (835, :'tel', 'recebida', 'texto', 'teste 315 a', 'Recebido');
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES (NULL, :'outro', 'recebida', 'texto', 'teste 315 b', 'Recebido');
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES (835, :'tel', 'enviada', 'resposta', 'teste 315 c', 'Enviado');
INSERT INTO _t (caso, esperado, veio)
SELECT 'status de entrada pelo gatilho', 'Recebido py/Recebido/Enviado',
       (SELECT status FROM captacao_mensagens WHERE texto = 'teste 315 a') || '/' || (SELECT status FROM captacao_mensagens WHERE texto = 'teste 315 b')
       || '/' || (SELECT status FROM captacao_mensagens WHERE texto = 'teste 315 c');

-- 3. a pergunta da indicação: pendente depois de um disparo novo; some quando a pergunta sai
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES (835, :'tel', 'enviada', 'disparo', 'modelo de teste 315', 'Enviado');
INSERT INTO _t (caso, esperado, veio)
SELECT 'depois do disparo a pergunta da indicação está pendente', 'true', (captacao_indicacao_pendente(:'tel') LIKE '%conhece alguém que esteja vendendo um imóvel%')::text;
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status)
VALUES (835, :'tel', 'enviada', 'resposta', 'Sr. Pedro, para finalizar: o Sr. conhece alguém que esteja vendendo um imóvel e que possa nos indicar?', 'Enviado');
INSERT INTO _t (caso, esperado, veio)
SELECT 'depois que a pergunta saiu não pergunta de novo', 'true', (captacao_indicacao_pendente(:'tel') IS NULL)::text;

-- 4. guardar a indicação
SELECT captacao_indicacao_guardar(:'tel', '', '', '') AS g0 \gset
SELECT captacao_indicacao_guardar(:'tel', 'João da Silva', '', 'vende uma casa no Tarumã') AS g1 \gset
SELECT captacao_indicacao_guardar(:'tel', 'Maria Souza', '(92) 99999-0000', '') AS g2 \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'indicação: vazia recusa, sem telefone pede o telefone, completa grava', 'true/true/true/2',
       (:'g0' LIKE 'Nao gravei%') || '/' || (:'g1' LIKE '%SEM telefone%') || '/' || (:'g2' LIKE 'Indicacao gravada%') || '/' ||
       (SELECT count(*) FROM privado.captacao_indicacao WHERE lead_id = 835);

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_315: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
