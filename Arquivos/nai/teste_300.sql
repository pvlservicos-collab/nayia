SELECT nai_cfg('pausada','?') AS nay_pausada;
SELECT estado, bloqueio, papel_destino, count(*) FROM nai_saida
 WHERE criado_em > now() - interval '3 hours' AND papel_destino = 'entrega' GROUP BY 1,2,3 ORDER BY 4 DESC;
SELECT prosrc LIKE '%r.papel_destino <> ''entrega''%' AS gate_novo FROM pg_proc WHERE proname = 'nai_liberar_saida';
