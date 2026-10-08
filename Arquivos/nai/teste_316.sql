-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;
SELECT telefone AS tel FROM captacao_leads WHERE id = 835 \gset
SELECT captacao_indicacao_guardar(:'tel', 'Carlos', '', 'cunhado, vende uma casa no Tarumã') AS g1 \gset
SELECT captacao_indicacao_guardar(:'tel', 'Carlos', '92 99999-0000', 'casa no Tarumã') AS g2 \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'nome e depois telefone: UMA linha, completa', 'true/true/1/Carlos/92 99999-0000/cunhado, vende uma casa no Tarumã',
       (:'g1' LIKE '%SEM telefone%') || '/' || (:'g2' LIKE 'Indicacao gravada%') || '/' || count(*) || '/' || max(nome) || '/' || max(contato) || '/' || max(detalhe)
  FROM privado.captacao_indicacao WHERE lead_id = 835;
SELECT captacao_indicacao_guardar(:'tel', 'Maria', '(92) 98888-7777', '') AS g3 \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'outra pessoa, já com telefone: linha nova', 'true/2', (:'g3' LIKE 'Indicacao gravada%') || '/' || count(*) FROM privado.captacao_indicacao WHERE lead_id = 835;
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN RAISE EXCEPTION 'teste_316 falhou'; END IF;
END $$;
