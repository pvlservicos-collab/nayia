-- 401: depois de atualizar, as listas (o placar da tela) e quantas chaves entraram por saída nossa
SELECT count(*) AS chaves, count(*) FILTER (WHERE ultima_em > now() - interval '60 days') AS em_60_dias,
       count(*) FILTER (WHERE ultima_em > now() - interval '60 days'
                          AND NOT origens && ARRAY['parceria', 'captacao', 'nay', 'corretores', 'crm']) AS so_por_saida_nossa
  FROM privado.falou_conosco;
SELECT n, nome, total, disparados, falaram FROM site_publicos_disparo();
SELECT count(*) AS fila_do_disparo FROM captacao_py_fila_do_disparo();
