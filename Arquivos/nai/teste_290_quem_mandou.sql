-- Testes da 290 (crm_quem_mandou): roda dentro do ensaio, depois da migração, antes do ROLLBACK.
\echo '== 1. as enviadas de 3 dias pelo número da Parceria, por origem'
SELECT q.origem, count(*) AS n
  FROM crm_quem_mandou(ARRAY(SELECT m.message_id FROM mensagens m
                              WHERE m.direcao = 'enviada' AND m.message_id IS NOT NULL
                                AND m.telefone NOT LIKE '%group%' AND m.criada_em > now() - interval '3 days')) q
 GROUP BY 1 ORDER BY 2 DESC;

\echo '== 2. a Leticia (fone 2295 e lid 3646): CRM das 19h = gente, celular das 16:54 e 20:36 = gente'
SELECT to_char(m.criada_em, 'DD/MM HH24:MI') AS hora, left(regexp_replace(coalesce(m.texto, ''), '\s+', ' ', 'g'), 30) AS texto, q.origem
  FROM mensagens m
  JOIN crm_quem_mandou(ARRAY(SELECT m2.message_id FROM mensagens m2
                              WHERE m2.direcao = 'enviada' AND m2.message_id IS NOT NULL
                                AND (right(m2.telefone, 4) = '2295' OR m2.telefone LIKE '%3646%')
                                AND m2.criada_em > now() - interval '3 days')) q ON q.message_id = m.message_id
 ORDER BY m.criada_em;

\echo '== 3. amostra do que vira "gente" (deve parecer gente digitando, não a Nay)'
SELECT to_char(m.criada_em, 'DD/MM HH24:MI') AS hora, left(regexp_replace(coalesce(nullif(m.texto, ''), '[mídia]'), '\s+', ' ', 'g'), 45) AS texto
  FROM mensagens m
  JOIN crm_quem_mandou(ARRAY(SELECT m2.message_id FROM mensagens m2
                              WHERE m2.direcao = 'enviada' AND m2.message_id IS NOT NULL
                                AND m2.telefone NOT LIKE '%group%' AND m2.criada_em > now() - interval '1 day')) q
    ON q.message_id = m.message_id AND q.origem = 'gente'
 ORDER BY random() LIMIT 15;

\echo '== 4. a Nay nova é reconhecida (core_saida com id, último dia)'
SELECT count(*) FILTER (WHERE q.origem = 'nay') AS nay, count(*) AS total
  FROM crm_quem_mandou(ARRAY(SELECT s.message_id FROM core_saida s WHERE s.message_id IS NOT NULL
                              AND s.criado_em > now() - interval '1 day')) q;

\echo '== 5. vazio, nulo e repetido não quebram'
SELECT count(*) AS deve_ser_0 FROM crm_quem_mandou(ARRAY[]::text[]);
SELECT count(*) AS deve_ser_1 FROM crm_quem_mandou(ARRAY['x-nao-existe', 'x-nao-existe', NULL, '']);

\echo '== 6. o papel do CRM pode chamar'
SELECT has_function_privilege('nay_disparo', 'public.crm_quem_mandou(text[])', 'EXECUTE') AS crm_pode;

\echo '== 7. quanto custa (300 ids)'
EXPLAIN (ANALYZE, TIMING ON, COSTS OFF, SUMMARY ON)
SELECT * FROM crm_quem_mandou(ARRAY(SELECT m.message_id FROM mensagens m WHERE m.direcao = 'enviada' AND m.message_id IS NOT NULL
                                     ORDER BY m.id DESC LIMIT 300));
