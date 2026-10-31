-- 550: as guardas. Nada aqui chama o corpo que manda mensagem com a chave no dono certo (o ensaio é um ROLLBACK,
-- mas a liberação marca linhas e a agenda mexe em visitas: melhor nem chamar).
SELECT 'chaves nascem em n8n' AS caso,
       nai_cfg('entrada', '?') AS entrada, nai_cfg('agenda_de', '?') AS agenda_de,
       (SELECT valor FROM captacao_config WHERE chave = 'entrada') AS cap_entrada,
       (SELECT valor FROM captacao_config WHERE chave = 'rotinas_de') AS cap_rotinas;
SELECT 'agenda: o python não roda enquanto é do n8n' AS caso, nai_agenda_tick('python') AS n;   -- 0
SELECT 'o vigia: o python não roda enquanto é do n8n' AS caso, captacao_vigiar('python') IS NULL AS ok;
SELECT 'o relatório: o python não recebe nada enquanto é do n8n' AS caso, count(*) = 0 AS ok FROM captacao_relatorio_da_vez('python');

UPDATE nai_config SET valor = 'python' WHERE chave = 'agenda_de';
SELECT 'agenda do python: o n8n não roda' AS caso, nai_agenda_tick() AS n;                       -- 0
SELECT 'agenda do python: o n8n não libera o que a Nay inicia' AS caso, count(*) AS linhas FROM nai_liberar_saida(NULL::bigint);   -- 0

UPDATE nai_config SET valor = 'python' WHERE chave = 'entrada';
SELECT 'entrada python: o n8n não libera o turno' AS caso, count(*) AS linhas
  FROM nai_liberar_saida((SELECT max(id) FROM nai_turno));                                        -- 0

UPDATE captacao_config SET valor = 'python' WHERE chave = 'rotinas_de';
SELECT 'rotinas do python: o vigia do n8n não roda' AS caso, captacao_vigiar() IS NULL AS ok;
SELECT 'rotinas do python: o relatório do n8n não sai' AS caso, count(*) = 0 AS ok FROM captacao_relatorio_da_vez();
SELECT 'rotinas do python: o python roda (pausada = sim -> NULL, como antes)' AS caso, captacao_vigiar('python') AS motivo;

SELECT 'os corpos continuam lá' AS caso, p.oid::regprocedure FROM pg_proc p
 WHERE p.proname IN ('nai_agenda_tick_rodar', 'captacao_vigiar_rodar', 'captacao_relatorio_da_vez_rodar',
                     'nai_agenda_tick', 'captacao_vigiar', 'captacao_relatorio_da_vez') ORDER BY 2::text;
