-- Testes da 319 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

INSERT INTO _t
SELECT 'conversa do número oficial não vai ao espelho da Z-API', '0',
       (SELECT count(*)::text FROM crm_captacao_mensagens(now() - interval '3 days', now(), 5000) c
          JOIN captacao_mensagens m ON m.id = c.id
          LEFT JOIN captacao_leads l ON l.id = m.lead_id
         WHERE l.canal = 'oficial' OR m.message_id LIKE 'wamid.%');

INSERT INTO _t
SELECT 'o teste do Pedro de hoje (oficial) ficou de fora', '0',
       (SELECT count(*)::text FROM crm_captacao_mensagens(now() - interval '3 hours', now(), 5000) c
         WHERE right(c.telefone, 8) = right((SELECT regexp_replace(valor, '\D', '', 'g') FROM captacao_config
                                              WHERE chave = 'telefone_teste'), 8));

INSERT INTO _t
SELECT 'quem conversa pela Z-API continua inteiro',
       (SELECT count(*)::text FROM captacao_mensagens m LEFT JOIN captacao_leads l ON l.id = m.lead_id
         WHERE m.criada_em >= now() - interval '3 days' AND m.criada_em < now()
           AND coalesce(m.telefone, '') !~ '-'
           AND length(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 16
           AND coalesce(l.canal, 'zapi') <> 'oficial' AND coalesce(m.message_id, '') NOT LIKE 'wamid.%'),
       (SELECT count(*)::text FROM crm_captacao_mensagens(now() - interval '3 days', now(), 5000));

INSERT INTO _t
SELECT 'ainda há conversa da Z-API no espelho (a função não ficou vazia)', 'sim',
       CASE WHEN (SELECT count(*) FROM crm_captacao_mensagens(now() - interval '3 days', now(), 5000)) > 0 THEN 'sim' ELSE 'não' END;

SELECT caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r FROM _t;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _t WHERE esperado IS DISTINCT FROM veio;
  IF n > 0 THEN RAISE EXCEPTION '319: % teste(s) falharam', n; END IF;
END $$;
